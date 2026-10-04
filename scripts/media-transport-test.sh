#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "config.env não existe: ${CONFIG_FILE}"
  exit 1
fi

set -a
source "${CONFIG_FILE}"
set +a

TEST_PORT="${MEDIA_TEST_PORT:-3191}"
FUNNEL_PORT="${MEDIA_TEST_FUNNEL_PORT:-8443}"
SIZE_MB="${1:-101}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

for cmd in tailscale jq python3 curl truncate ss; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Comando ausente: ${cmd}. Execute: bluesky media install"
    exit 1
  fi
done

if ! [[ "${SIZE_MB}" =~ ^[0-9]+$ ]] || (( SIZE_MB < 1 )); then
  echo "Tamanho inválido: ${SIZE_MB} MB"
  exit 1
fi

if [[ "${FUNNEL_PORT}" != "8443" && "${FUNNEL_PORT}" != "10000" ]]; then
  echo "MEDIA_TEST_FUNNEL_PORT deve ser 8443 ou 10000."
  exit 1
fi

if "${SUDO}" ss -ltnH "sport = :${TEST_PORT}" 2>/dev/null | grep -q .; then
  echo "ERRO: porta local de teste ${TEST_PORT} já está em uso."
  exit 1
fi

if "${SUDO}" tailscale funnel status 2>/dev/null | grep -q ":${FUNNEL_PORT}"; then
  echo "ERRO: o Funnel já usa a porta ${FUNNEL_PORT} neste nó."
  exit 1
fi

DNS_NAME="$("${SUDO}" tailscale status --json | jq -r ".Self.DNSName // empty" | sed "s/\\.$//")"
if [[ -z "${DNS_NAME}" ]]; then
  echo "Tailscale não está autenticado. Execute: sudo tailscale up"
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/espelunca-media-test.XXXXXX)"
SERVER_SCRIPT="${WORK_DIR}/server.py"
FILE="${WORK_DIR}/payload.bin"
RESULT="${WORK_DIR}/result.json"
LOG="${WORK_DIR}/server.log"
SERVER_PID=""

cleanup() {
  set +e
  if [[ -n "${SERVER_PID}" ]]; then
    kill "${SERVER_PID}" 2>/dev/null || true
  fi
  "${SUDO}" tailscale funnel --https="${FUNNEL_PORT}" off >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cat > "${SERVER_SCRIPT}" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib
import json
import os

port = int(os.environ["TEST_PORT"])
result_path = os.environ["RESULT_PATH"]
server_log = os.environ["SERVER_LOG"]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = self.headers.get("Content-Length")
        if length is None:
            self.send_response(411)
            self.end_headers()
            return

        remaining = int(length)
        total = 0
        digest = hashlib.sha256()

        while remaining > 0:
            chunk = self.rfile.read(min(1024 * 1024, remaining))
            if not chunk:
                raise RuntimeError(f"EOF inesperado após {total} bytes de {length}")
            total += len(chunk)
            remaining -= len(chunk)
            digest.update(chunk)

        payload = {"bytes": total, "sha256": digest.hexdigest()}
        with open(result_path, "w", encoding="utf-8") as fp:
            json.dump(payload, fp)

        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ready")

    def log_message(self, fmt, *args):
        with open(server_log, "a", encoding="utf-8") as fp:
            fp.write((fmt % args) + "\n")

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

export TEST_PORT RESULT_PATH="${RESULT}" SERVER_LOG="${LOG}"
python3 "${SERVER_SCRIPT}" >/dev/null 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 50); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${TEST_PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! curl -fsS --max-time 2 "http://127.0.0.1:${TEST_PORT}/" >/dev/null; then
  echo "ERRO: servidor de teste não iniciou."
  cat "${LOG}" 2>/dev/null || true
  exit 1
fi

echo "==> Criando arquivo esparso de ${SIZE_MB} MB (decimal)"
truncate -s "$((SIZE_MB * 1000 * 1000))" "${FILE}"

echo "==> Ativando Funnel temporário em HTTPS ${FUNNEL_PORT}"
"${SUDO}" tailscale funnel --bg --https="${FUNNEL_PORT}" "http://127.0.0.1:${TEST_PORT}"

URL="https://${DNS_NAME}:${FUNNEL_PORT}/upload-test"
echo "==> Enviando ${SIZE_MB} MB para ${URL}"

START_NS="$(date +%s%N)"
HTTP_CODE="$(
  curl -sS --fail-with-body -o "${WORK_DIR}/response.json" -w "%{http_code}" \
    --data-binary "@${FILE}" "${URL}"
)"
END_NS="$(date +%s%N)"
ELAPSED_NS=$((END_NS - START_NS))
ELAPSED_SEC="$(awk -v ns="${ELAPSED_NS}" 'BEGIN {printf "%.2f", ns/1000000000}')"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "ERRO: HTTP ${HTTP_CODE}"
  cat "${WORK_DIR}/response.json" 2>/dev/null || true
  exit 1
fi

EXPECTED=$((SIZE_MB * 1000 * 1000))
RECEIVED="$(jq -r ".bytes // 0" "${RESULT}")"

if [[ "${RECEIVED}" != "${EXPECTED}" ]]; then
  echo "ERRO: servidor recebeu ${RECEIVED} bytes; esperado ${EXPECTED}."
  exit 1
fi

echo
echo "TESTE DE TRANSPORTE: OK"
echo "Bytes enviados:  ${EXPECTED}"
echo "Bytes recebidos: ${RECEIVED}"
echo "Tempo:            ${ELAPSED_SEC}s"
echo "Endpoint:         ${URL}"
echo
echo "Este teste comprova somente o transporte do corpo pelo Funnel."
echo "Ele não altera DID/PLC e não configura video.bsky.app."

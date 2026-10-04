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
EXPECTED="$((SIZE_MB * 1000 * 1000))"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

for cmd in tailscale jq python3 curl ss; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Comando ausente: ${cmd}. Execute: bluesky media install"
    exit 1
  fi
done

if ! [[ "${SIZE_MB}" =~ ^[0-9]+$ ]] || (( SIZE_MB < 1 )); then
  echo "Tamanho inválido: ${SIZE_MB} MB"
  exit 1
fi

DNS_NAME="$("${SUDO}" tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
if [[ -z "${DNS_NAME}" ]]; then
  echo "Tailscale não está autenticado. Execute: sudo tailscale up"
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/espelunca-media-external.XXXXXX)"
SERVER_SCRIPT="${WORK_DIR}/server.py"
RESULT="${WORK_DIR}/result.json"
LOG="${WORK_DIR}/server.log"
SERVER_PID=""

cleanup() {
  set +e
  if [[ -n "${SERVER_PID}" ]]; then kill "${SERVER_PID}" 2>/dev/null || true; fi
  "${SUDO}" tailscale funnel --https="${FUNNEL_PORT}" off >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT INT TERM

cat > "${SERVER_SCRIPT}" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os

port = int(os.environ["TEST_PORT"])
expected = int(os.environ["EXPECTED"])
result_path = os.environ["RESULT_PATH"]
server_log = os.environ["SERVER_LOG"]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = (
            "Espelunca media transport test\n\n"
            f"Expected upload: {expected} bytes\n"
            "Use POST /upload-test from a DIFFERENT Internet connection.\n"
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/upload-test":
            self.send_response(404)
            self.end_headers()
            return
        length = self.headers.get("Content-Length")
        if length is None:
            self.send_response(411)
            self.end_headers()
            return
        content_length = int(length)
        received = 0
        while received < content_length:
            chunk = self.rfile.read(min(4 * 1024 * 1024, content_length - received))
            if not chunk:
                break
            received += len(chunk)
        payload = {
            "received": received,
            "content_length": content_length,
            "expected": expected,
            "ok": received == expected == content_length,
        }
        with open(result_path, "w", encoding="utf-8") as fp:
            json.dump(payload, fp)
        body = json.dumps(payload).encode()
        self.send_response(200 if payload["ok"] else 400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        with open(server_log, "a", encoding="utf-8") as fp:
            fp.write((fmt % args) + "\n")

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

export TEST_PORT EXPECTED RESULT_PATH="${RESULT}" SERVER_LOG="${LOG}"
python3 "${SERVER_SCRIPT}" >/dev/null 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 50); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${TEST_PORT}/" >/dev/null 2>&1; then break; fi
  sleep 0.1
done

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "ERRO: servidor de teste não iniciou."
  exit 1
fi

echo "==> Ativando Funnel temporário em HTTPS ${FUNNEL_PORT}"
"${SUDO}" tailscale funnel --bg --https="${FUNNEL_PORT}" "http://127.0.0.1:${TEST_PORT}"

URL="https://${DNS_NAME}:${FUNNEL_PORT}/upload-test"
echo
echo "TESTE EXTERNO — execute o upload a partir de OUTRA máquina/rede."
echo
echo "Tamanho esperado: ${EXPECTED} bytes (${SIZE_MB} MB)"
echo "URL: ${URL}"
echo
echo "Exemplo em outro computador:"
echo "  curl --data-binary \"@ARQUIVO\" \"${URL}\""
echo
echo "Não use esta mesma máquina para o upload."
echo "Ctrl+C cancela e desativa o Funnel temporário."
echo

while true; do
  if [[ -f "${RESULT}" ]]; then
    RECEIVED="$(jq -r '.received // 0' "${RESULT}")"
    CONTENT_LENGTH="$(jq -r '.content_length // 0' "${RESULT}")"
    OK="$(jq -r '.ok // false' "${RESULT}")"
    echo
    if [[ "${OK}" == "true" ]]; then
      echo "TESTE EXTERNO DE TRANSPORTE: OK"
      echo "Bytes esperados: ${EXPECTED}"
      echo "Bytes recebidos: ${RECEIVED}"
      echo "Content-Length:   ${CONTENT_LENGTH}"
      break
    fi
    echo "Upload recebido com tamanho incorreto: ${RECEIVED}/${EXPECTED} bytes."
    exit 1
  fi
  sleep 1
done

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
SIZE_ARG="${1:-101}"
MIN_MB="${2:-100}"

if [[ "$SIZE_ARG" == "auto" ]]; then
  if ! [[ "$MIN_MB" =~ ^[0-9]+$ ]] || (( MIN_MB < 1 )); then
    echo "Mínimo inválido: ${MIN_MB} MB"
    exit 1
  fi
  EXPECTED=0
  MIN_BYTES="$((MIN_MB * 1000 * 1000))"
else
  if ! [[ "$SIZE_ARG" =~ ^[0-9]+$ ]] || (( SIZE_ARG < 1 )); then
    echo "Tamanho inválido: ${SIZE_ARG} MB"
    exit 1
  fi
  EXPECTED="$((SIZE_ARG * 1000 * 1000))"
  MIN_BYTES="${EXPECTED}"
fi

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

for cmd in tailscale jq python3 curl ss; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Comando ausente: ${cmd}. Execute: bluesky media install"
    exit 1
  fi
done

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
minimum_bytes = int(os.environ["MIN_BYTES"])
result_path = os.environ["RESULT_PATH"]
server_log = os.environ["SERVER_LOG"]

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def handle_expect_100(self):
        self.send_response_only(100)
        self.end_headers()
        return True
    def do_GET(self):
        if self.path != "/":
            self.send_response(404)
            self.end_headers()
            return

        if expected:
            target = f"Expected exact upload: {expected} bytes"
        else:
            target = f"Expected minimum upload: {minimum_bytes} bytes"

        html = f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Espelunca media transport test</title>
</head>
<body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:760px;margin:40px auto;padding:0 16px">
<h1>Espelunca media transport test</h1>
<p>{target}</p>
<p>Esta página envia o arquivo diretamente por POST a partir desta conexão.</p>
<input id="file" type="file">
<br><br>
<button id="send" type="button">Enviar arquivo</button>
<pre id="out" style="white-space:pre-wrap"></pre>
<script>
const fileInput = document.getElementById('file');
const button = document.getElementById('send');
const out = document.getElementById('out');

button.addEventListener('click', () => {{
  const file = fileInput.files && fileInput.files[0];
  if (!file) {{
    out.textContent = 'Selecione um arquivo primeiro.';
    return;
  }}

  button.disabled = true;
  out.textContent = 'Enviando ' + file.size.toLocaleString('pt-BR') + ' bytes...\\n';

  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/upload-test', true);
  xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream');

  xhr.upload.onprogress = (event) => {{
    if (event.lengthComputable) {{
      const pct = ((event.loaded / event.total) * 100).toFixed(1);
      out.textContent = 'Enviando: ' + pct + '%\\n'
        + event.loaded.toLocaleString('pt-BR') + ' / '
        + event.total.toLocaleString('pt-BR') + ' bytes';
    }} else {{
      out.textContent = 'Enviando: ' + event.loaded.toLocaleString('pt-BR') + ' bytes';
    }}
  }};

  xhr.onload = () => {{
    out.textContent = 'HTTP ' + xhr.status + '\\n' + xhr.responseText;
    button.disabled = false;
  }};

  xhr.onerror = () => {{
    out.textContent = 'Falha de rede durante o POST.';
    button.disabled = false;
  }};

  xhr.send(file);
}});
</script>
</body>
</html>"""

        body = html.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/upload-test":
            self.send_response(404)
            self.end_headers()
            return
        length = self.headers.get("Content-Length")
        transfer_encoding = (self.headers.get("Transfer-Encoding") or "").lower()
        expect_header = self.headers.get("Expect") or ""

        received = 0
        if "chunked" in transfer_encoding:
            while True:
                line = self.rfile.readline()
                if not line:
                    break
                size_text = line.strip().split(b";", 1)[0]
                try:
                    chunk_size = int(size_text, 16)
                except ValueError:
                    chunk_size = 0
                if chunk_size == 0:
                    while True:
                        trailer = self.rfile.readline()
                        if not trailer or trailer in (b"\r\n", b"\n"):
                            break
                    break
                remaining = chunk_size
                while remaining:
                    chunk = self.rfile.read(min(4 * 1024 * 1024, remaining))
                    if not chunk:
                        remaining = 0
                        break
                    received += len(chunk)
                    remaining -= len(chunk)
                self.rfile.read(2)
            content_length = int(length) if length is not None else received
        elif length is not None:
            content_length = int(length)
            while received < content_length:
                chunk = self.rfile.read(min(4 * 1024 * 1024, content_length - received))
                if not chunk:
                    break
                received += len(chunk)
        else:
            self.send_response(411)
            self.end_headers()
            return

        size_ok = received == content_length and received >= minimum_bytes
        if expected:
            size_ok = size_ok and received == expected == content_length

        payload = {
            "received": received,
            "content_length": content_length,
            "expected": expected,
            "minimum_bytes": minimum_bytes,
            "transfer_encoding": transfer_encoding,
            "expect": expect_header,
            "ok": size_ok,
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

export TEST_PORT EXPECTED MIN_BYTES="${MIN_BYTES}" RESULT_PATH="${RESULT}" SERVER_LOG="${LOG}"
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
if [[ "$SIZE_ARG" == "auto" ]]; then
  echo "Modo: tamanho automático"
  echo "Mínimo esperado: ${MIN_BYTES} bytes (${MIN_MB} MB)"
else
  echo "Tamanho esperado: ${EXPECTED} bytes (${SIZE_ARG} MB)"
fi
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
    echo "Upload recebido com tamanho incorreto: ${RECEIVED}/${CONTENT_LENGTH} bytes no Content-Length."
    if [[ "$SIZE_ARG" == "auto" ]]; then
      echo "Mínimo configurado: ${MIN_BYTES} bytes."
    else
      echo "Esperado exatamente: ${EXPECTED} bytes."
    fi
    exit 1
  fi
  sleep 1
done

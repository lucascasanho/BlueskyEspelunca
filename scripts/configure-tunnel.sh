#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${CLOUDFLARED_CONFIG:?CLOUDFLARED_CONFIG não definido}"
: "${CLOUDFLARED_SERVICE:?CLOUDFLARED_SERVICE não definido}"
: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${PDS_PORT:?PDS_PORT não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

if [[ "$(id -u)" -ne 0 ]]; then SUDO=sudo; else SUDO=; fi

if [[ ! -f "${CLOUDFLARED_CONFIG}" ]]; then
  echo "Configuração do cloudflared não encontrada: ${CLOUDFLARED_CONFIG}"
  exit 1
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared não está instalado ou não está no PATH."
  exit 1
fi

BACKUP="${CLOUDFLARED_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
${SUDO} cp "${CLOUDFLARED_CONFIG}" "${BACKUP}"

python3 - "${CLOUDFLARED_CONFIG}" "${PDS_HOSTNAME}" "${PDS_PORT}" "${WEB_PORT}" "${OZONE_TUNNEL_ENABLED:-false}" "${OZONE_HOSTNAME:-}" "${OZONE_PORT:-3300}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
pds_host, pds_port, web_port, ozone_enabled, ozone_host, ozone_port = sys.argv[2:]
text = path.read_text()

if "ingress:" not in text:
    raise SystemExit("O arquivo não contém ingress:. O backup foi criado e nenhuma alteração foi feita.")

lines = text.splitlines()
start = next(i for i, line in enumerate(lines) if line.strip() == "ingress:")
prefix = lines[:start + 1]
existing = lines[start + 1:]
managed = {pds_host, "*." + pds_host}
if ozone_enabled == "true" and ozone_host:
    managed.add(ozone_host)
filtered = []
i = 0

while i < len(existing):
    line = existing[i]
    if line.startswith("  - hostname:"):
        host = line.split(":", 1)[1].strip().strip('"').strip("'")
        if host in managed:
            i += 1
            while i < len(existing) and not existing[i].startswith("  - "):
                i += 1
            continue
    filtered.append(line)
    i += 1

catch = []
for j, line in enumerate(filtered):
    if line.startswith("  - service: http_status:404"):
        catch = filtered[j:]
        filtered = filtered[:j]
        break

rules = [
    "  - hostname: {}".format(pds_host),
    "    path: ^/xrpc/.*",
    "    service: http://127.0.0.1:{}".format(pds_port),
    "  - hostname: {}".format(pds_host),
    "    path: ^/\\.well-known/.*",
    "    service: http://127.0.0.1:{}".format(pds_port),
    "  - hostname: {}".format(pds_host),
    "    path: ^/oauth/.*",
    "    service: http://127.0.0.1:{}".format(pds_port),
    "  - hostname: {}".format(pds_host),
    "    path: ^/oauth-client-metadata\\.json$",
    "    service: http://127.0.0.1:{}".format(pds_port),
    "  - hostname: {}".format(pds_host),
    "    service: http://127.0.0.1:{}".format(web_port),
]
if ozone_enabled == "true" and ozone_host:
    rules.extend([
        "  - hostname: {}".format(ozone_host),
        "    service: http://127.0.0.1:{}".format(ozone_port),
    ])
rules.extend([
    "  - hostname: \"*.{}\"" .format(pds_host),
    "    service: http://127.0.0.1:{}".format(pds_port),
])

path.write_text("\n".join(prefix + rules + filtered + catch) + "\n")
PY

echo "==> Validando configuração do Tunnel"
cloudflared tunnel ingress validate --config "${CLOUDFLARED_CONFIG}"

echo "==> Reiniciando ${CLOUDFLARED_SERVICE}"
${SUDO} systemctl restart "${CLOUDFLARED_SERVICE}"

echo
echo "Tunnel atualizado."
echo "Backup: ${BACKUP}"
echo
echo "Rotas:"
echo "  https://${PDS_HOSTNAME}/xrpc/* -> http://127.0.0.1:${PDS_PORT}"
echo "  https://${PDS_HOSTNAME}/.well-known/* -> http://127.0.0.1:${PDS_PORT}"
echo "  https://${PDS_HOSTNAME}/oauth/* -> http://127.0.0.1:${PDS_PORT}"
echo "  https://${PDS_HOSTNAME}/oauth-client-metadata.json -> http://127.0.0.1:${PDS_PORT}"
echo "  https://${PDS_HOSTNAME}/* -> http://127.0.0.1:${WEB_PORT}"
if [[ "${OZONE_TUNNEL_ENABLED:-false}" == "true" ]]; then
  echo "  https://${OZONE_HOSTNAME}/* -> http://127.0.0.1:${OZONE_PORT}"
fi
echo "  https://*.${PDS_HOSTNAME} -> http://127.0.0.1:${PDS_PORT}"
echo
echo "Os registros DNS precisam existir no Cloudflare."
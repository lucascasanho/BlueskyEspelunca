#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "config.env não existe."
  echo "Execute: cp config.env.example config.env"
  exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

SCRIPT_DIR="${ROOT_DIR}/scripts"

chmod +x "${SCRIPT_DIR}"/*.sh

"${SCRIPT_DIR}/install-pds.sh"
"${SCRIPT_DIR}/install-web.sh"

echo
echo "============================================================"
echo " BLUESKY ESPelunca — INSTALAÇÃO CONCLUÍDA"
echo "============================================================"
echo
echo "PDS: https://${PDS_HOSTNAME}"
echo "Web: https://${APP_HOSTNAME}"
echo
echo "Verifique:"
echo "  ${SCRIPT_DIR}/status.sh"
echo
echo "Se a máquina estiver atrás do Cloudflare Tunnel, configure:"
echo "  ${PDS_HOSTNAME}     -> https://127.0.0.1:443"
echo "  *.${PDS_HOSTNAME}   -> https://127.0.0.1:443"
echo "  ${APP_HOSTNAME}     -> http://127.0.0.1:${WEB_PORT}"

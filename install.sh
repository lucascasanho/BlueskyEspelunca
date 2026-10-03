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
set -a
source "${CONFIG_FILE}"
set +a

SCRIPT_DIR="${ROOT_DIR}/scripts"

chmod +x "${SCRIPT_DIR}"/*.sh

echo "============================================================"
echo " BLUESKY ESPELUNCA — INSTALAÇÃO"
echo "============================================================"
echo
echo "PDS: https://${PDS_HOSTNAME}"
echo "Site/Web: https://${PDS_HOSTNAME}"
echo "PDS local: ${PDS_PORT}"
echo "Web local: ${WEB_PORT}"
echo

"${SCRIPT_DIR}/install-pds.sh"
"${SCRIPT_DIR}/install-web.sh"

echo
echo "============================================================"
echo " BLUESKY ESPELUNCA — INSTALAÇÃO CONCLUÍDA"
echo "============================================================"
echo
echo "PDS local: http://127.0.0.1:${PDS_PORT}"
echo "Web local: http://127.0.0.1:${WEB_PORT}"
echo
echo "Próximo passo:"
echo "  ${SCRIPT_DIR}/status.sh"
echo
echo "Depois de validar os serviços, configure o Cloudflare Tunnel:"
echo "  ${SCRIPT_DIR}/configure-tunnel.sh"
echo
echo "DNS:"
echo "  ${PDS_HOSTNAME}       -> Tunnel existente"
echo "  *.${PDS_HOSTNAME}     -> Tunnel existente"

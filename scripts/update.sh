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

PDS_ENV_FILE="${PDS_DATA_DIR}/pds.env"

set_pds_env() {
  local key="$1"
  local value="$2"
  sudo sed -i "/^${key}=.*/d" "${PDS_ENV_FILE}"
  printf '%s=%s\n' "${key}" "${value}" | sudo tee -a "${PDS_ENV_FILE}" >/dev/null
}

if [[ -f "${PDS_ENV_FILE}" ]]; then
  echo "==> Aplicando branding da Espelunca ao PDS"
  set_pds_env "PDS_SERVICE_NAME" "Espelunca"
  set_pds_env "PDS_HOME_URL" "https://${PDS_HOSTNAME}"
  set_pds_env "PDS_LOGO_URL" "https://${PDS_HOSTNAME}/espelunca-icon.svg"
  set_pds_env "PDS_PRIMARY_COLOR" "#006AFF"
  set_pds_env "PDS_EMAIL_DISABLE_CONFIRMATION_LINK" "true"
  set_pds_env "PDS_INVITE_REQUIRED" "false"
fi

echo "==> Atualizando PDS source"
if [[ -d "${INSTALL_DIR}/pds-src/.git" ]]; then
  git -C "${INSTALL_DIR}/pds-src" fetch --tags --prune
  git -C "${INSTALL_DIR}/pds-src" pull --ff-only
fi

echo "==> Atualizando imagem do PDS"
sudo docker compose --file "${PDS_DATA_DIR}/compose.yaml" pull pds
sudo systemctl restart espelunca-pds

echo "==> Atualizando social-app e serviço Web"
"${ROOT_DIR}/scripts/install-web.sh"

echo
echo "Atualização concluída."

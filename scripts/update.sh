#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

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

#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${APP_DIR:?APP_DIR não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

cd "${APP_DIR}"
pnpm build-web
"${ROOT_DIR}/scripts/apply-social-app-customizations.sh"
sudo systemctl restart espelunca-bluesky-web.service
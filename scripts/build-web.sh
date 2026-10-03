#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${APP_DIR:?APP_DIR não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

cd "${APP_DIR}"
"${ROOT_DIR}/scripts/apply-social-app-customizations.sh"
pnpm build-web
mkdir -p dist/static
ln -sfn ../_expo dist/static/_expo
sudo systemctl restart espelunca-bluesky-web.service
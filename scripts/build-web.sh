#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
cd "${APP_DIR}"
pnpm build-web
sudo systemctl restart espelunca-web

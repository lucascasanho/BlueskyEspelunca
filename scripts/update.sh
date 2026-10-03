#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

echo "==> Atualizando PDS source"
if [[ -d "${INSTALL_DIR}/pds-src/.git" ]]; then
  git -C "${INSTALL_DIR}/pds-src" fetch --tags --prune
  git -C "${INSTALL_DIR}/pds-src" pull --ff-only
fi

echo "==> Atualizando imagem/compose do PDS"
curl -fsSL https://raw.githubusercontent.com/bluesky-social/pds/main/compose.yaml |
  sed "s|/pds|${PDS_DATA_DIR}|g" |
  sudo tee "${PDS_DATA_DIR}/compose.yaml" >/dev/null

sudo systemctl restart espelunca-pds

echo "==> Atualizando social-app"
git -C "${APP_DIR}" fetch --prune origin
git -C "${APP_DIR}" reset --hard origin/main

cd "${APP_DIR}"
pnpm install --frozen-lockfile

# Reaplica a configuração local caso o upstream tenha alterado os valores.
python3 - "${PDS_HOSTNAME}" "${APP_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

pds, host = sys.argv[1], sys.argv[2]

path = Path("src/lib/constants.ts")
text = path.read_text()
text = text.replace("export const BSKY_SERVICE = 'https://bsky.social'", f"export const BSKY_SERVICE = 'https://{pds}'")
text = text.replace("export const BSKY_SERVICE_DID = 'did:web:bsky.social'", f"export const BSKY_SERVICE_DID = 'did:web:{pds}'")
path.write_text(text)

path = Path("app.config.js")
text = path.read_text()
text = text.replace("name: 'Bluesky'", "name: 'Espelunca'")
text = text.replace("slug: 'bluesky'", "slug: 'espelunca'")
text = text.replace("scheme: 'bluesky'", "scheme: 'espelunca'")
text = text.replace("bundleIdentifier: 'xyz.blueskyweb.app'", "bundleIdentifier: 'blue.espelunca.app'")
text = text.replace("package: 'xyz.blueskyweb.app'", "package: 'blue.espelunca.app'")
text = text.replace("'applinks:bsky.app',", f"'applinks:{host}',")
text = text.replace("host: 'bsky.app',", f"host: '{host}',")
path.write_text(text)
PY

pnpm build-web
sudo systemctl restart espelunca-web

echo
echo "Atualização concluída."

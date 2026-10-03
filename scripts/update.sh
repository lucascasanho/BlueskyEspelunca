#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

echo "==> Atualizando PDS source"
if [[ -d "${INSTALL_DIR}/pds-src/.git" ]]; then
  git -C "${INSTALL_DIR}/pds-src" fetch --tags --prune
  git -C "${INSTALL_DIR}/pds-src" pull --ff-only
fi

echo "==> Atualizando compose/configuração do PDS"
sudo docker compose --file "${PDS_DATA_DIR}/compose.yaml" pull pds
sudo systemctl restart espelunca-pds

echo "==> Atualizando social-app"
git -C "${APP_DIR}" fetch --prune origin
git -C "${APP_DIR}" reset --hard origin/main

cd "${APP_DIR}"
pnpm install --frozen-lockfile

python3 - "${PDS_HOSTNAME}" "${APP_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

pds, host = sys.argv[1], sys.argv[2]

path = Path("src/lib/constants.ts")
text = path.read_text()
old_service = "export const BSKY_SERVICE = 'https://bsky.social'"
old_did = "export const BSKY_SERVICE_DID = 'did:web:bsky.social'"
if old_service not in text or old_did not in text:
    raise SystemExit("Não foi possível localizar os padrões atuais de BSKY_SERVICE no upstream.")
text = text.replace(old_service, f"export const BSKY_SERVICE = 'https://{pds}'")
text = text.replace(old_did, f"export const BSKY_SERVICE_DID = 'did:web:{pds}'")
path.write_text(text)

path = Path("app.config.js")
text = path.read_text()
replacements = {
    "name: 'Bluesky'": "name: 'Espelunca'",
    "slug: 'bluesky'": "slug: 'espelunca'",
    "scheme: 'bluesky'": "scheme: 'espelunca'",
    "bundleIdentifier: 'xyz.blueskyweb.app'": "bundleIdentifier: 'blue.espelunca.app'",
    "package: 'xyz.blueskyweb.app'": "package: 'blue.espelunca.app'",
    "'applinks:bsky.app',": f"'applinks:{host}',",
    "host: 'bsky.app',": f"host: '{host}',",
}
for old, new in replacements.items():
    text = text.replace(old, new)
path.write_text(text)
PY

SERVE_BIN="$(command -v serve || true)"
if [[ -z "${SERVE_BIN}" ]]; then
  echo "ERRO: 'serve' não encontrado. Execute: npm install --global serve"
  exit 1
fi

pnpm build-web
sudo systemctl restart espelunca-web

echo
echo "Atualização concluída."

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${APP_DIR:?APP_DIR não definido}"

cd "${APP_DIR}"

echo "==> Aplicando customizações versionadas do BlueskyEspelunca"

# Patches opcionais permitem que alterações maiores no social-app fiquem no GitHub
# sem copiar o repositório upstream inteiro para o BlueskyEspelunca.
PATCH_DIR="${ROOT_DIR}/patches/social-app"
if [[ -d "${PATCH_DIR}" ]]; then
  shopt -s nullglob
  patches=("${PATCH_DIR}"/*.patch)
  shopt -u nullglob
  for patch in "${patches[@]}"; do
    echo "==> Aplicando patch: $(basename "${patch}")"
    git apply --3way "${patch}"
  done
fi

python3 - "${PDS_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

pds = sys.argv[1]
path = Path("src/lib/constants.ts")
text = path.read_text()

old_service = "export const BSKY_SERVICE = 'https://bsky.social'"
old_did = "export const BSKY_SERVICE_DID = 'did:web:bsky.social'"

if old_service not in text or old_did not in text:
    raise SystemExit("Não foi possível localizar os padrões atuais de BSKY_SERVICE no upstream.")

text = text.replace(old_service, f"export const BSKY_SERVICE = 'https://{pds}'")
text = text.replace(old_did, f"export const BSKY_SERVICE_DID = 'did:web:{pds}'")
path.write_text(text)
PY

python3 - "${PDS_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

host = sys.argv[1]
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

echo "==> Customizações de código/configuração aplicadas."

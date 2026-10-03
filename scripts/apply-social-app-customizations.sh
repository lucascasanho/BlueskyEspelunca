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

desired_service = f"export const BSKY_SERVICE = 'https://{pds}'"
desired_did = f"export const BSKY_SERVICE_DID = 'did:web:{pds}'"
desired_default = "export const DEFAULT_SERVICE = BSKY_SERVICE"

# Keep this step idempotent: the upstream file may already contain our
# customization from a previous build.
if desired_service in text and desired_did in text and desired_default in text:
    path.write_text(text)
    raise SystemExit(0)

old_service = "export const BSKY_SERVICE = 'https://bsky.social'"
old_did = "export const BSKY_SERVICE_DID = 'did:web:bsky.social'"

if old_service not in text or old_did not in text or desired_default not in text:
    raise SystemExit("Não foi possível localizar os padrões de serviço padrão no upstream.")

text = text.replace(old_service, desired_service)
text = text.replace(old_did, desired_did)

if desired_service not in text:
    raise SystemExit("Falha ao configurar BSKY_SERVICE para o PDS da Espelunca.")
if desired_did not in text:
    raise SystemExit("Falha ao configurar BSKY_SERVICE_DID para o PDS da Espelunca.")
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

python3 - <<'PY'
from pathlib import Path

# Make the hosting-provider name match the Espelunca-branded PDS in the signup UI.
python3 <<'PY'
from pathlib import Path

path = Path("src/lib/strings/url-helpers.ts")
text = path.read_text()

old = """  if (\`https://\${urlp.host}\` === BSKY_SERVICE) {
      return 'Bluesky Social'
    }"""
new = """  if (\`https://\${urlp.host}\` === BSKY_SERVICE) {
      return urlp.host === 'espelunca.blue' ? 'Espelunca' : 'Bluesky Social'
    }"""

if old not in text:
    raise SystemExit("Não foi possível localizar o nome padrão do provedor no upstream.")

path.write_text(text.replace(old, new, 1))
PY

path = Path("src/state/persisted/schema.ts")
text = path.read_text()

old = "  darkTheme: 'dim',"
new = "  darkTheme: 'dark',"

if old not in text:
    raise SystemExit("Não foi possível localizar o tema escuro padrão no upstream.")

path.write_text(text.replace(old, new, 1))
PY

echo "==> Customizações de código/configuração aplicadas."

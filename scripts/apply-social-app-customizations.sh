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


python3 - "\${PDS_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

pds = sys.argv[1]
path = Path("src/lib/constants.ts")
text = path.read_text()

desired_service = f"export const BSKY_SERVICE = 'https://{pds}'"
desired_did = f"export const BSKY_SERVICE_DID = 'did:web:{pds}'"
desired_default = "export const DEFAULT_SERVICE = BSKY_SERVICE"

if desired_service in text and desired_did in text and desired_default in text:
    path.write_text(text)
    raise SystemExit(0)

old_service = "export const BSKY_SERVICE = 'https://bsky.social'"
old_did = "export const BSKY_SERVICE_DID = 'did:web:bsky.social'"

if old_service not in text or old_did not in text or desired_default not in text:
    raise SystemExit("Não foi possível localizar os padrões de serviço padrão no upstream.")

text = text.replace(old_service, desired_service, 1)
text = text.replace(old_did, desired_did, 1)

if desired_service not in text or desired_did not in text:
    raise SystemExit("Falha ao configurar o PDS da Espelunca.")

path.write_text(text)
PY

python3 <<'PY'
from pathlib import Path
import re

path = Path("app.config.js")
text = path.read_text()

replacements = {
    "name: 'Bluesky'": "name: 'Espelunca'",
    "slug: 'bluesky'": "slug: 'espelunca'",
    "scheme: 'bluesky'": "scheme: 'espelunca'",
    "bundleIdentifier: 'xyz.blueskyweb.app'": "bundleIdentifier: 'blue.espelunca.app'",
    "package: 'xyz.blueskyweb.app'": "package: 'blue.espelunca.app'",
    "host: 'bsky.app',": "host: 'espelunca.blue',",
    "'applinks:bsky.app',": "'applinks:espelunca.blue',",
}

for old, new in replacements.items():
    text = text.replace(old, new)

text = re.sub(
    r"CFBundleSpokenName:\s*'[^']*'",
    "CFBundleSpokenName: 'Espelunca'",
    text,
    count=1,
)

path.write_text(text)
PY

python3 <<'PY'
from pathlib import Path

path = Path("src/lib/strings/url-helpers.ts")
text = path.read_text()

old = "      return 'Bluesky Social'"
new = "      return urlp.host === 'espelunca.blue' ? 'Espelunca' : 'Bluesky Social'"

if "urlp.host === 'espelunca.blue' ? 'Espelunca' : 'Bluesky Social'" not in text:
    if old not in text:
        raise SystemExit("Não foi possível configurar o nome do provedor no signup.")
    text = text.replace(old, new, 1)

path.write_text(text)

path = Path("src/state/persisted/schema.ts")
text = path.read_text()

if "  darkTheme: 'dim'," in text:
    text = text.replace("  darkTheme: 'dim',", "  darkTheme: 'dark',", 1)
elif "  darkTheme: 'dark'," not in text:
    raise SystemExit("Não foi possível localizar o tema escuro padrão no upstream.")

path.write_text(text)
PY

python3 "\${ROOT_DIR}/espelunca-icon.svg" <<'PY'
from pathlib import Path
import re
import sys

icon = Path(sys.argv[1]).read_text()
match = re.search(r"<path\b[^>]*\bd=\"([^\"]+)\"", icon, re.IGNORECASE)
if not match:
    raise SystemExit("Não foi possível extrair o path do espelunca-icon.svg.")
icon_d = match.group(1)

def replace_path_d(path: Path, pattern: str, label: str) -> None:
    text = path.read_text()
    match = re.search(pattern, text, re.DOTALL)
    if not match:
        raise SystemExit(f"Não foi possível localizar {label} no upstream.")
    text = text[:match.start(2)] + icon_d + text[match.end(2):]
    path.write_text(text)

logo = Path("src/view/icons/Logo.tsx")
logo_text = logo.read_text()
logo_text = logo_text.replace("const ratio = 57 / 64", "const ratio = 1", 1)
logo_text = logo_text.replace('viewBox="0 0 64 57"', 'viewBox="0 0 640 640"', 1)
logo_text = logo_text.replace('accessibilityLabel="Bluesky"', 'accessibilityLabel="Espelunca"', 1)
logo.write_text(logo_text)
replace_path_d(
    logo,
    r'(<Path\s*\n\s*fill=\{_fill\}\s*\n\s*d=")([^"]+)(")',
    "o desenho do Logo",
)

mark = Path("src/view/icons/Logomark.tsx")
mark_text = mark.read_text()
mark_text = mark_text.replace("const ratio = 54 / 61", "const ratio = 1", 1)
mark_text = mark_text.replace('viewBox="0 0 61 54"', 'viewBox="0 0 640 640"', 1)
mark.write_text(mark_text)
replace_path_d(
    mark,
    r'(<Path\s*\n\s*fill=\{fill \|\| pal\.text\.color\}\s*\n\s*d=")([^"]+)(")',
    "o desenho do Logomark",
)

Path("src/view/icons/Logotype.tsx").write_text("""import Svg, {Text as SvgText, type PathProps, type SvgProps} from 'react-native-svg'

import {usePalette} from '#/lib/hooks/usePalette'

const ratio = 17 / 120

export function Logotype({
  fill,
  ...rest
}: {fill?: PathProps['fill']} & SvgProps) {
  const pal = usePalette('default')
  // @ts-expect-error it's fiiiiine
  const size = parseInt(String(rest.width || 32), 10)

  return (
    <Svg
      fill="none"
      viewBox="0 0 120 17"
      {...rest}
      width={size}
      height={Number(size) * ratio}>
      <SvgText
        x="0"
        y="13.5"
        fill={fill || pal.text.color}
        fontSize="15"
        fontWeight="700"
        letterSpacing="0.1">
        Espelunca
      </SvgText>
    </Svg>
  )
}
""")

Path("src/view/icons/LogomarkWithType.tsx").write_text("""import Svg, {Path, Text as SvgText, type PathProps, type SvgProps} from 'react-native-svg'

import {useTheme} from '#/alf'

const ratio = 31 / 160
const iconScale = 31 / 640

export function LogomarkWithType({
  fill,
  ...rest
}: {fill?: PathProps['fill']} & SvgProps) {
  const t = useTheme()
  const size = parseInt(String(rest.width || 32), 10)

  return (
    <Svg
      fill="none"
      viewBox="0 0 160 31"
      {...rest}
      width={size}
      height={Number(size) * ratio}>
      <Path
        d="__ESP_ICON_D__"
        fill={fill || t.atoms.text.color}
        transform={'scale(' + iconScale + ')'}
      />
      <SvgText
        x="39"
        y="22"
        fill={fill || t.atoms.text.color}
        fontSize="21"
        fontWeight="700"
        letterSpacing="0.15">
        Espelunca
      </SvgText>
    </Svg>
  )
}
""".replace("__ESP_ICON_D__", icon_d))

splash = Path("src/Splash.tsx")
splash_text = splash.read_text()
splash_text = splash_text.replace('viewBox="0 0 64 66"', 'viewBox="0 0 640 640"', 1)
splash_text = splash_text.replace("const height = width * (67 / 64)", "const height = width", 1)
splash.write_text(splash_text)
replace_path_d(
    splash,
    r'(<Path\s*\n\s*fill=\{props\.fill \|\| \x27#fff\x27\}\s*\n\s*d=")([^"]+)(")',
    "o desenho do logo do splash",
)
PY

echo "==> Customizações de código/configuração aplicadas."
echo "==> Customizações de código/configuração aplicadas."

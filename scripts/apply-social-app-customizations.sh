#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "\${ROOT_DIR}/config.env"
set +a

: "\${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "\${APP_DIR:?APP_DIR não definido}"

cd "\${APP_DIR}"

echo "==> Aplicando customizações versionadas do BlueskyEspelunca"

PATCH_DIR="\${ROOT_DIR}/patches/social-app"
if [[ -d "\${PATCH_DIR}" ]]; then
  shopt -s nullglob
  patches=("\${PATCH_DIR}"/*.patch)
  shopt -u nullglob
  for patch in "\${patches[@]}"; do
    echo "==> Aplicando patch: $(basename "\${patch}")"
    git apply --3way "\${patch}"
  done
fi

python3 - "\${PDS_HOSTNAME}" "\${ROOT_DIR}/espelunca-icon.svg" <<'PY'
from pathlib import Path
import re
import sys

pds = sys.argv[1]
root = Path(sys.argv[2])

# PDS used by the app.
constants = Path("src/lib/constants.ts")
text = constants.read_text()

desired_service = "export const BSKY_SERVICE = 'https://" + pds + "'"
desired_did = "export const BSKY_SERVICE_DID = 'did:web:" + pds + "'"
desired_default = "export const DEFAULT_SERVICE = BSKY_SERVICE"

text = re.sub(
    r"export const BSKY_SERVICE = '[^']+'",
    desired_service,
    text,
    count=1,
)
text = re.sub(
    r"export const BSKY_SERVICE_DID = '[^']+'",
    desired_did,
    text,
    count=1,
)
text = re.sub(
    r"export const DEFAULT_SERVICE = [^\n]+",
    desired_default,
    text,
    count=1,
)
if desired_service not in text or desired_did not in text or desired_default not in text:
    raise SystemExit("Falha ao configurar o PDS da Espelunca.")
constants.write_text(text)

# Application identity and supported deep-link domains.
app_config = Path("app.config.js")
text = app_config.read_text()
for old, new in {
    "name: 'Bluesky'": "name: 'Espelunca'",
    "slug: 'bluesky'": "slug: 'espelunca'",
    "scheme: 'bluesky'": "scheme: 'espelunca'",
    "bundleIdentifier: 'xyz.blueskyweb.app'": "bundleIdentifier: 'blue.espelunca.app'",
    "package: 'xyz.blueskyweb.app'": "package: 'blue.espelunca.app'",
    "host: 'bsky.app',": "host: 'espelunca.blue',",
    "'applinks:bsky.app',": "'applinks:espelunca.blue',",
}.items():
    text = text.replace(old, new)

text = re.sub(
    r"CFBundleSpokenName:\s*'[^']*'",
    "CFBundleSpokenName: 'Espelunca'",
    text,
    count=1,
)
app_config.write_text(text)

# User-facing provider name in account creation/server selection.
url_helpers = Path("src/lib/strings/url-helpers.ts")
text = url_helpers.read_text()
custom_provider = "return urlp.host === 'espelunca.blue' ? 'Espelunca' : 'Bluesky Social'"
if custom_provider not in text:
    old_provider = "      return 'Bluesky Social'"
    if old_provider not in text:
        raise SystemExit("Não foi possível configurar o nome do provedor no signup.")
    text = text.replace(old_provider, "      " + custom_provider, 1)
url_helpers.write_text(text)

# Page/browser titles use the Espelunca identity.
headings = Path("src/lib/strings/headings.ts")
text = headings.read_text()
text = text.replace("return \`\${unreadPrefix}\${page} — Bluesky\`", "return \`\${unreadPrefix}\${page} — Espelunca\`")
headings.write_text(text)

# Hosting provider selector should identify this PDS as Espelunca.
server_input = Path("src/components/dialogs/ServerInput.tsx")
text = server_input.read_text()
text = text.replace("label={_(msg\`Bluesky\`)}", "label={_(msg\`Espelunca\`)}", 1)
text = text.replace("{_(msg\`Bluesky\`)}", "{_(msg\`Espelunca\`)}", 1)
text = text.replace(
    """                Bluesky is an open network where you can choose your own
                provider. If you're new here, we recommend sticking with the
                default Bluesky Social option.""",
    """                Espelunca is an open network where you can choose your own
                provider. If you're new here, the default Espelunca option is
                already selected.""",
    1,
)
text = text.replace(
    """                Bluesky is an open network where you can choose your hosting
                provider. If you're a developer, you can host your own server.""",
    """                Espelunca is an open network where you can choose your
                hosting provider. If you're a developer, you can host your own
                server.""",
    1,
)
server_input.write_text(text)

# Default appearance: darkest theme. Users may still explicitly choose Light
# or Dim in Appearance settings.
schema = Path("src/state/persisted/schema.ts")
text = schema.read_text()
text = re.sub(r"colorMode: 'system',", "colorMode: 'dark',", text, count=1)
text = re.sub(r"darkTheme: 'dim',", "darkTheme: 'dark',", text, count=1)
schema.write_text(text)

# Replace the butterfly path in reusable logo components.
icon = root.read_text()
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
text = logo.read_text()
text = text.replace("const ratio = 57 / 64", "const ratio = 1", 1)
text = text.replace('viewBox="0 0 64 57"', 'viewBox="0 0 640 640"', 1)
text = text.replace('accessibilityLabel="Bluesky"', 'accessibilityLabel="Espelunca"', 1)
logo.write_text(text)
replace_path_d(
    logo,
    r'(<Path\s*\n\s*fill=\{_fill\}\s*\n\s*d=")([^"]+)(")',
    "o desenho do Logo",
)

mark = Path("src/view/icons/Logomark.tsx")
text = mark.read_text()
text = text.replace("const ratio = 54 / 61", "const ratio = 1", 1)
text = text.replace('viewBox="0 0 61 54"', 'viewBox="0 0 640 640"', 1)
mark.write_text(text)
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
text = splash.read_text()
text = text.replace('viewBox="0 0 64 66"', 'viewBox="0 0 640 640"', 1)
text = text.replace("const height = width * (67 / 64)", "const height = width", 1)
splash.write_text(text)
replace_path_d(
    splash,
    r"(<Path\s*\n\s*fill=\{props\.fill \|\| '#fff'\}\s*\n\s*d=")([^"]+)(")",
    "o desenho do logo do splash",
)

print("Customizações de branding e tema aplicadas.")
PY

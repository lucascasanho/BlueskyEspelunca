#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${APP_DIR:?APP_DIR não definido}"

cd "${APP_DIR}"

# Cada build deve começar do código upstream limpo. As customizações deste
# repositório são reaplicadas abaixo e não devem se acumular entre builds.
echo "==> Restaurando social-app para o HEAD atual"
git reset --hard HEAD >/dev/null

echo "==> Aplicando customizações versionadas do BlueskyEspelunca"

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

python3 - "${PDS_HOSTNAME}" "${ROOT_DIR}/espelunca-icon.svg" <<'PY'
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
desired_feed_uri = "export const ESPELUNCA_BR_FEED_URI = 'at://did:plc:kafjdndx54b3wdlu6cbiwk42/app.bsky.feed.generator/espelunca-br'"

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
if desired_feed_uri not in text:
    text = text.replace(
        desired_default,
        desired_default + "\n" + desired_feed_uri,
        1,
    )
if (
    desired_service not in text
    or desired_did not in text
    or desired_default not in text
    or desired_feed_uri not in text
):
    raise SystemExit("Falha ao configurar o PDS/feed da Espelunca.")
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
text = text.replace("return `${unreadPrefix}${page} — Bluesky`", "return `${unreadPrefix}${page} — Espelunca`")
headings.write_text(text)

# Hosting provider selector should identify this PDS as Espelunca.
server_input = Path("src/components/dialogs/ServerInput.tsx")
text = server_input.read_text()
text = text.replace("label={_(msg`Bluesky`)}", "label={_(msg`Espelunca`)}", 1)
text = text.replace("{_(msg`Bluesky`)}", "{_(msg`Espelunca`)}", 1)
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

# iOS Safari zooms focused web inputs whose computed font size is below 16 CSS px.
# Match the current upstream component types instead of assuming every input is TextField.Input.
login_form = Path("src/screens/Login/LoginForm.tsx")
text = login_form.read_text()
alf_import_pattern = r"(import\s*\{)([^}]*)(\}\s*from '#/alf')"
def add_web_import(match):
    names = match.group(2)
    if re.search(r"\bweb\b", names):
        return match.group(0)
    trimmed = names.rstrip()
    separator = "" if trimmed.endswith(",") else ","
    return match.group(1) + trimmed + separator + " web" + match.group(3)
text, import_count = re.subn(alf_import_pattern, add_web_import, text, count=1, flags=re.DOTALL)
if import_count != 1:
    raise SystemExit("Não foi possível localizar o import de #/alf no LoginForm.")

for component, test_id in (
    ("TextField\\.Input", "loginUsernameInput"),
    ("PasswordField", "loginPasswordInput"),
    ("TokenField", "loginAuthFactorTokenInput"),
):
    pattern = rf'(<{component}\b(?:(?!>).)*\btestID="{test_id}"\n)'
    replacement = r'\1            style={web({fontSize: 16})}' + "\n"
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise SystemExit(f"Não foi possível ajustar o font-size Safari de {test_id}.")
login_form.write_text(text)

# TokenField must forward the conditional style to its inner TextField.Input.
token_field = Path("src/components/dialogs/EmailDialog/components/TokenField.tsx")
text = token_field.read_text()
text = text.replace(
    "  testID,\n  autoFocus,",
    "  testID,\n  style,\n  autoFocus,",
    1,
)
text = text.replace(
    "  | 'testID'\n  | 'autoFocus'",
    "  | 'testID'\n  | 'style'\n  | 'autoFocus'",
    1,
)
text = text.replace(
    "        <TextField.Input\n          testID={testID}\n",
    "        <TextField.Input\n          testID={testID}\n          style={style}\n",
    1,
)
if "          style={style}" not in text or "  | 'style'" not in text:
    raise SystemExit("Não foi possível encaminhar o estilo do TokenField.")
token_field.write_text(text)

# Default appearance: darkest theme. Users may still explicitly choose Light
# or Dim in Appearance settings.
schema = Path("src/state/persisted/schema.ts")
text = schema.read_text()
text = re.sub(r"colorMode: 'system',", "colorMode: 'dark',", text, count=1)
text = re.sub(r"darkTheme: 'dim',", "darkTheme: 'dark',", text, count=1)
schema.write_text(text)

# Apply the new dark-first default to existing installations only once.
# Explicit Light/Dim choices remain untouched after the migration.
schema = Path("src/state/persisted/schema.ts")
text = schema.read_text()
if "appearanceDefaultMigrated: z.boolean().optional()," not in text:
    text = text.replace(
        "  darkTheme: z.enum(['dim', 'dark']).optional(),",
        "  darkTheme: z.enum(['dim', 'dark']).optional(),\n  appearanceDefaultMigrated: z.boolean().optional(),",
        1,
    )
text = re.sub(r"colorMode: 'system',", "colorMode: 'dark',", text, count=1)
text = re.sub(r"darkTheme: 'dim',", "darkTheme: 'dark',", text, count=1)
if "  appearanceDefaultMigrated: false," not in text:
    text = text.replace(
        "  darkTheme: 'dark',\n  session:",
        "  darkTheme: 'dark',\n  appearanceDefaultMigrated: false,\n  session:",
        1,
    )
schema.write_text(text)

persisted_util = Path("src/state/persisted/util.ts")
text = persisted_util.read_text()
migration = """  if (!next.appearanceDefaultMigrated) {
    if (next.colorMode === 'system' && (next.darkTheme === 'dim' || !next.darkTheme)) {
      next.colorMode = 'dark'
      next.darkTheme = 'dark'
    }
    next.appearanceDefaultMigrated = true
  }

"""
if migration.strip() not in text:
    marker = "\n  return next\n"
    if marker not in text:
        raise SystemExit("Não foi possível localizar o retorno da normalização de preferências.")
    text = text.replace(marker, migration + marker, 1)
persisted_util.write_text(text)

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

# Never render the upstream Kawaii/butterfly variant in this fork.
text = text.replace("import {Image} from 'expo-image'\n", "")
text = text.replace("import {useLogoVariant} from '#/view/icons/useLogoVariant'\n", "")
text = text.replace(
    "  const {allowVariants = true, fill, ...rest} = props",
    "  const {fill, ...rest} = props",
    1,
)
text = re.sub(
    r"\n  const logoVariant = useLogoVariant\(allowVariants\)\n\n  if \(logoVariant === 'kawaii'\) \{.*?\n  \}\n\n  return \(",
    "\n  return (",
    text,
    count=1,
    flags=re.DOTALL,
)

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
    r"""(<Path\s*\n\s*fill=\{props\.fill \|\| '#fff'\}\s*\n\s*d=")([^"]+)(")""",
    "o desenho do logo do splash",
)

# Web also has an early React splash plus a static HTML splash. Both must use
# the Espelunca mark so the upstream butterfly never appears during startup.
splash_web = Path("src/Splash.web.tsx")
text = splash_web.read_text()
text = text.replace("const ratio = 57 / 64", "const ratio = 1", 1)
text = text.replace('viewBox="0 0 64 57"', 'viewBox="0 0 640 640"', 1)
text = text.replace(
    '<Svg\n            fill="none"\n            viewBox="0 0 640 640"',
    '<Svg\n            fill="none"\n            viewBox="0 0 640 640"\n            accessibilityLabel="Espelunca"',
    1,
)
# The literal tab/spacing above is intentionally not a regex. Handle the
# actual formatted source explicitly as well.
text = text.replace(
    '            viewBox="0 0 640 640"\n            style=',
    '            viewBox="0 0 640 640"\n            accessibilityLabel="Espelunca"\n            style=',
    1,
)
splash_web.write_text(text)
replace_path_d(
    splash_web,
    r'(<Path\s*\n\s*fill="#006AFF"\s*\n\s*d=")([^"]+)(")',
    "o desenho do splash web",
)

def replace_static_splash(path: Path, label: str) -> None:
    text = path.read_text()
    replacement = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 640"><path fill="#006AFF" d="' + icon_d + '"/></svg>'

    # Idempotent: if this file was already branded by a previous partial build,
    # leave the existing Espelunca splash untouched.
    if icon_d in text and "viewBox=\"0 0 640 640\"" in text:
        return

    # Current upstream splash markup.
    splash_pattern = r'(<div id="splash">\s*)(?:<!--.*?-->\s*)?<svg\b.*?</svg>'
    text, count = re.subn(
        splash_pattern,
        lambda m: m.group(1) + "<!-- Espelunca SVG -->\n    " + replacement,
        text,
        count=1,
        flags=re.DOTALL,
    )
    if count != 1:
        raise SystemExit(f"Não foi possível localizar o splash estático em {label}.")
    path.write_text(text)

replace_static_splash(Path("public/index.html"), "public/index.html")
replace_static_splash(Path("bskyweb/templates/base.html"), "bskyweb/templates/base.html")


# Welcome modal: keep the public landing popover fully branded as Espelunca.
welcome_modal = Path("src/components/WelcomeModal.tsx")
text = welcome_modal.read_text()
text = text.replace(
    """                    Bluesky
                  </Text>""",
    """                    Espelunca
                  </Text>""",
    1,
)
welcome_modal.write_text(text)

# New accounts should follow the Espelunca profile instead of the Bluesky account.
step_finished = Path("src/screens/Onboarding/StepFinished/index.tsx")
text = step_finished.read_text()
text = re.sub(
    r"(?m)^  (?:BSKY_APP_ACCOUNT_DID|ESPELUNCA_BR_FEED_URI),\n  DISCOVER_SAVED_FEED,\n  TIMELINE_SAVED_FEED,\n(?:  VIDEO_SAVED_FEED,\n)?",
    "  ESPELUNCA_BR_FEED_URI,\n  DISCOVER_SAVED_FEED,\n  TIMELINE_SAVED_FEED,\n",
    text,
    count=1,
)
text = text.replace(
    "import {app} from '#/lexicons'",
    "import {app, com} from '#/lexicons'",
    1,
)
follow_pattern = re.compile(
    r"    (?:const followDids = \[\n.*?\n    \])",
    re.DOTALL,
)
follow_replacement = """    let espeluncaDid: string | undefined
    try {
      const resolved = await pdsClient.call(com.atproto.identity.resolveHandle, {
        handle: 'espelunca.blue',
      })
      espeluncaDid = resolved.did
    } catch (e) {
      logger.error('Failed to resolve the Espelunca account for onboarding follow', {
        safeMessage: e,
      })
    }

    const followDids = [
      ...(espeluncaDid ? [espeluncaDid] : []),
      ...(listItems?.map(i => i.subject.did) ?? []),
    ]"""
text, count = follow_pattern.subn(follow_replacement, text, count=1)
if count != 1:
    raise SystemExit("Não foi possível localizar followDids no StepFinished.")
step_finished.write_text(text)

# Retire the Espelunca BR feed from onboarding, recommendations and saved-feed preferences.
constants = Path("src/lib/constants.ts")
text = constants.read_text()
text = re.sub(r"(?m)^export const ESPELUNCA_BR_FEED_URI = '[^']+'\n?", "", text)
retired_uri = "export const RETIRED_ESPELUNCA_FEED_URI = 'at://did:plc:kafjdndx54b3wdlu6cbiwk42/app.bsky.feed.generator/espelunca-br'"
if retired_uri not in text:
    text = text.replace(desired_default, desired_default + "\n" + retired_uri, 1)
if retired_uri not in text:
    raise SystemExit("Não foi possível registrar a URI do feed desativado.")
constants.write_text(text)

step_finished = Path("src/screens/Onboarding/StepFinished/index.tsx")
text = step_finished.read_text()
text = re.sub(r"(?m)^  ESPELUNCA_BR_FEED_URI,\n", "", text, count=1)
feeds_pattern = r"""          const feedsToSave: app\.bsky\.actor\.defs\.SavedFeed\[\] = \[.*?          \]\n\n          // Any Starter Pack feeds"""
feeds_custom = """          const feedsToSave: app.bsky.actor.defs.SavedFeed[] = [
            {
              ...TIMELINE_SAVED_FEED,
              id: TID.nextStr(),
            },
            {
              ...DISCOVER_SAVED_FEED,
              id: TID.nextStr(),
            },
          ]

          // Any Starter Pack feeds"""
text, count = re.subn(feeds_pattern, feeds_custom, text, count=1, flags=re.DOTALL)
if count != 1 or "ESPELUNCA_BR_FEED_URI" in text:
    raise SystemExit("Não foi possível remover o feed do onboarding.")
step_finished.write_text(text)

create_account = Path("src/state/session/create-account.ts")
text = create_account.read_text()
text = re.sub(r"(?m)^  ESPELUNCA_BR_FEED_URI,\n", "", text, count=1)
create_feed_pattern = r"""function initializeSavedFeeds\(client: Client\) \{.*?\n\}"""
create_feed_custom = """function initializeSavedFeeds(client: Client) {
  return retryPostSignupTask('set initial feeds', 1, () =>
    client.call(overwriteSavedFeeds, [
      {...TIMELINE_SAVED_FEED, id: TID.nextStr()},
      {...DISCOVER_SAVED_FEED, id: TID.nextStr()},
    ]),
  )
}"""
text, count = re.subn(create_feed_pattern, create_feed_custom, text, count=1, flags=re.DOTALL)
if count != 1 or "ESPELUNCA_BR_FEED_URI" in text:
    raise SystemExit("Não foi possível remover o feed do create-account.")
create_account.write_text(text)

preferences = Path("src/state/queries/preferences/index.ts")
text = preferences.read_text()
text = text.replace("import {PROD_DEFAULT_FEED} from '#/lib/constants'", "import {PROD_DEFAULT_FEED, RETIRED_ESPELUNCA_FEED_URI} from '#/lib/constants'", 1)
preferences_anchor = """        const res = await client.call(getPreferences)

        const labelerDids = res.moderationPrefs.labelers.map(l => l.did)"""
preferences_replacement = """        const res = await client.call(getPreferences)
        const retiredFeedIds = res.savedFeeds
          .filter(feed => feed.value === RETIRED_ESPELUNCA_FEED_URI)
          .map(feed => feed.id)
        if (retiredFeedIds.length) {
          try {
            await client.call(removeSavedFeeds, retiredFeedIds)
          } catch (error) {
            console.warn('Unable to remove the retired Espelunca feed from saved preferences', error)
          }
        }

        const labelerDids = res.moderationPrefs.labelers.map(l => l.did)"""
if preferences_anchor not in text:
    raise SystemExit("Não foi possível localizar o carregamento das preferências.")
text = text.replace(preferences_anchor, preferences_replacement, 1)
text = text.replace("savedFeeds: res.savedFeeds.filter(f => f.type !== 'unknown'),", "savedFeeds: res.savedFeeds.filter(\n            f => f.type !== 'unknown' && f.value !== RETIRED_ESPELUNCA_FEED_URI,\n          ),", 1)
if "retiredFeedIds" not in text: raise SystemExit("Preferências não filtram o feed aposentado.")
preferences.write_text(text)

feed_query = Path("src/state/queries/feed.ts")
text = feed_query.read_text()
text = text.replace("import {DISCOVER_FEED_URI, DISCOVER_SAVED_FEED} from '#/lib/constants'", "import {\n  DISCOVER_FEED_URI,\n  DISCOVER_SAVED_FEED,\n  RETIRED_ESPELUNCA_FEED_URI,\n} from '#/lib/constants'", 1)
text, count = re.subn(r"return !alreadySaved && !decision\.ui\('contentList'\)\.filter", "return feed.uri !== RETIRED_ESPELUNCA_FEED_URI && !alreadySaved && !decision.ui('contentList').filter", text, count=1)
if count != 1: raise SystemExit("Não foi possível filtrar recomendações.")
search_anchor = """      if (moderationOpts) {
        return data.feeds.filter(feed => {
          const decision = moderateFeedGenerator(feed, moderationOpts)
          return !decision.ui('contentMedia').blur
        })
      }

      return data.feeds"""
search_replacement = """      if (moderationOpts) {
        return data.feeds.filter(feed => {
          const decision = moderateFeedGenerator(feed, moderationOpts)
          return feed.uri !== RETIRED_ESPELUNCA_FEED_URI && !decision.ui('contentMedia').blur
        })
      }

      return data.feeds.filter(feed => feed.uri !== RETIRED_ESPELUNCA_FEED_URI)"""
if search_anchor not in text: raise SystemExit("Não foi possível localizar a busca de feeds.")
text = text.replace(search_anchor, search_replacement, 1)
text = text.replace("return !decision.ui('contentMedia').blur", "return feed.uri !== RETIRED_ESPELUNCA_FEED_URI && !decision.ui('contentMedia').blur", 1)
feed_query.write_text(text)
if "ESPELUNCA_BR_FEED_URI" in step_finished.read_text() or "ESPELUNCA_BR_FEED_URI" in create_account.read_text():
    raise SystemExit("Onboarding mantém referência ao feed.")


# Keep only the supported upstream trending behavior and our 10-topic limit.
trends_query = Path("src/state/queries/trending/useGetTrendsQuery.ts")
text = trends_query.read_text()
text = text.replace("export const DEFAULT_LIMIT = 5", "export const DEFAULT_LIMIT = 10", 1)
trends_query.write_text(text)
PY

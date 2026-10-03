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
text = text.replace("return \`${unreadPrefix}${page} — Bluesky\`", "return \`${unreadPrefix}${page} — Espelunca\`")
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
    text = text.replace("<!-- Bluesky SVG -->", "<!-- Espelunca SVG -->", 1)
    pattern = r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 57"><path fill="#006AFF" d="[^"]+"/></svg>'
    replacement = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 640"><path fill="#006AFF" d="' + icon_d + '"/></svg>'
    text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"Não foi possível substituir o splash estático em {label}.")
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
text = text.replace(
    """  BSKY_APP_ACCOUNT_DID,
  DISCOVER_SAVED_FEED,
  TIMELINE_SAVED_FEED,
  VIDEO_SAVED_FEED,""",
    """  ESPELUNCA_BR_FEED_URI,
  DISCOVER_SAVED_FEED,
  TIMELINE_SAVED_FEED,""",
    1,
)
text = text.replace(
    "import {app} from '#/lexicons'",
    "import {app, com} from '#/lexicons'",
    1,
)
old_follow = """    const followDids = [
      BSKY_APP_ACCOUNT_DID,
      ...(listItems?.map(i => i.subject.did) ?? []),
    ]"""
new_follow = """    let espeluncaDid: string | undefined
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
if old_follow not in text:
    raise SystemExit("Bloco followDids não encontrado no StepFinished upstream")
text = text.replace(old_follow, new_follow, 1)
# Pin the Espelunca BR feed for every account completing onboarding on this branded app.
# The URI belongs to the public Feed Generator and is saved alongside the normal
# Bluesky defaults. Re-running this script must not create duplicate entries.
feed_import_anchor = """  ESPELUNCA_BR_FEED_URI,
  DISCOVER_SAVED_FEED,"""
if feed_import_anchor not in text:
    raise SystemExit("Não foi possível localizar a importação do feed Espelunca.")
feeds_pattern = r"""          const feedsToSave: app\.bsky\.actor\.defs\.SavedFeed\[\] = \[.*?          \]\n\n          // Any Starter Pack feeds"""
feed_custom = """          const feedsToSave: app.bsky.actor.defs.SavedFeed[] = [
            {
              ...TIMELINE_SAVED_FEED,
              id: TID.nextStr(),
            },
            {
              type: 'feed',
              value: ESPELUNCA_BR_FEED_URI,
              pinned: true,
              id: TID.nextStr(),
            },
            {
              ...DISCOVER_SAVED_FEED,
              id: TID.nextStr(),
            },
          ]

          // Any Starter Pack feeds"""
text, count = re.subn(feeds_pattern, feed_custom, text, count=1, flags=re.DOTALL)
if count != 1:
    raise SystemExit("Não foi possível substituir a lista de feeds padrão no StepFinished.")
step_finished.write_text(text)

# The upstream account-creation flow also initializes feeds asynchronously.
# Keep the same canonical order so it cannot race with onboarding and restore
# a different default set.
create_account = Path("src/state/session/create-account.ts")
text = create_account.read_text()
text = re.sub(
    r"""  DISCOVER_SAVED_FEED,
  IS_PROD_SERVICE,
  TIMELINE_SAVED_FEED,""",
    """  DISCOVER_SAVED_FEED,
  ESPELUNCA_BR_FEED_URI,
  IS_PROD_SERVICE,
  TIMELINE_SAVED_FEED,""",
    text,
    count=1,
)
create_feed_pattern = r"""function initializeSavedFeeds\(client: Client\) \{.*?\n\}"""
create_feed_custom = """function initializeSavedFeeds(client: Client) {
  return retryPostSignupTask('set initial feeds', 1, () =>
    client.call(overwriteSavedFeeds, [
      {...TIMELINE_SAVED_FEED, id: TID.nextStr()},
      {
        type: 'feed',
        value: ESPELUNCA_BR_FEED_URI,
        pinned: true,
        id: TID.nextStr(),
      },
      {...DISCOVER_SAVED_FEED, id: TID.nextStr()},
    ]),
  )
}"""
text, count = re.subn(create_feed_pattern, create_feed_custom, text, count=1, flags=re.DOTALL)
if count != 1:
    raise SystemExit("Não foi possível substituir a inicialização de feeds do create-account.")
create_account.write_text(text)

# The Home tab bar must use the Espelunca canonical order even if the
# AppView returns saved-feed preferences in a different order. We preserve
# every other pinned item after the first three positions.
home = Path("src/view/screens/Home.tsx")
text = home.read_text()
text = text.replace(
    """  DISCOVER_FEED_URI,
  PROD_DEFAULT_FEED,
  TIMELINE_SAVED_FEED,""",
    """  DISCOVER_FEED_URI,
  ESPELUNCA_BR_FEED_URI,
  PROD_DEFAULT_FEED,
  TIMELINE_SAVED_FEED,""",
    1,
)
home_anchor = """  const allFeeds = useMemo(
    () => pinnedFeedInfos.map(f => f.feedDescriptor),
    [pinnedFeedInfos],
  )"""
home_custom = """  const orderedPinnedFeedInfos = useMemo(() => {
    const rank = (feed: SavedFeedSourceInfo) => {
      if (feed.uri === TIMELINE_SAVED_FEED.value) return 0
      if (feed.uri === ESPELUNCA_BR_FEED_URI) return 1
      if (feed.uri === DISCOVER_FEED_URI) return 2
      return 3
    }

    return pinnedFeedInfos
      .map((feed, index) => ({feed, index}))
      .sort((a, b) => rank(a.feed) - rank(b.feed) || a.index - b.index)
      .map(({feed}) => feed)
  }, [pinnedFeedInfos])

  const allFeeds = useMemo(
    () => orderedPinnedFeedInfos.map(f => f.feedDescriptor),
    [orderedPinnedFeedInfos],
  )"""
if home_anchor not in text:
    raise SystemExit("Não foi possível localizar a lista de feeds da Home para ordenar as abas.")
text = text.replace(home_anchor, home_custom, 1)
text = text.replace(
    "const selectedFeedInfo = pinnedFeedInfos[selectedIndex]",
    "const selectedFeedInfo = orderedPinnedFeedInfos[selectedIndex]",
    1,
)
text = text.replace(
    "feeds={pinnedFeedInfos}",
    "feeds={orderedPinnedFeedInfos}",
    1,
)
text = text.replace(
    "      {pinnedFeedInfos.length ? (",
    "      {orderedPinnedFeedInfos.length ? (",
    1,
)
text = text.replace(
    "pinnedFeedInfos.map((feedInfo, index) => {",
    "orderedPinnedFeedInfos.map((feedInfo, index) => {",
    1,
)
if "orderedPinnedFeedInfos" not in text:
    raise SystemExit("A ordenação da Home não foi aplicada.")
home.write_text(text)

# Build-time hard checks: never ship a bundle with the official default feed
# order or Video default accidentally restored by an upstream update.
step_check = Path("src/screens/Onboarding/StepFinished/index.tsx").read_text()
create_check = Path("src/state/session/create-account.ts").read_text()
if "value: ESPELUNCA_BR_FEED_URI" not in step_check:
    raise SystemExit("Validação falhou: StepFinished não contém o Feed Espelunca BR.")
if "value: ESPELUNCA_BR_FEED_URI" not in create_check:
    raise SystemExit("Validação falhou: create-account não contém o Feed Espelunca BR.")
if "TIMELINE_SAVED_FEED" not in step_check or "DISCOVER_SAVED_FEED" not in step_check:
    raise SystemExit("Validação falhou: StepFinished perdeu os feeds padrão esperados.")
if re.search(r"\.\.\.VIDEO_SAVED_FEED", step_check):
    raise SystemExit("Validação falhou: VIDEO_SAVED_FEED voltou ao conjunto padrão do onboarding.")
if re.search(r"\.\.\.VIDEO_SAVED_FEED", create_check):
    raise SystemExit("Validação falhou: VIDEO_SAVED_FEED voltou ao conjunto padrão do create-account.")

if "orderedPinnedFeedInfos" not in text:
    raise SystemExit("Validação falhou: Home.tsx não recebeu a ordenação canônica das abas.")
if "feeds={orderedPinnedFeedInfos}" not in text:
    raise SystemExit("Validação falhou: HomeHeader não está usando a ordem canônica.")
if "orderedPinnedFeedInfos.map((feedInfo, index) => {" not in text:
    raise SystemExit("Validação falhou: páginas da Home não estão usando a ordem canônica.")

# Keep only the supported upstream trending behavior and our 10-topic limit.
trends_query = Path("src/state/queries/trending/useGetTrendsQuery.ts")
text = trends_query.read_text()
text = text.replace("export const DEFAULT_LIMIT = 5", "export const DEFAULT_LIMIT = 10", 1)
trends_query.write_text(text)
PY

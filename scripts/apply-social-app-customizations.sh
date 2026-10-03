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


# Trending: default to Brazilian Portuguese, with an explicit global toggle
# in the main Trending modules. Global mode removes both language and topic
# personalization headers so it reflects network-wide trends.
trends_query = Path("src/state/queries/trending/useGetTrendsQuery.ts")
text = trends_query.read_text()
text = text.replace("export const DEFAULT_LIMIT = 5", "export const DEFAULT_LIMIT = 10", 1)
text = text.replace(
    """type QueryProps = {
  fetchLimit?: number
  limit?: number
  refetchOnWindowFocus?: boolean
}""",
    """export type TrendingScope = 'pt-BR' | 'global'

type QueryProps = {
  fetchLimit?: number
  limit?: number
  refetchOnWindowFocus?: boolean
  scope?: TrendingScope
}""",
    1,
)
text = text.replace(
    """export const createGetTrendsQueryKey = (fetchLimit?: number) =>
  fetchLimit === undefined ? ['trends'] : ['trends', {limit: fetchLimit}]""",
    """export const createGetTrendsQueryKey = (
  fetchLimit?: number,
  scope: TrendingScope = 'pt-BR',
) =>
  fetchLimit === undefined
    ? ['trends', {scope}]
    : ['trends', {limit: fetchLimit, scope}]""",
    1,
)
text = text.replace(
    """  const fetchLimit = props.fetchLimit ?? DEFAULT_FETCH_LIMIT
  const limit = props.limit ?? DEFAULT_LIMIT""",
    """  const fetchLimit = props.fetchLimit ?? DEFAULT_FETCH_LIMIT
  const limit = props.limit ?? DEFAULT_LIMIT
  const scope = props.scope ?? 'pt-BR'""",
    1,
)
text = text.replace(
    """    queryKey: createGetTrendsQueryKey(fetchLimit),
    queryFn: async () => {
      const contentLangs = getContentLanguages().join(',')
      const data = await client.call(
        app.bsky.unspecced.getTrends,
        {
          limit: fetchLimit,
        },
        {
          headers: {
            ...createBskyTopicsHeader(aggregateUserInterests(preferences)),
            'Accept-Language': contentLangs,
          },
        },
      )""",
    """    queryKey: createGetTrendsQueryKey(fetchLimit, scope),
    queryFn: async () => {
      const headers =
        scope === 'pt-BR'
          ? {
              ...createBskyTopicsHeader(aggregateUserInterests(preferences)),
              'Accept-Language': 'pt-BR',
            }
          : {}
      const data = await client.call(
        app.bsky.unspecced.getTrends,
        {
          limit: fetchLimit,
        },
        {
          headers,
        },
      )""",
    1,
)
text = text.replace("import {getContentLanguages} from '#/state/preferences/languages'\n", "", 1)
trends_query.write_text(text)

explore = Path("src/screens/Search/modules/ExploreTrendingTopics.tsx")
text = explore.read_text()
text = text.replace("import {useMemo} from 'react'", "import {useMemo, useState} from 'react'", 1)
text = text.replace(
    """  const topicCount = ax.features.getValue(
    ax.features.TrendingExploreTopicsCountValue,
    DEFAULT_LIMIT,
  )""",
    """  const topicCount = DEFAULT_LIMIT
  const [showGlobal, setShowGlobal] = useState(false)""",
    1,
)
text = text.replace(
    """    fetchLimit: Math.min(topicCount * 2, DEFAULT_FETCH_LIMIT),
    limit: topicCount,
  })""",
    """    fetchLimit: Math.min(topicCount * 2, DEFAULT_FETCH_LIMIT),
    limit: topicCount,
    scope: showGlobal ? 'global' : 'pt-BR',
  })""",
    1,
)
marker="""          <ModuleHeader.EllipsisButton
            label={l__BT__Trending options__BT__}
            onPress={() => trendingPrompt.open()}
          />"""
replacement="""          <Link
            label={showGlobal ? l__BT__View Brazilian trending__BT__ : l__BT__View global trending__BT__}
            to="#"
            onPress={() => setShowGlobal(value => !value)}>
            {({hovered, pressed}) => (
              <Text
                style={[
                  a.text_sm,
                  a.font_medium,
                  hovered || pressed
                    ? [t.atoms.text, a.underline]
                    : t.atoms.text_contrast_medium,
                ]}>
                {showGlobal ? <Trans>BR</Trans> : <Trans>Global</Trans>}
              </Text>
            )}
          </Link>
          <ModuleHeader.EllipsisButton
            label={l__BT__Trending options__BT__}
            onPress={() => trendingPrompt.open()}
          />"""
marker=marker.replace("__BT__",String.fromCharCode(96))
replacement=replacement.replace("__BT__",String.fromCharCode(96))
if marker not in text: raise SystemExit("Explore header marker não encontrado")
text=text.replace(marker,replacement,1)
explore.write_text(text)

sidebar = Path("src/view/shell/desktop/SidebarTrendingTopics.tsx")
text = sidebar.read_text()
text = text.replace("import {View} from 'react-native'", "import {useState} from 'react'\nimport {View} from 'react-native'", 1)
text = text.replace(
    """  const exploreTopicCount = ax.features.getValue(
    ax.features.TrendingExploreTopicsCountValue,
    DEFAULT_LIMIT,
  )""",
    """  const exploreTopicCount = DEFAULT_LIMIT
  const [showGlobal, setShowGlobal] = useState(false)""",
    1,
)
text = text.replace(
    """  } = useGetTrendsQuery({
    refetchOnWindowFocus: true,
  })""",
    """  } = useGetTrendsQuery({
    refetchOnWindowFocus: true,
    scope: showGlobal ? 'global' : 'pt-BR',
  })""",
    1,
)
marker="""          {exploreTopicCount > DEFAULT_LIMIT ? (
            <Link label={l__BT__See more trending topics__BT__} to="/search">
              {({hovered, pressed}) => (
                <Text
                  style={[
                    a.text_sm,
                    a.font_medium,
                    {
                      color:
                        hovered || pressed
                          ? t.palette.contrast_800
                          : t.palette.contrast_500,
                    },
                  ]}
                  numberOfLines={1}>
                  <Trans>See more</Trans>
                </Text>
              )}
            </Link>
          ) : null}
          <Button"""
replacement="""          <Link
            label={showGlobal ? l__BT__View Brazilian trending__BT__ : l__BT__View global trending__BT__}
            to="#"
            onPress={() => setShowGlobal(value => !value)}>
            {({hovered, pressed}) => (
              <Text
                style={[
                  a.text_xs,
                  a.font_medium,
                  hovered || pressed
                    ? [t.atoms.text, a.underline]
                    : t.atoms.text_contrast_medium,
                ]}
                numberOfLines={1}>
                {showGlobal ? <Trans>BR</Trans> : <Trans>Global</Trans>}
              </Text>
            )}
          </Link>
          <Button"""
marker=marker.replace("__BT__",String.fromCharCode(96))
replacement=replacement.replace("__BT__",String.fromCharCode(96))
if marker not in text: raise SystemExit("Sidebar header marker não encontrado")
text=text.replace(marker,replacement,1)
sidebar.write_text(text)

print("Customização de Em Alta PT-BR/global e limite 10 aplicada.")
PY

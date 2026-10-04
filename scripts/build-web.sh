#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${APP_DIR:?APP_DIR não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

cd "${APP_DIR}"
"${ROOT_DIR}/scripts/apply-social-app-customizations.sh"
pnpm build-web

# Apply web-only branding to the generated static shell.
cp "${ROOT_DIR}/espelunca-icon.svg" dist/espelunca-icon.svg
python3 - <<'PY'
from pathlib import Path
import re

path = Path("dist/index.html")
text = path.read_text()

text = re.sub(r"<title>.*?</title>", "<title>Espelunca</title>", text, count=1, flags=re.DOTALL)
text = re.sub(
    r'<meta\s+name="application-name"\s+content="[^"]*"\s*/?>',
    '<meta name="application-name" content="Espelunca">',
    text,
    count=1,
)

# Remove Expo's generated favicon declarations and use the fork's icon.
text = re.sub(r'\s*<link\s+[^>]*rel="icon"[^>]*>', "", text, flags=re.IGNORECASE)
favicon = '<link rel="icon" type="image/svg+xml" href="/espelunca-icon.svg">'
if favicon not in text:
    text = text.replace("</head>", f"  {favicon}\n</head>", 1)

path.write_text(text)
PY

# Install the Espelunca PWA shell and assets into the generated web output.
PWA_DIR="$ROOT_DIR/pwa"
if [[ ! -f "$PWA_DIR/manifest.json" || ! -f "$PWA_DIR/sw.js" ]]; then
  echo "ERRO: arquivos PWA ausentes em $PWA_DIR"
  exit 1
fi
if [[ ! -f "$PWA_DIR/icons/icon-any.svg" || ! -f "$PWA_DIR/icons/icon-maskable.svg" ]]; then
  echo "ERRO: fontes de ícone PWA ausentes em $PWA_DIR/icons"
  exit 1
fi

mkdir -p dist/icons dist/screenshots

# Generate the normal PWA icons as rounded blue app tiles with the white Espelunca mark.
# Rasterize all PWA icons as standard 8-bit PNGs. Keep the normal icon large enough to match the source mark;
# keep the maskable variant inside the standardized safe area so platform masks do not clip the logo.
for size in 96 192 512; do
  magick -background none \
    "$PWA_DIR/icons/icon-any.svg" \
    -resize "${size}x${size}" \
    -depth 8 \
    -define png:color-type=6 \
    -strip \
    "dist/icons/icon-${size}.png"
done

for size in 192 512; do
  magick -background none \
    "$PWA_DIR/icons/icon-maskable.svg" \
    -resize "${size}x${size}" \
    -depth 8 \
    -define png:color-type=6 \
    -strip \
    "dist/icons/icon-${size}-maskable.png"
done

# Fail the build if any generated icon is not square or is not 8-bit.
for file in dist/icons/*.png; do
  info="$(magick identify -format "%w %h %[depth]" "$file")"
  read -r width height depth <<< "$info"
  if [[ "$width" != "$height" || "$depth" != "8" ]]; then
    echo "ERRO: ícone PWA inválido: $file ($info)"
    exit 1
  fi
done

cp "$PWA_DIR/manifest.json" dist/manifest.json
cp "$ROOT_DIR/desktop-home.png" dist/screenshots/desktop-home.png
cp "$ROOT_DIR/mobile-home.png" dist/screenshots/mobile-home.png
cp "$PWA_DIR/sw.js" dist/sw.js

python3 - <<'PY'
from pathlib import Path
import re

path = Path("dist/index.html")
text = path.read_text()

text = re.sub(r"<title>.*?</title>", "<title>Espelunca</title>", text, count=1, flags=re.DOTALL)
text = re.sub(
    r'<meta\s+name="application-name"\s+content="[^"]*"\s*/?>',
    '<meta name="application-name" content="Espelunca">',
    text,
    count=1,
)

text = re.sub(
    r'<meta\s+name="theme-color"(?:\s+content="[^"]*")?\s*/?>',
    '<meta name="theme-color" content="#006AFF">',
    text,
    count=1,
)

text = re.sub(r'\s*<link\s+[^>]*rel="icon"[^>]*>', "", text, flags=re.IGNORECASE)
favicon = '<link rel="icon" type="image/svg+xml" href="/espelunca-icon.svg">'
if favicon not in text:
    text = text.replace("</head>", f"  {favicon}\n</head>", 1)

manifest_link = '<link rel="manifest" href="/manifest.json">'
if manifest_link not in text:
    text = text.replace("</head>", f"  {manifest_link}\n</head>", 1)

apple_icon = '<link rel="apple-touch-icon" sizes="192x192" href="/icons/icon-192.png">'
if apple_icon not in text:
    text = text.replace("</head>", f"  {apple_icon}\n</head>", 1)

for meta in [
    '<meta name="mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="black">',
]:
    if meta not in text:
        text = text.replace("</head>", f"  {meta}\n</head>", 1)

sw_script = """<script>
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', {scope: '/'}).catch(() => {})
  })
}
</script>"""
if "navigator.serviceWorker.register('/sw.js'" not in text:
    text = text.replace("</body>", f"  {sw_script}\n</body>", 1)

# Keep the PWA viewport explicit even if Expo changes the generated HTML template.
viewport = '<meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, viewport-fit=cover">'
text = re.sub(r'<meta\s+name="viewport"[^>]*>', viewport, text, count=1, flags=re.IGNORECASE)
if viewport not in text:
    text = text.replace("</head>", f"  {viewport}\n</head>", 1)

# Espelunca iOS PWA layout normalization
# WebKit has a known standalone-PWA regression where the viewport can fall back
# to a legacy desktop width (often ~980px) even though the device is narrower.
# This makes the whole React Native Web layout appear slightly/strongly zoomed
# and can also cause horizontal overflow. WebKit's documented workaround is to
# toggle the viewport meta to a flat device-width scale and then restore it.
ios_pwa_style = """<style id="espelunca-ios-pwa-layout">
@supports (-webkit-touch-callout: none) {
  html,
  body,
  #root {
    box-sizing: border-box;
    max-width: 100%;
    min-width: 0;
    overflow-x: hidden;
  }

  body {
    overflow-x: hidden;
  }

  @media (display-mode: standalone) {
    html,
    body,
    #root {
      width: 100%;
    }

    body {
      overflow-y: auto;
    }
  }
}
</style>"""
if 'id="espelunca-ios-pwa-layout"' not in text:
    text = text.replace("</head>", f"  {ios_pwa_style}\n</head>", 1)

ios_pwa_repair = r"""<script>
(() => {
  const isStandalone =
    (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
    window.navigator.standalone === true

  if (!isStandalone) return

  const viewport = document.querySelector('meta[name="viewport"]')
  if (!viewport) return

  const canonical =
    'width=device-width, initial-scale=1, minimum-scale=1, viewport-fit=cover'
  const repair = () => {
    const visualWidth = window.visualViewport?.width || 0
    const innerWidth = window.innerWidth || 0

    // When WebKit drops the mobile viewport it commonly reports a much wider
    // layout viewport than the visual viewport. Rebuild the viewport once.
    if (visualWidth > 0 && innerWidth > 0 && Math.abs(innerWidth - visualWidth) > 10) {
      const current = viewport.getAttribute('content') || canonical
      viewport.setAttribute(
        'content',
        'width=device-width, initial-scale=1, maximum-scale=1',
      )
      requestAnimationFrame(() => {
        window.setTimeout(() => {
          viewport.setAttribute('content', current || canonical)
          window.dispatchEvent(new Event('resize'))
        }, 50)
      })
    }
  }

  repair()
  window.addEventListener('pageshow', repair)
  window.addEventListener('resize', repair)
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) repair()
  })
})()
</script>"""
if "WebKit drops the mobile viewport" not in text:
    text = text.replace("</head>", f"  {ios_pwa_repair}\n</head>", 1)

path.write_text(text)
path.write_text(text)
PY

mkdir -p dist/static
ln -sfn ../_expo dist/static/_expo

echo "==> Build Web concluído."

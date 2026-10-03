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
PWA_DIR="${ROOT_DIR}/pwa"
if [[ ! -f "${PWA_DIR}/manifest.json" || ! -f "${PWA_DIR}/sw.js" ]]; then
  echo "ERRO: arquivos PWA ausentes em ${PWA_DIR}"
  exit 1
fi

mkdir -p dist/icons
cp "${PWA_DIR}/manifest.json" dist/manifest.json
cp "${PWA_DIR}/icons/icon-192.png" dist/icons/icon-192.png
cp "${PWA_DIR}/icons/icon-512.png" dist/icons/icon-512.png
cp "${PWA_DIR}/sw.js" dist/sw.js

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

path.write_text(text)
PY

mkdir -p dist/static
ln -sfn ../_expo dist/static/_expo

echo "==> Build Web concluído."

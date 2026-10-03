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

# Keep the PWA manifest branded as Espelunca when Expo emits one.
python3 - <<'PY'
from pathlib import Path
import json

path = Path("dist/manifest.json")
if path.exists():
    data = json.loads(path.read_text())
    data["name"] = "Espelunca"
    data["short_name"] = "Espelunca"
    data["icons"] = [
        {
            "src": "/espelunca-icon.svg",
            "sizes": "any",
            "type": "image/svg+xml",
        }
    ]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY

mkdir -p dist/static
ln -sfn ../_expo dist/static/_expo

echo "==> Build Web concluído."

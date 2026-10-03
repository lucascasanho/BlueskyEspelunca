#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP_HOSTNAME:?APP_HOSTNAME não definido}"
: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${INSTALL_DIR:?INSTALL_DIR não definido}"
: "${APP_DIR:?APP_DIR não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

echo "==> Instalando Node.js 24"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | ${SUDO} -E bash -
  ${SUDO} apt-get install -y nodejs
fi

echo "==> Ativando pnpm"
corepack enable
corepack prepare pnpm@11.23.0 --activate

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "==> Baixando social-app oficial"
  git clone https://github.com/bluesky-social/social-app.git "${APP_DIR}"
else
  echo "==> Atualizando social-app oficial"
  git -C "${APP_DIR}" fetch --prune origin
  git -C "${APP_DIR}" pull --ff-only
fi

cd "${APP_DIR}"

echo "==> Instalando dependências"
pnpm install --frozen-lockfile

echo "==> Aplicando configuração Espelunca"

python3 - "${PDS_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

pds = sys.argv[1]
path = Path("src/lib/constants.ts")
text = path.read_text()

text = text.replace(
    "export const BSKY_SERVICE = 'https://bsky.social'",
    f"export const BSKY_SERVICE = 'https://{pds}'",
)
text = text.replace(
    "export const BSKY_SERVICE_DID = 'did:web:bsky.social'",
    f"export const BSKY_SERVICE_DID = 'did:web:{pds}'",
)

path.write_text(text)
PY

python3 - "${APP_HOSTNAME}" <<'PY'
from pathlib import Path
import sys

host = sys.argv[1]
path = Path("app.config.js")
text = path.read_text()

text = text.replace("name: 'Bluesky'", "name: 'Espelunca'")
text = text.replace("slug: 'bluesky'", "slug: 'espelunca'")
text = text.replace("scheme: 'bluesky'", "scheme: 'espelunca'")
text = text.replace("bundleIdentifier: 'xyz.blueskyweb.app'", "bundleIdentifier: 'blue.espelunca.app'")
text = text.replace("package: 'xyz.blueskyweb.app'", "package: 'blue.espelunca.app'")
text = text.replace("'applinks:bsky.app',", f"'applinks:{host}',")
text = text.replace("host: 'bsky.app',", f"host: '{host}',")
path.write_text(text)
PY

# Expo's current social-app exposes a production web build through build-web.
# The generated dist directory is served locally by the dedicated systemd unit.
echo "==> Gerando Web build"
pnpm build-web

echo "==> Criando serviço Web"

cat <<EOF | ${SUDO} tee /etc/systemd/system/espelunca-web.service >/dev/null
[Unit]
Description=Espelunca Bluesky Web
After=network.target

[Service]
Type=simple
User=$(id -un)
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
ExecStart=/usr/bin/pnpx serve -s dist -l ${WEB_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable espelunca-web
${SUDO} systemctl restart espelunca-web

echo
echo "Web local: http://127.0.0.1:${WEB_PORT}"
echo "Host público esperado: https://${APP_HOSTNAME}"

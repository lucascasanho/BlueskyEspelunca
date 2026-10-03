#!/usr/bin/env bash
set -Eeuo pipefail

: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${INSTALL_DIR:?INSTALL_DIR não definido}"
: "${APP_DIR:?APP_DIR não definido}"
: "${WEB_PORT:?WEB_PORT não definido}"

WEB_SERVICE="espelunca-bluesky-web.service"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

if ! [[ "${WEB_PORT}" =~ ^[0-9]+$ ]] || (( WEB_PORT < 1024 || WEB_PORT > 65535 )); then
  echo "WEB_PORT inválida: ${WEB_PORT}"
  exit 1
fi

if [[ ! -f "/etc/systemd/system/${WEB_SERVICE}" ]] && ${SUDO} ss -ltnH "sport = :${WEB_PORT}" 2>/dev/null | grep -q .; then
  echo "ERRO: a porta local ${WEB_PORT} já está em uso."
  ${SUDO} ss -ltnp "sport = :${WEB_PORT}" || true
  exit 1
fi

echo "==> Instalando Node.js 24"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | ${SUDO} -E bash -
  ${SUDO} apt-get install -y nodejs
fi

echo "==> Ativando pnpm 11.23.0"
corepack enable
corepack prepare pnpm@11.23.0 --activate

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "==> Baixando social-app oficial"
  git clone https://github.com/bluesky-social/social-app.git "${APP_DIR}"
else
  echo "==> Atualizando social-app oficial"
  git -C "${APP_DIR}" fetch --prune origin
  git -C "${APP_DIR}" reset --hard origin/main
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

old_service = "export const BSKY_SERVICE = 'https://bsky.social'"
old_did = "export const BSKY_SERVICE_DID = 'did:web:bsky.social'"

if old_service not in text or old_did not in text:
    raise SystemExit("Não foi possível localizar os padrões atuais de BSKY_SERVICE no upstream.")

text = text.replace(old_service, f"export const BSKY_SERVICE = 'https://{pds}'")
text = text.replace(old_did, f"export const BSKY_SERVICE_DID = 'did:web:{pds}'")
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

echo "==> Gerando Web build"
pnpm build-web

echo "==> Instalando servidor estático"
${SUDO} npm install --global serve

SERVE_BIN="$(command -v serve || true)"
if [[ -z "${SERVE_BIN}" ]]; then
  echo "ERRO: o comando 'serve' não foi encontrado após a instalação."
  exit 1
fi

APP_USER="${SUDO_USER:-$(id -un)}"

cat <<EOF | ${SUDO} tee /etc/systemd/system/${WEB_SERVICE} >/dev/null
[Unit]
Description=Espelunca Bluesky Web
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
ExecStart=${SERVE_BIN} -s dist -l ${WEB_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable "${WEB_SERVICE}"
${SUDO} systemctl restart "${WEB_SERVICE}"

echo
echo "Web local: http://127.0.0.1:${WEB_PORT}"
echo "Host público esperado: https://${PDS_HOSTNAME}"

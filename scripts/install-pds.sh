#!/usr/bin/env bash
set -Eeuo pipefail

: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${PDS_ADMIN_EMAIL:?PDS_ADMIN_EMAIL não definido}"
: "${INSTALL_DIR:?INSTALL_DIR não definido}"
: "${PDS_DATA_DIR:?PDS_DATA_DIR não definido}"

if [[ "$(id -u)" -ne 0 ]]; then
  SUDO=sudo
else
  SUDO=
fi

if ! grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  echo "Aviso: este script foi projetado para WSL2, mas continuará em Linux."
fi

echo "==> Instalando dependências básicas"
${SUDO} apt-get update
${SUDO} apt-get install -y ca-certificates curl git jq openssl sqlite3 xxd lsb-release

if ! command -v docker >/dev/null 2>&1; then
  if [[ "${INSTALL_DOCKER:-true}" != "true" ]]; then
    echo "Docker não encontrado e INSTALL_DOCKER=false."
    exit 1
  fi

  echo "==> Instalando Docker Engine"
  ${SUDO} install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg |
    ${SUDO} gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

  ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg

  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" |
    ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null

  ${SUDO} apt-get update
  ${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

if ! docker info >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl enable --now docker || true
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker está instalado, mas o daemon não está acessível."
  echo "No WSL2 com systemd, verifique: sudo systemctl status docker"
  echo "Depois execute novamente: ./install.sh"
  exit 1
fi

echo "==> Criando diretórios"
${SUDO} mkdir -p "${INSTALL_DIR}" "${PDS_DATA_DIR}"
${SUDO} chmod 700 "${PDS_DATA_DIR}"

if [[ ! -d "${INSTALL_DIR}/pds-src/.git" ]]; then
  echo "==> Baixando PDS oficial"
  git clone https://github.com/bluesky-social/pds.git "${INSTALL_DIR}/pds-src"
else
  echo "==> PDS oficial já existe; atualizando"
  git -C "${INSTALL_DIR}/pds-src" fetch --tags --prune
  git -C "${INSTALL_DIR}/pds-src" pull --ff-only
fi

echo "==> Preparando configuração do PDS"

PDS_ADMIN_PASSWORD_FILE="${PDS_DATA_DIR}/.admin-password"
JWT_SECRET_FILE="${PDS_DATA_DIR}/.jwt-secret"
PLC_KEY_FILE="${PDS_DATA_DIR}/.plc-key"

if [[ ! -s "${PDS_ADMIN_PASSWORD_FILE}" ]]; then
  openssl rand -hex 24 | ${SUDO} tee "${PDS_ADMIN_PASSWORD_FILE}" >/dev/null
  ${SUDO} chmod 600 "${PDS_ADMIN_PASSWORD_FILE}"
fi

if [[ ! -s "${JWT_SECRET_FILE}" ]]; then
  openssl rand -hex 32 | ${SUDO} tee "${JWT_SECRET_FILE}" >/dev/null
  ${SUDO} chmod 600 "${JWT_SECRET_FILE}"
fi

if [[ ! -s "${PLC_KEY_FILE}" ]]; then
  openssl ecparam --name secp256k1 --genkey --noout --outform DER |
    tail --bytes=+8 | head --bytes=32 | xxd --plain --cols 32 |
    ${SUDO} tee "${PLC_KEY_FILE}" >/dev/null
  ${SUDO} chmod 600 "${PLC_KEY_FILE}"
fi

PDS_ADMIN_PASSWORD="$(${SUDO} cat "${PDS_ADMIN_PASSWORD_FILE}")"
JWT_SECRET="$(${SUDO} cat "${JWT_SECRET_FILE}")"
PLC_KEY="$(${SUDO} cat "${PLC_KEY_FILE}")"

${SUDO} mkdir -p "${PDS_DATA_DIR}/caddy/data" "${PDS_DATA_DIR}/caddy/etc/caddy"

cat <<EOF | ${SUDO} tee "${PDS_DATA_DIR}/pds.env" >/dev/null
PDS_HOSTNAME=${PDS_HOSTNAME}
PDS_JWT_SECRET=${JWT_SECRET}
PDS_ADMIN_PASSWORD=${PDS_ADMIN_PASSWORD}
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=${PLC_KEY}
PDS_DATA_DIRECTORY=${PDS_DATA_DIR}
PDS_BLOBSTORE_DISK_LOCATION=${PDS_DATA_DIR}/blocks
PDS_BLOB_UPLOAD_LIMIT=314572800
PDS_DID_PLC_URL=https://plc.directory
PDS_BSKY_APP_VIEW_URL=https://api.bsky.app
PDS_BSKY_APP_VIEW_DID=did:web:api.bsky.app
PDS_REPORT_SERVICE_URL=https://mod.bsky.app
PDS_REPORT_SERVICE_DID=did:plc:ar7c4by46qjdydhdevvrndac
PDS_CRAWLERS=https://bsky.network
LOG_ENABLED=true
PDS_RATE_LIMITS_ENABLED=true
PDS_INVITE_REQUIRED=true
EOF

${SUDO} chmod 600 "${PDS_DATA_DIR}/pds.env"

curl -fsSL https://raw.githubusercontent.com/bluesky-social/pds/main/compose.yaml |
  sed "s|/pds|${PDS_DATA_DIR}|g" |
  ${SUDO} tee "${PDS_DATA_DIR}/compose.yaml" >/dev/null

cat <<EOF | ${SUDO} tee "${PDS_DATA_DIR}/caddy/etc/caddy/Caddyfile" >/dev/null
{
  email ${PDS_ADMIN_EMAIL}
  on_demand_tls {
    ask http://localhost:3000/tls-check
  }
}

${PDS_HOSTNAME}, *.${PDS_HOSTNAME} {
  tls {
    on_demand
  }
  reverse_proxy http://localhost:3000
}
EOF

cat <<EOF | ${SUDO} tee /etc/systemd/system/espelunca-pds.service >/dev/null
[Unit]
Description=Espelunca Bluesky PDS
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${PDS_DATA_DIR}
ExecStart=/usr/bin/docker compose --file ${PDS_DATA_DIR}/compose.yaml up --detach
ExecStop=/usr/bin/docker compose --file ${PDS_DATA_DIR}/compose.yaml down

[Install]
WantedBy=multi-user.target
EOF

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable espelunca-pds
${SUDO} systemctl restart espelunca-pds

echo
echo "==> PDS iniciado"
echo "Dados: ${PDS_DATA_DIR}"
echo "Admin password armazenada em: ${PDS_ADMIN_PASSWORD_FILE}"
echo "Não publique esse arquivo."
echo

if [[ "${CREATE_INITIAL_ACCOUNT:-false}" == "true" ]]; then
  echo "Criação automática da conta inicial foi solicitada."
  echo "Por segurança, a criação será feita manualmente com pdsadmin após validar DNS/TLS."
fi

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

: "${PDS_HOSTNAME}"
: "${OZONE_HOSTNAME}"
: "${OZONE_PORT}"
: "${OZONE_DB_PORT}"
: "${OZONE_DATA_DIR}"
: "${OZONE_SERVICE_ACCOUNT_HANDLE}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

command -v docker >/dev/null 2>&1 || {
  echo "Docker não encontrado. Execute a instalação principal primeiro."
  exit 1
}

echo "==> Resolvendo @${OZONE_SERVICE_ACCOUNT_HANDLE}"
SERVICE_DID="$(
  curl --fail --silent --show-error \
    "https://api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=${OZONE_SERVICE_ACCOUNT_HANDLE}" |
    jq --raw-output '.did'
)"

if [[ -z "${SERVICE_DID}" || "${SERVICE_DID}" == "null" ]]; then
  echo "Não foi possível resolver a conta do serviço."
  echo "Crie primeiro @${OZONE_SERVICE_ACCOUNT_HANDLE} e tente novamente."
  exit 1
fi

${SUDO} mkdir -p "${OZONE_DATA_DIR}/postgres"
${SUDO} chmod 700 "${OZONE_DATA_DIR}"

ADMIN_PASSWORD_FILE="${OZONE_DATA_DIR}/.admin-password"
SIGNING_KEY_FILE="${OZONE_DATA_DIR}/.signing-key-hex"
POSTGRES_PASSWORD_FILE="${OZONE_DATA_DIR}/.postgres-password"
OZONE_ENV_FILE="${OZONE_DATA_DIR}/ozone.env"
POSTGRES_ENV_FILE="${OZONE_DATA_DIR}/postgres.env"
COMPOSE_FILE="${OZONE_DATA_DIR}/compose.yaml"

if [[ ! -s "${ADMIN_PASSWORD_FILE}" ]]; then
  openssl rand -hex 24 | ${SUDO} tee "${ADMIN_PASSWORD_FILE}" >/dev/null
  ${SUDO} chmod 600 "${ADMIN_PASSWORD_FILE}"
fi
if [[ ! -s "${SIGNING_KEY_FILE}" ]]; then
  openssl ecparam --name secp256k1 --genkey --noout --outform DER |
    tail --bytes=+8 | head --bytes=32 | xxd --plain --cols 32 |
    ${SUDO} tee "${SIGNING_KEY_FILE}" >/dev/null
  ${SUDO} chmod 600 "${SIGNING_KEY_FILE}"
fi
if [[ ! -s "${POSTGRES_PASSWORD_FILE}" ]]; then
  openssl rand -hex 24 | ${SUDO} tee "${POSTGRES_PASSWORD_FILE}" >/dev/null
  ${SUDO} chmod 600 "${POSTGRES_PASSWORD_FILE}"
fi

OZONE_ADMIN_PASSWORD="$(${SUDO} cat "${ADMIN_PASSWORD_FILE}")"
OZONE_SIGNING_KEY_HEX="$(${SUDO} cat "${SIGNING_KEY_FILE}")"
POSTGRES_PASSWORD="$(${SUDO} cat "${POSTGRES_PASSWORD_FILE}")"
ADMIN_DIDS="${SERVICE_DID}${OZONE_ADMIN_DIDS_EXTRA:+,${OZONE_ADMIN_DIDS_EXTRA}}"

cat <<EOF | ${SUDO} tee "${POSTGRES_ENV_FILE}" >/dev/null
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=ozone
EOF
${SUDO} chmod 600 "${POSTGRES_ENV_FILE}"

cat <<EOF | ${SUDO} tee "${OZONE_ENV_FILE}" >/dev/null
NODE_ENV=production
OZONE_PORT=${OZONE_PORT}
OZONE_SERVER_DID=${SERVICE_DID}
OZONE_PUBLIC_URL=https://${OZONE_HOSTNAME}
OZONE_ADMIN_DIDS=${ADMIN_DIDS}
OZONE_ADMIN_PASSWORD=${OZONE_ADMIN_PASSWORD}
OZONE_SIGNING_KEY_HEX=${OZONE_SIGNING_KEY_HEX}
OZONE_DB_POSTGRES_URL=postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:${OZONE_DB_PORT}/ozone
OZONE_DB_MIGRATE=1
OZONE_DID_PLC_URL=https://plc.directory
OZONE_APPVIEW_URL=https://api.bsky.app
OZONE_APPVIEW_DID=did:web:api.bsky.app
OZONE_PDS_URL=https://${PDS_HOSTNAME}
OZONE_PDS_DID=did:web:${PDS_HOSTNAME}
OZONE_JETSTREAM_URL=https://jetstream.us-east.bsky.network
LOG_ENABLED=1
EOF
${SUDO} chmod 600 "${OZONE_ENV_FILE}"

cp "${ROOT_DIR}/deploy/ozone-compose.yaml" "${COMPOSE_FILE}"
${SUDO} chmod 600 "${COMPOSE_FILE}"

cat <<EOF | ${SUDO} tee /etc/systemd/system/espelunca-ozone.service >/dev/null
[Unit]
Description=Espelunca Bluesky Ozone Labeler
Documentation=https://github.com/bluesky-social/ozone
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${OZONE_DATA_DIR}
ExecStart=/usr/bin/docker compose --file ${COMPOSE_FILE} up --detach
ExecStop=/usr/bin/docker compose --file ${COMPOSE_FILE} down

[Install]
WantedBy=multi-user.target
EOF

${SUDO} systemctl daemon-reload
${SUDO} systemctl enable espelunca-ozone
${SUDO} docker compose --file "${COMPOSE_FILE}" pull
${SUDO} systemctl restart espelunca-ozone

update_local() {
  local key="\$1" value="\$2"
  if grep -q "^${key}=" "${ROOT_DIR}/config.env"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ROOT_DIR}/config.env"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ROOT_DIR}/config.env"
  fi
}

update_local "ESPELUNCA_LABELER_DID" "${SERVICE_DID}"
update_local "OZONE_ENABLED" "true"
update_local "OZONE_TUNNEL_ENABLED" "true"

echo
echo "Ozone instalado."
echo "URL: https://${OZONE_HOSTNAME}"
echo "Conta do Labeler: @${OZONE_SERVICE_ACCOUNT_HANDLE}"
echo "DID: ${SERVICE_DID}"
echo "Chave: ${SIGNING_KEY_FILE}"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

read -r -p "Handle (sem @, ex.: luc): " HANDLE
read -r -p "E-mail: " EMAIL
read -r -s -p "Senha: " PASSWORD
echo

FULL_HANDLE="${HANDLE}.${PDS_HOSTNAME}"
ADMIN_PASSWORD="$(sudo cat "${PDS_DATA_DIR}/.admin-password")"

echo "Criando conta ${FULL_HANDLE}..."

sudo docker exec -e PDS_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  pds goat pds admin account create \
  --pds-host "http://127.0.0.1:${PDS_PORT}" \
  --handle "${FULL_HANDLE}" \
  --email "${EMAIL}" \
  --password "${PASSWORD}"

echo
echo "Conta criada: @${FULL_HANDLE}"

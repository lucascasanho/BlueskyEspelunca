#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

read -r -p "Handle (sem @, ex.: luc): " HANDLE
read -r -p "E-mail: " EMAIL
read -r -s -p "Senha: " PASSWORD
echo

FULL_HANDLE="${HANDLE}.${PDS_HOSTNAME}"

echo "Criando conta ${FULL_HANDLE}..."

docker exec -e PDS_ADMIN_PASSWORD="$(sudo cat "${PDS_DATA_DIR}/.admin-password")"   pds goat pds admin account create   --handle "${FULL_HANDLE}"   --email "${EMAIL}"   --password "${PASSWORD}"

echo
echo "Conta criada: @${FULL_HANDLE}"

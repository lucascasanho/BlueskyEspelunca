#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "config.env não existe: ${CONFIG_FILE}"
  exit 1
fi

set -a
source "${CONFIG_FILE}"
set +a

: "${PDS_DATA_DIR:?PDS_DATA_DIR não definido}"
: "${INSTALL_DIR:?INSTALL_DIR não definido}"
: "${PDS_PORT:?PDS_PORT não definido}"

PATCH_ENTRYPOINT="${ROOT_DIR}/patches/pds/entrypoint.sh"

if [[ ! -f "${PATCH_ENTRYPOINT}" ]]; then
  echo "ERRO: entrypoint personalizado do PDS não encontrado: ${PATCH_ENTRYPOINT}"
  exit 1
fi

chmod +x "${PATCH_ENTRYPOINT}"

if [[ "$(id -u)" -ne 0 ]]; then SUDO=sudo; else SUDO=; fi

COMPOSE_FILE="${PDS_DATA_DIR}/compose.yaml"

echo "==> Atualizando compose do PDS"

cat <<EOF | ${SUDO} tee "${COMPOSE_FILE}" >/dev/null
services:
  pds:
    container_name: pds
    image: ghcr.io/bluesky-social/pds:0.4
    network_mode: host
    restart: unless-stopped
    volumes:
      - type: bind
        source: ${PDS_DATA_DIR}
        target: /pds
      - type: bind
        source: ${PATCH_ENTRYPOINT}
        target: /usr/local/bin/espelunca-pds-entrypoint.sh
        read_only: true
    env_file:
      - ${PDS_DATA_DIR}/pds.env
    entrypoint:
      - /usr/local/bin/espelunca-pds-entrypoint.sh
    command:
      - node
      - --enable-source-maps
      - index.ts

  watchtower:
    container_name: espelunca-pds-watchtower
    image: ghcr.io/nicholas-fedor/watchtower:latest
    network_mode: host
    volumes:
      - type: bind
        source: /var/run/docker.sock
        target: /var/run/docker.sock
    restart: unless-stopped
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_SCHEDULE: "@midnight"
EOF

echo "Compose atualizado: ${COMPOSE_FILE}"

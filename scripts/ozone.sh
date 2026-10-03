#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "${ROOT_DIR}/config.env"
set +a

SERVICE="espelunca-ozone.service"
DATA_DIR="${OZONE_DATA_DIR:-${INSTALL_DIR}/ozone-data}"
COMPOSE_FILE="${DATA_DIR}/compose.yaml"

case "${1:-}" in
  install) exec bash "${ROOT_DIR}/scripts/install-ozone.sh" ;;
  start) sudo systemctl start "${SERVICE}" ;;
  stop) sudo systemctl stop "${SERVICE}" ;;
  restart) sudo systemctl restart "${SERVICE}" ;;
  status)
    echo "Ozone: https://${OZONE_HOSTNAME:-ozone.${PDS_HOSTNAME}}"
    echo "Local: http://127.0.0.1:${OZONE_PORT:-3300}"
    sudo systemctl --no-pager --full status "${SERVICE}" || true
    sudo docker ps --filter "name=espelunca-ozone" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
    if curl -fsS --max-time 10 "http://127.0.0.1:${OZONE_PORT:-3300}/xrpc/_health" >/dev/null; then
      echo "Ozone local: OK"
    else
      echo "Ozone local: FALHA"
    fi
    ;;
  logs) sudo docker logs --tail 200 espelunca-ozone ;;
  update)
    [[ -f "${COMPOSE_FILE}" ]] || { echo "Ozone ainda não foi instalado."; exit 1; }
    sudo docker compose --file "${COMPOSE_FILE}" pull
    sudo systemctl restart "${SERVICE}"
    ;;
  ""|-h|--help|help)
    echo "Uso: bluesky ozone {install|start|stop|restart|status|logs|update}"
    ;;
  *) echo "Comando desconhecido: ${1}"; exit 2 ;;
esac

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
FEED_SERVICE="${FEEDGEN_SERVICE:-espelunca-bluesky-feed.service}"
FEED_DIR="${FEEDGEN_INSTALL_DIR:-${INSTALL_DIR}/feed-generator}"
FEED_ENV_FILE="${FEEDGEN_ENV_FILE:-${INSTALL_DIR}/feed.env}"
FEED_PORT="${FEEDGEN_PORT:-3200}"

case "${1:-}" in
  install) exec "${ROOT_DIR}/scripts/install-feed-generator.sh" ;;
  start) sudo systemctl start "${FEED_SERVICE}" ;;
  stop) sudo systemctl stop "${FEED_SERVICE}" ;;
  restart) sudo systemctl restart "${FEED_SERVICE}" ;;
  status)
    sudo systemctl --no-pager --full status "${FEED_SERVICE}" || true
    echo
    curl -fsS --max-time 10 "http://127.0.0.1:${FEED_PORT}/health" || true
    echo
    ;;
  logs) sudo journalctl -u "${FEED_SERVICE}" -n 100 --no-pager ;;
  publish)
    source "${FEED_ENV_FILE}"
    sudo env PDS_SERVICE="https://${PDS_HOSTNAME}" FEEDGEN_HOSTNAME="${FEEDGEN_HOSTNAME}" FEEDGEN_SERVICE_DID="${FEEDGEN_SERVICE_DID}" FEEDGEN_RECORD_NAME="${FEEDGEN_RECORD_NAME}" FEEDGEN_DISPLAY_NAME="${FEEDGEN_DISPLAY_NAME}" FEEDGEN_DESCRIPTION="${FEEDGEN_DESCRIPTION}" FEEDGEN_ENV_FILE="${FEED_ENV_FILE}" FEEDGEN_INSTALL_DIR="${FEED_DIR}" node "${FEED_DIR}/feed.mjs" publish
    sudo systemctl restart "${FEED_SERVICE}"
    ;;
  seed)
    source "${FEED_ENV_FILE}"
    sudo -u espelunca env FEEDGEN_APPVIEW_URL="${FEEDGEN_APPVIEW_URL}" FEEDGEN_SQLITE_LOCATION="${FEEDGEN_SQLITE_LOCATION}" FEEDGEN_DATA_DIR="${FEED_DATA_DIR}" FEEDGEN_ENV_FILE="${FEED_ENV_FILE}" FEEDGEN_SEED_LIMIT="${FEEDGEN_SEED_LIMIT:-100}" node "${FEED_DIR}/feed.mjs" seed
    ;;
  tunnel) exec "${ROOT_DIR}/scripts/configure-feed-tunnel.sh" ;;
  *)
    echo "Uso: bluesky feed {install|start|stop|restart|status|logs|publish|seed|tunnel}"
    exit 2
    ;;
esac

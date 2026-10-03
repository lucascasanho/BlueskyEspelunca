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

echo "============================================================"
echo " BLUESKY ESPELUNCA — STATUS"
echo "============================================================"
echo
echo "PDS: https://${PDS_HOSTNAME}"
echo "Web: https://${PDS_HOSTNAME}"
echo "Feed: https://${FEEDGEN_HOSTNAME:-feeds.${PDS_HOSTNAME}}"
echo "PDS local: http://127.0.0.1:${PDS_PORT}"
echo "Web local: http://127.0.0.1:${WEB_PORT}"
if [[ "${OZONE_ENABLED:-false}" == "true" ]]; then
  echo "Ozone: https://${OZONE_HOSTNAME:-ozone.${PDS_HOSTNAME}}"
  echo "Ozone local: http://127.0.0.1:${OZONE_PORT:-3300}"
fi
echo

echo "--- systemd ---"
sudo systemctl --no-pager --full status espelunca-pds || true
sudo systemctl --no-pager --full status espelunca-bluesky-web || true
sudo systemctl --no-pager --full status ${FEEDGEN_SERVICE:-espelunca-bluesky-feed.service} || true
if [[ "${OZONE_ENABLED:-false}" == "true" ]]; then
  sudo systemctl --no-pager --full status espelunca-ozone || true
fi

echo
echo "--- containers ---"
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true

echo
echo "--- PDS health local ---"
if curl -fsS --max-time 10 "http://127.0.0.1:${PDS_PORT}/xrpc/_health"; then
  echo
  echo "PDS local: OK"
else
  echo
  echo "PDS local: FALHA"
fi

echo
if [[ "${OZONE_ENABLED:-false}" == "true" ]]; then
  echo
  echo "--- Ozone health local ---"
  if curl -fsS --max-time 10 "http://127.0.0.1:${OZONE_PORT:-3300}/xrpc/_health" >/dev/null; then
    echo "Ozone local: OK"
  else
    echo "Ozone local: FALHA"
  fi
fi

echo "--- Web local ---"
if curl -fsSI --max-time 10 "http://127.0.0.1:${WEB_PORT}/" >/dev/null; then
  echo "Web local: OK"
else
  echo "Web local: FALHA"
fi

echo
echo "--- portas ---"
sudo ss -ltnp "sport = :${PDS_PORT}" || true
sudo ss -ltnp "sport = :${WEB_PORT}" || true
sudo ss -ltnp "sport = :${FEEDGEN_PORT:-3200}" || true
if [[ "${OZONE_ENABLED:-false}" == "true" ]]; then
  sudo ss -ltnp "sport = :${OZONE_PORT:-3300}" || true
fi

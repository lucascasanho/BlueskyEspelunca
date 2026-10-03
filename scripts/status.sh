#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"

echo "============================================================"
echo " BLUESKY ESPELUNCA — STATUS"
echo "============================================================"
echo
echo "PDS: https://${PDS_HOSTNAME}"
echo "Web: https://${APP_HOSTNAME}"
echo "PDS local: http://127.0.0.1:${PDS_PORT}"
echo "Web local: http://127.0.0.1:${WEB_PORT}"
echo

echo "--- systemd ---"
sudo systemctl --no-pager --full status espelunca-pds || true
sudo systemctl --no-pager --full status espelunca-web || true

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

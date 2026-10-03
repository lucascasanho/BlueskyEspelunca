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
echo

echo "--- systemd ---"
sudo systemctl --no-pager --full status espelunca-pds || true
sudo systemctl --no-pager --full status espelunca-web || true

echo
echo "--- containers ---"
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true

echo
echo "--- PDS health local ---"
curl -kfsS --max-time 10 "https://127.0.0.1/xrpc/_health" || true
echo
echo

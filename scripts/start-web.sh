#!/usr/bin/env bash
set -Eeuo pipefail
sudo systemctl start espelunca-web
sudo systemctl status espelunca-web --no-pager

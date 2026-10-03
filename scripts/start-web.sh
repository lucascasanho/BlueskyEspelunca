#!/usr/bin/env bash
set -Eeuo pipefail

sudo systemctl start espelunca-bluesky-web
sudo systemctl status espelunca-bluesky-web --no-pager

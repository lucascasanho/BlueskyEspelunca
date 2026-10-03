#!/bin/sh
set -eu

# Espelunca customizations for the official Bluesky PDS image.
# The official image can be replaced by Watchtower, so these changes must be
# reapplied every time the container starts.

echo "==> Aplicando customizações do PDS da Espelunca"

# Allow the PDS service hostname itself (e.g. espelunca.blue) to resolve as
# an external/custom handle. The upstream PDS treats the bare service hostname
# as a local handle and rejects it before DNS/HTTP resolution.
for file in /app/node_modules/.pnpm/@atproto+pds@*/node_modules/@atproto/pds/dist/api/com/atproto/identity/resolveHandle.js; do
  [ -f "$file" ] || continue
  sed -i 's/handle\.endsWith(host) || handle === host\.slice(1)/handle.endsWith(host)/' "$file"
done

# Some browser contexts can legitimately omit Sec-Fetch-Site on the initial
# OAuth authorization navigation. The authorization endpoint is GET-only;
# consent/rejection API calls remain protected by their same-origin checks.
# Permit a missing value while keeping all supplied values validated.
for file in /app/node_modules/.pnpm/@atproto+oauth-provider@*/node_modules/@atproto/oauth-provider/dist/router/create-authorization-page-middleware.js; do
  [ -f "$file" ] || continue
  sed -i "s/validateFetchSite(req, \['same-origin', 'same-site', 'cross-site', 'none'\])/validateFetchSite(req, [null, 'same-origin', 'same-site', 'cross-site', 'none'])/" "$file"
done

exec /usr/bin/dumb-init -- "$@"

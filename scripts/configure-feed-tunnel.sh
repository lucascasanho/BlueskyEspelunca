#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/home/espelunca/.cloudflared/config.yml"
SERVICE="cloudflared-espelunca.service"
BACKUP="${CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"

[[ -f "${CONFIG}" ]] || { echo "Arquivo não encontrado: ${CONFIG}"; exit 1; }
command -v cloudflared >/dev/null 2>&1 || { echo "cloudflared não encontrado."; exit 1; }

sudo cp "${CONFIG}" "${BACKUP}"

python3 - "${CONFIG}" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
lines = p.read_text().splitlines()
try:
    i = next(i for i, line in enumerate(lines) if line.strip() == "ingress:")
except StopIteration:
    raise SystemExit("ingress: não encontrado")

prefix = lines[:i+1]
rest = lines[i+1:]

out = []
removed = False
j = 0
while j < len(rest):
    line = rest[j]
    if line.startswith("  - hostname: feeds.espelunca.blue"):
        removed = True
        j += 1
        while j < len(rest) and not rest[j].startswith("  - "):
            j += 1
        continue
    out.append(line)
    j += 1

catch = []
for k, line in enumerate(out):
    if line.startswith("  - service: http_status:404"):
        catch = out[k:]
        out = out[:k]
        break

rule = [
    "  - hostname: feeds.espelunca.blue",
    "    service: http://127.0.0.1:3200",
]
p.write_text("\n".join(prefix + rule + out + catch) + "\n")
PY

cloudflared tunnel --config "${CONFIG}" ingress validate
sudo systemctl restart "${SERVICE}"

echo "Rota do Feed instalada: https://feeds.espelunca.blue -> http://127.0.0.1:3200"
echo "Backup: ${BACKUP}"

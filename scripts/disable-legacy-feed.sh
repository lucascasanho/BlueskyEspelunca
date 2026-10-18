#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then echo "config.env não existe: ${CONFIG_FILE}" >&2; exit 1; fi
set -a; source "${CONFIG_FILE}"; set +a
: "${INSTALL_DIR:?INSTALL_DIR não definido}"
FEED_HOST="${FEEDGEN_HOSTNAME:-feeds.${PDS_HOSTNAME}}"
FEED_SERVICE="${FEEDGEN_SERVICE:-espelunca-bluesky-feed.service}"
FEED_DIR="${FEEDGEN_INSTALL_DIR:-${INSTALL_DIR}/feed-generator}"
FEED_DATA_DIR="${FEEDGEN_DATA_DIR:-${INSTALL_DIR}/feed-data}"
FEED_ENV_FILE="${FEEDGEN_ENV_FILE:-${INSTALL_DIR}/feed.env}"
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-/home/espelunca/.cloudflared/config.yml}"
CLOUDFLARED_SERVICE="${CLOUDFLARED_SERVICE:-cloudflared-espelunca.service}"
PUBLISHER_DID="did:plc:kafjdndx54b3wdlu6cbiwk42"
RECORD_NAME="espelunca-br"
PENDING_MARKER="${ROOT_DIR}/.feed-unpublish-pending"
if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi
echo "==> Interrompendo e removendo o Feed Generator antigo"
if [[ "${FEED_SERVICE}" =~ ^[A-Za-z0-9_.@-]+\.service$ ]]; then
  ${SUDO} systemctl disable --now "${FEED_SERVICE}" >/dev/null 2>&1 || true
  ${SUDO} rm -f -- "/etc/systemd/system/${FEED_SERVICE}"
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl reset-failed "${FEED_SERVICE}" >/dev/null 2>&1 || true
else echo "AVISO: nome de serviço inesperado; não removido: ${FEED_SERVICE}" >&2
fi
SAFE_ROOT="$(realpath -m -- "${INSTALL_DIR}")"
remove_feed_path() {
  local path="$1" expected_leaf="$2" resolved
  resolved="$(realpath -m -- "${path}")"
  if [[ "${resolved}" == "${SAFE_ROOT}/"* && "$(basename -- "${resolved}")" == "${expected_leaf}" ]]; then
    ${SUDO} rm -rf -- "${resolved}"
    echo "Removido: ${resolved}"
  else echo "AVISO: caminho fora dos limites esperados, mantido: ${resolved}" >&2
  fi
}
remove_feed_path "${FEED_DIR}" "feed-generator"
remove_feed_path "${FEED_DATA_DIR}" "feed-data"
remove_feed_path "${FEED_ENV_FILE}" "feed.env"
if [[ -f "${CLOUDFLARED_CONFIG}" ]]; then
  if ! command -v cloudflared >/dev/null 2>&1; then echo "AVISO: cloudflared não encontrado; a rota não foi alterada." >&2
  else
    TMP_CONFIG="$(mktemp "${CLOUDFLARED_CONFIG}.retire.XXXXXX")"
    trap 'rm -f -- "${TMP_CONFIG}"' EXIT
    ${SUDO} cp -- "${CLOUDFLARED_CONFIG}" "${TMP_CONFIG}"
    python3 - "${TMP_CONFIG}" "${FEED_HOST}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1]); feed_host = sys.argv[2]; lines = path.read_text().splitlines()
try: ingress_index = next(i for i, line in enumerate(lines) if line.strip() == "ingress:")
except StopIteration: raise SystemExit("ingress: não encontrado; configuração original preservada.")
prefix = lines[:ingress_index + 1]; existing = lines[ingress_index + 1:]; filtered = []; i = 0
while i < len(existing):
    line = existing[i]
    if line.startswith("  - hostname:"):
        host = line.split(":", 1)[1].strip().strip('"').strip("'")
        if host == feed_host:
            i += 1
            while i < len(existing) and not existing[i].startswith("  - "): i += 1
            continue
    filtered.append(line); i += 1
catch = []
for i, line in enumerate(filtered):
    if line.startswith("  - service: http_status:404"):
        catch = filtered[i:]; filtered = filtered[:i]; break
rule = ["  - hostname: {}".format(feed_host), "    service: http_status:404"]
path.write_text("\n".join(prefix + rule + filtered + catch) + "\n")
PY
    if cloudflared tunnel --config "${TMP_CONFIG}" ingress validate; then
      BACKUP="${CLOUDFLARED_CONFIG}.bak.feed-retired.$(date +%Y%m%d-%H%M%S)"
      ${SUDO} cp -- "${CLOUDFLARED_CONFIG}" "${BACKUP}"
      ${SUDO} cp -- "${TMP_CONFIG}" "${CLOUDFLARED_CONFIG}"
      if ${SUDO} systemctl restart "${CLOUDFLARED_SERVICE}" && ${SUDO} systemctl is-active --quiet "${CLOUDFLARED_SERVICE}"; then
        echo "Rota desativada: https://${FEED_HOST} -> HTTP 404"; echo "Backup: ${BACKUP}"
      else
        echo "ERRO: Tunnel não reiniciou; restaurando o backup." >&2
        ${SUDO} cp -- "${BACKUP}" "${CLOUDFLARED_CONFIG}"; ${SUDO} systemctl restart "${CLOUDFLARED_SERVICE}" || true
      fi
    else echo "AVISO: validação do Tunnel falhou; configuração original preservada." >&2
    fi
    rm -f -- "${TMP_CONFIG}"; trap - EXIT
  fi
else echo "AVISO: arquivo do Tunnel não encontrado: ${CLOUDFLARED_CONFIG}" >&2
fi
if ! command -v node >/dev/null 2>&1; then touch "${PENDING_MARKER}"; echo "AVISO: Node.js não disponível; registro público não verificado." >&2; exit 0; fi
set +e
RECORD_STATUS="$(node "${ROOT_DIR}/scripts/unpublish-feed-record.mjs" --check "${PUBLISHER_DID}" "${RECORD_NAME}" 2>/dev/null)"; CHECK_STATUS=$?
set -e
if [[ ${CHECK_STATUS} -eq 0 && "${RECORD_STATUS}" == "record-absent" ]]; then rm -f -- "${PENDING_MARKER}"; echo "Registro público do feed: já removido."; exit 0; fi
touch "${PENDING_MARKER}"
if [[ ! -t 0 || ! -t 1 ]]; then echo "AVISO: registro público ainda existe ou não pôde ser verificado. Execute 'bluesky update' em um terminal para tentar removê-lo." >&2; exit 0; fi
echo; echo "O serviço local já foi desativado. O registro público ainda pode estar publicado."
echo "Para removê-lo, autentique a conta dona do registro ${PUBLISHER_DID}."
read -r -p "Handle da conta publicadora [@espelunca.blue]: " PUBLISHER_HANDLE
PUBLISHER_HANDLE="${PUBLISHER_HANDLE:-@espelunca.blue}"
read -r -s -p "App Password da conta (não será armazenada): " PUBLISHER_PASSWORD; printf '\n'
if [[ -z "${PUBLISHER_PASSWORD}" ]]; then unset PUBLISHER_PASSWORD; echo "Remoção pública pulada; desativação local concluída."; exit 0; fi
set +e
printf '%s\0%s\0' "${PUBLISHER_HANDLE}" "${PUBLISHER_PASSWORD}" | node "${ROOT_DIR}/scripts/unpublish-feed-record.mjs" "${PUBLISHER_DID}" "${RECORD_NAME}"; UNPUBLISH_STATUS=$?
set -e; unset PUBLISHER_PASSWORD
if [[ ${UNPUBLISH_STATUS} -eq 0 ]]; then rm -f -- "${PENDING_MARKER}"; echo "Registro público do feed removido."
else echo "AVISO: registro público não removido; interface e serviço continuam desativados." >&2; fi
echo "Desativação local do Feed Generator concluída."

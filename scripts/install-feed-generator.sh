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

FEED_HOST="${FEEDGEN_HOSTNAME:-feeds.${PDS_HOSTNAME}}"
FEED_PORT="${FEEDGEN_PORT:-3200}"
FEED_DIR="${FEEDGEN_INSTALL_DIR:-${INSTALL_DIR}/feed-generator}"
FEED_DATA_DIR="${FEEDGEN_DATA_DIR:-${INSTALL_DIR}/feed-data}"
FEED_ENV_FILE="${FEEDGEN_ENV_FILE:-${INSTALL_DIR}/feed.env}"
FEED_SERVICE="${FEEDGEN_SERVICE:-espelunca-bluesky-feed.service}"
FEED_DID="${FEEDGEN_SERVICE_DID:-did:web:${FEED_HOST}}"
FEED_RECORD="${FEEDGEN_RECORD_NAME:-espelunca-br}"
FEED_NAME="${FEEDGEN_DISPLAY_NAME:-Espelunca}"
FEED_DESCRIPTION="${FEEDGEN_DESCRIPTION:-Feed em PT-BR da Espelunca.blue.}"
EXISTING_PUBLISHER_DID=""
if [[ -f "${FEED_ENV_FILE}" ]]; then
  EXISTING_PUBLISHER_DID="$(sed -n 's/^FEEDGEN_PUBLISHER_DID=//p' "${FEED_ENV_FILE}" | head -n1)"
fi
PUBLISHER_DID="${FEEDGEN_PUBLISHER_DID:-${EXISTING_PUBLISHER_DID}}"
JETSTREAM="${FEEDGEN_JETSTREAM_URL:-https://jetstream.us-east.bsky.network}"
APPVIEW="${FEEDGEN_APPVIEW_URL:-https://api.bsky.app}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js não encontrado. Instale Node.js 22.12+ antes de instalar o Feed."
  exit 1
fi
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
NODE_MINOR="$(node -p 'Number(process.versions.node.split(".")[1])')"
if (( NODE_MAJOR < 22 || (NODE_MAJOR == 22 && NODE_MINOR < 12) )); then
  echo "Node.js $(node -p 'process.versions.node') encontrado; o Feed exige Node.js 22.12+."
  exit 1
fi
command -v npm >/dev/null 2>&1 || { echo "npm não encontrado."; exit 1; }

${SUDO} mkdir -p "${FEED_DIR}" "${FEED_DATA_DIR}"
${SUDO} cp -a "${ROOT_DIR}/feed-generator/." "${FEED_DIR}/"
${SUDO} chown -R espelunca:espelunca "${FEED_DIR}" "${FEED_DATA_DIR}"
${SUDO} systemctl stop "${FEED_SERVICE}" 2>/dev/null || true

cd "${FEED_DIR}"
if ! sudo -u espelunca npm install --omit=dev; then
  echo "npm install falhou. Instalando ferramentas de compilação para better-sqlite3."
  ${SUDO} apt-get update
  ${SUDO} apt-get install -y build-essential python3
  sudo -u espelunca npm install --omit=dev
fi

${SUDO} mkdir -p "${FEED_DATA_DIR}/hf-cache"
${SUDO} chown -R espelunca:espelunca "${FEED_DIR}" "${FEED_DATA_DIR}"

${SUDO} tee "${FEED_ENV_FILE}" >/dev/null <<ENV
PDS_SERVICE=https://${PDS_HOSTNAME}
FEEDGEN_LISTENHOST=127.0.0.1
FEEDGEN_PORT=${FEED_PORT}
FEEDGEN_HOSTNAME=${FEED_HOST}
FEEDGEN_SERVICE_DID=${FEED_DID}
FEEDGEN_RECORD_NAME=${FEED_RECORD}
FEEDGEN_DISPLAY_NAME="${FEED_NAME}"
FEEDGEN_DESCRIPTION="${FEED_DESCRIPTION}"
FEEDGEN_PUBLISHER_DID=${PUBLISHER_DID}
FEEDGEN_SQLITE_LOCATION=${FEED_DATA_DIR}/feed.sqlite
FEEDGEN_MODEL_CACHE=${FEED_DATA_DIR}/hf-cache
FEEDGEN_JETSTREAM_URL=${JETSTREAM}
FEEDGEN_APPVIEW_URL=${APPVIEW}
FEEDGEN_MODEL_DEVICE=${FEEDGEN_MODEL_DEVICE:-cpu}
TOXICITY_MODEL=onnx-community/distilbert-multilingual-toxicity-classifier-ONNX
TOXICITY_THRESHOLD=0.72
AI_MEDIA_MODEL=onnx-community/ai-image-detect-distilled-ONNX
AI_MEDIA_THRESHOLD=0.80
AI_MEDIA_UNKNOWN_ACTION=drop
FEEDGEN_RETENTION_DAYS=7
FEEDGEN_WORKER_INTERVAL_MS=100
ENV
${SUDO} chown root:espelunca "${FEED_ENV_FILE}"
${SUDO} chmod 640 "${FEED_ENV_FILE}"
${SUDO} cp "${FEED_DIR}/systemd.service.template" "/etc/systemd/system/${FEED_SERVICE}"
${SUDO} sed -i "s#^EnvironmentFile=.*#EnvironmentFile=-${FEED_ENV_FILE}#" "/etc/systemd/system/${FEED_SERVICE}"
${SUDO} systemctl daemon-reload
${SUDO} systemctl enable "${FEED_SERVICE}"
${SUDO} systemctl start "${FEED_SERVICE}"

sleep 2
if ! ${SUDO} systemctl is-active --quiet "${FEED_SERVICE}"; then
  echo "ERRO: serviço ${FEED_SERVICE} não iniciou."
  ${SUDO} systemctl --no-pager --full status "${FEED_SERVICE}" || true
  exit 1
fi

if ! curl -fsS --max-time 10 "http://127.0.0.1:${FEED_PORT}/health" >/dev/null; then
  echo "AVISO: /health ainda não respondeu. O primeiro início pode estar baixando modelos."
fi

echo
echo "Feed Espelunca instalado."
echo "Serviço: ${FEED_SERVICE}"
echo "Local: http://127.0.0.1:${FEED_PORT}"
echo "Público: https://${FEED_HOST}"
echo "DID do serviço: ${FEED_DID}"
echo "Registro: ${FEED_RECORD}"
echo "Próximo passo: bluesky feed publish"

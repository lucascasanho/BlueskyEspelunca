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

: "${PDS_PORT:?PDS_PORT não definido}"
if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi
IDENTIFIER="${1:-}"
if [[ -z "${IDENTIFIER}" ]]; then
  echo "Uso: bluesky media inspect <DID ou handle>"
  exit 2
fi

for cmd in curl jq tailscale; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Comando ausente: ${cmd}"
    exit 1
  fi
done

if [[ "${IDENTIFIER}" == did:* ]]; then
  DID="${IDENTIFIER}"
else
  DID="$(curl -fsS "http://127.0.0.1:${PDS_PORT}/xrpc/com.atproto.identity.resolveHandle?handle=${IDENTIFIER}" | jq -r ".did // empty")"
fi

if [[ -z "${DID}" ]]; then
  echo "Não foi possível resolver o identificador: ${IDENTIFIER}"
  exit 1
fi
if [[ "${DID}" != did:plc:* ]]; then
  echo "A conta não usa did:plc: ${DID}"
  exit 1
fi

TAIL_DNS="$("${SUDO}" tailscale status --json | jq -r ".Self.DNSName // empty" | sed "s/\.$//")"
if [[ -z "${TAIL_DNS}" ]]; then
  echo "Não foi possível obter o hostname *.ts.net deste nó."
  echo "Autentique o Tailscale primeiro: sudo tailscale up"
  exit 1
fi

PLC_DATA="$(curl -fsS "https://plc.directory/${DID}/data")"
DID_DOC="$(curl -fsS "https://plc.directory/${DID}")"
CURRENT_ENDPOINT="$(jq -r ".services.atproto_pds.endpoint // empty" <<<"${PLC_DATA}")"
HANDLE="$(jq -r ".alsoKnownAs[]? | select(startswith(\"at://\")) | sub(\"^at://\"; \"\")" <<<"${PLC_DATA}" | head -n1)"
ACCOUNT_KEY="$(jq -r ".verificationMethods.atproto // empty" <<<"${PLC_DATA}")"
ROTATION_KEYS="$(jq -c ".rotationKeys // []" <<<"${PLC_DATA}")"
TARGET="https://${TAIL_DNS}"

echo "=== Conta ==="
echo "Identificador: ${IDENTIFIER}"
echo "Handle:        ${HANDLE:-não encontrado}"
echo "DID:           ${DID}"
echo
echo "=== PLC ==="
echo "PDS atual:     ${CURRENT_ENDPOINT:-não encontrado}"
echo "PDS alvo:      ${TARGET}"
echo "Chave atproto: ${ACCOUNT_KEY}"
echo "Rotation keys: ${ROTATION_KEYS}"
echo
echo "=== DID Document resolvido ==="
jq -c "{ id, alsoKnownAs, service }" <<<"${DID_DOC}"
echo
if [[ "${CURRENT_ENDPOINT}" == "${TARGET}" ]]; then
  echo "Estado: a conta já aponta para o endpoint Tailscale."
else
  echo "Estado: a conta ainda aponta para o endpoint atual."
  echo "Nenhuma alteração foi feita."
fi
echo
echo "IMPORTANTE: este comando é somente leitura. Ele não cria nem envia PLC operations."
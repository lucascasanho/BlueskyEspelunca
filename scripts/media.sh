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

: "${INSTALL_DIR:?INSTALL_DIR não definido}"
: "${PDS_HOSTNAME:?PDS_HOSTNAME não definido}"
: "${PDS_PORT:?PDS_PORT não definido}"

MEDIA_GATEWAY_PORT="${MEDIA_GATEWAY_PORT:-3190}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

usage() {
  cat <<'EOF'
Uso:
  bluesky media install
  bluesky media status
  bluesky media funnel
  bluesky media funnel-off
  bluesky media url
  bluesky media logs

Comandos:
  install       Instala/configura o gateway local de uploadBlob.
  status        Mostra gateway, Tailscale e Funnel.
  funnel        Publica o gateway no Funnel, em HTTPS 443.
  funnel-off    Remove o Funnel de HTTPS 443 deste gateway.
  url           Mostra o hostname público do Tailscale.
  logs          Mostra as últimas requisições do nginx.
EOF
}

require_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale não está instalado. Execute: bluesky media install"
    exit 1
  fi
}

get_dns_name() {
  require_tailscale
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq não está instalado."
    exit 1
  fi
  "${SUDO}" tailscale status --json | jq -r ".Self.DNSName // empty" | sed "s/\\.$//"
}

case "${1:-}" in
  install)
    exec "${ROOT_DIR}/scripts/install-media-gateway.sh"
    ;;
  status)
    echo "=== Gateway de mídia ==="
    echo "Porta local: ${MEDIA_GATEWAY_PORT}"
    echo "PDS destino: http://127.0.0.1:${PDS_PORT}"
    echo "PDS hostname lógico: ${PDS_HOSTNAME}"
    echo
    echo "=== Nginx ==="
    "${SUDO}" systemctl is-active nginx || true
    "${SUDO}" nginx -t || true
    echo
    echo "=== Tailscale ==="
    require_tailscale
    "${SUDO}" tailscale status || true
    echo
    echo "=== Funnel ==="
    "${SUDO}" tailscale funnel status || true
    ;;
  funnel)
    require_tailscale
    if [[ -z "$(get_dns_name)" ]]; then
      echo "Tailscale ainda não está autenticado nesta máquina."
      echo "Execute: sudo tailscale up"
      exit 1
    fi
    echo "==> Publicando gateway pelo Tailscale Funnel em HTTPS 443"
    echo "==> O Funnel usa exclusivamente o hostname *.ts.net do seu tailnet."
    "${SUDO}" tailscale funnel --bg --https=443 "http://127.0.0.1:${MEDIA_GATEWAY_PORT}"
    echo
    echo "Hostname público:"
    echo "https://$(get_dns_name)/xrpc/com.atproto.repo.uploadBlob"
    echo
    echo "IMPORTANTE: esta rota é um teste de transporte. O Bluesky oficial ainda não foi configurado para trocar o PDS para este hostname."
    ;;
  funnel-off)
    require_tailscale
    "${SUDO}" tailscale funnel --https=443 off
    echo "Funnel de HTTPS 443 desativado."
    ;;
  url)
    echo "https://$(get_dns_name)"
    ;;
  logs)
    "${SUDO}" tail -n 100 /var/log/nginx/access.log || true
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Comando desconhecido: ${1}"
    echo
    usage
    exit 2
    ;;
esac
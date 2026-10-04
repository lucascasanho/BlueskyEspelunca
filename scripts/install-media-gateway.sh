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
MEDIA_GATEWAY_MAX_BODY="${MEDIA_GATEWAY_MAX_BODY:-500m}"
MEDIA_GATEWAY_DIR="${MEDIA_GATEWAY_DIR:-${INSTALL_DIR}/media-gateway}"
MEDIA_GATEWAY_NGINX_CONF="${MEDIA_GATEWAY_NGINX_CONF:-/etc/nginx/conf.d/espelunca-media-gateway.conf}"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=; else SUDO=sudo; fi

if ! [[ "${MEDIA_GATEWAY_PORT}" =~ ^[0-9]+$ ]] || (( MEDIA_GATEWAY_PORT < 1024 || MEDIA_GATEWAY_PORT > 65535 )); then
  echo "MEDIA_GATEWAY_PORT inválida: ${MEDIA_GATEWAY_PORT}"
  exit 1
fi

echo "==> Instalando dependências do gateway"
${SUDO} apt-get update
${SUDO} apt-get install -y ca-certificates curl gnupg nginx

if ! command -v tailscale >/dev/null 2>&1; then
  echo "==> Instalando Tailscale"
  curl -fsSL https://tailscale.com/install.sh | ${SUDO} sh
fi

echo "==> Criando diretórios"
${SUDO} mkdir -p "${MEDIA_GATEWAY_DIR}"
${SUDO} chmod 755 "${MEDIA_GATEWAY_DIR}"

if ${SUDO} ss -ltnH "sport = :${MEDIA_GATEWAY_PORT}" 2>/dev/null | grep -q .; then
  echo "ERRO: a porta local ${MEDIA_GATEWAY_PORT} já está em uso."
  ${SUDO} ss -ltnp "sport = :${MEDIA_GATEWAY_PORT}" || true
  exit 1
fi

echo "==> Configurando nginx para streaming de uploadBlob"
${SUDO} tee "${MEDIA_GATEWAY_NGINX_CONF}" >/dev/null <<EOF
server {
    listen 127.0.0.1:${MEDIA_GATEWAY_PORT};
    server_name _;

    client_max_body_size ${MEDIA_GATEWAY_MAX_BODY};
    client_body_timeout 30m;
    proxy_connect_timeout 30s;
    proxy_send_timeout 30m;
    proxy_read_timeout 30m;
    send_timeout 30m;

    location = /xrpc/com.atproto.repo.uploadBlob {
        if (\$request_method != POST) {
            return 405;
        }

        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;

        proxy_set_header Host ${PDS_HOSTNAME};
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Content-Type \$http_content_type;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_pass http://127.0.0.1:${PDS_PORT};
    }

    location / {
        return 404;
    }
}
EOF

echo "==> Validando nginx"
${SUDO} nginx -t
${SUDO} systemctl enable --now nginx
${SUDO} systemctl reload nginx

echo "==> Validando gateway local"
LOCAL_STATUS="$(
  curl -sS -o /dev/null -w "%{http_code}" \
    -X GET "http://127.0.0.1:${MEDIA_GATEWAY_PORT}/xrpc/com.atproto.repo.uploadBlob" \
    || true
)
if [[ "${LOCAL_STATUS}" != "405" ]]; then
  echo "ERRO: gateway local retornou HTTP ${LOCAL_STATUS}; esperado 405 para GET."
  exit 1
fi

echo
echo "Gateway local instalado."
echo "Endpoint local de mídia: http://127.0.0.1:${MEDIA_GATEWAY_PORT}/xrpc/com.atproto.repo.uploadBlob"
echo "Destino: http://127.0.0.1:${PDS_PORT}"
echo "Buffering de request: desativado"
echo "Armazenamento temporário do vídeo pelo nginx: não"
echo
echo "IMPORTANTE: o Tailscale Funnel ainda NÃO foi ativado."
echo "Próximo passo: bluesky media funnel"
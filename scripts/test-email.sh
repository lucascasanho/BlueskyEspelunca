#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"
: "$PDS_HOSTNAME"

BASE_URL="https://$PDS_HOSTNAME"

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "ERRO: curl e jq são necessários."
  exit 1
fi

echo
echo "============================================================"
echo " Espelunca — TESTE DE E-MAIL"
echo "============================================================"
echo
echo "1) Confirmação de e-mail"
echo "2) Redefinição de senha"
echo
read -r -p "Escolha [1/2]: " TEST_TYPE

case "$TEST_TYPE" in
  1)
    read -r -p "Handle da conta (ex.: luc ou luc.espelunca.blue): " HANDLE
    read -r -s -p "Senha da conta: " PASSWORD
    echo

    HANDLE="${HANDLE#@}"
    if [[ "$HANDLE" != *.* ]]; then
      HANDLE="$HANDLE.$PDS_HOSTNAME"
    fi

    echo "==> Criando sessão para @$HANDLE"
    PAYLOAD="$(jq -nc --arg identifier "$HANDLE" --arg password "$PASSWORD" '{identifier:$identifier,password:$password}')"
    SESSION_RESPONSE="$(curl -fsS -X POST "$BASE_URL/xrpc/com.atproto.server.createSession" -H "Content-Type: application/json" --data "$PAYLOAD")" || {
      echo "ERRO: não foi possível iniciar a sessão."
      exit 1
    }

    ACCESS_JWT="$(jq -r ".accessJwt // empty" <<<"$SESSION_RESPONSE")"
    if [[ -z "$ACCESS_JWT" ]]; then
      echo "ERRO: o PDS não retornou accessJwt."
      jq . <<<"$SESSION_RESPONSE" || true
      exit 1
    fi

    echo "==> Solicitando novo e-mail de confirmação"
    HTTP_CODE="$(curl -sS -o /tmp/espelunca-email-test-response -w "%{http_code}" -X POST "$BASE_URL/xrpc/com.atproto.server.requestEmailConfirmation" -H "Authorization: Bearer $ACCESS_JWT" -H "Content-Type: application/json" --data "{}")"

    if [[ "$HTTP_CODE" == 2* ]]; then
      echo "E-mail de confirmação solicitado com sucesso."
    else
      echo "ERRO: PDS retornou HTTP $HTTP_CODE."
      cat /tmp/espelunca-email-test-response
      echo
      exit 1
    fi
    ;;

  2)
    read -r -p "E-mail da conta: " EMAIL

    echo "==> Solicitando redefinição de senha para $EMAIL"
    PAYLOAD="$(jq -nc --arg email "$EMAIL" '{email:$email}')"
    HTTP_CODE="$(curl -sS -o /tmp/espelunca-email-test-response -w "%{http_code}" -X POST "$BASE_URL/xrpc/com.atproto.server.requestPasswordReset" -H "Content-Type: application/json" --data "$PAYLOAD")"

    if [[ "$HTTP_CODE" == 2* ]]; then
      echo "E-mail de redefinição solicitado com sucesso."
    else
      echo "ERRO: PDS retornou HTTP $HTTP_CODE."
      cat /tmp/espelunca-email-test-response
      echo
      exit 1
    fi
    ;;

  *)
    echo "Opção inválida."
    exit 1
    ;;
esac

echo
echo "Verifique a caixa de entrada."
echo "Log SMTP do PDS:"
echo "sudo docker logs pds --since 10m 2>&1 | grep -Ei \"smtp|email|mailer|error|failed|535|550\" | tail -50"

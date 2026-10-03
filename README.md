# BlueskyEspelunca

Infraestrutura da Espelunca baseada no AT Protocol, usando o PDS oficial do Bluesky e o código oficial do aplicativo social para Web, Android e iOS.

## Arquitetura

- PDS: `https://espelunca.blue`
- Web: `https://app.espelunca.blue`
- Handles: `@usuario.espelunca.blue`
- PDS local: `127.0.0.1:3100`
- Web local: `127.0.0.1:3101`
- Cloudflare Tunnel existente: `espelunca`
- AppView: inicialmente o AppView público do Bluesky
- Relay/crawlers: rede AT Protocol pública
- Instalação alvo: WSL2 com systemd

A porta 80 continua pertencendo ao Mastodon da Espelunca. O instalador não instala Caddy para o PDS, porque o TLS público é terminado pelo Cloudflare Tunnel.

O repositório contém apenas automação e configuração. O código upstream não é copiado para cá: o instalador baixa os projetos oficiais durante a instalação.

## Instalação

No WSL da Espelunca:

```bash
git clone https://github.com/lucascasanho/BlueskyEspelunca.git ~/BlueskyEspelunca
cd ~/BlueskyEspelunca
cp config.env.example config.env
nano config.env
bash install.sh
```

O instalador:

1. valida as portas locais dedicadas;
2. lê a configuração local, incluindo SMTP quando configurado;
3. instala dependências;
4. instala/configura Docker Engine quando necessário;
5. baixa o PDS oficial;
6. cria os segredos do PDS;
7. executa o PDS oficial em `PDS_PORT=3100`;
8. baixa o `social-app` oficial;
9. aponta o cliente para `https://espelunca.blue`;
10. aplica a configuração de marca básica da Espelunca;
11. compila a versão Web;
12. publica o build local em `WEB_PORT=3101`;
13. cria serviços systemd separados.

## Cloudflare Tunnel

O Tunnel existente da Espelunca pode encaminhar os serviços sem abrir 3100/3101 na Internet.

No arquivo local `/home/espelunca/.cloudflared/config.yml`, use estas regras antes do catch-all:

```yaml
  - hostname: app.espelunca.blue
    service: http://127.0.0.1:3101
  - hostname: espelunca.blue
    service: http://127.0.0.1:3100
  - hostname: "*.espelunca.blue"
    service: http://127.0.0.1:3100
```

O catch-all `http_status:404` deve permanecer por último.

O repositório inclui `scripts/configure-tunnel.sh` para fazer esse ajuste com backup e validação. Ele não cria registros DNS nem pede credenciais novas do Cloudflare.

Depois do ingress, os DNS do Cloudflare devem apontar para o Tunnel existente:

```text
espelunca.blue       CNAME  bc4501b3-4922-45e9-960b-234f622b9cc7.cfargotunnel.com
app.espelunca.blue   CNAME  bc4501b3-4922-45e9-960b-234f622b9cc7.cfargotunnel.com
*.espelunca.blue     CNAME  bc4501b3-4922-45e9-960b-234f622b9cc7.cfargotunnel.com
```

Esses registros devem ficar proxied pelo Cloudflare. Não coloque o UUID ou credenciais do Tunnel em arquivos públicos de configuração.

## Diagnóstico

```bash
./scripts/status.sh
```

O diagnóstico verifica:

- serviço systemd do PDS;
- serviço systemd do Web;
- containers Docker;
- `http://127.0.0.1:3100/xrpc/_health`;
- Web local em 3101;
- processos escutando nas duas portas.

## Conta inicial

Depois de validar o PDS e o domínio:

```bash
./scripts/create-account.sh
```

O script cria uma conta com handle `@usuario.espelunca.blue`.

O SMTP configurado em `config.env` é gravado somente no servidor em `pds.env`; o arquivo não deve ser enviado ao GitHub.

A senha administrativa fica somente no servidor em:

```text
/opt/espelunca-bluesky/pds-data/.admin-password
```

## Atualização

```bash
./scripts/update.sh
```

O script atualiza o clone de referência do PDS, baixa a imagem atual do PDS, atualiza o `social-app`, reaplica as alterações da Espelunca e recompila o Web.

Faça backup de `PDS_DATA_DIR` antes de atualizações de produção.

## Android / iOS

O mesmo clone do `social-app` é usado para desenvolvimento nativo. O WSL pode preparar o projeto Android, mas publicação iOS exige o ecossistema Apple/Xcode fora do WSL.

```bash
cd /opt/espelunca-bluesky/social-app
pnpm android
pnpm ios
```

## Branding e licenças

O código-fonte do `social-app` é MIT, mas o próprio projeto informa que vários ícones, ilustrações, imagens e marcas não estão cobertos pela licença MIT. Antes de distribuir publicamente um aplicativo próprio da Espelunca, substitua os assets e marcas do Bluesky conforme os termos upstream.

Este repositório não copia esses assets. O instalador baixa o upstream para a máquina local.

Fontes e créditos:

- Bluesky Social App: https://github.com/bluesky-social/social-app
- Bluesky PDS: https://github.com/bluesky-social/pds
- AT Protocol: https://github.com/bluesky-social/atproto
- Expo Web: https://docs.expo.dev/guides/publishing-websites/
- Cloudflare Tunnel: https://developers.cloudflare.com/tunnel/

Licenças: PDS sob MIT/Apache-2.0; social-app sob MIT para o código-fonte, com exceções de assets descritas pelo próprio projeto.

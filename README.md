# BlueskyEspelunca

Infraestrutura da Espelunca baseada no AT Protocol, usando o PDS oficial do Bluesky e o código oficial do aplicativo social para Web, Android e iOS.

## Arquitetura

- PDS: `https://espelunca.blue`
- Web: `https://espelunca.blue`
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

No arquivo local `/home/espelunca/.cloudflared/config.yml`, o mesmo hostname atende o Web e o PDS. As rotas do protocolo vão primeiro para o PDS e o restante da raiz vai para o Web:

```yaml
  - hostname: espelunca.blue
    path: ^/xrpc/.*
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/\\.well-known/.*
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/oauth/.*
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/oauth-client-metadata\\.json$
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/@atproto/oauth-provider/~assets/.*$
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/@atproto/oauth-provider/~api(?:/.*)?$
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    path: ^/account(?:/.*)?$
    service: http://127.0.0.1:3100
  - hostname: espelunca.blue
    service: http://127.0.0.1:3101
  - hostname: "*.espelunca.blue"
    service: http://127.0.0.1:3100
```

O catch-all `http_status:404` deve permanecer por último.

O repositório inclui `scripts/configure-tunnel.sh` para fazer esse ajuste com backup e validação. Ele não cria registros DNS nem pede credenciais novas do Cloudflare.

Depois do ingress, os DNS do Cloudflare devem apontar para o Tunnel existente:

```text
espelunca.blue       CNAME  bc4501b3-4922-45e9-960b-234f622b9cc7.cfargotunnel.com
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

## Comando de administração

Após a instalação, o comando global `bluesky` aponta para este clone Git. Isso mantém a automação versionada no GitHub e permite que as alterações feitas no repositório sejam aplicadas ao servidor.

```bash
bluesky status
bluesky update
bluesky install
bluesky start
bluesky stop
bluesky tunnel
bluesky account
```

O comando `bluesky update` faz todo o ciclo de atualização em uma única chamada: guarda automaticamente alterações rastreadas locais em um backup Git, atualiza este repositório e depois atualiza o PDS e o Web. O arquivo local `config.env` permanece fora desse backup e não é sobrescrito.


### Customizações do PDS

O PDS oficial continua sendo usado como base. O arquivo `patches/pds/entrypoint.sh` reaplica automaticamente duas compatibilidades da Espelunca quando o container é iniciado ou recriado: permite que o hostname do próprio PDS também seja usado como handle personalizado (por exemplo, `@espelunca.blue`) e aceita ausência de `Sec-Fetch-Site` na navegação inicial de autorização OAuth. A segunda alteração é restrita à página GET de autorização; os endpoints de consentimento permanecem protegidos por validações same-origin.

Essas customizações são reaplicadas pelo compose versionado e, portanto, não dependem de alterações manuais dentro do container. Elas foram criadas a partir do código oficial do AT Protocol/PDS.

### Customizações do social-app

O repositório não copia o código inteiro do Bluesky. O upstream é baixado em `/opt/espelunca-bluesky/social-app` durante a instalação/atualização. As alterações próprias da Espelunca ficam versionadas aqui, principalmente em `scripts/apply-social-app-customizations.sh` e, para alterações maiores, em `patches/social-app/*.patch`.

O PDS da Espelunca está configurado com `PDS_BLOB_UPLOAD_LIMIT=524288000`, equivalente a 500 MiB por blob. Esse é o limite no PDS; o acesso público por Cloudflare pode impor um limite menor de tamanho de requisição, conforme o plano da zona.

Isso permite alterar a interface ou o comportamento do aplicativo no próprio GitHub e reaplicar essas alterações automaticamente depois que o upstream for atualizado.

O build Web cria também `dist/static/_expo -> ../_expo`, necessário para o layout de assets produzido pelo build atual do social-app. O serviço Web é sempre `espelunca-bluesky-web.service`; o instalador não deve alterar o serviço Mastodon `espelunca-web.service`.

Faça backup de `PDS_DATA_DIR` antes de atualizações de produção.

## Feed personalizado Espelunca BR

A instalação inclui um Feed Generator separado do PDS/Web:

- Host público: `https://feeds.espelunca.blue`
- Registro: `espelunca-br`
- Porta local: `3200`
- Filtro estrito de idioma `pt-BR`
- Temas: notícias, memes brasileiros, tecnologia, Dead by Daylight, Fortnite e League of Legends
- Bloqueio de domínios/paywalls e redirecionadores conhecidos
- Filtro de marcadores explícitos de conteúdo gerado por IA
- Classificação local de toxicidade e mídia sintética

Comandos:

```bash
bluesky feed status
bluesky feed publish
bluesky feed seed
bluesky feed logs
bluesky feed tunnel
```

O Feed é independente do PDS e do Web. Seu banco e cache ficam em `/opt/espelunca-bluesky/feed-data`.

### Feed padrão para novas contas

O Web da Espelunca configura os feeds iniciais de novas contas com esta ordem:

1. `Seguindo`
2. `Espelunca BR`
3. `Discover`

A guia oficial `Video` não é incluída nos feeds padrão. Caso existam outros feeds fixados, eles permanecem depois desses três, na ordem original.

Além de gravar essa ordem nas preferências da conta durante o onboarding, a Home do Web aplica a mesma ordenação visual para impedir que uma resposta inesperada do AppView altere a sequência exibida no topo.

Essa personalização é aplicada ao fluxo de onboarding do `social-app` hospedado em `espelunca.blue`. Uma conta criada por um cliente externo, sem passar pelo Web da Espelunca, não recebe essa preferência automaticamente.

A lista de paywalls é uma lista configurada de domínios conhecidos, não uma detecção universal de paywalls. A detecção de IA é probabilística. O modelo padrão de toxicidade é multilíngue e não inclui português em sua lista declarada de idiomas; por isso, essa camada não deve ser tratada como moderação perfeita para PT-BR.

## Créditos adicionais do Feed

- Bluesky Feed Generator Starter: `bluesky-social/feed-generator`
- Jetstream: `@bsky/jetstream`
- Transformers.js: `@huggingface/transformers`
- Modelos ONNX da organização `onnx-community`

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

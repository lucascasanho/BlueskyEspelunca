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

## Gateway de mídia via Tailscale

Existe uma implementação experimental para transportar `com.atproto.repo.uploadBlob` por Tailscale Funnel, sem abrir portas no roteador e sem armazenar o vídeo na Oracle ou no servidor intermediário.

Instalação:

```bash
bluesky media install
sudo tailscale up
bluesky media status
```

Teste de transporte acima de 100 MB:

```bash
bluesky media test 101
bluesky media test 276
```

O teste usa o Funnel em HTTPS 8443 temporariamente, cria um arquivo esparso local e confirma que exatamente o número esperado de bytes chegou ao servidor doméstico. O arquivo é removido no final.

Para publicar o gateway pelo Funnel em produção de teste:

```bash
bluesky media funnel
bluesky media url
bluesky media status
```

O Funnel usa um hostname `*.ts.net` fornecido pelo Tailscale. Não é necessário abrir portas no roteador. O hostname `espelunca.blue` continua separado e pode continuar atrás do Cloudflare.

**Importante:** esta implementação não altera `PDS_HOSTNAME`, DID, PLC ou o endpoint principal das contas. Portanto, ela ainda não faz o `video.bsky.app` enviar o blob final para o hostname Tailscale.

O Bluesky localiza o PDS a partir do DID Document da conta. O fluxo oficial de vídeo obtém um service-auth e, no final do processamento, realiza `com.atproto.repo.uploadBlob` no PDS da conta. Por isso, adicionar um segundo hostname Tailscale sem alterar o endpoint de PDS anunciado não muda o destino do serviço de vídeo.

Para transformar o Funnel em rota de produção, seria necessário primeiro decidir como o PDS será anunciado publicamente. Uma possibilidade futura é usar um hostname de PDS separado do site, por exemplo `pds.espelunca.blue`, e atualizar as identidades hospedadas de acordo com o procedimento de migração/alteração de hostname do AT Protocol. Essa mudança não é aplicada automaticamente por estes scripts.

Fontes da arquitetura e pesquisa detalhada:
- `docs/media-upload/tailscale-research.md`
- Tailscale Funnel: https://tailscale.com/docs/features/tailscale-funnel
- AT Protocol self-hosting: https://atproto.com/guides/self-hosting
- Video upload: https://bsky.network/docs/about-bluesky-content/video/

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

## Feed personalizado desativado

O Feed Generator próprio da Espelunca.blue foi descontinuado. O comando bluesky update interrompe e desabilita o serviço antigo, remove seus arquivos, banco de dados e cache locais e configura feeds.espelunca.blue para responder HTTP 404 pelo Cloudflare Tunnel. A interface deixa de fixar esse feed em contas novas e remove a referência das preferências das contas existentes quando elas carregam o aplicativo atualizado.

O registro público AT Protocol app.bsky.feed.generator/espelunca-br pertence à conta que o publicou. Durante a atualização, o script verifica se o registro ainda existe e, se existir, oferece a remoção autenticada. Informe o handle da conta publicadora e uma App Password do Bluesky. A senha é lida sem eco, não é gravada em arquivo e a sessão criada para a operação é revogada ao final. Se a autenticação for pulada ou falhar, a desativação local continua, mas o registro público permanece até ser removido com autenticação válida.
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

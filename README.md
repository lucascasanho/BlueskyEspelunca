# BlueskyEspelunca

Infraestrutura para a Espelunca baseada no AT Protocol, usando o PDS oficial do Bluesky e o código oficial do aplicativo social para Web, Android e iOS.

## Arquitetura

- PDS: `https://espelunca.blue`
- Web: `https://app.espelunca.blue`
- Handles: `@usuario.espelunca.blue`
- PDS oficial: clonado durante a instalação a partir de `bluesky-social/pds`
- App oficial: clonado durante a instalação a partir de `bluesky-social/social-app`
- AppView: inicialmente o AppView público do Bluesky
- Relay: rede AT Protocol pública
- Instalação alvo: WSL2 Ubuntu/Debian

O repositório da Espelunca contém apenas automação e configuração. O código upstream não é copiado para cá; o instalador baixa as versões atuais dos projetos oficiais.

## Instalação

No WSL:

```bash
git clone https://github.com/lucascasanho/BlueskyEspelunca.git ~/BlueskyEspelunca
cd ~/BlueskyEspelunca
cp config.env.example config.env
nano config.env
bash install.sh
```

O instalador:

1. valida WSL/Linux;
2. instala dependências;
3. instala/configura Docker Engine quando necessário;
4. baixa o PDS oficial;
5. cria os segredos do PDS;
6. configura o PDS para `espelunca.blue`;
7. baixa o `social-app` oficial;
8. aplica somente as alterações necessárias para apontar o cliente para o PDS da Espelunca;
9. compila a versão Web;
10. cria um serviço local para servir o Web build;
11. gera scripts de atualização e diagnóstico.

## DNS / Cloudflare

O PDS oficial normalmente espera acesso público em 80/443. Se a máquina estiver atrás de NAT, o instalador não substitui o túnel.

Para Cloudflare Tunnel, uma configuração inicial típica é:

- `espelunca.blue` -> serviço local do PDS/Caddy em `https://127.0.0.1:443`
- `*.espelunca.blue` -> o mesmo serviço
- `app.espelunca.blue` -> Web build em `http://127.0.0.1:3001`

Não coloque credenciais do Cloudflare neste repositório.

## Comandos

```bash
./scripts/status.sh
./scripts/update.sh
./scripts/build-web.sh
./scripts/start-web.sh
./scripts/stop-web.sh
```

## Atualização

`update.sh` atualiza os clones upstream, reaplica o patch da Espelunca e recompila o Web. O PDS é atualizado usando a ferramenta oficial quando possível.

Antes de atualizar uma instalação de produção, faça backup do diretório de dados do PDS.

## Android / iOS

O mesmo clone do `social-app` é usado para desenvolvimento nativo. O WSL pode preparar o projeto Android, mas publicação iOS exige o ecossistema Apple/Xcode fora do WSL.

```bash
cd /opt/espelunca-bluesky/social-app
pnpm android
pnpm ios
```

Para gerar o Web:

```bash
pnpm build-web
```

## Importante sobre branding e licenças

O código-fonte do `social-app` é MIT, mas o próprio projeto informa que vários ícones, ilustrações, imagens e marcas não estão cobertos por essa licença. Uma distribuição pública da Espelunca deve substituir os assets e marcas do Bluesky antes de ser publicada como aplicativo próprio.

Este repositório, portanto, não inclui cópias desses assets. O instalador baixa o upstream para a máquina local.

Fontes e créditos:

- Bluesky Social App: https://github.com/bluesky-social/social-app
- Bluesky PDS: https://github.com/bluesky-social/pds
- AT Protocol: https://github.com/bluesky-social/atproto
- Documentação Expo Web: https://docs.expo.dev/guides/publishing-websites/

Licenças: PDS sob MIT/Apache-2.0; social-app sob MIT para o código-fonte, com exceções de assets descritas pelo próprio projeto.

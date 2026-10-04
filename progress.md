# Progresso — Gateway de mídia via Tailscale

Objetivo: investigar e preparar uma rota alternativa para uploads grandes do Bluesky, mantendo os dados no servidor doméstico e sem abrir portas no roteador.

## Estado atual

- [x] Repositório atual inspecionado.
- [x] PDS atual confirmado em `127.0.0.1:3100`.
- [x] Web atual confirmado em `127.0.0.1:3101`.
- [x] PDS configurado para aceitar blobs de até 500 MiB.
- [x] Gargalo atual identificado: Cloudflare limita requisições públicas a 100 MB nos planos aplicáveis.
- [x] Fluxo oficial de vídeo do social-app verificado: cliente envia ao `video.bsky.app`; o serviço de vídeo posteriormente chama `com.atproto.repo.uploadBlob` no PDS.
- [x] Tailscale Funnel verificado: pode publicar um serviço local sem port forwarding, usando um hostname `*.ts.net`.
- [ ] Provar experimentalmente o transporte de um upload >100 MB pelo Funnel.
- [ ] Criar gateway local de mídia com buffering desativado, para não armazenar os vídeos em disco.
- [ ] Criar comando simples de instalação/diagnóstico.
- [ ] Determinar, com teste real, se o fluxo oficial `video.bsky.app → PDS` pode usar o endpoint alternativo sem alterar a identidade das contas.
- [ ] Só conectar o gateway ao caminho de produção depois de comprovar compatibilidade.
- [ ] Atualizar README e documentação operacional.
- [ ] Validar instalação idempotente e reversível.

## Decisão técnica provisória

O gateway Tailscale será tratado inicialmente como infraestrutura de teste, não como solução de produção.

Motivo: o protocolo de vídeo descobre o PDS a partir do DID Document da conta. A documentação oficial mostra que o serviço de vídeo usa a localização do PDS encontrada no DID Document e depois chama `uploadBlob` nesse PDS. Alterar apenas um hostname extra para mídia não faz o `video.bsky.app` automaticamente trocar de destino.

Portanto, nenhum DID, PLC operation, `PDS_HOSTNAME` ou endpoint principal será alterado nesta fase.

## Regra de continuidade

Toda alteração de arquivo deve ser seguida por um commit que registre a alteração nesta mesma página. Uma etapa não será marcada como concluída sem esse registro.

## Histórico de commits

### Commit inicial
- Este arquivo criado para ser a fonte persistente do progresso.


### Etapa 1 — Pesquisa técnica
- [x] Arquivo `docs/media-upload/tailscale-research.md` criado.
- [x] Registrado o fluxo oficial de vídeo e a dependência do DID Document para localizar o PDS.
- [x] Registrada a limitação de que um segundo hostname `*.ts.net` não é automaticamente escolhido pelo `video.bsky.app`.
- [x] Definido gateway local restrito ao endpoint `com.atproto.repo.uploadBlob`, sem armazenamento permanente.


### Etapa 2 — Primeiro componente implementado
- [x] `scripts/install-media-gateway.sh` criado.
- [x] Gateway limitado ao endpoint `/xrpc/com.atproto.repo.uploadBlob`.
- [x] Gateway escuta somente em `127.0.0.1`.
- [x] Nginx configurado com `proxy_request_buffering off`, evitando guardar o corpo do upload em disco como etapa intermediária.
- [x] Limite local configurável, padrão 500 MB, alinhado ao limite atual do PDS.
- [x] Script instala Tailscale, mas não ativa o Funnel automaticamente nesta fase.


### Etapa 2.1 — Comando de administração
- [x] `scripts/media.sh` criado.
- [x] Comandos previstos: `install`, `status`, `funnel`, `funnel-off`, `url`, `logs`.
- [x] O Funnel não é ativado automaticamente durante a instalação.
- [x] A publicação pública usa HTTPS 443 e o hostname `*.ts.net` fornecido pelo Tailscale.


### Etapa 2.2 — Configuração versionada
- [x] `config.env.example` recebeu parâmetros do gateway de mídia.
- [x] Porta local padrão: `3190`.
- [x] Limite de corpo padrão: `500m`.
- [x] Caminho do arquivo de configuração Nginx ficou configurável.


### Etapa 2.3 — Comando principal
- [x] O comando `bluesky` passou a encaminhar `bluesky media ...`.
- [x] A execução usa `bash` para não depender de bit executável do arquivo recém-criado.


### Etapa 2.4 — Dependências
- [x] Instalador atualizado para incluir `jq` e `python3`, usados pelo diagnóstico/teste.


### Etapa 3 — Teste de transporte
- [x] `scripts/media-transport-test.sh` criado.
- [x] Teste usa Funnel HTTPS 8443/10000 temporário, sem mexer na porta 443 de produção.
- [x] O teste gera arquivo esparso temporário, envia por HTTP e confere exatamente quantos bytes chegaram ao servidor doméstico.
- [x] O arquivo de teste é apagado ao final.
- [x] O teste não altera DID, PLC, `PDS_HOSTNAME` ou Cloudflare.

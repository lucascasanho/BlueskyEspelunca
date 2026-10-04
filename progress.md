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

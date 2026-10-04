# Pesquisa — Upload de mídia grande com Tailscale

Data da pesquisa: 2026-10-04

## 1. Problema observado

O PDS da Espelunca está configurado com:

- host lógico: `espelunca.blue`
- HTTP local: `127.0.0.1:3100`
- `PDS_BLOB_UPLOAD_LIMIT=524288000` (500 MiB)

O endpoint público atual passa pelo Cloudflare Tunnel. Nos testes feitos no ambiente da Espelunca, um corpo de 101 MB enviado a `https://espelunca.blue/xrpc/com.atproto.repo.uploadBlob` recebeu HTTP 413 antes de chegar ao PDS.

## 2. Como o Bluesky faz upload de vídeo

O social-app oficial atual usa:

- `https://video.bsky.app` como serviço de vídeo;
- `did:web:video.bsky.app` como DID do serviço;
- limite de 300 MB no cliente;
- upload multipart do arquivo para o serviço de vídeo.

Depois do processamento, o serviço de vídeo precisa colocar o blob resultante no PDS da conta usando:

`com.atproto.repo.uploadBlob`.

O fluxo recomendado pela documentação do Bluesky é: descobrir o PDS pelo DID Document da conta, obter um service-auth token no PDS com audiência do PDS e método `com.atproto.repo.uploadBlob`, enviar o vídeo ao `video.bsky.app` e, no final, o serviço de vídeo chamar `uploadBlob` no PDS.

## 3. O que o Tailscale Funnel resolve

O Tailscale Funnel publica um serviço local para a Internet sem port forwarding e sem IP público na residência.

Características relevantes documentadas pelo Tailscale:

- disponível no plano Personal;
- usa um hostname do próprio tailnet, no formato `*.ts.net`;
- publica o serviço por HTTPS;
- pode encaminhar para uma porta local;
- não impõe um limite de tamanho de requisição documentado equivalente aos 100 MB do Cloudflare;
- existe limite de banda não configurável.

O Funnel, portanto, é adequado para testar se um corpo de aproximadamente 276 MB consegue chegar ao servidor doméstico sem passar pelo Cloudflare.

## 4. Limitação importante para produção

Um segundo hostname Tailscale, por exemplo:

`espelunca-pds.<tailnet>.ts.net`

não será automaticamente usado pelo `video.bsky.app`.

O motivo é o mecanismo de descoberta do PDS. A localização atual do PDS é declarada no DID Document da conta. A documentação oficial de upload de vídeo indica explicitamente que o cliente/serviço deriva o host do PDS a partir desse documento.

Também existe uma consequência protocolar: a documentação oficial do AT Protocol informa que, quando o domínio de um PDS é alterado, é necessário atualizar as entradas PLC de cada conta hospedada. Portanto, trocar o endpoint principal do DID para um hostname Tailscale não é uma simples configuração de nginx.

Isso significa que a arquitetura desejada pelo operador:

`espelunca.blue` para site/API normal + `*.ts.net` somente para uploadBlob

não pode ser considerada compatível com o serviço oficial de vídeo sem uma prova adicional ou uma mudança mais profunda na identidade/hosting endpoint.

## 5. Gateway local proposto

Mesmo com essa limitação de descoberta, podemos preparar um gateway local seguro e reutilizável:

Internet
  -> Tailscale Funnel
  -> gateway HTTP local
  -> somente /xrpc/com.atproto.repo.uploadBlob
  -> PDS 127.0.0.1:3100

O gateway deve:

- aceitar somente POST para `/xrpc/com.atproto.repo.uploadBlob`;
- rejeitar outras rotas com 404;
- preservar o corpo como stream;
- usar `proxy_request_buffering off` ou equivalente;
- não gravar o vídeo em disco;
- preservar os headers de autenticação;
- enviar `Host: espelunca.blue` ao PDS para manter o hostname lógico esperado;
- ter limite local acima de 500 MiB, sem superar o limite configurado no PDS;
- ficar escutando somente em loopback, por exemplo `127.0.0.1:3190`.

O Funnel apontaria exclusivamente para essa porta.

## 6. O que precisa ser testado

Teste A — transporte:

- arquivo sintético de 101 MB;
- arquivo sintético de ~276 MB;
- confirmar que o gateway recebe o corpo inteiro;
- confirmar que o PDS recebe e responde, usando autenticação válida.

Teste B — vídeo real:

- vídeo de ~276 MB;
- usar o fluxo oficial do social-app;
- observar `video.bsky.app` e os logs do PDS;
- verificar se o serviço de vídeo chega ao hostname Tailscale.

Teste C — compatibilidade:

- determinar qual endpoint o serviço de vídeo usa depois de resolver o DID;
- confirmar se há alguma forma suportada de fornecer endpoint alternativo;
- não alterar PLC/DID de contas existentes para realizar esse teste.

## 7. Fallbacks

Se o Funnel transportar o arquivo, mas o serviço oficial continuar enviando `uploadBlob` para `espelunca.blue`, o gateway Tailscale sozinho não resolve o problema.

As opções passam a ser:

1. Oracle/VM ou outro gateway público com hostname que possa ser usado como PDS endpoint;
2. mudar a identidade/endpoint de hospedagem seguindo o procedimento de migração do AT Protocol;
3. implementar serviço de vídeo próprio e cliente próprio;
4. aceitar temporariamente o limite público do Cloudflare.

Não será implementado nenhum workaround que dependa de ultrapassar o limite do Cloudflare por comportamento não documentado.

## Fontes principais

- Tailscale Funnel: https://tailscale.com/docs/features/tailscale-funnel
- Tailscale Funnel CLI: https://tailscale.com/docs/reference/tailscale-cli/funnel
- AT Protocol self-hosting: https://atproto.com/guides/self-hosting
- AT Protocol account migration: https://atproto.com/guides/account-migration
- AT Protocol blob specification: https://atproto.com/specs/blob
- Bluesky video upload guide: https://bsky.network/docs/about-bluesky-content/video/
- Bluesky social-app atual: https://github.com/bluesky-social/social-app

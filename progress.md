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
- [x] Provar experimentalmente o transporte de um upload >100 MB pelo Funnel.
- [x] Criar gateway local de mídia com buffering desativado, para não armazenar os vídeos em disco.
- [x] Criar comando simples de instalação/diagnóstico.
- [ ] Determinar, com teste real, se o fluxo oficial `video.bsky.app → PDS` pode usar o endpoint alternativo sem alterar a identidade das contas.
- [ ] Só conectar o gateway ao caminho de produção depois de comprovar compatibilidade.
- [x] Atualizar README e documentação operacional.
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


### Etapa 3.1 — Teste integrado ao comando
- [x] `bluesky media test [MB]` adicionado.
- [x] Instalação do gateway passou a usar `bash` explicitamente, sem depender de permissões executáveis do GitHub Contents API.
- [x] Teste padrão definido em 101 MB para ultrapassar o limite atual de 100 MB; 276 MB pode ser solicitado com `bluesky media test 276`.


### Etapa 4 — Documentação
- [x] `README.md` documenta instalação, teste e comandos do gateway.
- [x] README deixa explícito que o gateway é experimental e não altera o endpoint de PDS.
- [x] README registra a necessidade de uma decisão/migração de endpoint antes de produção.


### Revisão Etapa 3.1 — Correções antes do uso
- [x] Corrigidos escapes indevidos no `scripts/media-transport-test.sh`.
- [x] Corrigida a ajuda do `scripts/media.sh` para mostrar `test [MB]`.
- [ ] Ainda falta executar o teste no servidor doméstico; portanto o transporte >100 MB continua não comprovado.


## Ponto de parada seguro — 2026-10-04
A fase de preparação terminou. O repositório contém a implementação experimental, mas nenhuma alteração de produção foi feita no PDS, DID, PLC ou Cloudflare.

### Arquivos versionados da fase de teste
- `docs/media-upload/tailscale-research.md`
- `scripts/install-media-gateway.sh`
- `scripts/media.sh`
- `scripts/media-transport-test.sh`
- `config.env.example`
- `bluesky`
- `README.md`

### Próximo comando no servidor doméstico
```bash
bluesky update
bluesky media install
sudo tailscale up
bluesky media test 101
```

Depois do teste de 101 MB:
```bash
bluesky media test 276
```

### Critério para avançar
Só marcar o transporte como concluído se o servidor de teste receber exatamente o número de bytes enviado.

Depois disso, ainda será necessário provar o fluxo `video.bsky.app -> PDS`. O gateway Tailscale não será ligado ao fluxo oficial de produção até essa compatibilidade ser demonstrada.

### Commits importantes
- `f4e4c00d90c5714908dd34ae83d9e40107dc292d` — cria `progress.md`
- `d6a41683e4ec424059e1f1c2d8238632f98c3717` — pesquisa técnica
- `9602c98ef37497d9896aa3adc3169b6aa4d78487` — instalador do gateway
- `29e4b5bbdd52c92f59e66e22ba9ea7011be36d95` — comando de administração
- `958bbdbb7b7a1c095ba44bcf3122d4573abae2fc` — teste de transporte
- `3a1a52124138f1d1a1e700b1bd1cd1763f08ce9d` — documentação


### Etapa 3.2 — Primeiro teste executado
- [x] Tailscale Funnel iniciou corretamente no primeiro teste, usando `lucas-2.taild078e5.ts.net:8443`.
- [x] O teste chegou à fase de envio de 101 MB.
- [x] Identificado erro local no cálculo de duração via `awk`; não houve evidência de falha de transporte nessa execução.
- [x] Corrigido o cálculo de duração em `scripts/media-transport-test.sh`.
- [x] Reexecutar `bluesky media test 101`.
- [x] Reexecutar `bluesky media test 276`.


### Etapa 3.3 — Transporte >100 MB comprovado
- [x] Teste de 101 MB: 101.000.000 bytes enviados e recebidos.
- [x] Teste de 276 MB: 276.000.000 bytes enviados e recebidos.
- [x] Tailscale Funnel recebeu ambos os testes no nó local sem HTTP 413.
- [ ] O teste local de 276 MB confirma o gateway, mas ainda não confirma entrada real pela Internet.
- [ ] Ainda falta integrar esse caminho ao fluxo real `video.bsky.app -> uploadBlob`.


### Etapa 4.1 — Inspeção de identidade
- [x] `scripts/media-inspect.sh` criado para inspeção somente leitura de DID/PLC.
- [x] O comando mostra endpoint PDS atual, handle, DID e alvo Tailscale.
- [x] Integrado como `bluesky media inspect <DID ou handle>`.
- [x] Nenhuma operação PLC é enviada por esse comando.


### Nova descoberta técnica — 2026-10-04
- [x] A investigação atual encontrou o issue oficial `bluesky-social/pds#298`, que reproduz o problema de vídeo quando o hostname usado pelo usuário difere do endpoint/PDS DID.
- [x] O próprio issue registra que apontar o `AtprotoPersonalDataServer` do PLC para o endpoint público usado pelo PDS elimina a falha inicial de vídeo, embora o autor tenha encontrado outro erro de processamento depois.
- [x] O código atual do `goat` possui `plc update`, `plc sign` e `plc submit`, permitindo preparar e publicar uma nova operação PLC com alteração do endpoint PDS.
- [x] A documentação do DID/PLC confirma que `serviceEndpoint` é o local atual do PDS e deve ser uma URL HTTPS pública sem path.
- [ ] Ainda não assumir que o endpoint Tailscale será a solução final: primeiro testar uma conta isolada e confirmar o comportamento do `video.bsky.app`.


### Correção metodológica do teste — 2026-10-04
- [x] Identificado que `bluesky media test 101/276` executa o cliente no mesmo host que publica o Funnel.
- [x] Corrigida a interpretação: isso não é prova de tráfego externo/hairpin pela Internet.
- [x] Criado `scripts/media-external-test-server.sh`.
- [x] Criado `bluesky media test-external <MB>`, que deixa o servidor aguardando um POST real vindo de outra máquina/rede.
- [ ] Executar `bluesky media test-external 276` e enviar o arquivo a partir de outra conexão.


### Etapa 3.4 — Diagnóstico do POST pelo iPhone — 2026-10-04
- [x] Teste externo foi acessado pelo iPhone em rede 5G, confirmando que o Funnel está publicamente acessível fora da rede doméstica.
- [x] Identificado que o servidor de teste devolvia `0/N` quando o corpo do POST não era lido corretamente.
- [x] Atualizado `scripts/media-external-test-server.sh` para HTTP/1.1 com suporte explícito a `Expect: 100-continue`.
- [x] Adicionado suporte a `Transfer-Encoding: chunked` e diagnóstico de `Content-Length`, `Transfer-Encoding` e `Expect`.
- [x] Adicionado modo `auto` para testar arquivos reais sem exigir que tenham exatamente 101/276 MB: `bluesky media test-external auto 100`.
- [ ] Ainda não comprovar o envio efetivo de um arquivo grande pelo iPhone.
- [ ] Não alterar DID, PLC, PDS ou Cloudflare antes da comprovação do transporte externo.

Commit da correção:
- `40224e930c2f3c15c03f04c67ad936364fdb1fe8` — corrige o servidor de teste para POSTs do iPhone e adiciona modo de tamanho automático.


### Etapa 3.5 — Upload externo via navegador — 2026-10-04
- [x] Identificado que o Atalhos do iPhone alcança o endpoint externo, mas os testes de arquivo chegam ao servidor com corpo de 0 bytes.
- [x] Adicionada página HTML temporária ao `scripts/media-external-test-server.sh` com seletor de arquivo e envio via `XMLHttpRequest`/POST direto, evitando o mecanismo de `Request Body: File` do Atalhos.
- [x] A página mostra progresso do upload no Safari e a resposta HTTP do servidor.
- [ ] Ainda não comprovar o envio de arquivo grande externamente.
- [ ] Nenhuma alteração de DID, PLC, PDS ou Cloudflare.
- Commit: `bd63775285af8235a67531b69f5b1a606d4b3b9c`.


### Etapa 3.6 — Diagnóstico mínimo de POST — 2026-10-04
- [x] Adicionado botão `Testar POST de 1 KB` à página temporária do teste externo.
- [x] O teste gera exatamente 1.024 bytes no JavaScript, sem depender de Arquivos, Fotos ou seleção de mídia do iPhone.
- [x] A resposta agora registra `Content-Length`, `Transfer-Encoding`, `Content-Type` e `User-Agent`.
- [ ] Ainda falta determinar se um POST mínimo chega ao backend pelo Funnel.
- [ ] Não repetir testes de 100–276 MB até o POST de 1 KB funcionar.
- Commit: `f9db54600a3d6e85d1647310095a2f74ae69533c`.


### Etapa 3.7 — Correção de inicialização do teste — 2026-10-04
- [x] Identificada a causa do `ERRO: servidor de teste não iniciou`: chaves JavaScript não escapadas dentro do `f-string` Python da página HTML.
- [x] Corrigido o HTML embutido em `scripts/media-external-test-server.sh`.
- [x] Adicionada validação com `python3 -m py_compile` antes de iniciar o servidor.
- [x] Em caso de falha futura, o script agora mostra o erro de sintaxe/log em vez de apenas informar que o servidor não iniciou.
- [ ] Ainda falta executar o teste externo de 1 KB.
- Commit: `f68fa81a95c537569944ed74d3cc55eb10eb7902`.


### Etapa 3.8 — Correção da URL da interface — 2026-10-04
- [x] Identificado que o endereço mostrado anteriormente apontava para `/upload-test`, enquanto a interface HTML estava em `/`.
- [x] A interface agora é servida tanto em `/` quanto em `/upload-test`.
- [x] O script passa a imprimir separadamente a URL da página e o endpoint POST.
- [x] Corrigido o JavaScript embutido para uma versão sem chaves Python/JavaScript conflitantes.
- [ ] Ainda falta executar o teste de 1 KB pela nova interface.
- Commit: `74018e46c5a559a02b937266ea5d9e605fec046a`.

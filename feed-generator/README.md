# Feed Espelunca BR

Feed Generator da Espelunca.blue para o ecossistema AT Protocol.

O feed aceita somente posts marcados como `pt-BR` ou `pt` e que tenham sinal de relevância em pelo menos um dos temas configurados: notícias, memes brasileiros, tecnologia, Dead by Daylight, Fortnite e League of Legends.

Antes da publicação, ele aplica filtros baratos de idioma, tema, domínios bloqueados, marcadores explícitos de conteúdo gerado por IA e rótulos de hate/harassment/spam/scam. Os candidatos então passam por um classificador de toxicidade executado localmente e, quando há imagem/vídeo, por um classificador local de mídia sintética.

A decisão de mídia é conservadora: quando uma imagem/miniatura não pode ser inspecionada, o padrão `AI_MEDIA_UNKNOWN_ACTION=drop` remove o post do feed. O detector de IA não é prova forense; é uma camada probabilística.

## Serviço

- Host público: `feeds.espelunca.blue`
- Porta local: `3200`
- DID do serviço: `did:web:feeds.espelunca.blue`
- Banco: `/opt/espelunca-bluesky/feed-data/feed.sqlite`
- Cache: `/opt/espelunca-bluesky/feed-data/hf-cache`

## Fontes e créditos

- Bluesky Feed Generator Starter: `bluesky-social/feed-generator`
- Jetstream / `@bsky/jetstream`
- AT Protocol / Lexicons
- Transformers.js
- `onnx-community/distilbert-multilingual-toxicity-classifier-ONNX`
- `onnx-community/ai-image-detect-distilled-ONNX`

As licenças dos projetos upstream permanecem aplicáveis. O código desta pasta é MIT.

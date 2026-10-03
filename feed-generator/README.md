# Feed Espelunca BR

Feed Generator da Espelunca.blue para o ecossistema AT Protocol.

O feed aceita somente posts marcados como `pt-BR` e que tenham sinal de relevância em pelo menos um dos temas configurados: notícias, memes brasileiros, tecnologia, Dead by Daylight, Fortnite e League of Legends.

Os modelos locais são executados no runtime Node em CPU por padrão (`FEEDGEN_MODEL_DEVICE=cpu`).

Antes da publicação, ele aplica filtros baratos de idioma, conteúdo comercial/vendas, tema, domínios bloqueados, marcadores explícitos de conteúdo gerado por IA e rótulos de hate/harassment/spam/scam. Posts com links de lojas, marketplaces, plataformas de afiliados ou sinais claros de oferta/venda são descartados. Os candidatos então passam por um classificador de toxicidade executado localmente e, quando há imagem/vídeo, por um classificador local de mídia sintética.

Importante: o modelo padrão de toxicidade é multilíngue e sua documentação lista 14 idiomas, sem incluir português. Portanto, ele é usado como camada adicional de segurança, não como garantia de detecção perfeita de toxicidade em PT-BR. A variável `TOXICITY_MODEL` permite substituir o modelo por outro mais adequado ao português em uma evolução posterior.

A decisão de mídia é conservadora: quando uma imagem/miniatura não pode ser inspecionada, o padrão `AI_MEDIA_UNKNOWN_ACTION=drop` remove o post do feed. O detector de IA também é probabilístico e pode produzir falsos positivos e falsos negativos.

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

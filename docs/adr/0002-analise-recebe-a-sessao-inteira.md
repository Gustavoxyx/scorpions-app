# A análise recebe a sessão inteira, e não uma vista

O ponto onde o modelo entra — `IdentificationAnalyzer` no aplicativo, `Analyzer`
e `POST /v1/analyses` no backend — recebe **todas as vistas da sessão de uma
vez** e devolve uma conclusão. Antes, o pipeline chamava um classificador por
imagem.

Um contrato por imagem só comporta fusão tardia: classificar cada vista sozinha
e combinar depois. Um modelo que recebe as duas vistas juntas não cabe nele. Com
o contrato na sessão, cabem as quatro combinações que a fase da IA ainda vai
decidir — fusão tardia ou modelo conjunto, no aparelho ou no servidor.

## Considered Options

- **Manter o contrato por imagem.** É o que existia, e bastaria para fusão
  tardia. Recusado porque obrigaria a reabrir o pipeline se o modelo conjunto
  for o escolhido, e essa escolha é justamente a que está em aberto.
- **Definir já a forma da entrada do modelo.** Recusado: seria decidir a
  arquitetura da IA antes da fase que existe para decidi-la.

## Consequences

O classificador por imagem e o serviço de fusão continuam existindo, agora
**atrás** do analisador de fusão tardia, como uma das formas de implementá-lo.

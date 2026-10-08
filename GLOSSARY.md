# Scorpions

Identificação de espécies de escorpião a partir de fotografias tiradas pelo
usuário. Este glossário fixa as palavras do domínio para que aplicativo,
backend, regras e a futura IA falem da mesma coisa.

## Language

### A tentativa de identificar

**Sessão**:
Uma tentativa completa de identificar um escorpião: as vistas enviadas, o estado
em que a tentativa está e, quando houver, a identificação a que se chegou.
_Avoid_: identificação (para a tentativa inteira), envio, registro

**Vista**:
Uma fotografia do animal feita seguindo uma instrução de captura. Uma sessão tem
uma ou duas.
_Avoid_: foto, imagem (quando o que importa é o papel dela na sessão)

**Vista geral**:
A primeira vista de toda sessão: o animal inteiro, visto de cima.
_Avoid_: foto principal, top view

**Vista complementar**:
A segunda vista, opcional, de uma região escolhida pelo aplicativo para separar
espécies parecidas.
_Avoid_: segunda foto, close

**Instrução de captura**:
O que o aplicativo pede ao usuário antes de uma vista: que região fotografar e
como.
_Avoid_: dica, orientação

**Qualidade da vista**:
O que o aparelho mediu da fotografia antes de enviá-la — nitidez, luz, contraste
e resolução.
_Avoid_: score da imagem, nota

### O que se conclui

**Análise**:
O exame das vistas de uma sessão por um modelo. Olha a sessão inteira, e não
uma vista isolada.
_Avoid_: inferência, classificação, processamento

**Hipótese**:
Uma espécie apontada por uma análise, com a confiança atribuída a ela.
_Avoid_: predição, candidato, palpite

**Confiança**:
O número que uma análise atribui a uma hipótese. Enquanto os limiares não forem
calibrados, não é probabilidade e não é apresentado como tal.
_Avoid_: probabilidade, certeza, acurácia

**Decisão**:
O que o sistema resolve fazer com o que a análise produziu: afirmar, afirmar com
ressalva, rejeitar ou encaminhar à revisão humana. Depende da confiança, da
distância entre as hipóteses e do acordo entre as vistas.
_Avoid_: veredito, resultado (a decisão antecede a identificação)

**Identificação**:
A conclusão de uma sessão: uma espécie com a confiança da hipótese vencedora,
mais as alternativas. Só existe depois de uma análise.
_Avoid_: resultado, resposta, predição

**Rejeição**:
A conclusão de que nenhuma espécie pode ser afirmada, com o motivo. É um
desfecho válido de uma sessão, e não uma falha dela.
_Avoid_: erro, não identificado (como sinônimo de falha)

**Revisão humana**:
O exame de uma sessão por uma pessoa habilitada, quando a decisão é de não
confiar só no modelo. Pode confirmar ou corrigir a identificação.
_Avoid_: moderação, validação, feedback

**Limiar**:
Um dos números que separam uma decisão da outra. Provisório até ser calibrado
com um conjunto de validação.
_Avoid_: threshold, corte

### O catálogo

**Espécie**:
Uma espécie de escorpião descrita no catálogo.
_Avoid_: classe, rótulo, label

**Catálogo publicado**:
As espécies que o serviço em produção conhece e pode devolver.
_Avoid_: catálogo real, base de espécies

**Espécie identificável**:
Uma espécie que uma identificação pode indicar. São exatamente as do catálogo
publicado.
_Avoid_: classe do modelo

### Uso

**Limite de criação**:
Quantas sessões uma conta pode abrir por dia.
_Avoid_: cota (reservada para a de análise), rate limit

**Cota de análise**:
Quantas análises uma conta pode pedir por dia. Protege o custo do modelo.
_Avoid_: limite de criação, crédito

**Dado simulado**:
Uma identificação que não saiu de modelo nenhum, produzida para demonstrar o
fluxo. É sempre marcada como tal, e nunca é gravada em produção.
_Avoid_: mock, resultado de teste, IA de demonstração

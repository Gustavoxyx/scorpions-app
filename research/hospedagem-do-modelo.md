# O que as hospedagens de baixo custo comportam para servir um modelo de visão

Ticket: Gustavoxyx/scorpions-app#3. Data da consulta de todas as fontes: 2026-10-08.

Pergunta: para servir um classificador de imagens pequeno (transfer learning, poucas classes) atrás do backend FastAPI, o que oferecem em memória, CPU, partida a frio, limite de requisição e preço o Hugging Face Spaces (gratuito e pago), o Render e o Cloud Run no plano Blaze do Firebase, e o que cada um exige para ficar acordado.

Este arquivo só levanta fatos. Não decide onde a inferência vai rodar.

## Como ler

- Todo número abaixo leva a URL de onde saiu (consulta em 2026-10-08).
- "NÃO VERIFICADO" significa que a página oficial lida não traz o dado ou que a leitura falhou. Nenhum valor foi estimado.
- Linhas marcadas "(conta minha)" são aritmética feita por mim sobre números citados, com a conta mostrada.
- Páginas de preço do Render e do Cloud Run foram lidas no HTML cru (a ferramenta de resumo perdia as tabelas). As do Hugging Face foram lidas por resumo automático da página, com os números conferidos entre duas páginas.

## Tabela comparativa

| | HF Spaces, CPU Basic | HF Spaces, CPU Upgrade | Render Free | Render Starter | Cloud Run (Blaze) |
|---|---|---|---|---|---|
| CPU | 2 vCPU | 8 vCPU | 0,1 CPU | 0,5 CPU | até 8 vCPU por instância (configurável) |
| Memória | 16 GB | 32 GB | 512 MB | 512 MB | padrão 512 MiB; até 32 GiB (1 vCPU comporta até 4 GiB) |
| Preço | grátis na máquina, mas criar Space Docker exige plano pago (PRO, US$ 9/mês) | US$ 0,03/hora, cobrado por minuto enquanto roda | US$ 0/mês | US$ 7/mês | por uso; franquia mensal gratuita; ver seção própria |
| Dorme quando ocioso | sim, após 48 h sem uso | não por padrão (configurável) | sim, após 15 min sem tráfego | não | escala a zero por padrão (mínimo de instâncias = 0) |
| Partida a frio | NÃO VERIFICADO (a documentação só diz que o próximo visitante reinicia o Space) | não se aplica se nunca dorme | cerca de 1 minuto (documentado) | não se aplica | NÃO VERIFICADO em segundos; a documentação não dá número |
| Limite de tempo da requisição | NÃO VERIFICADO | NÃO VERIFICADO | respostas até 100 minutos (página de comparação com o Heroku) | idem | padrão 300 s, máximo 3600 s |
| Limite de tamanho da requisição | NÃO VERIFICADO | NÃO VERIFICADO | NÃO VERIFICADO | NÃO VERIFICADO | 32 MiB por requisição em HTTP/1; sem limite em servidor HTTP/2 |

## 1. Hugging Face Spaces

### Hardware e preço

Fonte: https://huggingface.co/docs/hub/spaces-gpus e https://huggingface.co/docs/hub/spaces-overview (ambas 2026-10-08).

- CPU Basic: 2 vCPU, 16 GB de memória, 50 GB de disco, "Free!".
- CPU Upgrade: 8 vCPU, 32 GB de memória, 50 GB de disco, US$ 0,03 por hora.
- Disco não é persistente. Em Docker Space, "the data written on disk is lost whenever your Docker Space restarts" (https://huggingface.co/docs/hub/spaces-sdks-docker). Para persistir, é preciso anexar um Storage Bucket, mas o modelo pode simplesmente ir dentro da imagem.
- Preço de GPU existe (T4 pequena a US$ 0,40/hora é a mais barata), mas é irrelevante para um classificador pequeno.
- Cobrança: "computed by the minute", cobra-se por cada minuto em que o Space está `Starting` ou `Running`, "regardless of whether the Space is used"; durante o build não se cobra (https://huggingface.co/docs/hub/spaces-gpus).
- Conta minha: CPU Upgrade 24 h por dia durante 30 dias = 720 h x US$ 0,03 = US$ 21,60 por mês, se nunca dormir.
- Página de preços: https://huggingface.co/pricing confirma CPU Basic "2 vCPU, 16 GB, FREE" e CPU Upgrade "8 vCPU, 32 GB, $0.03" por hora, e PRO a US$ 9/mês com "Host ZeroGPU, Gradio & Docker Spaces".

### Ponto crítico: Space gratuito de FastAPI exige plano pago

Fonte: https://huggingface.co/docs/hub/spaces-overview (2026-10-08). A página afirma que "Static Spaces are free for everyone. Gradio and Docker Spaces run on compute and require a paid plan to create: PRO for personal accounts, Team or Enterprise for organizations." Contas pessoais gratuitas só podem hospedar até 2 Spaces Gradio em ZeroGPU.

Consequências, lidas diretamente da frase acima:

- FastAPI roda como Space Docker (https://huggingface.co/docs/hub/spaces-sdks-docker diz que o SDK Docker serve "From FastAPI and Go endpoints"). Logo, em conta pessoal gratuita, não é possível criar esse Space. O custo mínimo real passa a ser o PRO, US$ 9/mês (https://huggingface.co/pricing), mais US$ 0,03/hora se quiser a máquina de 8 vCPU.
- Space estático é grátis, mas não executa Python, então não serve para inferência no servidor.
- A página não diz o que acontece com Docker Spaces criados antes dessa regra. NÃO VERIFICADO.

### Hibernação e como manter acordado

Fontes: https://huggingface.co/docs/hub/spaces-gpus (seção "Set a custom sleep time") e https://huggingface.co/docs/hub/spaces-overview (seção "Lifecycle management").

- Hardware gratuito (`cpu-basic`): "it will go to sleep if inactive for more than a set time (currently, 48 hours). Anyone visiting your Space will restart it automatically."
- Para nunca dormir ou escolher o tempo, é preciso hardware pago. "By default, an upgraded Space will never go to sleep", e há uma opção de tempo de sono personalizado; hardware pago dormindo não é cobrado.
- Também é possível pausar manualmente; Space pausado só o dono reinicia, e o tempo pausado não é cobrado.
- Quanto tempo leva para um Space adormecido voltar: NÃO VERIFICADO. A documentação não dá número.

### Limites de requisição

- Rede: o Space só faz chamadas de saída pelas portas 80, 443 e 8080 (https://huggingface.co/docs/hub/spaces-overview, seção Networking). Isso é sobre tráfego de saída.
- Porta de entrada padrão do Space Docker: 7860, configurável por `app_port` (https://huggingface.co/docs/hub/spaces-sdks-docker).
- Limite de tempo de resposta e de tamanho do corpo da requisição: NÃO VERIFICADO. Nenhuma das páginas lidas (spaces-overview, spaces-gpus, spaces-sdks-docker, spaces-sdks-docker-first-demo) traz esses números.

## 2. Render

### Planos de serviço web

Fontes: https://render.com/docs/compute-plans e https://render.com/pricing (2026-10-08).

| Plano | CPU | RAM | Preço |
|---|---|---|---|
| Free | 0,1 CPU | 512 MB | US$ 0/mês |
| Starter | 0,5 CPU | 512 MB | US$ 7/mês |
| Standard | 1 CPU | 2 GB | US$ 25/mês |
| Pro | 2 CPU | 4 GB | US$ 85/mês |

(A página de preços lista também planos maiores, de 2 CPU/8 GB a 12 CPU/96 GB. Não são relevantes aqui.)

Observação: a página de preços descreve o plano Free como "Less than 1 CPU"; a tabela de planos dá o número 0,1 CPU.

### Hibernação (plano Free) e como manter acordado

Fonte: https://render.com/docs/free (2026-10-08).

- "Render spins down a Free web service that goes 15 minutes without receiving any inbound traffic."
- Volta ao receber nova requisição HTTP; "This process takes about one minute."
- 750 horas de instância Free por mês por workspace ("Render grants 750 Free instance hours to each workspace per calendar month"). Serviço hibernado não consome horas; se acabarem, o Render suspende os serviços Free até o início do mês seguinte.
- Sistema de arquivos efêmero: perdido a cada redeploy, reinício ou hibernação. Plano Free não anexa disco persistente.
- A página diz: "Do not use them for production applications."
- Manter acordado: a página manda "upgrade to any paid compute plan" para remover as limitações do Free. O menor plano pago de serviço web é o Starter, US$ 7/mês, de 512 MB de RAM (https://render.com/pricing). Se esse plano hiberna ou não foi lido por mim como "limitação só do Free", pela frase da página, mas a página não escreve explicitamente "Starter não hiberna". NÃO VERIFICADO em texto literal.
- Mudar o plano do workspace não remove as limitações do Free; o plano de computação é independente (mesma página).

### Limites de requisição

- Tempo: "Render allows responses to take up to 100 minutes for HTTP requests." Fonte: https://render.com/docs/render-vs-heroku-comparison. A frase não distingue plano Free de pago.
- Tamanho máximo do corpo da requisição: NÃO VERIFICADO. Procurei em web-services, docker, networking, faq e troubleshooting-deploys e não achei o número.
- Largura de banda e minutos de build do Free: a página do Free diz que contam contra a franquia mensal do workspace mas "não declara o número" para o Free. NÃO VERIFICADO.

### Memória como fator

512 MB de RAM nos planos Free e Starter. Se a imagem do modelo, o PyTorch/ONNX Runtime e o FastAPI não couberem em 512 MB, o próximo plano é o Standard (2 GB, US$ 25/mês). Quanto o modelo ocupa na memória não foi medido aqui; não faz parte desta pesquisa.

## 3. Cloud Run (via plano Blaze do Firebase)

### Limites do serviço

Fontes: https://docs.cloud.google.com/run/quotas, https://docs.cloud.google.com/run/docs/configuring/services/memory-limits e https://docs.cloud.google.com/run/docs/configuring/request-timeout (2026-10-08).

- Tempo máximo por requisição: 60 minutos. Padrão: 5 minutos (300 s); configurável até 3600 s.
- Tamanho máximo de requisição HTTP/1: 32 MiB. Resposta HTTP/1: 32 MiB. Com servidor HTTP/2 não há limite de tamanho de requisição (a página diz que o limite de 32 MiB se aplica a HTTP/1).
- Memória: padrão 512 MiB por instância; máximo 32 GiB; mínimo 128 MiB (1ª geração) ou 512 MiB (2ª geração).
- Relação CPU e memória (memory-limits): 1 vCPU comporta até 4 GiB; 2 vCPU até 8 GiB; 4 vCPU de 2 a 16 GiB; 8 vCPU de 4 a 32 GiB.
- CPU máxima: 8 vCPU por instância.
- Imagem de contêiner: "There is no direct limit for the size of container images you can deploy."
- Concorrência máxima por instância (serviço): 1.000.
- Sistema de arquivos é em memória: "Files written to disk consume memory otherwise available to your service" (https://docs.cloud.google.com/run/docs/tips/general). Arquivos do modelo gravados em disco em tempo de execução gastam memória; um modelo embutido na imagem não.

### Partida a frio e como manter acordado

Fontes: https://docs.cloud.google.com/run/docs/configuring/min-instances e https://docs.cloud.google.com/run/docs/tips/general (2026-10-08).

- Padrão: mínimo de instâncias = 0, ou seja, o serviço escala a zero e a próxima requisição causa partida a frio.
- Manter acordado: configurar mínimo de instâncias maior ou igual a 1. "Cloud Run keeps at least the number of minimum instances running, even if they're not processing requests." Instâncias mantidas assim "do incur billing costs".
- Opção de "startup CPU boost" para reduzir latência de partida.
- O tamanho da imagem não afeta o tempo de partida, por causa do "container image streaming" (a página afirma isso). O tempo para carregar o modelo dentro do contêiner continua somando à partida; a página avisa que o tempo de carregar módulos soma à latência de partida.
- Requisições ficam na fila até "3.5 times average startup time of container instances of this service, or 10 seconds, whichever is greater".
- Duração da partida a frio em segundos: NÃO VERIFICADO. A documentação oficial não publica um número; só medição com o modelo real responderia.

### Preço

Fonte: https://cloud.google.com/run/pricing, HTML cru, coluna "Default (USD)" que corresponde à região Iowa (us-central1), Tier 1 (2026-10-08).

Faturamento por requisição (serviço só cobra enquanto processa requisições):

- Franquia mensal gratuita (base us-central1): 180.000 vCPU-segundos, 360.000 GiB-segundos e 2 milhões de requisições.
- CPU ativa: US$ 0,000024 por vCPU-segundo. Memória ativa: US$ 0,0000025 por GiB-segundo. Requisições: US$ 0,40 por milhão.
- Instância mínima ociosa: CPU US$ 0,0000025 por vCPU-segundo; memória US$ 0,0000025 por GiB-segundo.

Faturamento por instância (instância cobrada durante todo o ciclo de vida): franquia mensal gratuita de 240.000 vCPU-segundos e 450.000 GiB-segundos (mesma página). Os preços unitários desse modo não foram extraídos; NÃO VERIFICADO.

Conta minha (instância mínima, 1 vCPU e 2 GiB, ociosa o mês todo, Tier 1, sem aplicar franquia): (0,0000025 x 1 + 0,0000025 x 2) US$/s x 2.592.000 s (30 dias) = US$ 19,44 por mês. Isso é só para dar ordem de grandeza; a franquia mensal gratuita e a atividade real mudam o valor.

Região: a página classifica southamerica-east1 (São Paulo) como Tier 2. Os preços de Tier 2 não apareceram no HTML estático; os acima são de Tier 1 (Iowa). Preço em São Paulo: NÃO VERIFICADO.

### Relação com o Blaze

Fonte: https://firebase.google.com/pricing (2026-10-08).

- O Blaze é o plano pago por uso; o Spark é descrito como "No payment method needed". A página do Firebase não traz franquia própria do Cloud Run; remete à página de preços do Cloud Run (https://cloud.google.com/run/pricing). Os números de franquia do Cloud Run acima vêm dessa página do Google Cloud, não do Firebase.
- A página do Firebase não detalha o que é exigido para ativar o Blaze (cartão, conta de faturamento). NÃO VERIFICADO nesta fonte.
- A página lista "If eligible, get $300 in free credit" no Blaze; elegibilidade não foi verificada.
- Alertas de orçamento e teto de gasto: NÃO VERIFICADO (não estavam na página lida).

## Resumo do que cabe e do que não cabe

- Hugging Face: a máquina gratuita é folgada (16 GB, 2 vCPU) para um modelo pequeno, mas a página oficial diz que criar Space Docker (o jeito de rodar FastAPI) exige plano pago. Com o PRO a US$ 9/mês, a máquina grátis cobre o caso e dorme após 48 h sem uso; ficar sempre acordado exige hardware pago (CPU Upgrade, US$ 0,03/hora, cerca de US$ 21,60 por mês, conta minha). Limites de tempo e de corpo da requisição não estão nas páginas lidas.
- Render: o plano Free tem só 0,1 CPU e 512 MB e hiberna em 15 minutos, com cerca de 1 minuto para voltar; o Starter (US$ 7/mês) mantém 512 MB, e 2 GB só chega no Standard a US$ 25/mês. Tempo de resposta de até 100 minutos.
- Cloud Run: único com todos os limites de requisição documentados (300 s padrão, 32 MiB em HTTP/1) e memória ajustável de 512 MiB a 32 GiB. Escala a zero por padrão, com franquia mensal gratuita; ficar sempre morno custa a instância mínima (ordem de US$ 19 por mês para 1 vCPU e 2 GiB em Tier 1, conta minha). Duração da partida a frio não é publicada.

## O que não foi possível verificar

1. Tempo para um Space do Hugging Face voltar da hibernação, e limites de tempo e de tamanho de requisição do Spaces.
2. Limite de tamanho do corpo da requisição no Render.
3. Se o Render Starter nunca hiberna, em texto literal. A página do Free atribui a hibernação ao plano Free, mas não escreve a negativa para o Starter.
4. Largura de banda e minutos de build incluídos no plano Free do Render (número ausente).
5. Preços de Cloud Run em Tier 2 (São Paulo) e preços unitários do faturamento por instância.
6. Duração real da partida a frio no Cloud Run, no Render e no Hugging Face com um modelo de visão. Só medindo com o modelo real.
7. Requisitos de ativação do Blaze, alertas de orçamento e elegibilidade ao crédito de US$ 300.
8. Se Docker Spaces gratuitos criados antes da regra de plano pago continuam rodando.

## Fontes

- https://huggingface.co/docs/hub/spaces-overview
- https://huggingface.co/docs/hub/spaces-gpus
- https://huggingface.co/docs/hub/spaces-sdks-docker
- https://huggingface.co/docs/hub/spaces-sdks-docker-first-demo
- https://huggingface.co/pricing
- https://render.com/docs/free
- https://render.com/docs/compute-plans
- https://render.com/pricing
- https://render.com/docs/render-vs-heroku-comparison
- https://cloud.google.com/run/pricing
- https://docs.cloud.google.com/run/quotas
- https://docs.cloud.google.com/run/docs/configuring/services/memory-limits
- https://docs.cloud.google.com/run/docs/configuring/request-timeout
- https://docs.cloud.google.com/run/docs/configuring/min-instances
- https://docs.cloud.google.com/run/docs/tips/general
- https://firebase.google.com/pricing

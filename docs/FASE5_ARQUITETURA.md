# Fase 5 — Arquitetura

**Status:** plano aprovado, implementação em andamento
**Decisões tomadas em 2026-10-05:** inferência em backend próprio gratuito; dataset de bancos públicos

---

## 1. Arquitetura atual (auditada antes de propor)

```
Flutter
├── features/   33 arquivos  telas, widgets
├── state/       6 arquivos  ChangeNotifier
├── data/       41 arquivos  models, repositories, services
└── core/       32 arquivos  tema, constantes, observabilidade
        │
        └──► Firebase (direto do cliente)
             Auth · Firestore · Storage · App Check
```

**Não há backend.** O aplicativo fala direto com o Firebase, e as Security Rules são a única autoridade.

O que a Fase 4 deixou pronto e que esta fase reaproveita sem reescrever:

| Peça | Papel na Fase 5 |
|---|---|
| `ImageValidator` | valida cada uma das duas imagens |
| `ImageQualityService` | qualidade individual; a combinada é nova |
| `MetadataStripper` | remove EXIF/GPS das duas |
| `ImageProcessingService` | as três formas, por imagem |
| `IdentificationPipeline` | vira orquestrador de sessão, não de foto única |
| `ScorpionDetectionService` | interface já existe, respondendo "não avaliado" |
| `SpeciesClassificationService` | idem — é onde o modelo real entra |
| `AppLog` | observabilidade com trava de conteúdo |

A Fase 4 já previu esta fase: as duas interfaces de IA existem e devolvem `notEvaluated`. Não há mock a remover — há implementação a preencher.

---

## 2. O conflito que decidiu a arquitetura

A auditoria (`security/SECURITY_AUDIT.md`, HIGH-1) encontrou que **o cliente escreve `confidence`, `modelVersion` e `status`**. A regra valida formato, não origem.

Sem IA isso quase não importa. Com IA, um `confidence: 0.99` forjado contamina métricas, fila de revisão e dataset de retreinamento — exatamente o que o §11 do briefing proíbe.

Logo: **a inferência roda no servidor, e o cliente perde o direito de escrever o resultado.**

Cloud Functions exigiria Blaze, que ainda não foi aprovado. A saída escolhida não depende disso.

---

## 3. Arquitetura proposta

```
Flutter  (não confiável)
   │
   │  ID token do Firebase
   ▼
Backend de inferência  (FastAPI, plano gratuito)
   │  valida o token com Firebase Admin
   │  baixa as imagens do Storage
   │  roda detecção + classificação nas duas vistas
   │  funde, calcula confiança, decide
   │
   ├──► escreve o resultado com Admin SDK  ──► Firestore
   └──► encaminha para revisão quando preciso
```

O cliente cria o documento com `status: 'processing'` e **nada mais**. A regra passa a recusar qualquer escrita de `species`, `confidence`, `modelVersion` ou `speciesId` vinda dele.

A service account vive nos secrets do servidor. Nunca no aplicativo — §32 e §35 intactos.

### Por que não Cloud Functions

Exige Blaze. A decisão do orientador não pode bloquear a fase.

### Por que não só TFLite no dispositivo

Resposta rápida e sem custo, mas o resultado continua vindo do cliente — não resolve o HIGH-1. Fica como possibilidade futura de camada de pré-visualização, com o registro oficial sempre vindo do servidor.

---

## 4. Domínio multi-view

O coração da fase, e a parte que **não depende do modelo** para estar correta.

```
CaptureType         topView · closeUp · pedipalp · tail · telson · generalSideView
ImageCaptureInstruction   id · title · description · captureType · targetRegion · priority
CapturePlan         sequência de instruções, estratégia configurável

IdentificationSession
  ├── primary:   SessionImage
  ├── secondary: SessionImage?
  └── status · modelVersion · createdAt · updatedAt

ViewPrediction      vista → candidatos ordenados + versão do modelo
CrossViewConsistency  concordância no topo · correlação de ranks · divergência de distribuição
MultiViewFusionService  estratégias: média tardia, máximo, ponderada por confiança,
                        ponderada por qualidade
ConfidenceEngine    score · margem Top1–Top2 · consistência · qualidade → decisão
DecisionLevel       highConfidence · mediumConfidence · lowConfidence · reject · humanReview
```

**Os limiares moram em um lugar só** (`DecisionThresholds`), nunca na interface — §12 e §15.

**Fusão e confiança são algoritmos**, testáveis com vetores de score sintéticos. Serão medidos antes de existir qualquer modelo, e continuarão válidos quando ele chegar.

---

## 5. Tecnologias novas

| O quê | Para quê | Justificativa |
|---|---|---|
| FastAPI + Uvicorn | backend de inferência | leve, tipado, roda no plano gratuito |
| PyTorch + torchvision | treino e inferência | transfer learning com MobileNetV3 |
| firebase-admin (Python) | validar token, escrever resultado | única forma de o servidor ter autoridade |
| Pillow | decodificação no servidor | validação de assinatura real do arquivo (LOW-1) |

Nenhuma dependência nova no Flutter. O aplicativo ganha um cliente HTTP, e `http` já vem transitivamente.

---

## 6. Dataset

**Origem:** iNaturalist e GBIF, imagens com licença Creative Commons das cinco espécies do catálogo.

**Limitação que precisa estar escrita no TCC:** são fotografias avulsas, não pares do mesmo espécime. A §27 pede a comparação *só foto 1 / só foto 2 / foto 1 + foto 2*, e ela **não poderá ser respondida com honestidade** com esse material — não há como saber qual par de fotos pertence ao mesmo animal.

O que será feito no lugar, e documentado como aproximação:

- treinar o classificador de vista única com as imagens reais;
- medir accuracy, precision, recall, F1, Top-1, Top-3 e matriz de confusão de verdade;
- avaliar a fusão com **pares sintéticos** (duas fotos de espécimes diferentes da mesma espécie), o que mede a robustez da fusão mas **não** o ganho de vistas complementares.

A diferença entre as duas coisas será dita explicitamente no relatório de métricas. Não será apresentada como resposta à §27.

**Controle de vazamento (§23):** o split será por *observação* do iNaturalist, não por imagem — várias fotos da mesma observação são do mesmo animal e não podem cair em treino e teste ao mesmo tempo.

---

## 7. Etapas

| # | Entrega | Depende de | Situação |
|---|---|---|---|
| 1 | Correções de segurança baratas (MEDIUM 1–2), regras preparadas | — | 🟢 feito |
| 2 | Domínio multi-view: sessão, fusão, consistência, confiança | — | 🟢 feito |
| 3 | Fluxo de duas fotos nas telas | 2 | 🟢 feito |
| 4 | Backend FastAPI: token, validação, escrita com Admin | 1 | 🟢 feito — **não publicado** |
| 5 | Dataset + treino + métricas reais | 4 | 🔴 **não começado** |
| 6 | Human-in-the-loop: fila, RBAC, painel | 4 | 🔴 não começado — o endpoint da fila existe e devolve vazio |
| 7 | Exclusão de conta em cascata (HIGH-2) | 4 | 🟢 feito |
| 8 | Documentação de segurança restante | todas | 🟢 feito |

### O que "feito" quer dizer na etapa 3, e o que não quer

O aplicativo captura duas fotografias, registra as duas na mesma identificação,
envia as duas em paralelo e mostra o que a fusão concluiu.

O que **não** existe é modelo. Então:

- com Firebase, as duas fotos são guardadas e o registro fica em `processing` —
  o estado honesto. Nenhuma espécie e nenhum resumo de fusão aparecem;
- no modo de demonstração, o que cada foto "disse" é **simulado**, e a fusão e a
  decisão são as de produção. Dá para mostrar o que o sistema faz quando duas
  vistas concordam e quando discordam. Não dá para mostrar o sistema acertando
  a espécie — e a tela diz isso, com o selo de dado simulado.

### Decisões tomadas na etapa 3 que este plano não tinha

**Onde a segunda imagem mora.** Na mesma pasta da identificação, com sufixo:
`original-2`, `processed-2`, `thumbnail-2`. Mesma pasta porque são a mesma
identificação — apagar o registro apaga as duas com um prefixo só. Só `-2`, e
não um padrão aberto: um cliente adulterado guardaria `original-3` até
`original-999` sem registro que os referencie. A regra do Storage, o aplicativo
e o backend concordam nesses nomes, e há teste nos três.

**Como o documento guarda a segunda vista.** Num mapa `secondaryView`, e não
numa lista `views`. Os campos de topo continuam descrevendo a primeira foto,
então todo registro anterior é lido sem migração. O briefing fixa duas fotos; a
generalidade de uma lista custaria reescrever o histórico para não servir a
nada.

**O que é do cliente e o que é do servidor.** `secondaryView` é do cliente: ele
capturou, mediu e enviou. `fusion` — se as vistas concordaram, quanto, e qual
foi a decisão — é do servidor, e entrou em `serverOwnedFields()`. Forjar "as
duas fotos concordaram" é o mesmo ataque de forjar `confidence: 0.99`.
`secondaryView` é validado com `hasOnly`: sem isso, um mapa aninhado aberto
seria o lugar óbvio para esconder uma conclusão um nível abaixo de onde a regra
olha.

**A segunda foto é oferecida, não imposta.** O animal pode ter fugido; a pessoa
pode não querer chegar perto. Seguir com uma foto só é um botão na tela de
confirmação, e uma segunda foto recusada na inspeção não prende ninguém.

**A instrução fica fixada quando a câmera abre.** O registro guarda o que foi
*pedido* junto do que foi obtido, e o pedido gravado precisa ser o que a pessoa
viu ao fotografar.

### Três coisas que a etapa 3 achou no caminho

1. **No modo de demonstração, cada identificação deixava dois registros no
   histórico.** O pipeline gravava com um id; o motor simulado devolvia o
   desfecho com outro; os dois eram salvos. O comentário do método dizia
   "mantendo id" — o código não mantinha. Existia desde a Fase 4.
2. **`IdentificationResult.toMap()` quebrava em registros sem hipótese.** Só
   perguntava se o registro fora rejeitado; um em `processing` não foi rejeitado
   *e* não tem hipótese. Nunca apareceu porque o método só era chamado em
   resultados concluídos.
3. **A qualidade da foto não entra na fusão padrão.** A estratégia padrão
   pondera pela confiança de cada vista; o peso de qualidade é calculado e
   viaja junto, mas só `qualityWeighted` o lê. Com a padrão, a qualidade
   influencia a *decisão*, não os scores. Um teste meu afirmava o contrário e
   falhou. Qual estratégia serve melhor é pergunta que só um modelo avaliado
   responde — é parte da etapa 5.

### O que falta, em ordem

A etapa 5 é a que destrava tudo: sem modelo, a etapa 6 não tem o que revisar, os
limiares de `DecisionThresholds` continuam sendo palpites (`calibrated = false`),
e o validador de imagem do backend continua sem quem o chame.

Ela não cabe na máquina de desenvolvimento — i3 de dois núcleos, sem GPU. O
treino precisa de um ambiente com GPU (Colab ou Kaggle, no plano gratuito), e
isso é decisão a tomar antes de começar.

---

## 8. Riscos

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Dataset público pequeno demais para acurácia útil | alta | reportar a métrica real, por baixa que seja; o briefing proíbe inventar |
| §27 sem resposta por falta de pares | **certa** | documentar como limitação metodológica, não disfarçar |
| Plano gratuito do backend hibernar | alta | primeira chamada lenta; a interface precisa tratar isso sem parecer travada |
| Treino no i3 sem GPU inviável | alta | treinar no Google Colab, versionar o artefato |
| Escopo da fase maior que o prazo | alta | entregar por etapas, cada uma verificada e commitada |

---

## 9. Plano de testes

**Unitários, sem modelo:** fusão com vistas concordantes, discordantes e com uma vista ausente; consistência entre distribuições; cada nível de decisão do confidence engine; limiares de fronteira; qualidade combinada quando uma imagem é ruim.

**Integração:** sessão com duas imagens válidas; primeira inválida; segunda inválida; ambas ruins; vistas conflitantes; espécie desconhecida; backend fora do ar; timeout; upload falho.

**Segurança (contra o emulador):** cliente tentando escrever `confidence`; cliente tentando alterar `species` num documento existente; usuário A lendo sessão de B; usuário tentando promover-se a `admin`; upload acima do limite; arquivo com extensão não prevista.

Os testes de segurança entram no mesmo job de CI que já roda as 53 regras.

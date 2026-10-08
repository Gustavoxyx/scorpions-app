# Fase 0 — Preparação para a IA

**Objetivo:** deixar o projeto seguro, consistente e testável para receber a
identificação por IA na fase seguinte. Nenhuma IA é implementada aqui.

**Ponto de partida:** auditoria de 2026-10-07 sobre o commit `a9e8ecd`
(achados `S-xx` de segurança e `Q-xx` de qualidade).

**Branch:** `fase-0-preparacao-ia`. **Vocabulário:** [GLOSSARY.md](../GLOSSARY.md).
**Decisões:** [docs/adr/](adr/).

## Restrições que valeram para todas as tarefas

- Não implementar inferência, treino, dataset nem escolher o modelo.
- Não trocar Flutter, Firebase ou FastAPI.
- Nenhum segredo no repositório; nada de credencial administrativa no app.
- O que é conclusão de análise só o servidor escreve.
- O modo `mock` e o emulador continuam funcionando.
- Não fingir que o Cloud Storage de produção existe.
- Os limiares de confiança são provisórios: centralizar, não recalibrar.

## Revisão de arquitetura

**Com todos os requisitos conhecidos hoje, incluindo a IA, a stack seria a
mesma? Sim.** Python é o lugar natural da inferência no servidor, Flutter
comporta inferência no aparelho por plugin, e o backend já existe pelas
operações que exigem o Admin SDK — não é uma ponte criada para a IA.

**A arquitetura evolui sem reconstrução.** O que não estava pronto era o nível
da costura onde o modelo entra:

| | Antes | Depois |
|---|---|---|
| O pipeline chama | detector e classificador **por imagem** | um analisador **por sessão** |
| Comporta fusão tardia | sim | sim |
| Comporta modelo de duas entradas | **não** | sim |
| Comporta inferência remota | não | sim (mesmo nível do `POST /v1/analyses`) |

O contrato por sessão já existia em `MultiViewAnalysisService`, sem consumidor.
A mudança foi ligá-lo ao pipeline atrás de `IdentificationAnalyzer`. Ver
[ADR 0002](adr/0002-analise-recebe-a-sessao-inteira.md).

### Tensão de nomes, registrada e não resolvida

O glossário separa **sessão** (a tentativa) de **identificação** (a conclusão).
No código, o registro da tentativa inteira se chama `IdentificationResult` e
mora na coleção `identifications`; a classe `IdentificationSession` só existe
como entrada do analisador. Renomear a coleção é migração de dados, e não cabe
aqui. O nome novo vale para o que for escrito daqui em diante: o backend já
chama o identificador de `sessionId`.

## Triagem

| Prioridade | Significado | Itens |
|---|---|---|
| **P0** | bloqueia segurança ou funcionamento | nenhum em aberto |
| **P1** | precisa estar fechado antes da IA | todos os de código fechados; restam cinco ações externas |
| **P2** | pode ser feito durante a IA | seis itens, listados abaixo |
| **P3** | melhoria futura | sete itens, listados abaixo |

## Tickets

Fechados nesta fase. O detalhe de cada um está na mensagem do commit.

| Ticket | O que fecha | Achado | Commit |
|---|---|---|---|
| SEC-001 | Limite de criação de sessões, imposto pelas regras | S-01 | `030acb0` |
| SEC-002 | O cliente não muda o estado da sessão | S-03 | `030acb0` |
| SEC-003 | Lista fechada de campos em `identifications`; `feedback` fechada | S-04 | `030acb0` |
| SEC-004 | E-mail confirmado para criar, enviar e pedir análise | S-06 | `030acb0`, `d8afe98` |
| SEC-005 | Limite de chamadas no backend, por endereço e por conta | S-13 | `d8afe98` |
| SEC-006 | Validação de imagem no caminho real da análise | S-07 | `d8afe98` |
| SEC-007 | App Check: o backend verifica e o app envia (exigência desligada) | S-05 | `d8afe98`, `9390c1b` |
| SEC-008 | Segundo fator para papel privilegiado (exigência desligada) | S-15 | `d8afe98` |
| SEC-009 | Metadados removidos de JPEG, PNG e WebP; falha para o lado seguro | S-08 | `9390c1b` |
| SEC-010 | Foto temporária apagada ao sair do fluxo | S-14 | `9390c1b` |
| SEC-011 | Release sem chave de debug; permissões de microfone e armazenamento fora | S-02, S-12 | `0b02ffa` |
| SEC-012 | Aviso de privacidade no app e aceite no cadastro | S-09 | `15de35e` |
| ARCH-001 | Fronteira de análise no nível da sessão | Q-02 | `9390c1b` |
| ARCH-002 | Contrato de resposta da análise no backend | — | `d8afe98` |
| ARCH-003 | Uma fonte de limiares | Q-01 | `5a9aa04` |
| ARCH-004 | Vocabulário de espécies identificáveis = catálogo publicado | Q-04 | `5a9aa04` |
| ARCH-005 | Mesmo vocabulário de papéis no app e no backend | S-17 | `5a9aa04` |
| ARCH-006 | Papel lido só onde é usado | Q-08 | `d8afe98` |
| CLEAN-001 | Código sem referência, supressão de lint, comentários históricos | Q-09, Q-10, Q-11, Q-14 | `030acb0`, `a60b362` |

### P1 em aberto — dependem de ação fora do código

| # | Ação | Por que não foi feita aqui |
|---|---|---|
| 1 | **Publicar as regras junto com a versão nova do aplicativo.** `firebase deploy --only firestore:rules --project production` | Publicar em produção é decisão sua. As regras novas e o aplicativo antigo não conversam: sem o contador de criação, o aplicativo antigo não cria sessão. |
| 2 | **Confirmar o e-mail da sua própria conta** antes de publicar as regras | As regras novas exigem e-mail confirmado para criar sessão. Uma conta sem confirmação continua lendo e apagando, mas não cria. |
| 3 | **Criar a keystore de release** e `android/key.properties` | Quem perde a keystore não publica mais atualização. Ela precisa nascer com quem vai guardá-la. Modelo em `android/key.properties.example`. |
| 4 | **App Check:** registrar o Play Integrity com o SHA-256 da chave de release, ligar a exigência no console e definir `REQUIRE_APP_CHECK=1` no backend | Depende do item 3 e do console. Ligado antes de registrar o provedor, barra o próprio aplicativo. |
| 5 | **Segundo fator** na conta Google dona do projeto | É configuração da sua conta. Para contas do aplicativo, exige o Identity Platform; depois disso, `REQUIRE_MFA_FOR_STAFF=1`. |

Também dependem de fora: publicar o backend e definir `BACKEND_URL` (sem isso,
exclusão de conta, exportação e cota de análise não alcançam ninguém); o plano
Blaze (Storage, backups, recuperação pontual); política de senha no console; e a
definição institucional do texto de privacidade e dos termos.

### P2 — pode ser feito durante a fase da IA

| Item | Por que pode esperar |
|---|---|
| Unificar a demonstração com o analisador (Q-03). Hoje o desfecho simulado sai de `MockIdentificationService` + `DemoMultiViewService`, fora de `IdentificationAnalyzer`. | Unificar agora seria refatorar o controlador e ~60 testes para trocar um dublê por outro. Com um classificador de verdade, a demonstração vira só outra implementação da mesma interface. |
| O aplicativo chamar `POST /v1/analyses`. | Depende da decisão entre inferência no aparelho e no servidor. |
| Paginação do histórico (Q-06). | Limite de 100 registros por conta, e sem modelo quase não há registros. |
| Persistir onboarding e preferências (Q-07). | Defeito de experiência, sem relação com a IA; pede uma dependência nova. |
| Convidar contas antigas a aceitar o aviso de privacidade. | As regras já aceitam a renovação; falta a tela. |
| Teste do repositório do Firestore contra um Firestore falso. | A transação do contador é coberta pelas regras no emulador e pelo teste de contrato, mas não por teste de unidade no Dart. |

### P3 — melhoria futura

Arquivos grandes (Q-12); idiomas misturados nos identificadores (Q-13); o
restante dos comentários históricos (Q-14); build de iOS; backups e recuperação
pontual; executor de retenção; registro de leitura administrativa direta.

## Onde a IA entra

| # | Ponto de entrada | O que existe hoje | O que a fase da IA faz |
|---|---|---|---|
| 1 | `IdentificationAnalyzer` — `lib/data/services/multi_view_analysis_service.dart` | Interface por sessão; `MultiViewAnalysisService` a implementa com fusão tardia sobre dublês que respondem "não avaliado". | Fornece outra implementação, ou classificadores de verdade para a existente. Injeta em `IdentificationPipeline(analyzer:)`, em `lib/app/dependencies.dart`. |
| 2 | `IdentificationPipeline._analisar` | Entrega a sessão ao analisador e **afirma** que nada foi avaliado. O resultado é descartado. | Remove a afirmação e leva a análise até o controlador, que hoje cai em `IdentificationAwaitingModel`. |
| 3 | `analysis.get_analyzer()` — `backend/app/analysis.py` | Devolve `None`; `POST /v1/analyses` responde 503. | Devolve um `Analyzer`. Autenticação, e-mail confirmado, cota, limite de chamadas e validação das imagens já estão antes dele. |
| 4 | Gravação do resultado no Firestore | **Não existe.** As regras já reservam os campos ao servidor. | O backend grava espécie, confiança, alternativas, `fusion`, `modelVersion` e o estado, com o Admin SDK. |
| 5 | `DecisionThresholds` (Dart) e `fusion.py` (Python) | Mesmos números nos dois lados, conferidos por teste de paridade; `calibrated = false`. | Calibra com um conjunto de validação e vira `calibrated`. |
| 6 | `MockSpecies.identifiable` e `firebase/species-data.mjs` | Cinco espécies, iguais nos dois lados por teste. | É o conjunto de classes do modelo. Mudar um lado quebra o teste. |
| 7 | `GET /v1/review-queue` e `needsHumanReview` | Endpoint com papel conferido no servidor, devolvendo vazio. | Enfileira o que a decisão encaminhar. |

## Decisões adiadas de propósito

- Fusão tardia ou modelo que recebe as duas vistas juntas.
- Inferência no aparelho ou no servidor — com a consequência de segurança
  descrita no [ADR 0001](adr/0001-identificacao-e-escrita-so-pelo-servidor.md).
- Família do modelo, dataset e onde treinar.
- Cinco ou oito espécies: três só existem na demonstração porque o conteúdo
  delas não foi curado.

## Riscos conhecidos

1. **Regras e aplicativo mudam juntos.** Publicar um sem o outro quebra a
   criação de sessões.
2. **O Storage de produção não existe.** O envio de imagem falha e a sessão fica
   marcada com erro; a validação de imagem no backend nunca rodou contra um
   bucket de verdade.
3. **O limite de chamadas do backend vive na memória de um processo.** Com mais
   de um processo, cada um conta sozinho.
4. **A câmera e o envio real não têm teste automatizado.** O que os cobre é o
   emulador e o uso manual.
5. **O aviso de privacidade é preliminar** e não passou por revisão
   institucional.
6. **No emulador, toda conta nasce sem e-mail confirmado**, e as regras exigem a
   confirmação para criar sessão. O link aparece na interface do emulador, na
   aba Authentication.
7. **A exclusão de conta não trava a conta durante a cascata.** Uma sessão
   criada pelo próprio titular enquanto a exclusão roda pode sobrar órfã.
8. **O limite de criação admite uma rajada inicial.** A regra aceita o dia do
   servidor e os vizinhos, então uma conta nova pode gastar de uma vez a cota de
   ontem, hoje e amanhã. A média continua sendo o limite diário.

## Verificação

Executada sobre o branch, depois do último commit de código.

| O quê | Antes | Depois |
|---|---|---|
| `flutter analyze` | sem apontamentos | sem apontamentos |
| Testes do aplicativo | 319 | **355**, todos passando |
| Testes do backend | 177 | **219**, todos passando |
| Testes das regras, no emulador | 85 | **110**, todos passando |
| Manifesto mesclado de release | câmera, internet, rede, **microfone, armazenamento** | câmera, internet, rede |
| Release sem chave de assinatura | assinado com a chave de debug | **build interrompido**, com instrução |
| APK de release (arm64), com a saída de emergência | 21.802.744 bytes | 21.802.640 bytes, compila |

**Revisão de segurança.** O `/security-review` nativo não chegou a rodar: o
comando exige `origin/HEAD` no repositório, que este clone não tem. O que rodou
foi uma segunda instância do Claude Code, dentro do repositório, revisando o
diff do branch de forma independente. Três achados: o limite por endereço atrás
de proxy (corrigido em `b1c8944`), e os itens 7 e 8 da lista de riscos acima.
Ela não leu o removedor de metadados nem a tela de cadastro.

**O que não foi verificado.** O aplicativo não foi executado num aparelho. A
transação do contador de criação só foi exercitada pelas regras no emulador, a
partir do teste — nunca pelo SDK do Firestore no Dart. O build de iOS continua
sem nunca ter sido feito.

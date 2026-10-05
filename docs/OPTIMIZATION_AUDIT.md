# Auditoria de otimização

Diagnóstico do projeto antes de qualquer mudança de desempenho, como o
briefing exige: *"NÃO MODIFIQUE O PROJETO ANTES DE TERMINAR O DIAGNÓSTICO
INICIAL."*

Data: 5 de outubro de 2026. Commit auditado: o mesmo que fechou o HIGH-1.

## Resumo em uma tela

| | |
|---|---|
| Arquivos Dart em `lib/` | 128, com 19.404 linhas |
| Dependências diretas | 13 — **todas em uso** |
| Dependências removíveis | **nenhuma** |
| Assets empacotados | **zero** |
| Arquivos nunca importados | 1, e não é código morto (ver M-1) |
| Pastas de backup, `.bak`, código comentado em bloco | nenhuma |
| `TODO`/`FIXME` em `lib/`, `test/`, `backend/app/` | nenhum |
| Listeners de Firestore em tempo real | nenhum |
| `StreamSubscription` sem `cancel()` | nenhum |
| Listas não virtualizadas | nenhuma |

O achado mais sério desta auditoria não é de desempenho: **o APK de release
não compilava** (B-1). Isso bloqueava a medição de tamanho que o §40 pede e,
muito antes disso, bloqueava instalar o aplicativo em um aparelho.

## O que não se aplica a este projeto, e por quê

O briefing foi escrito para um aplicativo com modelos 3D, fotografias,
bibliotecas de ícones e fontes. Boa parte dele não encontra alvo aqui. Dizer
isso é mais honesto que inventar trabalho:

| Seção do briefing | Situação |
|---|---|
| §13 thumbnails, §14 imagens, §15 ícones, §16 fontes | ⚪ `pubspec.yaml` não declara **nenhum** asset. A identidade visual é desenhada em `CustomPainter`. Não existe um arquivo de imagem no aplicativo. |
| §11, §12, §30, §31 modelos 3D | ⚪ Nenhum arquivo 3D é empacotado nem hospedado. `Species.model3D` existe como campo e é **sempre nulo**. A arquitetura que o §11 pede — metadado no app, modelo em armazenamento remoto — já é a que está no lugar, por ainda não haver modelo. |
| §32 duplicação de assets | ⚪ Sem assets, sem duplicação de assets. |
| §34 backups dentro do projeto | 🟢 Procurado: `old/`, `backup/`, `temp/`, `final/`, `*.bak`, `*~`, `*copia*`. Nada. O repositório rastreia 25 arquivos fora de `lib/`, `test/`, `backend/` e as pastas de plataforma — todos com função. |
| §33 código comentado | 🟢 Nenhum bloco de código comentado. Nenhum `TODO` ou `FIXME` no código do aplicativo. |

As únicas fontes no pacote são as de ícone do Flutter, e o tree-shaking já as
corta — **medido na saída do próprio build**:

```
CupertinoIcons.ttf       257.628 →    848 bytes   (99,7%)
MaterialIcons-Regular.otf 1.645.184 → 14.700 bytes (99,1%)
```

## ETAPA 1 — Mapa da arquitetura

```
lib/
├── main.dart ─────── ponto de entrada (31 linhas)
├── app/ ───────────── composição + go_router (3 arquivos)
├── core/
│   ├── widgets/ ───── 17 widgets compartilhados, vários CustomPainter
│   ├── theme/ ─────── 8 arquivos (cores, tipografia, tema)
│   ├── constants/ ─── 5 (limites de imagem, limiares de decisão, ambiente)
│   ├── utils/ ─────── 2
│   └── observability/ AppLog, com a trava de conteúdo em assert
├── data/
│   ├── models/ ────── 17 modelos puros, sem dependência de Firestore
│   ├── services/ ──── 22 serviços atrás de interfaces
│   ├── repositories/  7, cada um com par simulado
│   └── mock/ ──────── 2 (catálogo de demonstração)
├── features/ ──────── 14 telas
└── state/ ─────────── 6 ChangeNotifier

backend/   FastAPI — inferência, autenticação por ID token, fusão
firebase/  Security Rules, seeds, 60 testes de regra
```

Topo da lista por tamanho — nenhum arquivo gigante, nenhuma "God class":

```
461  features/camera/capture_page.dart
455  data/models/identification.dart
453  features/identification/result_page.dart
371  features/home/home_page.dart
366  data/services/identification_pipeline.dart
```

## ETAPA 2 — Dependências

As 13 diretas, com a contagem de arquivos que as importam:

| Pacote | Importado em | Veredito |
|---|---|---|
| `provider` | 21 | em uso |
| `go_router` | 17 | em uso |
| `image` | 9 | em uso |
| `cloud_firestore` | 5 | em uso |
| `firebase_auth` | 4 | em uso |
| `firebase_core` | 3 | em uso |
| `camera` | 3 | em uso |
| `firebase_storage` | 2 | em uso |
| `permission_handler` | 1 | em uso |
| `image_picker` | 1 | em uso |
| `firebase_app_check` | 1 | **em uso, e é segurança** (§36: não remover) |
| `connectivity_plus` | 1 | em uso |
| `cupertino_icons` | **0** | **manter** — ver abaixo |

`cupertino_icons` não aparece em nenhum `import` e mesmo assim precisa ficar:
`app_theme.dart` usa `CupertinoPageTransitionsBuilder`, cujos `IconData`
declaram a família de fontes deste pacote. Sem ele, cada build avisa
`Expected to find fonts for (…CupertinoIcons)`. Já foi removido uma vez numa
limpeza e teve de voltar; o custo real medido é **848 bytes** após
tree-shaking. O comentário no `pubspec.yaml` existe para que não saia de novo.

**Nenhuma dependência é removível.** Nenhuma tem substituta nativa mais leve
que valha a troca. `npm audit --omit=dev` nas ferramentas de teste do Firebase
dá 0 — a CVE do `@grpc/grpc-js` registrada em `SECURITY_AUDIT.md` (MEDIUM-6)
está só em dependências de desenvolvimento.

## ETAPA 4 — Bundle

**Web** (`build/web`, 42 MB brutos — e o número bruto engana):

```
7.060 KB  canvaskit/canvaskit.wasm
5.626 KB  canvaskit/chromium/canvaskit.wasm
5.051 KB  canvaskit/skwasm_heavy.wasm
3.473 KB  main.dart.js
1.345 KB  assets/NOTICES
```

O Flutter empacota **todas** as variantes do CanvasKit; o navegador baixa uma.
Somar os 42 MB e chamar de "tamanho do aplicativo" seria inventar um problema.
O que de fato pesa no código próprio é `main.dart.js`, com 3.473 KB.

A web, além disso, não é a plataforma de entrega: o aplicativo é mobile, e o
alvo que importa para "tamanho de instalação" é o APK.

### APK — a medição que importa

Depois de destravar o build (B-1), medido:

```
app-release.apk  (arm64-v8a)                            21.769.635 bytes
  lib/ (binários nativos)                18,36 MB   89,1%
    libflutter.so                        11,05 MB            ← o MOTOR
    libapp.so                             7,19 MB            ← o código Dart
  dex (Java/Kotlin dos plugins)           1,82 MB    8,8%
  outros (protobuf, kotlin, arsc)         0,30 MB    1,5%
  assets/flutter_assets                   0,12 MB    0,6%
  res/ + META-INF                         0,01 MB    0,0%
```

E, por dentro do código Dart, o que o próprio Flutter reporta
(`--analyze-size`):

```
Dart AOT symbols                                              7 MB
  package:flutter                                             3 MB
  package:scorpions                                         367 KB   ← TUDO
  dart:typed_data                                           194 KB      o que
  package:camera_android_camerax                            146 KB      este
  dart:async                                                138 KB      projeto
  dart:io                                                   119 KB      escreveu
  package:go_router                                          91 KB
  dart:collection                                            77 KB
```

### A conclusão desconfortável, e é a mais importante deste documento

**O código inteiro deste projeto são 367 KB de 21 MB — 1,7% do APK.**

O resto é o motor do Flutter (11 MB), a biblioteca Flutter em Dart (3 MB) e os
plugins. Não há asset gordo, não há modelo 3D, não há imagem, não há fonte
sobrando. As fontes de ícone já são cortadas pelo tree-shaking em 99%.

Isso quer dizer que a meta do §40 — reduzir o tamanho de instalação — tem
**quase nenhum espaço** neste projeto. Remover código morto (não há), unificar
funções duplicadas (30 linhas) e enxugar dependências (nenhuma é removível)
mexeria em frações de KB dentro de 367 KB.

O único corte real que a análise encontrou está abaixo, e são 91 KB.

### O que de fato havia para cortar

Sobravam binários nativos de arquiteturas que este APK não atende:

```
lib/armeabi-v7a/libimage_processing_util_jni.so   32 KB
lib/x86_64/libimage_processing_util_jni.so        59 KB
```

`--target-platform android-arm64` filtra os binários do Flutter, mas **não** os
ABIs das bibliotecas nativas que vêm das dependências Android. Corrigido com
`ndk { abiFilters }`.

### ANTES ↓ DEPOIS

| | bytes | MiB |
|---|---|---|
| **ANTES** | 21.769.635 | 20,76 |
| **DEPOIS** | 21.605.256 | 20,60 |
| **redução** | **164.379** | **160,5 KB** |
| **percentual** | | **0,755%** |

E a conta fecha, verificada entrada por entrada dentro do APK:

| | bytes |
|---|---|
| 6 bibliotecas nativas removidas (x86_64 e armeabi-v7a) | 92.956 |
| padding de alinhamento que elas carregavam | 71.423 |
| **total** | **164.379** |

As entradas do APK caíram de 199 para 193. Os `.so` são armazenados sem
compressão e alinhados em página, então cada um carrega preenchimento — tirar
seis tirou o preenchimento junto.

**E `libapp.so` ficou idêntico**: 19.163.960 bytes de `arm64-v8a` antes e
depois, e nenhum arquivo em comum mudou de tamanho. As mudanças de P-1 e D-1
removeram cerca de 30 linhas e acrescentaram cerca de 40 — neutro no binário.

Essa última frase é a prova da conclusão acima: **não há redução de tamanho a
obter mexendo no código deste projeto.** O ganho de P-1 e P-2 é de tempo, não
de bytes, e está medido na ETAPA 8.

### Para distribuição real

| | |
|---|---|
| App Bundle (`flutter build appbundle`) | a Play Store entrega a cada aparelho só o ABI e os recursos dele. É o caminho correto, e o maior ganho disponível para o usuário final |
| **Atenção** | o `abiFilters` acima é para APK avulso. Um AAB precisa dos três ABIs — é a loja que escolhe. O comentário no `build.gradle.kts` avisa |
| APK por ABI (`--split-per-abi`) | alternativa se a distribuição for fora da loja |

## ETAPA 5 — Código morto

Classificado como o briefing pede, e **nada foi removido**:

### DEFINITIVAMENTE NÃO UTILIZADO
Nenhum.

### UTILIZADO INDIRETAMENTE
- `cupertino_icons` (acima).
- `main.dart` aparece como "nunca importado" em qualquer varredura: é o ponto
  de entrada.

### NÃO FOI POSSÍVEL DETERMINAR POR ANÁLISE ESTÁTICA
Nenhum caso. O projeto não usa reflexão, não carrega classe por nome e não
tem registro dinâmico de rota — a análise estática é conclusiva aqui.

### M-1 — `capture_plan_service.dart`: sem consumidor e sem teste

| | |
|---|---|
| Arquivo | `lib/data/services/capture_plan_service.dart` |
| Motivo para considerar inútil | Único arquivo de `lib/` que nada importa, nem o aplicativo nem os testes |
| Onde foi procurado | `import` em `lib/` e `test/`; referência ao nome da classe `HeuristicCapturePlanService` |
| Dependências encontradas | Nenhuma. Ele importa `capture_instruction.dart` e `image_quality.dart`; ninguém importa ele |
| Risco de remover | **Alto, e não é risco técnico** — é o serviço que decide qual segunda foto pedir, escrito nesta sessão para a Fase 5. Remover desfaria trabalho que a tela de duas fotos vai consumir |
| Recomendação | **Não remover. Escrever o teste que falta.** Código sem consumidor e sem teste é código que ninguém sabe se funciona; quando a tela chegar, ninguém vai descobrir o defeito a tempo |

Classificação: 🟡 — não é peso no aplicativo (o tree-shaking do Dart remove o
que nada alcança do `main`), é risco de correção.

## ETAPA 6 — Duplicações

### D-1 — `_normalize` duplicada palavra por palavra 🟢

`lib/data/repositories/species_repository.dart:37` e
`lib/data/repositories/firestore_species_repository.dart:100` contêm a mesma
função, caractere por caractere, inclusive o comentário. O método `search()`
dos dois repositórios também é quase idêntico.

Mesma responsabilidade, mesma saída, mesmo motivo de existir: é duplicação de
verdade, e o §46 se aplica.

### Falso positivo que **não** deve ser unificado

`lib/data/models/view_prediction.dart:190` também tem um `_normalize`. Ele
normaliza uma **distribuição de probabilidade** para somar 1, dentro do cálculo
de Jensen-Shannon. Mesmo nome, responsabilidade sem nenhuma relação.

O §3 do briefing avisa exatamente contra isto: *"NÃO CONFUNDIR DUPLICAÇÃO COM
ESPECIALIZAÇÃO."* Unificar os três porque o nome coincide produziria uma função
que faz duas coisas incompatíveis.

### D-2 — Catálogo de espécies divergente entre modo demonstração e nuvem 🟡

| | |
|---|---|
| `lib/data/mock/mock_species.dart` | 8 espécies |
| `firebase/species-data.mjs` | 5 espécies |

Só no modo demonstração existem *Tityus obscurus*, *Rhopalurus rochai* e
*Ananteris balzanii*. Já divergiram, em silêncio, e nada no projeto percebe.

Não é duplicação a eliminar — são linguagens e finalidades diferentes (uma é
demonstração sem rede, a outra semeia o catálogo real). O problema é a
divergência sem guarda. O controle certo é o mesmo que já pegou um bug real
neste projeto: um teste que compare os dois conjuntos, como
`contract_shapes_test.dart` faz com as formas dos documentos.

### Duplicação já assumida e controlada 🟢

A lógica de fusão e decisão existe em Dart e em Python. Está documentada em
`backend/README.md`, e o controle é `fusion_cases.json` — **gerado** pela
implementação Dart e verificado contra a Python por `test_parity.py`. Divergir
quebra o CI, apontando o caso e os dois valores. Nada a fazer.

## ETAPA 8 — Performance: o que foi medido

As duas medições abaixo rodam com:

```bash
flutter test benchmark/search_normalization_benchmark.dart
flutter test benchmark/image_pipeline_benchmark.dart
```

Os arquivos vivem em `benchmark/`, fora de `test/`, de propósito: um número de
tempo varia com a carga da máquina, e deixá-lo no CI quebraria o verde sem
haver defeito.

### Advertência sobre esta máquina

As medições saem de um i3 de 2 núcleos sem GPU dedicada. Os **tempos
absolutos** variam muito aqui — a mesma busca mediu 1.171 µs e 2.686 µs em
execuções diferentes, e a segunda foi depois de 20 minutos de Gradle, com
provável limitação térmica. As **razões entre estratégias** se mantiveram.

Então as razões são o que este documento afirma. Os tempos absolutos são
ordens de grandeza, não promessas.

E um aviso ganho na prática: a primeira medição do pipeline de imagem rodou
**com o Gradle compilando em paralelo** e inverteu o resultado — disse que a
mudança proposta era 83% mais lenta. Com a máquina livre, a mesma medição diz
45% mais rápida. Dois núcleos não comportam um benchmark e um build ao mesmo
tempo. A medição contaminada foi descartada, não mediada com a boa.

### P-1 — Busca no catálogo renormaliza tudo a cada tecla 🟢

**Problema.** `FirestoreSpeciesRepository.search()` chama
`_normalize(s.searchIndex)` para **cada** espécie a **cada** tecla digitada.
Cada chamada: monta uma lista nova de 5+ campos, faz `join`, faz `toLowerCase`
e então percorre caractere por caractere fazendo `indexOf` numa string de 26
posições, escrevendo num `StringBuffer` novo.

**Causa.** O índice de busca é um getter calculado (`Species.searchIndex`) e a
normalização é feita no momento da comparação, não no momento em que o dado
entra. Nada é reaproveitado entre teclas.

**Medido**, catálogo de 200 espécies (a fauna de escorpiões descrita no Brasil
não chega a 200 — é a ordem de grandeza real):

| Estratégia | Custo por tecla | Ganho |
|---|---|---|
| A — como está hoje | 1.171 – 2.686 µs | — |
| B — tabela de consulta no lugar de `indexOf` | 675 – 1.265 µs | 1,7 – 2,1× |
| C — índice pré-normalizado uma vez | **31 – 47 µs** | **38 – 57×** |

C paga 649 – 1.475 µs uma única vez, na montagem do índice.

**Honestidade sobre o impacto.** 1,2 ms por tecla **não é visível**: o orçamento
de um quadro a 60 FPS é 16,7 ms. Este não é um travamento que o usuário sente
hoje. O que justifica a mudança é o que vem:

- em celular de entrada o fator costuma ser 5 a 10× pior, levando o custo a
  6 – 12 ms por tecla, aí sim comendo o quadro;
- o briefing prevê *"milhares de espécies"*. Dez vezes o catálogo são ~12 ms
  por tecla **nesta máquina**, e a busca passa a ser o gargalo visível.

Classificação: 🟢 alto impacto na escala prevista, baixo risco. A saída é
idêntica — o benchmark verifica isso contra o alfabeto acentuado inteiro antes
de comparar tempos, senão estaria cronometrando coisas diferentes.

### P-2 — Miniatura reamostrada do original em vez da imagem processada 🟢

**Problema.** `DefaultImageProcessingService.runPipeline` decodifica a foto uma
única vez (isso está certo, e documentado), mas deriva as duas reduções a
partir da imagem em tamanho original:

```
original 4000×3000 ──copyResize──► processada 1600
original 4000×3000 ──copyResize──► miniatura   320
```

**Causa.** O custo de `copyResize` com `Interpolation.average` cresce com o
fator de redução, porque a janela amostrada por pixel de destino cresce com
ele. Produzir 320px a partir de 4000 amostra uma vizinhança de ~156 pixels por
destino; a partir de 1600, ~25.

**Medido**, cada passo isolado, a partir de 4000×3000 (12 MP, resolução de
câmera de celular intermediário, abaixo do teto de `ImageLimits.maxDimension`):

| Passo | 1ª execução | 2ª execução |
|---|---|---|
| 4000 → 1600 (a processada; existe nas duas formas) | 841 ms | 812 ms |
| 4000 → 320 (**miniatura como é hoje**) | 901 ms | 840 ms |
| 1600 → 320 (**miniatura em cascata**) | **115 ms** | **134 ms** |
| **total hoje** | 1.742 ms | 1.652 ms |
| **total em cascata** | 956 ms | 946 ms |

Economia: **~700 – 790 ms por foto, 43 – 45%**, reproduzido em duas execuções.
Com duas fotos por análise na Fase 5, isso dobra.

**E a qualidade?** É a pergunta que decide, porque o §47 não admite ganhar
tempo às custas do visual. Reamostrar em duas etapas com `average` é média de
médias, o que *pode* borrar. Medido:

| | |
|---|---|
| Diferença média por canal | **0,34** de 255 |
| Nitidez (variância do laplaciano) direta | 0,017007 |
| Nitidez em cascata | 0,016959 |
| Razão | **0,997** |

Indistinguível. A nitidez é medida com o mesmo indicador que
`ImageQualityService` usa para julgar foco, não com um critério inventado para
a ocasião.

**Ressalva.** A cena é sintética, com textura em baixa, média e alta
frequência. Para medir **tempo** isso não importa — o custo depende da
contagem de pixels, idêntica à de uma foto do mesmo tamanho. Para **qualidade
percebida**, uma cena sintética não substitui fotografia real. O número de
0,34/255 é forte, mas a confirmação com fotos de campo fica pendente.

Classificação: 🟢 alto impacto, baixo risco, com uma ressalva registrada.

### Uma hipótese que a medição derrubou ⚪

A auditoria também suspeitou que a redução intermediária (4000 → 1600) fosse o
custo dominante e que mexer nela renderia mais. Não: ela custa 812 – 841 ms e
**aparece nas duas formas**, então não decide nada. O que decide é o passo
final. O benchmark ficou escrito dessa forma — cada passo isolado — para que
isso fique visível em vez de ser deduzido.

É o §54 na prática: a hipótese era plausível e estava errada.

## ETAPA 9 — Rede

🟢 Nada a corrigir. Verificado:

- **Nenhum `snapshots()` no projeto.** Não existe um único listener de
  Firestore em tempo real. Toda leitura é `get()` pontual. Isso significa que
  o histórico não se atualiza sozinho — escolha de projeto que economiza rede e
  bateria, correta para este aplicativo.
- Todas as consultas de coleção têm `limit()`. O catálogo tem teto de 500
  documentos, folgado de propósito (a fauna brasileira descrita não chega a
  200) para que um seed rodado duas vezes não vire download ilimitado.
- O catálogo é cacheado em memória por sessão, e `findById` consulta o cache
  antes de ir à rede.
- Persistência offline do Firestore ligada com teto explícito de 40 MB, não
  `CACHE_SIZE_UNLIMITED`, e limpa no encerramento de sessão.
- Os envios de imagem já são paralelos (`Future.wait`), não sequenciais — o
  §27 já está atendido.

## ETAPA 10 — Memória

🟢 Nada a corrigir. Verificado:

- Três `StreamSubscription` no projeto, **todos** com `.cancel()` em
  `dispose()`: `firebase_auth_repository`, `auth_controller`,
  `history_controller`.
- O processamento de imagem roda em `compute()`, isolate de verdade no Android
  e no iOS. Uma decodificação só, três variantes derivadas dela — o comentário
  do arquivo explica o custo de heap que isso evita (~48 MB por decodificação
  de 12 MP).
- Todas as listas são `ListView.separated` com `itemBuilder`: virtualizadas.
- Todos os `CustomPainter` implementam `shouldRepaint`.
- Um único `.repeat()` perpétuo, na animação da tela "analisando", com
  `dispose()`. O ticker do Flutter já o suspende em segundo plano.
- `image_quality_service` mede sobre uma redução de 256px, não sobre a imagem
  cheia — ~40× menos pixels, e o comentário diz por quê.

## ETAPA 12 — Reconstruções

🟡 Observado, **nada a mudar sem medir primeiro**.

Há 14 `context.watch` em `build()` de páginas e nenhum `context.select`. Cada
`watch` reconstrói a página inteira quando o controller notifica.

Para uma tela que observa o próprio estado, isso é o comportamento correto, não
um defeito. O §18 avisa contra memoização indiscriminada, e trocar 14 `watch`
por `select` sem medir seria exatamente isso. Não há evidência de quadro
perdido; sem evidência, não há otimização, há mexida.

Para medir de verdade é preciso aparelho: `flutter run --profile` com o
cronômetro de desempenho. **NÃO MEDIDO.**

## O que ficou NÃO MEDIDO

O §41 pede que isto seja dito em voz alta em vez de estimado:

| Métrica | Situação |
|---|---|
| Tamanho do APK antes/depois | 🟢 **medido** — ver a ETAPA 4 |
| Tempo de inicialização | **NÃO MEDIDO** — precisa de aparelho Android |
| FPS em uso | **NÃO MEDIDO** — precisa de aparelho |
| RAM e CPU em uso | **NÃO MEDIDO** — precisa de aparelho |
| Tempo de abertura da câmera | **NÃO MEDIDO** — precisa de aparelho |
| Consumo de rede por sessão | **NÃO MEDIDO** |
| iOS | **NÃO MEDIDO** — sem máquina Apple |
| Windows | **NÃO MEDIDO** — `flutter doctor` reporta Visual Studio ausente |

Sobre a inicialização, há uma suspeita concreta e **não medida**: `main()`
aguarda `FirebaseBootstrap.ensureInitialized()` — que inicializa o Firebase e
ativa o App Check — **antes** de `runApp`. Tudo isso é trabalho de rede e disco
acontecendo antes do primeiro quadro.

Mover para depois do `runApp` parece melhorar o tempo até o primeiro quadro.
Não está sendo proposto, por duas razões: não há medição, e o App Check precisa
estar ativo antes da primeira chamada ao Firestore — mexer na ordem é mexer
numa camada de segurança, e o §36 pede análise explícita de risco antes. Fica
registrado como candidato, para quando houver aparelho.

## Bugs encontrados (fora do escopo de otimização)

### B-1 — O APK de release não compilava 🔴 → corrigido

```
:camera_android_camerax:compileReleaseJavaWithJavac
camera-core-1.5.3-api.jar(androidx/camera/core/SurfaceRequest.class):
error: Cannot attach type annotations @org.jspecify.annotations.NonNull
to SurfaceRequest.mSurfaceRecreationCompleter:
  class file for androidx.concurrent.futures.CallbackToFutureAdapter not found
```

**Causa.** `camera_android_camerax` declara `androidx.camera:camera-core:1.5.3`
e nada mais. O campo `SurfaceRequest.mSurfaceRecreationCompleter` é um
`CallbackToFutureAdapter.Completer`, classe de
`androidx.concurrent:concurrent-futures` — que o POM do camera-core traz como
dependência de **runtime**, não de API. Ela não entra no classpath de
compilação.

Versões anteriores do javac toleravam. Com JDK 21 + AGP 9.0.1, resolver a
anotação de tipo `@NonNull` naquele campo exige carregar a classe, e a
compilação falha. O plugin declara ter sido testado com AGP 8.13.1; este
projeto usa 9.0.1.

**Correção.** A dependência que falta é acrescentada ao classpath de compilação
daquele módulo, de fora, em `android/build.gradle.kts`. Como `compileOnly`:
ela já está presente em runtime, trazida pelo próprio camera-core; o que
faltava era o javac poder lê-la.

Por que não editar o pacote: ele vive em `~/AppData/Local/Pub/Cache`, recriado
a cada `pub get`.

O bloco tem comentário dizendo quando pode sair, porque este projeto já
perdeu um build para uma limpeza que removeu dependência sem consumidor
aparente.

A primeira forma da correção não funcionou — `Configuration with name
'compileOnly' not found`. A configuração só passa a existir quando
`com.android.library` é aplicado ao subprojeto, então a declaração entrou
dentro de `plugins.withId("com.android.library")`.

Validado isoladamente, na tarefa exata que falhava, antes de gastar vinte
minutos num build inteiro:

```
> Task :camera_android_camerax:compileReleaseJavaWithJavac
BUILD SUCCESSFUL in 1m 47s
```

**Observação importante.** A primeira tentativa de build, antes desta
auditoria, falhou com outro erro — resolução de plugin Gradle, *"Searched in
the following repositories: Gradle Central Plugin Repository"*. Aquele era
cache do Gradle incompleto e desapareceu sozinho. Sem rodar de novo, teria
sido diagnosticado errado.

### B-2 — A compilação de release assina com a chave de depuração 🔴

`android/app/build.gradle.kts`:

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

É o padrão do template do Flutter, e continua lá. Consequências:

- a chave de depuração é a **mesma em todas as instalações do SDK Android** —
  qualquer pessoa consegue assinar um APK que o sistema aceita como atualização
  deste aplicativo;
- a Play Store recusa um APK assim.

**Isto não é correção que eu deva fazer sozinho**: gerar o keystore significa
criar uma chave e uma senha que pertencem ao Gustavo, e que, se perdidas,
tornam impossível publicar atualizações do aplicativo para sempre. Fica
listado como ação dele, com o procedimento, antes de qualquer publicação.

Até lá o APK serve para medir tamanho e instalar em aparelho de teste — o que
é exatamente o uso atual.

### B-3 — Comentários que descrevem o que não existe 🟡

Três casos. Documentação errada é pior que ausência: a próxima pessoa confia
nela.

| Onde | O que diz | O que é |
|---|---|---|
| `species.dart:137` | `searchIndex` é "normalizado sem acentos" | só faz `toLowerCase()`; os acentos continuam. É por isso que `_normalize` tem de ser chamada depois — ligado a P-1 |
| `firebase_bootstrap.dart:74` | `/// Aponta os SDKs para os emuladores locais.` | está acima de `_cacheMaximoBytes`, uma constante de cache. O comentário escorregou de `_connectEmulators` |
| `firebase_bootstrap.dart:76` | "ver a justificativa em `[ensureReady]`" | não existe método com esse nome; é `ensureInitialized` |
| `android/app/build.gradle.kts:21` | TODO para especificar o `applicationId` | já foi especificado: `com.scorpionslabs.scorpions` |

### B-4 — Um `debugPrint` sem guarda de modo 🟡

`firebase_bootstrap.dart:118` escreve sem verificar `kDebugMode`. `debugPrint`
**continua escrevendo em compilação de release** — só `assert` é removido.

O risco concreto é pequeno: a linha só roda no modo emulador, que não é
compilado para produção. Mas os outros cinco `debugPrint` do projeto têm a
guarda, e a inconsistência é o tipo de coisa que viaja por imitação.

## Plano, na ordem de prioridade do §43

| | Mudança | Impacto | Risco | Medição |
|---|---|---|---|---|
| 1 | B-1: destravar o build de release | 🔴 bloqueante | baixo | build passa a produzir APK |
| 2 | P-2: miniatura em cascata | 🟢 ~700 ms/foto | baixo | benchmark, 2 execuções |
| 3 | P-1: índice de busca pré-normalizado | 🟢 38–57× | baixo | benchmark |
| 4 | D-1: unificar a `_normalize` duplicada | 🟡 manutenção | baixo | testes existentes |
| 5 | M-1: teste para `capture_plan_service` | 🟡 correção | nenhum | teste novo |
| 6 | D-2: teste de consistência entre os dois catálogos | 🟡 correção | nenhum | teste novo |
| 7 | B-3, B-4: comentários e guarda | 🟡 manutenção | nenhum | leitura |
| 8 | B-2: keystore de release | 🔴 publicação | — | **ação do Gustavo** |
| ⚪ | startup depois do `runApp` | desconhecido | **médio — toca o App Check** | **NÃO MEDIDO**, não proposto |
| ⚪ | `context.select` no lugar de `watch` | desconhecido | baixo | **NÃO MEDIDO**, não proposto |

## O que foi implementado

Executado após o diagnóstico, na ordem do plano, com as medições acima.

| | Mudança | Arquivos | Verificação |
|---|---|---|---|
| B-1 | `compileOnly` de `concurrent-futures` no módulo da câmera; `compileSdk = 37` | `android/build.gradle.kts`, `android/app/build.gradle.kts` | o APK de release passou a existir |
| — | `abiFilters` só arm64 | `android/app/build.gradle.kts` | **164.379 bytes**, conferido entrada por entrada |
| P-1, D-1 | `TextSearch` + `SearchIndex` num lugar só; os dois repositórios passam a usar; as duas cópias de `_normalize` saem | `lib/core/utils/text_search.dart` (novo), `species_repository.dart`, `firestore_species_repository.dart` | 12 testes novos, incluindo comparação com a implementação antiga como oráculo |
| P-2 | miniatura derivada da imagem já reduzida | `image_processing_service.dart` | benchmark em duas execuções; qualidade medida |
| M-1 | teste de `HeuristicCapturePlanService` | `test/capture_plan_test.dart` (novo) | 8 testes |
| D-2 | teste de consistência entre os dois catálogos | `test/catalog_consistency_test.dart` (novo) | 6 testes |
| B-3 | três comentários que descreviam o que não existe | `species.dart`, `firebase_bootstrap.dart`, `build.gradle.kts` | leitura |
| B-4 | guarda de `kDebugMode` no `debugPrint` restante | `firebase_bootstrap.dart` | varredura |
| C-1 | job `segredos` no CI: Gitleaks + `pip-audit --strict` | `.github/workflows/verificacao.yml`, `.gitleaks.toml` (novo) | `pip-audit` roda limpo localmente; YAML e TOML validados |

### Testes

| | antes | depois |
|---|---|---|
| Aplicativo (`flutter test`) | 199 | **225** |
| `flutter analyze` | 0 avisos | **0 avisos** |
| Regras no emulador | 60 | 60 (intocadas) |
| Backend | 72 | 72 (intocados) |

Os 26 testes novos são de comportamento, não de tempo. Os benchmarks ficam fora
de `test/` de propósito: um número de tempo varia com a carga da máquina e
quebraria o verde sem haver defeito.

### Uma nota sobre o `late` desnecessário

A primeira versão de `MockSpeciesRepository._indice` foi escrita com
`static late final`, e o analisador apontou: em Dart, **toda** variável estática
já é inicializada de forma preguiçosa. O `late` não fazia nada. Corrigido, e o
comentário agora explica por que o comportamento desejado já é o padrão.

Fica registrado porque deixar um aviso passar é como a régua deixa de ser régua
— e isto já aconteceu nesta sessão, com um `prefer_const_constructors`.

## O que esta auditoria confirma que **não** será tocado (§36)

Nenhuma das mudanças acima encosta em autenticação, autorização, RBAC, Security
Rules, App Check, validação de entrada, proteção de segredos, registro de
segurança ou controles de retenção. P-1 e P-2 são aritmética dentro de funções
puras. B-1 é classpath de compilação.

A única mudança que **tocaria** segurança — mover a inicialização do Firebase e
do App Check para depois do primeiro quadro — está marcada como não proposta,
justamente por isso.

Conferido depois de implementar: nenhuma linha de `firebase/firestore.rules`,
`firebase/storage.rules`, `lib/data/repositories/firebase_auth_repository.dart`
ou `backend/app/auth.py` foi alterada. A otimização **acrescentou** segurança —
o job `segredos` do CI não existia antes.

## Resumo honesto, para a banca

O briefing pedia um aplicativo "pequeno na instalação, rápido no startup, sem
código morto, sem dependência inútil, sem asset pesado". O que a auditoria
encontrou:

| Pedido | Achado |
|---|---|
| Sem código morto | **já estava.** Nenhum arquivo não utilizado, nenhum `TODO`, nenhuma pasta de backup, nenhum bloco comentado |
| Sem dependência inútil | **já estava.** 13 diretas, todas em uso |
| Sem asset pesado | **já estava, e por construção:** zero assets. Tudo desenhado em `CustomPainter` |
| Pequeno na instalação | **quase nada a fazer.** 89% do APK é o motor do Flutter; o projeto inteiro são 367 KB de 21 MB. Cortados 160 KB |
| Rápido | **dois ganhos reais e medidos**, ambos de tempo: ~700 ms por fotografia e 38–57× na busca |
| Sem duplicação | **uma real**, eliminada; uma falsa, deliberadamente mantida separada; uma assumida e controlada por teste de paridade |

E duas coisas que a auditoria achou sem estar procurando, mais graves que
qualquer otimização:

1. **o APK de release não compilava** — ninguém poderia instalar o aplicativo;
2. **a compilação de release assina com a chave de depuração** — a Play Store
   recusaria, e qualquer pessoa poderia assinar uma atualização aceita como
   deste aplicativo. Pendente, e é ação do Gustavo.

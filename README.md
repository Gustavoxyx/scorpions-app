# Scorpions — Identificação científica de escorpiões por IA

> **Fase 5 — Duas fotografias, backend e direitos do titular.**
> *(Fases 1 a 4 concluídas.)*
>
> O aplicativo captura **duas fotografias** da mesma identificação — a segunda
> escolhida a partir do que foi medido na primeira —, envia as duas e sabe
> fundir o que cada vista diz. Há um backend próprio que verifica o token, limita
> o uso, apaga a conta em cascata e exporta os dados do titular.
>
> **O que ainda não existe é o modelo.** Nenhuma espécie é inventada: com
> Firebase, uma identificação nova fica em `processing`. No modo de demonstração
> o que cada foto "diz" é simulado e a tela avisa — a fusão e a decisão é que são
> as de produção. Treinar e medir um classificador é o que falta da Fase 5; ver
> [docs/FASE5_ARQUITETURA.md](docs/FASE5_ARQUITETURA.md).
>
> O backend roda só localmente. Enquanto não for publicado, exclusão de conta,
> exportação e limite de uso existem no código e nos testes, mas nenhum usuário
> as alcança — e a tela diz isso.
>
> Roda em três modos: `mock` (memória), `emulator` (local) e `firebase` (nuvem).
> Ver [firebase/README.md](firebase/README.md).

Scorpions é o nome de trabalho. O aplicativo é multiplataforma (**Android** e
**iOS**), feito em **Flutter / Dart**.

> O projeto se chamava *Telson* — o último segmento da cauda do escorpião,
> onde fica o ferrão. O termo permanece no código como **anatomia**
> (`AnatomyPart.telson`), não como marca. O ID do projeto Firebase na
> nuvem (`telson-tcc-2026`) também permanece: IDs de projeto são
> imutáveis no Firebase.

---

## 1. Objetivo

Receber a fotografia de um escorpião e, no futuro, usar visão computacional para
estimar a espécie — sempre de forma **informativa**, com a capacidade explícita
de dizer *"não foi possível identificar"*. Público-alvo: estudantes,
pesquisadores, profissionais de campo, instituições e curiosos.

## 2. Tecnologia

- **Flutter 3.44+ / Dart 3.12+**
- **go_router** — navegação declarativa com abas que preservam estado e guarda
  de acesso centralizada.
- **provider** — injeção e observação de estado sem geração de código.
- **camera** / **image_picker** — captura e seleção de imagem, ambos atrás de
  interfaces com fallback simulado.
- **firebase_core / auth / cloud_firestore / storage / app_check** — backend
  real, contido inteiramente em `lib/data/` (nenhuma tela importa o SDK).

Nenhuma credencial, chave de API ou segredo no código. As chaves de cliente do
Firebase **identificam** o projeto, não autorizam nada — quem autoriza é o
Authentication mais as Security Rules. Service accounts e chaves privadas nunca
entram no aplicativo; operações administrativas rodam em backend.

## 3. Como executar

Pré-requisitos: Flutter no PATH e um dispositivo/emulador.

```bash
flutter pub get
flutter run
```

> **Windows:** o build de apps com plugins exige *Developer Mode* ligado
> (`start ms-settings:developers`) para suporte a symlinks. Isso afeta apenas o
> build/run — `flutter analyze` funciona sem ele.

Verificação estática e testes:

```bash
flutter analyze
flutter test
```

> **Se `flutter test` falhar no Windows** com *"Uma política de Controle de
> Aplicativo bloqueou este arquivo"*, é o Controle Inteligente de Aplicativos
> recusando o `flutter_tester.exe` por assinatura — não é defeito do projeto.
> Desligá-lo é irreversível sem reinstalar o sistema, então a verificação roda
> na integração contínua (abaixo), onde o runner é Linux. `flutter analyze` e
> `flutter build` continuam funcionando localmente porque rodam na `dart.exe`.

### Modos de dados (§22, §42)

```bash
flutter run                                        # mock — memória, sem rede
flutter run --dart-define=DATA_SOURCE=emulator     # emuladores locais
flutter run --dart-define=DATA_SOURCE=firebase     # nuvem
```

A escolha acontece em `lib/app/dependencies.dart` e mais lugar nenhum. Se algo
der errado com o Firebase, voltar ao modo simulado é imediato — a aplicação
inteira continua funcionando. Ver [firebase/README.md](firebase/README.md).

### Modo demonstração

Abre o aplicativo já autenticado, direto na Home — útil para apresentar o
produto sem repetir onboarding e login a cada abertura:

```bash
flutter run --dart-define=DEMO_AUTOLOGIN=true
```

Desligado por padrão. Não é um atalho de autenticação: quando o Firebase entrar
na Fase 3, o caminho real de login passa a ser o único que produz sessão válida,
e este sinalizador continua servindo apenas ao repositório simulado.

### Pré-visualizar no navegador

Sem celular à mão, dá para rodar como aplicação web:

```bash
flutter run -d chrome --dart-define=DEMO_AUTOLOGIN=true
```

A câmera cai automaticamente no **modo simulado** (o plugin não tem suporte
equivalente no navegador) e o restante do fluxo funciona normalmente.

### Android
```bash
flutter run -d <android-device-id>
flutter build apk --debug
```
Permissões declaradas em `android/app/src/main/AndroidManifest.xml`
(`CAMERA`, câmera marcada como não obrigatória).

### iOS
```bash
flutter run -d <ios-device-id>
```
Descrições de uso de câmera e galeria em `ios/Runner/Info.plist`
(`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`). Requer macOS +
Xcode para compilar.

## 4. Estrutura de pastas

```
lib/
├── main.dart                  # ponto de entrada mínimo
├── app/
│   ├── app.dart               # composição de dependências + MaterialApp.router
│   └── router/                # rotas tipadas, GoRouter + guarda, transições
├── core/
│   ├── theme/                 # design system (cores, tipografia, espaçamento…)
│   ├── constants/             # strings (pt-BR) e configuração
│   ├── utils/                 # validators, formatters
│   └── widgets/               # componentes reutilizáveis do design system
├── data/
│   ├── models/                # Species, IdentificationResult, ConfidenceLevel…
│   ├── mock/                  # DADOS SIMULADOS (isolados aqui)
│   ├── repositories/          # interfaces + implementações Mock/InMemory
│   └── services/              # IdentificationService, Camera/Gallery (abstratos)
├── state/                     # controllers (ChangeNotifier)
└── features/                  # uma pasta por tela + widgets locais
    ├── splash/ onboarding/ auth/ shell/ home/ camera/
    └── identification/ species/ history/ catalog/ profile/ settings/
```

**Por que esta arquitetura?** É *feature-first* com camadas, sem o boilerplate
de uma Clean Architecture completa. A fronteira que realmente importa para as
próximas fases é **UI ↔ Repository/Service**, e é essa que está isolada por
interfaces. As telas só conhecem controllers e modelos; nunca uma implementação
concreta nem um SDK.

## 5. Arquitetura de estado

Cada área tem um `ChangeNotifier` em `lib/state/`. Estados relevantes são
**classes seladas**, não booleanos — por exemplo `IdentificationState` já
distingue `Analyzing`, `Success`, `Rejected` e `Error`, e `ConfidenceLevel` já
tem as quatro faixas (`high/medium/low/unidentified`). Quando a IA real chegar,
troca-se quem produz o resultado, não a UI.

## 6. Fluxo principal (critério de sucesso da Fase 1)

```
Splash → Onboarding → Login → Home → Identificar → Câmera → Capturar
      → Confirmar foto → Analisando → Resultado → Informações da espécie
```
E navegação livre entre **Início · Histórico · Catálogo · Perfil · Configurações**.
Existe também o caminho de **rejeição** ("não foi possível identificar"), tratado
com o mesmo cuidado do resultado positivo.

## 7. Dados MOCK

Ficam **apenas** em `lib/data/mock/`. Todo resultado exibido carrega o selo
`DADOS SIMULADOS` (`MockDataBadge`) enquanto `AppConfig.useMockIdentification`
for `true`. As espécies são aproximações didáticas, **sem validade científica**,
para fins de protótipo.

## 8. Como adicionar uma nova tela

1. Crie `lib/features/<feature>/<nome>_page.dart` (widgets locais em `widgets/`).
2. Registre o caminho em `lib/app/router/app_routes.dart`.
3. Adicione a `GoRoute` em `lib/app/router/app_router.dart`, escolhendo a
   transição em `page_transitions.dart` (`forward`, `fade` ou `modal`).
4. Use `AppScaffold` e os componentes de `core/widgets/` — não declare cores,
   paddings ou raios literais.

## 9. Como substituir MOCK por dados reais (fases futuras)

Tudo passa por trocar a implementação injetada em `lib/app/app.dart`:

| Fase | Trocar | De → Para | Estado |
|------|--------|-----------|--------|
| 3 | `AuthRepository` | `MockAuthRepository` → `FirebaseAuthRepository` | ✅ |
| 3 | `IdentificationRepository` | `InMemory…` → `Firestore…` (+ Storage) | ✅ |
| 3 | `SpeciesRepository` | `MockSpeciesRepository` → `FirestoreSpeciesRepository` | ✅ |
| 5 | `IdentificationService` | `MockIdentificationService` → modelo TFLite/API | pendente |

Nenhuma tela precisa mudar: elas dependem das **interfaces** em
`data/repositories/` e `data/services/`, não das implementações. O contrato de
identificação é sempre `CapturedImage → IdentificationService → IdentificationResult`.

## 10. Design System

Definido em `lib/core/theme/`, exposto por `ThemeExtension` e acessado via
`context.colors` / `context.text`. **Nenhuma tela declara cor, tamanho de fonte
ou dimensão de ícone literal.**

**Conceito: caderno de campo científico.** Papel off-white levemente quente,
verde-musgo profundo como cor de autoridade, ocre de terra como secundária. O
tema claro é o principal; o escuro é o mesmo caderno sob luz de campo noturno —
mesma estrutura, mesma semântica, paridade real (verificada em teste).

| Arquivo | Responsabilidade |
|---|---|
| `app_colors.dart` | Paleta **semântica** (`primary`, `secondary`, `success`, `warning`, `error`, `confidenceHigh/Medium/Low/None`, `onMedia`). Nomes descrevem significado, não cor. |
| `app_typography.dart` | 17 degraus, incluindo micro (`caption`, `micro`, `overlineSmall`, `monoSmall`) e três níveis de nome científico. |
| `app_sizing.dart` | Ícones, alturas de controle, avatares, miniaturas, alvo mínimo de toque, breakpoints. |
| `app_spacing.dart` · `app_radii.dart` · `app_shadows.dart` | Escala 4pt, raios, elevações. |
| `app_motion.dart` | Durações e curvas — a linguagem única de movimento. |

### Regras de movimento (§31)

Toda animação responde a "por que ela existe?". Feedback de toque
(`Pressable`), continuidade (transições de página), orientação (revelação
progressiva do resultado) e progresso (scanner da análise) passam. Decoração
não passa — a Fase 2 **removeu** um pulso infinito da Home que repintava a tela
para sempre sem comunicar nada. `Reveal` respeita a preferência de movimento
reduzido do sistema.

### Onde o 3D vai encaixar (§12, §20, §24)

`Species.model3D` existe e é sempre `null` nesta fase — nenhum arquivo 3D foi
empacotado. `SpeciesModel3D`, `AnatomyPart` e `AnatomyHotspot` definem o
vocabulário; `Model3DSlot` já ocupa o espaço na tela de resultado e na seção de
Morfologia, exibido em estado inativo com aviso honesto. Ligar o visualizador na
Fase 7 é preencher o campo e trocar o corpo de um único widget.

## 11. Testes

`test/responsive_smoke_test.dart` monta **12 telas em 4 larguras**
(320 / 360 / 390 / 768) mais a paridade do tema escuro — 60 casos. Falha se
qualquer exceção de layout for lançada.

Isso existe porque um `RenderFlex overflow` não quebra o build: aparece como
faixa listrada em execução e **desaparece silenciosamente em release**. Na Fase 2
este teste encontrou dois estouros reais em 320dp que nenhuma inspeção visual
havia pego.

### Integração contínua

`.github/workflows/verificacao.yml` roda a cada envio, em quatro trabalhos:

| Trabalho | O que roda | Hoje |
| --- | --- | --- |
| Análise e testes do app | `flutter analyze` + `flutter test` | **355** testes |
| Backend de inferência | `pytest`, com os casos de paridade gerados pelo Dart | **219** testes |
| Security Rules no emulador | Firestore + Storage + Auth emulados | **110** testes |
| Segredos e dependências | Gitleaks no histórico inteiro + `pip-audit --strict` | bloqueia o envio |

O terceiro começa gerando `firebase/test/contract-shapes.json` **a partir dos
modelos de produção** e só então roda as regras contra ele. A diferença não é
cerimônia: enquanto os testes de regra usavam documentos escritos à mão, eles
ficavam verdes com o cadastro quebrado — `AppUser.toCreateMap()` não enviava
`role`, a regra exigia, e todo cadastro teria dado `permission-denied` em
produção. Teste que inventa o dado testa a si mesmo.

Para o TCC isso tem um efeito colateral útil: a prova de que os testes passam
deixa de ser "rodei na minha máquina" e vira um registro público, com data e
número de testes, que a banca pode conferir.

## 12. Pipeline de imagem (Fase 4)

```
foto  ->  validar  ->  medir qualidade  ->  derivar 3 formas
                                              |
                       registrar (processing) |
                                              v
                            enviar  ->  ligar imagens ao registro
```

Validar, medir e derivar acontecem numa **única decodificação**, dentro de um
isolate. Não é microtimização: decodificar uma foto de 12 MP custa ~48 MB de
heap, e repetir isso três vezes num aparelho de entrada é a diferença entre o
aplicativo responder e ser encerrado pelo sistema. Na web não existe isolate e
o trabalho roda na mesma thread — por isso os limites são conservadores.

| Peça | Responsabilidade |
|---|---|
| `ImageValidator` | vale a pena gastar CPU e rede com esta imagem? |
| `ImageQualityService` | brilho, contraste e nitidez |
| `MetadataStripper` | remove EXIF e GPS **sem recomprimir** |
| `ImageProcessingService` | as três formas, numa passada |
| `IdentificationPipeline` | a sequência inteira, incluindo cancelamento |

**As três formas** (§7): `original` é o registro científico, com os pixels
preservados; `processed` (≤ 1600 px) é o que a análise vai consumir;
`thumbnail` (≤ 320 px) existe para que abrir o histórico não baixe megabytes.

**Privacidade** (§8): a foto de um celular carrega coordenadas de GPS no EXIF.
Elas são removidas andando pelos segmentos do JPEG, sem recomprimir —
reencodar limparia de graça, mas degradaria o registro original. Quando o
arquivo traz etiqueta de rotação, a recompressão é inevitável: apagar o EXIF
apagaria junto o pedido de girar, e o original abriria deitado.

**O que o pipeline não faz:** identificar. `ScorpionDetectionService` e
`SpeciesClassificationService` existem como contratos e respondem **"não
avaliado"**. Nenhum deles sorteia uma resposta — um placeholder que inventa
preenche o banco com ficção indistinguível do que o modelo real produzirá.

## Roadmap

Fase 1 casca e navegação ✅ · 2 identidade visual ✅ ·
3 Firebase e infraestrutura ✅ · **4 pipeline de imagem ✅** · 5 modelo de IA ·
6 confiança e rejeição · 7 catálogo científico e 3D · 8 human-in-the-loop ·
9 segurança avançada · 10 testes e produção.

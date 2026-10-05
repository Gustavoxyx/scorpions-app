# Inventário e fluxo de dados

Resposta à FASE 2 e à FASE 41 do briefing de segurança. Lista **todo** dado que
o sistema processa, de onde vem, para que serve, onde repousa, por quanto tempo
e quem alcança.

Data: 5 de outubro de 2026. Levantado por leitura do código, não por
declaração: cada linha abaixo aponta o arquivo onde o campo existe.

> **Aviso.** Este documento é levantamento técnico. A definição formal de
> controlador, operador e encarregado, a política de privacidade publicada e a
> base legal de cada tratamento precisam de validação da UTFPR e/ou do
> responsável jurídico competente antes de produção. Nada aqui é conclusão
> jurídica — ver FASE 51 e `PRIVACY.md`.

## Princípio aplicado

**Minimização por padrão.** O aplicativo não coleta nada "porque pode ser útil
depois". Em particular, e verificado por varredura, ele **não** coleta:

| Não coletado | Confirmado por |
|---|---|
| Localização (GPS) | nenhuma permissão de localização no manifesto; nenhum pacote de geolocalização |
| Endereço IP | o aplicativo não o envia; o Firebase o vê na borda, fora do alcance do app |
| Identificador de aparelho | nenhum `device_info` no `pubspec.yaml` |
| Contatos, agenda, chamadas, SMS | nenhuma permissão declarada |
| Análise de uso / telemetria | `analyticsEnabled` nasce **falso**; nenhum SDK de analytics instalado |
| Relatório de falhas | Crashlytics não instalado |
| Dados de pagamento | o aplicativo não cobra |
| Dados de saúde | o aplicativo **não** diagnostica nem registra acidente |

A única permissão que o aplicativo pede é `CAMERA`, e ela é declarada
`required="false"` — em aparelho sem câmera o aplicativo funciona pela galeria.

**EXIF e GPS embutidos na foto:** o pipeline remove os metadados antes de
enviar (`metadata_stripper.dart`). Uma foto de celular normalmente carrega
coordenada de onde foi tirada; essa coordenada **não sai do aparelho**.

## Inventário

### Conta do usuário

Origem: o próprio usuário, no cadastro. Armazenado em Firestore
`users/{uid}` — ver `lib/data/models/app_user.dart`.

| Campo | Pessoal? | Finalidade | Retenção | Quem acessa |
|---|---|---|---|---|
| `uid` | sim (identificador) | ligar as identificações ao dono; é a chave de autorização | enquanto a conta existir | o dono; o backend com o uid verificado |
| `email` | **sim** | autenticação e recuperação de senha | enquanto a conta existir | o dono; Firebase Auth |
| `name` | **sim** | cumprimento na tela inicial e no perfil | enquanto a conta existir | o dono |
| `role` | não | autorização (RBAC) | enquanto a conta existir | lido pelo servidor; **escrita negada ao cliente** |
| `avatarUrl` | sim, se preenchido | foto de perfil | sempre nulo hoje | o dono |
| `identificationCount`, `speciesSeenCount` | não | contadores mostrados no perfil | enquanto a conta existir | o dono |
| `memberSince`, `updatedAt` | não | exibição e ordenação | enquanto a conta existir | o dono |

**Necessidade do `name`:** é o único campo cuja necessidade é discutível. Serve
para o cumprimento na tela inicial. Se a minimização fosse levada ao extremo,
ele sairia. Fica registrado como coleta deliberada, de dado que o usuário
digita sabendo onde aparece — não como coleta silenciosa.

### Fotografias

Origem: câmera ou galeria, por ação explícita do usuário. Armazenado em Cloud
Storage, caminho `users/{uid}/identifications/{id}/`.

| Variante | Classe | Finalidade | Por que existe |
|---|---|---|---|
| `original.jpg` | **SENSÍVEL** | registro científico; reprocessamento por modelo melhor | é dele que a Fase 5 em diante vai querer reanalisar |
| `processed.jpg` | **SENSÍVEL** | entrada da análise (1600px, qualidade 88) | o modelo não precisa de 12 MP |
| `thumbnail.webp` | **SENSÍVEL** | lista do histórico (320px) | não baixar 8 MB para mostrar 320px |

**Por que SENSÍVEL e não só PRIVADO:** uma foto de escorpião tirada por alguém
diz onde essa pessoa esteve, frequentemente dentro de qual casa. Com a data e o
perfil, é rastro de localização. Classificar como "foto de bicho" subestimaria
o dado.

| | |
|---|---|
| Pessoal? | **sim** — é imagem de um lugar onde uma pessoa identificável esteve |
| Enviado a terceiros? | **não.** Nenhuma API externa é chamada. As fotos não saem do Google Cloud |
| Usado para treinar modelo? | **não automaticamente.** Ver FASE 15 e a seção adiante |
| Pode ser anonimizada? | parcialmente — o EXIF já é removido; o conteúdo da imagem não é anonimizável |
| Pode ser excluída? | 🔴 **não há caminho para isso hoje** — ver pendência abaixo |
| Retenção | 🔴 **indefinida** — ver `RETENTION_POLICY.md` |

### Identificações

Firestore `identifications/{id}` — ver `lib/data/models/identification.dart`.

| Campo | Pessoal? | Origem | Quem pode escrever |
|---|---|---|---|
| `userId` | sim | **o servidor/regra**, conferido contra `request.auth.uid` | o dono, e só com o próprio uid |
| `imageUrl`, `thumbnailUrl` | sim (aponta para foto) | o aplicativo | o dono |
| `status` | não | aplicativo na criação (`processing`); servidor depois | ambos, conforme a regra |
| `imageQuality` | não | medido no aparelho | o dono |
| `pipelineVersion`, `errorCode` | não | aplicativo | o dono |
| `createdAt` | não | `serverTimestamp()` — **relógio do servidor** | ninguém pode forjar |
| `speciesId`, `scientificName`, `confidence`, `species`, `alternatives`, `rejectionReason`, `modelVersion`, `isMock` | não | **só o servidor** | 🟢 **cliente bloqueado pela regra** (HIGH-1) |
| `reviewedBy`, `reviewedAt`, `humanSpeciesId` | sim (identifica o revisor) | só o servidor | 🟢 cliente bloqueado |

A separação da última coluna é o achado HIGH-1 fechado: `serverOwnedFields()`
nas Security Rules recusa a escrita desses campos vinda do cliente, tanto na
criação quanto na atualização — `!changedFields().hasAny(serverOwnedFields())`
fecha o caminho "criar limpo e reescrever depois".

### Catálogo de espécies

Firestore `species/{id}`. **PÚBLICO**, sem dado pessoal: nome científico, nome
popular, família, gênero, descrição, distribuição, relevância médica,
morfologia. Leitura liberada a qualquer usuário autenticado; escrita negada a
todos os clientes.

Registrado como INFO-1 na auditoria de segurança: catálogo legível permite
raspagem do conteúdo científico. É conteúdo que seria publicado de qualquer
forma, e App Check reduz o automatizado.

### Registros

| Registro | Contém dado pessoal? | Onde |
|---|---|---|
| `AppLog` do aplicativo | **não**, e é verificado por `assert` | console, só em depuração |
| Log do backend | **não** — `request_id` e contagem de vistas | saída padrão do provedor |
| Logs do Firebase / Google Cloud | **sim** (IP, uid) | Google, retenção dele, fora do nosso controle |

`AppLog` mantém lista de chaves proibidas — `password`, `token`, `email`,
`uid`, `path`, `url`, `bytes`, `image`, entre outras — e **quebra o aplicativo
em depuração** se alguém tentar registrar uma delas. A proibição não depende de
disciplina.

A terceira linha é importante e honesta: o Google registra IP e uid nas
requisições, e isso é tratamento de dado pessoal que acontece por usarmos a
plataforma dele. Está em `THIRD_PARTY_PROCESSORS.md`.

### Dados que **não existem** ainda

Para não dar a impressão de que o sistema é maior do que é:

| | Situação |
|---|---|
| Fila de revisão humana | estrutura prevista; `GET /v1/review-queue` devolve lista vazia |
| `reviewedBy`, `reviewedAt`, `humanSpeciesId` | campos existem no modelo e nas regras; nunca preenchidos |
| Resultado de modelo | **nenhum modelo existe.** `POST /v1/analyses` responde 503 |
| Audit log | não existe — LOW-4 na auditoria de segurança |
| Dataset de treinamento | não existe |
| Backups | não existem |

## Fluxo de dados

```
                        ┌──────────────────┐
                        │     USUÁRIO      │
                        └────────┬─────────┘
                                 │ e-mail, senha, nome        [PESSOAL]
                                 │ fotografia                 [SENSÍVEL]
                                 ▼
                        ┌──────────────────┐
                        │  APLICATIVO      │  não confiável (§35)
                        │                  │
                        │  remove EXIF/GPS │  ◄── o dado de localização
                        │  mede qualidade  │      morre aqui
                        │  reduz e comprime│
                        └────┬────────┬────┘
                             │ TLS    │ TLS
          ┌──────────────────┘        └──────────────┐
          ▼                                          ▼
  ┌───────────────┐                        ┌──────────────────┐
  │ Firebase Auth │                        │  Cloud Storage   │
  │   [PESSOAL]   │                        │   [SENSÍVEL]     │
  │ e-mail, hash  │                        │ users/{uid}/...  │
  │ scrypt        │                        │ privado, cifrado │
  └───────┬───────┘                        └─────────┬────────┘
          │ ID token                                 │
          │                                          │
          ▼                                          │
  ┌─────────────────────────────────────────┐        │
  │  BACKEND DE INFERÊNCIA (FastAPI)        │        │
  │  verifica o token; lê o papel           │◄───────┘
  │  monta o caminho com o uid VERIFICADO   │   lê com Admin SDK
  │  decide espécie, confiança, versão      │
  └───────────────────┬─────────────────────┘
                      │ Admin SDK (ignora as regras)
                      ▼
            ┌──────────────────────┐
            │      FIRESTORE       │
            │ users/      [PESSOAL]│
            │ identifications/     │
            │             [PESSOAL]│
            │ species/    [PÚBLICO]│
            │ cifrado em repouso   │
            └──────────┬───────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ RESULTADO ──► usuário (só o dono lê)
              └─────────────────┘

TERCEIROS: Google / Firebase, e **nenhum outro**.
           Nenhuma imagem de usuário sai do Google Cloud.
           Nenhuma API de IA externa é chamada.
```

### O ponto do fluxo que mais importa

```
aplicativo  ──► remove EXIF/GPS ──►  envia
```

É onde o rastro de localização é destruído, no aparelho, antes de qualquer
transmissão. Nada downstream — nem o Storage, nem o backend, nem um futuro
revisor humano — recebe a coordenada. É minimização aplicada no único lugar em
que ela ainda é possível.

## Residência dos dados

| | |
|---|---|
| Firestore e Storage | `southamerica-east1` (São Paulo) |
| Firebase Authentication | **não tem seleção de região** — o Google processa em infraestrutura global |
| Backend de inferência | ainda não publicado. A região do provedor escolhido precisa entrar aqui |

A segunda linha é uma transferência internacional de dado pessoal (o e-mail) e
precisa de avaliação jurídica. Está marcada em `PRIVACY.md`.

## Pendências que este inventário expõe

| | Pendência | Gravidade |
|---|---|---|
| 1 | **Não existe exclusão de conta.** O titular não consegue apagar os próprios dados — Art. 18 da LGPD. É o HIGH-2 da auditoria de segurança | 🔴 |
| 2 | **Nenhuma política de retenção.** Foto e identificação ficam para sempre, por omissão, não por decisão | 🔴 |
| 3 | **Não existe exportação de dados.** O titular não consegue obter o que é dele em formato legível — Art. 18, V | 🟡 |
| 4 | **Não existe política de privacidade publicada** nem tela de consentimento | 🔴 antes de produção |
| 5 | Sem verificação de e-mail: o `email` armazenado pode não pertencer a quem cadastrou | 🟡 (MEDIUM-3) |
| 6 | Sem audit log: acesso administrativo a dado pessoal não deixa rastro | 🟡 (LOW-4) |

As quatro primeiras são bloqueadoras para produção com usuários reais. **Nenhuma
delas bloqueia o TCC**, que é demonstração com dados do próprio autor — mas a
diferença entre as duas situações precisa estar escrita, e está.

## Sobre treinar modelo com foto de usuário

A FASE 15 do briefing é explícita, e aqui não há nada a corrigir **porque nada
disso existe ainda**. O que fica registrado, antes de existir:

```
FOTO DO USUÁRIO
      │
      ▼  nunca automático
  REVISÃO humana
      │
      ▼
  CHECAGEM de qualidade
      │
      ▼
  CONSENTIMENTO específico e separado  ◄── não o aceite geral de termos
      │
      ▼
  DATASET validado
      │
      ▼
  TREINAMENTO
```

O consentimento para treinar precisa ser **pedido à parte**, recusável sem
perder o uso do aplicativo, e revogável. O plano da Fase 5 já decidiu usar
bancos públicos (iNaturalist/GBIF) justamente para que o modelo inicial não
dependa de foto de usuário nenhum — ver `docs/FASE5_ARQUITETURA.md`.

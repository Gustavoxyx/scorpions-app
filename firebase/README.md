# Infraestrutura — Firebase

Regras de segurança, testes e ferramentas de emulação do Scorpions.

## Como rodar

Pré-requisitos: **Node** e **Java** (o emulador do Firestore roda na JVM).

```bash
cd firebase
npm install
```

### Testar as Security Rules

```bash
npm run emulate
```

Sobe os emuladores, roda os 53 testes e desliga. É o comando de verificação.

### Desenvolver com o app conectado

```bash
# terminal 1
cd firebase && npm start

# terminal 2 (com os emuladores no ar)
cd firebase && npm run seed
cd .. && flutter run --dart-define=DATA_SOURCE=emulator
```

Interface dos emuladores: <http://127.0.0.1:4000>

> Em aparelho físico, `localhost` aponta para o próprio celular. Use o IP da
> sua máquina: `--dart-define=EMULATOR_HOST=192.168.x.x`.

## Por que `demo-scorpions`

O `projectId` começa com `demo-`. Os SDKs e a CLI tratam esse prefixo como
projeto puramente local: **nenhuma requisição alcança a nuvem**, mesmo que
existam credenciais na máquina. É a salvaguarda contra rodar um teste
destrutivo em produção.

Nenhuma credencial é necessária para desenvolver — e nenhuma existe no
repositório.

## Os três níveis de teste

| Arquivo | Pergunta que responde |
|---|---|
| `test/firestore.test.mjs` | A **política** está certa? (Alice não lê os dados de Bob) |
| `test/storage.test.mjs` | Upload respeita dono, tamanho, tipo e caminho? |
| `test/contract.test.mjs` | O que o **app realmente grava** passa pelas regras? |

O terceiro merece explicação. Os dois primeiros usam documentos escritos à mão
— e por isso deixaram passar um bug real: o mapa de criação de usuário do Dart
não trazia `role`, a regra exigia `role == 'user'`, e **todo cadastro falharia
com `permission-denied`** em produção. Os testes estavam verdes porque
inventavam o documento em vez de usar o de verdade.

`contract.test.mjs` consome `test/contract-shapes.json`, que é **gerado** a
partir dos modelos de produção por `test/contract_shapes_test.dart`. Quando um
campo muda no Dart e quebra uma regra, agora um teste falha.

```bash
flutter test test/contract_shapes_test.dart   # regenera as formas
cd firebase && npm run emulate                # verifica contra as regras
```

## Decisões das regras

**`species` é de leitura pública.** É conteúdo científico de referência, sem
dado pessoal, e quem acabou de encontrar um escorpião precisa de informação
antes de se cadastrar. Escrita é exclusiva de admin.

**Fotografias nunca são públicas.** São dado potencialmente sensível: mostram
onde a pessoa esteve e o que encontrou. Só o dono lê.

**O histórico não pode ser listado sem filtro.** A regra
`resource.data.userId == uid` faz o Firestore recusar qualquer consulta que
não prove que só retornará documentos do solicitante. Buscar o histórico
alheio é impossível, não apenas desencorajado.

**`role` é fixado em `'user'` na criação e imutável na atualização.** As duas
portas de escalação de privilégio estão fechadas, e ambas têm teste. Promover
alguém a admin é operação de console.

**Contadores de perfil não existem no banco.** Se o cliente pudesse escrevê-los,
inflaria as próprias estatísticas. O perfil deriva os números da coleção.

## Ir para a nuvem

Nada aqui muda. Do lado do Flutter:

```bash
firebase login
flutterfire configure          # sobrescreve lib/firebase_options.dart
flutter run --dart-define=DATA_SOURCE=firebase --dart-define=APP_ENV=production
```

E publicar as regras:

```bash
firebase deploy --only firestore:rules,storage:rules,firestore:indexes
```

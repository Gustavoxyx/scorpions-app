# Backend de inferência

Serviço que roda os modelos e grava o resultado da análise.

## Por que ele existe

A auditoria de segurança (`security/SECURITY_AUDIT.md`, HIGH-1) encontrou que o
aplicativo escrevia `confidence` e `modelVersion` direto no Firestore. A regra
validava o **formato**, não a **origem** — um `0.99` forjado passava igual a um
produzido por modelo.

Sem IA isso quase não importava: o pior caso era o usuário poluir o próprio
histórico. Com IA, um registro forjado contaminaria as métricas de acurácia,
entraria na fila de revisão humana como se fosse saída do modelo, alimentaria o
dataset de retreinamento com rótulo falso, e destruiria a auditabilidade que o
§39 exige.

O §11 do briefing de segurança não deixa margem: *"Nunca permitir que o usuário
simplesmente envie `confidence = 0.99` e isso seja salvo."*

Então o resultado nasce aqui, onde o cliente não alcança.

## Por que não Cloud Functions

Exigem plano Blaze, que ainda não foi aprovado. A escolha de um serviço próprio
em plano gratuito tira a Fase 5 da dependência dessa decisão.

## Arquitetura

```
Flutter  (não confiável)
   │  ID token do Firebase
   ▼
este serviço
   │  verifica a assinatura do token com a chave pública do Google
   │  lê o papel em users/{uid} — o mesmo lugar que as regras consultam
   │  baixa as imagens do Storage pelo caminho montado com o uid VERIFICADO
   │  detecta, classifica, funde, decide
   ▼
Firestore  (escrita com Admin SDK)
```

O `uid` sai do token, nunca do corpo. É o IDOR fechado por construção: um
`sessionId` apontando para a pasta de outra pessoa não encontra nada, porque o
prefixo é montado a partir de quem está autenticado.

## Rodar localmente

```bash
cd backend
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements-dev.txt   # Windows
cp .env.example .env    # e preencher
.venv/Scripts/python -m uvicorn app.main:app --reload --port 8000
```

## Testes

```bash
python -m pytest tests/ -v
```

São dois conjuntos:

**`test_security.py`** — 34 testes, cada um uma tentativa descrita no §30 do
briefing: corpo com `confidence`, com `role: admin`, com `userId` de outra
pessoa; travessia de caminho no nome do arquivo; `sessionId` malformado;
pedido com mil vistas; papel desconhecido virando `admin`. Todos precisam ser
bloqueados.

**`test_parity.py`** — verifica que a fusão em Python concorda com a fusão em
Dart, caso a caso.

## A duplicação da fusão, e o que a controla

A lógica de fusão e decisão existe em dois lugares: `app/fusion.py` e
`lib/data/services/multi_view_fusion_service.dart`. Duplicação é dívida, e esta
é assumida de olhos abertos:

- **o servidor** precisa dela porque é ele quem grava o resultado;
- **o aplicativo** precisa dela para o modo de demonstração, que roda sem rede,
  sem conta e sem cota — como numa apresentação cujo Wi-Fi não se pode
  garantir.

O risco é divergirem em silêncio. O controle é `fusion_cases.json`, que **não é
escrito à mão**: o teste `test/fusion_cases_test.dart` executa a implementação
Dart e grava o que ela produziu; o pytest roda os mesmos casos contra a
implementação Python. Divergiu, o CI quebra — apontando o caso e os dois
valores.

É o mesmo padrão de `contract_shapes_test.dart`, que já pegou um bug real neste
projeto. Enquanto o teste inventa o dado, ele testa a si mesmo.

Regenerar os casos:

```bash
flutter test test/fusion_cases_test.dart
```

## Segredos

Nenhum neste diretório. A service account chega por variável de ambiente, e o
`.env` está no `.gitignore`.

Ela **ignora as Security Rules**: se vazar, entrega o banco inteiro. Por isso
existe só no servidor, nunca no aplicativo (§32 da Fase 3, §2 e §21 do briefing
de segurança), e é lida de uma variável em vez de arquivo — arquivo é mais
fácil de commitar por engano.

## Estado atual

| | |
|---|---|
| Autenticação por ID token, com revogação conferida | ✅ |
| Papel lido de `users/{uid}`, falhando para `user` | ✅ |
| Validação de entrada, mass assignment fechado | ✅ |
| CORS por lista explícita, nunca `*` | ✅ |
| Erros sem detalhe interno, com `requestId` | ✅ |
| Fusão e decisão, com paridade verificada | ✅ |
| **Modelo treinado** | ❌ não existe |

`POST /v1/analyses` responde **503** enquanto não houver modelo, dizendo isso em
voz alta. Não devolve resultado vazio que a tela interpretaria como "nada
encontrado" — o §12 da Fase 5 proíbe fingir que o modelo existe.

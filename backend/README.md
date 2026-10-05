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

São seis conjuntos, 164 testes. Nenhum fala com o Firebase de verdade — um
teste de exclusão de conta contra o banco real apagaria dados para verificar que
a exclusão apaga dados.

| Arquivo | Testes | O que guarda |
|---|---|---|
| `test_security.py` | 34 | corpo com `confidence`, `role: admin`, `userId` alheio; travessia de caminho; papel desconhecido virando `admin` |
| `test_endpoints.py` | 23 | as peças estão **ligadas**: `DELETE /v1/me` de fato pede senha, a análise de fato cobra cota, ninguém entra sem token |
| `test_account.py` | 20 | a ordem da cascata; não tocar dado de outro usuário; falha parcial preserva a conta; reautenticação |
| `test_quota.py` | 15 | o limite; a recusa não incrementa; falhar fechado |
| `test_images.py` | 34 | arquivos que **afirmam** um formato e **são** outro; dimensões lidas do cabeçalho, antes de decodificar |
| `test_parity.py` | 38 | a fusão em Python concorda com a fusão em Dart, caso a caso |

`test_endpoints.py` existe por uma razão específica: uma função
`requires_recent_auth` impecável não protege nada se o endpoint esquecer de
chamá-la, e esse esquecimento não aparece em teste de unidade nenhum.

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

## Endpoints

| Método | Caminho | Autenticação | O que faz |
|---|---|---|---|
| `GET` | `/health` | nenhuma | estado do serviço, sem revelar configuração |
| `POST` | `/v1/analyses` | token | cobra a cota e analisa — hoje responde 503 (não há modelo) |
| `GET` | `/v1/me/quota` | token | consumo da cota de hoje |
| `GET` | `/v1/me/data` | token | exporta os dados do titular (LGPD, Art. 18, V) |
| `DELETE` | `/v1/me` | token **+ senha recente** | apaga a conta em cascata (LGPD, Art. 18, VI) |
| `GET` | `/v1/review-queue` | token + papel | fila de revisão; o acesso gera audit log |

Nenhum deles aceita `uid`, `userId` ou `role` vindos do cliente. O dono sai do
token verificado; o papel, de `users/{uid}`.

## A exclusão de conta

`DELETE /v1/me` fechou o HIGH-2 da auditoria: antes dele, o titular não tinha
caminho nenhum para apagar os próprios dados.

**Exige senha recente.** O ID token do Firebase se renova sozinho a cada hora,
sem pedir senha — quem pega um aparelho destravado continua autenticado. O
endpoint olha a claim `auth_time`, que só se move quando a senha é apresentada
de fato, e recusa com 401 + `X-Reauth-Required: true` se ela tiver mais de 5
minutos. O aplicativo responde chamando `reauthenticateWithCredential` e pedindo
um token novo com `forceRefresh`.

**A ordem da cascata não é negociável:**

```
1. imagens no Storage              users/{uid}/**
2. documentos em identifications   onde userId == uid
3. subcoleções de users/{uid}      quotas
4. o documento users/{uid}
5. a conta no Authentication       ← por último
```

Se a conta fosse apagada primeiro e a cascata falhasse no meio, sobrariam
imagens órfãs — dado pessoal sem dono e sem regra protegendo, porque as regras
comparam com `request.auth.uid` e esse uid deixou de existir. Com esta ordem,
uma falha deixa a conta **ainda existindo**: o titular entra e tenta de novo.

## O limite de uso

60 análises por dia por usuário (`MAX_ANALYSES_PER_DAY`), contadas em
`users/{uid}/quotas/{dia}` dentro de uma **transação** — dois pedidos
simultâneos que lessem 59 e gravassem 60 deixariam passar 61. A cota é cobrada
**antes** do trabalho, e o serviço **falha fechado**: se o contador não puder
ser lido, a análise é recusada com 503.

O dia é contado em UTC, não no fuso do usuário: o fuso vem do cliente, e quem
escolhesse o fuso teria um "novo dia" a cada troca.

A regra do Firestore nega escrita em `quotas` a todo cliente. Sem isso, bastaria
zerar o próprio contador.

## Estado atual

| | |
|---|---|
| Autenticação por ID token, com revogação conferida | ✅ |
| Papel lido de `users/{uid}`, falhando para `user` | ✅ |
| Validação de entrada, mass assignment fechado | ✅ |
| CORS por lista explícita, nunca `*` | ✅ |
| Erros sem detalhe interno, com `requestId` | ✅ |
| Fusão e decisão, com paridade verificada | ✅ |
| Limite de uso por usuário, em transação | ✅ |
| Exclusão de conta em cascata, com senha recente | ✅ |
| Exportação dos dados do titular | ✅ |
| Audit log das operações críticas | ✅ |
| Validação de imagem pelos bytes (`app/images.py`) | 🟡 pronta e testada, **ainda não chamada** |
| **Modelo treinado** | ❌ não existe |
| **Publicado em algum lugar** | ❌ roda só localmente |

As duas últimas linhas são as que importam para quem lê com pressa.

`POST /v1/analyses` responde **503** enquanto não houver modelo, dizendo isso em
voz alta. Não devolve resultado vazio que a tela interpretaria como "nada
encontrado" — o §12 da Fase 5 proíbe fingir que o modelo existe. É também por
isso que o validador de imagem ainda não é chamado: a resposta sai antes de
qualquer imagem ser lida.

E enquanto o serviço não estiver publicado, a exclusão de conta, a exportação e
a cota existem no código e nos testes, mas nenhum usuário as alcança. O
aplicativo sabe disso: sem `BACKEND_URL`, a tela "Meus dados" diz que o recurso
precisa do serviço online — não finge que apagou.

Para ligar o aplicativo a uma instância local:

```bash
flutter run --dart-define=DATA_SOURCE=firebase --dart-define=BACKEND_URL=http://localhost:8000
```

`http://` só é aceito para `localhost`, `127.0.0.1` e `[::1]`. Qualquer outro
endereço precisa de `https://`, porque o ID token do usuário vai no cabeçalho de
cada chamada.

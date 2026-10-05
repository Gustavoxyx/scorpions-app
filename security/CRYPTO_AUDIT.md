# Auditoria de criptografia e proteção de dados

Resposta à Fase 61. Complementa `SECURITY_AUDIT.md`, não o substitui — ali
estão os achados de autenticação, autorização e abuso; aqui, os de criptografia
e gestão de chaves.

Data: 5 de outubro de 2026.

## A conclusão primeiro

**Nenhuma criptografia precisa ser escrita neste projeto.** O briefing já
antecipa a razão em 61.2 e 61.5: *"Quando o serviço já fornece criptografia
gerenciada adequadamente, utilizar essa proteção em vez de implementar
criptografia caseira."*

Firestore, Storage e Firebase Authentication cifram em repouso com chaves
gerenciadas pelo Google, e todo o tráfego dos SDKs é TLS. O que sobra para
este projeto não é algoritmo — é **onde as chaves ficam, o que o aparelho
guarda, e o que os registros deixam escapar**. É aí que estão os três achados
abaixo.

| | |
|---|---|
| 🔴 Faltando | varredura automática de segredos no CI (C-1) |
| 🟡 Risco residual registrado | cache local do Firestore não é cifrado no aparelho (C-2) |
| 🟡 Pendente para quando a Fase 5 ligar o cliente | TLS obrigatório na chamada ao backend (C-3) |
| 🟢 Verificado e correto | 14 itens, listados adiante |

## 61.1 — Criptografia em trânsito

| Caminho | Situação |
|---|---|
| App → Firebase (Auth, Firestore, Storage) | 🟢 TLS pelos SDKs, sem opção de desligar |
| App → backend de inferência | 🟡 **ainda não existe** — ver C-3 |
| Backend → Firebase (Admin SDK) | 🟢 TLS |
| Backend → terceiros | ⚪ nenhum terceiro é chamado |

No Android, `usesCleartextTraffic="false"` está declarado no manifesto. O
padrão do Android 9+ já é esse; declarar troca uma garantia que depende da
versão do sistema por uma garantia do aplicativo.

### Sobre fixação de certificado (certificate pinning)

**Recomendação: não fazer.** O §32 do briefing de segurança menciona validação
de certificado, e a tentação é fixar o do Firebase. Seria um erro: o Google
rotaciona esses certificados sem aviso, e um aplicativo com o certificado
antigo fixado para de funcionar para todos os usuários ao mesmo tempo, sem
nada no servidor para corrigir — só uma atualização na loja, que leva dias.

O risco que o pinning mitigaria é um ataque de intermediário com autoridade
certificadora confiável instalada no aparelho. Nesse cenário o aparelho já
está comprometido, e o 61.19 diz o que vale aqui: criptografia não substitui
autorização. Um token roubado continua barrado pelas Security Rules, que
conferem `request.auth.uid`.

### C-3 — TLS obrigatório na chamada ao backend 🟡

O aplicativo **não conhece nenhuma URL de backend**. A varredura confirma:
nenhum `http://` nem `https://` em `lib/`, nenhuma constante de endereço. A
Fase 5 construiu o domínio (fusão, confiança, sessão) e o serviço em Python,
mas o cliente HTTP que liga os dois ainda não existe.

Isso significa que o requisito de TLS para esse caminho é **pendente, não
violado**. Quando o cliente for escrito:

1. a URL base vive em `AppEnvironmentConfig`, junto das outras decisões de
   ambiente, não espalhada;
2. o esquema é verificado em tempo de construção — um `assert` que recuse
   qualquer coisa que não comece com `https://`, exceto `http://localhost` e
   `http://127.0.0.1` para desenvolvimento;
3. o provedor que hospedar o serviço precisa terminar TLS. Hugging Face Spaces
   e Render fazem isso por padrão e não expõem porta em texto claro.

## 61.2 e 61.5 — Criptografia em repouso

Inventário de todo lugar onde dado pode parar:

| Onde | Cifrado em repouso? | Por quem |
|---|---|---|
| Firestore (perfis, identificações, catálogo) | 🟢 sim, AES-256 | Google, chaves gerenciadas, sem configuração |
| Cloud Storage (fotos) | 🟢 sim, AES-256 | Google, chaves gerenciadas |
| Firebase Authentication (senhas) | 🟢 hash scrypt | Firebase — ver 61.10 |
| Backups do Firestore | ⚪ não existem ainda | ver `RETENTION_POLICY.md` |
| Cache local do Firestore no aparelho | 🔴 **não** | ver C-2 |
| Arquivos temporários de imagem no aparelho | 🟡 ver C-2 |
| Registros (logs) | 🟢 não contêm dado pessoal — ver 61.17 |
| Filas, snapshots | ⚪ não existem |

Nada aqui pede AES implementado à mão. O 61.5 é explícito: *"Não implementar
AES manualmente sem necessidade."*

### C-2 — O cache local do Firestore não é cifrado 🟡

**O fato.** A persistência offline do Firestore está ligada, e o SDK grava em
disco **sem cifrar**. O que ele guarda é o perfil e o histórico de
identificações do usuário — data, local declarado, espécie, foto referenciada.
O SDK não oferece opção de cifrar esse arquivo.

**Por que a persistência fica ligada mesmo assim.** Desligá-la faria o
histórico e o catálogo desaparecerem sem rede. O aplicativo é usado em campo,
onde sinal é exatamente o que falta. Trocar isso por uma proteção que só vale
contra um aparelho já comprometido seria mau negócio.

**O que já reduz o alcance:**

| Controle | Efeito |
|---|---|
| Teto de 40 MB, não `CACHE_SIZE_UNLIMITED` | o cache não cresce enquanto houver disco; o Firestore descarta o mais antigo |
| `clearPersistence()` no encerramento de sessão | quem sai não deixa o histórico em disco para o próximo usuário do aparelho |
| `allowBackup="false"` + `fullBackupContent="false"` | o backup do Android não leva o arquivo |
| `data_extraction_rules.xml` com `<exclude domain="root" path="." />` | Android 12+ ignora `allowBackup`; sem este arquivo o atributo não valeria nada |

**Risco residual, declarado.** Num aparelho com root, ou com acesso físico e
depuração habilitada, o arquivo é legível. Isso não é corrigível pelo
aplicativo — é a premissa do 61.19 e do modelo de ameaça: *dispositivo
comprometido* é um atacante contra o qual o aplicativo não vence sozinho. O
que o aplicativo pode fazer, e fez, é não ampliar o alcance via backup e não
deixar resíduo após o logout.

Registrado como **risco aceito**, não como pendência.

## 61.3 — Classificação dos dados

| Dado | Classe | Onde | Quem acessa |
|---|---|---|---|
| Catálogo de espécies (nome, descrição, distribuição) | PÚBLICO | Firestore `species` | qualquer um autenticado |
| Nome exibido, e-mail | PRIVADO | Firestore `users/{uid}` | o próprio dono, e o backend com o uid verificado |
| `role` | INTERNO CRÍTICO | Firestore `users/{uid}` | **escrita só por console/servidor** |
| Fotografias enviadas | SENSÍVEL | Storage `users/{uid}/identifications/...` | só o dono |
| Histórico de identificações | SENSÍVEL | Firestore `identifications` | só o dono |
| `confidence`, `speciesId`, `modelVersion` | INTERNO | Firestore | **escrita só pelo servidor** (HIGH-1) |
| Token de sessão | SEGREDO | aparelho, gerido pelo SDK | ver 61.14 |
| Service account do backend | **SEGREDO CRÍTICO** | variável de ambiente no servidor | ninguém, nem em log |

O detalhamento completo, com finalidade, retenção e base legal, está em
`DATA_MAP.md`.

### Por que as fotos são SENSÍVEL e não só PRIVADO

Uma foto de escorpião tirada por alguém diz onde essa pessoa esteve, e em
muitos casos dentro de qual casa. Combinada com a data e o perfil, é um rastro
de localização. Tratar como "só uma foto de bicho" seria subestimar o dado.

## 61.4 — Criptografia das fotos

🟢 O fluxo que o briefing pede já é o que está no lugar:

```
App  ──TLS──►  Cloud Storage (privado)  ──►  cifrado em repouso
                      │
                 regra confere request.auth.uid == {userId} do caminho
```

Verificado em `firebase/storage.rules`:

- `users/{userId}/identifications/{id}/{arquivo}` — leitura e escrita só para
  `request.auth.uid == userId`;
- `catalog/{**}` — leitura pública, escrita negada a **todos** os clientes:
  publicar conteúdo científico é operação de console ou de backend;
- `match /{allPaths=**} { allow read, write: if false; }` como negação final,
  que fecha a raiz do bucket.

Público e privado ficam em árvores separadas, como a FASE 56 do briefing de
segurança pede. Nenhuma foto de usuário é pública, em nenhum caminho.

## 61.6, 61.7 e 61.20 — Gestão de chaves e menor privilégio

🟢 Verificado:

| Onde uma chave **não** está | Confirmado por |
|---|---|
| no código do aplicativo | varredura em `lib/` |
| no APK | não há nada para empacotar |
| no Git, inclusive no histórico | varredura descrita em 61.21 |
| no Firestore ou no Storage | nenhum documento de configuração com segredo |
| na documentação | `.env.example` traz **nomes** de variáveis e um JSON de exemplo com `"..."` |

A service account chega ao backend por variável de ambiente, aceitando JSON ou
base64 — base64 porque alguns provedores estragam as quebras de linha, e a
chave privada tem várias. O campo é declarado com `repr=False`, para que a
chave não vá junto quando alguém imprimir as configurações numa investigação.
Isso é verificado por teste:

```python
def test_credencial_nao_aparece_na_representacao(monkeypatch) -> None:
    ...
    assert "SEGREDO-QUE-NAO-PODE-VAZAR" not in texto
```

**Separação de chaves (61.7):** hoje existe **uma** credencial de servidor, a
service account. Não há chave de cifragem de banco, de assinatura de token nem
de backup, porque não há cifragem própria, os tokens são assinados pelo Google
e não há backup. Criar quatro variáveis de ambiente para honrar uma lista
seria teatro.

**Menor privilégio para chaves (61.20):** a service account ignora as Security
Rules — se vazar, entrega o banco inteiro. O aplicativo não a tem. Um ponto a
melhorar, registrado: ela é a service account **padrão** do projeto, com
privilégio amplo. Uma conta de serviço dedicada, com apenas
`datastore.user` e `storage.objectAdmin` restrito ao prefixo necessário, seria
o correto. Isso é configuração de IAM no console — **ação do Gustavo**, listada
no fim.

## 61.8 — Rotação de chaves

Hoje: nenhum procedimento escrito. Com uma credencial só, o procedimento é
curto, e estar curto não é motivo para não existir — se ela vazar às duas da
manhã, ninguém vai inventar o passo a passo na hora.

### Procedimento, para a service account

**Rotação de rotina** — a cada 12 meses, ou quando alguém com acesso ao
servidor sai do projeto:

1. console do Firebase → Configurações do projeto → Contas de serviço → Gerar
   nova chave privada;
2. colar o JSON novo na variável de ambiente do provedor;
3. reiniciar o serviço e confirmar que `/health` responde `ok`;
4. **só então** apagar a chave antiga no console. Nessa ordem: apagar primeiro
   derruba o serviço;
5. registrar a data neste arquivo.

**Chave comprometida** — a ordem muda, porque conter vem antes de manter no ar:

```
REVOGAR  ─► apagar a chave no console AGORA. O serviço cai. Deixar cair.
   │
ROTACIONAR ─► gerar a nova, publicar, subir
   │
INVESTIGAR ─► Google Cloud → Logging: que operações essa chave fez, e quando
   │
AUDITAR  ─► comparar com o esperado; procurar leitura em massa e escrita em
            documentos que o backend não escreve
```

Não considerar resolvido porque a chave foi trocada — o 61.22 é explícito. Uma
chave vazada pode já ter sido usada, e o que ela leu não volta.

**Quem pode rotacionar:** o dono do projeto Firebase (hoje, só o Gustavo).

**Se for perdida sem ter vazado:** nenhum dado é perdido. A service account
não cifra nada; ela autentica. Gerar outra resolve. Essa é uma vantagem real
de não ter criptografia própria — o 61.24 pergunta *"o que acontece se a chave
for perdida?"*, e aqui a resposta é "nada".

## 61.9 — Criptografia de campo

**Recomendação: não aplicar.** O 61.9 pede que a necessidade seja verificada
antes, e ela não se sustenta aqui:

| Pergunta do 61.24 | Resposta |
|---|---|
| O provedor já oferece criptografia? | Sim, em repouso, com chave gerenciada |
| Existe necessidade adicional? | Não identificada. O risco real não é alguém ler o disco do Google — é autorização falha, e isso se resolve com regra, não com cifra |
| Quem precisaria decifrar? | O backend e o próprio dono. Ou seja, quase todo mundo que lê — o que esvazia o ganho |
| Onde a chave ficaria? | Cloud KMS. Custo e complexidade reais |
| Como afetaria a busca? | Mataria a busca no catálogo e qualquer consulta por campo cifrado |
| Como afetaria a recuperação? | Chave perdida = dado perdido para sempre. Hoje, chave perdida = nada |

Cifrar campo por campo aqui adicionaria um jeito novo de perder os dados do
usuário sem fechar nenhum caminho de ataque conhecido.

## 61.10 e 61.11 — Senhas e hashing

🟢 Verificado:

- O aplicativo **não armazena senha**, em nenhuma forma. Ela vai do campo de
  texto direto para `FirebaseAuth.signInWithEmailAndPassword` e não é
  persistida, cacheada nem registrada.
- Nenhum `MD5`, `SHA1`, `ECB` ou `AES(password)` existe no projeto.
- O Firebase Authentication guarda a senha com **scrypt** modificado, com
  parâmetros definidos pelo Google. Não é Argon2id, que o 61.10 cita como
  exemplo, mas é uma função de derivação específica para senha, com sal e
  fator de custo — que é o requisito real. O 61.10 fecha dizendo: *"Se Firebase
  Authentication estiver sendo utilizado, não implementar armazenamento próprio
  de senha sem necessidade."*
- O script de semeadura do catálogo pede a senha com **o eco do terminal
  desligado**, para que ela não apareça na tela nem no histórico do shell.

A distinção que o 61.11 pede está respeitada: nenhum hash é usado como se fosse
cifra reversível, e nenhuma cifra é usada onde se queria hash.

## 61.12 e 61.13 — Assinatura e tokens

🟢 Verificado:

- O backend valida o ID token com `verify_id_token(check_revoked=True)` — a
  assinatura é conferida contra a chave pública do Google, e a revogação é
  consultada. Sem `check_revoked`, um token de alguém que acabou de sair da
  conta continuaria válido até expirar.
- O `uid` sai do token, **nunca** do corpo da requisição. É o IDOR fechado por
  construção: o caminho de armazenamento é montado com o uid verificado, então
  um `sessionId` apontando para a pasta de outra pessoa não encontra nada.
- Nenhum token em URL, em parâmetro de consulta ou em mensagem de erro.
- `AnalysisRequest` usa `extra: "forbid"`: um corpo com `confidence`,
  `userId`, `role` ou `speciesId` é **recusado**, não tem o campo ignorado em
  silêncio. Recusar é melhor — quem tentou descobre que tentou algo que não
  existe.

## 61.14 — Armazenamento seguro no aparelho

🟡 A resposta honesta aqui é curta: **o aplicativo não guarda segredo nenhum no
aparelho**, então não há nada para mover para o Keychain ou o Keystore.

Verificado por varredura: o projeto não usa `shared_preferences`,
`flutter_secure_storage`, Hive, `sqflite` nem `path_provider`. Nenhuma dessas
está no `pubspec.yaml`. As preferências do usuário (tema, idioma,
notificações) vivem **em memória**, e os comentários do
`SettingsController` registram isso.

O único segredo que existe no aparelho é o token de sessão, **persistido pelo
SDK do Firebase Auth**, não pelo código deste projeto. No Android o SDK o
guarda em um arquivo de preferências próprio, não no Android Keystore. Isso é
escolha do SDK do Google e está fora do controle do aplicativo.

O que reduz o alcance é o mesmo conjunto do C-2 — e aqui está a ligação que
vale registrar: a correção do `allowBackup` (MEDIUM-2 da auditoria de
segurança) é também a mitigação deste item. O token não sai do aparelho em
backup nem em transferência.

**Recomendação explícita: não adicionar `flutter_secure_storage`.** Não há o
que guardar nele. Adicionar uma dependência para honrar um item de lista
contraria o §5 do briefing de otimização e aumenta a superfície sem fechar
nada.

Quando a Fase 5 ligar o cliente do backend, isso **continua** valendo: a
chamada usa o ID token do Firebase, obtido do SDK a cada requisição. Não há
chave de API própria para o aplicativo guardar — e não deve haver (61.18).

## 61.15 — Cache

| Cache | Risco | Situação |
|---|---|---|
| Persistência do Firestore | dado pessoal em disco | 🟡 C-2, com quatro mitigações |
| Catálogo em memória, por sessão | nenhum — dado público | 🟢 |
| Cache HTTP / CDN | nenhum — as fotos não passam por CDN pública | 🟢 |
| Arquivos temporários de imagem | a câmera e a galeria escrevem o arquivo original no diretório temporário do aplicativo | 🟡 incluído nas regras de exclusão de backup; não é apagado explicitamente após o envio |

O último merece uma frase honesta: o aplicativo lê os bytes do arquivo que a
câmera ou a galeria produziu e não apaga o arquivo depois. O sistema limpa o
diretório temporário por conta própria, mas não em momento previsível. Está
coberto contra backup; não está apagado. Pequeno, real, registrado.

## 61.16 — Backups

⚪ **Não existem backups.** O Firestore no plano Spark não oferece exportação
agendada, que depende de Blaze. Então não há backup público para proteger, e
também não há backup nenhum — o que é um risco de outra natureza, de perda de
dados, tratado em `RETENTION_POLICY.md`.

Dizer "backups estão cifrados" aqui seria afirmar o que não foi feito.

## 61.17 — Registros

🟢 Verificado, e é a parte da qual este projeto pode se orgulhar: a proibição
não depende de disciplina.

`AppLog` mantém uma lista de chaves que nunca podem ser registradas —
`password`, `senha`, `token`, `apikey`, `secret`, `email`, `credential`,
`authorization`, `bytes`, `image`, `photo`, `foto`, `uid`, `userid`, `path`,
`url` — e a verifica em `assert`. Em depuração, o aplicativo **quebra** se
alguém tentar registrar uma delas. Em produção o `assert` desaparece, mas o
código que teria disparado já foi corrigido antes de chegar lá.

Isso atende exatamente o que o 61.17 pede: *"Primeiro: NÃO REGISTRAR O DADO
DESNECESSÁRIO."* Não se cifra registro para poder registrar demais.

Detalhes verificados:

- os `debugPrint` do projeto estão atrás de `if (!kDebugMode) return;` —
  importante porque `debugPrint` **continua escrevendo em release**; só
  `assert` é removido. Uma exceção, em `firebase_bootstrap.dart:118`, está
  registrada como B-4 na auditoria de otimização;
- o backend registra `request_id` e a contagem de vistas. Não registra uid,
  e-mail nem caminho de arquivo;
- o tratador de exceção devolve ao cliente uma frase e o `requestId`. A pilha
  de chamadas vai para o log do servidor, não para a tela.

## 61.18 — Terceiros

⚪ Nenhuma API de terceiro é chamada, nem pelo aplicativo nem pelo backend.
Não há chave de terceiro para proteger, e nenhuma imagem de usuário sai do
Google Cloud.

O inventário dos subcontratados que **existem** (Google/Firebase) está em
`THIRD_PARTY_PROCESSORS.md`.

A regra do 61.18 fica registrada para a Fase 5: se um serviço externo de
inferência entrar, é o **backend** que fala com ele, nunca o aplicativo, e a
chave vive na variável de ambiente do servidor.

## 61.21 — Varredura de segredos expostos

Feita à mão nesta auditoria, sobre o histórico inteiro do Git:

```bash
git grep -I -l -E "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AIza[0-9A-Za-z_-]{35}|\"private_key\" *:|sk-[A-Za-z0-9]{20}" $(git rev-list --all)
```

Resultado: três arquivos, **nenhum deles um segredo**.

| Arquivo | O que casou | Veredito |
|---|---|---|
| `lib/firebase_options.dart` | `AIza…` | Chave de API do Firebase para cliente. **Pública por desenho** — ela identifica o projeto, não autoriza nada. O que protege é as Security Rules e o App Check. Já registrado como INFO-2 |
| `firebase/seed-cloud.mjs` | a mesma `AIza…` | idem — o script faz login real com e-mail e senha, e são as regras que decidem se ele pode escrever |
| `backend/tests/test_security.py` | `"private_key":"nao-e-uma-chave"` | valor falso de teste, escolhido para ser obviamente falso |

Nenhuma chave privada, nenhuma senha, nenhuma service account em nenhum
commit, ramo ou etiqueta. Nada a revogar, nada a reescrever do histórico.

### C-1 — A varredura não é automática 🔴

Este resultado limpo vale para hoje e para quem fez a varredura. O próximo
commit não é coberto por ele.

O briefing pede isso duas vezes — FASE 28 do briefing de segurança e 61.21
aqui — e o CI tem três trabalhos (`aplicativo`, `backend`, `regras`) e **nenhum
deles procura segredo**. Também não há SAST nem análise de composição de
dependências.

É a lacuna mais acionável de toda esta auditoria: barato de fechar, e fecha um
caminho que nenhuma revisão humana cobre de forma confiável. Um segredo
commitado por engano às onze da noite não espera a próxima auditoria.

Recomendação: um quarto trabalho no CI com Gitleaks, varrendo o histórico
completo, bloqueando o merge quando encontrar. Mais `pip-audit` para o backend
e `flutter pub outdated` como aviso. Detalhado no plano, ao fim.

## 61.19 — Criptografia não substitui autorização

🟢 É o princípio que organiza o resto, e está respeitado por construção:

```
Identidade    ID token verificado contra a chave pública do Google
Autorização   Security Rules conferem request.auth.uid; papel lido de
              users/{uid}, no servidor, falhando para `user`
Caminho       users/{uid}/... montado com o uid VERIFICADO, nunca com o
              que veio no corpo
Cifra         gerenciada pelo provedor, por baixo de tudo isso
```

O usuário A não recebe chave para decifrar nada do usuário B porque não há
chave para receber: o acesso é negado antes, pela regra. O teste
`test_requires_bloqueia_papel_insuficiente` confirma que a recusa vem com 403 e
uma mensagem que **não diz** qual papel faltava nem se o recurso existe —
entregar isso daria o mapa a quem está sondando.

Um papel corrompido, ausente ou adulterado vira `user`, nunca promoção:
`Role.parse` falha para o menor privilégio, e o teste percorre `None`, `""`,
`"superadmin"`, `"ADMIN"`, `"root"`, `"admin "` e `"0"` para garantir.

## 61.23 — Testes de criptografia e vazamento

O que já existe:

| Verificação | Onde | Quantos |
|---|---|---|
| Regras do Firestore e do Storage, incluindo acesso cruzado entre usuários | `firebase/test/` | 60 |
| Autorização, mass assignment, travessia de caminho, papéis, segredo fora da representação, CORS sem curinga | `backend/tests/test_security.py` | 34 |
| Paridade da fusão Dart ↔ Python | `backend/tests/test_parity.py` | 36 casos |
| Formas dos documentos (contrato entre app e regras) | `test/contract_shapes_test.dart` | — |

O que **falta**, e entra no plano:

- um teste que falhe se aparecer segredo no código — hoje é a varredura manual
  acima (C-1);
- um teste que confirme que o aplicativo não declara nenhuma URL `http://`
  fora de localhost. Hoje isso é verdade por não haver URL nenhuma; quando a
  Fase 5 escrever o cliente, essa verdade precisa de guarda (C-3).

## 61.24 — Revisão antes de implementar criptografia própria

As dez perguntas do 61.24 foram respondidas em 61.9. O resultado é o que o
próprio briefing prescreve: *"Se não houver resposta clara, NÃO implementar uma
solução criptográfica improvisada."*

Não há necessidade clara. Nada próprio será implementado.

## Plano

| | Ação | Quem | Classe |
|---|---|---|---|
| 1 | Gitleaks + `pip-audit` no CI, bloqueando merge (C-1) | eu | 🔴 → fechável agora |
| 2 | Registrar C-2 como risco aceito, com as quatro mitigações | feito neste arquivo | 🟡 |
| 3 | Guarda de `https://` quando o cliente do backend nascer (C-3) | Fase 5 | 🟡 pendente |
| 4 | Apagar o arquivo temporário da imagem após o envio (61.15) | eu | 🟡 pequeno |
| 5 | Service account dedicada, com IAM mínimo em vez da padrão do projeto (61.20) | **Gustavo, no console** | 🟡 |
| 6 | Primeira rotação da service account, e registrar a data aqui (61.8) | **Gustavo** | 🟢 rotina |
| ⚪ | Fixação de certificado | **não fazer** — justificado em 61.1 | ⚪ |
| ⚪ | Criptografia de campo | **não fazer** — justificado em 61.9 | ⚪ |
| ⚪ | `flutter_secure_storage` | **não adicionar** — justificado em 61.14 | ⚪ |
| ⚪ | Backups cifrados | depende de Blaze; ver `RETENTION_POLICY.md` | ⚪ |

## O que esta auditoria não pode afirmar

O briefing proíbe certas frases, e com razão. Então, explicitamente:

- não foi feito pentest profissional, e nada aqui equivale a um;
- a criptografia do Google é afirmada com base na documentação dele, não em
  verificação independente — nenhum cliente pode verificar isso;
- a varredura de segredos cobre padrões conhecidos. Um segredo em formato que o
  padrão não reconhece passaria;
- C-2 é risco **aceito**, não resolvido. Num aparelho com root, o histórico do
  usuário é legível, e nada no aplicativo muda isso;
- a configuração de IAM da service account não foi inspecionada no console —
  ela é descrita como "padrão do projeto" por ser o que o procedimento de
  `.env.example` gera, e precisa de confirmação.

O que foi feito: inventariar onde cada dado repousa, confirmar que a cifra em
repouso e em trânsito existe onde há dado, confirmar que nenhuma chave está no
aplicativo ou no histórico, e escrever o procedimento de rotação que não
existia.

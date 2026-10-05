# Modelo de ameaças

Resposta à FASE 42. Dez atacantes, o que cada um consegue hoje, e o que o
impede.

Data: 5 de outubro de 2026.

A pergunta que organiza o documento não é "o sistema é seguro?" — não é
respondível. É: **para cada atacante, qual é o pior resultado alcançável, e
qual controle específico o limita?**

## Ativos, em ordem de gravidade se perdidos

| | Ativo | Pior caso |
|---|---|---|
| 1 | Service account do backend | entrega o banco inteiro — ela **ignora** as Security Rules |
| 2 | Fotografias dos usuários | rastro de onde pessoas estiveram |
| 3 | `role` no Firestore | promoção a admin; acesso a tudo |
| 4 | Histórico de identificações | perfil de comportamento de uma pessoa |
| 5 | E-mails | base para phishing direcionado |
| 6 | Cota do Firebase / orçamento | conta suspensa, aplicativo fora do ar |
| 7 | Integridade do resultado da IA | métricas falsas, dataset envenenado |
| 8 | Catálogo científico | raspagem — é conteúdo que seria público de todo modo |

## T-1 — Atacante externo, sem conta

**Quer:** entrar.

| Tentativa | Resultado |
|---|---|
| Ler `identifications` sem autenticar | 🟢 negado — regra exige `request.auth != null` e posse |
| Ler foto pelo URL do Storage | 🟢 negado — `isOwner(userId)` compara com o segmento do caminho |
| Chamar `POST /v1/analyses` sem token | 🟢 401 — `current_caller` recusa |
| Chamar `GET /v1/review-queue` | 🟢 401, e depois 403 por papel |
| Abrir a documentação da API | 🟢 `docs_url=None`, `openapi_url=None` |
| Usar o token de um usuário a partir de outra origem (navegador) | 🟢 CORS por lista explícita; sem `ALLOWED_ORIGINS` a lista é **vazia**, não `*` |
| Ler a raiz do bucket | 🟢 negação final `allow read, write: if false` |
| Força bruta no login | 🟡 Firebase Auth limita por conta, mas não há proteção própria — MEDIUM-4 |

**Pior caso hoje:** ler o catálogo de espécies, se conseguir uma conta. É
conteúdo científico público.

## T-2 — Usuário malicioso, com conta legítima

O atacante mais provável, e o que o briefing mais enfatiza. Tem token válido —
autenticado **não** é autorizado.

| Tentativa | Resultado |
|---|---|
| Ler identificação de outro usuário (IDOR) | 🟢 negado — regra confere `resource.data.userId == request.auth.uid` |
| Ler foto de outro usuário | 🟢 negado — o `uid` está no caminho |
| Criar identificação com `userId` de outro | 🟢 negado — a regra compara com `request.auth.uid` |
| Escrever `confidence: 0.99` | 🟢 **negado** — `serverOwnedFields()` recusa o campo na criação |
| Criar limpo e reescrever `confidence` depois | 🟢 **negado** — `!changedFields().hasAny(serverOwnedFields())` na atualização |
| Mandar `confidence` no corpo da API | 🟢 recusado — `extra: "forbid"` do Pydantic rejeita o corpo inteiro |
| Promover-se a `admin` escrevendo em `users/{uid}` | 🟢 negado — `role` é campo de servidor |
| Mandar `role: admin` no corpo da API | 🟢 recusado — mesmo mecanismo |
| Travessia de caminho no nome do arquivo (`../outro/original.jpg`) | 🟢 recusado — lista fechada de nomes, no servidor e na regra |
| Pedir análise de 1.000 vistas | 🟢 recusado — teto de 2 vistas |
| Enviar arquivo de 100 MB | 🟢 recusado — 8 MB na regra do Storage |
| Enviar `.exe` renomeado para `.jpg` | 🟡 `contentType` vem do cliente e pode mentir — LOW-1. O conteúdo real não é validado no servidor |
| Gerar 10.000 análises e estourar a cota | 🔴 **consegue** — MEDIUM-4 |

**Pior caso hoje:** esgotar a cota do projeto. `maxIdentificationsPerDay = 60`
existe como constante e **ninguém a aplica** — nem o aplicativo, nem as regras.
O comentário no código diz isso em voz alta, de propósito.

## T-3 — Conta de usuário comprometida

O atacante tem a senha de alguém.

| | |
|---|---|
| Alcança | tudo o que aquele usuário alcança: o próprio histórico, as próprias fotos |
| 🟢 Não alcança | dados de outros usuários, nem recursos administrativos |
| 🟡 Lacuna | **não há reautenticação** para operação sensível (MEDIUM-5). Hoje não existe operação sensível no aplicativo, então a lacuna é latente — quando a exclusão de conta existir (HIGH-2), ela precisa pedir a senha de novo |
| 🟢 Mitigação ativa | `check_revoked=True` no backend: se a senha for trocada, o token em uso deixa de valer |

## T-4 — Conta administrativa comprometida

**O cenário mais grave que depende de credencial.**

| | |
|---|---|
| Alcança | tudo que o papel `admin` permite nas regras |
| 🔴 Lacuna | **sem MFA** (LOW-3). Uma senha é tudo que separa o atacante do papel de admin |
| 🔴 Lacuna | **sem audit log** (LOW-4). Um admin comprometido lê dados de usuários e nada registra |
| 🟢 Mitigação | o papel é lido do Firestore no servidor, não enviado pelo cliente; `Role.parse` falha para `user` |
| 🟡 Agravante registrado | a conta do Gustavo é `admin` **e** dono do projeto Firebase. Comprometê-la entrega o console, que está acima de qualquer regra |

**Ação mais valiosa de toda esta auditoria, e é do Gustavo:** ativar
verificação em duas etapas na conta Google dona do projeto. Nenhum controle no
código supera isso.

## T-5 — Desenvolvedor ou máquina de desenvolvimento comprometida

| | |
|---|---|
| Alcança | o repositório, e o console do Firebase se a sessão estiver aberta |
| 🟢 Mitigação | **nenhum segredo no repositório** — varredura do histórico completo em `CRYPTO_AUDIT.md` (61.21). Clonar o repositório não dá acesso a nada |
| 🟢 Mitigação | a service account vive só em variável de ambiente do provedor, nunca em arquivo |
| 🔴 Lacuna | sem varredura automática de segredos no CI (C-1). Um segredo commitado por engano não é detectado |
| 🟡 Realidade | esta é uma máquina de uso pessoal, com Smart App Control ativo. Não há separação entre ambiente de desenvolvimento e uso cotidiano. Risco aceito, de um TCC individual |

## T-6 — Terceiro comprometido

| Terceiro | Exposição |
|---|---|
| Google / Firebase | **total** — ele hospeda tudo. Não há mitigação possível no aplicativo; é a premissa de usar nuvem gerenciada |
| Nenhum outro | ⚪ nenhuma API externa é chamada |

Importante, e o briefing insiste (FASE 51): usar o Google **não transfere a
responsabilidade legal**. Ele é operador; o controlador é quem define a
finalidade. Quem é o controlador neste projeto — o Gustavo, a UTFPR, ou os dois
— é definição institucional, não técnica.

## T-7 — Dispositivo do usuário comprometido

Aparelho com root, infectado ou com depuração habilitada.

| | |
|---|---|
| Alcança | o cache do Firestore em disco (histórico e perfil, **não cifrado**) e o token de sessão |
| 🟢 Mitigação | `allowBackup="false"` + `fullBackupContent="false"` + `data_extraction_rules.xml` — nada sai em backup ou transferência de aparelho |
| 🟢 Mitigação | `clearPersistence()` no logout — quem sai não deixa resíduo para o próximo usuário do aparelho |
| 🟢 Mitigação | teto de 40 MB no cache, em vez de ilimitado |
| 🟡 Risco residual aceito | com acesso físico e root, o arquivo é legível. Nenhum aplicativo vence isso sozinho — ver C-2 em `CRYPTO_AUDIT.md` |
| 🟢 Importante | **o aparelho comprometido não vira privilégio.** As regras conferem `request.auth.uid`; o atacante só alcança o que aquele usuário alcança |

## T-8 — Abuso automatizado da API

| | |
|---|---|
| 🔴 **Pior lacuna conhecida** | nenhum limite de taxa em lugar nenhum — MEDIUM-4 |
| 🟡 Parcial | App Check atesta que a requisição vem de instalação legítima do aplicativo. Reduz script, **não** limita o aplicativo real em laço |
| 🟢 Limite estrutural | o backend recusa mais de 2 vistas por análise, e o Storage recusa acima de 8 MB. Isso limita o custo **por** requisição, não o número delas |
| 🟢 Limite acidental | `POST /v1/analyses` responde 503 — não há modelo para abusar ainda |

A última linha é a razão honesta pela qual isso não é 🔴 bloqueante hoje: não
existe inferência para consumir. Quando o modelo entrar, a contenção precisa
entrar **antes** — e precisa ser de servidor. Um freio no cliente custaria uma
consulta por envio e um cliente adulterado o ignoraria: pagaria o preço sem
entregar a proteção.

## T-9 — Raspagem de dados

| Alvo | Resultado |
|---|---|
| Catálogo de espécies | 🟡 **consegue** — leitura liberada a autenticados (INFO-1). É conteúdo científico, que seria publicado de todo modo |
| Dados de outros usuários | 🟢 negado pelas regras |
| Modelos 3D | ⚪ não existem |
| Enumerar usuários por e-mail no cadastro | 🟡 o Firebase Auth pode revelar se um e-mail existe, dependendo da configuração de proteção de enumeração no console |

## T-10 — Engenharia reversa do aplicativo

O atacante descompila o APK.

| Encontra | Importa? |
|---|---|
| Chave de API do Firebase | **não** — pública por desenho; identifica o projeto, não autoriza nada |
| Nomes das coleções e a forma dos documentos | **não** — as regras não dependem de segredo |
| Endereço do backend | não há nenhum ainda; quando houver, também não é segredo |
| Lógica de fusão e de limiares de decisão | **não** — o servidor recalcula e é ele quem grava (HIGH-1) |
| Segredo | 🟢 **nenhum.** Não há o que encontrar |

Este é o ponto em que a arquitetura se paga. A FASE 32 avisa contra "segurança
falsa apenas escondendo endpoints"; aqui nada depende de estar escondido. Um
APK totalmente descompilado não entrega nada além do que a documentação pública
do Firebase já entrega.

## Resumo: o que de fato está aberto

| | Lacuna | Atacante | Gravidade | Onde está registrada |
|---|---|---|---|---|
| 1 | Sem limite de taxa | T-2, T-8 | 🔴 quando o modelo existir | MEDIUM-4 |
| 2 | Sem exclusão de conta | — (é direito do titular, não ataque) | 🔴 | HIGH-2 |
| 3 | Sem MFA no admin | T-4 | 🔴 | LOW-3 |
| 4 | Sem audit log | T-4 | 🟡 | LOW-4 |
| 5 | Sem varredura de segredos no CI | T-5 | 🔴 fechável agora | C-1 |
| 6 | `contentType` não validado no servidor | T-2 | 🟡 | LOW-1 |
| 7 | Cache local não cifrado | T-7 | 🟡 risco aceito | C-2 |
| 8 | Sem verificação de e-mail | T-1, T-8 | 🟡 | MEDIUM-3 |
| 9 | Sem política de retenção | — | 🔴 antes de produção | `RETENTION_POLICY.md` |

## O que este modelo não cobre

- **Nenhum teste de intrusão foi feito.** As colunas "resultado" acima vêm de
  ler as regras e de 94 testes automatizados (60 de regras, 34 do backend), não
  de alguém atacando o sistema de verdade.
- Ataques à infraestrutura do Google estão fora do alcance de qualquer controle
  deste projeto.
- Ataques de canal lateral, análise de tráfego e correlação temporal não foram
  considerados — desproporcionais ao porte.
- A hipótese de que as Security Rules fazem o que dizem está verificada por
  teste contra o emulador, não contra produção. Testar contra produção
  significaria escrever no banco real, que o briefing proíbe.

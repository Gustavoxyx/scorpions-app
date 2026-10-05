# Auditoria de segurança — Scorpions

**Data:** 2026-10-05
**Versão auditada:** commit `3d18e20` (Fase 4 concluída)
**Referências:** OWASP MASVS 2.x, OWASP ASVS 4.0, OWASP API Security Top 10 (2023), LGPD (Lei 13.709/2018)
**Escopo:** aplicativo Flutter, regras do Firestore e do Storage, scripts de infraestrutura, dependências, histórico do repositório

---

## Sumário

| Severidade | Quantidade |
|---|---|
| CRITICAL | 0 |
| HIGH | 2 |
| MEDIUM | 6 |
| LOW | 4 |
| INFO | 3 |

Nenhuma credencial exposta foi encontrada no código ou no histórico do repositório.

Os dois achados HIGH não são exploráveis hoje do jeito que o aplicativo está — um depende da IA que ainda não existe, o outro é uma obrigação legal sem implementação. Ambos **bloqueiam a Fase 5**, e é por isso que estão no topo.

---

## O que foi verificado e estava correto

Registrado porque uma auditoria que lista só problemas dá a impressão errada do estado do projeto.

| Verificação | Resultado |
|---|---|
| Secrets no código (`lib/`, `android/`, `ios/`, `web/`, `.github/`) | nenhum |
| Secrets no histórico do Git (todos os commits) | nenhum |
| `serviceAccount.json`, `.pem`, `.p12`, `.jks` jamais commitados | confirmado |
| Regra `allow read, write: if true` em dado privado | ausente |
| Negação final (`match /{document=**}`) no Firestore e no Storage | presente |
| Escalação de privilégio por `role` | bloqueada — a regra fixa `role == 'user'` na criação |
| IDOR horizontal em `identifications` | bloqueado — `resource.data.userId == uid()` |
| Enumeração de usuários | bloqueada — `allow list: if isAdmin()` |
| Imagens públicas | nenhuma — `users/{uid}/...` exige `isOwner` |
| Upload para caminho arbitrário | bloqueado — nome e caminho validados por regex |
| Dados pessoais além do necessário | nenhum: só `uid`, `name`, `email` |
| GPS nas fotos | removido antes do envio (`MetadataStripper`) |
| Permissões Android | só `CAMERA`; nenhuma de localização |
| Tráfego em claro | bloqueado pelo padrão do Android 9+ |
| Logs com dado sensível | bloqueado por `assert` em `AppLog` |
| App Check | ativo (Play Integrity / App Attest em release) |

---

## HIGH-1 — O cliente determina o resultado da análise

**Arquivos:** [firebase/firestore.rules:178](../firebase/firestore.rules#L178), [lib/data/models/identification.dart](../lib/data/models/identification.dart)
**Categoria:** OWASP API3:2023 (Broken Object Property Level Authorization) · MASVS-AUTH-2
**Risco hoje:** moderado · **Risco na Fase 5:** crítico

### A falha

A regra valida o **formato** de `confidence`, `modelVersion` e `status`, mas não a **origem**. Quem escreve esses campos é o aplicativo:

```
&& (request.resource.data.confidence == null
    || (request.resource.data.confidence is number
        && request.resource.data.confidence >= 0
        && request.resource.data.confidence <= 1))
```

Um `0.99` enviado por um cliente adulterado passa nessa validação exatamente como um `0.99` produzido por um modelo.

### Como seria explorada

Com o token de sessão legítimo do próprio usuário (obtido de um aparelho com root, de um proxy, ou chamando a API REST do Firestore direto), basta um POST:

```json
{ "userId": "<próprio uid>", "status": "identified",
  "confidence": 0.99, "modelVersion": "qualquer-coisa" }
```

O documento é aceito. O usuário forja uma identificação com a confiança que quiser.

### Impacto

Hoje é limitado: não existe IA, `status` é sempre `processing`, e o registro forjado só polui o histórico do próprio autor — não há dano a terceiros.

Na Fase 5 muda de natureza. O briefing dela é explícito em §11: *"Nunca permitir que o usuário simplesmente envie `confidence = 0.99` e isso seja salvo"*. Um registro forjado passaria a:

- contaminar as métricas de acurácia do modelo (§26, §33);
- entrar na fila de revisão humana como se fosse saída do modelo (§19);
- alimentar o dataset de retreinamento com rótulo falso (§22);
- quebrar a auditabilidade exigida em §39 — não haveria como distinguir o que o modelo disse do que o usuário digitou.

### Recomendação

**Este achado decide a arquitetura da Fase 5.** A inferência não pode rodar no cliente com o resultado escrito direto no Firestore. Duas saídas:

1. **Cloud Function / backend de inferência.** O cliente envia as imagens e cria o documento apenas com `status: 'processing'`. O servidor roda o modelo e escreve `species`, `confidence`, `modelVersion`. A regra passa a proibir o cliente de tocar nesses campos.
2. **Inferência no dispositivo (TFLite) com resultado assinado.** Mais barato, mas não resolve: um cliente adulterado também forja a assinatura. Serve para resposta rápida, não para o registro de verdade.

A opção 1 é a única que satisfaz §11 e §35 do briefing de segurança. A regra correspondente fica assim:

```
allow create: if ownsIncoming()
  && request.resource.data.status == 'processing'
  && !request.resource.data.keys().hasAny(['species','confidence','speciesId']);

allow update: if ownsExisting() && ownsIncoming()
  && !changedFields().hasAny(
       ['species','confidence','modelVersion','speciesId','reviewedBy']);
```

---

## HIGH-2 — Não existe exclusão de conta

**Arquivos:** nenhum — a funcionalidade não foi escrita
**Categoria:** LGPD Art. 18, incisos VI (eliminação) e IV (anonimização/bloqueio) · MASVS-PRIVACY-3
**Risco:** legal, não técnico

### A falha

Busquei por `deleteAccount`, `reauthenticate` e qualquer tela de exclusão. Não existe nada. A regra do Firestore inclusive **nega** a exclusão do perfil de propósito:

```
allow delete: if false;   // users/{userId}
```

O comentário ao lado está certo ao dizer que a exclusão real envolve Authentication, Storage e identificações, e que isso pertence a um backend. Mas o resultado prático hoje é que **não há caminho nenhum** para o titular exercer o direito.

### Impacto

O aplicativo coleta `email` e `name`, que são dados pessoais, e fotografias, que o próprio briefing classifica como potencialmente sensíveis (mostram onde a pessoa esteve). A LGPD dá ao titular o direito à eliminação, e o controlador — você — precisa oferecer o meio.

Para um TCC isso é também um ponto que a banca pode cobrar diretamente.

### Recomendação

Implementar `excluir minha conta` com:

1. **Reautenticação** antes de confirmar (exigência do próprio Firebase para `user.delete()`, e boa prática do ASVS 4.0 §2.5).
2. **Cascata**: apagar identificações, arquivos do Storage, perfil, e por último a conta do Authentication — nessa ordem, para que uma falha no meio não deixe a pessoa sem conta mas com dados.
3. Como a cascata precisa de privilégio que o cliente não tem, ela pertence a uma **Cloud Function** disparada pelo app — a mesma infraestrutura que a HIGH-1 vai exigir.
4. Documentar a retenção: o que é apagado na hora, o que fica em backup e por quanto tempo.

---

## MEDIUM-1 — Cache do Firestore ilimitado e não limpo no logout

**Arquivos:** [lib/data/services/firebase_bootstrap.dart:54](../lib/data/services/firebase_bootstrap.dart#L54), [lib/data/repositories/firebase_auth_repository.dart:121](../lib/data/repositories/firebase_auth_repository.dart#L121)
**Categoria:** MASVS-STORAGE-1

```dart
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

```dart
Future<void> signOut() => FirebaseErrorMapper.guard(() => _auth.signOut());
```

A persistência offline é uma decisão boa e bem justificada no comentário. O problema são duas consequências não tratadas:

1. **Sem teto.** `CACHE_SIZE_UNLIMITED` deixa o cache crescer indefinidamente no disco do aparelho.
2. **`signOut` não limpa nada.** Perfil e identificações do usuário anterior continuam em disco depois da saída. As Security Rules impedem o acesso *pela rede*, mas o arquivo local já está lá.

Em aparelho com root, ou com o backup do Android habilitado (ver MEDIUM-2), esses dados são extraíveis.

**Recomendação:** definir um teto explícito (ex.: 40 MB) e chamar `terminate()` seguido de `clearPersistence()` no logout. A ordem importa — `clearPersistence()` falha se houver conexão ativa.

---

## MEDIUM-2 — `android:allowBackup` não declarado

**Arquivo:** [android/app/src/main/AndroidManifest.xml:8](../android/app/src/main/AndroidManifest.xml#L8)
**Categoria:** MASVS-STORAGE-2

O atributo não está no manifesto, e o padrão do Android é `true`. Os dados do aplicativo — incluindo o cache do Firestore da MEDIUM-1 e o token de sessão — entram no backup do dispositivo.

Combinado com a MEDIUM-1, forma uma cadeia: cache ilimitado → backup automático → dado pessoal fora do controle do app.

**Recomendação:** `android:allowBackup="false"` e `android:fullBackupContent="false"`. Nada no aplicativo precisa sobreviver a uma troca de aparelho: o histórico vive no Firestore e volta no primeiro login.

---

## MEDIUM-3 — Sem verificação de e-mail

**Categoria:** ASVS 4.0 §2.1 · OWASP API2:2023

`sendEmailVerification` e `emailVerified` não aparecem em lugar nenhum — nem no app, nem nas regras. Qualquer e-mail, inclusive de domínio inexistente ou de outra pessoa, cria conta utilizável.

**Impacto:** permite criar contas em massa com endereços falsos, o que amplifica o MEDIUM-4 (abuso de cota) e envenena qualquer métrica por usuário na Fase 5.

**Recomendação:** enviar verificação no cadastro e exigir `request.auth.token.email_verified == true` nas regras de criação de identificação. Deixar a leitura do catálogo livre, para não travar quem só quer consultar.

---

## MEDIUM-4 — Nenhuma proteção contra abuso de cota

**Categoria:** OWASP API4:2023 (Unrestricted Resource Consumption)

Não há rate limiting em nenhuma camada. `ImageLimits.maxIdentificationsPerDay = 60` existe como constante e **não é lida por lugar nenhum** — está documentado como tal no próprio arquivo.

Um usuário autenticado pode criar identificações e enviar imagens em laço. No plano Spark isso derruba a cota diária; com Blaze, vira conta.

Na Fase 5 o risco muda de escala: cada identificação passa a custar uma inferência.

**Recomendação:** contador por usuário em `users/{uid}` incrementado por Cloud Function e conferido pela regra. O briefing da Fase 5 (§12) pede exatamente isso.

---

## MEDIUM-5 — Sem reautenticação para operações sensíveis

**Categoria:** ASVS 4.0 §2.5

Uma sessão do Firebase dura indefinidamente enquanto o refresh token for válido. Não há reautenticação para nenhuma operação. Com o aparelho desbloqueado nas mãos de outra pessoa, todo o histórico fica acessível e apagável.

**Recomendação:** exigir senha novamente para exclusão de conta (obrigatório pelo Firebase de qualquer forma) e para exclusão em massa de identificações.

---

## MEDIUM-6 — Dependências de desenvolvimento com CVE conhecida

**Arquivo:** [firebase/package.json](../firebase/package.json)
**Categoria:** OWASP A06:2021

`npm audit` reporta 5 vulnerabilidades HIGH, todas na mesma raiz: `@grpc/grpc-js@1.9.16`, trazido transitivamente por `firebase@12.18.0`. Corrigida na 1.14.5.

```
firebase@12.18.0 → @firebase/firestore@4.17.1 → @grpc/grpc-js@1.9.16
```

**Contexto que reduz a severidade real:** essas dependências existem só em `firebase/`, para testes de regra e scripts de seed. O aplicativo Flutter usa os SDKs Dart e nativos, que não passam por aí. `npm audit --omit=dev` reporta **0 vulnerabilidades**.

Ainda assim, `seed-cloud.mjs` roda contra produção usando esse SDK.

**Recomendação:** subir para `firebase@12.19.0` e reavaliar; se a transitiva não resolver, usar `overrides` no `package.json`. Testar depois — o `@firebase/rules-unit-testing@5` tem restrição de versão do `firebase`.

---

## LOW-1 — `contentType` do Storage vem do cliente

**Arquivo:** [firebase/storage.rules:41](../firebase/storage.rules#L41)

Já documentado honestamente no próprio arquivo: a regra barra o descuidado, não o mal-intencionado. Um arquivo arbitrário com `Content-Type: image/jpeg` passa.

O dano é contido pelo limite de 8 MB, pelo regex de nome de arquivo e pelo caminho isolado por `uid`. O pior caso é o usuário desperdiçar o próprio espaço.

**Recomendação:** validar a assinatura binária em Cloud Function antes da análise. O `ImageValidator` já faz exatamente isso no cliente — a lógica é reaproveitável.

## LOW-2 — Sem política de retenção de imagens

Nenhuma imagem é apagada automaticamente. O briefing de segurança §7 pede que a retenção seja definida. Hoje as fotos ficam indefinidamente.

## LOW-3 — Sem MFA para a conta administrativa

A conta com `role: 'admin'` usa apenas e-mail e senha. Ela pode ler qualquer perfil, enumerar a base e reescrever o catálogo.

**Nota:** o dono do projeto optou conscientemente por manter a própria conta como `admin` permanentemente. MFA no Google/Firebase Console é a mitigação que não depende do aplicativo.

## LOW-4 — Sem audit log

Nenhum registro de quem fez o quê. Operações administrativas (escrita no catálogo, leitura de perfil alheio) não deixam rastro. Os §19 e §39 da Fase 5 vão exigir.

---

## INFO-1 — Catálogo com leitura pública

`allow read: if true` em `species` é **intencional e correto**: conteúdo científico sem dado pessoal, consultável antes do cadastro. Verificado em produção: lê sem login, e `users`/`identifications` devolvem `permission-denied`.

Consequência aceita: o catálogo pode ser raspado. Mitigação parcial pelo App Check.

## INFO-2 — Chaves do Firebase no repositório

`firebase_options.dart` contém `apiKey` e `appId`. **Não são secrets** — identificam o projeto e vão dentro de todo aplicativo publicado. Quem autoriza são as Security Rules. Confirmado pela documentação do Firebase.

## INFO-3 — Nenhum deep link declarado

O manifesto não registra `intent-filter` de `VIEW`. O `_pendingDeepLink` do roteador não é alcançável de fora hoje. Quando a Fase 6 adicionar compartilhamento de espécie, a validação do destino passa a ser necessária.

---

## O que não pôde ser verificado

| Item | Motivo |
|---|---|
| Regras de Storage em produção | Storage não ativado — exige plano Blaze, aguardando aprovação do orientador |
| IAM do Google Cloud | exige acesso ao console; não inspecionável pelo código |
| MFA das contas administrativas | configuração de conta Google, fora do repositório |
| Backups do Firestore | não configurados; exigem Blaze |
| DAST / pentest | não há ambiente publicado |

---

## Riscos residuais

Mesmo depois de corrigir tudo acima, permanecem:

- **Engenharia reversa do APK.** Toda lógica no cliente é inspecionável. É por isso que a autoridade fica nas regras e no backend.
- **Conta comprometida.** Senha vazada dá acesso aos dados daquele usuário. MFA reduz; não elimina.
- **Dispositivo comprometido.** Root ou malware com privilégio contornam qualquer proteção do aplicativo.
- **Dependência do Firebase.** Uma falha no provedor é uma falha do sistema.
- **App Check não é autenticação.** Um atacante determinado obtém um token válido de um dispositivo real.

Nenhum sistema é totalmente seguro. O objetivo desta auditoria é reduzir a superfície de ataque e limitar o impacto de um comprometimento — não eliminar o risco.

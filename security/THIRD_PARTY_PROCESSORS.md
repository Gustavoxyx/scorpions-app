# Terceiros e subcontratados

Resposta às FASES 39 e 40. Quem recebe dado deste sistema, qual dado, para quê,
e onde fica.

Data: 5 de outubro de 2026.

## O inventário completo

Começa com a notícia boa, que é curta: **há um único terceiro.**

| Terceiro | Serviços usados |
|---|---|
| **Google LLC** (Firebase / Google Cloud) | Authentication, Firestore, Cloud Storage, App Check |

E a lista do que **não** é usado, porque isso é tão informativo quanto:

| | Situação |
|---|---|
| Serviço externo de IA (OpenAI, Gemini, Replicate, Hugging Face Inference) | ⚪ **nenhum.** Nenhuma imagem de usuário sai do Google Cloud |
| Meshy ou qualquer gerador 3D | ⚪ nenhum. Não há modelo 3D no projeto |
| Analytics (Firebase Analytics, Amplitude, Mixpanel) | ⚪ nenhum instalado. `analyticsEnabled` nasce falso e não há SDK por trás |
| Crash reporting (Crashlytics, Sentry) | ⚪ nenhum |
| Serviço de e-mail transacional | ⚪ nenhum — a recuperação de senha é do Firebase Auth |
| Mapas | ⚪ nenhum. Não há coleta de localização |
| CDN própria | ⚪ nenhuma |
| Publicidade | ⚪ nenhuma |

Verificado por leitura do `pubspec.yaml` (13 dependências, todas listadas na
auditoria de otimização) e por varredura de chamadas de rede em `lib/` — que não
encontrou uma única URL além das dos SDKs do Firebase.

## Google / Firebase, serviço por serviço

### Firebase Authentication

| | |
|---|---|
| Dado recebido | e-mail, senha (que ele guarda como hash scrypt), carimbos de criação e último acesso |
| Finalidade | autenticar o usuário e permitir recuperação de senha |
| Necessário? | **sim.** Sem identidade não há como isolar os dados de cada pessoa |
| Localização | 🔴 **não tem seleção de região.** O Google processa em infraestrutura global |
| Retenção | enquanto a conta existir |
| Segurança | hash específico para senha, com sal e fator de custo |
| Transferência internacional | **sim** — ver abaixo |

### Cloud Firestore

| | |
|---|---|
| Dado recebido | perfil (`uid`, e-mail, nome, papel), identificações, catálogo público |
| Finalidade | armazenar o que o aplicativo mostra |
| Localização | 🟢 `southamerica-east1` (São Paulo) |
| Retenção | indefinida hoje — ver `RETENTION_POLICY.md` |
| Segurança | cifrado em repouso com chave gerenciada; acesso por Security Rules |

### Cloud Storage

| | |
|---|---|
| Dado recebido | as fotografias (original, processada, miniatura) — **o dado mais sensível do sistema** |
| Finalidade | guardar a imagem que será analisada e exibida no histórico |
| Localização | 🟢 `southamerica-east1` (São Paulo) |
| Retenção | indefinida hoje |
| Segurança | privado por dono; cifrado em repouso; nenhum caminho público para imagem de usuário |
| Minimização aplicada | 🟢 **EXIF e GPS removidos no aparelho, antes do envio.** A coordenada de onde a foto foi tirada não chega aqui |

### Firebase App Check

| | |
|---|---|
| Dado recebido | atestado de integridade da instalação, via Play Integrity (Android) e App Attest (iOS) |
| Finalidade | reduzir abuso de cota e raspagem por script |
| Dado pessoal? | o atestado identifica a **instalação**, não a pessoa. Mas o Play Integrity envolve a conta Google do aparelho no lado do Google |
| Necessário? | não é indispensável; é camada adicional. Não autentica nem autoriza nada |

## O que o Google vê sem a gente enviar

Esta seção existe porque omiti-la daria uma impressão falsa de minimização.

| Dado | Como ele chega lá |
|---|---|
| **Endereço IP** | de toda requisição, inevitavelmente. O aplicativo não o coleta nem o envia; o Google o vê na borda da rede |
| **Metadados de requisição** | horário, tamanho, endpoint, nos logs de plataforma dele |
| **Agente de usuário / plataforma** | idem |

Isso é tratamento de dado pessoal que acontece **por usarmos a plataforma**, não
por escolha do código. Não é evitável sem trocar de infraestrutura, e está aqui
declarado em vez de escondido.

## Transferência internacional

Firestore e Storage ficam em São Paulo. **Firebase Authentication não oferece
escolha de região**, e os logs de plataforma do Google também não.

Então há transferência internacional de dado pessoal — e-mail, IP — para fora do
Brasil. Isso cai nos Arts. 33 a 36 da LGPD.

O Google oferece cláusulas contratuais padrão e um Adendo de Processamento de
Dados nos termos do Firebase. **Se isso é suficiente para este caso é questão
jurídica, não técnica**, e precisa de validação da UTFPR e/ou do responsável
jurídico competente. Não invento a conclusão.

## Papéis

A FASE 51 é explícita: usar o Google não transfere a responsabilidade legal.

| Papel | Quem |
|---|---|
| **Operador** (processador) | Google LLC — processa conforme instruções, nos termos do Firebase |
| **Controlador** | 🔴 **não definido.** Pode ser o Gustavo, pode ser a UTFPR, podem ser os dois em conjunto |
| **Encarregado (DPO)** | 🔴 não definido |

A segunda e a terceira linhas não são lacunas de código. Dependem de a UTFPR
dizer se um TCC que processa dado de terceiros é tratamento institucional. Está
em `PRIVACY.md` como pendência formal.

## Regra para o que vier depois

Antes de qualquer terceiro novo — e o candidato mais provável é um serviço
externo de inferência —, responder por escrito:

1. qual dado exatamente ele recebe (e por que não pode ser menos);
2. ele usa esse dado para treinar modelos dele?
3. por quanto tempo guarda?
4. em que país?
5. é possível exigir exclusão?
6. que contrato se aplica?
7. **o aplicativo pode evitar mandar a imagem e mandar só uma medida derivada?**

A pergunta 7 é a mais produtiva e a mais esquecida. Em geral a resposta é sim, e
aí o terceiro deixa de receber dado pessoal.

E a arquitetura já está preparada para a regra do 61.18: é o **backend** que
falaria com o serviço externo, nunca o aplicativo, com a chave em variável de
ambiente do servidor. O aplicativo não tem — nem deve ter — chave de terceiro
nenhuma.

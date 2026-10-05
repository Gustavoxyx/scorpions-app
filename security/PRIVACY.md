# Privacidade e LGPD

Resposta às FASES 37, 51 e 52. O que está implementado, o que falta, e o que
precisa de validação jurídica.

Data: 5 de outubro de 2026.

> **Este documento não é parecer jurídico, e não é uma política de privacidade
> publicável.** É o levantamento técnico que serve de insumo para uma. A
> definição formal de controlador, operador e encarregado, a base legal de cada
> tratamento e o texto a ser mostrado ao usuário precisam de validação da UTFPR
> e/ou do responsável jurídico competente antes de produção.

## Privacidade desde o projeto: o que já está no código

Estes não são planos — são decisões já tomadas e verificáveis.

| Princípio | Como aparece no código |
|---|---|
| **Minimização** | uma única permissão (`CAMERA`), e marcada `required="false"`. Sem localização, sem identificador de aparelho, sem contatos, sem telemetria |
| **Minimização, de novo** | 🟢 **EXIF e GPS removidos no aparelho, antes do envio.** A coordenada de onde a foto foi tirada **não sai do telefone** |
| **Finalidade** | cada campo de `users/{uid}` e de `identifications/{id}` tem finalidade escrita em `DATA_MAP.md` |
| **Segurança** | Security Rules por dono, cifra em repouso gerenciada, TLS, App Check, 94 testes de segurança |
| **Controle de acesso** | o usuário A não alcança nada do usuário B — verificado por 60 testes contra o emulador |
| **Opt-in** | `analyticsEnabled` nasce **falso**, e não há SDK de analytics instalado para ligar |
| **Não treinar sem consentimento** | nenhuma foto de usuário entra em treinamento. A Fase 5 decidiu usar bancos públicos (iNaturalist/GBIF) justamente para que o modelo inicial não dependa de foto de ninguém |
| **Registros limpos** | `AppLog` **quebra o aplicativo em depuração** se alguém tentar registrar e-mail, token, `uid`, caminho ou imagem. A proibição não depende de disciplina |
| **Dados locais contidos** | cache com teto de 40 MB, limpo no logout, excluído de backup e de transferência de aparelho |

A linha do EXIF merece destaque: é minimização aplicada no único ponto em que
ainda era possível. Depois do envio, nada downstream poderia desfazer.

## Direitos do titular (Art. 18) — o estado real

| Direito | Situação |
|---|---|
| **Confirmação e acesso** (I, II) | 🟡 parcial. O usuário vê o próprio perfil e histórico no aplicativo, mas não há uma visão "todos os meus dados" |
| **Correção** (III) | 🟡 parcial. Dá para editar o nome; o e-mail, não |
| **Anonimização, bloqueio ou eliminação** de dado desnecessário (IV) | 🔴 **não existe** |
| **Portabilidade** (V) | 🔴 **não existe.** Nada exporta os dados do titular |
| **Eliminação** dos dados tratados com consentimento (VI) | 🔴 **não existe.** É o HIGH-2 |
| **Informação sobre compartilhamento** (VII) | 🟡 o inventário existe em `THIRD_PARTY_PROCESSORS.md`, mas não é mostrado ao usuário |
| **Informação sobre não consentir** (VIII) | 🔴 não há tela de consentimento |
| **Revogação do consentimento** (IX) | 🔴 não há consentimento registrado para revogar |

**Cinco dos nove direitos não têm caminho nenhum hoje.** O mais grave é o VI: o
titular não consegue apagar o que é dele, de forma alguma — nem pelo aplicativo,
nem pedindo, porque não há a quem pedir.

### O que fecha a maior parte disso

Dois endpoints no backend que **já existe**, usando o Admin SDK:

```
DELETE /v1/me      ─►  apaga, em cascata:
                        as imagens no Storage (users/{uid}/**)
                        os documentos em identifications onde userId == uid
                        o documento users/{uid}
                        a conta no Firebase Authentication

GET    /v1/me/data ─►  devolve um JSON com perfil + identificações
                        (portabilidade, Art. 18, V)
```

Duas exigências que não são negociáveis:

1. **reautenticação antes de apagar** (MEDIUM-5). Exclusão de conta é a operação
   irreversível por definição; um token roubado não pode bastar;
2. **ordem da cascata: imagens primeiro, conta por último.** Se a conta for
   apagada primeiro e a cascata falhar no meio, sobram imagens órfãs — dado
   pessoal sem dono e sem regra que o proteja. Pior que antes de começar.

Isso **não depende do plano Blaze**, e é a razão de recomendar o backend em vez
de uma Cloud Function.

## Bases legais, para validação

Proposta técnica. Quem decide é o responsável jurídico.

| Tratamento | Base provável (Art. 7) |
|---|---|
| E-mail e senha para autenticar | execução de contrato (V) — sem conta não há serviço |
| Nome para exibição | 🟡 consentimento, ou legítimo interesse. É o campo cuja necessidade é mais discutível |
| Foto para identificar a espécie | execução de contrato (V) — é o serviço pedido |
| Guardar a foto depois do resultado | 🔴 **a mais frágil.** Terminada a identificação, qual é a finalidade? Guardar "para treinar depois" exige consentimento específico |
| Histórico de identificações | execução de contrato (V) — é funcionalidade pedida |
| Treinar modelo com foto de usuário | consentimento específico e separado (I), revogável. **Não implementado, e não deve ser até existir** |

A quarta linha é a que mais pede decisão: hoje a foto fica indefinidamente sem
base legal clara para a retenção. A proposta em `RETENTION_POLICY.md` são 12
meses, com justificativa.

## Papéis — pendência institucional

| Papel | Quem |
|---|---|
| Operador | Google LLC |
| **Controlador** | 🔴 **não definido** — Gustavo, UTFPR, ou os dois |
| **Encarregado (DPO)** | 🔴 não definido |

A FASE 51 pede que isto seja sinalizado, e está sinalizado: **se o projeto é
desenvolvido na UTFPR e vai processar dados de pessoas que não o autor, a
instituição precisa dizer se isso é tratamento institucional.** Disso dependem o
contrato, a política publicada e quem responde por um incidente.

Também precisa de validação: a transferência internacional de dado pessoal
causada pelo Firebase Authentication não ter seleção de região (Arts. 33 a 36) —
ver `THIRD_PARTY_PROCESSORS.md`.

## RIPD — Relatório de Impacto

Um RIPD completo **não** é produzido aqui. O que existe é a matéria-prima:

| Seção de um RIPD | Documento |
|---|---|
| Descrição do tratamento | `DATA_MAP.md` |
| Inventário de dados | `DATA_MAP.md` |
| Fluxo de dados | `DATA_MAP.md` |
| Riscos | `THREAT_MODEL.md`, `SECURITY_AUDIT.md` |
| Medidas técnicas | `SECURITY_AUDIT.md`, `CRYPTO_AUDIT.md` |
| Subcontratados | `THIRD_PARTY_PROCESSORS.md` |
| Retenção | `RETENTION_POLICY.md` |
| Resposta a incidente | `INCIDENT_RESPONSE.md` |
| **Avaliação de necessidade e proporcionalidade** | 🔴 falta — é juízo, não levantamento |
| **Medidas de mitigação aprovadas pelo controlador** | 🔴 falta — depende de haver controlador definido |

Se o projeto for a produção com usuários reais, há argumento para um RIPD ser
necessário: trata imagem (dado que pode revelar local de residência) de
titulares, em escala indeterminada, com apoio de decisão automatizada por IA. **A
decisão sobre a necessidade é jurídica.**

## Antes de qualquer usuário real

Em ordem de bloqueio:

| | O que | Quem |
|---|---|---|
| 1 | **Exclusão de conta** (Art. 18, VI) | implementável no backend que já existe |
| 2 | **Política de privacidade** publicada, com tela de aceite | precisa de validação jurídica |
| 3 | **Exportação de dados** (Art. 18, V) | mesmo caminho do item 1 |
| 4 | **Prazos de retenção** em vigor | ver `RETENTION_POLICY.md` |
| 5 | **Controlador e encarregado** definidos | **UTFPR** |
| 6 | Verificação de e-mail (MEDIUM-3) | implementável |
| 7 | Audit log (LOW-4) | implementável |

**Nenhum destes bloqueia o TCC**, que é demonstração com dados do próprio autor.
Todos bloqueiam uso por terceiros. A diferença entre as duas situações é o ponto
deste documento, e está escrita para que ninguém a confunda depois.

## O que não se pode afirmar

Em especial, nunca:

- *"a LGPD está garantida"* — conformidade não é estado que código demonstre;
- *"não há possibilidade de vazamento"*;
- *"o proprietário não tem responsabilidade"*;
- *"o sistema está 100% seguro."*

O que se pode afirmar, e está demonstrado nestes documentos: quais controles
técnicos existem, quais testes foram executados e com que resultado, quais
riscos foram reduzidos, quais permanecem, e quais pontos precisam de revisão
profissional e jurídica.

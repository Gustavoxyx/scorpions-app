# Política de retenção

Resposta à FASE 38. Por quanto tempo cada categoria de dado fica, o que
acontece quando o prazo termina, e o que **hoje não tem prazo nenhum**.

Data: 5 de outubro de 2026.

## O estado atual, sem rodeio

**Nenhuma política de retenção está em vigor.** Foto, identificação e conta
ficam para sempre — por omissão, não por decisão. Nada no sistema apaga nada.

Isso é o oposto do que o §38 pede (*"Não guardar tudo para sempre"*) e contraria
os princípios de necessidade e finalidade da LGPD. É registrado aqui como
pendência, não descrito como se já estivesse resolvido.

O que segue é a política **proposta**, com prazo e justificativa para cada
categoria, mais o que falta existir para que ela possa ser aplicada.

## Prazos propostos

| Categoria | Prazo | No fim do prazo | Justificativa |
|---|---|---|---|
| **Conta** (`users/{uid}`) | enquanto houver uso; 24 meses sem acesso | avisar por e-mail, e excluir 30 dias depois | uma conta abandonada é dado pessoal guardado sem finalidade |
| **Fotografia original** | 12 meses | excluir do Storage | é o registro científico de maior valor e o dado de maior risco. 12 meses cobrem o ciclo de reprocessamento por um modelo melhor |
| **Fotografia processada** | 12 meses | excluir | derivada do original; sem ele perde a razão de ser |
| **Miniatura** | junto da identificação | excluir | é a ilustração do histórico |
| **Identificação** (metadados) | 36 meses | **anonimizar**, não excluir | o registro sem `userId`, sem `imageUrl` e sem data exata ainda serve para medir acurácia do modelo e para a estatística do TCC. Com esses campos, é dado pessoal |
| **Registro técnico** (log) | 90 dias | excluir | prazo para investigar incidente; depois disso o log não serve a nada |
| **Audit log** | 24 meses | excluir | precisa sobreviver ao tempo de descobrir um abuso. Não existe ainda (LOW-4) |
| **Backup** | 30 dias, em janela móvel | sobrescrever | não existe ainda |
| **Dado de treinamento** | enquanto o consentimento valer | excluir ao revogar | não existe ainda |

### Por que anonimizar a identificação em vez de excluir

É a única categoria em que exclusão destruiria algo legítimo. A informação
*"uma foto de qualidade X foi classificada como Tityus serrulatus com
confiança Y, e um especialista corrigiu para Z"* é o que mede se o modelo
funciona. Sem `userId`, sem URL de imagem e com a data arredondada para o mês,
ela deixa de apontar para uma pessoa.

A distinção importa e o §38 a oferece: *"delete ou anonymize, conforme a
finalidade"*.

### Por que 12 meses para a foto, e não mais

A tentação é guardar indefinidamente "para treinar o modelo depois". O §15
fecha esse caminho: foto de usuário não entra em treinamento sem consentimento
específico. Então guardar além do uso do próprio titular não tem finalidade — é
só risco acumulado.

## O que falta existir para aplicar isto

| | Falta | Por quê |
|---|---|---|
| 1 | ~~Exclusão de conta em cascata~~ | 🟢 **existe** — `DELETE /v1/me`. É o mecanismo que o executor de prazos vai reutilizar |
| 2 | **Um executor** — algo que rode periodicamente e apague o que venceu | uma política que ninguém aplica é um texto. Exige Cloud Scheduler + Function, logo **Blaze** |
| 3 | **Marca de último acesso** em `users/{uid}` | `updatedAt` existe, mas é escrito em qualquer atualização, não só em acesso. Sem um campo próprio, "24 meses sem uso" não é calculável |
| 4 | ~~Exclusão em cascata do Storage~~ | 🟢 **existe**, dentro da mesma cascata, e roda **primeiro** — justamente para não sobrar imagem órfã |
| 5 | ~~Registro de quando cada exclusão aconteceu~~ | 🟢 **existe** — entrada `account.deleted` no audit log, com contagens e horário do servidor |

Restam os itens 2 e 3. O 3 é pequeno. O 2 — o executor periódico — depende do
plano Blaze, que ainda não foi aprovado; sem ele, **nenhum prazo desta política
está em vigor**: o que existe é a exclusão a pedido do titular, não a exclusão
por decurso de prazo.

## Backups: a outra metade do problema

**Não existe backup nenhum.** O Firestore no plano Spark não oferece exportação
agendada.

Isso tem duas faces, e as duas precisam ser ditas:

- 🟢 não há backup público nem mal protegido, porque não há backup — o §36 do
  briefing de segurança fica atendido por vacuidade;
- 🔴 **não há recuperação possível.** Uma exclusão acidental, um seed rodado
  errado ou uma regra publicada com defeito que apague dados são irreversíveis.
  Nenhuma retenção protege do que já foi perdido.

Quando backups existirem, eles entram nesta política: **backup também é dado**,
e um backup de 2 anos atrás esvazia um prazo de retenção de 12 meses.

## Ordem de execução recomendada

1. ~~Exclusão de conta~~ — 🟢 feito.
2. ~~Exportação de dados~~ — 🟢 feito.
3. Campo de último acesso, que é uma linha.
4. Executor periódico dos prazos — depende de Blaze.
5. Backups — depende de Blaze.

O terceiro não depende de decisão nenhuma além de tempo.

## O que esta política não é

Não é parecer jurídico. Os prazos acima são propostas técnicas com justificativa
escrita, para serem **validadas** pela UTFPR e/ou pelo responsável jurídico
competente — que podem ter obrigações de guarda que este documento não conhece.

E, enquanto os itens acima não existirem, a frase verdadeira sobre este sistema
é: *os dados são guardados por tempo indeterminado*. É o que está no código.

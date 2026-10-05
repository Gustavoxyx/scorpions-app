# Plano de resposta a incidentes

Resposta à FASE 50. O que fazer quando algo acontece, escrito **antes** de
acontecer.

Data: 5 de outubro de 2026.

## Para que serve um plano num projeto de uma pessoa

Às duas da manhã, com a adrenalina no lugar do raciocínio, ninguém monta o passo
a passo. A tentação nesse momento é sempre a mesma — *apagar o que vazou e
seguir* — e ela destrói exatamente a evidência de que se vai precisar.

Este documento é curto de propósito. Um plano que ninguém lê não é plano.

## A sequência

```
DETECTAR  ─►  CONFIRMAR  ─►  CONTER  ─►  PRESERVAR
                                             │
POSTMORTEM ◄─ RECUPERAR ◄─ COMUNICAR ◄─ INVESTIGAR
                                             │
                                          CORRIGIR
```

**A regra que não se quebra: não apagar nada durante um incidente.** Log,
documento suspeito, conta usada no ataque — nada. O impulso de "limpar" é o que
torna o incidente impossível de entender e de relatar.

## Passo a passo

### 1. Detectar

Hoje a detecção é quase toda manual, e isso precisa estar escrito. O que existe:

| Sinal | De onde vem |
|---|---|
| Pico de uso ou cota estourada | e-mail do Firebase, painel de uso |
| Erro em massa | logs do provedor do backend |
| Falha de regra | Firebase Console → Firestore → Uso |
| Segredo commitado | 🟢 job `segredos` do CI (Gitleaks) — **o único automático** |
| Acesso indevido a dado de usuário | 🟡 **parcialmente detectável.** O audit log registra o que passa pelo backend — exclusão e exportação de conta, cota estourada, acesso à fila de revisão. Leitura direta pelo Firestore, permitida pelas regras a um admin, **não** passa por ele |
| Abuso de cota | 🟢 entrada `quota.exceeded` no audit log |

A penúltima linha continua sendo a mais importante: um acesso administrativo
direto ao banco ainda não deixa rastro próprio. O que mudou é que as operações
críticas agora deixam — e que o registro não pode ser lido nem apagado por
cliente nenhum, inclusive admin.

### 2. Confirmar

Antes de agir, responder: **é incidente ou é defeito?**

Um erro 500 em massa por configuração errada não é vazamento. Tratar defeito
como incidente queima tempo; tratar incidente como defeito perde a janela.

A pergunta que separa: **algum dado saiu, ou alguém alcançou algo que não
deveria?** Se sim, é incidente.

### 3. Conter

Pela natureza do que aconteceu:

| Se | Fazer |
|---|---|
| **Service account vazou** | apagar a chave no console **agora**. O backend cai. Deixar cair — ver `CRYPTO_AUDIT.md` 61.8 |
| **Regra de segurança aberta por engano** | publicar a regra correta imediatamente: `firebase deploy --only firestore:rules` |
| **Conta de usuário comprometida** | Firebase Console → Authentication → desabilitar a conta. Isso revoga os tokens, porque o backend usa `check_revoked=True` |
| **Conta administrativa comprometida** | trocar a senha da conta Google, revogar as sessões, e **só depois** olhar o resto. Ela está acima de todas as regras |
| **Abuso de cota em andamento** | desabilitar a conta de origem; se não houver uma só, considerar publicar uma regra temporária que negue escrita |
| **Backend comprometido** | derrubar o serviço no provedor. O aplicativo continua funcionando para leitura — as regras não dependem do backend |

Conter vem antes de entender. Um sistema no ar durante um vazamento ativo
continua vazando.

### 4. Preservar a evidência

Antes de corrigir qualquer coisa:

1. **exportar os logs** do período — Google Cloud → Logging, e os logs do
   provedor do backend. Salvar fora do sistema afetado;
2. **anotar o horário** em que cada coisa foi notada e feita, com fuso. A linha
   do tempo é o que permite reconstruir depois;
3. **não apagar** a conta usada no ataque, o documento adulterado ou a chave
   vazada — ela já foi revogada no passo 3, e revogada é diferente de apagada;
4. **tirar captura de tela** do que estiver anormal no console. Painéis mudam.

### 5. Investigar

| Pergunta | Onde olhar |
|---|---|
| Que operações aconteceram, e quando? | Google Cloud Logging |
| Que dado foi alcançado? | padrão de leitura nos logs do Firestore e do Storage |
| Era uma conta, ou várias? | `uid` nos logs |
| Veio de fora ou de dentro? | IP e tipo de credencial |
| A causa foi regra, código, credencial ou configuração? | comparar com o commit em vigor |

### 6. Corrigir a causa, não o sintoma

Fechar a brecha é obrigatório. **E escrever o teste que a pegaria** também — os
testes de segurança deste projeto existem para que a mesma falha não volte.

Um incidente sem teste novo é um incidente que pode acontecer duas vezes.

### 7. Comunicar

| A quem | Quando |
|---|---|
| **Orientador / UTFPR** | em qualquer incidente que envolva dado de terceiro. Imediatamente, não depois de resolver |
| **Titulares afetados** | se dado pessoal foi exposto. A LGPD (Art. 48) exige comunicação em prazo razoável |
| **ANPD** | 🔴 **decisão jurídica, não técnica.** O Art. 48 obriga a comunicar incidente com risco relevante. Quem avalia "relevante" é o responsável jurídico, não eu nem este documento |

Não inventar conclusão jurídica aqui. O que este plano manda é **escalar**, e
rápido.

### 8. Recuperar

🔴 **Não há backup.** Se dado foi perdido ou corrompido, ele não volta — ver
`RETENTION_POLICY.md`.

É a lacuna mais séria deste plano, e é honesto dizer que a etapa de recuperação,
hoje, pode não ter conteúdo.

### 9. Postmortem

Escrever, mesmo que ninguém mais vá ler. Quatro perguntas:

1. o que aconteceu, na linha do tempo;
2. por que aconteceu — a causa, não o sintoma;
3. por que não foi detectado antes;
4. o que mudou para não repetir: código, regra, teste, processo.

**Sem procurar culpado.** Num projeto de uma pessoa, o culpado é sempre o mesmo,
e isso torna o exercício inútil se for o objetivo. O objetivo é a pergunta 3.

## Os três contatos

| | |
|---|---|
| Responsável técnico | Gustavo (dono do projeto Firebase, único com acesso ao console) |
| Orientador / UTFPR | **preencher** |
| Suporte do Firebase | console → Suporte; plano Spark tem suporte limitado |

A segunda linha está em branco e deve ser preenchida **antes** de haver usuários
reais. Procurar o contato do orientador durante um incidente é desperdiçar a
primeira hora, que é a que mais importa.

## O que falta para este plano funcionar de verdade

| | Falta | Efeito |
|---|---|---|
| 1 | Audit log cobrindo **leitura administrativa direta** | o registro existe para o que passa pelo backend; a leitura pelo console ou pelas regras não é coberta |
| 2 | **Alertas** (FASE 49) | a detecção é olhar o painel por acaso |
| 3 | **Backup** | o passo 8 pode não ter o que fazer |
| 4 | **MFA na conta administrativa** (LOW-3) | o pior cenário (T-4 no modelo de ameaças) continua a uma senha de distância |
| 5 | Contato do orientador preenchido | uma linha de texto |

O item 5 custa um minuto. O item 4 custa cinco, no console, e é o que mais reduz
a probabilidade de precisar deste documento.

# O limite de criação é imposto pelas regras, com contador escrito pelo cliente

Quantas sessões uma conta abre por dia é controlado **nas regras do Firestore**:
cada criação vai num lote com o incremento de um contador diário, e a regra só
aceita se o contador subir exatamente um, por aquela sessão, sem passar do
limite. O contador é escrito pelo próprio cliente.

Parece errado — o cliente não é confiável, e é ele quem grava o número. O que o
torna seguro é que a regra confere a transição, e não o valor: o contador só
pode subir de um em um, não pode ser apagado, e cada incremento fica amarrado a
uma única sessão.

## Considered Options

- **Criar a sessão pelo backend**, que cobraria a cota antes de gravar. É o
  desenho mais limpo. Recusado agora porque o backend não está publicado, e
  condicionar a criação a ele deixaria o aplicativo sem conseguir abrir sessão
  nenhuma em produção.
- **Só App Check.** Reduz contas criadas por script, mas não limita uma conta
  legítima em laço, e a exigência ainda não está ligada no console.

## Consequences

Regras e aplicativo passam a mudar juntos: uma versão do aplicativo que não
envia o contador não cria sessão contra as regras novas, e o contrário também.

Quando o backend estiver publicado, mover a criação para ele continua sendo a
evolução natural, e este contador sai.

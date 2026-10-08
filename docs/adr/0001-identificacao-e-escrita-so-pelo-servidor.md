# A identificação é escrita só pelo servidor

Espécie, confiança, alternativas, motivo de rejeição, versão do modelo, dados de
revisão humana e o estado da sessão depois de criada **não podem ser gravados
pelo aplicativo**. As regras do Firestore enumeram o que o cliente pode escrever
e recusam todo o resto; quem grava a identificação é o backend, com o Admin SDK.

A razão é que o aplicativo pode ser adulterado. Uma confiança forjada pelo
cliente contaminaria as métricas, entraria na fila de revisão humana como se
fosse saída do modelo e alimentaria um retreinamento com rótulo falso — e não
haveria como distinguir depois o que o modelo disse do que alguém digitou.

## Consequences

**Inferência no aparelho não cabe neste desenho como está.** Um modelo rodando
no celular produz a identificação no cliente, que é justamente quem não pode
gravá-la. Se a fase da IA escolher inferência no aparelho, esta decisão precisa
ser revista junto: ou o resultado local é tratado como rascunho não confiável e
confirmado no servidor, ou o modelo de confiança muda. Inferência no servidor
encaixa sem alteração.

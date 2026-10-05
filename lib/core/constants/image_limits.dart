/// Limites do pipeline de imagem, num lugar só (briefing Fase 4, §4 e §21).
///
/// Nada aqui é arbitrário: cada número tem um motivo escrito ao lado. Espalhar
/// esses valores pelo código foi o que o briefing pediu para evitar, e a razão
/// é concreta — o teto de tamanho precisa bater com o das Storage Rules, e um
/// número solto num arquivo de tela é exatamente o que sai de sincronia sem
/// ninguém perceber.
abstract final class ImageLimits {
  // -- Tamanho em bytes -------------------------------------------------------

  /// Teto de envio. **Espelha `firebase/storage.rules`.**
  ///
  /// Duplicado de propósito: validar aqui evita gastar a rede do usuário com
  /// um envio que o servidor recusaria de qualquer forma. A regra continua
  /// sendo a autoridade — esta constante é cortesia, não segurança.
  static const int maxBytes = 8 * 1024 * 1024;

  /// Piso. Uma fotografia de escorpião utilizável não cabe em 8 KB; abaixo
  /// disso é ícone, avatar ou arquivo truncado.
  static const int minBytes = 8 * 1024;

  // -- Dimensões --------------------------------------------------------------

  /// Menor lado aceitável.
  ///
  /// Abaixo de 480px os caracteres que distinguem as espécies — granulação do
  /// tegumento, proporção das pinças, segmentos da cauda — deixam de estar
  /// presentes na imagem. Aceitar seria prometer uma análise impossível.
  static const int minDimension = 480;

  /// Maior lado aceitável antes de processar.
  ///
  /// Uma imagem de 8000px decodificada em RGBA ocupa ~256 MB de heap. Em um
  /// aparelho modesto isso é o encerramento do processo, não uma exceção que
  /// dê para tratar. Recusamos antes de decodificar.
  static const int maxDimension = 6000;

  // -- Processamento ----------------------------------------------------------

  /// Maior lado da imagem processada, que é a que vai para a análise.
  ///
  /// Classificadores de imagem trabalham em entradas bem menores (tipicamente
  /// 224 a 384px). 1600 preserva folga para recorte futuro sem carregar peso
  /// que ninguém vai usar.
  static const int processedMaxDimension = 1600;
  static const int processedQuality = 88;

  /// Qualidade usada quando o original **precisa** ser reencodado — só
  /// acontece quando ele traz etiqueta de orientação, caso em que limpar os
  /// metadados sem reencodar deixaria a foto deitada. Alta de propósito: este
  /// arquivo é o registro científico, e é dele que um modelo melhor da Fase 5
  /// em diante vai querer reprocessar.
  static const int originalQuality = 95;

  /// Miniatura para as listas de histórico.
  static const int thumbnailMaxDimension = 320;
  static const int thumbnailQuality = 78;

  /// Lado da imagem reduzida usada para **medir** qualidade.
  ///
  /// As métricas (brilho, contraste, nitidez) são estatísticas da imagem
  /// inteira e sobrevivem à redução. Medir em 256px em vez de 1600px é cerca
  /// de 40x menos pixels — a diferença entre instantâneo e travar a interface
  /// num aparelho de entrada.
  static const int analysisDimension = 256;

  // -- Qualidade --------------------------------------------------------------

  /// Faixa de luminância média aceitável, de 0 a 1.
  ///
  /// Fora dela a foto está escura ou estourada demais para distinguir cor e
  /// textura — os dois sinais mais usados na identificação.
  static const double minBrightness = 0.18;
  static const double maxBrightness = 0.80;

  /// Desvio padrão mínimo da luminância. Mede contraste: uma foto de parede
  /// branca ou de escuridão total tem desvio próximo de zero.
  static const double minContrast = 0.055;

  /// Nitidez mínima, pela variância do laplaciano normalizada.
  ///
  /// Os valores foram **medidos**, não estimados. Sobre cenas sintéticas com
  /// textura, reduzidas a [analysisDimension] como o serviço faz:
  ///
  /// | cena                    | nitidez  |
  /// |-------------------------|----------|
  /// | nítida                  | 0,0055   |
  /// | desfoque gaussiano r=2  | 0,0010   |
  /// | desfoque gaussiano r=6  | 0,00003  |
  ///
  /// O piso fica em 0,0015: acima do desfoque leve, bem abaixo da nítida.
  ///
  /// RESSALVA HONESTA: a calibração é sintética. Fotografias reais de campo
  /// têm mais alta frequência que estas cenas, então a tendência é medirem
  /// acima — o erro provável é deixar passar borrão, não barrar foto boa, que
  /// é o lado certo para errar. Recalibrar com fotos reais é tarefa da Fase 6.
  static const double minSharpness = 0.0015;

  /// Entre este valor e [minSharpness] a foto passa com aviso de foco mole.
  static const double warnSharpness = 0.0040;

  // -- Contenção de abuso (§21) -----------------------------------------------

  /// Identificações por usuário por dia.
  ///
  /// **Quem aplica este número é o servidor**, não este arquivo.
  ///
  /// O backend conta em `users/{uid}/quotas/{dia}`, dentro de uma transação,
  /// antes de cada análise (`backend/app/quota.py`), e a regra do Firestore
  /// nega escrita nesse caminho a todo cliente — senão bastaria zerar o próprio
  /// contador. O número de lá vem da variável `MAX_ANALYSES_PER_DAY`; este
  /// daqui é o **espelho**, para a tela poder dizer "restam N" sem inventar.
  ///
  /// Este comentário já mentiu duas vezes, e vale deixar o histórico: primeiro
  /// dizia que havia "um freio de cliente", e não havia; depois passou a dizer
  /// que ninguém aplicava o limite, o que foi verdade até o backend ganhar a
  /// cota. Comentário que descreve mecanismo é o primeiro a ficar para trás.
  ///
  /// Continua não havendo freio de cliente, e pelo mesmo motivo de antes: ele
  /// custaria uma consulta por envio e um cliente adulterado o ignoraria.
  ///
  /// Limite do que isto cobre: são **análises**, não envios ao Storage. Um
  /// cliente adulterado ainda pode enviar imagens sem pedir análise; o que
  /// limita isso é só o teto de [maxBytes] por arquivo.
  static const int maxIdentificationsPerDay = 60;

  /// Envios simultâneos. Acima disso a fila é do aparelho, não da rede.
  static const int maxConcurrentUploads = 2;
}

/// Ciclo de vida de uma identificação (brief §12).
///
/// # Por que isto existe antes da IA
/// Hoje a análise é síncrona e simulada: o resultado nasce pronto. Quando o
/// modelo real entrar (Fase 5), o processamento passa a ser assíncrono — o
/// aplicativo grava o documento, envia a imagem, e uma Cloud Function devolve
/// o resultado depois. Nesse mundo, [processing] é o estado inicial normal e a
/// tela precisa saber lidar com ele.
///
/// Criar o campo agora significa que os documentos gravados nesta fase já
/// nascem com o formato certo, e nenhuma migração de dados será necessária.
enum IdentificationStatus {
  /// Imagem enviada, resultado ainda não disponível.
  processing('processing'),

  /// Espécie estimada com confiança suficiente para ser apresentada.
  identified('identified'),

  /// Há uma estimativa, mas fraca. A tela mostra o resultado com ressalva.
  lowConfidence('low_confidence'),

  /// O sistema preferiu não responder. **Não é erro** — é uma decisão.
  rejected('rejected'),

  /// Falha técnica: upload, processamento ou infraestrutura.
  error('error');

  const IdentificationStatus(this.id);

  /// Valor persistido. Independente do nome do membro em Dart.
  final String id;

  /// Se `true`, existe uma espécie estimada para exibir.
  bool get hasPrediction =>
      this == IdentificationStatus.identified ||
      this == IdentificationStatus.lowConfidence;

  /// Se `true`, o resultado ainda pode mudar — a tela deve observar o
  /// documento em vez de tratá-lo como final.
  bool get isPending => this == IdentificationStatus.processing;

  String get label => switch (this) {
        IdentificationStatus.processing => 'Analisando',
        IdentificationStatus.identified => 'Identificado',
        IdentificationStatus.lowConfidence => 'Confiança baixa',
        IdentificationStatus.rejected => 'Não identificado',
        IdentificationStatus.error => 'Falha na análise',
      };

  /// Converte o valor vindo do banco. Desconhecido vira [error]: é melhor a
  /// tela mostrar "algo deu errado" do que fingir um resultado válido.
  static IdentificationStatus fromId(Object? raw) {
    if (raw is! String) return IdentificationStatus.error;
    for (final IdentificationStatus status in IdentificationStatus.values) {
      if (status.id == raw) return status;
    }
    return IdentificationStatus.error;
  }
}

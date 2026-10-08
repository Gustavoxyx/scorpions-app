import 'package:flutter/foundation.dart';

import 'capture_instruction.dart';
import 'captured_image.dart';
import 'image_quality.dart';
import 'processed_image.dart';

/// Uma das vistas de uma sessão.
///
/// Junta o que foi **pedido** ([instruction]) com o que foi **obtido** — a
/// captura, o que o pipeline mediu e o que foi enviado. Manter o pedido junto
/// do resultado é o que permite, mais tarde, responder "o usuário fotografou a
/// cauda quando pedimos a cauda?" — pergunta que o §38 vai precisar fazer para
/// justificar características, e que seria impossível se só guardássemos a
/// imagem.
@immutable
class SessionView {
  const SessionView({
    required this.instruction,
    required this.image,
    this.quality,
    this.processed,
    this.imageUrl,
    this.thumbnailUrl,
  });

  final ImageCaptureInstruction instruction;
  final CapturedImage image;

  /// Nulo quando a imagem é simulada — não há pixels para medir.
  final ImageQualityResult? quality;

  /// Nulo antes do processamento, e em modo simulado.
  final ProcessedImage? processed;

  final String? imageUrl;
  final String? thumbnailUrl;

  bool get isSimulated => image.isSimulated;

  /// Se esta vista tem conteúdo que um modelo poderia consumir.
  bool get isAnalysable => processed != null;

  SessionView copyWith({
    ImageQualityResult? quality,
    ProcessedImage? processed,
    String? imageUrl,
    String? thumbnailUrl,
  }) {
    return SessionView(
      instruction: instruction,
      image: image,
      quality: quality ?? this.quality,
      processed: processed ?? this.processed,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}

/// Situação da sessão. Espelha o `status` gravado no Firestore.
enum SessionStatus {
  /// Primeira foto aceita, segunda ainda não capturada.
  awaitingSecondView('awaiting_second_view'),

  /// As duas imagens existem e seguem para o servidor.
  submitting('submitting'),

  /// Enviadas; o resultado ainda não chegou.
  processing('processing'),

  identified('identified'),
  lowConfidence('low_confidence'),
  humanReview('human_review'),
  rejected('rejected'),
  error('error');

  const SessionStatus(this.id);

  final String id;
}

/// As duas fotografias de uma mesma identificação (§4).
///
/// # Por que não são duas identificações
/// Porque não são duas perguntas. São dois ângulos da **mesma** pergunta, e
/// tratá-las como registros independentes criaria dois históricos para um
/// evento, duas chances de resultado divergente e nenhum lugar onde a fusão
/// pudesse acontecer. O §4 é explícito.
///
/// # Por que a segunda é opcional
/// Porque a sessão existe antes dela. Entre a primeira e a segunda foto há uma
/// decisão humana — e, mais adiante, pode haver o caso de a segunda não ser
/// possível: o animal fugiu, a pessoa está em situação de risco, o aparelho
/// não focou. O §5 diz que uma imagem ruim não invalida automaticamente a
/// identificação se a outra tiver informação suficiente; uma imagem **ausente**
/// segue a mesma lógica. Quem decide é o pipeline, não a interface.
@immutable
class IdentificationSession {
  const IdentificationSession({
    required this.id,
    required this.userId,
    required this.primary,
    required this.status,
    required this.createdAt,
    this.secondary,
    this.updatedAt,
  });

  final String id;
  final String userId;

  final SessionView primary;
  final SessionView? secondary;

  final SessionStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get hasSecondView => secondary != null;

  /// As vistas existentes, na ordem de captura.
  List<SessionView> get views => <SessionView>[primary, ?secondary];

  /// As vistas que um modelo consegue consumir.
  List<SessionView> get analysableViews =>
      views.where((SessionView v) => v.isAnalysable).toList(growable: false);

  /// Qualidade do **conjunto** (§5).
  ///
  /// Não é a média das duas. É a melhor, e a escolha tem razão: a pergunta que
  /// importa é "existe informação suficiente para analisar?", e uma vista boa
  /// responde sim mesmo ao lado de uma ruim. A média puniria o par
  /// (excelente, sofrível) tanto quanto o par (medíocre, medíocre), que são
  /// situações diferentes — no primeiro há uma foto aproveitável, no segundo
  /// não há nenhuma.
  ///
  /// A vista ruim não é descartada: ela entra na fusão com peso menor, e a
  /// divergência entre as duas é medida à parte pela consistência cruzada.
  /// Aqui a pergunta é só se vale seguir.
  ImageQuality? get combinedQuality {
    final List<ImageQuality> medidas = views
        .map((SessionView v) => v.quality?.quality)
        .whereType<ImageQuality>()
        .toList(growable: false);

    if (medidas.isEmpty) return null;

    // `ImageQuality` é declarado do melhor para o pior, então o menor índice
    // é a melhor medida.
    return medidas.reduce(
      (ImageQuality a, ImageQuality b) => a.index <= b.index ? a : b,
    );
  }

  IdentificationSession copyWith({
    SessionView? primary,
    SessionView? secondary,
    SessionStatus? status,
    DateTime? updatedAt,
  }) {
    return IdentificationSession(
      id: id,
      userId: userId,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

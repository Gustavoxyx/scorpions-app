import 'package:flutter/foundation.dart';

/// Eventos estruturados do pipeline (briefing Fase 4, §27).
///
/// Enum e não texto livre: um evento com nome digitado à mão vira dois eventos
/// diferentes na primeira vez que alguém escrever `upload_complete` em vez de
/// `upload_completed`, e a contagem passa a mentir sem avisar.
enum AppEvent {
  imageSelected('image_selected'),
  imageValidationFailed('image_validation_failed'),
  imageQualityChecked('image_quality_checked'),
  imageProcessingStarted('image_processing_started'),
  imageProcessingCompleted('image_processing_completed'),
  uploadStarted('upload_started'),
  uploadCompleted('upload_completed'),
  uploadFailed('upload_failed'),
  uploadSkipped('upload_skipped'),
  identificationCreated('identification_created'),
  pipelineCancelled('pipeline_cancelled'),
  pipelineFailed('pipeline_failed');

  const AppEvent(this.id);

  final String id;
}

/// Registro de eventos.
///
/// # Hoje e amanhã
/// Hoje escreve no console de depuração e nada mais. Quando Crashlytics ou
/// Analytics entrarem, entram **aqui** — num lugar só, com a mesma trava de
/// conteúdo já aplicada.
///
/// # A trava (§27)
/// O briefing proíbe registrar senha, token, imagem e dado pessoal. Confiar em
/// disciplina para isso não funciona: basta um `data: {'email': email}` escrito
/// com pressa. Então a proibição é verificada em `assert` — em depuração, o
/// aplicativo **quebra** se alguém tentar. Em produção o assert some, mas o
/// código que teria disparado já foi corrigido antes de chegar lá.
abstract final class AppLog {
  /// Chaves que nunca podem ser registradas, mesmo que o valor pareça inócuo.
  static const Set<String> _proibidas = <String>{
    'password', 'senha', 'token', 'apikey', 'api_key', 'secret',
    'email', 'credential', 'authorization', 'bytes', 'image', 'photo',
    'foto', 'uid', 'userid', 'user_id', 'path', 'caminho', 'url',
  };

  static void event(AppEvent event, [Map<String, Object?> data = const <String, Object?>{}]) {
    assert(_verificar(event, data));
    if (!kDebugMode) return;

    final String detalhe = data.isEmpty
        ? ''
        : ' ${data.entries.map((MapEntry<String, Object?> e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('[Scorpions] ${event.id}$detalhe');
  }

  /// Roda apenas em depuração, dentro do `assert`.
  static bool _verificar(AppEvent event, Map<String, Object?> data) {
    for (final MapEntry<String, Object?> e in data.entries) {
      final String chave = e.key.toLowerCase().replaceAll(RegExp(r'[^a-z_]'), '');
      if (_proibidas.contains(chave)) {
        throw FlutterError(
          'AppLog: a chave "${e.key}" nao pode ser registrada (briefing §27).\n'
          'Evento: ${event.id}.\n'
          'Registre uma medida derivada — um tamanho, uma contagem, um codigo '
          '— em vez do conteudo.',
        );
      }
      final Object? v = e.value;
      if (v is Uint8List || v is List<int>) {
        throw FlutterError(
          'AppLog: tentativa de registrar bytes no evento ${event.id}. '
          'Imagem nunca vai para o log; registre o tamanho.',
        );
      }
      if (v is String && v.length > 120) {
        throw FlutterError(
          'AppLog: valor longo demais em "${e.key}" (${v.length} caracteres) '
          'no evento ${event.id}. Log guarda medida, nao conteudo.',
        );
      }
    }
    return true;
  }
}

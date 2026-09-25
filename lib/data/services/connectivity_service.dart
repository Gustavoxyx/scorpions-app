import 'package:connectivity_plus/connectivity_plus.dart';

/// Situação de rede, do ponto de vista do produto (briefing Fase 4, §19).
///
/// # A ressalva que precisa estar escrita
/// O que se consegue saber barato é se **existe uma interface de rede ativa**.
/// Isso não é o mesmo que ter internet: um Wi-Fi de cafeteria com portal de
/// login responde "conectado" e não entrega um byte.
///
/// Por isso este serviço é usado para **evitar** trabalho inútil — não iniciar
/// um envio quando o aparelho está claramente offline —, e nunca como prova de
/// que a operação vai funcionar. Quem dá o veredito final é a tentativa real,
/// traduzida por `FirebaseErrorMapper` em `FailureKind.network`.
abstract interface class ConnectivityService {
  /// `false` apenas quando **não há** interface ativa. `true` significa
  /// "provavelmente dá", não "com certeza dá".
  Future<bool> hasConnection();
}

class PlatformConnectivityService implements ConnectivityService {
  PlatformConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> hasConnection() async {
    try {
      final List<ConnectivityResult> r = await _connectivity.checkConnectivity();
      return r.any((ConnectivityResult c) => c != ConnectivityResult.none);
    } catch (_) {
      // Plataforma sem suporte ao plugin: assumir que há rede é a escolha
      // certa. O erro real aparece na tentativa, com mensagem melhor do que
      // um "você está offline" inventado por um plugin que não respondeu.
      return true;
    }
  }
}

/// Sempre conectado. Usada em teste e no modo simulado.
class AlwaysOnlineConnectivityService implements ConnectivityService {
  const AlwaysOnlineConnectivityService();

  @override
  Future<bool> hasConnection() async => true;
}

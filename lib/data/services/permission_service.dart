import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// O que o sistema respondeu sobre uma permissão (briefing Fase 4, §17).
enum PermissionState {
  granted,

  /// Negada desta vez. Perguntar de novo ainda faz sentido.
  denied,

  /// Negada de forma definitiva: o sistema não mostra mais o diálogo.
  /// A única saída é o usuário abrir os ajustes do aparelho.
  permanentlyDenied,

  /// Bloqueada por controle parental ou política do dispositivo. O usuário
  /// não consegue conceder nem pelos ajustes.
  restricted,

  /// A plataforma não tem esse conceito de permissão.
  notApplicable,
}

/// Permissões de câmera e galeria.
///
/// # Por que existe uma interface para algo tão simples
/// Porque as três plataformas discordam. No Android há permissão explícita; no
/// iOS há, com vocabulário diferente; **na web não há** — o navegador pede
/// sozinho, no momento do uso, e nenhum código nosso participa. Um
/// `permission_handler` chamado direto da tela responderia qualquer coisa na
/// web e produziria um cartão de "permissão negada" que não corresponde a nada.
abstract interface class PermissionService {
  Future<PermissionState> cameraStatus();
  Future<PermissionState> requestCamera();

  /// Abre os ajustes do sistema. Só faz sentido em [PermissionState.permanentlyDenied].
  Future<bool> openSettings();
}

class DevicePermissionService implements PermissionService {
  const DevicePermissionService();

  @override
  Future<PermissionState> cameraStatus() => _traduzir(ph.Permission.camera.status);

  @override
  Future<PermissionState> requestCamera() =>
      _traduzir(ph.Permission.camera.request());

  @override
  Future<bool> openSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  static Future<PermissionState> _traduzir(Future<ph.PermissionStatus> futuro) async {
    try {
      final ph.PermissionStatus s = await futuro;
      return switch (s) {
        ph.PermissionStatus.granted ||
        ph.PermissionStatus.limited ||
        ph.PermissionStatus.provisional =>
          PermissionState.granted,
        ph.PermissionStatus.permanentlyDenied => PermissionState.permanentlyDenied,
        ph.PermissionStatus.restricted => PermissionState.restricted,
        ph.PermissionStatus.denied => PermissionState.denied,
      };
    } catch (_) {
      // Plugin ausente (desktop, teste): não há permissão a gerenciar.
      return PermissionState.notApplicable;
    }
  }
}

/// Usada onde o conceito não se aplica: web, desktop e testes.
///
/// Responde [PermissionState.notApplicable] — e **não** `granted`. A distinção
/// importa: a tela precisa saber que não há nada a pedir, em vez de acreditar
/// que já pediu e recebeu.
class NoopPermissionService implements PermissionService {
  const NoopPermissionService();

  @override
  Future<PermissionState> cameraStatus() async => PermissionState.notApplicable;

  @override
  Future<PermissionState> requestCamera() async => PermissionState.notApplicable;

  @override
  Future<bool> openSettings() async => false;
}

/// Escolhe a implementação certa para a plataforma.
PermissionService createPermissionService() {
  if (kIsWeb) return const NoopPermissionService();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => const DevicePermissionService(),
    _ => const NoopPermissionService(),
  };
}

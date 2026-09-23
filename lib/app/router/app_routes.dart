/// Caminhos de navegação.
///
/// Centralizados para que nenhuma tela escreva uma rota como string solta:
/// renomear um caminho passa a ser uma alteração de um único arquivo, e o
/// compilador acusa quem ficou para trás.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';

  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // Abas da navegação inferior.
  static const String home = '/home';
  static const String history = '/history';
  static const String catalog = '/catalog';
  static const String profile = '/profile';

  static const String settings = '/profile/settings';
  static const String about = '/profile/about';

  // Fluxo de identificação, empilhado sobre as abas.
  static const String capture = '/capture';
  static const String confirmPhoto = '/capture/confirm';
  static const String analyzing = '/analyzing';
  static const String result = '/result';
  static const String unidentified = '/result/unidentified';

  static const String photoTips = '/guide/photo-tips';

  static const String speciesPattern = '/species/:id';
  static String species(String id) => '/species/$id';

  /// Telas em que um usuário não autenticado pode legitimamente estar.
  static const Set<String> publicRoutes = <String>{
    splash,
    onboarding,
    login,
    register,
    forgotPassword,
  };
}

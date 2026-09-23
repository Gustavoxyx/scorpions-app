/// Validações de formulário de interface.
///
/// São validações de UX, não de segurança: a autoridade sobre credenciais é do
/// backend (Fase 3). Aqui o objetivo é dar feedback imediato e evitar viagens
/// desnecessárias à rede.
abstract final class Validators {
  static final RegExp _email = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  static const int minPasswordLength = 8;

  static String? required(String? value, {String field = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field é obrigatório.';
    }
    return null;
  }

  static String? name(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Informe seu nome.';
    if (v.length < 2) return 'Nome muito curto.';
    if (v.length > 80) return 'Nome muito longo.';
    return null;
  }

  static String? email(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Informe seu e-mail.';
    if (!_email.hasMatch(v)) return 'E-mail inválido.';
    return null;
  }

  static String? password(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Informe uma senha.';
    if (v.length < minPasswordLength) {
      return 'Use ao menos $minPasswordLength caracteres.';
    }
    return null;
  }

  static String? passwordConfirmation(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirme a senha.';
    if (value != original) return 'As senhas não coincidem.';
    return null;
  }

  /// Força relativa da senha, de 0 a 1. Usada só como indicador visual.
  static double passwordStrength(String value) {
    if (value.isEmpty) return 0;
    int score = 0;
    if (value.length >= minPasswordLength) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return (score / 5).clamp(0, 1);
  }
}

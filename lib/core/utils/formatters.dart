/// Formatação de exibição.
///
/// Evitamos `intl` nesta fase para manter a árvore de dependências enxuta; a
/// troca por `DateFormat` localizado é local a este arquivo.
abstract final class Formatters {
  static const List<String> _months = <String>[
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 01/09/2026
  static String date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// 01 set 2026
  static String dateLong(DateTime d) =>
      '${_two(d.day)} ${_months[d.month - 1]} ${d.year}';

  /// 01/09/2026 · 14:32
  static String dateTime(DateTime d) =>
      '${date(d)} · ${_two(d.hour)}:${_two(d.minute)}';

  /// "há 3 dias", "agora"
  static String relative(DateTime d, {DateTime? now}) {
    final Duration diff = (now ?? DateTime.now()).difference(d);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 30) return 'há ${diff.inDays} dias';
    return dateLong(d);
  }

  /// 0.94 -> "94%"
  static String percent(double value) =>
      '${(value.clamp(0, 1) * 100).round()}%';

  /// Saudação por horário, usada no cabeçalho da Home.
  static String greeting(DateTime now) {
    final int h = now.hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  /// Primeiro nome, para cabeçalhos que não podem quebrar linha.
  static String firstName(String fullName) {
    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  /// Iniciais para o avatar (sem foto na Fase 1).
  static String initials(String fullName) {
    final List<String> parts =
        fullName.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static const List<String> _monthsFull = <String>[
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  /// "setembro de 2026" — usado para agrupar o histórico por mês.
  static String monthYear(DateTime d) =>
      '${_monthsFull[d.month - 1]} de ${d.year}';

  /// Chave estável de agrupamento por mês (ordenável como texto).
  static String monthKey(DateTime d) =>
      '${d.year}-${_two(d.month)}';
}

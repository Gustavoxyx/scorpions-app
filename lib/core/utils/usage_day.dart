/// Dia de uso, como as Security Rules o entendem.
///
/// As regras limitam quantas identificações uma conta cria por dia, e contam
/// isso num documento por dia em `users/{uid}/usage/{dia}`. O identificador do
/// documento é este: dias inteiros desde a época, em UTC.
///
/// UTC, e não o fuso do aparelho, porque o servidor confere o valor contra o
/// próprio relógio — e dois lados contando dias em fusos diferentes
/// discordariam durante três horas todas as noites.
///
/// A regra aceita o dia do servidor e os vizinhos imediatos, então um relógio
/// de aparelho adiantado ou atrasado perto da virada não barra ninguém.
abstract final class UsageDay {
  static const int _millisPerDay = 86400000;

  static String of(DateTime instant) =>
      (instant.toUtc().millisecondsSinceEpoch ~/ _millisPerDay).toString();

  static String today() => of(DateTime.now());
}

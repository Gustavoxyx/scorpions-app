import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/stat_value.dart';
import '../../core/widgets/reveal.dart';
import '../../data/models/identification.dart';
import '../../state/history_controller.dart';
import '../../state/identification_controller.dart';
import 'widgets/history_card.dart';

/// Aba Histórico.
///
/// # Por que parece uma coleção, e não um log
/// Duas escolhas fazem isso: o resumo no topo — registros, espécies distintas e
/// **quantas vezes o sistema não soube responder** — e o agrupamento por mês,
/// que transforma uma lista corrida numa linha do tempo de descobertas.
///
/// Mostrar as rejeições no mesmo resumo é deliberado: elas fazem parte do
/// histórico do usuário, e escondê-las maquiaria o comportamento do produto.
///
/// Tocar num item reabre o resultado correspondente, reaproveitando as telas de
/// resultado/rejeição sem duplicar UI. Pronta para paginar sobre o Firestore na
/// Fase 3 sem mudança de layout.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  void _open(BuildContext context, IdentificationResult result) {
    context.read<IdentificationController>().showExisting(result);
    context.push(result.isRejected ? AppRoutes.unidentified : AppRoutes.result);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final HistoryController history = context.watch<HistoryController>();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AppStrings.historyTitle,
                        style: context.text.h1,
                      ),
                      if (!history.loading && history.items.isNotEmpty) ...[
                        AppSpacing.gapLg,
                        _CollectionSummary(history: history),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _body(context, history)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, HistoryController history) {
    if (history.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Falha de rede com lista vazia: mostra o erro. Falha com itens em cache:
    // a lista continua visível (ver nota em HistoryController.refresh) e o
    // aviso aparece discreto no topo, sem apagar o que o usuário já tinha.
    if (history.hasError && history.items.isEmpty) {
      return ErrorState(
        title: 'Não foi possível carregar',
        message: history.errorMessage!,
        onRetry: history.isRetryable ? history.refresh : null,
      );
    }

    if (history.isEmpty) {
      return EmptyState(
        title: AppStrings.historyEmptyTitle,
        message: AppStrings.historyEmptyBody,
        actionLabel: AppStrings.identifyCta,
        onAction: () {
          context.read<IdentificationController>().reset();
          context.push(AppRoutes.capture);
        },
      );
    }

    // Achata a lista em entradas intercaladas: cabeçalho de mês seguido dos
    // registros daquele mês. Mais simples de rolar que listas aninhadas e
    // mantém o `ListView` virtualizado.
    final List<_Entry> entries = _groupByMonth(history.items);

    return RefreshIndicator(
      onRefresh: history.refresh,
      color: context.colors.primary,
      backgroundColor: context.colors.surface,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.xs,
          AppSpacing.screenGutter,
          AppSpacing.bottomNavClearance,
        ),
        itemCount: entries.length,
        separatorBuilder: (BuildContext context, int index) => SizedBox(
          height: entries[index + 1].isHeader ? AppSpacing.xl : AppSpacing.md,
        ),
        itemBuilder: (BuildContext context, int index) {
          final _Entry entry = entries[index];
          return Reveal(
            // Atraso com teto: uma lista longa não pode terminar de aparecer
            // depois de o usuário já ter rolado até o fim dela.
            delay: Duration(milliseconds: 40 * (index > 6 ? 6 : index)),
            child: entry.isHeader
                ? _MonthHeader(label: entry.monthLabel!)
                : HistoryCard(
                    result: entry.result!,
                    onTap: () => _open(context, entry.result!),
                  ),
          );
        },
      ),
    );
  }

  static List<_Entry> _groupByMonth(List<IdentificationResult> items) {
    final List<_Entry> entries = <_Entry>[];
    String? currentKey;

    for (final IdentificationResult item in items) {
      final String key = Formatters.monthKey(item.createdAt);
      if (key != currentKey) {
        currentKey = key;
        entries.add(_Entry.header(Formatters.monthYear(item.createdAt)));
      }
      entries.add(_Entry.item(item));
    }
    return entries;
  }
}

/// Entrada achatada da lista: ou um cabeçalho de mês, ou um registro.
class _Entry {
  const _Entry.header(this.monthLabel) : result = null;
  const _Entry.item(this.result) : monthLabel = null;

  final String? monthLabel;
  final IdentificationResult? result;

  bool get isHeader => monthLabel != null;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: context.text.overline.copyWith(color: c.textTertiary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Container(height: AppSizing.hairline, color: c.border),
        ),
      ],
    );
  }
}

/// Resumo da coleção do usuário.
class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.history});

  final HistoryController history;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final int total = history.items.length;
    final int species = history.distinctSpeciesCount;
    final int unresolved =
        history.items.where((IdentificationResult r) => r.isRejected).length;

    return StatStrip(
      stats: <StatValue>[
        StatValue(value: '$total', label: 'Registros'),
        StatValue(value: '$species', label: 'Espécies', tint: c.primary),
        StatValue(
          value: '$unresolved',
          label: 'Sem resposta',
          tint: unresolved > 0 ? c.textSecondary : c.textTertiary,
        ),
      ],
    );
  }
}

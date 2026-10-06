import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/identification.dart';
import '../../../data/models/secondary_view.dart';

/// O que as duas fotografias disseram juntas.
///
/// Aparece nas telas de resultado quando a identificação teve duas vistas. Com
/// uma foto só, não aparece — não há o que dizer, e um cartão afirmando "1
/// vista, concordância total" seria informação inventada.
///
/// # Por que isto precisa estar na tela
/// A segunda fotografia existe para **pegar o erro confiante**: o caso em que
/// uma vista aponta uma espécie com firmeza e a outra aponta outra. Se a fusão
/// resolvesse isso em silêncio, o usuário veria um nome apresentado como
/// sempre, sem saber que as fotos discordaram. Dizer é o ponto.
///
/// # O aviso de limiar não calibrado
/// Os cortes de "alta" e "baixa" confiança ainda são palpites: nenhum modelo
/// foi avaliado. Enquanto for assim, o cartão diz. Mostrar o veredito sem esse
/// aviso seria afirmar uma precisão que ninguém mediu.
class MultiViewNote extends StatelessWidget {
  const MultiViewNote({super.key, required this.result});

  final IdentificationResult result;

  @override
  Widget build(BuildContext context) {
    if (result.viewCount < 2) return const SizedBox.shrink();

    final AppColors c = context.colors;
    final MultiViewSummary? resumo = result.multiView;

    final ({IconData icone, Color cor, String titulo, String corpo}) conteudo =
        _conteudo(c, resumo);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(conteudo.icone, color: conteudo.cor),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(conteudo.titulo, style: context.text.h4),
                    AppSpacing.gapXs,
                    Text(
                      conteudo.corpo,
                      style: context.text.bodySmall
                          .copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (resumo != null && !resumo.thresholdsCalibrated) ...<Widget>[
            AppSpacing.gapMd,
            Text(
              'Os limites de confiança ainda não foram calibrados com dados '
              'reais.',
              style: context.text.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  ({IconData icone, Color cor, String titulo, String corpo}) _conteudo(
    AppColors c,
    MultiViewSummary? resumo,
  ) {
    // Duas fotos registradas, nenhuma análise ainda — o caso de todo registro
    // gravado com infraestrutura de verdade enquanto não há modelo. O cartão
    // diz o que aconteceu com as fotos, sem insinuar um veredito.
    if (resumo == null) {
      return (
        icone: Icons.photo_library_outlined,
        cor: c.info,
        titulo: 'Duas fotos registradas',
        corpo: 'As duas vistas foram guardadas e seguem juntas para a análise.',
      );
    }

    if (resumo.agreeOnTop1) {
      return (
        icone: Icons.verified_outlined,
        cor: c.success,
        titulo: 'Duas fotos analisadas',
        corpo: 'As duas vistas apontaram a mesma espécie.',
      );
    }

    return (
      icone: Icons.compare_arrows_rounded,
      cor: c.warning,
      titulo: 'As duas fotos divergiram',
      corpo: result.isRejected
          ? 'Cada vista apontou uma espécie diferente, e por isso não '
              'mostramos um resultado.'
          : 'As vistas não apontaram a mesma espécie. Trate o resultado com '
              'cautela.',
    );
  }
}

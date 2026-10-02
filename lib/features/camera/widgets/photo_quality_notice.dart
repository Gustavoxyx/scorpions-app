import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_sizing.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/image_quality.dart';
import '../../../data/models/processed_image.dart';

/// O que o sistema achou da fotografia, dito ao usuário (briefing Fase 4, §6).
///
/// # Por que não basta um erro genérico
/// "Imagem inválida" não ajuda ninguém a tirar uma foto melhor. Cada aviso
/// aqui nomeia o problema **e** sugere a ação: procurar luz, apoiar o celular,
/// chegar mais perto. É a diferença entre uma porta fechada e uma instrução.
///
/// # Três tons, três decisões
/// - **bloqueio** — a foto não pode ser analisada. Só resta tirar outra.
/// - **atenção** — dá para seguir, e quem decide é o usuário.
/// - **silêncio** — foto boa não merece ruído na tela.
class PhotoQualityNotice extends StatelessWidget {
  const PhotoQualityNotice({super.key, required this.preparation});

  /// `null` enquanto a inspeção ainda não terminou.
  final ImagePreparation? preparation;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final ImagePreparation? p = preparation;

    if (p == null) {
      return _Painel(
        icone: Icons.hourglass_empty_rounded,
        cor: c.textTertiary,
        titulo: 'Verificando a foto…',
        linhas: const <String>['Conferindo resolução, luz e nitidez.'],
      );
    }

    // Recusa na validação: formato, tamanho ou resolução fora dos limites.
    if (!p.isValid) {
      return _Painel(
        icone: Icons.block_rounded,
        cor: c.error,
        titulo: 'Essa foto não dá para analisar',
        linhas: <String>[p.validation.message],
      );
    }

    // Foto de demonstração: não há arquivo, logo não há o que medir. Dizer
    // isso é mais honesto que exibir um veredito de qualidade inventado.
    if (p.isSimulated) {
      return _Painel(
        icone: Icons.science_outlined,
        cor: c.textTertiary,
        titulo: 'Foto de demonstração',
        linhas: const <String>[
          'Este aparelho não tem câmera disponível, então não há imagem '
              'para medir.',
        ],
      );
    }

    final ImageQualityResult q = p.quality!;

    // Quadro preto, estourado ou chapado: nenhuma análise salvaria.
    if (!q.isUsable) {
      return _Painel(
        icone: Icons.block_rounded,
        cor: c.error,
        titulo: 'Essa foto não dá para analisar',
        linhas: q.warnings.isEmpty
            ? const <String>['A imagem não tem informação visual suficiente.']
            : q.warnings
                .map((ImageQualityWarning w) => w.message)
                .toList(growable: false),
      );
    }

    if (q.warnings.isEmpty) {
      return _Painel(
        icone: Icons.check_circle_outline_rounded,
        cor: c.success,
        titulo: 'A foto está boa',
        linhas: const <String>[
          'Resolução, luz e nitidez dentro do esperado.',
        ],
      );
    }

    return _Painel(
      icone: Icons.info_outline_rounded,
      cor: c.warning,
      titulo: q.quality == ImageQuality.poor
          ? 'Essa foto pode atrapalhar a análise'
          : 'Dá para seguir, mas atenção',
      linhas: q.warnings
          .map((ImageQualityWarning w) => w.message)
          .toList(growable: false),
    );
  }
}

class _Painel extends StatelessWidget {
  const _Painel({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.linhas,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final List<String> linhas;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardCompact,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brSm,
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: AppSizing.iconMd, color: cor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  titulo,
                  style: context.text.labelSmall.copyWith(color: cor),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // Até três motivos. Uma lista longa deixa de ser orientação e
                // vira parede de texto que ninguém lê antes de tocar no botão.
                for (final String linha in linhas.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(linha, style: context.text.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

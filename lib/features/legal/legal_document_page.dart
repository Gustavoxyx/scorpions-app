import 'package:flutter/material.dart';

import '../../core/constants/legal_documents.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/feedback_states.dart';

/// Exibe um documento legal para leitura.
///
/// Acessível com e sem sessão: quem está se cadastrando precisa conseguir ler o
/// aviso de privacidade **antes** de ter uma conta.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final String? notice = document.notice;

    return AppScaffold(
      title: document.title,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (notice != null) ...<Widget>[
            DisclaimerBanner(message: notice),
            AppSpacing.gapXl,
          ],
          for (final LegalSection section in document.sections) ...<Widget>[
            Text(section.heading, style: context.text.h4),
            AppSpacing.gapSm,
            Text(section.body, style: context.text.body),
            AppSpacing.gapXl,
          ],
          if (document.version != null)
            Text(
              'Versão ${document.version}',
              style: context.text.bodySmall
                  .copyWith(color: context.colors.textTertiary),
            ),
          AppSpacing.gapXxl,
        ],
      ),
    );
  }
}

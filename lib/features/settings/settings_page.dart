import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/list_items.dart';
import '../../state/settings_controller.dart';

/// Configurações.
///
/// Os controles são reais quando têm efeito imediato nesta fase (tema,
/// notificações, telemetria, idioma). Os que dependem de backend aparecem como
/// itens de navegação com aviso de "fase futura" — visíveis, mas honestos
/// quanto ao que ainda não fazem.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();

    return AppScaffold(
      title: AppStrings.settingsTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Aparência.
          AppSection(
            title: AppStrings.settingsAppearance,
            icon: Icons.palette_outlined,
            child: _ThemeSelector(
              value: settings.themeMode,
              onChanged: settings.setThemeMode,
            ),
          ),
          AppSpacing.gapXxl,

          // Preferências ativas.
          AppSection(
            title: 'Preferências',
            icon: Icons.tune_rounded,
            child: AppTileGroup(
              children: <Widget>[
                AppSwitchTile(
                  label: AppStrings.settingsNotifications,
                  description: 'Alertas e novidades do aplicativo',
                  icon: Icons.notifications_outlined,
                  value: settings.notificationsEnabled,
                  onChanged: settings.setNotificationsEnabled,
                ),
                AppSwitchTile(
                  label: 'Compartilhar dados de uso',
                  description: 'Ajuda a melhorar o app. Desligado por padrão.',
                  icon: Icons.insights_outlined,
                  value: settings.analyticsEnabled,
                  onChanged: settings.setAnalyticsEnabled,
                ),
              ],
            ),
          ),
          AppSpacing.gapXxl,

          // Idioma.
          AppSection(
            title: AppStrings.settingsLanguage,
            icon: Icons.language_rounded,
            child: _LanguageSelector(
              value: settings.language,
              onChanged: settings.setLanguage,
            ),
          ),
          AppSpacing.gapXxl,

          // Itens que dependem de fases futuras.
          AppSection(
            title: 'Legal',
            icon: Icons.gavel_rounded,
            child: AppTileGroup(
              children: <Widget>[
                AppNavTile(
                  label: AppStrings.settingsPrivacy,
                  icon: Icons.privacy_tip_outlined,
                  value: AppStrings.soon,
                  onTap: () => _soon(context),
                ),
                AppNavTile(
                  label: AppStrings.settingsTerms,
                  icon: Icons.description_outlined,
                  value: AppStrings.soon,
                  onTap: () => _soon(context),
                ),
              ],
            ),
          ),
          AppSpacing.gapXxl,
          Center(
            child: Text(
              '${AppConfig.appName} ${AppConfig.version} · ${AppConfig.phaseLabel}',
              style: context.text.bodySmall
                  .copyWith(color: context.colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.comingSoon)),
    );
  }
}

/// Seletor de tema em três segmentos: sistema, claro, escuro.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const List<(ThemeMode, String, IconData)> _options =
      <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'Sistema', Icons.brightness_auto_rounded),
    (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Escuro', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: AppRadii.brMd,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: <Widget>[
          for (final (ThemeMode mode, String label, IconData icon) option
              in _options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option.$1),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: value == option.$1 ? c.surface : Colors.transparent,
                    borderRadius: AppRadii.brSm,
                    border: Border.all(
                      color: value == option.$1 ? c.border : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        option.$3,
                        size: 20,
                        color: value == option.$1 ? c.primary : c.textTertiary,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        option.$2,
                        style: context.text.labelSmall.copyWith(
                          color:
                              value == option.$1 ? c.textPrimary : c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Seletor de idioma. Só pt-BR está disponível; os demais aparecem
/// desabilitados para expressar a intenção do produto.
class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.value, required this.onChanged});

  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTileGroup(
      children: <Widget>[
        for (final AppLanguage language in AppLanguage.values)
          Opacity(
            opacity: language.available ? 1 : 0.45,
            child: AppNavTile(
              label: language.label,
              icon: value == language
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              value: language.available ? null : AppStrings.comingSoon,
              showChevron: false,
              onTap: language.available ? () => onChanged(language) : null,
            ),
          ),
      ],
    );
  }
}

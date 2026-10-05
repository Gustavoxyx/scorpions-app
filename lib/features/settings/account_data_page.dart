import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/list_items.dart';
import '../../data/repositories/account_repository.dart';
import '../../state/account_controller.dart';
import '../../state/auth_controller.dart';

/// Meus dados: exportar e excluir a conta.
///
/// # Por que esta tela existe
/// A auditoria encontrou que **cinco dos nove direitos** do Art. 18 da LGPD não
/// tinham caminho nenhum no aplicativo. O mais grave era o VI, eliminação: o
/// titular não conseguia apagar os próprios dados, nem pedindo — porque não
/// havia a quem pedir.
///
/// # Por que a exclusão fica aqui, e não escondida
/// A tentação é esconder a opção para reduzir cancelamentos. Mas um direito que
/// só existe para quem procura muito é um direito pela metade, e o §37 pede
/// transparência. Fica visível, com o aviso do que acontece — e com confirmação,
/// porque é irreversível.
class AccountDataPage extends StatelessWidget {
  const AccountDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountController conta = context.watch<AccountController>();

    return AppScaffold(
      title: 'Meus dados',
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _EmailVerificationNotice(),

          AppSection(
            title: 'Seus dados',
            icon: Icons.folder_outlined,
            child: AppTileGroup(
              children: <Widget>[
                AppNavTile(
                  label: 'Baixar meus dados',
                  icon: Icons.download_outlined,
                  value: conta.isExporting ? 'Preparando…' : null,
                  onTap: conta.isBusy ? null : () => _exportar(context),
                ),
              ],
            ),
          ),
          AppSpacing.gapXxl,

          AppSection(
            title: 'Excluir conta',
            icon: Icons.delete_forever_outlined,
            child: _DeletionCard(controller: conta),
          ),
        ],
      ),
    );
  }

  Future<void> _exportar(BuildContext context) async {
    final AccountController conta = context.read<AccountController>();
    final Map<String, Object?>? pacote = await conta.exportData();

    if (!context.mounted) return;

    if (pacote == null) {
      final String mensagem =
          conta.failure?.message ?? 'Não foi possível exportar seus dados.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagem)));
      return;
    }

    // Para a área de transferência, e não para um arquivo.
    //
    // Gravar arquivo exigiria `path_provider` e, no Android, negociar acesso ao
    // armazenamento compartilhado — dependência e permissão novas para um
    // recurso que o usuário usa uma vez. A área de transferência atende o
    // propósito do Art. 18, V (levar os dados para outro lugar) sem nada disso.
    //
    // Quando houver uma tela de compartilhamento nativa, ela entra aqui.
    final String json = const JsonEncoder.withIndent('  ').convert(pacote);
    await Clipboard.setData(ClipboardData(text: json));

    if (!context.mounted) return;
    final int quantas = (pacote['identifications'] as List<Object?>?)?.length ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Seus dados foram copiados: perfil e $quantas '
          '${quantas == 1 ? 'identificação' : 'identificações'}. '
          'Cole num aplicativo de notas para guardar.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

/// Aviso de e-mail não confirmado (MEDIUM-3 da auditoria).
///
/// # Por que isto importa, e não é burocracia
/// Sem confirmação, duas coisas ruins ficam possíveis. Alguém cadastra o
/// endereço de outra pessoa, e essa pessoa perde o endereço para uma conta que
/// não é dela. E, mais imediato: um endereço errado por um dígito **não recupera
/// a senha** — um esquecimento comum passa a significar perder a conta.
class _EmailVerificationNotice extends StatefulWidget {
  const _EmailVerificationNotice();

  @override
  State<_EmailVerificationNotice> createState() =>
      _EmailVerificationNoticeState();
}

class _EmailVerificationNoticeState extends State<_EmailVerificationNotice> {
  bool _enviando = false;
  bool _enviado = false;

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final bool verificado = auth.user?.emailVerified ?? true;

    if (verificado) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.mark_email_unread_outlined,
                  color: context.colors.warning,
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: Text(
                    'Confirme seu e-mail',
                    style: context.text.h4,
                  ),
                ),
              ],
            ),
            AppSpacing.gapMd,
            Text(
              _enviado
                  ? 'Enviamos o link. Abra seu e-mail e toque nele; depois volte '
                      'e toque em "Já confirmei".'
                  : 'Sem a confirmação, você não consegue recuperar a senha se '
                      'esquecê-la.',
              style: context.text.bodySmall
                  .copyWith(color: context.colors.textSecondary),
            ),
            AppSpacing.gapLg,
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: _enviado ? 'Já confirmei' : 'Enviar link',
                    variant: AppButtonVariant.secondary,
                    loading: _enviando,
                    onPressed: _enviado ? _recarregar : _enviar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final bool ok = await context.read<AuthController>().sendEmailVerification();
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _enviado = ok;
    });
  }

  /// A confirmação acontece fora do aplicativo, num navegador.
  ///
  /// O objeto em memória não sabe disso. Sem recarregar, o aviso continuaria na
  /// tela depois de confirmado — e um aviso que não some é um aviso que ensina o
  /// usuário a ignorar avisos.
  Future<void> _recarregar() async {
    setState(() => _enviando = true);
    await context.read<AuthController>().reloadUser();
    if (!mounted) return;
    setState(() => _enviando = false);
  }
}

class _DeletionCard extends StatelessWidget {
  const _DeletionCard({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: switch (controller.stage) {
        DeletionStage.done => _Concluido(receipt: controller.receipt),
        DeletionStage.awaitingPassword => _PedeSenha(controller: controller),
        _ => _Explicacao(controller: controller),
      },
    );
  }
}

class _Explicacao extends StatelessWidget {
  const _Explicacao({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Isto apaga, definitivamente:',
          style: context.text.body,
        ),
        AppSpacing.gapMd,
        // A lista é específica de propósito. "Todos os seus dados" não informa
        // nada; dizer o que some permite a pessoa decidir de verdade.
        ...<String>[
          'suas fotografias',
          'seu histórico de identificações',
          'seu perfil e seu login',
        ].map(
          (String item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('·  ', style: context.text.bodySmall),
                Expanded(
                  child: Text(
                    item,
                    style: context.text.bodySmall
                        .copyWith(color: context.colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.gapMd,
        Text(
          'Não há como desfazer, e não guardamos cópia.',
          style: context.text.bodySmall.copyWith(color: context.colors.error),
        ),
        if (controller.failure != null) ...<Widget>[
          AppSpacing.gapLg,
          Text(
            controller.failure!.message,
            style: context.text.bodySmall
                .copyWith(color: context.colors.error),
          ),
        ],
        AppSpacing.gapXl,
        AppButton(
          label: 'Excluir minha conta',
          variant: AppButtonVariant.danger,
          loading: controller.stage == DeletionStage.deleting,
          onPressed: controller.isBusy ? null : () => _confirmar(context),
        ),
      ],
    );
  }

  /// Confirmação antes de começar.
  ///
  /// Duas barreiras, e nenhuma é excesso: esta pergunta protege do toque
  /// acidental, e a senha depois protege de alguém que pegou o aparelho
  /// destravado. São ameaças diferentes.
  Future<void> _confirmar(BuildContext context) async {
    final bool? certeza = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogo) => AlertDialog(
        title: const Text('Excluir a conta?'),
        content: const Text(
          'Suas fotos, seu histórico e seu login serão apagados. '
          'Isso não pode ser desfeito.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: Text(
              'Excluir',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );

    if (certeza != true || !context.mounted) return;
    await context.read<AccountController>().requestDeletion();
  }
}

class _PedeSenha extends StatefulWidget {
  const _PedeSenha({required this.controller});

  final AccountController controller;

  @override
  State<_PedeSenha> createState() => _PedeSenhaState();
}

class _PedeSenhaState extends State<_PedeSenha> {
  final TextEditingController _senha = TextEditingController();

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Confirme sua senha', style: context.text.h4),
        AppSpacing.gapMd,
        Text(
          'Pedimos de novo porque esta ação não pode ser desfeita.',
          style: context.text.bodySmall
              .copyWith(color: context.colors.textSecondary),
        ),
        AppSpacing.gapLg,
        TextField(
          controller: _senha,
          obscureText: true,
          autofocus: true,
          enabled: widget.controller.stage != DeletionStage.deleting,
          decoration: const InputDecoration(labelText: 'Senha'),
          onSubmitted: (_) => _confirmar(),
        ),
        if (widget.controller.failure != null) ...<Widget>[
          AppSpacing.gapMd,
          Text(
            widget.controller.failure!.message,
            style: context.text.bodySmall
                .copyWith(color: context.colors.error),
          ),
        ],
        AppSpacing.gapXl,
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.secondary,
                onPressed: widget.controller.stage == DeletionStage.deleting
                    ? null
                    : widget.controller.cancelDeletion,
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: AppButton(
                label: 'Confirmar',
                variant: AppButtonVariant.danger,
                loading: widget.controller.stage == DeletionStage.deleting,
                onPressed: _confirmar,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmar() {
    if (_senha.text.isEmpty) return;
    context.read<AccountController>().confirmDeletion(_senha.text);
  }
}

class _Concluido extends StatelessWidget {
  const _Concluido({required this.receipt});

  final DeletionReceipt? receipt;

  @override
  Widget build(BuildContext context) {
    final DeletionReceipt? r = receipt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, color: context.colors.success),
            AppSpacing.gapMd,
            Expanded(
              child: Text('Conta excluída', style: context.text.h4),
            ),
          ],
        ),
        AppSpacing.gapMd,
        // O recibo é específico porque o usuário acabou de pedir algo
        // irreversível. "3 fotos e 2 análises apagadas" é verificável;
        // "pronto" não é.
        Text(
          r == null
              ? 'Seus dados foram apagados.'
              : 'Apagamos ${r.images} '
                  '${r.images == 1 ? 'foto' : 'fotos'} e '
                  '${r.identifications} '
                  '${r.identifications == 1 ? 'identificação' : 'identificações'}.',
          style: context.text.bodySmall
              .copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/pos_session.dart';

/// Cashier sign-in on a paired tablet. The desktop decides who may sign in
/// (this branch, point-of-sale access); a refusal is shown, never hidden.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final PosSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_user.text, _pass.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = posErrorCode(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final s = widget.session;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PicPosPageHeader(
            title: t('signInTitle'),
            subtitle: t('signInSub', {'branch': '${s.branchId ?? '-'}', 'terminal': s.terminalCode ?? '-'}),
            icon: Icons.lock_outline,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PicPosSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      key: const Key('login.user'),
                      controller: _user,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(labelText: t('username')),
                    ),
                    const SizedBox(height: PicPosSpacing.md),
                    TextField(
                      key: const Key('login.password'),
                      controller: _pass,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(labelText: t('password')),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: PicPosSpacing.md),
                      Text(S.errorText(context, _error!),
                          key: const Key('login.error'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: PicPosSpacing.lg),
                    FilledButton(
                      key: const Key('login.submit'),
                      onPressed: _busy ? null : _submit,
                      child: Text(t(_busy ? 'signingIn' : 'signIn')),
                    ),
                    const SizedBox(height: PicPosSpacing.md),
                    TextButton(
                      key: const Key('login.unpair'),
                      onPressed: _busy ? null : s.wipe,
                      child: Text(t('unpairDevice')),
                    ),
                    const SizedBox(height: PicPosSpacing.md),
                    const Center(child: PicPosLanguageThemeControls()),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

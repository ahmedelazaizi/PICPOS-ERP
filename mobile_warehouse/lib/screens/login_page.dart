import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart';
import 'settings_page.dart' show confirmUnpair;

/// Sign-in with the user's own PicPos account on the paired phone. The
/// phone's pairing grants nothing by itself: the account's role decides.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final WhSession session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
      if (mounted) setState(() => _error = errorCode(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PicPosPageHeader(title: t('loginTitle'), subtitle: t('loginSub'), icon: Icons.lock_outline),
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
                      autofillHints: const [AutofillHints.username],
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: t('username')),
                    ),
                    const SizedBox(height: PicPosSpacing.md),
                    TextField(
                      key: const Key('login.password'),
                      controller: _pass,
                      obscureText: true,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(labelText: t('password')),
                    ),
                    const SizedBox(height: PicPosSpacing.lg),
                    FilledButton(
                      key: const Key('login.submit'),
                      onPressed: _busy ? null : _submit,
                      child: Text(t(_busy ? 'signingIn' : 'signIn')),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: PicPosSpacing.md),
                      Text(S.errorText(context, _error!),
                          key: const Key('login.error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: PicPosSpacing.lg),
                    TextButton(
                      key: const Key('login.unpair'),
                      onPressed: () async {
                        if (await confirmUnpair(context)) await widget.session.wipe();
                      },
                      child: Text(t('unpair')),
                    ),
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

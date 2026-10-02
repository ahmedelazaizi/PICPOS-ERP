import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'common.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _url = TextEditingController(text: 'http://10.0.2.2:18080');
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _pair() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).pair(_url.text, _code.text);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pairTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: s.t('serverUrl')),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pairingCode'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              maxLength: 8,
              decoration: InputDecoration(labelText: s.t('pairingCode')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _pair,
              child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('pair')),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).login(_pin.text);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('loginTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.repName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(c.repName, style: Theme.of(context).textTheme.headlineSmall),
              ),
            TextField(
              key: const Key('pin'),
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.t('pin')),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _login, child: Text(s.t('login'))),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../scan/camera_scan_view.dart';
import '../session/wh_session.dart';

/// Pairs this phone with the office computer: scan the QR of the desktop
/// (Settings › Linked apps › PicPos Warehouse) or enter address, one-time
/// code and certificate fingerprint by hand. The pairing is pinned to the
/// fingerprint; a host without TLS is refused.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.session, this.scanner = scanWithCamera});
  final WhSession session;

  /// Camera QR reader; replaced in tests.
  final Future<String?> Function(BuildContext context, {bool qr}) scanner;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _fingerprint = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  Future<void> _run(PairingPayload Function() build) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.pair(build());
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final raw = await widget.scanner(context, qr: true);
    if (raw == null || !mounted) return;
    await _run(() => PairingPayload.parse(raw));
  }

  Future<void> _manual() => _run(() {
        final typed = _address.text.trim();
        // A pasted whole QR text is accepted in the address field.
        if (typed.startsWith('{')) return PairingPayload.parse(typed);
        final uri = Uri.tryParse(typed.contains('://') ? typed : 'https://$typed');
        if (uri == null || uri.host.isEmpty) throw const FormatException('incomplete');
        final fp = normalizeFingerprint(_fingerprint.text);
        if (fp == null) throw const FormatException('no_fingerprint');
        if (_code.text.trim().isEmpty) throw const FormatException('incomplete');
        return PairingPayload(
          version: 2,
          kind: PairingKind.warehouse,
          url: Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : 443),
          code: _code.text.trim().toUpperCase(),
          fingerprint: fp,
        );
      });

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PicPosPageHeader(title: t('pairTitle'), subtitle: t('pairSub'), icon: Icons.qr_code_2),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PicPosSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(t('appTitle'),
                        style: tt.displaySmall?.copyWith(color: context.picposBrandInk), textAlign: TextAlign.center),
                    const SizedBox(height: PicPosSpacing.lg),
                    PicPosBlock(
                      title: t('pairTitle'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final (i, key) in const [(1, 'pairStep1'), (2, 'pairStep2'), (3, 'pairStep3')])
                          Padding(
                            padding: const EdgeInsets.only(bottom: PicPosSpacing.sm),
                            child: Text('$i. ${t(key)}', style: tt.bodyMedium),
                          ),
                        const SizedBox(height: PicPosSpacing.sm),
                        FilledButton.icon(
                          key: const Key('onboarding.scan'),
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(t('scanQr')),
                        ),
                      ]),
                    ),
                    const SizedBox(height: PicPosSpacing.lg),
                    PicPosBlock(
                      title: t('manualEntry'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          key: const Key('onboarding.address'),
                          controller: _address,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t('serverAddress')),
                        ),
                        const SizedBox(height: PicPosSpacing.md),
                        TextField(
                          key: const Key('onboarding.code'),
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t('pairingCode')),
                        ),
                        const SizedBox(height: PicPosSpacing.md),
                        TextField(
                          key: const Key('onboarding.fingerprint'),
                          controller: _fingerprint,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t('fingerprint')),
                        ),
                        const SizedBox(height: PicPosSpacing.sm),
                        Text(t('pasteHint'), style: tt.bodySmall),
                        const SizedBox(height: PicPosSpacing.md),
                        OutlinedButton(
                          key: const Key('onboarding.pair'),
                          onPressed: _busy ? null : _manual,
                          child: Text(t(_busy ? 'pairingBusy' : 'pair')),
                        ),
                      ]),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: PicPosSpacing.md),
                      Text(S.errorText(context, _error!),
                          key: const Key('onboarding.error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: PicPosSpacing.lg),
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

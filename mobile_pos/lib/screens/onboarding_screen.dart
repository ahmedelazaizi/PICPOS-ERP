import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../scan/camera_scan_view.dart';
import '../session/pos_session.dart';

/// Pairs this Cashier tablet with the desktop (ADR-M5): scan the QR the
/// desktop shows for «ربط جهاز كاشير» or type the address, one-time code and
/// certificate fingerprint. The pairing is pinned to the fingerprint; a host
/// without TLS, an expired payload and a code for another device kind are
/// refused with a plain message. Manual entry always works (no camera needed).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.session, this.onPreview, this.scanner = scanWithCamera});
  final PosSession session;

  /// Opens the app shell without pairing (design preview); null hides it.
  final VoidCallback? onPreview;

  /// Camera QR reader; replaced in tests.
  final Future<String?> Function(BuildContext context, {bool qr}) scanner;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
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
      if (mounted) setState(() => _error = posErrorCode(e));
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
          kind: PairingKind.pos,
          url: Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : 443),
          code: _code.text.trim().toUpperCase(),
          fingerprint: fp,
        );
      });

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
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
                    Text(t('appTitle'), style: tt.displaySmall?.copyWith(color: context.picposBrandInk), textAlign: TextAlign.center),
                    const SizedBox(height: PicPosSpacing.lg),
                    // The office unpaired this tablet: say so.
                    if (widget.session.unpairNotice != null) ...[
                      Material(
                        key: const Key('onboarding.unpaired'),
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(PicPosSpacing.md),
                          child: Text(t('unpairedNotice'), style: TextStyle(color: scheme.onErrorContainer)),
                        ),
                      ),
                      const SizedBox(height: PicPosSpacing.lg),
                    ],
                    PicPosBlock(
                      title: t('pairTitle'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final (i, key) in const [(1, 'pairStep1'), (2, 'pairStep2'), (3, 'pairStep3')])
                          Padding(
                            padding: const EdgeInsets.only(bottom: PicPosSpacing.sm),
                            child: Text('$i. ${t(key)}', style: tt.bodyMedium),
                          ),
                        const SizedBox(height: PicPosSpacing.sm),
                        FilledButton(
                          key: const Key('onboarding.scan'),
                          onPressed: _busy ? null : _scan,
                          child: const _IconLabel(Icons.qr_code_scanner, 'scanQr'),
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
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(labelText: t('serverAddress'), hintText: '192.168.1.10:8443'),
                        ),
                        const SizedBox(height: PicPosSpacing.md),
                        TextField(
                          key: const Key('onboarding.code'),
                          controller: _code,
                          textDirection: TextDirection.ltr,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(labelText: t('pairingCode')),
                        ),
                        const SizedBox(height: PicPosSpacing.md),
                        TextField(
                          key: const Key('onboarding.fingerprint'),
                          controller: _fingerprint,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t('pairFingerprint')),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: PicPosSpacing.md),
                          Text(S.errorText(context, _error!), key: const Key('onboarding.error'), style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: PicPosSpacing.md),
                        OutlinedButton(
                          key: const Key('onboarding.pair'),
                          onPressed: _busy ? null : _manual,
                          child: Text(t(_busy ? 'pairBusy' : 'pair')),
                        ),
                      ]),
                    ),
                    if (widget.onPreview != null) ...[
                      const SizedBox(height: PicPosSpacing.lg),
                      TextButton.icon(
                        key: const Key('onboarding.preview'),
                        onPressed: widget.onPreview,
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(t('previewApp')),
                      ),
                    ],
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

class _IconLabel extends StatelessWidget {
  const _IconLabel(this.icon, this.labelKey);
  final IconData icon;
  final String labelKey;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: PicPosSpacing.sm),
        Flexible(child: Text(S.of(context)(labelKey))),
      ]);
}

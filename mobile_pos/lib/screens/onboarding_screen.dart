import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// Pairing screen — UI only in M-0 (ARCHITECTURE-M ADR-M5: the tablet pairs
/// with the desktop LAN server as a terminal). Pairing arrives in M-5.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onPreview});
  final VoidCallback onPreview;

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
                    Text(t('appTitle'), style: tt.displaySmall?.copyWith(color: context.picposBrandInk), textAlign: TextAlign.center),
                    const SizedBox(height: PicPosSpacing.sm),
                    Center(child: StatusPill(label: t('previewOnly'), tone: PicPosTone.warning, icon: Icons.info_outline)),
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
                        const FilledButton(onPressed: null, child: _IconLabel(Icons.qr_code_scanner, 'scanQr')),
                      ]),
                    ),
                    const SizedBox(height: PicPosSpacing.lg),
                    PicPosBlock(
                      title: t('manualEntry'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          enabled: false,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: t('serverAddress'), hintText: '192.168.1.10'),
                        ),
                        const SizedBox(height: PicPosSpacing.md),
                        TextField(enabled: false, decoration: InputDecoration(labelText: t('pairingCode'))),
                        const SizedBox(height: PicPosSpacing.md),
                        OutlinedButton(onPressed: null, child: Text(t('pair'))),
                      ]),
                    ),
                    const SizedBox(height: PicPosSpacing.lg),
                    TextButton.icon(
                      key: const Key('onboarding.preview'),
                      onPressed: onPreview,
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(t('previewApp')),
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

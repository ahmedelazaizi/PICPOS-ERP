import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../app.dart';
import '../l10n/strings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onOpenPairing});
  final VoidCallback onOpenPairing;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(title: t('navSettings'), subtitle: t('settingsSub'), icon: Icons.settings_outlined),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
          Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PicPosBlock(title: t('navSettings'), child: const PicPosLanguageThemeControls()),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(title: t('printer'), child: Text(t('printerMsg'), style: tt.bodyMedium)),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('pairing'),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const Key('settings.openPairing'),
                      onPressed: onOpenPairing,
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(t('openPairing')),
                    ),
                  ),
                ),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('about'),
                  child: Text('${t('appTitle')} · ${t('version', {'v': kAppVersion})}', style: tt.bodyMedium),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

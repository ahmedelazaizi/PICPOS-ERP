import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../app.dart';
import '../admin_session.dart';
import '../l10n/strings.dart';
import 'unpair_flow.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session, required this.onOpenPairing});
  final AdminSession session;
  final VoidCallback onOpenPairing;

  Future<void> _confirmLogout(BuildContext context) async {
    final t = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('logout')),
        content: Text(t('logoutWarning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t('logout'))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await session.logout();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
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
                PicPosBlock(
                  title: t('accountDevice'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${t('boundUser')}: ${session.displayName ?? session.username ?? t('unknownUser')}'
                        '${session.displayName != null && session.username != null ? ' (${session.username})' : ''}'),
                    Text('${t('serverUrl')}: ${session.serverUrl ?? '—'}'),
                    Text(session.paired ? t('pairedStatus') : t('notPaired')),
                    if (session.loggedIn) ...[
                      const SizedBox(height: PicPosSpacing.sm),
                      OutlinedButton.icon(
                        key: const Key('settings.logout'),
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout),
                        label: Text(t('logout')),
                      ),
                    ],
                    if (session.paired) ...[
                      const SizedBox(height: PicPosSpacing.sm),
                      OutlinedButton.icon(
                        key: const Key('settings.unpair'),
                        onPressed: () => confirmUnpair(context, session),
                        icon: const Icon(Icons.phonelink_erase),
                        label: Text(t('switchUserUnpair')),
                      ),
                    ] else
                      OutlinedButton.icon(
                        key: const Key('settings.openPairing'),
                        onPressed: onOpenPairing,
                        icon: const Icon(Icons.qr_code_2),
                        label: Text(t('openPairing')),
                      ),
                  ]),
                ),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('about'),
                  child: Text('${t('appTitle')} · ${t('version', {'v': kAppVersion})}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

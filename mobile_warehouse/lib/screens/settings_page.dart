import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../session/wh_session.dart';
import '../sync/wh_ops.dart';
import 'printer_settings_page.dart';

/// Asks before wiping the pairing; returns true when confirmed.
Future<bool> confirmUnpair(BuildContext context) async {
  final t = S.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('unpair')),
          content: Text(t('unpairBody')),
          actions: [
            TextButton(key: const Key('unpair.cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(key: const Key('unpair.confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(t('confirm'))),
          ],
        ),
      ) ??
      false;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session, this.ops});
  final WhSession session;
  final WhOps? ops;

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
                PicPosBlock(
                  title: t('account'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(session.info?.displayName ?? '—', style: tt.titleMedium),
                    const SizedBox(height: PicPosSpacing.sm),
                    OutlinedButton.icon(
                      key: const Key('settings.signOut'),
                      onPressed: session.signOut,
                      icon: const Icon(Icons.logout),
                      label: Text(t('signOut')),
                    ),
                  ]),
                ),
                if (ops != null) ...[
                  const SizedBox(height: PicPosSpacing.lg),
                  PicPosBlock(
                    title: t('printerTitle'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ops!.printer.hasPrinter ? t('printerCurrent', {'name': ops!.printer.printerName ?? ''}) : t('noPrinterConnected'),
                          key: const Key('settings.printerStatus')),
                      const SizedBox(height: PicPosSpacing.sm),
                      OutlinedButton.icon(
                        key: const Key('settings.printer'),
                        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PrinterSettingsPage(ops: ops!))),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(t('choosePrinter')),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('pairing'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('pairedTo', {'name': session.info?.branchName ?? '${session.branchId ?? ''}'})),
                    Text(session.serverUrl?.host ?? '', textDirection: TextDirection.ltr, style: tt.bodySmall),
                    const SizedBox(height: PicPosSpacing.sm),
                    OutlinedButton.icon(
                      key: const Key('settings.unpair'),
                      onPressed: () async {
                        if (await confirmUnpair(context)) await session.wipe();
                      },
                      icon: const Icon(Icons.link_off),
                      label: Text(t('unpair')),
                    ),
                  ]),
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

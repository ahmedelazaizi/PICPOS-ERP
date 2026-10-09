import 'package:flutter/material.dart';

import '../admin_session.dart';
import '../l10n/strings.dart';

Future<void> confirmUnpair(BuildContext context, AdminSession session) async {
  final t = S.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t('unpairDevice')),
      content: Text(t('unpairWarning')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t('unpairDevice'))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final revoked = await session.unpairAndWipe();
  if (!revoked && messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(t('revokeOnDesktop'))));
  }
}

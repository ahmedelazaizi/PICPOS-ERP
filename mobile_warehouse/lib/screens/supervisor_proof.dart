import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';

import '../l10n/strings.dart';
import '../sync/wh_ops.dart';
import '../widgets/wh_widgets.dart';

/// WH-010: the supervisor standing next to this phone types HIS credential; the
/// office checks it and signs a proof for exactly this document + [action] (and
/// its version). The caller attaches [WhApprovalProof.proof] to the approve /
/// reject call. Returns null when cancelled or refused (the refusal is shown).
Future<WhApprovalProof?> askSupervisorProof(
  BuildContext context,
  WhOps ops, {
  required String kind,
  required String ref,
  required String action,
}) async {
  final creds = await showDialog<(String, String)>(context: context, builder: (_) => const _CredentialsDialog());
  if (creds == null || !context.mounted) return null;
  try {
    return await ops.online((c) => c.approvalProof(kind: kind, ref: ref, action: action, username: creds.$1, password: creds.$2));
  } on Object catch (e) {
    if (context.mounted) showFailure(context, e);
    return null;
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog();
  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t('askSupervisor')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(key: const Key('proof.user'), controller: _user, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: t('supervisorUser'))),
        TextField(
            key: const Key('proof.password'),
            controller: _pass,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: t('supervisorPassword'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          key: const Key('proof.ok'),
          onPressed: () {
            final name = _user.text.trim();
            if (name.isNotEmpty && _pass.text.isNotEmpty) Navigator.pop(context, (name, _pass.text));
          },
          child: Text(t('approve')),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../admin_session.dart';
import '../l10n/strings.dart';

class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final rows = <Widget>[];
    for (final kind in SnapshotKinds.approvals) {
      final snapshot = session.snapshots?.find(kind);
      if (snapshot?.payload is! Map) continue;
      final payload = snapshot!.payload as Map;
      final entries = payload['items'];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! Map) continue;
        rows.add(
          ListTile(
            title: Text('${entry['summary']}'),
            subtitle: Text('$kind · ${entry['ref']}'),
            trailing: Text('${entry['amount']}'),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PicPosPageHeader(
          title: t('navApprovals'),
          subtitle: t('approvalsSub'),
          icon: Icons.fact_check_outlined,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            children: [
              Text(t('viewOnly')),
              if (rows.isEmpty) Text(t('noPendingApprovals')) else ...rows,
            ],
          ),
        ),
      ],
    );
  }
}

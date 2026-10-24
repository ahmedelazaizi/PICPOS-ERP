import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// Receiving, transfers, counts and vouchers arrive in plan phases W2-W4.
/// Until then this tab says so plainly; nothing here pretends to work.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: t('navDocuments'),
        subtitle: t('documentsSub'),
        icon: Icons.description_outlined,
        actions: [StatusPill(label: t('notAvailable'), tone: PicPosTone.warning, icon: Icons.info_outline)],
      ),
      Expanded(child: EmptyState(icon: Icons.description_outlined, title: t('notAvailable'), message: t('documentsNone'))),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../sync/wh_ops.dart';
import 'approvals_page.dart';
import 'count_pages.dart';
import 'labels_page.dart';
import 'printer_settings_page.dart';
import 'receive_pages.dart';
import 'transfer_pages.dart';

/// Hub of the document screens. A tile appears only when the signed-in user's
/// permissions (as returned by the office) allow it; nothing is shown that
/// the server would refuse.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key, required this.ops});
  final WhOps ops;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    Widget tile(String id, IconData icon, String title, String sub, Widget Function() page) => Card(
          child: ListTile(
            key: Key('doc.$id'),
            minVerticalPadding: PicPosSpacing.lg,
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page())),
          ),
        );
    final tiles = <Widget>[
      if (ops.can('goods_receipt_mobile')) tile('receive', Icons.inventory_2_outlined, t('receiveTitle'), t('receiveSub'), () => PoListPage(ops: ops)),
      if (ops.can('stock_count_submit')) tile('count', Icons.fact_check_outlined, t('countTitle'), t('countSub'), () => CountTasksPage(ops: ops)),
      if (ops.can('inventory_transfer') || ops.can('stock_adjust_approve'))
        tile('transfers', Icons.swap_horiz, t('transfersTitle'), t('transfersSub'), () => TransfersPage(ops: ops)),
      if (ops.can('inventory_edit')) tile('voucher', Icons.edit_note, t('voucherTitle'), t('voucherSub'), () => VoucherPage(ops: ops)),
      if (ops.can('stock_adjust_approve')) tile('approvals', Icons.verified_outlined, t('approvalsTitle'), t('approvalsSub'), () => ApprovalsPage(ops: ops)),
      if (ops.can('inventory_view'))
        tile('labels', Icons.label_outline, t('labelsTitle'), t('labelsSub'),
            () => LabelsPage(ops: ops, openSettings: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PrinterSettingsPage(ops: ops))))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(title: t('navDocuments'), subtitle: t('documentsSub'), icon: Icons.description_outlined),
      Expanded(
        child: tiles.isEmpty
            ? EmptyState(icon: Icons.lock_outline, title: t('navDocuments'), message: t('documentsNoAccess'))
            : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: tiles),
      ),
    ]);
  }
}

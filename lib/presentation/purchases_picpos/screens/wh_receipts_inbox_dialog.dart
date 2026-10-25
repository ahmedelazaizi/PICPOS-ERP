// WH-002: «استلامات المخازن» - the accountant's inbox of receipts the
// warehouse phones submitted. Converting one posts the purchase invoice with
// the accepted quantities (damaged goods stay out), the batch/expiry the
// storekeeper scanned and the PO line's discount/tax/cost centre. The service
// (`WhReceiptsInbox`) enforces `purchases_create` and the warehouse scope;
// this dialog only presents.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/wh_receipts_inbox_provider.dart';
import '../../picpos_shell/picpos_dialog.dart';

Future<void> showWhReceiptsInboxDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const WhReceiptsInboxDialog());

class WhReceiptsInboxDialog extends ConsumerStatefulWidget {
  const WhReceiptsInboxDialog({super.key});

  @override
  ConsumerState<WhReceiptsInboxDialog> createState() => _WhReceiptsInboxDialogState();
}

class _WhReceiptsInboxDialogState extends ConsumerState<WhReceiptsInboxDialog> {
  List<Map<String, Object?>>? _receipts;
  String? _error;
  String? _busyGid;

  int? get _userId => ref.read(authProvider).user?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The service refuses with a stable code; the dialog speaks the user's words.
  String _say(Object e) {
    final code = (e as dynamic).toString();
    if (code.contains('permission_denied')) return tr('ليست لديك صلاحية تحويل الاستلامات إلى فواتير.');
    if (code.contains('invalid_transition')) return tr('حُوِّل هذا الاستلام من قبل. حدّث القائمة.');
    if (code.contains('period_closed')) return tr('الفترة المحاسبية مغلقة؛ لم يُسجَّل شيء.');
    if (code.contains('accounts_not_mapped')) return tr('حسابات المخزون غير مربوطة؛ لم يُسجَّل شيء.');
    if (code.contains('po_not_receivable')) return tr('أمر الشراء لم يعد مفتوحاً لهذا الاستلام.');
    return tr('تعذّر التحويل؛ لم يُسجَّل شيء.');
  }

  Future<void> _load() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final list = await ref.read(whReceiptsInboxProvider).list(uid);
      if (mounted) setState(() => _receipts = list);
    } catch (e) {
      if (mounted) setState(() => _error = _say(e));
    }
  }

  Future<void> _convert(String gid) async {
    final uid = _userId;
    if (uid == null || _busyGid != null) return;
    setState(() => _busyGid = gid);
    try {
      await ref.read(whReceiptsInboxProvider).convert(gid, uid);
      if (mounted) AppToast.show(context, tr('حُوِّل الاستلام إلى فاتورة مشتريات.'));
    } catch (e) {
      if (mounted) AppToast.show(context, _say(e), type: ToastType.error);
    }
    if (mounted) setState(() => _busyGid = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final muted = picposDialogMuted(context);
    final receipts = _receipts;
    return PicPosDialog(
      icon: PhosphorIconsBold.package,
      title: tr('استلامات المخازن'),
      subtitle: tr('استلامات أرسلتها هواتف المخازن وتنتظر التحويل إلى فاتورة مشتريات'),
      width: 760,
      onCancel: () => Navigator.of(context).pop(),
      cancelLabel: tr('إغلاق'),
      body: [
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.error))
        else if (receipts == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (receipts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('لا توجد استلامات بانتظار التحويل.'), style: TextStyle(color: muted)),
          )
        else
          for (final r in receipts) _card(context, r, muted),
      ],
    );
  }

  Widget _card(BuildContext context, Map<String, Object?> r, Color muted) {
    final gid = r['globalId']! as String;
    final lines = (r['lines']! as List).cast<Map>();
    final busy = _busyGid == gid;
    return Container(
      key: Key('whInbox.$gid'),
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('أمر الشراء {p0} — {p1}', {'p0': '${r['orderNumber']}', 'p1': '${r['supplier'] ?? ''}'}),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                key: Key('whInbox.convert.$gid'),
                onPressed: _busyGid == null ? () => _convert(gid) : null,
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(PhosphorIconsBold.receipt, size: 16),
                label: Text(tr('تحويل لفاتورة')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('المخزن {p0} · أرسله {p1}', {'p0': '${r['warehouse'] ?? ''}', 'p1': '${r['createdBy']}'}),
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Row(
                children: [
                  Expanded(child: Text('${l['name']}')),
                  // Quantities and batch codes are LTR runs inside RTL text.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('${l['quantity']}${l['batchNumber'] == null ? '' : '  ${l['batchNumber']}'}'),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l['condition'] == 'damaged' ? tr('تالف — لا يدخل المخزون') : tr('سليم'),
                    style: TextStyle(color: l['condition'] == 'damaged' ? AppColors.error : muted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

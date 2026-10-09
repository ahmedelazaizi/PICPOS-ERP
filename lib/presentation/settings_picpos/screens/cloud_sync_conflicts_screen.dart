import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/cloud_sync/cloud_link_controller.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';

String cloudConflictKindLabel(String kind) => switch (kind) {
  'sales_invoice' => tr('فاتورة مبيعات'),
  'sales_return' => tr('مرتجع مبيعات'),
  'collection' => tr('سند قبض'),
  'visit' => tr('زيارة عميل'),
  'expense' => tr('سند صرف مصروف مندوب'),
  _ => kind,
};

String _reasonCode(CloudConflictView conflict) =>
    (conflict.reason ?? '').split(':').first.trim();

String _reasonLabel(String code) => switch (code) {
  'customer_not_found' => tr('العميل غير موجود على هذا الجهاز'),
  'product_not_found' => tr('الصنف غير موجود'),
  'van_warehouse_not_found' => tr('مخزن السيارة غير موجود'),
  'rep_not_found' => tr('المندوب غير موجود'),
  'custody_safe_not_found' => tr('خزنة العهدة غير موجودة'),
  'original_invoice_not_posted' => tr('الفاتورة الأصلية لم تُرحَّل بعد'),
  'totals_mismatch' => tr('اختلاف الإجمالي بين الجهاز والسحابة'),
  'desktop_rejected' => tr('رفض الجهاز المستند'),
  'no_lines' => tr('مستند بلا أصناف'),
  'return_qty_exceeds_invoice' => tr('كمية المرتجع تتجاوز الفاتورة'),
  'voucher_book_leaf_rejected' => tr('رُفض رقم دفتر السندات'),
  'voucher_book_not_found' => tr('دفتر السندات غير موجود'),
  'book_number_required' => tr('رقم السند مطلوب'),
  'invalid_amount' => tr('المبلغ غير صالح'),
  'expense_category_not_found' => tr('فئة المصروف غير موجودة'),
  'expense_account_not_found' => tr('حساب المصروف غير موجود'),
  'route_not_found' => tr('المسار غير موجود'),
  'invalid_global_id' => tr('معرّف المستند غير صالح'),
  'name_required' => tr('الاسم مطلوب'),
  'unsupported_kind' => tr('نوع المستند غير مدعوم'),
  'desktop_error' => tr('خطأ على هذا الجهاز'),
  _ => code,
};

class CloudSyncConflictsScreen extends ConsumerStatefulWidget {
  const CloudSyncConflictsScreen({super.key, required this.conflicts});
  final List<CloudConflictView> conflicts;

  @override
  ConsumerState<CloudSyncConflictsScreen> createState() =>
      _CloudSyncConflictsScreenState();
}

class _CloudSyncConflictsScreenState
    extends ConsumerState<CloudSyncConflictsScreen> {
  late List<CloudConflictView> _conflicts = widget.conflicts;
  String? _kind;
  String? _reason;
  bool _busy = false;

  CloudLinkController get _ctrl => ref.read(cloudLinkControllerProvider);

  List<CloudConflictView> get _filtered {
    final conflicts = _conflicts.where((conflict) =>
        (_kind == null || conflict.kind == _kind) &&
        (_reason == null || _reasonCode(conflict) == _reason)).toList();
    conflicts.sort((a, b) => (b.updatedAt ?? DateTime(0))
        .compareTo(a.updatedAt ?? DateTime(0)));
    return conflicts;
  }

  Future<void> _retry(List<CloudConflictView> conflicts) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      for (final conflict in conflicts) {
        await _ctrl.retry(conflict.globalId);
      }
      await _ctrl.syncNow();
      final view = await _ctrl.load(includeSecret: false);
      if (mounted) setState(() => _conflicts = view.conflicts);
    } catch (error) {
      if (mounted) {
        AppToast.show(context,
            tr('تعذّر تنفيذ العملية: {error}', {'error': '$error'}),
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryAll() async {
    final conflicts = _filtered.where((conflict) => !conflict.retryRequested).toList();
    if (conflicts.isEmpty) return;
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.arrowsClockwise,
      title: tr('إعادة محاولة الكل'),
      message: tr('ستُعاد محاولة {n} تعارضات في الفلتر الحالي.',
          {'n': conflicts.length}),
      confirmLabel: tr('إعادة محاولة الكل'),
    );
    if (confirmed && mounted) await _retry(conflicts);
  }

  Widget _chips(String? selected, Map<String, int> counts,
      String Function(String) label, ValueChanged<String?> onSelected) =>
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: Text('${tr('الكل')} (${_conflicts.length})'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final entry in counts.entries)
            ChoiceChip(
              label: Text('${label(entry.key)} (${entry.value})'),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
        ],
      );

  Widget _conflictCard(CloudConflictView conflict) => Card(
    color: context.picposField,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${cloudConflictKindLabel(conflict.kind)} ${conflict.cloudNumber ?? ''}',
              style: TextStyle(fontWeight: FontWeight.w700,
                  color: context.picposText)),
          const SizedBox(height: 6),
          Text(_reasonLabel(_reasonCode(conflict)),
              style: TextStyle(color: context.picposText)),
          if ((conflict.reason ?? '').isNotEmpty)
            Text(conflict.reason!, style: TextStyle(fontSize: 11,
                color: context.picposMuted)),
          Text([
            tr('المحاولات: {n}', {'n': conflict.attempts}),
            if (conflict.updatedAt != null)
              tr('آخر محاولة: {t}', {'t': DateFormat('yyyy-MM-dd HH:mm')
                  .format(conflict.updatedAt!)}),
          ].join(' · '), style: TextStyle(fontSize: 11,
              color: context.picposMuted)),
          if (conflict.retryRequested)
            Text(tr('ستُعاد المحاولة في المزامنة القادمة'))
          else
            TextButton(
              onPressed: _busy ? null : () => _retry([conflict]),
              child: Text(tr('إعادة المحاولة')),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kinds = <String, int>{};
    final reasons = <String, int>{};
    for (final conflict in _conflicts) {
      kinds.update(conflict.kind, (count) => count + 1, ifAbsent: () => 1);
      final code = _reasonCode(conflict);
      reasons.update(code, (count) => count + 1, ifAbsent: () => 1);
    }
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(tr('تعارضات المزامنة السحابية'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('نوع المستند'), style: Theme.of(context).textTheme.titleSmall),
          _chips(_kind, kinds, cloudConflictKindLabel,
              (kind) => setState(() => _kind = kind)),
          const SizedBox(height: 12),
          Text(tr('سبب التعارض'), style: Theme.of(context).textTheme.titleSmall),
          _chips(_reason, reasons, _reasonLabel,
              (reason) => setState(() => _reason = reason)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy || filtered.every((c) => c.retryRequested)
                  ? null : _retryAll,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise),
              label: Text(tr('إعادة محاولة الكل')),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (filtered.isEmpty) Text(tr('لا توجد تعارضات')),
          for (final conflict in filtered) _conflictCard(conflict),
        ],
      ),
    );
  }
}

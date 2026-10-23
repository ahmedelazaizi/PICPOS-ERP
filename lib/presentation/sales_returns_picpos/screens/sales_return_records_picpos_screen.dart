import 'package:picpos_erp/core/i18n/tr.dart';
// شاشةُ **سجلّ مرتجعات المبيعات** — J2 (قرارُ المالك).
//
// ═══ ما كان، وما صار ═══
//
// مدخلُ «مرتجع المبيعات» كان يفتح استمارةَ الإنشاء مباشرةً، ولمطالعة ما
// مضى **حوارٌ** خلف زرّ «سجل المرتجعات». فصار المدخلُ هذا السجلّ — كسجلّ
// فواتير البيع وسجلّ المشتريات: مدىً وبحثٌ (بالرقم/العميل/السبب)، وشرائحُ
// حالةٍ (الكلّ · مسودة · معتمد · ملغى)، وجدولٌ بمجاميعه، وأفعالُ صفٍّ بحسب
// الحالة والصلاحية. و«جديد» يدفع الاستمارةَ صفحةً، وبعد الاعتماد تعود إلى
// هنا والصفُّ الجديدُ مختار.
//
// ⚠️ **المعتمدُ صفٌّ لكلّ فاتورةٍ أصل** — هي القراءةُ نفسُها التي كان يعرضها
//    الحوار (`getSalesReturnHistoryEntries`)، وهي ما يعمل عليه الإلغاءُ
//    القائم (`cancelSalesReturn` يلغي مرتجعاتِ الفاتورة كلَّها معاً).
//    والمسوّداتُ والملغاةُ من `return_drafts` (v189).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/return_records_providers.dart';
import '../../../domain/models/return_draft.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../providers/sales_return_provider.dart';
import '../../shared_widgets/return_draft_support.dart';
import '../../shared_widgets/return_records_view.dart';
import '../../widgets/permission_guard.dart';
import 'sales_returns_picpos_screen.dart';

class SalesReturnRecordsPicPosScreen extends ConsumerStatefulWidget {
  const SalesReturnRecordsPicPosScreen({super.key});

  @override
  ConsumerState<SalesReturnRecordsPicPosScreen> createState() =>
      _SalesReturnRecordsPicPosScreenState();
}

class _SalesReturnRecordsPicPosScreenState
    extends SalesReturnRecordActionsState<SalesReturnRecordsPicPosScreen> {
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  final _searchController = TextEditingController();
  int _statusChip = 0;
  String? _selectedKey;

  /// بعد العودة من الاستمارة: اختيارُ صفّ الفاتورة المرحَّلة متى ظهر.
  int? _selectPostedInvoice;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ReturnRecordWindow get _window => (
        from: DateTime(_from.year, _from.month, _from.day),
        // آخرُ اللحظة لا أوّلُها — وإلّا سقطت مرتجعاتُ اليوم.
        to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
      );

  void _refresh() => ref.invalidate(salesReturnRecordsProvider);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(salesReturnRecordsProvider(_window));
    final entries = async.asData?.value ?? const <SalesReturnRecordEntry>[];
    final all = [
      for (final e in entries)
        if (e.row.matches(_search)) e,
    ];
    final rows = [for (final e in all) e.row];

    if (_selectPostedInvoice != null && async.hasValue) {
      final hit = rows
          .where((r) =>
              r.originalInvoiceId == _selectPostedInvoice &&
              r.status == ReturnRecordStatus.posted)
          .firstOrNull;
      if (hit != null) {
        _selectedKey = hit.key;
        _selectPostedInvoice = null;
      }
    }

    final shown = ReturnRecordsTable.shownRows(rows, _statusChip);
    final selected = all
        .where((e) =>
            e.row.key == _selectedKey && shown.any((r) => r.key == e.row.key))
        .firstOrNull;

    return PermissionGuard(
      permission: PermissionCodes.salesReturnView,
      child: PicPosScreenScaffold(
        title: tr('مرتجع المبيعات'),
        subtitle: tr('تسجيل ومتابعة مرتجعات البيع'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        headerActions: [
          FilledButton.icon(
            key: const Key('return_records_new'),
            onPressed: _openNew,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text(tr('جديد')),
          ),
        ],
        toolbar: ReturnRecordsFilterBar(
          from: _from,
          to: _to,
          onPickFrom: () => _pickDate(isFrom: true),
          onPickTo: () => _pickDate(isFrom: false),
          searchController: _searchController,
          onSearchChanged: (v) => setState(() => _search = v.trim()),
          searchHint: tr('الرقم · العميل · السبب'),
        ),
        body: async.hasError
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.warning,
                title: tr('تعذّرت قراءةُ السجلّ'),
                hint: '${async.error}',
              )
            : ListView(children: [
                ReturnRecordsTable(
                  title: tr('مرتجعات المبيعات'),
                  rows: rows,
                  statusChip: _statusChip,
                  onStatusChip: (i) => setState(() {
                    _statusChip = i;
                    _selectedKey = null;
                  }),
                  selectedKey: _selectedKey,
                  onSelect: (k) => setState(() => _selectedKey = k),
                  partyLabel: tr('العميل'),
                  loading: async.isLoading,
                ),
                if (selected != null) ...[
                  const SizedBox(height: 10),
                  ReturnRecordActionBar(
                    row: selected.row,
                    actions: _actionsFor(selected),
                  ),
                ],
              ]),
      ),
    );
  }

  List<Widget> _actionsFor(SalesReturnRecordEntry e) {
    final r = e.row;
    final view = returnRowActionButton(
      key: const Key('return_row_view'),
      icon: PhosphorIconsBold.eye,
      label: tr('عرض'),
      tint: AppColors.primary,
      onPressed: () => _view(e),
    );
    switch (r.status) {
      case ReturnRecordStatus.draft:
        return [
          view,
          returnRowActionButton(
            key: const Key('return_row_edit'),
            icon: PhosphorIconsBold.pencilSimple,
            label: tr('تعديل المسودة'),
            tint: AppColors.warning,
            onPressed: () => _openDraft(r.draftId!, approve: false),
          ),
          // ظاهرٌ دوماً ومعطَّلٌ بلا `sales_return_approve` — يقول ما ينقص.
          returnRowActionButton(
            key: const Key('return_row_approve'),
            icon: PhosphorIconsBold.checkCircle,
            label: tr('مراجعة واعتماد'),
            tint: AppColors.success,
            onPressed: watchReturnPermission(
                    ref, PermissionCodes.salesReturnApprove)
                ? () => _openDraft(r.draftId!, approve: true)
                : null,
          ),
          returnRowActionButton(
            key: const Key('return_row_delete'),
            icon: PhosphorIconsBold.trash,
            label: tr('حذف المسودة'),
            tint: AppColors.error,
            onPressed: () => _deleteDraft(r),
          ),
        ];
      case ReturnRecordStatus.posted:
        return [
          view,
          // نفسُ الحارسَين اللذين كانا في الحوار (`sales_return_print` و
          // `sales_return_delete`، بتجاوز مدير).
          postedReturnPrintButton(
            onPrint: () => reprintPostedReturn(
              originalInvoiceNumber: r.originalInvoiceNumber ?? '',
              returnTotal: r.total,
            ),
          ),
          if (e.originalInvoice != null)
            postedReturnCancelButton(onCancel: () => _cancel(e)),
        ];
      case ReturnRecordStatus.cancelled:
        return [view];
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
      _selectedKey = null;
    });
  }

  Future<void> _openNew() async {
    ref.read(salesReturnProvider.notifier).resetForm();
    await _push(const SalesReturnsPicposScreen(popOnDone: true));
  }

  Future<void> _openDraft(int draftId, {required bool approve}) => _push(
        SalesReturnsPicposScreen(
          draftId: draftId,
          approveOnOpen: approve,
          popOnDone: true,
        ),
      );

  Future<void> _push(Widget form) async {
    final result = await Navigator.of(context).push<ReturnFormResult>(
      MaterialPageRoute(builder: (_) => form),
    );
    if (!mounted) return;
    setState(() {
      if (result != null && result.posted) {
        _selectPostedInvoice = result.originalInvoiceId;
        _statusChip = 0;
        // المرتجعُ الجديدُ مؤرَّخٌ اليوم — يجب أن يقع في المدى.
        final now = DateTime.now();
        if (_to.isBefore(DateTime(now.year, now.month, now.day))) _to = now;
      }
    });
    _refresh();
  }

  Future<void> _deleteDraft(ReturnRecordRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف المسودة')),
        content: Text(tr('تُحذف المسودة {p0} — لم يتحرّك بها مخزونٌ ولا قيد.',
            {'p0': r.number})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('تراجع')),
          ),
          FilledButton(
            key: const Key('return_row_delete_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(tr('حذف')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(returnDraftsRepositoryProvider).deleteDraft(r.draftId!);
      if (!mounted) return;
      AppToast.show(context, tr('حُذفت المسودة'), type: ToastType.success);
      setState(() => _selectedKey = null);
      _refresh();
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }

  Future<void> _cancel(SalesReturnRecordEntry e) async {
    final invoice = e.originalInvoice;
    if (invoice == null) return;
    final cancelled = await cancelPostedReturn(
      originalInvoiceNumber: e.row.originalInvoiceNumber ?? invoice.invoiceNumber,
      returnAmount: e.row.total,
      invoice: invoice,
    );
    if (!cancelled || !mounted) return;
    try {
      await ref
          .read(returnDraftsRepositoryProvider)
          .markSalesCancelled(invoice.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _selectedKey = null);
    _refresh();
  }

  Future<void> _view(SalesReturnRecordEntry e) async {
    final r = e.row;
    // الأصنافُ المرتجعة للمعتمد/الملغى — مفتاحُها الفاتورةُ الأصل كما في
    // الحوار القديم (`stock_movements.reference_id`).
    List<Map<String, dynamic>> items = const [];
    if (r.status != ReturnRecordStatus.draft) {
      try {
        items = await ref
            .read(databaseProvider)
            .getSalesReturnItemDetails(r.originalInvoiceId);
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => PicPosDialog(
        title: tr('مرتجع مبيعات {p0}', {'p0': r.number}),
        subtitle: returnRecordDate(r.date),
        icon: PhosphorIconsBold.arrowUUpLeft,
        width: 620,
        cancelLabel: tr('إغلاق'),
        body: [
          Column(
            key: const Key('return_document_view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...returnRecordFields(r, partyLabel: tr('العميل')),
              if (items.isNotEmpty) ...[
                const Divider(height: 20),
                for (final item in items)
                  ReturnRecordField(
                    (item['product_name'] as String?) ??
                        tr('صنف #{p0}', {'p0': item['product_id']}),
                    '${(item['returned_qty'] as num?)?.toDouble() ?? 0} × '
                    '${returnRecordMoney((item['unit_cost'] as num?)?.toDouble() ?? 0)}',
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

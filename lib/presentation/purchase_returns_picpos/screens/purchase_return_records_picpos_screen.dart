import 'package:picpos_erp/core/i18n/tr.dart';
// شاشةُ **سجلّ مردودات المشتريات** — خ‑٩، ثمّ J2 (قرارُ المالك).
//
// ═══ ما كان، وما صار ═══
//
// مدخلُ «مرتجع المشتريات» كان يفتح **شاشةَ إنشاءٍ** مباشرةً: تختار فاتورةَ
// مشترياتٍ ثمّ تحدّد منها ما يُردّ. ولمطالعةِ ما مضى **حوارٌ** خلف زرٍّ في
// ترويستها — وذاك الحوارُ لا يعرض مردودات:
//
//   • يقرأ `purchase_invoices` ويرشّح على `status`، **فالصفُّ فاتورةٌ لا
//     مردود** — وثلاثةُ مردوداتٍ على فاتورةٍ تظهر صفّاً واحداً بمجموعها؛
//   • ومداه على **تاريخ الفاتورة**، فمردودُ اليوم على فاتورةٍ عمرُها سنتان
//     لا يظهر أبداً؛
//   • ولا `id` مردودٍ يُفتَح، فمرفقاتُ §٨ بلا مرساة.
//
// فصار المدخلُ يفتح السجلَّ من `purchase_returns` **بتاريخ المردود**،
// و«جديد» يدفع شاشةَ الإنشاء صفحةً.
//
// ═══ J2 ═══
//
// • شرائحُ الحالة: الكلّ · مسودة (`return_drafts`) · معتمد (`purchase_returns`)
//   · ملغى (مستندٌ أبطله مسارُ التعديل القائم `voidPurchaseReturnDocs`).
// • حوارُ «طباعة أو تعديل مرتجعٍ سابق» **سُحب** لصالح أفعال الصفّ: عرضٌ
//   وطباعةٌ (`purchases_return_print`) وتعديلُ المعتمد (`purchases_return_edit`)
//   بالمعالجات القائمة نفسِها (`PurchaseReturnRecordActionsState`)، وتعديلُ
//   المسوّدة واعتمادُها (`purchases_return_approve`) وحذفُها.
// • بعد الاعتماد تعود الاستمارةُ إلى هنا والصفُّ الجديدُ مختار.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/document_record_providers.dart';
import '../../../data/providers/return_records_providers.dart';
import '../../../domain/models/document_record.dart';
import '../../../domain/models/return_draft.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_attachments_panel.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../providers/purchase_return_provider.dart';
import '../../shared_widgets/return_draft_support.dart';
import '../../shared_widgets/return_records_view.dart';
import '../../widgets/permission_guard.dart';
import 'purchase_returns_picpos_screen.dart';

class PurchaseReturnRecordsPicPosScreen extends ConsumerStatefulWidget {
  const PurchaseReturnRecordsPicPosScreen({super.key});

  @override
  ConsumerState<PurchaseReturnRecordsPicPosScreen> createState() =>
      _PurchaseReturnRecordsPicPosScreenState();
}

class _PurchaseReturnRecordsPicPosScreenState
    extends PurchaseReturnRecordActionsState<PurchaseReturnRecordsPicPosScreen> {
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  final _searchController = TextEditingController();
  int _statusChip = 0;
  String? _selectedKey;

  /// بعد العودة من الاستمارة: اختيارُ أحدث مستندٍ لهذه الفاتورة متى ظهر.
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

  DateTime get _fromDay => DateTime(_from.year, _from.month, _from.day);

  // ⚠️ آخرُ اللحظة لا أوّلُها — وإلّا سقطت مردوداتُ اليوم من سجلّ اليوم.
  DateTime get _toEnd => DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999);

  @override
  Widget build(BuildContext context) {
    final filter = (
      from: _fromDay,
      to: _toEnd,
      search: _search.isEmpty ? null : _search,
    );
    final ReturnRecordWindow window = (from: _fromDay, to: _toEnd);
    // مستندٌ معتمدٌ جديدٌ (أو مُبطَلٌ بالتعديل) يغيّر المسوّداتِ والملغاة.
    ref.listen(purchaseReturnRecordsProvider(filter), (_, _) {
      ref.invalidate(purchaseReturnRecordExtrasProvider);
    });
    final async = ref.watch(purchaseReturnRecordsProvider(filter));
    final extrasAsync = ref.watch(purchaseReturnRecordExtrasProvider(window));
    final posted = async.asData?.value ?? const <PurchaseReturnRecord>[];
    final extras =
        extrasAsync.asData?.value ?? const PurchaseReturnRecordExtras();

    final rows = _rows(posted, extras);
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
    final selected =
        shown.where((r) => r.key == _selectedKey).firstOrNull;

    return PermissionGuard(
      // نفسُ كودِ الشاشة التي يفتحها — فلا دورٌ يفقد باباً كان يملكه.
      permission: PermissionCodes.purchasesReturnView,
      child: PicPosScreenScaffold(
        title: tr('مرتجع المشتريات'),
        subtitle: tr('سجلُّ ما رُدّ — واضغط «جديد» لتنفيذ ارتجاع'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        headerActions: [
          FilledButton.icon(
            key: const Key('return_records_new'),
            onPressed: _openForm,
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
          searchHint: tr('رقمُ الفاتورة · المورّد · السبب'),
        ),
        body: async.hasError
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.warning,
                title: tr('تعذّرت قراءةُ السجلّ'),
                hint: '${async.error}',
              )
            : ListView(children: [
                ReturnRecordsTable(
                  title: tr('المردوداتُ المحفوظة'),
                  rows: rows,
                  statusChip: _statusChip,
                  onStatusChip: (i) => setState(() {
                    _statusChip = i;
                    _selectedKey = null;
                  }),
                  selectedKey: _selectedKey,
                  onSelect: (k) => setState(() => _selectedKey = k),
                  partyLabel: tr('المورّد'),
                  loading: async.isLoading,
                  emptyLabel: tr('لا مردوداتٍ في هذا المدى'),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 10),
                  ReturnRecordActionBar(
                    row: selected,
                    actions: _actionsFor(selected, posted, extras),
                  ),
                ],
              ]),
      ),
    );
  }

  /// صفوفُ السجلّ: المعتمدُ من المستندات بأرقام سنداتها، والمسوّداتُ
  /// والملغاةُ من الإضافات (مرشَّحةً بالبحث في الذاكرة — البحثُ على المعتمد
  /// يصل الاستعلام).
  List<ReturnRecordRow> _rows(
    List<PurchaseReturnRecord> posted,
    PurchaseReturnRecordExtras extras,
  ) {
    // رقمُ PRET- لكلّ مستند: مستنداتُ الفاتورة (معتمدةً ومُبطَلة) بترتيب
    // إنشائها تقابل سنداتِها بترتيب كتابتها.
    final docsByInvoice = <int, List<({int id, bool posted})>>{};
    for (final r in posted) {
      docsByInvoice.putIfAbsent(r.originalInvoiceId, () => [])
          .add((id: r.id, posted: true));
    }
    for (final v in extras.voided) {
      docsByInvoice.putIfAbsent(v.originalInvoiceId, () => [])
          .add((id: v.documentId!, posted: false));
    }
    final voucherOf = <int, ReturnVoucherLegs>{};
    docsByInvoice.forEach((invoiceId, docs) {
      docs.sort((a, b) => a.id.compareTo(b.id));
      final legs = extras.vouchers[invoiceId] ?? const <ReturnVoucherLegs>[];
      for (var i = 0; i < docs.length && i < legs.length; i++) {
        voucherOf[docs[i].id] = legs[i];
      }
    });
    final out = <ReturnRecordRow>[
      for (final r in posted)
        purchaseRecordRow(
          r,
          ReturnRecordStatus.posted,
          number: voucherOf[r.id]?.voucher,
          settlement: voucherOf[r.id]?.settlement,
        ),
      for (final d in extras.drafts)
        if (d.matches(_search)) d,
      for (final v in extras.voided)
        if (v.matches(_search))
          ReturnRecordRow(
            key: v.key,
            status: v.status,
            number: voucherOf[v.documentId]?.voucher ?? v.number,
            date: v.date,
            originalInvoiceId: v.originalInvoiceId,
            originalInvoiceNumber: v.originalInvoiceNumber,
            partyName: v.partyName,
            reason: v.reason,
            settlement: voucherOf[v.documentId]?.settlement ?? v.settlement,
            tax: v.tax,
            total: v.total,
            isFullReturn: v.isFullReturn,
            documentId: v.documentId,
          ),
    ];
    out.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.key.compareTo(a.key);
    });
    return out;
  }

  List<Widget> _actionsFor(
    ReturnRecordRow r,
    List<PurchaseReturnRecord> posted,
    PurchaseReturnRecordExtras extras,
  ) {
    final view = returnRowActionButton(
      key: const Key('return_row_view'),
      icon: PhosphorIconsBold.eye,
      label: tr('عرض'),
      tint: AppColors.primary,
      onPressed: () => _showDocument(r, posted),
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
          // ظاهرٌ دوماً ومعطَّلٌ بلا `purchases_return_approve`.
          returnRowActionButton(
            key: const Key('return_row_approve'),
            icon: PhosphorIconsBold.checkCircle,
            label: tr('مراجعة واعتماد'),
            tint: AppColors.success,
            onPressed: watchReturnPermission(
                    ref, PermissionCodes.purchasesReturnApprove)
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
          returnRowActionButton(
            key: const Key('return_row_items'),
            icon: PhosphorIconsBold.package,
            label: tr('الأصناف المرتجعة'),
            tint: AppColors.primary,
            onPressed: () => _withInvoice(r, showPostedReturnItems),
          ),
          // purchases_return_print — نفسُ حارس الحوار القديم (بتجاوز مدير).
          PermissionGuard(
            permission: PermissionCodes.purchasesReturnPrint,
            allowManagerOverride: true,
            actionName: tr('طباعة مرتجع مشتريات'),
            onGranted: () => _withInvoice(r, reprintPostedReturn),
            child: OutlinedButton.icon(
              key: const Key('return_row_print'),
              onPressed: () => _withInvoice(r, reprintPostedReturn),
              icon: const Icon(PhosphorIconsBold.printer,
                  size: 15, color: AppColors.success),
              label: Text(tr('طباعة')),
            ),
          ),
          // ميزة ٠١٥ — تعديلُ مرتجعٍ مرحَّل (`purchases_return_edit`)؛ قفلُ
          // الفترة يفرضه `_editPurchaseReturn` نفسُه.
          PermissionGuard(
            permission: PermissionCodes.purchasesReturnEdit,
            child: OutlinedButton.icon(
              key: const Key('return_row_edit_posted'),
              onPressed: () => _withInvoice(r, (inv) async {
                await editPostedReturn(inv);
                ref.invalidate(purchaseReturnRecordExtrasProvider);
              }),
              icon: const Icon(PhosphorIconsBold.pencilSimple,
                  size: 15, color: AppColors.warning),
              label: Text(tr('تعديل المرتجع')),
            ),
          ),
        ];
      case ReturnRecordStatus.cancelled:
        return [view];
    }
  }

  Future<void> _withInvoice(
    ReturnRecordRow r,
    Future<void> Function(PurchaseInvoiceData) action,
  ) async {
    try {
      final invoice = await ref
          .read(returnDraftsRepositoryProvider)
          .getPurchaseInvoice(r.originalInvoiceId);
      if (invoice == null) {
        if (mounted) {
          AppToast.show(context, tr('الفاتورة الأصلية غير موجودة'),
              type: ToastType.error);
        }
        return;
      }
      await action(invoice);
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // مدىً مقلوبٌ يعيد صفراً دوماً ويبدو «لا بيانات».
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
      _selectedKey = null;
    });
  }

  void _showDocument(ReturnRecordRow r, List<PurchaseReturnRecord> posted) {
    final doc = posted.where((p) => p.id == r.documentId).firstOrNull;
    showDialog<void>(
      context: context,
      builder: (ctx) => PicPosDialog(
        title: tr('مردودُ فاتورة {p0}',
            {'p0': r.originalInvoiceNumber ?? r.originalInvoiceId}),
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
              ...returnRecordFields(r, partyLabel: tr('المورّد')),
              ReturnRecordField(tr('المدى'),
                  r.isFullReturn ? tr('ارتجاعٌ كامل') : tr('ارتجاعٌ جزئيّ')),
              if (doc != null) ...[
                ReturnRecordField(
                    tr('ما قبلَ الضريبة'), returnRecordMoney(doc.subtotal)),
                ReturnRecordField(tr('ضريبةُ المدخلات المردودة'),
                    returnRecordMoney(doc.tax)),
              ],
              // §٨ (v176) — **إشعارُ الخصم ورقةُ المردود لا ورقةُ الفاتورة**؛
              // فاللوحُ مرسًى على المستند نفسِه (لا للمسوّدة: لا مستندَ بعد).
              if (r.documentId != null) ...[
                const SizedBox(height: 12),
                PicPosAttachmentsPanel(
                  entityType: 'purchase_return',
                  entityId: r.documentId!,
                  attachedByUserId: ref.read(authProvider).user?.id,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// «جديد» يدفع شاشةَ الإنشاء صفحةً فوق السجلّ — لا يستبدله به.
  Future<void> _openForm() async {
    ref.read(purchaseReturnProvider.notifier).resetForm();
    await _push(const PurchaseReturnsPicposScreen(popOnDone: true));
  }

  Future<void> _openDraft(int draftId, {required bool approve}) => _push(
        PurchaseReturnsPicposScreen(
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
        final now = DateTime.now();
        if (_to.isBefore(DateTime(now.year, now.month, now.day))) _to = now;
      }
    });
    ref.invalidate(purchaseReturnRecordExtrasProvider);
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
      ref.invalidate(purchaseReturnRecordExtrasProvider);
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }
}

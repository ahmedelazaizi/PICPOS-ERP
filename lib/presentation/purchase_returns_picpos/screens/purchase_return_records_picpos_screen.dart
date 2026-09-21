// شاشةُ **سجلّ مردودات المشتريات** — خ‑٩.
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
// و«جديد» يدفع شاشةَ الإنشاء **كما هي بلا تعديلٍ في منطقها** (خ‑٩٫٧).
//
// ⚠️ **وحوارُ السجلّ القديم يبقى حيث هو**: هو مدخلُ **إعادةِ الطباعة**
//    (`purchases_return_print`) وشاشةُ الإنشاء تملكه، وسحبُه هنا يُسقط
//    مساراً قائماً. والقراءتان مختلفتان لا نسختان — راجع
//    `IReturnsRepository.watchPurchaseReturnRecords`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/document_record_providers.dart';
import '../../../domain/models/document_record.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_attachments_panel.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';
import 'purchase_returns_picpos_screen.dart';

final _money = NumberFormat('#,##0.${'0' * AppConstants.decimalPlaces}');
final _dateFmt = DateFormat('yyyy/MM/dd');

class PurchaseReturnRecordsPicPosScreen extends ConsumerStatefulWidget {
  const PurchaseReturnRecordsPicPosScreen({super.key});

  @override
  ConsumerState<PurchaseReturnRecordsPicPosScreen> createState() =>
      _PurchaseReturnRecordsPicPosScreenState();
}

class _PurchaseReturnRecordsPicPosScreenState
    extends ConsumerState<PurchaseReturnRecordsPicPosScreen> {
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  final _searchController = TextEditingController();

  /// شريحةُ طريقة الردّ — «الكلّ» · نقداً · بنكيّاً · على الحساب.
  int _methodChip = 0;
  static const _methods = <String?>[null, 'cash', 'bank', 'credit'];

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

  @override
  Widget build(BuildContext context) {
    final filter = (
      from: DateTime(_from.year, _from.month, _from.day),
      // ⚠️ آخرُ اللحظة لا أوّلُها — وإلّا سقطت مردوداتُ اليوم من سجلّ اليوم.
      to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
      search: _search.isEmpty ? null : _search,
    );
    final async = ref.watch(purchaseReturnRecordsProvider(filter));
    final all = async.asData?.value ?? const <PurchaseReturnRecord>[];
    final picked = _methods[_methodChip];
    final rows = picked == null
        ? all
        : [for (final r in all) if (r.refundMethod == picked) r];

    return PermissionGuard(
      // نفسُ كودِ الشاشة التي يفتحها — فلا دورٌ يفقد باباً كان يملكه.
      permission: PermissionCodes.purchasesReturnView,
      child: PicPosScreenScaffold(
        title: 'مرتجع المشتريات',
        subtitle: 'سجلُّ ما رُدّ — واضغط «جديد» لتنفيذ ارتجاع',
        icon: PhosphorIconsBold.arrowUUpLeft,
        headerActions: [
          FilledButton.icon(
            key: const Key('return_records_new'),
            onPressed: _openForm,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: const Text('جديد'),
          ),
        ],
        toolbar: _filters(),
        body: async.hasError
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.warning,
                title: 'تعذّرت قراءةُ السجلّ',
                hint: '${async.error}',
              )
            : ListView(children: [
                _table(rows, all: all, loading: async.isLoading),
              ]),
      ),
    );
  }

  Widget _filters() => PicPosFilterStrip(
        children: [
          PicPosFilterPill(
            key: const Key('return_records_from'),
            icon: PhosphorIconsBold.calendarBlank,
            label: 'من ${_dateFmt.format(_from)}',
            tabular: true,
            onTap: () => _pickDate(isFrom: true),
          ),
          PicPosFilterPill(
            key: const Key('return_records_to'),
            icon: PhosphorIconsBold.calendarCheck,
            label: 'إلى ${_dateFmt.format(_to)}',
            tabular: true,
            onTap: () => _pickDate(isFrom: false),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('return_records_search'),
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'رقمُ الفاتورة · المورّد · السبب',
                prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
              ),
            ),
          ),
        ],
      );

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
    });
  }

  Widget _table(
    List<PurchaseReturnRecord> rows, {
    required List<PurchaseReturnRecord> all,
    required bool loading,
  }) {
    final total = rows.fold<double>(0, (s, r) => s + r.total);
    // ⚠️ **وضريبةُ المدخلات المردودة تُجمَع على حدة**: هي الحقلُ الذي وُجد
    //    الجدولُ لأجله، وإخفاؤها يترك الدوريّةَ الضريبيّةَ بلا رقمٍ يُراجَع.
    final tax = rows.fold<double>(0, (s, r) => s + r.tax);

    return PicPosDataTable(
      title: 'المردوداتُ المحفوظة',
      subtitle: loading ? 'جارٍ القراءة…' : 'المعروضُ ${rows.length} مردوداً',
      // ⚠️ **العدُّ من غير المرشَّح** (`all`) لا من `rows`: لو عُدّ المرشَّحُ
      //    لقرأت كلُّ شريحةٍ نفسَ الرقم، فلا تقول شيئاً.
      chips: [
        for (var i = 0; i < _methods.length; i++)
          PicPosTableChip(
            label: _methods[i] == null
                ? 'الكلّ'
                : refundMethodLabelAr(_methods[i]!),
            count: '${_methods[i] == null ? all.length : all.where((r) => r.refundMethod == _methods[i]).length}',
            onTap: () => setState(() => _methodChip = i),
          ),
      ],
      selectedChip: _methodChip,
      columns: const [
        PicPosTableColumn('التاريخ', flex: 1.0),
        PicPosTableColumn('الفاتورة الأصل', flex: 1.2),
        PicPosTableColumn('المورّد', flex: 1.5),
        PicPosTableColumn('الردّ', flex: 0.9),
        PicPosTableColumn('الضريبة', flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn('الإجمالي', flex: 1.1, align: PicPosCellAlign.end),
      ],
      totals: [
        '',
        '',
        '',
        '',
        _money.format(tax),
        _money.format(total),
      ],
      emptyLabel: 'لا مردوداتٍ في هذا المدى',
      rows: [
        for (final r in rows)
          PicPosTableRow(
            onTap: () => _showDocument(r),
            cells: [
              PicPosTextCell(_dateFmt.format(r.returnDate)),
              PicPosTextCell(r.originalInvoiceNumber ?? '—',
                  sub: r.isFullReturn ? 'ارتجاعٌ كامل' : 'ارتجاعٌ جزئيّ',
                  bold: true),
              PicPosTextCell(r.supplierName ?? '—', sub: r.reason),
              PicPosPillCell(
                refundMethodLabelAr(r.refundMethod),
                r.refundMethod == 'credit' ? AppColors.info : AppColors.success,
              ),
              PicPosTextCell(_money.format(r.tax)),
              PicPosTextCell(_money.format(r.total)),
            ],
          ),
      ],
    );
  }

  void _showDocument(PurchaseReturnRecord r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => PicPosDialog(
        title: 'مردودُ فاتورة ${r.originalInvoiceNumber ?? r.originalInvoiceId}',
        subtitle: _dateFmt.format(r.returnDate),
        icon: PhosphorIconsBold.arrowUUpLeft,
        width: 620,
        cancelLabel: 'إغلاق',
        body: [
          Column(
            key: const Key('return_document_view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('تاريخُ المردود', _dateFmt.format(r.returnDate)),
              _field('المورّد', r.supplierName ?? '—'),
              _field('الفاتورةُ الأصل', r.originalInvoiceNumber ?? '—'),
              _field('المدى', r.isFullReturn ? 'ارتجاعٌ كامل' : 'ارتجاعٌ جزئيّ'),
              _field('طريقةُ الردّ', refundMethodLabelAr(r.refundMethod)),
              _field('ما قبلَ الضريبة', _money.format(r.subtotal)),
              _field('ضريبةُ المدخلات المردودة', _money.format(r.tax)),
              _field('الإجمالي', _money.format(r.total)),
              if ((r.reason ?? '').isNotEmpty) _field('السبب', r.reason!),
              const SizedBox(height: 12),
              // §٨ (v176) — **إشعارُ الخصم ورقةُ المردود لا ورقةُ الفاتورة**،
              // وهو ما كان وسمُ `purchase_returns_picpos_screen.dart` يقوله:
              // «يومَ تُبنى شاشةُ عرضٍ للمردود، التركيبُ سطران». وهذه هي.
              PicPosAttachmentsPanel(
                entityType: 'purchase_return',
                entityId: r.id,
                attachedByUserId: ref.read(authProvider).user?.id,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(label,
                  style: TextStyle(color: context.picposMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  /// يدفع شاشةَ الإنشاء القائمةَ **بلا تعديلٍ في منطقها** (خ‑٩٫٧).
  void _openForm() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PurchaseReturnsPicposScreen(),
      ),
    );
  }
}

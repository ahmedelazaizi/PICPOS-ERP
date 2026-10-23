import 'package:picpos_erp/core/i18n/tr.dart';
// شاشةُ **سجلّ السندات** — خ‑٩ (قبضاً وصرفاً).
//
// ═══ ما تغيّر، ولماذا ═══
//
// كان مدخلُ «سند قبض» في الشريط يفتح **استمارةَ إنشاءٍ** مباشرةً: لا سجلَّ،
// ولا سبيلَ لمطالعة سندٍ محفوظ، ولا مرساةً لمرفقاته (§٨). فصار المدخلُ
// يفتح السجلَّ، و«جديد» يدفع الاستمارةَ **كما هي بلا تعديلٍ في منطقها**.
//
// ═══ ⚠️ ملفٌّ واحدٌ لاتّجاهَين ═══
//
// القبضُ والصرفُ يختلفان في العنوان والأيقونة والاستمارة المدفوعة لا أكثر.
// ونسختان كانتا ستفترقان عند أوّل تعديلٍ في المرشِّحات — وهو عينُ ما يشرحه
// `voucherOpenInvoicesProvider` في هذا المسار نفسِه.
//
// ═══ ⚠️ والدفعُ لا التبديلُ في المكان ═══
//
// `PicPosPageHeader` يرسم زرَّ رجوعٍ من نفسه عند `Navigator.canPop`، و
// `finishVoucherSave` يُغلق الاستمارةَ المدفوعةَ بعد الحفظ فيعود المستخدمُ
// إلى سجلٍّ **فيه سندُه الجديد**. وهو مدخلٌ واحدٌ في الشريط وشاشةٌ واحدةٌ
// في مُبدِّل الشاشات: المدفوعُ يعيش في ملّاح القشرة المتداخل.

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
import 'payment_voucher_picpos_screen.dart';
import 'receipt_voucher_picpos_screen.dart';
import 'voucher_books_panel.dart';

/// تنسيقُ المال — خاناتُه من [AppConstants.decimalPlaces] لا مكتوبةً:
/// العملةُ الافتراضيّةُ هنا بثلاث خانات، وتثبيتُ اثنتَين يُخفي فلساً.
final _money = NumberFormat('#,##0.${'0' * AppConstants.decimalPlaces}');
final _dateFmt = DateFormat('yyyy/MM/dd');

class VoucherRecordsPicPosScreen extends ConsumerStatefulWidget {
  const VoucherRecordsPicPosScreen({super.key, required this.direction});

  final VoucherDirection direction;

  @override
  ConsumerState<VoucherRecordsPicPosScreen> createState() =>
      _VoucherRecordsPicPosScreenState();
}

class _VoucherRecordsPicPosScreenState
    extends ConsumerState<VoucherRecordsPicPosScreen> {
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  final _searchController = TextEditingController();

  /// شريحةُ النوع — «الكلّ» أو النقديُّ أو الشيك.
  ///
  /// 🔴 **وهي مرشِّحٌ لا زينة**: سندُ الشيك مستندٌ **بلا أثرٍ ماليّ** (قيدُه
  ///    يقع على الورقة التجاريّة)، فخلطُه بالنقد في نظرةٍ واحدةٍ يجعل
  ///    المجموعَ المرئيَّ أكبرَ ممّا دخل الخزنة فعلاً.
  int _kindChip = 0;

  /// E3 — تبويبُ «دفاتر السندات».
  bool _booksTab = false;

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

  bool get _isReceipt => widget.direction == VoucherDirection.receipt;

  @override
  Widget build(BuildContext context) {
    final filter = (
      from: DateTime(_from.year, _from.month, _from.day),
      // ⚠️ **آخرُ اللحظة لا أوّلُها**: `created_at` يحمل الساعةَ، و
      //    `to = اليوم 00:00` كان يُسقط كلَّ سندات اليوم من سجلّ اليوم.
      to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
      search: _search.isEmpty ? null : _search,
    );
    final async = ref.watch(
      voucherRecordsProvider((widget.direction, filter)),
    );
    final all = async.asData?.value ?? const <VoucherRecord>[];
    final rows = switch (_kindChip) {
      1 => [for (final r in all) if (!r.isCheque) r],
      2 => [for (final r in all) if (r.isCheque) r],
      _ => all,
    };

    return PermissionGuard(
      // نفسُ كودِ الاستمارة التي يفتحها — فلا دورٌ يفقد باباً كان يملكه.
      permission: PermissionCodes.treasuryView,
      child: PicPosScreenScaffold(
        title: widget.direction.displayLabel,
        subtitle: tr('سجلُّ ما حُفظ — واضغط «جديد» لتحرير سندٍ'),
        icon: _isReceipt
            ? PhosphorIconsBold.arrowCircleDown
            : PhosphorIconsBold.arrowCircleUp,
        headerActions: [
          // E3 — «دفاتر السندات» تبويبٌ داخل السجلّ.
          VoucherRecordsTabSwitch(
            booksTab: _booksTab,
            onChanged: (v) => setState(() => _booksTab = v),
          ),
          FilledButton.icon(
            key: const Key('voucher_records_new'),
            onPressed: _openForm,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label:  Text(tr('جديد')),
          ),
        ],
        toolbar: _booksTab ? null : _filters(context),
        body: _booksTab
            ? VoucherBooksPanel(type: widget.direction.txnType)
            : async.hasError
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.warning,
                title: tr('تعذّرت قراءةُ السجلّ'),
                hint: '${async.error}',
              )
            : ListView(
                children: [
                  _table(rows, loading: async.isLoading),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // المرشِّحات
  // ═══════════════════════════════════════════════════════════════════

  Widget _filters(BuildContext context) => PicPosFilterStrip(
        children: [
          PicPosFilterPill(
            key: const Key('voucher_records_from'),
            icon: PhosphorIconsBold.calendarBlank,
            label: tr('من {p0}', {'p0': _dateFmt.format(_from)}),
            tabular: true,
            onTap: () => _pickDate(isFrom: true),
          ),
          PicPosFilterPill(
            key: const Key('voucher_records_to'),
            icon: PhosphorIconsBold.calendarCheck,
            label: tr('إلى {p0}', {'p0': _dateFmt.format(_to)}),
            tabular: true,
            onTap: () => _pickDate(isFrom: false),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              key: const Key('voucher_records_search'),
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration:  InputDecoration(
                isDense: true,
                hintText: tr('رقمُ السند · البيان · الطرف'),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
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
        // ⚠️ مدىً مقلوبٌ يعيد صفراً دوماً ويبدو «لا بيانات» — فيُسحَب
        //    الطرفُ الآخرُ معه بدل أن يصمت.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // الجدول
  // ═══════════════════════════════════════════════════════════════════

  Widget _table(List<VoucherRecord> rows, {required bool loading}) {
    // 🔴 **المجموعُ للنقد وحدَه**: سندُ الشيك مستندٌ بلا أثرٍ ماليّ، وجمعُه
    //    مع النقد يُظهر في الخزنة مالاً لم يدخلها.
    final cash = [for (final r in rows) if (!r.isCheque) r];
    final cashTotal = cash.fold<double>(0, (s, r) => s + r.amount);

    return PicPosDataTable(
      title: tr('السنداتُ المحفوظة'),
      subtitle: loading
          ? tr('جارٍ القراءة…')
          : tr('المعروضُ {p0} — والمجموعُ للنقديّ وحدَه', {'p0': rows.length}),
      chips: [
        PicPosTableChip(
            label: tr('الكلّ'),
            count: '${rows.length}',
            onTap: () => setState(() => _kindChip = 0)),
        PicPosTableChip(
            label: tr('نقديّ'),
            count: '${cash.length}',
            onTap: () => setState(() => _kindChip = 1)),
        PicPosTableChip(
            label: tr('شيك'),
            count: '${rows.length - cash.length}',
            onTap: () => setState(() => _kindChip = 2)),
      ],
      selectedChip: _kindChip,
      columns:  [
        PicPosTableColumn(tr('رقم السند'), flex: 1.1),
        PicPosTableColumn(tr('التاريخ'), flex: 1.0),
        PicPosTableColumn(tr('الطرف'), flex: 1.5),
        PicPosTableColumn(tr('الخزنة'), flex: 1.1),
        PicPosTableColumn(tr('النوع'), flex: 0.8),
        PicPosTableColumn(tr('المبلغ'), flex: 1.1, align: PicPosCellAlign.end),
      ],
      totals: ['', '', '', '', tr('نقداً'), _money.format(cashTotal)],
      emptyLabel: tr('لا سنداتٍ في هذا المدى'),
      rows: [
        for (final r in rows)
          PicPosTableRow(
            onTap: () => _showDocument(r),
            cells: [
              PicPosTextCell(r.voucherNumber, bold: true),
              PicPosTextCell(_dateFmt.format(r.date)),
              PicPosTextCell(r.partyName ?? '—',
                  sub: voucherCategoryLabelAr(r.category)),
              PicPosTextCell(trData(r.safeName)),
              if (r.isCheque)
                 PicPosPillCell(tr('شيك'), AppColors.info)
              else
                 PicPosPillCell(tr('نقديّ'), AppColors.success),
              PicPosTextCell(_money.format(r.amount)),
            ],
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // المستندُ المحفوظُ — للقراءة
  // ═══════════════════════════════════════════════════════════════════

  void _showDocument(VoucherRecord r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => PicPosDialog(
        title: '${widget.direction.displayLabel} ${r.voucherNumber}',
        subtitle: _dateFmt.format(r.date),
        icon: r.isCheque
            ? PhosphorIconsBold.checkSquareOffset
            : PhosphorIconsBold.receipt,
        width: 620,
        cancelLabel: tr('إغلاق'),
        body: [
          Column(
            key: const Key('voucher_document_view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(tr('التاريخ'), _dateFmt.format(r.date)),
              _field(tr('الطرف'), r.partyName ?? '—'),
              _field(tr('الخزنة'), trData(r.safeName)),
              _field(tr('التصنيف'), voucherCategoryLabelAr(r.category)),
              _field(tr('المبلغ'), _money.format(r.amount)),
              if (r.discount > 0) _field(tr('الخصم'), _money.format(r.discount)),
              _field(tr('النوع'),
                  r.isCheque ? tr('شيك — مستندٌ بلا حركةِ نقد') : tr('نقديّ')),
              if ((r.description ?? '').isNotEmpty)
                _field(tr('البيان'), r.description!),
              const SizedBox(height: 12),
              // §٨ (v176) — **المرفقاتُ هنا لا في الاستمارة**: اللوحُ يشترط
              // رقمَ المستند وهُويّتَه، وهو أوّلُ موضعٍ في هذا المسار يعرض
              // سنداً **محفوظاً**. وقبلَه كان الوسمُ في
              // `voucher_form_picpos.dart` يقول «ينتظر شاشةَ عرض» — وهذه هي.
              //
              // ⚠️ و`entityType` يتبع الاتّجاهَ لا الجدول: الصفّان يعيشان في
              //    `safe_transactions`، فنوعٌ واحدٌ كان يخلط إيصالَ قبضٍ
              //    بإيصالِ صرف.
              PicPosAttachmentsPanel(
                entityType:
                    _isReceipt ? 'receipt_voucher' : 'payment_voucher',
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
              width: 110,
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

  // ═══════════════════════════════════════════════════════════════════

  /// يدفع الاستمارةَ القائمةَ **بلا تعديلٍ في منطقها** (خ‑٩٫٧).
  void _openForm() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _isReceipt
            ? const ReceiptVoucherPicposScreen()
            : const PaymentVoucherPicposScreen(),
      ),
    );
  }
}

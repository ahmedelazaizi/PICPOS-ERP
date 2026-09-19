// نموذجُ سندِ القبض والصرف — تصميمُ المالك `(11)` و`(12)` و`(13)`.
//
// ═══ ⚠️ ودجتٌ واحدةٌ للسندَين ═══
//
// التصميمُ يجعل سندَ القبض **توأمَ** سندِ الصرف: نفسُ الترويسة ونفسُ
// شريطِ الطريقة ونفسُ جدولِ الشيكات ونفسُ التذييل. والفرقُ ثلاثةُ أشياءَ لا
// أكثر: اسمُ الطرف (عميلٌ / مستفيد)، ولونُ الرأس، وحالةُ الشيك المعروضة
// (برسم التحصيل / صادر). فنسختان كانتا تفترقان عند أوّل تعديل.
//
// ═══ 🔴 ورقمُ السند لا يُخمَّن ═══
//
// التصميمُ يعرض `RV-0051` و`PV-0041`. والرقمُ يُولَّد **داخلَ معاملة الحفظ**
// (‏Spec 066)، فقبلها لا رقمَ موجود. ورقمٌ مخمَّنٌ على الشاشة يُنقَل إلى
// دفترٍ ورقيٍّ أو يُبلَّغ للعميل ثمّ يُحفَظ غيرُه.
//
// ═══ 🔴 ومبلغُ كلِّ شيكٍ يُكتَب ولا يُقسَّم ═══
//
// الحواران القائمان يجمعان **أرقامَ** الشيكات وحدَها ثمّ يقسّمان المبلغَ
// عليها بالتساوي:
//
//     final perCheck = amount / count;
//
// فثلاثةُ شيكاتٍ بـ١٠٠٠ و٢٠٠٠ و٣٠٠٠ تصير ٢٠٠٠ و٢٠٠٠ و٢٠٠٠ في
// `commercial_papers`. والمجموعُ صحيحٌ فلا شيءَ يبدو معطوباً — حتى يحين
// تحصيلُ أوّلِ شيك، فيُقيَّد بمبلغٍ لم يُكتَب على الورقة، ويبقى فرقٌ في
// حساب أوراق القبض إلى أن تُحصَّل الثلاثةُ كلُّها. ولو ارتدّ أحدُها ارتدّ
// بمبلغٍ مخترَع.
//
// ⇒ الجدولُ هنا يأخذ **مبلغَ كلّ شيكٍ** وتاريخَه وبنكَه، والإجماليُّ مجموعُها
//   لا العكس.
//
// ═══ ⚠️ و«حفظ مسودة» لا يُبنى ═══
//
// `createReceiptVoucher` و`createPaymentVoucher` **بلا `asDraft`**، و
// `SafeTransactions` بلا عمودِ حالةٍ أصلاً — لا مسوّدةَ في المحرّك. وهو عينُ
// ما حُسم في فاتورتَي المشتريات والمبيعات. وزرٌّ يُعرَض ويحفظ **مستنداً
// مُرحَّلاً** أسوأُ من غيابه: المستخدمُ يظنّ أنّه أجّل حركةَ مالٍ وقد وقعت.
//
// ═══ ⚠️ و«تفاصيل إضافية» تُسقَط ═══
//
// محتواها «ملاحظات ومرفقات»: الملاحظاتُ حقلٌ قائمٌ معروضٌ هنا، والمرفقاتُ
// مؤجَّلةٌ بقرار مالكٍ مستقلّ (ح‑٤).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_form_action_bar.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../picpos_shell/picpos_totals_bar.dart';
import '../../widgets/compact_date_picker.dart';

final _money = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd-MM-yyyy');

/// رقمُ السند قبل الحفظ — **لا يُخمَّن**. راجع رأسَ الملفّ (‏Spec 066).
const String kVoucherNumberPlaceholder = 'يُولَّد عند الحفظ';

enum PicPosVoucherKind { receipt, payment }

extension PicPosVoucherKindX on PicPosVoucherKind {
  bool get isReceipt => this == PicPosVoucherKind.receipt;

  String get title => isReceipt ? 'سند قبض' : 'سند صرف';

  /// اسمُ الطرف كما يسمّيه التصميم.
  String get partyLabel => isReceipt ? 'العميل' : 'المستفيد';

  String get methodLabel => isReceipt ? 'طريقة القبض' : 'طريقة الصرف';

  /// حالةُ الشيك المعروضةُ — **تُعرَض ولا تُحرَّر**.
  ///
  /// 🔴 المحرّكُ يُنشئ الورقةَ عند `pending` دائماً ويقيّد عندها قيدَ أوراق
  /// القبض/الدفع. وحقلٌ يُحرَّر كان يَعِد بحالةٍ لا يكتبها أحد.
  String get chequeStatusLabel => isReceipt ? 'برسم التحصيل' : 'صادر';

  Color get accent => isReceipt ? AppColors.success : AppColors.error;

  IconData get icon => isReceipt
      ? PhosphorIconsBold.arrowCircleDown
      : PhosphorIconsBold.arrowCircleUp;
}

typedef VoucherPartyOption = ({
  int id,
  String name,
  String? meta,
  bool isDeliveryCompany,
});

typedef VoucherSafeOption = ({int id, String name, String type});

typedef VoucherCostCenterOption = ({int id, String name});

/// فاتورةٌ مفتوحةٌ يجوز توزيعُ المبلغ عليها.
typedef VoucherInvoiceOption = ({
  /// `sales` أو `purchase`.
  String invoiceType,
  int id,
  String number,
  DateTime date,
  double total,
  double paid,
});

/// شيكٌ واحدٌ في السند — **بمبلغه**، راجع رأسَ الملفّ.
class VoucherChequeDraft {
  VoucherChequeDraft();

  final numberCtrl = TextEditingController();
  final bankCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  DateTime? dueDate;

  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0;

  void dispose() {
    numberCtrl.dispose();
    bankCtrl.dispose();
    amountCtrl.dispose();
  }
}

/// ما يخرج من النموذج عند الاعتماد.
typedef VoucherSubmission = ({
  PicPosVoucherKind kind,
  int? partyId,
  DateTime date,
  String method,
  int? safeId,
  int? costCenterId,
  double grossAmount,
  double discount,
  double commissionPercent,
  String notes,
  List<({String number, String bank, DateTime? dueDate, double amount})> cheques,
  bool depositImmediately,
  List<({String invoiceType, int invoiceId, double amount})> allocations,
});

class PicPosVoucherForm extends StatefulWidget {
  const PicPosVoucherForm({
    super.key,
    required this.kind,
    required this.parties,
    required this.safes,
    required this.costCenters,
    required this.openInvoices,
    required this.onSubmit,
    this.onCancel,
    this.onPartyPicked,
    this.initialPartyId,
    this.busy = false,
  });

  final PicPosVoucherKind kind;
  final List<VoucherPartyOption> parties;
  final List<VoucherSafeOption> safes;
  final List<VoucherCostCenterOption> costCenters;

  /// فواتيرُ الطرف المختار — تُحدَّث من المضيف عند تبديل الطرف.
  final List<VoucherInvoiceOption> openInvoices;

  final Future<void> Function(VoucherSubmission) onSubmit;
  final VoidCallback? onCancel;

  /// يُبلَّغ المضيفُ بتبديل الطرف — فواتيرُه تُقرأ عنده لا هنا.
  final ValueChanged<int?>? onPartyPicked;

  final int? initialPartyId;
  final bool busy;

  @override
  State<PicPosVoucherForm> createState() => PicPosVoucherFormState();
}

class PicPosVoucherFormState extends State<PicPosVoucherForm> {
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String _method = 'cash';
  int? _partyId;
  int? _safeId;
  int? _costCenterId;
  bool _depositImmediately = false;
  bool _allocationOpen = false;

  final List<VoucherChequeDraft> _cheques = [VoucherChequeDraft()];

  /// المخصَّصُ لكلّ فاتورة — بمفتاح `نوع#رقم`.
  final Map<String, TextEditingController> _allocCtrls = {};

  @override
  void initState() {
    super.initState();
    _partyId = widget.initialPartyId;
    final def = widget.safes.where((s) => s.type == 'cash').firstOrNull ??
        widget.safes.firstOrNull;
    _safeId = def?.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    _commissionCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _cheques) {
      c.dispose();
    }
    for (final c in _allocCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الحساب
  // ═══════════════════════════════════════════════════════════════════════

  bool get _isCheque => _method == 'check';

  VoucherPartyOption? get _party =>
      widget.parties.where((p) => p.id == _partyId).firstOrNull;

  /// مجموعُ الشيكات — **الإجماليُّ مشتقٌّ منها لا العكس**.
  double get _chequesTotal =>
      _cheques.fold<double>(0, (s, c) => s + c.amount);

  double get _grossAmount => _isCheque
      ? _chequesTotal
      : (double.tryParse(_amountCtrl.text.trim()) ?? 0);

  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;

  double get _commissionPercent =>
      double.tryParse(_commissionCtrl.text.trim()) ?? 0;

  bool get _isDeliveryCompany => _party?.isDeliveryCompany == true;

  double get _commissionAmount =>
      _isDeliveryCompany ? _grossAmount * (_commissionPercent / 100) : 0;

  double get _netAmount => _grossAmount - _discount - _commissionAmount;

  double _allocatedFor(VoucherInvoiceOption inv) =>
      double.tryParse(_allocCtrls[_key(inv)]?.text.trim() ?? '') ?? 0;

  double get _allocatedTotal => widget.openInvoices
      .fold<double>(0, (s, inv) => s + _allocatedFor(inv));

  String _key(VoucherInvoiceOption inv) => '${inv.invoiceType}#${inv.id}';

  /// سببُ منعِ الاعتماد — أو `null` إن جاز.
  ///
  /// ⚠️ **يُعرَض ولا يُبتلَع**: زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب».
  String? get blockReason {
    if (_partyId == null) return 'اختر ${widget.kind.partyLabel}.';
    if (_safeId == null) return 'اختر الخزينة.';
    // ⚠️ مراكزُ التكلفة حين تكون معرَّفةً **إلزاميّة**: بدونها يسقط القيدُ
    //    على «عام» ويُقرأ في تقارير المراكز على غير موضعه.
    if (widget.costCenters.isNotEmpty && _costCenterId == null) {
      return 'اختر مركز التكلفة.';
    }
    if (_isCheque) {
      for (var i = 0; i < _cheques.length; i++) {
        final c = _cheques[i];
        if (c.numberCtrl.text.trim().isEmpty) {
          return 'الشيك ${i + 1}: اكتب رقمه.';
        }
        // 🔴 مبلغٌ صفرٌ يعني قسمةً بالتساوي في المسار القديم — وهنا يُرفَض.
        if (c.amount <= 0) return 'الشيك ${i + 1}: اكتب مبلغه.';
        if (c.dueDate == null) return 'الشيك ${i + 1}: اختر تاريخ استحقاقه.';
      }
    }
    if (_grossAmount <= 0) return 'أدخل مبلغاً أكبر من صفر.';
    if (_discount < 0) return 'الخصم لا يكون سالباً.';
    if (_commissionPercent < 0 || _commissionPercent > 100) {
      return 'نسبة العمولة بين صفر ومئة.';
    }
    if (_netAmount <= 0) return 'صافي المبلغ يجب أن يكون أكبر من صفر.';
    // 🔴 التوزيعُ لا يتجاوز الصافي: تخصيصٌ أكبرُ يُقفل فواتيرَ بمالٍ لم يُقبَض.
    if (_allocatedTotal > _netAmount + 0.001) {
      return 'التوزيع (${_money.format(_allocatedTotal)}) يتجاوز الصافي '
          '(${_money.format(_netAmount)}).';
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final reason = blockReason;
    return PicPosScreenScaffold(
      title: widget.kind.title,
      // 🔴 لا رقمَ قبل الحفظ — راجع رأسَ الملفّ.
      subtitle: 'رقم السند: $kVoucherNumberPlaceholder',
      icon: widget.kind.icon,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  if (_isCheque) _chequesCard() else _cashCard(),
                  const SizedBox(height: 12),
                  _allocationCard(),
                  const SizedBox(height: 12),
                  PicPosTotalsBar(items: [
                    PicPosTotal(
                      label: 'الإجمالي',
                      value: _money.format(_grossAmount),
                    ),
                    if (_isDeliveryCompany)
                      PicPosTotal(
                        label: 'العمولة',
                        value: _money.format(_commissionAmount),
                      ),
                    PicPosTotal(
                      label: 'الخصم',
                      value: _money.format(_discount),
                    ),
                    PicPosTotal(
                      label: 'الصافي',
                      value: _money.format(_netAmount),
                      emphasis: true,
                      tone: widget.kind.accent,
                    ),
                  ]),
                ],
              ),
            ),
          ),
          PicPosFormActionBar(
            onBack: widget.busy ? null : widget.onCancel,
            backLabel: 'رجوع',
            busy: widget.busy,
            hint: reason ?? 'يُرحَّل السندُ فورَ الاعتماد',
            // ⚠️ **لا زرَّ مسوّدة** — راجع رأسَ الملفّ: لا حالةَ مسوّدةٍ في
            //    المحرّك، وزرٌّ يحفظ مُرحَّلاً وهو يقول «مسودة» أسوأُ من غيابه.
            primary: PicPosFormAction(
              label: 'مراجعة واعتماد',
              icon: PhosphorIconsBold.check,
              onPressed:
                  (widget.busy || reason != null) ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PicPosSectionHeader(
              icon: PhosphorIconsBold.info,
              title: 'بيانات ${widget.kind.title}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(width: 220, child: _partyField()),
                SizedBox(width: 190, child: _dateField()),
                SizedBox(width: 200, child: _costCenterField()),
              ],
            ),
            const SizedBox(height: 12),
            _methodSegments(),
            const SizedBox(height: 10),
            TextField(
              key: const Key('voucher_notes'),
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'البيان',
                hintText: 'اختياري',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _partyField() => DropdownButtonFormField<int>(
        key: const Key('voucher_party'),
        initialValue: _partyId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: widget.kind.partyLabel,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final p in widget.parties)
            DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (v) {
          setState(() {
            _partyId = v;
            // تبديلُ الطرف يُبطل توزيعاً بُني على فواتيرِ غيرِه.
            for (final c in _allocCtrls.values) {
              c.clear();
            }
          });
          widget.onPartyPicked?.call(v);
        },
      );

  Widget _dateField() => InkWell(
        onTap: () async {
          final picked = await CompactDatePicker.showCompact(
            context,
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) setState(() => _date = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'التاريخ',
            isDense: true,
            border: OutlineInputBorder(),
            prefixIcon: Icon(PhosphorIconsBold.calendar, size: 15),
          ),
          child: Text(_dateFmt.format(_date)),
        ),
      );

  Widget _costCenterField() => DropdownButtonFormField<int>(
        key: const Key('voucher_cost_center'),
        initialValue: _costCenterId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'مركز التكلفة',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final c in widget.costCenters)
            DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (v) => setState(() => _costCenterId = v),
      );

  Widget _methodSegments() {
    const methods = <({String value, String label, IconData icon})>[
      (value: 'cash', label: 'نقدي', icon: PhosphorIconsBold.money),
      (value: 'bank', label: 'بنك', icon: PhosphorIconsBold.bank),
      (value: 'check', label: 'شيكات', icon: PhosphorIconsBold.creditCard),
    ];
    return Row(
      children: [
        for (final m in methods)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: OutlinedButton.icon(
                key: Key('voucher_method_${m.value}'),
                onPressed: () => setState(() => _method = m.value),
                icon: Icon(m.icon, size: 15),
                label: Text(m.label),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _method == m.value
                      ? widget.kind.accent.withValues(alpha: 0.12)
                      : null,
                  foregroundColor:
                      _method == m.value ? widget.kind.accent : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cashCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PicPosSectionHeader(
              icon: PhosphorIconsBold.wallet,
              title: widget.kind.methodLabel,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(width: 230, child: _safeField()),
                SizedBox(
                  width: 170,
                  child: TextField(
                    key: const Key('voucher_amount'),
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (widget.kind.isReceipt) ...[
                  SizedBox(
                    width: 170,
                    child: TextField(
                      key: const Key('voucher_discount'),
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'خصم سداد معجَّل',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  // ⚠️ **العمولةُ لشركات التوصيل وحدَها**: حقلٌ يُعرَض لكلّ
                  //    عميلٍ كان يُغري بخصمٍ لا مقابلَ له في العقد.
                  if (_isDeliveryCompany)
                    SizedBox(
                      width: 170,
                      child: TextField(
                        key: const Key('voucher_commission'),
                        controller: _commissionCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'عمولة التوصيل ٪',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      );

  Widget _safeField() => DropdownButtonFormField<int>(
        key: const Key('voucher_safe'),
        initialValue: _safeId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'الخزينة',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final s in widget.safes)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (v) => setState(() => _safeId = v),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // الشيكات
  // ═══════════════════════════════════════════════════════════════════════

  Widget _chequesCard() => PicPosContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: PicPosSectionHeader(
                    icon: PhosphorIconsBold.creditCard,
                    title: 'الشيكات',
                  ),
                ),
                TextButton.icon(
                  key: const Key('voucher_add_cheque'),
                  onPressed: () =>
                      setState(() => _cheques.add(VoucherChequeDraft())),
                  icon: const Icon(PhosphorIconsBold.plus, size: 14),
                  label: const Text('إضافة شيك'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(width: 230, child: _safeField()),
            const SizedBox(height: 8),
            for (var i = 0; i < _cheques.length; i++) _chequeRow(i),
            const SizedBox(height: 4),
            if (widget.kind.isReceipt)
              // 🔴 **مربّعٌ يُنفّذ انتقالاً بقيده، لا وسمٌ على الورقة.**
              //    المحرّكُ يُنشئ الشيكَ عند `pending` ويقيّد أوراقَ القبض،
              //    والإيداعُ حالةٌ تاليةٌ لها قيدُها. وزيفُها عند الإنشاء
              //    كان يُظهر الشيكَ محصَّلاً وهو في الدرج.
              CheckboxListTile(
                key: const Key('voucher_deposit_now'),
                value: _depositImmediately,
                onChanged: (v) =>
                    setState(() => _depositImmediately = v ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('أودِعه للتحصيل فوراً'),
                subtitle: const Text(
                  'يُنشأ الشيكُ برسم التحصيل ثمّ يُنقَل إلى «أودِع» بقيده',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      );

  Widget _chequeRow(int i) {
    final c = _cheques[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
        // ⚠️ `picposHairline` لا `AppColors.border`: الثاني لونُ الوضع
        //    الفاتح وحدَه فيبقى فاتحاً في الغامق ويترك خطّاً أبيض.
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('شيك ${i + 1}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              // حالةٌ تُعرَض ولا تُحرَّر — راجع `chequeStatusLabel`.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.kind.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(widget.kind.chequeStatusLabel,
                    style: TextStyle(
                        fontSize: 10, color: widget.kind.accent)),
              ),
              const Spacer(),
              IconButton(
                tooltip: _cheques.length > 1
                    ? 'حذف الشيك'
                    : 'لا يقلّ السندُ عن شيكٍ واحد',
                onPressed: _cheques.length > 1
                    ? () => setState(() => _cheques.removeAt(i).dispose())
                    : null,
                icon: const Icon(PhosphorIconsBold.trash,
                    size: 14, color: AppColors.error),
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: c.numberCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'رقم الشيك',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: c.bankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البنك',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: InkWell(
                  onTap: () async {
                    final picked = await CompactDatePicker.showCompact(
                      context,
                      initialDate: c.dueDate ??
                          DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setState(() => c.dueDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الاستحقاق',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    child: Text(c.dueDate == null
                        ? 'اختر التاريخ'
                        : _dateFmt.format(c.dueDate!)),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: c.amountCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // توزيعُ المبلغ على الفواتير
  // ═══════════════════════════════════════════════════════════════════════

  Widget _allocationCard() {
    final invoices = widget.openInvoices;
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('voucher_allocation_toggle'),
            onTap: () => setState(() => _allocationOpen = !_allocationOpen),
            child: Row(
              children: [
                const Expanded(
                  child: PicPosSectionHeader(
                    icon: PhosphorIconsBold.receipt,
                    title: 'توزيع المبلغ على الفواتير',
                  ),
                ),
                if (_allocatedTotal > 0)
                  Text(_money.format(_allocatedTotal),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.kind.accent)),
                const SizedBox(width: 6),
                Icon(
                  _allocationOpen
                      ? PhosphorIconsBold.caretUp
                      : PhosphorIconsBold.caretDown,
                  size: 14,
                ),
              ],
            ),
          ),
          if (_allocationOpen) ...[
            const SizedBox(height: 8),
            if (_partyId == null)
              Text('اختر ${widget.kind.partyLabel} أوّلاً.',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted))
            else if (invoices.isEmpty)
              const Text(
                'لا فواتيرَ مفتوحةً لهذا الطرف — ويُحفَظ السندُ على حسابه '
                'بلا توزيع.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              )
            else
              for (final inv in invoices) _allocationRow(inv),
            if (invoices.isNotEmpty) ...[
              const SizedBox(height: 6),
              // ⚠️ **التوزيعُ اختياريٌّ لا إلزاميّ**: سندٌ على الحساب بلا
              //    فاتورةٍ بعينها حالةٌ مشروعةٌ تماماً (دفعةٌ تحت الحساب).
              const Text(
                'التوزيع اختياريّ — وما لا يُوزَّع يبقى على حساب الطرف.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _allocationRow(VoucherInvoiceOption inv) {
    final remaining = inv.total - inv.paid;
    final ctrl = _allocCtrls.putIfAbsent(_key(inv), TextEditingController.new);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inv.number,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                  '${_dateFmt.format(inv.date)} · الباقي '
                  '${_money.format(remaining)}',
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextField(
              key: Key('voucher_alloc_${_key(inv)}'),
              controller: ctrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'المخصَّص',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            // «الباقي» — أكثرُ ما يُكتَب، ويمنع تجاوزَ الفاتورة بالكتابة اليدويّة.
            onPressed: () => setState(
                () => ctrl.text = remaining.toStringAsFixed(2)),
            child: const Text('الباقي'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final allocations =
        <({String invoiceType, int invoiceId, double amount})>[];
    for (final inv in widget.openInvoices) {
      final a = _allocatedFor(inv);
      if (a > 0) {
        allocations.add(
            (invoiceType: inv.invoiceType, invoiceId: inv.id, amount: a));
      }
    }
    await widget.onSubmit((
      kind: widget.kind,
      partyId: _partyId,
      date: _date,
      method: _method,
      safeId: _safeId,
      costCenterId: _costCenterId,
      grossAmount: _grossAmount,
      discount: _discount,
      commissionPercent: _isDeliveryCompany ? _commissionPercent : 0,
      notes: _notesCtrl.text.trim(),
      cheques: [
        if (_isCheque)
          for (final c in _cheques)
            (
              number: c.numberCtrl.text.trim(),
              bank: c.bankCtrl.text.trim(),
              dueDate: c.dueDate,
              amount: c.amount,
            ),
      ],
      depositImmediately: _isCheque && _depositImmediately,
      allocations: allocations,
    ));
  }
}

import 'package:picpos_erp/core/i18n/tr.dart';
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
// ═══ ⚠️ و«تفاصيل إضافية»: الملاحظاتُ هنا، والمرفقاتُ لا ═══
//
// محتواها «ملاحظات ومرفقات». والملاحظاتُ حقلٌ قائمٌ معروضٌ هنا.
//
// 🔴 **وأمّا المرفقاتُ فبُنيت في v176 (§٨) ولم تُركَّب هنا — والسببُ
// بنيويٌّ لا تأجيل:** هذه **استمارةُ إنشاءٍ لا شاشةُ عرض**. السندُ لا
// يوجد قبل الحفظ، فلا رقمَ له ولا هُويّةَ عالميّة — و`PicPosAttachmentsPanel`
// يشترطهما (المرفقُ يُربَط بهُويّة المستند لأنّ الرقمَ المحلّيَّ لا يعبر
// الأجهزة). فاللوحُ هنا لن يقول غيرَ «احفظ السندَ أوّلاً» ثمّ تُغلَق
// الاستمارةُ بالحفظ.
//
// ⚠️ **وما ينقص هو شاشةُ عرضٍ لسندٍ محفوظ** — لا يوجد في المستودع اليومَ
// موضعٌ يُفتَح فيه `safe_transactions` صفّاً واحداً للمطالعة. ويومَ يوجد،
// التركيبُ سطران: `entityType: 'receipt_voucher'` أو `'payment_voucher'`
// و`entityId` من الصفّ. والنوعان **مُعرَّفان أصلاً** في
// `kAttachmentEntities` — البنيةُ جاهزةٌ والمنفذُ مفتوح.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/cheque_book_plan.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_form_action_bar.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../picpos_shell/picpos_totals_bar.dart';
import '../../widgets/compact_date_picker.dart';
import '../widgets/voucher_form_parts.dart';

export '../widgets/voucher_form_parts.dart'
    show VoucherAccountOption, VoucherBookOption;

final _money = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd-MM-yyyy');

/// رقمُ السند قبل الحفظ — **لا يُخمَّن**. راجع رأسَ الملفّ (‏Spec 066).
String get kVoucherNumberPlaceholder => tr('يُولَّد عند الحفظ');

enum PicPosVoucherKind { receipt, payment }

extension PicPosVoucherKindX on PicPosVoucherKind {
  bool get isReceipt => this == PicPosVoucherKind.receipt;

  String get title => isReceipt ? tr('سند قبض') : tr('سند صرف');

  /// اسمُ الطرف كما يسمّيه التصميم.
  String get partyLabel => isReceipt ? tr('العميل') : tr('المستفيد');

  String get methodLabel => isReceipt ? tr('طريقة القبض') : tr('طريقة الصرف');

  /// حالةُ الشيك المعروضةُ — **تُعرَض ولا تُحرَّر**.
  ///
  /// 🔴 المحرّكُ يُنشئ الورقةَ عند `pending` دائماً ويقيّد عندها قيدَ أوراق
  /// القبض/الدفع. وحقلٌ يُحرَّر كان يَعِد بحالةٍ لا يكتبها أحد.
  String get chequeStatusLabel => isReceipt ? tr('برسم التحصيل') : tr('صادر');

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

/// دفترُ شيكاتٍ يجوز السحبُ منه — **لسند الصرف وحدَه**.
///
/// ⚠️ الواردُ يأتي من دفتر الطرف الآخر، ولا دفترَ لنا يضبطه — فلا منتقيَ
///    في سند القبض.
typedef VoucherChequeBookOption = ({
  int id,
  String label,
  String? prefix,
  int nextNumber,
  int toNumber,
  int remaining,
});

/// شيكٌ واحدٌ في السند — **بمبلغه**، راجع رأسَ الملفّ.
class VoucherChequeDraft {
  VoucherChequeDraft();

  final numberCtrl = TextEditingController();
  final bankCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  /// E4 — الساحب (للشيك الوارد).
  final drawerCtrl = TextEditingController();

  /// E-fix ٢ (v186) — الساحبُ (وارد) / المستفيدُ (صادر) من دليل الحسابات.
  int? drawerAccountId;
  DateTime? dueDate;

  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0;

  void dispose() {
    numberCtrl.dispose();
    bankCtrl.dispose();
    amountCtrl.dispose();
    drawerCtrl.dispose();
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
  List<({String number, String bank, DateTime? dueDate, double amount, String drawer, int? drawerAccountId})> cheques,
  bool depositImmediately,
  List<({String invoiceType, int invoiceId, double amount})> allocations,

  /// الدفترُ المختارُ — و`null` يعني رقماً مكتوباً بيد.
  ///
  /// 🔴 **والأرقامُ في [cheques] معاينةٌ لا حجز** حين يكون هذا غيرَ فارغ:
  ///    المضيفُ يسحبها بـ`allocateChequeNumbers` داخلَ معاملةٍ ويستعمل ما
  ///    تُرجعه هي. وجهازٌ آخرُ قد يكون سحب في اللحظة نفسِها.
  int? chequeBookId,

  /// E2 — المستفيدُ من دليل الحسابات حين لا يكون حسابَ طرف.
  int? beneficiaryAccountId,

  /// E2 — حسابُ الخزينة من الدليل؛ و[safeId] `null` معه = تحويلٌ محاسبيّ.
  int? treasuryAccountId,

  /// E3 — دفترُ السندات ورقمُ الورقة.
  int? bookId,
  int? bookNumber,
});

/// يُنهي سنداً **حُفظ بنجاح**: يُغلق الاستمارةَ إن كانت مدفوعةً، وإلّا
/// يطلب من المضيف تجديدَها. يُرجع `true` حين وجب التجديد.
///
/// ═══ 🔴 ولماذا لا يكفي `Navigator.maybePop` وحدَها ═══
///
/// سندا القبض والصرف يُبلَغان من الشريط الجانبيّ، فجسمُهما هو **المسارُ
/// الأوّل** في ملّاح القشرة المتداخل (`appShellNestedNavigatorKey`).
/// و`maybePop` على المسار الأوّل تُرجع `false` ولا تفعل شيئاً — فكان السندُ
/// يُكتَب، وتخرج رسالةُ النجاح، **وتبقى الاستمارةُ ممتلئةً كما هي**:
/// ضغطةٌ ثانيةٌ على «مراجعة واعتماد» تكتب سنداً ثانياً مطابقاً، ولا شيءَ في
/// المحرّك يردّه فهو سندٌ مشروعٌ تماماً من وجهة نظره.
///
/// وهو عينُ ما تقوله `_resetForm` في `journal_voucher_picpos_screen.dart`
/// حرفيّاً: «نموذجٌ نظيفٌ بعد الحفظ — وإلّا رُحِّل القيدُ نفسُه مرّتين».
///
/// ⚠️ **ودالّةٌ واحدةٌ لا نسختان في الشاشتَين**: `voucherOpenInvoicesProvider`
///    في هذا المسار نفسِه يحمل شرحاً لنسختَين افترقتا عند أوّل تعديل.
bool finishVoucherSave(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return false;
  }
  return true;
}

class PicPosVoucherForm extends StatefulWidget {
  const PicPosVoucherForm({
    super.key,
    required this.kind,
    required this.parties,
    required this.safes,
    required this.costCenters,
    required this.openInvoices,
    required this.onSubmit,
    this.chequeBooks = const [],
    this.onCancel,
    this.onPartyPicked,
    this.initialPartyId,
    this.busy = false,
    this.accounts = const [],
    this.voucherBooks = const [],
    this.initialBookId,
  });

  /// E2 — حين يُمرَّر: المستفيدُ والخزينةُ يُختاران من دليل الحسابات.
  final List<VoucherAccountOption> accounts;

  /// E3 — دفاترُ السندات السارية لهذا النوع، و[initialBookId] دفترُ المستخدم.
  final List<VoucherBookOption> voucherBooks;
  final int? initialBookId;

  final PicPosVoucherKind kind;
  final List<VoucherPartyOption> parties;
  final List<VoucherSafeOption> safes;
  final List<VoucherCostCenterOption> costCenters;

  /// فواتيرُ الطرف المختار — تُحدَّث من المضيف عند تبديل الطرف.
  final List<VoucherInvoiceOption> openInvoices;

  /// دفاترُ الشيكات السارية — **لسند الصرف وحدَه**، وفارغةٌ في القبض.
  final List<VoucherChequeBookOption> chequeBooks;

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

  /// الدفترُ المختار — `null` يعني رقماً مكتوباً بيد.
  int? _chequeBookId;

  VoucherChequeBookOption? get _pickedBook => _chequeBookId == null
      ? null
      : widget.chequeBooks.where((b) => b.id == _chequeBookId).firstOrNull;

  /// الرقمُ الذي **سيُسحَب** للشيك رقم [i] — معاينةٌ لا حجز.
  String _previewChequeNumber(VoucherChequeBookOption b, int i) =>
      formatChequeNumber(
          prefix: b.prefix, number: b.nextNumber + i, toNumber: b.toNumber);

  /// المخصَّصُ لكلّ فاتورة — بمفتاح `نوع#رقم`.
  final Map<String, TextEditingController> _allocCtrls = {};

  // ── E2 — طرفا السند من دليل الحسابات ──
  int? _beneficiaryAccountId;
  int? _treasuryAccountId;

  // ── E3 — دفترُ السندات ──
  int? _bookId;
  final _bookNumberCtrl = TextEditingController();

  bool get _useAccounts => widget.accounts.isNotEmpty;

  /// طرفُ الخزينة حسابٌ ليس خزنة ⇒ تحويلٌ محاسبيٌّ بلا حركة خزنة.
  bool get _isTransfer =>
      _useAccounts && !_isCheque && _treasuryAccountId != null && _safeId == null;

  VoucherBookOption? get _pickedVoucherBook =>
      widget.voucherBooks.where((b) => b.id == _bookId).firstOrNull;

  int? get _bookNumber => int.tryParse(_bookNumberCtrl.text.trim());

  @override
  void initState() {
    super.initState();
    _partyId = widget.initialPartyId;
    final def = widget.safes.where((s) => s.type == 'cash').firstOrNull ??
        widget.safes.firstOrNull;
    _safeId = def?.id;
    if (_useAccounts && _safeId != null) {
      _treasuryAccountId =
          widget.accounts.where((a) => a.safeId == _safeId).firstOrNull?.id;
    }
    _pickBook(widget.voucherBooks.any((b) => b.id == widget.initialBookId)
        ? widget.initialBookId
        : null);
  }

  void _pickBook(int? id) {
    _bookId = id;
    final suggested = _pickedVoucherBook?.suggested;
    _bookNumberCtrl.text = suggested?.toString() ?? '';
  }

  @override
  void dispose() {
    _bookNumberCtrl.dispose();
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
    if (_partyId == null && _beneficiaryAccountId == null) {
      return tr('اختر {p0}.', {'p0': widget.kind.partyLabel});
    }
    if (_safeId == null && _treasuryAccountId == null) {
      return tr('اختر الخزينة.');
    }
    // الشيكُ ورقةٌ على طرفٍ بعينه — حسابٌ عامٌّ لا يحمل شيكاً.
    if (_isCheque && _partyId == null) {
      return tr('الشيكات تتطلّب حساب عميل أو مورّد.');
    }
    final vb = _pickedVoucherBook;
    if (vb != null) {
      final n = _bookNumber;
      if (n == null) return tr('اكتب رقم ورقة الدفتر.');
      if (n < vb.rangeFrom || n > vb.rangeTo) {
        return tr('رقم الورقة خارج مدى الدفتر ({p0}–{p1}).',
            {'p0': vb.rangeFrom, 'p1': vb.rangeTo});
      }
    }
    // ⚠️ مراكزُ التكلفة حين تكون معرَّفةً **إلزاميّة**: بدونها يسقط القيدُ
    //    على «عام» ويُقرأ في تقارير المراكز على غير موضعه.
    if (widget.costCenters.isNotEmpty && _costCenterId == null) {
      return tr('اختر مركز التكلفة.');
    }
    if (_isCheque) {
      // 🔴 **والدفترُ يُفحَص قبل الأرقام**: لو لم يبقَ فيه ما يكفي فرسالةُ
      //    «اكتب رقم الشيك» كاذبةٌ — الحقلُ مقفولٌ لأنّ الدفترَ يملؤه.
      final book = _pickedBook;
      if (book != null) {
        final plan = planChequeNumbers(
          book: (
            id: book.id,
            bankAccountId: 0,
            fromNumber: book.nextNumber,
            toNumber: book.toNumber,
            nextNumber: book.nextNumber,
            status: 'active',
          ),
          count: _cheques.length,
        );
        if (plan.error != null) return tr('الدفتر: {p0}', {'p0': plan.error});
      }
      for (var i = 0; i < _cheques.length; i++) {
        final c = _cheques[i];
        if (book == null && c.numberCtrl.text.trim().isEmpty) {
          return tr('الشيك {p0}: اكتب رقمه.', {'p0': i + 1});
        }
        // 🔴 مبلغٌ صفرٌ يعني قسمةً بالتساوي في المسار القديم — وهنا يُرفَض.
        if (c.amount <= 0) return tr('الشيك {p0}: اكتب مبلغه.', {'p0': i + 1});
        if (c.dueDate == null) return tr('الشيك {p0}: اختر تاريخ استحقاقه.', {'p0': i + 1});
      }
    }
    if (_grossAmount <= 0) return tr('أدخل مبلغاً أكبر من صفر.');
    if (_discount < 0) return tr('الخصم لا يكون سالباً.');
    if (_commissionPercent < 0 || _commissionPercent > 100) {
      return tr('نسبة العمولة بين صفر ومئة.');
    }
    if (_netAmount <= 0) return tr('صافي المبلغ يجب أن يكون أكبر من صفر.');
    // 🔴 التوزيعُ لا يتجاوز الصافي: تخصيصٌ أكبرُ يُقفل فواتيرَ بمالٍ لم يُقبَض.
    if (_allocatedTotal > _netAmount + 0.001) {
      return tr('التوزيع ({p0}) يتجاوز الصافي ({p1}).', {'p0': _money.format(_allocatedTotal), 'p1': _money.format(_netAmount)});
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
      subtitle: tr('رقم السند: {kVoucherNumberPlaceholder}', {'kVoucherNumberPlaceholder': kVoucherNumberPlaceholder}),
      icon: widget.kind.icon,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // E2 — رأسُ المستند على نمط الفاتورة: العنوانُ والرقمُ
                  // وشارةُ الحالة، وشارةُ «تحويل محاسبي» حين لا خزنة.
                  VoucherDocHeader(
                    title: widget.kind.title,
                    icon: widget.kind.icon,
                    accent: widget.kind.accent,
                    numberText: _pickedVoucherBook == null
                        ? '—'
                        : tr('ورقة الدفتر: {p0}', {
                            'p0': '${_pickedVoucherBook!.prefix ?? ''}'
                                '${_bookNumberCtrl.text.trim()}'
                          }),
                    isTransfer: _isTransfer,
                  ),
                  const SizedBox(height: 12),
                  _headerCard(),
                  const SizedBox(height: 12),
                  if (_isCheque) _chequesCard() else _cashCard(),
                  const SizedBox(height: 12),
                  _allocationCard(),
                  const SizedBox(height: 12),
                  PicPosTotalsBar(items: [
                    PicPosTotal(
                      label: tr('الإجمالي'),
                      value: _money.format(_grossAmount),
                    ),
                    if (_isDeliveryCompany)
                      PicPosTotal(
                        label: tr('العمولة'),
                        value: _money.format(_commissionAmount),
                      ),
                    PicPosTotal(
                      label: tr('الخصم'),
                      value: _money.format(_discount),
                    ),
                    PicPosTotal(
                      label: tr('الصافي'),
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
            backLabel: tr('رجوع'),
            busy: widget.busy,
            hint: reason ?? tr('يُرحَّل السندُ فورَ الاعتماد'),
            // ⚠️ **لا زرَّ مسوّدة** — راجع رأسَ الملفّ: لا حالةَ مسوّدةٍ في
            //    المحرّك، وزرٌّ يحفظ مُرحَّلاً وهو يقول «مسودة» أسوأُ من غيابه.
            primary: PicPosFormAction(
              label: tr('مراجعة واعتماد'),
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
              title: tr('بيانات {p0}', {'p0': widget.kind.title}),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                    width: _useAccounts ? 300 : 220, child: _partyField()),
                SizedBox(width: 190, child: _dateField()),
                SizedBox(width: 200, child: _costCenterField()),
              ],
            ),
            if (widget.voucherBooks.isNotEmpty) ...[
              const SizedBox(height: 10),
              VoucherBookSection(
                books: widget.voucherBooks,
                bookId: _bookId,
                numberCtrl: _bookNumberCtrl,
                onBookChanged: (v) => setState(() => _pickBook(v)),
                onNumberChanged: () => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            _methodSegments(),
            const SizedBox(height: 10),
            TextField(
              key: const Key('voucher_notes'),
              controller: _notesCtrl,
              decoration:  InputDecoration(
                labelText: tr('البيان'),
                hintText: tr('اختياري'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _partyField() => _useAccounts
      ? VoucherAccountField(
          key: const Key('voucher_party'),
          label: widget.kind.partyLabel,
          accounts: widget.accounts,
          selectedId: _beneficiaryAccountId,
          helper: _partyId != null
              ? tr('حساب طرف — يُحدَّث رصيده وكشفه')
              : null,
          onChanged: (a) {
            setState(() {
              _beneficiaryAccountId = a.id;
              _partyId = a.partyId;
              for (final c in _allocCtrls.values) {
                c.clear();
              }
            });
            widget.onPartyPicked?.call(a.partyId);
          },
        )
      : _partyDropdown();

  Widget _partyDropdown() => DropdownButtonFormField<int>(
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
          decoration:  InputDecoration(
            labelText: tr('التاريخ'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(PhosphorIconsBold.calendar, size: 15),
          ),
          child: Text(_dateFmt.format(_date)),
        ),
      );

  Widget _costCenterField() => DropdownButtonFormField<int>(
        key: const Key('voucher_cost_center'),
        initialValue: _costCenterId,
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('مركز التكلفة'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final c in widget.costCenters)
            DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (v) => setState(() => _costCenterId = v),
      );

  Widget _methodSegments() {
    final methods = <({String value, String label, IconData icon})>[
      (value: 'cash', label: tr('نقدي'), icon: PhosphorIconsBold.money),
      (value: 'bank', label: tr('بنك'), icon: PhosphorIconsBold.bank),
      (value: 'check', label: tr('شيكات'), icon: PhosphorIconsBold.creditCard),
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
                SizedBox(width: _useAccounts ? 300 : 230, child: _safeField()),
                SizedBox(
                  width: 170,
                  child: TextField(
                    key: const Key('voucher_amount'),
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration:  InputDecoration(
                      labelText: tr('المبلغ'),
                      isDense: true,
                      border: const OutlineInputBorder(),
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
                      decoration:  InputDecoration(
                        labelText: tr('خصم سداد معجَّل'),
                        isDense: true,
                        border: const OutlineInputBorder(),
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
                        decoration:  InputDecoration(
                          labelText: tr('عمولة التوصيل ٪'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      );

  Widget _safeField() => _useAccounts
      ? VoucherAccountField(
          key: const Key('voucher_safe'),
          label: tr('الخزينة / الحساب'),
          accounts: widget.accounts,
          selectedId: _treasuryAccountId,
          helper: _isTransfer
              ? tr('ليس حساب خزنة — قيد تحويل بلا حركة خزنة')
              : null,
          onChanged: (a) => setState(() {
            _treasuryAccountId = a.id;
            _safeId = a.safeId;
          }),
        )
      : _safeDropdown();

  Widget _safeDropdown() => DropdownButtonFormField<int>(
        key: const Key('voucher_safe'),
        initialValue: _safeId,
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('الخزينة'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final s in widget.safes)
            DropdownMenuItem(value: s.id, child: Text(trData(s.name))),
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
                 Expanded(
                  child: PicPosSectionHeader(
                    icon: PhosphorIconsBold.creditCard,
                    title: tr('الشيكات'),
                  ),
                ),
                TextButton.icon(
                  key: const Key('voucher_add_cheque'),
                  onPressed: () =>
                      setState(() => _cheques.add(VoucherChequeDraft())),
                  icon: const Icon(PhosphorIconsBold.plus, size: 14),
                  label:  Text(tr('إضافة شيك')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(width: _useAccounts ? 300 : 230, child: _safeField()),
            if (widget.chequeBooks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _chequeBookField(),
            ],
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
                title:  Text(tr('أودِعه للتحصيل فوراً')),
                subtitle:  Text(
                  tr('يُنشأ الشيكُ برسم التحصيل ثمّ يُنقَل إلى «أودِع» بقيده'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      );

  /// منتقي الدفتر — و«بلا دفتر» خيارٌ **صريحٌ** لا غيابُ اختيار.
  ///
  /// ⚠️ **ولماذا يبقى الكتابةُ بيدٍ ممكنةً**: دفاترُ قديمةٌ لم تُسجَّل بعد،
  ///    وشيكٌ مصرفيٌّ يُسحَب من غير دفترنا. ومنعُ اليدِ كان يوقف الصرفَ حتى
  ///    يُسجَّل كلُّ دفترٍ في الدرج.
  Widget _chequeBookField() => DropdownButtonFormField<int?>(
        key: const Key('voucher_cheque_book'),
        initialValue: _chequeBookId,
        // ⚠️ راجع نظيرَه في شاشة الدفتر: بلا هذه يفيض الصفُّ على اسمٍ طويل.
        isExpanded: true,
        decoration:  InputDecoration(
          labelText: tr('دفتر الشيكات'),
          helperText: tr('الرقمُ يُسحَب من الدفتر عند الحفظ — لا يُكتَب بيد'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
           DropdownMenuItem<int?>(
            value: null,
            child: Text(tr('بلا دفتر — أكتب الرقم بيدي')),
          ),
          for (final b in widget.chequeBooks)
            DropdownMenuItem<int?>(
              value: b.id,
              child: Text(tr('{p0} · متبقٍّ {p1}', {'p0': b.label, 'p1': b.remaining})),
            ),
        ],
        onChanged: (v) => setState(() => _chequeBookId = v),
      );

  Widget _chequeRow(int i) {
    final c = _cheques[i];
    final book = _pickedBook;
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
              Text(tr('شيك {p0}', {'p0': i + 1}),
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
                    ? tr('حذف الشيك')
                    : tr('لا يقلّ السندُ عن شيكٍ واحد'),
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
                width: 170,
                child: book == null
                    ? TextField(
                        controller: c.numberCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration:  InputDecoration(
                          labelText: tr('رقم الشيك'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      )
                    // 🔴 **معاينةٌ مقفولةٌ لا حقلٌ محرَّر**: الرقمُ يُسحَب في
                    //    معاملة الحفظ، وحقلٌ يُكتَب فيه رقمٌ ثمّ يُستبدَل
                    //    بغيره عند الحفظ يكذب على من كتبه.
                    : InputDecorator(
                        decoration:  InputDecoration(
                          labelText: tr('رقم الشيك'),
                          helperText: tr('من الدفتر عند الحفظ'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        child: Text(
                          _previewChequeNumber(book, i),
                          key: Key('voucher_cheque_preview_$i'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: c.bankCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('البنك'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              // E4 — الساحبُ للشيك الوارد؛ والصادرُ ساحبُه نحن.
              if (widget.kind.isReceipt)
                SizedBox(
                  width: 170,
                  child: TextField(
                    key: Key('voucher_cheque_drawer_$i'),
                    controller: c.drawerCtrl,
                    decoration: InputDecoration(
                      labelText: tr('الساحب'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              // E-fix ٢ — الساحبُ (وارد) / المستفيدُ (صادر) من دليل الحسابات
              // بمنتقي المرحلة هـ؛ يُحفَظ في `commercial_papers.drawer_*`.
              if (widget.accounts.isNotEmpty)
                SizedBox(
                  width: 240,
                  child: VoucherAccountField(
                    key: Key('voucher_cheque_drawer_account_$i'),
                    label: widget.kind.isReceipt
                        ? tr('حساب الساحب')
                        : tr('حساب المستفيد'),
                    accounts: widget.accounts,
                    selectedId: c.drawerAccountId,
                    onChanged: (a) =>
                        setState(() => c.drawerAccountId = a.id),
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
                    decoration:  InputDecoration(
                      labelText: tr('الاستحقاق'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    child: Text(c.dueDate == null
                        ? tr('اختر التاريخ')
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
                  decoration:  InputDecoration(
                    labelText: tr('المبلغ'),
                    isDense: true,
                    border: const OutlineInputBorder(),
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
                 Expanded(
                  child: PicPosSectionHeader(
                    icon: PhosphorIconsBold.receipt,
                    title: tr('توزيع المبلغ على الفواتير'),
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
              Text(tr('اختر {p0} أوّلاً.', {'p0': widget.kind.partyLabel}),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted))
            else if (invoices.isEmpty)
               Text(
                tr('لا فواتيرَ مفتوحةً لهذا الطرف — ويُحفَظ السندُ على حسابه بلا توزيع.'),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              )
            else
              for (final inv in invoices) _allocationRow(inv),
            if (invoices.isNotEmpty) ...[
              const SizedBox(height: 6),
              // ⚠️ **التوزيعُ اختياريٌّ لا إلزاميّ**: سندٌ على الحساب بلا
              //    فاتورةٍ بعينها حالةٌ مشروعةٌ تماماً (دفعةٌ تحت الحساب).
               Text(
                tr('التوزيع اختياريّ — وما لا يُوزَّع يبقى على حساب الطرف.'),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                  tr('{p0} · الباقي {p1}', {'p0': _dateFmt.format(inv.date), 'p1': _money.format(remaining)}),
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
              decoration:  InputDecoration(
                labelText: tr('المخصَّص'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            // «الباقي» — أكثرُ ما يُكتَب، ويمنع تجاوزَ الفاتورة بالكتابة اليدويّة.
            onPressed: () => setState(
                () => ctrl.text = remaining.toStringAsFixed(2)),
            child:  Text(tr('الباقي')),
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
          for (var i = 0; i < _cheques.length; i++)
            (
              // معاينةٌ حين يكون ثَمَّ دفتر — والمضيفُ يسحب ويستبدل.
              number: _pickedBook == null
                  ? _cheques[i].numberCtrl.text.trim()
                  : _previewChequeNumber(_pickedBook!, i),
              bank: _cheques[i].bankCtrl.text.trim(),
              dueDate: _cheques[i].dueDate,
              amount: _cheques[i].amount,
              drawer: _cheques[i].drawerCtrl.text.trim(),
              drawerAccountId: _cheques[i].drawerAccountId,
            ),
      ],
      depositImmediately: _isCheque && _depositImmediately,
      allocations: allocations,
      chequeBookId: _isCheque ? _chequeBookId : null,
      beneficiaryAccountId: _partyId == null ? _beneficiaryAccountId : null,
      treasuryAccountId: _useAccounts ? _treasuryAccountId : null,
      bookId: _pickedVoucherBook?.id,
      bookNumber: _pickedVoucherBook == null ? null : _bookNumber,
    ));
  }
}

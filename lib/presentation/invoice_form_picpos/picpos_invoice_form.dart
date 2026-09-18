// شاشةُ «فاتورة جديدة» بهوية PicPos — مبيعاتٍ ومشترياتٍ بنمطٍ واحد.
//
// المصدر: تصميمُ Claude Design «تصميم شاشات فواتير PicPos»، شاشتا
// `newsale` و`newpur` (سطر ١٨٥٩–٢١٢٧ في `PicPos Invoices.dc.html`). وهما في
// التصميم **شاشةٌ واحدة** خلف `isNewInv`، تقلب سبعةَ نصوصٍ وحقلاً واحداً —
// فبُنيت هنا ودجتاً واحدةً بـ[PicPosInvoiceKind] لا توأمَين ينحرفان بأوّل
// تعديل.
//
// ═══ أربعةُ قيودٍ حكمت البناء — كلُّها مقيسةٌ لا مذوَّقة ═══
//
// ‏١) **لا مسَّ بمسار المال.** `SalesInvoiceForm` و`PurchaseInvoiceForm`
//    عرضٌ خالصٌ فوق ردِّ نداء: الحفظُ والقيدُ والمخزونُ كلُّه في mixin
//    المستدعي. فهذه الشاشةُ تستدعي **نفسَ** ردِّ النداء بنفس الوسائط، ولا
//    تكتب في قاعدةٍ ولا تُنشئ قيداً.
//
// ‏٢) **ولا تُلمَس الملفّاتُ المشتركة.** الودجتان أعلاه تخدمان UralCash
//    أيضاً، وقرارُ المالك: ما يُعمَل على PicPos لا ينتقل إلى UralCash.
//    فهذه فوركٌ مستقلٌّ تماماً — صفرُ تعديلٍ في الاثنتين.
//
// ‏٣) **ولا استيرادَ لـ`data/database`.** حارسُ `presentation_db_import_guard`
//    يمنعه على كلّ ملفِّ عرضٍ جديد. فالأنواعُ الداخلةُ من `domain/models`
//    (`PicPosPartyOption` وأخواتها)، والمستدعي — وهو ملفٌّ قديمٌ يستورد
//    القاعدةَ أصلاً — يحوّل إليها.
//
// ‏٤) **إنشاءٌ فقط، لا تعديل.** الشاشةُ اسمُها «فاتورة جديدة» وهذا نطاقُها.
//    والتعديلُ يبقى على النموذج القائم — الذي يستقبل `PurchaseInvoiceData`
//    من القاعدة مباشرةً، وهو ما يمنعه القيدُ ٣ على ملفٍّ جديد.
//
// ⚠️ **وما لم يُبنَ عمداً، ولماذا:**
//  • **لا خصمَ على مستوى السطر** رغم وجود العمود في التصميم: مسارُ الحفظ لا
//    يقرأ `item['discount']` ولا يحمل `PurchaseItemParams` حقلاً له، فالقيمةُ
//    كانت ستُبتلَع صفراً مهما أُدخلت. والخصمُ على المستند يُحفَظ فعلاً فهو
//    المعروض. (التفصيل في `picpos_invoice_draft.dart`.)
//  • **لا «تاريخ استحقاق»** في هذه الدفعة: قرارُ المالك أن يكون حقلاً
//    يُحفَظ، وذلك يوجب عموداً وهجرةً و`build_runner` — وقد أُجِّل الـcodegen
//    إلى دفعةٍ واحدةٍ في الآخر.
//  • **ولا ضريبةَ ١٤٪ مطبوعة**: التصميمُ يكتبها قيمةَ عيّنة، والنسبةُ تأتي
//    من إعداد النظام. وطبعُها ثابتةً كان سيكذب على كلّ تنصيبٍ بنسبةٍ أخرى.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/number_utils.dart';
import '../../domain/models/invoice_due_date.dart';
import '../../domain/models/picpos_invoice_draft.dart';

part 'picpos_invoice_lines.dart';
part 'picpos_invoice_money.dart';

/// عقدُ الحفظ — يُترجمه المستدعي إلى `onSave` القائم بلا تغييرٍ في المسار.
typedef PicPosInvoiceSaveCallback = Future<void> Function({
  required int? partyId,
  required String supplierInvoiceNumber,
  required DateTime date,
  required double subtotal,
  required double discount,
  required double tax,
  required double net,
  required double paid,
  required String notes,
  required List<Map<String, dynamic>> items,
  required int? warehouseId,
  required int? costCenterId,
  required String paymentMethod,
  required bool printAfterSave,
});

/// حفظُ المسودّة — ومعناه يختلف بالنمط اختلافاً جوهريّاً:
///
/// • **المشتريات**: `onSave(isDraft: true)` — مسودّةُ فاتورةِ شراء.
/// • **المبيعات**: **عرضُ سعر** يُحفَظ فيظهر في تبويب «عروض الأسعار»، فيُعدَّل
///   لاحقاً أو يُحوَّل إلى فاتورة (قرارُ المالك 2026-08-21). والمسارُ قائمٌ
///   بالكامل — `onSaveQuotation` ← `_saveQuotation` — فلا سطرَ جديدٌ في أيّ
///   عقدٍ مشترك.
typedef PicPosInvoiceDraftCallback = Future<void> Function({
  required int? partyId,
  required String notes,
  required List<Map<String, dynamic>> items,
  required double subtotal,
  required double discount,
  required double tax,
  required double net,
});

/// لونُ النصِّ الخافت — `--muted` في الوضعين.
Color _fMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// لونُ الحقل — `--field` في الوضعين.
Color _fField(BuildContext context) =>
    Theme.of(context).inputDecorationTheme.fillColor ??
    (Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18243A)
        : const Color(0xFFF4F7FC));

/// خلفيّةُ البطاقة الداكنة — `--hero`.
Color _fHero(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF10305F)
        : AppColors.primaryDark;

class PicPosInvoiceForm extends StatefulWidget {
  const PicPosInvoiceForm({
    super.key,
    required this.kind,
    required this.parties,
    required this.products,
    required this.warehouses,
    required this.costCenters,
    required this.systemTaxRate,
    required this.invoiceNumberPreview,
    required this.onSave,
    required this.onCancel,
    this.onSaveDraft,
    this.userName = '',
    this.initialWarehouseId,
    this.initialCostCenterId,
    this.availableStock,
  });

  final PicPosInvoiceKind kind;
  final List<PicPosPartyOption> parties;
  final List<PicPosProductOption> products;
  final List<PicPosNamedOption> warehouses;
  final List<PicPosNamedOption> costCenters;

  /// نسبةُ الضريبة من إعداد النظام — لا رقمٌ مطبوع.
  final double systemTaxRate;

  /// رقمُ الفاتورة كما سيُولَّد — يُعرض مقفولاً كما في التصميم.
  final String invoiceNumberPreview;

  final PicPosInvoiceSaveCallback onSave;

  /// `null` ⇒ لا زرَّ مسودّة. اقرأ [PicPosInvoiceDraftCallback].
  final PicPosInvoiceDraftCallback? onSaveDraft;

  final VoidCallback onCancel;

  /// اسمُ المستخدم — يُعرض في حقل «البائع».
  ///
  /// ⚠️ **عرضٌ لا اختيار**: `SalesInvoices.userId` عمودٌ إلزاميّ، لكنّ عقدَ
  /// الحفظ لا يحمل وسيطَ مستخدم — فالحفظُ يستعمل مستخدمَ الجلسة. ورسمُه
  /// قائمةً منسدلةً لا تغيّر شيئاً كان زخرفاً يكذب.
  final String userName;

  final int? initialWarehouseId;
  final int? initialCostCenterId;

  /// الأرصدةُ المتاحة لكلّ صنف — `productId` ← الكمّيّةُ المتاحة.
  ///
  /// ⚠️ **و`null` ليست «صفر» بل «لا تُعرَف».** التصميمُ يكتب «الرصيد المتاح
  /// يكفي جميع البنود»، وهي جملةٌ عن المخزون لا زخرف. فلا تُطبَع إلّا حين
  /// تصل الأرصدةُ فعلاً؛ وبدونها لا يُقال شيءٌ في الاتّجاهَين — لا كفايةٌ
  /// تُدَّعى ولا نقصٌ يُتَّهَم به.
  ///
  /// وصنفٌ غائبٌ عن الخريطة يُتخطّى: قد يكون خدمةً لا تُخزَّن.
  final Map<int, double>? availableStock;

  @override
  State<PicPosInvoiceForm> createState() => _PicPosInvoiceFormState();
}

class _PicPosInvoiceFormState extends State<PicPosInvoiceForm> {
  final _lines = <PicPosInvoiceLine>[];
  final _notesController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _paidController = TextEditingController(text: '0');
  final _supplierInvoiceController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  int? _partyId;
  int? _warehouseId;
  int? _costCenterId;
  DateTime _date = DateTime.now();
  String _paymentMethod = 'cash';
  bool _saving = false;

  /// هل كتب المستخدمُ «المحصَّل» بيده؟ يوقف التهيئةَ التلقائيّة إلى الأبد
  /// (اقرأ [picPosAutoPaid]). ويُرفع من `onChanged` وحدَه — الإسنادُ
  /// البرمجيُّ على `controller.text` **لا** يستدعيه، وهذا بالضبط ما يفرّق
  /// بين رقمِ المستخدم ورقمِ التهيئة.
  bool _paidTouched = false;

  /// حارسُ عدمِ الارتداد: الكتابةُ في `_paidController` تُوقظ مستمعَها،
  /// فبلا هذا الحارس تُنادي التهيئةُ نفسَها.
  bool _syncingPaid = false;

  /// كميّةُ سطرِ الإدخال السريع.
  double _quickQty = 1;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.initialWarehouseId ??
        (widget.warehouses.length == 1 ? widget.warehouses.first.id : null);
    _costCenterId = widget.initialCostCenterId;
    // إعادةُ الرسم مع كلّ تغيّرٍ في الخصم أو المدفوع: الاثنان يغذّيان
    // المعادلةَ والمتبقي، فبقاؤهما بلا استماعٍ كان سيُجمِّد الأرقامَ على
    // قيمةٍ قديمةٍ بينما الحقلُ يُظهر جديدةً.
    _discountController.addListener(_onMoneyFieldChanged);
    _paidController.addListener(_onMoneyFieldChanged);
  }

  @override
  void dispose() {
    _discountController.removeListener(_onMoneyFieldChanged);
    _paidController.removeListener(_onMoneyFieldChanged);
    _notesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _supplierInvoiceController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onMoneyFieldChanged() {
    // الخصمُ يغيّر الصافيَ، والصافي يقود التهيئةَ — فتُعاد الحسبةُ قبل
    // إعادة الرسم لا بعدها.
    _syncAutoPaid();
    if (mounted) setState(() {});
  }

  /// يُعيد «المحصَّل» إلى ما تفرضه طريقةُ الدفع ما لم يكتبه المستخدمُ بيده.
  ///
  /// يُنادى بعد كلِّ ما يحرّك الصافيَ — إضافةُ بندٍ أو تعديلُه أو حذفُه
  /// أو تغيُّرُ الخصم — وعند اختيار طريقةِ دفعٍ صراحةً.
  void _syncAutoPaid() {
    if (_syncingPaid) return;
    final auto = picPosAutoPaid(
      paymentMethod: _paymentMethod,
      net: _totals.net,
      userEdited: _paidTouched,
    );
    if (auto == null) return;
    final text = auto.toStringAsFixed(AppConstants.decimalPlaces);
    if (_paidController.text == text) return;
    _syncingPaid = true;
    _paidController.text = text;
    _syncingPaid = false;
  }

  double get _headerDiscount =>
      NumberUtils.tryParseLocale(_discountController.text) ?? 0;

  /// الطرفُ المختار — أو `null`.
  PicPosPartyOption? get _party =>
      widget.parties.where((p) => p.id == _partyId).firstOrNull;

  /// تاريخُ الاستحقاق **مشتقٌّ** من مهلة الطرف وتاريخ الفاتورة — ح‑١.
  ///
  /// 🔴 **ولا يُحسَب هنا**: [resolveDueDateFromTerms] هي عينُ الدالّة التي
  /// يناديها `PartyDao.resolveInvoiceDueDate` وقتَ الحفظ. فما يُقرأ على
  /// الشاشة هو ما يُختَم على المستند حرفاً — ومرآةٌ تحسب بنفسها ليست مرآة.
  ///
  /// و`null` = **بلا مهلةٍ متّفقة**، لا «يُستحقُّ اليوم».
  DateTime? get _dueDate => resolveDueDateFromTerms(
        invoiceDate: _date,
        paymentTermsDays: _party?.paymentTermsDays,
      );

  double get _paidRaw => NumberUtils.tryParseLocale(_paidController.text) ?? 0;

  PicPosInvoiceTotals get _totals =>
      PicPosInvoiceTotals.from(_lines, headerDiscount: _headerDiscount);

  /// رقمُ فاتورةِ المورد مطلوبٌ في نمط المشتريات — التصميمُ يصبغه بلونِ
  /// الخطأ ويضع له تنبيهاً مستقلّاً.
  bool get _supplierInvoiceMissing =>
      !widget.kind.isSales && _supplierInvoiceController.text.trim().isEmpty;

  void _addProduct(PicPosProductOption p) {
    setState(() {
      final i = _lines.indexWhere((l) => l.productId == p.id);
      final qty = _quickQty <= 0 ? 1.0 : _quickQty;
      if (i >= 0) {
        // نفسُ سلوك النموذجَين القائمَين: الصنفُ المكرَّر يزيد كمّيّةَ سطره
        // ولا يفتح سطراً ثانياً — وإلّا انقسم الصنفُ الواحدُ على سطرَين
        // بسعرَين وصار تدقيقُ الفاتورة أصعب.
        _lines[i] = _lines[i].copyWith(quantity: _lines[i].quantity + qty);
      } else {
        final rate = p.taxRate > 0 ? p.taxRate : widget.systemTaxRate;
        _lines.add(PicPosInvoiceLine(
          productId: p.id,
          productName: p.name,
          categoryId: p.categoryId,
          quantity: qty,
          unitPrice: p.priceFor(widget.kind),
          taxRate: rate,
          // الضريبةُ مفعَّلةٌ متى وُجدت نسبةٌ — نفسُ افتراض النموذج القائم
          // (Spec 135 BUG-B: الإطفاءُ الافتراضيُّ كان يُخفي الضريبةَ عن
          // الكاشير بينما يحفظها المُنسِّق).
          taxEnabled: rate > 0,
          unitName: p.unitName,
        ));
      }
      _quickQty = 1;
      _searchController.clear();
    });
    _syncAutoPaid();
    _searchFocus.requestFocus();
  }

  void _updateLine(int i, PicPosInvoiceLine next) {
    setState(() => _lines[i] = next);
    _syncAutoPaid();
  }

  void _removeLine(int i) {
    setState(() => _lines.removeAt(i));
    _syncAutoPaid();
  }

  /// التحقّقُ قبل الحفظ — يعيد رسالةَ المنع أو `null`.
  ///
  /// الترتيبُ مقصود: المخزنُ أوّلاً لأن غيابَه كان يمرّ صامتاً في النموذج
  /// القائم (`warehouseId ?? 1` كان يخترع المخزنَ رقم ١).
  String? _blockingReason() {
    if (_warehouseId == null) return 'يجب اختيار المخزن قبل حفظ الفاتورة';
    if (_partyId == null) return 'يجب اختيار ${widget.kind.partyLabel}';
    if (_lines.isEmpty) return 'أضف صنفاً واحداً على الأقل';
    if (_supplierInvoiceMissing) {
      return 'أدخل رقم فاتورة المورد قبل الحفظ — مطلوب للمطابقة الضريبية';
    }
    return null;
  }

  Future<void> _save({required bool printAfterSave}) async {
    final blocked = _blockingReason();
    if (blocked != null) {
      _toast(blocked);
      return;
    }
    final t = _totals;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        partyId: _partyId,
        supplierInvoiceNumber: _supplierInvoiceController.text.trim(),
        date: _date,
        subtotal: t.subtotal,
        // 🔴 **الخصمُ كلُّه لا حقلُ الترويسة وحدَه.** المحرّكُ يقرأ هذا الرقمَ
        // على أنّه مجموعُ الخصم ثمّ يحفر منه خصمَ كلّ سطر
        // (`resolvePurchaseLineNets`). فتمريرُ حقل الترويسة وحدَه كان يجعل
        // ترويسةَ الفاتورة تقول «بلا خصم» وسطورَها مخصومة — ذمّةٌ على المورّد
        // لا يقابلها مخزونٌ دخل.
        discount: t.discountTotal,
        tax: t.tax,
        net: t.net,
        // المحصورُ لا الخام: الحقلُ يقبل أيَّ رقم، والحفظُ لا يقبل سالباً
        // ولا فوقَ الصافي.
        paid: t.clampPaid(_paidRaw),
        notes: _notesController.text,
        items: _lines.map((l) => l.toSaveMap(widget.kind)).toList(),
        warehouseId: _warehouseId,
        costCenterId: _costCenterId,
        paymentMethod: _paymentMethod,
        printAfterSave: printAfterSave,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDraft() async {
    final cb = widget.onSaveDraft;
    if (cb == null) return;
    // المسودّةُ أخفُّ شرطاً من الفاتورة: لا تحرّك مخزوناً ولا مالاً، فلا
    // تُطلَب لها المخزنُ ولا رقمُ فاتورةِ المورد. لكنّ سطراً واحداً على
    // الأقلّ شرطٌ باقٍ — مسودّةٌ فارغةٌ لا تعني شيئاً.
    if (_lines.isEmpty) {
      _toast('أضف صنفاً واحداً على الأقل');
      return;
    }
    final t = _totals;
    setState(() => _saving = true);
    try {
      await cb(
        partyId: _partyId,
        notes: _notesController.text,
        items: _lines.map((l) => l.toSaveMap(widget.kind)).toList(),
        subtotal: t.subtotal,
        discount: t.discountTotal,
        tax: t.tax,
        net: t.net,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Text(msg),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      // الاختصاران مذكوران في التصميم على الزرَّين — فوُصِلا فعلاً. وشارةٌ
      // مرسومةٌ لاختصارٍ لا يعمل أسوأُ من غيابها: المستخدمُ يجرّبها فيظنّ
      // الشاشةَ معطوبة.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              _searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.f9): () {
            if (!_saving) _save(printAfterSave: false);
          },
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, c) {
              // العمودُ الماليُّ ٤٢٠ ثابتةً كما في التصميم. ودون ~٩٦٠ لا يبقى
              // للبنود عرضٌ صالح، فينكسر التخطيطُ رأسيّاً بدل أن يُسحَق أفقيّاً.
              final wide = c.maxWidth >= 960;
              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 520, child: _buildDocumentColumn(context)),
                      const SizedBox(height: 12),
                      _PicPosMoneyPanel(state: this, expand: false),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildDocumentColumn(context)),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 420,
                      child: _PicPosMoneyPanel(state: this, expand: true),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PicPosDocBar(state: this),
        const SizedBox(height: 12),
        _PicPosQuickAdd(state: this),
        const SizedBox(height: 12),
        Expanded(child: _PicPosLinesTable(state: this)),
      ],
    );
  }
}

/// شريطُ بيانات المستند — كتلةُ الطرف ثمّ حقولٌ متساوية.
class _PicPosDocBar extends StatelessWidget {
  const _PicPosDocBar({required this.state});
  final _PicPosInvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    final w = state.widget;
    final party = w.parties.where((p) => p.id == state._partyId).firstOrNull;

    final fields = <Widget>[
      _field(
        context,
        icon: PhosphorIconsBold.calendarBlank,
        label: 'التاريخ والوقت',
        value: '${state._date.toString().substring(0, 10)} · '
            '${state._date.hour.toString().padLeft(2, '0')}:'
            '${state._date.minute.toString().padLeft(2, '0')}',
        trailing: PhosphorIconsBold.caretDown,
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: state._date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) {
            state.setState(() => state._date = picked);
          }
        },
      ),
      _field(
        context,
        icon: PhosphorIconsBold.hash,
        label: 'رقم الفاتورة',
        value: w.invoiceNumberPreview,
        // مقفولٌ كما في التصميم: الرقمُ يولّده الخادمُ تسلسليّاً، وحقلٌ
        // يقبل تحريراً ثمّ يُتجاهَل أسوأُ من حقلٍ مقفول.
        trailing: PhosphorIconsBold.lockSimple,
        valueColor: muted,
      ),
      if (!w.kind.isSales)
        _supplierInvoiceField(context)
      else if (w.userName.isNotEmpty)
        _field(
          context,
          icon: PhosphorIconsBold.user,
          label: 'البائع',
          value: w.userName,
          // بلا سهمٍ: عرضٌ لا اختيار (اقرأ `userName` في الودجت).
          trailing: null,
        ),
      _field(
        context,
        icon: PhosphorIconsBold.warehouse,
        label: 'المخزن',
        value: w.warehouses
                .where((x) => x.id == state._warehouseId)
                .firstOrNull
                ?.name ??
            'اختر',
        trailing: PhosphorIconsBold.caretDown,
        valueColor: state._warehouseId == null ? AppColors.error : null,
        onTap: () => _pick(
          context,
          title: 'المخزن',
          options: w.warehouses,
          selected: state._warehouseId,
          onPick: (id) => state.setState(() => state._warehouseId = id),
        ),
      ),
      _field(
        context,
        icon: PhosphorIconsBold.crosshair,
        label: 'مركز التكلفة',
        value: w.costCenters
                .where((x) => x.id == state._costCenterId)
                .firstOrNull
                ?.name ??
            'بلا',
        trailing: PhosphorIconsBold.caretDown,
        onTap: () => _pick(
          context,
          title: 'مركز التكلفة',
          options: w.costCenters,
          selected: state._costCenterId,
          onPick: (id) => state.setState(() => state._costCenterId = id),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 300, child: _partyBlock(context, party)),
            for (final f in fields)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: f,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _partyBlock(BuildContext context, PicPosPartyOption? party) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    return Material(
      color: _fField(context),
      child: InkWell(
        onTap: () => _pickParty(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  party?.initials ?? '؟',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      state.widget.kind.partyLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: muted,
                      ),
                    ),
                    Text(
                      party?.name ?? 'اختر ${state.widget.kind.partyLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: party == null
                            ? AppColors.error
                            : theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    if (party != null && party.meta.isNotEmpty)
                      Text(
                        party.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(PhosphorIconsBold.caretDown,
                  size: 13, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supplierInvoiceField(BuildContext context) {
    final muted = _fMuted(context);
    final missing = state._supplierInvoiceMissing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // مرنٌ كنظيره في [_field]: عمودُ المستند يتقاسم عرضَه بين خمسةِ
          // حقول، فعنوانٌ عاري النصِّ يفيض عن حصّته.
          Row(
            children: [
              Icon(PhosphorIconsBold.fileText, size: 11, color: muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'رقم فاتورة المورد',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          TextField(
            controller: state._supplierInvoiceController,
            onChanged: (_) => state.setState(() {}),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'مطلوب',
              hintStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: missing ? AppColors.error : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    IconData? trailing,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final muted = _fMuted(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 11, color: muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Icon(trailing, size: 11, color: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickParty(BuildContext context) async {
    final w = state.widget;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: 'اختر ${w.kind.partyLabel}',
        items: [
          for (final p in w.parties)
            (id: p.id, title: p.name, subtitle: p.meta),
        ],
      ),
    );
    if (picked != null) state.setState(() => state._partyId = picked);
  }

  Future<void> _pick(
    BuildContext context, {
    required String title,
    required List<PicPosNamedOption> options,
    required int? selected,
    required ValueChanged<int?> onPick,
  }) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: 'اختر $title',
        items: [
          for (final o in options) (id: o.id, title: o.name, subtitle: ''),
        ],
      ),
    );
    if (picked != null) onPick(picked);
  }
}

/// منتقٍ ببحثٍ — يُستعمل للطرف والمخزن ومركز التكلفة.
///
/// ⚠️ **والبحثُ ليس زينة**: قوائمُ الأطراف قد تبلغ آلافاً، ومنتقٍ بلا بحثٍ
/// يجعل اختيارَ عميلٍ تمريراً لا ينتهي — وهو العطبُ نفسُه الذي عولج في
/// قائمة العملاء والموردين.
class _SearchPickerDialog extends StatefulWidget {
  const _SearchPickerDialog({required this.title, required this.items});

  final String title;
  final List<({int id, String title, String subtitle})> items;

  @override
  State<_SearchPickerDialog> createState() => _SearchPickerDialogState();
}

class _SearchPickerDialogState extends State<_SearchPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final muted = _fMuted(context);
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.title.toLowerCase().contains(q) ||
                i.subtitle.toLowerCase().contains(q))
            .toList();

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x, size: 16),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    isDense: true,
                    prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass,
                        size: 15, color: muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('لا نتائج',
                            style: TextStyle(color: muted)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return ListTile(
                            dense: true,
                            title: Text(it.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            subtitle: it.subtitle.isEmpty
                                ? null
                                : Text(it.subtitle,
                                    style: TextStyle(
                                        fontSize: 11, color: muted)),
                            onTap: () => Navigator.pop(context, it.id),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

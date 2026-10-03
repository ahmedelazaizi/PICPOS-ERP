import 'package:ural_erp/core/i18n/tr.dart';
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
import '../../core/tax/effective_item_tax_rate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/number_utils.dart';
import '../../domain/models/import_purchase_plan.dart';
import '../../domain/models/invoice_due_date.dart';
import '../../domain/models/picpos_invoice_draft.dart';

part 'picpos_invoice_layout.dart';
part 'picpos_invoice_lines.dart';
part 'picpos_invoice_money.dart';
part 'picpos_invoice_one_time_customer.dart';

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
  // أمرُ الشراء المصدر — `null` حين لا رابط.
  //
  // 🔴 **ويجب أن يصل المحرّك**: هو ما يستهلك الأمرَ في نفس معاملة الفاتورة.
  // ولو سُقط لبقي الأمرُ مفتوحاً بعد أن دخلت بضاعتُه، فيحوّله أحدٌ من شاشة
  // الأوامر وتدخل مرّتَين.
  required int? sourceOrderId,
});

/// حفظُ المسودّة — ومعناه يختلف بالنمط اختلافاً جوهريّاً:
///
/// • **المشتريات**: لا شيء — حُذف الفعلُ بقرار المالك 2026-09-19 (كان
///   ينادي `onSave(isDraft: true)` ومعاملاً لا يقرؤه أحد، فيرحّل فاتورةً
///   آجلةً كاملة). ويمنعه توكيدٌ في `PicPosInvoiceForm`.
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

/// معاينةُ A4 **قبل الحفظ** — قرارُ المالك على تصميم `12.02.29`.
///
/// ⚠️ **بلا رقمِ مستند**: الرقمُ يُولَّد داخلَ معاملة الحفظ (‏Spec 066)، فلا
/// رقمَ يُطبَع قبلها. وتخمينُه على ورقةٍ تبدو مستنداً ضريبيّاً أسوأُ من عدم
/// المعاينة: يطبع المستخدمُ «INV-1043» ثمّ يُحفَظ المستندُ برقمٍ آخر.
typedef PicPosInvoicePreviewCallback = Future<void> Function({
  required int? partyId,
  required DateTime date,
  required List<Map<String, dynamic>> items,
  required double subtotal,
  required double discount,
  required double tax,
  required double net,
  required double paid,
  required String notes,
});

/// عملةُ الإدخال المعروضةُ في [PicPosInvoiceForm.entryCurrency].
typedef PicPosEntryCurrency = ({
  int id,
  String code,
  String symbol,
  double localPerForeign,
});

class PicPosInvoiceForm extends StatefulWidget {
  const PicPosInvoiceForm({
    super.key,
    required this.kind,
    this.entryCurrency,
    required this.parties,
    required this.products,
    required this.warehouses,
    required this.costCenters,
    required this.systemTaxRate,
    required this.invoiceNumberPreview,
    required this.onSave,
    required this.onCancel,
    this.onSaveDraft,
    this.onPreviewA4,
    this.userName = '',
    this.initialWarehouseId,
    this.initialCostCenterId,
    this.availableStock,
    this.purchaseOrders = const [],
    this.onPullPurchaseOrder,
    this.initial,
    this.revenueAccounts = const [],
    this.defaultRevenueAccountId,
    this.onRevenueAccountChanged,
    this.purchaseAccounts = const [],
    this.defaultPurchaseAccountId,
    this.initialPurchaseAccountId,
    this.onPurchaseAccountChanged,
    this.onOneTimeCustomerChanged,
    this.onSaveAsPermanentCustomer,
  })  :
        // 🔴 **فعلُ المسوّدة للمبيعات وحدَها** — قرارُ المالك 2026-09-19.
        //
        // في المبيعات هو `_saveQuotation`: **مستندٌ آخرُ حقيقيٌّ** (عرضُ سعر)
        // له تبويبُه ولا يحرّك مخزوناً ولا مالاً. وفي المشتريات كان ينادي
        // عينَ مسار الحفظ بـ`isDraft: true` — ومعاملاً **لا يقرؤه أحد**: فيتحرّك
        // المخزونُ ويُرحَّل القيدُ وتُقيَّد ذمّةُ المورّد، ويُختَم المستندُ على
        // **أوّل مخزنٍ في النطاق** لأنّ المسار يمرّر `null`.
        //
        // والتوكيدُ هنا لا في المنادي: منادٍ جديدٌ يعيد توصيلَه يقع على خطأ
        // يُرى عند أوّل فتحٍ للشاشة، لا على رقمٍ خاطئٍ في الدفاتر.
        // (‏`kind.isSales` مُوصِلٌ لا ثابتٌ، وهذا مُنشئٌ `const` — فالمقارنةُ
        // بالقيمة هي الصيغةُ التي يقبلها المحلّل.)
        assert(onSaveDraft == null || kind == PicPosInvoiceKind.sales,
            'فعلُ المسوّدة للمبيعات وحدَها — والمشترياتُ خطوةٌ واحدة');

  final PicPosInvoiceKind kind;

  /// معاينةُ A4 قبل الحفظ — `null` ⇒ لا زرَّ لها.
  ///
  /// ⚠️ **والزرُّ يتبع الرابطَ لا النمط**: مسارُ المعاينة مبنيٌّ للمبيعات
  /// وحدَها في هذه الدفعة، وزرٌّ يُعرَض بلا ما ينفّذه أسوأُ من غيابه.
  final PicPosInvoicePreviewCallback? onPreviewA4;

  /// أوامرُ الشراء **المفتوحة** — فارغةٌ تعني «لا ربطَ في هذا النطاق».
  ///
  /// ⚠️ شاشةُ أوامر الشراء في نطاق `unified` وحدَه، والترشيحُ يقع عند
  /// المنادي: النموذجُ لا يعرف `ScreenId` ولا يقرأ إعداداً.
  final List<PicPosPurchaseOrderOption> purchaseOrders;

  /// يجلب بنودَ أمرٍ بعينه عند اختياره.
  ///
  /// البنودُ لا تُحمَّل مع القائمة: أمرٌ واحدٌ قد يحمل عشرات، والقائمةُ
  /// تُحمَّل لتُعرَض.
  final Future<List<PicPosInvoiceLine>> Function(int orderId)?
      onPullPurchaseOrder;

  final List<PicPosPartyOption> parties;
  final List<PicPosProductOption> products;
  final List<PicPosWarehouseOption> warehouses;
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

  /// حالةُ البدء حين تُفتَح على فاتورةٍ قائمة — `null` ⇒ فاتورةٌ جديدة.
  ///
  /// ووجودُها يقلب تسميةَ الفعل إلى «حفظ التعديلات»: زرٌّ يقول «حفظ
  /// الفاتورة» على تحريرٍ يوهم بإنشاء ثانية.
  final PicPosInvoiceInitial? initial;

  /// عملةُ **الإدخال** حين تخالف المحلّيّة — المشتريات الخارجيّة (المرحلة ٨).
  ///
  /// ⚠️ **ولا تُغيّر حساباً واحداً في هذا النموذج.** الأرقامُ تُجمَع وتُخصَم
  ///    وتُضرَّب في الضريبة كما هي؛ وأثرُها **عرضيٌّ حصراً**: رمزُ العملة
  ///    فوق الإجماليّ، وسطرُ المقابل المحلّيّ تحته.
  ///
  /// 🔴 **والتحويلُ يقع عند المنادي لا هنا** (‏`import_purchases_picpos`):
  ///    لهذا النموذج ثلاثةُ منادين، ولمسار الشراء نفسِه مساران (محلّيٌّ
  ///    وحمولةُ JSON إلى الخادم). فتحويلٌ داخلَ النموذج كان يجعل كلَّ منادٍ
  ///    يرث سلوكاً لم يطلبه، ومسارَ الخادم يرى أرقاماً محوَّلةً مرّتَين أو
  ///    غيرَ محوَّلةٍ أصلاً — بلا فرقٍ يظهر على الشاشة.
  ///
  /// و`null` ⇒ فاتورةٌ محلّيّة، وهو حالُ كلِّ منادٍ قائم.
  final PicPosEntryCurrency? entryCurrency;

  /// C2 — حساباتُ الإيراد التفصيليّة النشطة كلُّها، لحقل «حساب المبيعات».
  /// فارغةٌ ⇒ لا حقل (المشتريات، أو منادٍ لا يعرفها) ويبقى الافتراضيّ.
  final List<PicPosNamedOption> revenueAccounts;

  /// الحسابُ المربوطُ لغرض المبيعات — القيمةُ الابتدائيّة للحقل.
  final int? defaultRevenueAccountId;

  /// يُنادى قبل [onSave] مباشرةً بالحساب المختار (`null` = الافتراضيّ).
  ///
  /// ردُّ نداءٍ منفصلٌ لا وسيطٌ في [PicPosInvoiceSaveCallback]: العقدُ
  /// مشتركٌ بين ثلاثة منادين واختباراتهم، والمشترياتُ لا شأنَ لها بالإيراد.
  final ValueChanged<int?>? onRevenueAccountChanged;

  /// J1b — الحساباتُ التفصيليّة النشطة الصالحةُ لمدين المشتريات (مصروف/أصل)،
  /// لحقل «حساب المشتريات». فارغةٌ ⇒ لا حقل (المبيعات، أو منادٍ لا يعرفها).
  final List<PicPosNamedOption> purchaseAccounts;

  /// الحسابُ المربوطُ الذي يدين له قيدُ المشتريات اليوم — الاختيارُ الافتراضيّ
  /// حين لا يحمل المستندُ حساباً مخزَّناً.
  final int? defaultPurchaseAccountId;

  /// الحسابُ المخزَّن على الفاتورة المفتوحة للتحرير (`null` ⇒ الافتراضيّ).
  final int? initialPurchaseAccountId;

  /// يُنادى قبل [onSave] مباشرةً بالحساب المختار (`null` = الافتراضيّ).
  final ValueChanged<int?>? onPurchaseAccountChanged;

  /// J3 — اسمُ العميل لمرّةٍ واحدة (+ الهاتف) حين يكون الطرفُ «عميل نقدي».
  /// يُنادى قبل [onSave] مباشرةً (`null` في الحقلين لأيّ طرفٍ آخر). `null` ⇒
  /// لا حقول.
  final PicPosOneTimeCustomerCallback? onOneTimeCustomerChanged;

  /// J3 — «حفظ كعميل دائم»: يُنشئ المنادي عميلاً حقيقيّاً ويُرجعه، فتنتقل
  /// الفاتورةُ إليه قبل الحفظ. `null` ⇒ لا زرّ.
  final PicPosSavePermanentCustomer? onSaveAsPermanentCustomer;

  bool get isEdit => initial != null;

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

  /// J3 — اسمُ/هاتفُ العميل لمرّةٍ واحدة على «عميل نقدي»، والعملاءُ الذين
  /// أُنشئوا من هذه الشاشة بـ«حفظ كعميل دائم» (ليسوا في [widget.parties]).
  String _oneTimeName = '';
  String _oneTimePhone = '';
  final _createdParties = <PicPosPartyOption>[];

  /// أمرُ الشراء المربوط — يُمرَّر إلى الحفظ فيُستهلَك في نفس المعاملة.
  int? _sourceOrderId;
  int? _warehouseId;
  int? _costCenterId;

  /// C2 — «حساب المبيعات» المختار؛ يبدأ بالافتراضيّ المربوط.
  int? _revenueAccountId;

  /// J1b — «حساب المشتريات» المختار؛ يبدأ بالمخزَّن على الفاتورة ثم بالافتراضيّ.
  int? _purchaseAccountId;

  /// «تفاصيل إضافية» مطويّةٌ ابتداءً — كما في التصميم.
  bool _detailsOpen = false;
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
    _revenueAccountId = widget.defaultRevenueAccountId;
    _purchaseAccountId =
        widget.initialPurchaseAccountId ?? widget.defaultPurchaseAccountId;

    // ═══ التحرير: تُملأ الحقولُ كلُّها دفعةً ═══
    //
    // ⚠️ وبعد إسناد المخزن أعلاه لا قبلَه: حالةُ البدء أولى بالمخزن من
    // الافتراضيّ، وإلّا انتقل التحريرُ إلى مخزنٍ آخرَ بلا أن يلمس أحدٌ شيئاً.
    final init = widget.initial;
    if (init != null) {
      _lines.addAll(init.lines);
      _partyId = init.partyId;
      if (init.warehouseId != null) _warehouseId = init.warehouseId;
      _costCenterId = init.costCenterId;
      _supplierInvoiceController.text = init.supplierInvoiceNumber;
      _notesController.text = init.notes;
      // ملاحظةٌ قائمةٌ لا تُخفى خلف صفٍّ مطويّ.
      _detailsOpen = init.notes.trim().isNotEmpty;
      if (init.date != null) _date = init.date!;
      _paymentMethod = init.paymentMethod;
      _discountController.text =
          init.headerDiscount.toStringAsFixed(AppConstants.decimalPlaces);
      _paidController.text =
          init.paid.toStringAsFixed(AppConstants.decimalPlaces);
      // 🔴 **والمسدَّدُ لا تُعيد التهيئةُ كتابتَه.** `picPosAutoPaid` تملأ
      // الصافيَ ما لم يكتبه المستخدم، وعلى فاتورةٍ قائمةٍ يعني ذلك أن يصير
      // المسدَّدُ كاملاً بمجرّد فتحها — فيُنشأ سندُ صرفٍ لم يُصدره أحد.
      _paidTouched = true;
    }

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
      widget.parties.where((p) => p.id == _partyId).firstOrNull ??
      _createdParties.where((p) => p.id == _partyId).firstOrNull;

  /// المخزنُ المختار — مصدرُ «الفرع» المعروض.
  PicPosWarehouseOption? get _selectedWarehouse =>
      widget.warehouses.where((x) => x.id == _warehouseId).firstOrNull;

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
        final rate = effectiveItemTaxRate(
          rate: p.taxRate,
          exempt: p.taxExempt,
          companyDefault: widget.systemTaxRate,
        );
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
    if (_warehouseId == null) return tr('يجب اختيار المخزن قبل حفظ الفاتورة');
    if (_partyId == null) return tr('يجب اختيار {p0}', {'p0': widget.kind.partyLabel});
    if (_lines.isEmpty) return tr('أضف صنفاً واحداً على الأقل');
    if (_supplierInvoiceMissing) {
      return tr('أدخل رقم فاتورة المورد قبل الحفظ — مطلوب للمطابقة الضريبية');
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
      // C2 — الحسابُ المختار يُسلَّم قبل الحفظ ليقرأه ردُّ النداء. والافتراضيُّ
      // نفسُه يُسلَّم `null`: فاتورةٌ على الحساب المربوط تبقى على سلوكها
      // القديم حرفاً (وتتبع الربطَ لو تغيّر لاحقاً).
      if (widget.kind.isSales) {
        widget.onRevenueAccountChanged?.call(
          _revenueAccountId != widget.defaultRevenueAccountId
              ? _revenueAccountId
              : null,
        );
      }
      // J1b — نفسُ حكم المبيعات: الافتراضيُّ يُسلَّم `null` فتبقى الفاتورةُ تتبع
      // الربطَ. وفي التحرير يُسلَّم الاختيارُ دائماً (`null` = العودةُ للافتراضيّ).
      if (!widget.kind.isSales) {
        widget.onPurchaseAccountChanged?.call(
          _purchaseAccountId != widget.defaultPurchaseAccountId
              ? _purchaseAccountId
              : null,
        );
      }
      _publishOneTimeCustomer();
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
        sourceOrderId: _sourceOrderId,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// يفتح معاينةَ A4 بالقيم المعروضة — بلا حفظٍ وبلا رقم.
  Future<void> _previewA4() async {
    final cb = widget.onPreviewA4;
    if (cb == null) return;
    if (_lines.isEmpty) {
      _toast(tr('أضف صنفاً واحداً على الأقل قبل المعاينة'));
      return;
    }
    final t = _totals;
    setState(() => _saving = true);
    try {
      _publishOneTimeCustomer();
      await cb(
        partyId: _partyId,
        date: _date,
        items: _lines.map((l) => l.toSaveMap(widget.kind)).toList(),
        subtotal: t.subtotal,
        // نفسُ الأرقام التي تذهب إلى الحفظ حرفاً — ورقةُ معاينةٍ تحسب
        // بنفسها ليست معاينة.
        discount: t.discountTotal,
        tax: t.tax,
        net: t.net,
        paid: t.clampPaid(_paidRaw),
        notes: _notesController.text,
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
      _toast(tr('أضف صنفاً واحداً على الأقل'));
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
      // اتّجاهُ اللغة النشطة لا RTL مفروض — الشاشةُ تعمل بالعربيّة والإنجليزيّة
      // (المرحلة C1). والعربيّةُ تبقى RTL لأنّ التطبيقَ يضعها كذلك.
      textDirection: Directionality.maybeOf(context) ?? ui.TextDirection.rtl,
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
        // ═══ تخطيطُ المرجع (المرحلة C1) — عمودٌ واحدٌ كما في تصميم المالك ═══
        //
        // رأسُ الصفحة ← بطاقةُ الحقول ← سطرُ البحث ← البنود ← الإجماليّات
        // والدفع ← «تفاصيل إضافية» المطويّة ← شريطُ الأفعال الثابت. والبناءُ
        // في `picpos_invoice_layout.dart`؛ الأفعالُ هي نفسُها `_save` و
        // `_saveDraft` و`_previewA4` و`onCancel` بلا مسارٍ جديد.
        child: Focus(
          autofocus: true,
          child: _PicPosInvoiceLayout(state: this),
        ),
      ),
    );
  }

  /// هل يُعرَض شريطُ «أمر الشراء المصدر»؟
  ///
  /// ثلاثةُ شروطٍ معاً، وأيُّها ناقصٌ يعني زرّاً لا يفعل شيئاً: النمطُ شراءٌ،
  /// وثمّة أوامرُ مفتوحة، ومنادٍ يعرف كيف يجلب بنودَها.
  /// 🔴 **ولا ربطَ على فاتورةٍ قائمة**: `updatePurchaseInvoice` لا يستهلك
  /// أمراً، فزرٌّ هنا يسحب بنوداً ويترك الأمرَ مفتوحاً — ثمّ يحوّله أحدٌ من
  /// شاشة الأوامر فتدخل البضاعةُ مرّتَين. والمنعُ هنا لا عند المنادي وحدَه:
  /// شرطُ المنادي عُرفٌ يُنسى، وهذا عقدُ الودجت.
  bool get _canLinkPurchaseOrder =>
      !widget.kind.isSales &&
      !widget.isEdit &&
      widget.onPullPurchaseOrder != null &&
      widget.purchaseOrders.isNotEmpty;

  /// يربط أمراً ويسحب بنودَه **بدل** ما في الجدول.
  ///
  /// ⚠️ **بدلاً لا إضافةً**: الإضافةُ فوق بنودٍ قائمةٍ تُنتج فاتورةً لا
  /// تطابق أمرَها، والأمرُ يُستهلَك كاملاً على أيّ حال — فيدخل المخزونَ ما
  /// لم يُطلَب. ولهذا يُستأذَن حين يكون الجدولُ غيرَ فارغ.
  Future<void> _linkPurchaseOrder(BuildContext context) async {
    final pull = widget.onPullPurchaseOrder;
    if (pull == null) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _SearchPickerDialog(
        title: tr('اختر أمر شراء'),
        items: [
          for (final o in widget.purchaseOrders)
            (id: o.id, title: o.orderNumber, subtitle: o.subtitle),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;

    if (_lines.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:  Text(tr('استبدال البنود؟')),
          content:  Text(
              tr('بنودُ أمر الشراء ستحلّ محلَّ البنود الحالية — لأنّ الأمرَ يُستهلَك كاملاً بهذه الفاتورة.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:  Text(tr('استبدال'))),
          ],
        ),
      );
      if (replace != true) return;
    }

    final order = widget.purchaseOrders.where((o) => o.id == picked).firstOrNull;
    final pulled = await pull(picked);
    if (!mounted) return;
    setState(() {
      _sourceOrderId = picked;
      _lines
        ..clear()
        ..addAll(pulled);
      // المورّدُ يتبع الأمرَ: فاتورةٌ على مورّدٍ آخرَ تستهلك أمرَ هذا
      // المورّد تقيّد الذمّةَ على الطرف الخطأ.
      if (order != null) _partyId = order.supplierId;
    });
    _syncAutoPaid();
  }

  void _unlinkPurchaseOrder() {
    // البنودُ تبقى: فكُّ الربط يعني «لن أستهلك هذا الأمر»، لا «امحُ ما
    // أدخلتُه». ومحوُها بلا طلبٍ يفقد عملَ المستخدم.
    setState(() => _sourceOrderId = null);
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
    final party = state._party;

    final fields = <Widget>[
      _field(
        context,
        icon: PhosphorIconsBold.calendarBlank,
        label: tr('التاريخ والوقت'),
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
        label: tr('رقم الفاتورة'),
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
          label: tr('البائع'),
          value: w.userName,
          // بلا سهمٍ: عرضٌ لا اختيار (اقرأ `userName` في الودجت).
          trailing: null,
        ),
      // 🔴 **الفرعُ مقفولٌ على فرع المخزن** — قرارُ المالك على تصميم
      //    `12.02.29`.
      //
      //    وهو في المحرّك ليس اختياراً: `createSalesInvoice` و
      //    `createPurchaseInvoice` كلاهما يشتقّ `branchId` من
      //    `warehouses.branch_id` حين لا يمرّره المنادي — وهذه الشاشةُ لا
      //    تمرّره. فمنتقي فرعٍ كان يَعِد بما لا يقع: يختار المستخدمُ فرعاً
      //    ويُختَم المستندُ على فرع المخزن، ثمّ يبحث عنه في تقارير فرعٍ آخر.
      _field(
        context,
        icon: PhosphorIconsBold.buildings,
        label: tr('الفرع'),
        value: state._selectedWarehouse == null
            ? tr('يتبع المخزن')
            : (state._selectedWarehouse!.branchName ?? tr('غير مخصّص لفرع')),
        trailing: PhosphorIconsBold.lockSimple,
        // ⚠️ مخزنٌ بلا فرعٍ ليس عطباً في العرض: المستندُ يُختَم
        //    `branch_id = NULL` فيسقط من كلّ تقريرٍ مرشَّحٍ بفرع. وقولُ ذلك
        //    قبل الحفظ أرخصُ من اكتشافه آخرَ الشهر.
        valueColor: state._selectedWarehouse != null &&
                state._selectedWarehouse!.branchName == null
            ? AppColors.warning
            : muted,
      ),
      _field(
        context,
        icon: PhosphorIconsBold.warehouse,
        label: tr('المخزن'),
        value: w.warehouses
                .where((x) => x.id == state._warehouseId)
                .firstOrNull
                ?.name ??
            tr('اختر'),
        trailing: PhosphorIconsBold.caretDown,
        valueColor: state._warehouseId == null ? AppColors.error : null,
        onTap: () => _pick(
          context,
          title: tr('المخزن'),
          options: w.warehouses,
          selected: state._warehouseId,
          onPick: (id) => state.setState(() => state._warehouseId = id),
        ),
      ),
      _field(
        context,
        icon: PhosphorIconsBold.crosshair,
        label: tr('مركز التكلفة'),
        value: w.costCenters
                .where((x) => x.id == state._costCenterId)
                .firstOrNull
                ?.name ??
            tr('بلا'),
        trailing: PhosphorIconsBold.caretDown,
        onTap: () => _pick(
          context,
          title: tr('مركز التكلفة'),
          options: w.costCenters,
          selected: state._costCenterId,
          onPick: (id) => state.setState(() => state._costCenterId = id),
        ),
      ),
      // C2 — «حساب المبيعات»: اختيارٌ حرٌّ من كلّ حسابات الإيراد التفصيليّة
      // النشطة، وافتراضُه الحسابُ المربوطُ لغرض المبيعات.
      if (w.kind.isSales && w.revenueAccounts.isNotEmpty)
        _field(
          context,
          key: const Key('picpos_revenue_account_field'),
          icon: PhosphorIconsBold.chartLineUp,
          label: tr('حساب المبيعات'),
          value: w.revenueAccounts
                  .where((x) => x.id == state._revenueAccountId)
                  .firstOrNull
                  ?.name ??
              tr('الحساب الافتراضي'),
          trailing: PhosphorIconsBold.caretDown,
          onTap: () => _pick(
            context,
            title: tr('حساب المبيعات'),
            options: w.revenueAccounts,
            selected: state._revenueAccountId,
            onPick: (id) => state.setState(() => state._revenueAccountId = id),
          ),
        ),
      // J1b — «حساب المشتريات»: اختيارٌ من حسابات المصروف/الأصل التفصيليّة
      // النشطة، وافتراضُه الحسابُ المربوطُ الذي يدين له قيدُ المشتريات اليوم.
      if (!w.kind.isSales && w.purchaseAccounts.isNotEmpty)
        _field(
          context,
          key: const Key('picpos_purchase_account_field'),
          icon: PhosphorIconsBold.shoppingBag,
          label: tr('حساب المشتريات'),
          value: w.purchaseAccounts
                  .where((x) => x.id == state._purchaseAccountId)
                  .firstOrNull
                  ?.name ??
              tr('الحساب الافتراضي'),
          trailing: PhosphorIconsBold.caretDown,
          onTap: () => _pick(
            context,
            title: tr('حساب المشتريات'),
            options: w.purchaseAccounts,
            selected: state._purchaseAccountId,
            onPick: (id) => state.setState(() => state._purchaseAccountId = id),
          ),
        ),
    ];

    // ═══ شبكةُ حقول الترويسة — بطاقةٌ واحدة كما في التصميم المرجعيّ ═══
    //
    // الأعمدةُ تتبع العرضَ لا عدداً ثابتاً: أربعةٌ على ١٣٦٦ فما فوق، وثلاثةٌ
    // ثمّ اثنان دونه — فلا حقلَ يُسحَق تحت ١٨٠ بكسل ولا فيضَ أفقيّ.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 1000
              ? 4
              : c.maxWidth >= 640
                  ? 3
                  : 2;
          const gap = 10.0;
          final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
          Widget cell(Widget child) => SizedBox(
                width: cellW,
                height: 64,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              );
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              cell(_partyBlock(context, party)),
              for (final f in fields) cell(f),
            ],
          );
        },
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  party?.initials ?? tr('؟'),
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
                      party?.name ?? tr('اختر {p0}', {'p0': state.widget.kind.partyLabel}),
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
                  tr('رقم فاتورة المورد'),
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
              hintText: tr('مطلوب'),
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
    Key? key,
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
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        title: tr('اختر {p0}', {'p0': w.kind.partyLabel}),
        items: [
          for (final p in [...w.parties, ...state._createdParties])
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
        title: tr('اختر {title}', {'title': title}),
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
      textDirection: Directionality.maybeOf(context) ?? ui.TextDirection.rtl,
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
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
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
                    hintText: tr('بحث...'),
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
                        child: Text(tr('لا نتائج'),
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

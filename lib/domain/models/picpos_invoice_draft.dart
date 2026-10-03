// نموذجُ مسوّدةِ فاتورةِ PicPos — **حسابٌ خالصٌ بلا واجهةٍ ولا قاعدة**.
//
// مكانُه `domain/models` لا `presentation`: الحسابُ الماليُّ يجب أن يكون
// قابلاً للاختبار بلا بناءِ شجرةِ ودجت، وحارسُ
// `presentation_db_import_guard` يمنع ملفَّ عرضٍ جديداً من لمسِ
// `data/database` أصلاً.
//
// ⚠️ **ولا يخترع هذا الملفُّ معادلةً**: كلُّ عمليّةٍ تمرّ عبر
// [FinancialUtils] — نفسِ الدوالِّ التي يستعملها نموذجا المبيعات والمشتريات
// القائمان. فلو انحرف التقريبُ هنا لاختلف ما تعرضه الشاشةُ عمّا يُحفَظ،
// وهو أسوأُ من خطأٍ صريح.
import '../../core/i18n/tr.dart';
import '../../core/utils/financial_utils.dart';

/// نمطُ المستند — يقلب التسمياتِ والحقولَ لا الحساب.
///
/// شاشتا `newsale` و`newpur` في التصميم **شاشةٌ واحدة** بمتغيّرٍ واحد، فبناءُ
/// توأمَين متطابقَين بنسبة ٩٠٪ كان سيخلق ملفَّين ينحرفان بأوّل تعديل.
enum PicPosInvoiceKind {
  sales,
  purchase;

  bool get isSales => this == PicPosInvoiceKind.sales;

  /// تسميةُ الطرف — «العميل» أو «المورد».
  String get partyLabel => isSales ? tr('العميل') : tr('المورد');

  /// تسميةُ عمود السعر — `priceLabel` في التصميم.
  String get priceLabel => isSales ? tr('سعر البيع') : tr('سعر الشراء');

  /// هل يقبل مسارُ الحفظ خصماً **لكلّ سطر**؟
  ///
  /// 🔴 **بوّابةٌ واحدةٌ يقرؤها العمودُ وخريطةُ الحفظ معاً.** لو قرأ
  /// كلٌّ منهما شرطَه الخاصَّ لانفصلا يوماً، والنتيجةُ أسوأُ الاثنين: عمودٌ
  /// يُعرَض ويُكتَب فيه ولا يصل القاعدةَ — حقلٌ يبتلع ما يُكتَب فيه صامتاً.
  /// وحارسٌ بنيويٌّ يثبّت أنّ الموضعَين يقرآن هذا الرمزَ بعينه.
  ///
  /// ⚠️ **والمشترياتُ وحدَها اليوم**: `createPurchaseInvoice`
  /// يوزّع خصمَ السطر على التكلفة عبر `resolvePurchaseLineNets` (قرارُ
  /// المالك 2026-09-18)، بينما `createSalesInvoice` لا يعرف خصماً إلّا على
  /// المستند — فعمودٌ في المبيعات كان سيُبتلَع.
  bool get supportsLineDiscount => this == PicPosInvoiceKind.purchase;

  /// عنوانُ بطاقة الدفع.
  String get payTitle =>
      isSales ? tr('التحصيل من العميل') : tr('السداد للمورد');

  /// تسميةُ المبلغ المدفوع الآن.
  String get paidLabel => isSales ? tr('المحصّل الآن') : tr('المسدّد الآن');

  /// تسميةُ الصافي في البطاقة الداكنة.
  String get netLabel => isSales
      ? tr('الإجمالي المستحق على العميل')
      : tr('الإجمالي المستحق للمورد');
}

/// طرفٌ في المنتقي — عميلٌ أو مورّد.
///
/// ⚠️ **ولماذا نوعٌ خاصٌّ بدل `Party` مباشرةً:** حارسُ
/// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
/// `data/database`، وقائمتُه البيضاء مقفولة. فالشاشةُ الجديدة تستقبل أنواعاً
/// من `domain` والمستدعي (وهو ملفٌّ قديمٌ يستورد القاعدةَ أصلاً) يحوّل إليها.
/// والفائدةُ ليست إرضاءَ حارسٍ فحسب: الشاشةُ صارت قابلةً للاختبار بلا قاعدة.
class PicPosPartyOption {
  const PicPosPartyOption({
    required this.id,
    required this.name,
    this.meta = '',
    this.paymentTermsDays,
    this.isCashParty = false,
  });

  final int id;
  final String name;

  /// J3 — الطرفُ النظاميُّ «عميل نقدي»: تظهر له حقولُ اسم العميل لمرّةٍ
  /// واحدة و«حفظ كعميل دائم».
  final bool isCashParty;

  /// مهلةُ السداد المتّفقة بالأيّام — مصدرُ «تاريخ الاستحقاق» المعروض.
  ///
  /// ‏`null` أو صفرٌ يعني **بلا مهلة**، فلا يُعرَض تاريخٌ أصلاً. راجع
  /// [resolveDueDateFromTerms].
  final int? paymentTermsDays;

  /// سطرُ التفاصيل تحت الاسم — «آجل · حد ائتمان …» أو «مورد · سداد ٣٠ يوم».
  final String meta;

  /// الأحرفُ الأولى للمربّع الملوّن في التصميم.
  ///
  /// تُشتقّ من أوّل كلمتَين، والاسمُ ذو الكلمة الواحدة يعطي حرفاً واحداً —
  /// ولا تُرمى استثناءً على اسمٍ فارغٍ (وهو واردٌ من صفٍّ ناقص).
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return '${parts[0].substring(0, 1)}.${parts[1].substring(0, 1)}';
  }
}

/// صنفٌ في منتقي الإضافة السريعة.
class PicPosProductOption {
  const PicPosProductOption({
    required this.id,
    required this.name,
    required this.salePrice,
    required this.costPrice,
    this.categoryId,
    this.sub = '',
    this.taxRate = 0,
    this.taxExempt = false,
    this.unitName = 'قطعة',
    this.barcode = '',
  });

  final int id;
  final String name;

  /// السطرُ الخافتُ تحت الاسم — الفئةُ أو الباركود.
  final String sub;

  final double salePrice;
  final double costPrice;
  final int? categoryId;
  final double taxRate;

  /// B3 — `products.tax_exempt`: the line is taxed at 0 % (sales and
  /// purchases alike) — see `effectiveItemTaxRate`.
  final bool taxExempt;
  final String unitName;
  final String barcode;

  /// السعرُ المناسبُ للنمط — بيعاً أو شراءً.
  double priceFor(PicPosInvoiceKind kind) =>
      kind.isSales ? salePrice : costPrice;
}

/// خيارٌ مسمّىً بسيط — مخزنٌ أو مركزُ تكلفة.
class PicPosNamedOption {
  const PicPosNamedOption({required this.id, required this.name});
  final int id;
  final String name;
}

/// مخزنٌ في المنتقي — ومعه **اسمُ فرعه**.
///
/// ═══ لماذا الفرعُ على المخزن لا حقلاً مستقلّاً ═══
///
/// تصميمُ المالك `12.02.29` يرسم «الفرع» بجوار «المستودع». وهو في المحرّك
/// **ليس اختياراً**: `createSalesInvoice` و`createPurchaseInvoice` كلاهما
/// يشتقّ `branchId` من `warehouses.branch_id` حين لا يمرّره المنادي، وهذه
/// الشاشةُ لا تمرّره. فمنتقي فرعٍ كان سيَعِد بما لا يقع — يختار المستخدمُ
/// فرعاً ويُختَم المستندُ على فرع المخزن.
///
/// ⚠️ و`null` تعني **«غيرُ مخصَّصٍ لفرع»** لا «لم يُحمَّل»: مخزنٌ عامٌّ يُختَم
/// على فاتورته `branch_id = NULL`، فتسقط من كلّ تقريرٍ مرشَّحٍ بفرع. وقولُ
/// ذلك على الشاشة قبل الحفظ أرخصُ من اكتشافه في تقريرٍ آخرَ الشهر.
class PicPosWarehouseOption extends PicPosNamedOption {
  const PicPosWarehouseOption({
    required super.id,
    required super.name,
    this.branchName,
  });

  final String? branchName;
}

/// حالةُ البدء حين تُفتَح الشاشةُ على فاتورةٍ **قائمة** (تحرير).
///
/// ═══ ولماذا نوعٌ واحدٌ لا عشرةُ معاملات ═══
///
/// التحريرُ يملأ عشرةَ حقولٍ معاً، وأيُّ واحدٍ يُنسى يُحفَظ بقيمةٍ خاطئةٍ
/// بلا رسالة: مخزنٌ يعود إلى الافتراضيّ، أو مسدَّدٌ يعود صفراً فيُنشأ سندٌ
/// لم يُصدره أحد. فالحزمةُ واحدةٌ يقرؤها `initState` دفعةً.
///
/// 🔴 **و[headerDiscount] ليس `invoice.discount`.** المخزَّنُ هو **مجموعُ**
/// الخصم (حقلُ الترويسة + خصومُ السطور)، والنموذجُ يجمعهما بنفسه
/// (`PicPosInvoiceTotals.discountTotal`). فملءُ الحقل بالمجموع يحسبه
/// **مرّتَين** — راجع [resolvePurchaseLineGross] وبانيَ هذه الحزمة عند
/// المنادي.
class PicPosInvoiceInitial {
  const PicPosInvoiceInitial({
    required this.lines,
    this.partyId,
    this.warehouseId,
    this.costCenterId,
    this.supplierInvoiceNumber = '',
    this.notes = '',
    this.date,
    this.paid = 0,
    this.paymentMethod = 'cash',
    this.headerDiscount = 0,
  });

  final List<PicPosInvoiceLine> lines;
  final int? partyId;
  final int? warehouseId;
  final int? costCenterId;
  final String supplierInvoiceNumber;
  final String notes;
  final DateTime? date;
  final double paid;
  final String paymentMethod;

  /// خصمُ المستند **بعد** طرح خصوم السطور منه.
  final double headerDiscount;
}

/// أمرُ شراءٍ **مفتوحٌ** صالحٌ لأن تُسحَب بنودُه — الاتّجاهُ الجديد بقرار
/// المالك 2026-09-18: من داخل الفاتورة ← اختَر أمراً، لا من الأمر ← أنشئ
/// فاتورة.
///
/// ⚠️ **ولا يحمل البنود**: الأمرُ الواحدُ قد يحمل عشرات، وقائمةُ الأوامر
/// تُحمَّل لتُعرَض. فالبنودُ تُجلَب عند الاختيار وحدَه
/// (`onPullPurchaseOrder`).
class PicPosPurchaseOrderOption {
  const PicPosPurchaseOrderOption({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.orderDate,
    required this.total,
  });

  final int id;
  final String orderNumber;
  final int supplierId;
  final String supplierName;
  final DateTime orderDate;
  final double total;

  /// السطرُ الخافتُ في المنتقي — المورّدُ والتاريخُ والإجماليّ.
  String get subtitle =>
      '$supplierName · ${orderDate.toString().substring(0, 10)} · '
      '${total.toStringAsFixed(2)}';
}

/// سطرُ بنودٍ واحد.
///
/// ‏**والخصمُ لكلّ سطرٍ في المشتريات وحدَها** — راجع
/// [PicPosInvoiceKind.supportsLineDiscount]. كان العمودُ موجوداً في التصميم
/// وفي القاعدة (`PurchaseInvoiceItems.discount`) وبلا كاتب، فوُصل مسارُ
/// الشراء حتى `resolvePurchaseLineNets` (قرارُ المالك 2026-09-18). ومسارُ
/// المبيعات لم يُوصَل بعد، فلا يُعرَض له العمودُ أصلاً — لا يُعرَض ويُبتلَع.
class PicPosInvoiceLine {
  const PicPosInvoiceLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.categoryId,
    this.taxRate = 0,
    this.taxEnabled = false,
    this.unitName = 'قطعة',
    this.discount = 0,
  });

  final int productId;
  final String productName;
  final int? categoryId;
  final double quantity;

  /// سعرُ البيع في نمط المبيعات، وسعرُ الشراء في نمط المشتريات.
  final double unitPrice;

  final double taxRate;

  /// الضريبةُ تُحسَب فقط حين تكون مفعَّلةً على السطر — حبّةُ التبديل في
  /// التصميم. ونسبةُ صفرٍ تعطي صفراً بأيّ حال ([FinancialUtils] يحرسها).
  final bool taxEnabled;

  final String unitName;

  /// خصمُ هذا السطر **مبلغاً** لا نسبةً — قرارُ المالك «يُثبَّت، لا مفتاح».
  ///
  /// ‏[appliedDiscount] هو ما يُحسَب ويُحفَظ؛ وهذا ما كتبه المستخدمُ خاماً.
  final double discount;

  /// إجماليُّ السطر **قبل** الضريبة و**قبل** الخصم — نفسُ اصطلاح النموذجَين
  /// القائمَين (`lineTotal` عندهما لا يشمل الضريبة). وهو «المجموع» في شريط
  /// الإجماليّات.
  double get lineSubtotal =>
      FinancialUtils.calculateLineSubtotal(quantity, unitPrice);

  /// الخصمُ المطبَّقُ فعلاً — محصورٌ في [0, lineSubtotal].
  ///
  /// ⚠️ **والحصرُ هنا لا عند المنادي**: خصمٌ أكبرُ من قيمة السطر كان
  /// يُنتج سطراً صافيه صفرٌ بينما ترويسةُ المستند تطرح المبلغَ كاملاً —
  /// فتنفصل الترويسةُ عن سطورها. والمحرّكُ يحصره أيضاً
  /// (`resolvePurchaseLineNets`)، فالحصرُ هنا يجعل المعروضَ هو المحفوظ.
  double get appliedDiscount {
    if (discount <= 0) return 0.0;
    final cap = lineSubtotal;
    return discount > cap ? cap : discount;
  }

  /// صافي السطر بعد خصمِه الصريح — وعاءُ الضريبة.
  double get lineNet =>
      FinancialUtils.round(lineSubtotal - appliedDiscount);

  /// ضريبةُ السطر — صفرٌ حين تُطفأ الحبّة.
  ///
  /// ⚠️ **على الصافي لا على الإجماليّ**: الخصمُ التجاريُّ يخفّض وعاءَ
  /// الضريبة، فاحتسابُها على الإجماليّ يُقرّ ضريبةَ مدخلاتٍ لم تُدفَع.
  /// وبلا خصمٍ يتطابق الوعاءان حرفاً.
  double get taxAmount => taxEnabled
      ? FinancialUtils.calculateTaxAmount(lineNet, taxRate)
      : 0.0;

  /// ما يُعرض في عمود «الإجمالي» — بعد الخصم وشاملاً ضريبةَ السطر كي يقرأ
  /// المستخدمُ ما سيدفعه في هذا السطر لا نصفَه.
  double get lineTotalWithTax =>
      FinancialUtils.round(lineNet + taxAmount);

  PicPosInvoiceLine copyWith({
    double? quantity,
    double? unitPrice,
    bool? taxEnabled,
    String? unitName,
    double? discount,
  }) =>
      PicPosInvoiceLine(
        productId: productId,
        productName: productName,
        categoryId: categoryId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        taxRate: taxRate,
        taxEnabled: taxEnabled ?? this.taxEnabled,
        unitName: unitName ?? this.unitName,
        discount: discount ?? this.discount,
      );

  /// الشكلُ الذي يفهمه مسارُ الحفظ القائم — **بمفاتيحَ مختلفةٍ بين النمطَين**.
  ///
  /// المبيعاتُ تقرأ `unitPrice` والمشترياتُ تقرأ `unitCost`، والمشترياتُ
  /// وحدَها تقرأ `selectedUnitName` و`taxEnabled`. وهذا مقيسٌ من
  /// `sales_invoice_form.dart:236` و`purchase_invoice_form.dart:250` —
  /// ومفتاحٌ واحدٌ خاطئٌ هنا يعني بنداً يُحفَظ بسعرِ صفر.
  Map<String, dynamic> toSaveMap(PicPosInvoiceKind kind) {
    final base = <String, dynamic>{
      'productId': productId,
      'productName': productName,
      'categoryId': categoryId,
      'quantity': quantity,
      'taxRate': taxRate,
      'taxAmount': taxAmount,
      'lineTotal': lineSubtotal,
    };
    if (kind.isSales) {
      base['unitPrice'] = unitPrice;
    } else {
      base['unitCost'] = unitPrice;
      base['taxEnabled'] = taxEnabled;
      base['selectedUnitName'] = unitName;
    }
    // 🔴 **نفسُ البوّابة التي يقرؤها العمود.** المفتاحُ لا يُكتَب لنمطٍ
    // لا يقرؤه مسارُ حفظه — فلا يبقى في الخريطة رقمٌ يظنُّ قارئُه أنّه وصل.
    if (kind.supportsLineDiscount) {
      base['discount'] = appliedDiscount;
    }
    return base;
  }
}

/// إجمالياتُ المستند — تُشتقّ من السطور ولا تُخزَّن، فلا تتباعد عنها.
class PicPosInvoiceTotals {
  const PicPosInvoiceTotals({
    required this.subtotal,
    required this.tax,
    required this.headerDiscount,
    required this.lineCount,
    required this.quantityTotal,
    this.lineDiscount = 0,
  });

  /// مجموعُ السطور قبل الضريبة وقبل خصمِ المستند.
  final double subtotal;

  /// مجموعُ ضرائب السطور.
  final double tax;

  /// خصمُ المستند — ما كُتب في حقل «خصم على الفاتورة» وحدَه.
  final double headerDiscount;

  /// مجموعُ خصوم السطور الصريحة.
  final double lineDiscount;

  final int lineCount;
  final double quantityTotal;

  /// الخصمُ المعروضُ في شريط الإجماليّات، وهو **ما يُمرَّر إلى المحرّك**.
  ///
  /// 🔴 **والمحرّكُ يقرأ خصمَ المستند على أنّه المجموع** ثمّ يحفر منه
  /// خصمَ كلّ سطر (`resolvePurchaseLineNets`). فتمريرُ حقل الترويسة وحدَه
  /// كان سيجعل ترويسةَ الفاتورة تقول «بلا خصم» وسطورَها مخصومة.
  double get discountTotal =>
      FinancialUtils.round(headerDiscount + lineDiscount);

  /// الصافي = الفرعي + الضريبة − الخصمِ كلِّه.
  ///
  /// نفسُ ترتيب `_netAmount` في نموذج المشتريات القائم حرفاً بحرف. وعكسُ
  /// الترتيب (خصمٌ قبل ضريبة) كان سيعطي رقماً مختلفاً على نفس المدخلات.
  double get net => FinancialUtils.round(subtotal + tax - discountTotal);

  /// المتبقي بعد ما دُفع — لا يقلّ عن صفر.
  double remainingAfter(double paid) =>
      FinancialUtils.round((net - clampPaid(paid)));

  /// المدفوعُ محصورٌ في [0, net].
  ///
  /// ‏`net` سالبٌ ممكنٌ نظريّاً (خصمُ مستندٍ يتجاوز الفرعيَّ)، و`clamp` على
  /// مدىً مقلوبٍ يرمي استثناءً — فيُحرَس الحدُّ الأعلى بألّا يقلَّ عن صفر.
  double clampPaid(double paid) {
    if (paid <= 0) return 0;
    final ceiling = net > 0 ? net : 0.0;
    return paid > ceiling ? ceiling : paid;
  }

  /// نسبةُ ما سُدِّد من الصافي — للشريط والنِّسَب.
  ///
  /// صافٍ صفرٌ يعطي صفراً لا `Infinity`: القسمةُ على صفرٍ في Dart لا ترمي.
  double paidPct(double paid) {
    if (net <= 0) return 0;
    return (clampPaid(paid) / net * 100).clamp(0, 100).toDouble();
  }

  static PicPosInvoiceTotals from(
    List<PicPosInvoiceLine> lines, {
    double headerDiscount = 0,
  }) {
    var subtotal = 0.0;
    var tax = 0.0;
    var qty = 0.0;
    var lineDiscount = 0.0;
    for (final l in lines) {
      subtotal += l.lineSubtotal;
      tax += l.taxAmount;
      qty += l.quantity;
      lineDiscount += l.appliedDiscount;
    }
    return PicPosInvoiceTotals(
      subtotal: FinancialUtils.round(subtotal),
      tax: FinancialUtils.round(tax),
      headerDiscount: headerDiscount,
      lineDiscount: FinancialUtils.round(lineDiscount),
      lineCount: lines.length,
      quantityTotal: qty,
    );
  }
}

/// ما يجب أن يُظهره حقلُ «المحصَّل الآن» تهيئةً — أو `null` إن كان يجب
/// تركُه كما هو.
///
/// ── العطبُ الذي وُلدت منه (بلاغُ المالك 2026-08-23) ───────────────────────
/// «فاتورةٌ بوسيلة دفعٍ نقديّ تظهر غيرَ مدفوعةٍ ومديونيّةً على العميل».
/// وسببُه أنّ الحبّةَ تبدأ مختارةً على `cash` بينما الحقلُ يبدأ `'0'`،
/// والتهيئةُ كانت تعيش **داخل `onTap` وحدَها**. فمن قبِل الافتراضَ ولم ينقر
/// حفظ صفراً: نقدٌ في الدرج ودَينٌ في الدفاتر.
///
/// ── والحدُّ المحفوظُ عمداً ────────────────────────────────────────────────
/// ‏[userEdited] يوقف التهيئةَ نهائيّاً. فالحقلُ يبقى **مصدرَ الحقيقة
/// الوحيد** لِما يُحفَظ، وهذه تهيئةٌ لا إلزام — وهو الدرسُ المكتوبُ في
/// `_handleSave` القائم: وضعُ الدفع كان **يفرض** سداداً كاملاً فيُنشئ سنداً
/// لم يُصدره أحد. الفرقُ أنّ المعروضَ هنا يُرى قبل الحفظ ويُعدَّل بحرّية.
///
/// و«آجل» وحدَه يُصفِّر؛ و«تحويل» مالٌ وصل فعلاً فيتبع الصافيَ كالنقد.
double? picPosAutoPaid({
  required String paymentMethod,
  required double net,
  required bool userEdited,
}) {
  if (userEdited) return null;
  if (paymentMethod == 'credit') return 0;
  return net > 0 ? net : 0;
}

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
  String get partyLabel => isSales ? 'العميل' : 'المورد';

  /// تسميةُ عمود السعر — `priceLabel` في التصميم.
  String get priceLabel => isSales ? 'سعر البيع' : 'سعر الشراء';

  /// عنوانُ بطاقة الدفع.
  String get payTitle => isSales ? 'التحصيل من العميل' : 'السداد للمورد';

  /// تسميةُ المبلغ المدفوع الآن.
  String get paidLabel => isSales ? 'المحصّل الآن' : 'المسدّد الآن';

  /// تسميةُ الصافي في البطاقة الداكنة.
  String get netLabel =>
      isSales ? 'الإجمالي المستحق على العميل' : 'الإجمالي المستحق للمورد';
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
  });

  final int id;
  final String name;

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

/// سطرُ بنودٍ واحد.
///
/// ‏**لا خصمَ على مستوى السطر** رغم وجود العمود في التصميم وفي القاعدة
/// (`PurchaseInvoiceItems.discount` و`SalesInvoiceItems.discount`): مسارُ
/// الحفظ القائم لا يقرأ `item['discount']` ولا يحمل `PurchaseItemParams`
/// حقلاً له، فالقيمةُ كانت ستُكتَب صفراً مهما أدخل المستخدم — حقلٌ يبتلع ما
/// يُكتَب فيه صامتاً. والخصمُ على مستوى **المستند** يُحفَظ فعلاً، فهو
/// المعروض. يُرفَع هذا حين يُمَدَّ العقدُ حتى القاعدة.
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

  /// إجماليُّ السطر **قبل** الضريبة — نفسُ اصطلاح النموذجَين القائمَين
  /// (`lineTotal` عندهما لا يشمل الضريبة).
  double get lineSubtotal =>
      FinancialUtils.calculateLineSubtotal(quantity, unitPrice);

  /// ضريبةُ السطر — صفرٌ حين تُطفأ الحبّة.
  double get taxAmount => taxEnabled
      ? FinancialUtils.calculateTaxAmount(lineSubtotal, taxRate)
      : 0.0;

  /// ما يُعرض في عمود «الإجمالي» — شاملاً ضريبةَ السطر كي يقرأ المستخدمُ
  /// ما سيدفعه في هذا السطر لا نصفَه.
  double get lineTotalWithTax =>
      FinancialUtils.round(lineSubtotal + taxAmount);

  PicPosInvoiceLine copyWith({
    double? quantity,
    double? unitPrice,
    bool? taxEnabled,
    String? unitName,
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
  });

  /// مجموعُ السطور قبل الضريبة وقبل خصمِ المستند.
  final double subtotal;

  /// مجموعُ ضرائب السطور.
  final double tax;

  /// خصمُ المستند — الخصمُ الوحيدُ الذي يصل القاعدةَ فعلاً (اقرأ
  /// [PicPosInvoiceLine]).
  final double headerDiscount;

  final int lineCount;
  final double quantityTotal;

  /// الصافي = الفرعي + الضريبة − خصمِ المستند.
  ///
  /// نفسُ ترتيب `_netAmount` في نموذج المشتريات القائم حرفاً بحرف. وعكسُ
  /// الترتيب (خصمٌ قبل ضريبة) كان سيعطي رقماً مختلفاً على نفس المدخلات.
  double get net => FinancialUtils.round(subtotal + tax - headerDiscount);

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
    for (final l in lines) {
      subtotal += l.lineSubtotal;
      tax += l.taxAmount;
      qty += l.quantity;
    }
    return PicPosInvoiceTotals(
      subtotal: FinancialUtils.round(subtotal),
      tax: FinancialUtils.round(tax),
      headerDiscount: headerDiscount,
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

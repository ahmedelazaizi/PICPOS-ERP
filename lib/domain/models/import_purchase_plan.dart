// حسابُ فاتورة الاستيراد — **خالصٌ**، بلا قاعدةٍ ولا ودجت.
//
// ═══ 🔴 اتّجاهُ السعر يُسمّى ولا يُضرَب في موضع النداء ═══
//
// `Currencies.exchangeRate` **وحداتُ العملةِ المحلّيّةِ مقابلَ وحدةٍ واحدةٍ
// أجنبيّة** — الجنيهُ المصريُّ مبذورٌ بـ`0.02` «مقابل الدينار»، و
// `convertToBase` في `multi_currency_dao` تضرب: `amount * rate`. فالاتّجاهُ
// **ضربٌ لا قسمة**.
//
// ⚠️ وقلبُه لا يُرى: بسعرٍ ٥٠ تصير فاتورةُ ألفٍ مليوناً أو عشرين، وكلاهما
//    «رقمٌ كبير» أو «رقمٌ صغير» لا رسالةَ خطأٍ فيه. ولهذا **لا تُضرَب هنا
//    قيمةٌ بمتغيّرٍ اسمُه `rate` في موضع النداء**: النداءُ يسمّي الوحدةَ
//    ([localPerForeign]) والدالّةُ وحدَها تعرف الاتّجاه. وهذا عينُ علاجِ
//    عائلةِ التباسِ الوحدات المقيسة في هذا المستودع.
//
// ═══ 🔴 والتحويلُ يقع مرّةً واحدةً — في النموذج ═══
//
// مسارُ الشراء **مساران**: `createPurchaseInvoice` محلّيّاً، وحمولةُ JSON
// إلى الخادم في وضع العميل ثمّ `insertPurchaseInvoiceWithoutStock` للنسخة
// المحلّيّة. فتحويلٌ داخلَ المحرّك يعني **ثلاثةَ مواضعِ تحويل** يتفرّق
// بينها رقمُ الذمّة بلا أن يظهر شيء.
//
// فالنموذجُ يحوّل، وما ينزل إلى الطبقات كلِّها **محلّيٌّ بالفعل**، و
// [currencyId]/[exchangeRate] لقطةٌ للسجلّ لا مُعامِلٌ يُعاد تطبيقُه.
// ولذلك **لا يقرأ أيُّ قارئٍ السعرَ ليضربَ به**: الضربُ تمّ.
//
// ═══ ⚠️ ولا فروقَ صرفٍ بقرار المالك 2026-09-18 (الخيارُ أ) ═══
//
// الذمّةُ محلّيّةٌ منذ لحظةِ الترحيل، فلا إعادةَ ترجمةٍ عند السداد ولا
// مكاسبَ/خسائرَ صرفٍ محقَّقة. و`JournalEntries.currency_id` — الذي يقرأه
// `calculateFxRevaluation` على أنّه **مبلغٌ أجنبيّ** — بلا كاتبٍ واحدٍ في
// `lib/`، فلا يتقاطع هذا مع ذاك.

import '../../core/utils/financial_utils.dart';

/// أدنى سعرِ صرفٍ يُقبَل. صفرٌ يُصفّر الفاتورةَ كلَّها، والسالبُ يقلب
/// إشارةَ الذمّة.
const double kMinExchangeRate = 0.000001;

/// أقصى طولٍ لكلّ حقلٍ مستنديّ — **مطابقٌ لـ`withLength` في الجدول**.
///
/// 🔴 والفحصُ هنا لا في القاعدة: الفاتورةُ ووسمُها يُكتبان في معاملةٍ
/// واحدة، فحرفٌ زائدٌ في «بوليصة الشحن» كان يرمي خطأَ drift غامضاً **بعد**
/// أن حُسبت الذمّةُ وتحرّك المخزون — فتتراجع المعاملةُ كلُّها والمستخدمُ
/// يقرأ رسالةً لا تدلّ على الحقل.
const int kCustomsDeclarationNoMax = 50;
const int kBillOfLadingMax = 60;
const int kCountryOfOriginMax = 60;
const int kPortMax = 60;
const int kLetterOfCreditMax = 50;
const int kClearingAgentNameMax = 100;

/// عملةٌ معروضةٌ في منتقي الفاتورة.
typedef ImportCurrencyOption = ({
  int id,
  String code,
  String name,
  String symbol,
  double localPerForeign,
  bool isBase,
});

/// تحويلُ مبلغٍ أجنبيٍّ إلى المحلّيّ.
///
/// ⚠️ [localPerForeign] **وحداتٌ محلّيّةٌ لكلّ وحدةٍ أجنبيّة** — راجع رأسَ
///    الملفّ. والتقريبُ إلى دقّةِ المال هنا لا عند العرض: الرقمُ المقرَّب هو
///    الذي يدخل الذمّةَ والمخزونَ والقيد، فتقريبٌ متأخّرٌ يجعل مجموعَ
///    السطور يخالف الترويسة.
double foreignToLocal({
  required double foreign,
  required double localPerForeign,
}) =>
    FinancialUtils.round(foreign * localPerForeign);

/// سببُ رفضِ سعرِ الصرف، أو `null` إن جاز.
///
/// [currencyId] فارغةٌ ⇒ فاتورةٌ محلّيّةٌ ولا سعرَ لها أصلاً.
String? validateExchangeRate({
  required int? currencyId,
  required double? localPerForeign,
}) {
  if (currencyId == null) {
    // 🔴 سعرٌ بلا عملةٍ مُعامِلٌ بلا وحدة: يضرب الأرقامَ ولا يقول بماذا.
    if (localPerForeign != null) {
      return 'سعرُ صرفٍ بلا عملة — اختر العملة أو امسح السعر';
    }
    return null;
  }
  if (localPerForeign == null) {
    // 🔴 وعملةٌ بلا سعرٍ تُقرأ لاحقاً على أنّها ١: تُقيَّد ألفُ دولارٍ
    //    على أنّها ألفُ وحدةٍ محلّيّة، والقيدُ متّزنٌ على الرقم الخاطئ.
    return 'اكتب سعر الصرف — العملةُ بلا سعرٍ تُقيَّد كأنّها محلّيّة';
  }
  if (localPerForeign < kMinExchangeRate) {
    return 'سعرُ الصرف لا بدّ أن يكون أكبر من صفر';
  }
  return null;
}

/// الحقولُ المستنديّةُ كما تُخزَّن.
typedef ImportDocumentFields = ({
  String? customsDeclarationNo,
  String? billOfLading,
  String? countryOfOrigin,
  String? port,
  String? letterOfCredit,
  int? clearingAgentPartyId,
  String? clearingAgentName,
  String? notes,
});

/// تطبيعُ المدخلات: فراغٌ ⇒ `null`، و**الطرفُ المسجَّلُ يُسقط النصّ**.
///
/// ⚠️ حين يُختار وكيلُ تخليصٍ مسجَّلٌ يبقى `clearingAgentPartyId` وحدَه:
///    الاسمُ يُقرأ بوصلةٍ إلى `parties` فيتبع تعديلَه، ولقطةٌ نصّيّةٌ إلى
///    جانبه كانت ستُعارضه بعد أوّلِ إعادةِ تسمية — حقلان يقولان اسمَين.
ImportDocumentFields normalizeImportDocument({
  String? customsDeclarationNo,
  String? billOfLading,
  String? countryOfOrigin,
  String? port,
  String? letterOfCredit,
  int? clearingAgentPartyId,
  String? clearingAgentName,
  String? notes,
}) {
  String? clean(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  return (
    customsDeclarationNo: clean(customsDeclarationNo),
    billOfLading: clean(billOfLading),
    countryOfOrigin: clean(countryOfOrigin),
    port: clean(port),
    letterOfCredit: clean(letterOfCredit),
    clearingAgentPartyId: clearingAgentPartyId,
    clearingAgentName:
        clearingAgentPartyId != null ? null : clean(clearingAgentName),
    notes: clean(notes),
  );
}

/// سببُ رفضِ الحقول المستنديّة، أو `null` إن جازت.
///
/// ⚠️ **ولا حقلَ منها إلزاميّ.** بضاعةٌ لم تُخلَّص بعدُ بلا بيانٍ جمركيّ،
///    وشراءٌ بلا اعتمادٍ مستنديٍّ شائع. فالمطلوبُ طولٌ يسع القاعدةَ لا
///    استمارةٌ تُملأ.
String? validateImportDocument(ImportDocumentFields d) {
  String? tooLong(String label, String? value, int max) =>
      (value != null && value.length > max)
          ? '$label أطولُ من $max حرفاً'
          : null;

  return tooLong('البيان الجمركي', d.customsDeclarationNo,
          kCustomsDeclarationNoMax) ??
      tooLong('بوليصة الشحن', d.billOfLading, kBillOfLadingMax) ??
      tooLong('بلد المنشأ', d.countryOfOrigin, kCountryOfOriginMax) ??
      tooLong('الميناء', d.port, kPortMax) ??
      tooLong('الاعتماد المستندي', d.letterOfCredit, kLetterOfCreditMax) ??
      tooLong('وكيل التخليص', d.clearingAgentName, kClearingAgentNameMax);
}

/// هل خلا المستندُ من كلّ حقل؟
///
/// ⚠️ **ولا يمنع الحفظَ.** صفُّ التفاصيل هو **الوسمُ** الذي يفرز فاتورةَ
///    الاستيراد عن المحلّيّة — لا `currencyId` (فشراءٌ بعملةٍ أجنبيّةٍ من
///    مورّدٍ محلّيٍّ ليس استيراداً). فصفٌّ فارغٌ يُكتَب ويُقرأ «استيرادٌ
///    لم تصل أوراقُه بعد»، وعدمُ كتابته كان يُخفي الفاتورةَ عن شاشتها
///    التي أُنشئت فيها.
bool importDocumentIsEmpty(ImportDocumentFields d) =>
    d.customsDeclarationNo == null &&
    d.billOfLading == null &&
    d.countryOfOrigin == null &&
    d.port == null &&
    d.letterOfCredit == null &&
    d.clearingAgentPartyId == null &&
    d.clearingAgentName == null &&
    d.notes == null;

/// سطرٌ بالعملة الأجنبيّة كما يُدخِله المستخدم.
typedef ImportLineInput = ({
  double quantity,
  double unitCostForeign,
  double discountForeign,
  double taxRate,
  bool taxEnabled,
});

/// السطرُ بعد التحويل — **بالمحلّيّة، وهو ما يصل المحرّك**.
typedef ImportLineLocal = ({
  double quantity,
  double unitCost,
  double discount,
  double taxRate,
  double taxAmount,
  double total,
});

/// تحويلُ سطورِ الفاتورة إلى المحلّيّة.
///
/// ⚠️ **الضريبةُ تُحسَب بعد التحويل لا قبلَه.** حسابُها أجنبيّةً ثمّ ضربُها
///    يعطي نفسَ الرقم رياضيّاً، لكنّه يُقرَّب مرّتَين — فيفترق مجموعُ
///    ضرائبِ السطور عن ضريبةِ الترويسة بقرشٍ، وهو عينُ الفرق الذي
///    يُفشل مطابقةَ وعاء الضريبة.
List<ImportLineLocal> convertImportLines({
  required List<ImportLineInput> lines,
  required double localPerForeign,
}) {
  final out = <ImportLineLocal>[];
  for (final l in lines) {
    final unitCost =
        foreignToLocal(foreign: l.unitCostForeign, localPerForeign: localPerForeign);
    final discount =
        foreignToLocal(foreign: l.discountForeign, localPerForeign: localPerForeign);
    final gross = FinancialUtils.round(l.quantity * unitCost);
    final net = FinancialUtils.round(gross - discount);
    final taxAmount =
        l.taxEnabled ? FinancialUtils.round(net * (l.taxRate / 100)) : 0.0;
    out.add((
      quantity: l.quantity,
      unitCost: unitCost,
      discount: discount,
      taxRate: l.taxRate,
      taxAmount: taxAmount,
      total: FinancialUtils.round(net + taxAmount),
    ));
  }
  return out;
}

/// إجماليّان متلازمان — ما اتّفق عليه المورّد، وما يدخل الدفتر.
typedef ImportTotalsPreview = ({double foreign, double local});

/// ⚠️ **ويُعرَضان معاً.** عرضُ المحلّيّ وحدَه يُخفي ما وقّع عليه المشتري،
///    وعرضُ الأجنبيّ وحدَه يُخفي ما سيُقيَّد على المورّد. والفرقُ بينهما هو
///    كلُّ ما في هذه الشاشة.
ImportTotalsPreview importTotalsPreview({
  required List<ImportLineInput> lines,
  required double localPerForeign,
  double documentDiscountForeign = 0,
}) {
  var foreign = 0.0;
  for (final l in lines) {
    final gross = l.quantity * l.unitCostForeign;
    final net = gross - l.discountForeign;
    foreign += net + (l.taxEnabled ? net * (l.taxRate / 100) : 0);
  }
  foreign = FinancialUtils.round(foreign - documentDiscountForeign);
  return (
    foreign: foreign,
    local: foreignToLocal(foreign: foreign, localPerForeign: localPerForeign),
  );
}

/// حمولةُ الوسم إلى الخادم — **بلا `clearingAgentPartyId`**.
///
/// 🔴 **ورقمُ الطرف المحلّيُّ لا يسافر.** رقمُ العميل ورقمُ الخادم يتباعدان
/// بالتصميم، فرقمٌ محلّيٌّ يصل الخادمَ قد يُطابِق **طرفاً آخرَ تماماً** —
/// فيُنسَب التخليصُ إلى مورّدٍ لا علاقةَ له. وهو عينُ ما يوثّقه
/// `_buildLandedCostDocument`. فالمنادي (‏`_CwiTrading.submitPurchase`)
/// يُلحِق `clearingAgentGlobalId`، والخادمُ يحلّه بـ`resolvePartyId`.
Map<String, dynamic> importDocumentToJson(ImportDocumentFields d) => {
      'customsDeclarationNo': d.customsDeclarationNo,
      'billOfLading': d.billOfLading,
      'countryOfOrigin': d.countryOfOrigin,
      'port': d.port,
      'letterOfCredit': d.letterOfCredit,
      'clearingAgentName': d.clearingAgentName,
      'notes': d.notes,
    };

/// عكسُ [importDocumentToJson] على الخادم.
///
/// [clearingAgentPartyId] يأتي من حلِّ المعرِّف العالميِّ لا من الحمولة.
ImportDocumentFields importDocumentFromJson(
  Map<String, dynamic> j, {
  int? clearingAgentPartyId,
}) {
  String? str(Object? v) {
    final t = (v as String?)?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  return normalizeImportDocument(
    customsDeclarationNo: str(j['customsDeclarationNo']),
    billOfLading: str(j['billOfLading']),
    countryOfOrigin: str(j['countryOfOrigin']),
    port: str(j['port']),
    letterOfCredit: str(j['letterOfCredit']),
    clearingAgentPartyId: clearingAgentPartyId,
    clearingAgentName: str(j['clearingAgentName']),
    notes: str(j['notes']),
  );
}

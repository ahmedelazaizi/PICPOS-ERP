// نموذجُ عرضِ «العملاء والموردين» بهويّة PicPos — **حسابٌ خالصٌ بلا واجهةٍ
// ولا قاعدة**.
//
// مكانُه `domain/models` لا `presentation` لنفس سببِ [PicPosInvoiceDraft]:
// حارسُ `presentation_db_import_guard` يمنع ملفَّ عرضٍ **جديداً** من استيراد
// `data/database`، وقائمتُه البيضاء مقفولة. فالشاشةُ تستقبل [PicPosPartyCard]
// والمستدعي — وهو ملفٌّ قديمٌ يستورد القاعدةَ أصلاً — يحوّل `Party` إليه.
//
// والفائدةُ الأكبرُ ليست إرضاءَ حارس: الترشيحُ والعدّاداتُ صارت قابلةً
// للاختبار بلا بناءِ شجرةِ ودجت ولا فتحِ قاعدة.
//
// ⚠️ **ولا يخترع هذا الملفُّ حقلاً**: كلُّ ما يُعرض مشتقٌّ من أعمدةٍ قائمةٍ
// في جدول `parties`. التصميمُ يطلب سطرَ «آخر حركة» ولا عمودَ يحمله —
// `lastModifiedAt` حقلُ مزامنةٍ لا حركةٌ ماليّة — فأُسقط السطرُ ولم يُختلق.
// راجع §الفجوات المعروفة في نهاية الملف.
import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../core/utils/financial_utils.dart';

/// ترشيحُ نوع الطرف — الأشرطةُ الخمسةُ في شريط التصميم.
///
/// القيمُ نصّيّةٌ متطابقةٌ مع ما كانت الشاشةُ تحمله في `_typeFilter` قبل
/// إعادةِ التصميم (`all`/`customer`/`supplier`/`delivery`/`both`)، فالانتقالُ
/// لا يغيّر دلالةَ ترشيحٍ قائمة.
enum PicPosPartyFilter {
  all('all', 'الكل'),
  customer('customer', 'عملاء'),
  supplier('supplier', 'موردين'),
  delivery('delivery', 'توصيل'),
  both('both', 'عميل مورد');

  const PicPosPartyFilter(this.id, this.label);

  final String id;
  final String label;

  String get displayLabel => tr(label);

  static PicPosPartyFilter fromId(String id) => values.firstWhere(
        (f) => f.id == id,
        orElse: () => PicPosPartyFilter.all,
      );
}

/// بطاقةُ طرفٍ واحدة — صورةُ عرضٍ ثابتةٌ لصفٍّ من `parties`.
///
/// كلُّ الحقولِ هنا أعمدةٌ حقيقيّة. ما يُشتقّ ([initials] · [typeLabel] ·
/// [isOverLimit] · [balanceLabel]) يُحسب من تلك الأعمدة لا من مصدرٍ آخر.
class PicPosPartyCard {
  const PicPosPartyCard({
    required this.id,
    required this.name,
    required this.balance,
    required this.creditLimit,
    this.phone,
    this.address,
    this.isCustomer = false,
    this.isSupplier = false,
    this.isDeliveryCompany = false,
  });

  final int id;
  final String name;

  /// `+` مدينٌ علينا له… لا: **موجبٌ = مدين (علىٰ الطرف)** — نفسُ اصطلاح
  /// العمود في القاعدة (`+debit / -credit`).
  final double balance;
  final double creditLimit;
  final String? phone;
  final String? address;
  final bool isCustomer;
  final bool isSupplier;
  final bool isDeliveryCompany;

  /// أوّلُ حرفٍ من أوّل كلمتَين — بديلُ الصورة في التصميم.
  ///
  /// اسمٌ من كلمةٍ واحدةٍ يعطي حرفاً واحداً لا حرفَين مصطنعَين، واسمٌ فارغٌ
  /// (لا يقع عمليّاً؛ العمودُ `NOT NULL`) يعطي `؟` لا انهياراً.
  ///
  /// القطعُ بـ`runes` لا بـ`[0]`: اسمٌ يبدأ برمزٍ خارج المستوى الأساسيّ
  /// (زوجٌ بديل) كان `substring(0, 1)` سيشطره نصفَ محرفٍ فيُرسم مربّعاً.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '؟';
    return words
        .take(2)
        .map((w) => String.fromCharCodes(w.runes.take(1)))
        .join();
  }

  /// تسميةُ النوع في الشارة.
  ///
  /// ⚠️ **النصوصُ منقولةٌ حرفيّاً عن `getPartyTypeLabel`** في
  /// `presentation/screens/parties/party_helpers.dart` — بنفس ترتيبِ
  /// الأولويّة. الفوركان يعرضان نفسَ الطرف؛ فلو كتبتُ «توصيل» هنا و«شركة
  /// توصيل» هناك لصار الاختلافُ عيباً يُبلَّغ عنه لا اختصاراً.
  String get typeLabel {
    if (isDeliveryCompany) return tr('شركة توصيل');
    if (isCustomer && isSupplier) return tr('عميل مورد');
    if (isCustomer) return tr('عميل');
    if (isSupplier) return tr('مورد');
    return tr('غير محدد');
  }

  /// هل تجاوز الرصيدُ حدَّ الائتمان؟
  ///
  /// **حدٌّ صفريٌّ يعني «بلا حدّ» لا «حدَّ صفر»** — وهو ما تعنيه القاعدة:
  /// العمودُ افتراضُه `0` ويُترك كذلك لمن لا حدَّ له، فلو قرأناه حرفيّاً
  /// لصار كلُّ عميلٍ عليه قرشٌ «متجاوزاً».
  bool get isOverLimit => creditLimit > 0 && balance > creditLimit;

  /// نصُّ الرصيد بالعملة — بـ[AppConstants.decimalPlaces] لا برقمٍ مكتوبٍ
  /// بخطِّ اليد (‏قِيس: هو **٣** لا ٢).
  String get balanceLabel =>
      '${FinancialUtils.round(balance).toStringAsFixed(AppConstants.decimalPlaces)}'
      ' ${AppConstants.currencySymbolEn}';

  /// تسميةُ حدّ الائتمان — أو «بلا حدّ» حين يكون صفراً.
  String get creditLimitLabel => creditLimit > 0
      ? tr('حد {p0}', {'p0': creditLimit.toStringAsFixed(0)})
      : tr('بلا حدّ ائتمان');

  /// سطرُ التفاصيل تحت الاسم: «الهاتف · العنوان».
  ///
  /// التصميمُ يكتب `{{ p.phone }} · {{ p.city }}`، ولا عمودَ `city` في
  /// الجدول — فالعنوانُ هو أقربُ حقلٍ **موجود**. وغيابُ أحدهما يُسقط الفاصلَ
  /// معه فلا يظهر «· » معلّقاً.
  String get subtitle {
    final parts = <String>[
      if (phone != null && phone!.trim().isNotEmpty) phone!.trim(),
      if (address != null && address!.trim().isNotEmpty) address!.trim(),
    ];
    return parts.isEmpty ? tr('لا توجد بيانات اتصال') : parts.join(' · ');
  }

  /// هل يطابق هذا الطرفُ الترشيحَ والبحث؟
  ///
  /// دلالةُ البحثِ **هي هي** التي كان فلترُ Dart في الشاشة يطبّقها قبل
  /// إعادةِ التصميم: الاسمُ أو الهاتف، بلا حساسيّةٍ لحالة الأحرف.
  bool matches(PicPosPartyFilter filter, String query) {
    switch (filter) {
      case PicPosPartyFilter.all:
        break;
      case PicPosPartyFilter.customer:
        if (!isCustomer) return false;
      case PicPosPartyFilter.supplier:
        if (!isSupplier) return false;
      case PicPosPartyFilter.delivery:
        if (!isDeliveryCompany) return false;
      case PicPosPartyFilter.both:
        if (!(isCustomer && isSupplier)) return false;
    }

    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        (phone?.toLowerCase().contains(q) ?? false);
  }
}

/// عدّاداتُ البطاقات الأربعِ أعلى الشاشة.
///
/// ⚠️ **تُحسب من القائمة المعروضة بعد الترشيح؟ لا — من القائمة الكاملة.**
/// عدّادٌ يتغيّر مع كلّ ضغطةِ مفتاحٍ في البحث لا يُعلِم بشيء؛ والمقصودُ
/// «كم عندي» لا «كم أرىٰ الآن».
class PicPosPartyKpis {
  const PicPosPartyKpis({
    required this.total,
    required this.customers,
    required this.suppliers,
    required this.totalDebit,
    required this.totalCredit,
    required this.overLimitCount,
  });

  factory PicPosPartyKpis.from(Iterable<PicPosPartyCard> parties) {
    var total = 0;
    var customers = 0;
    var suppliers = 0;
    var debitMinor = 0;
    var creditMinor = 0;
    var overLimit = 0;

    for (final p in parties) {
      total++;
      if (p.isCustomer) customers++;
      if (p.isSupplier) suppliers++;
      if (p.isOverLimit) overLimit++;
      // الجمعُ بالوحداتِ الصغرى — **وقِيس ما يفعله ولا يفعله**:
      //
      // لا يمنع هذا انحرافاً مرئيّاً عن الجمع المباشر بـ`double`: مُسحت
      // القيمُ حتى مئةِ ألفِ صفٍّ فلم يختلف النصُّ المعروضُ عند ثلاثِ خاناتٍ
      // ولا مرّة. فالادّعاءُ بذلك كان سيكون زخرفاً.
      //
      // ما يفعله فعلاً: يُقرِّب بدل أن يبتر. رصيدٌ يحمل دقّةً أعلى من
      // المعروضة (‏0.0006) يدخل المجموعَ ملّيمَ‍اً واحداً لا صفراً — وهو
      // اتّساقٌ مع بقيّة المحرَّك المالي الذي يمرّ كلُّه عبر [FinancialUtils].
      final minor = FinancialUtils.toMinorUnits(p.balance);
      if (minor > 0) {
        debitMinor += minor;
      } else {
        creditMinor += -minor;
      }
    }

    return PicPosPartyKpis(
      total: total,
      customers: customers,
      suppliers: suppliers,
      totalDebit: FinancialUtils.fromMinorUnits(debitMinor),
      totalCredit: FinancialUtils.fromMinorUnits(creditMinor),
      overLimitCount: overLimit,
    );
  }

  final int total;
  final int customers;
  final int suppliers;

  /// مجموعُ الأرصدة الموجبة — ما **على** الأطراف.
  final double totalDebit;

  /// مجموعُ الأرصدة السالبة بإشارةٍ موجبة — ما **لهم**.
  final double totalCredit;
  final int overLimitCount;

  String get totalDebitLabel =>
      totalDebit.toStringAsFixed(AppConstants.decimalPlaces);
  String get totalCreditLabel =>
      totalCredit.toStringAsFixed(AppConstants.decimalPlaces);
}

// ═══════════════════════════════════════════════════════════════════════════
// §الفجوات المعروفة — مقصودةٌ ومكتوبةٌ لا منسيّة
// ═══════════════════════════════════════════════════════════════════════════
//
// ١) **«آخر حركة»** في التصميم أُسقط. لا عمودَ حركةٍ في `parties`؛ اشتقاقُه
//    الصادقُ يعني استعلاماً لكلّ طرفٍ على حدة (N+1) في شاشةٍ تعرض مئاتِ
//    البطاقات. يُرفَع حين يُضاف عمودٌ محسوبٌ أو استعلامُ تجميعٍ واحد.
//
// ٢) **«المدينة»** أُبدلت بـ`address` — أقربُ حقلٍ موجود. لا يوجد عمودُ
//    مدينةٍ منفصل.

// حسابُ الإهلاك — **نسخةٌ واحدةٌ للمحرّك والشاشة والحوار**.
//
// ═══ لماذا هنا ═══
//
// الصيغةُ مكتوبةٌ في `runMonthlyDepreciation` بـ`fixed_assets_dao_ext.dart`
// وهي **مصدرُ الحقيقة**: ما تكتبه هي هو ما يُقيَّد. وشاشةُ الأصول تعرض القسطَ
// قبل ترحيله، وحوارُ «أصل جديد» يعرض جدولَ الإهلاك قبل إنشاء الأصل — فثلاثةُ
// مواضعَ لصيغةٍ واحدة.
//
// 🔴 **وانحرافُها يعني رقماً يُعرَض وغيرَه يُقيَّد** — وهو أسوأُ من ألّا
// يُعرَض شيء: المستخدمُ يقرّر على الرقم المعروض.
//
// ⇒ فالحسابُ الخالصُ في `domain/models` (‏لا يستورد `data/database` فيمرّ
//   بحارس `presentation_db_import_guard`، ويُختبَر بلا قاعدة)، والمواضعُ
//   الثلاثةُ تناديه.
//
// ⚠️ **وأيُّ تعديلٍ في الـDAO يُنقَل هنا** — والعكسُ ليس صحيحاً: الـDAO هو
// الذي يكتب.
library;

/// طريقتا الإهلاك كما يكتبهما العمودُ `depreciationMethod`.
const String kStraightLine = 'straight_line';
const String kDecliningBalance = 'declining_balance';

/// المبلغُ القابل للإهلاك = التكلفة − القيمة التخريديّة.
double depreciableAmount({
  required double purchasePrice,
  required double salvageValue,
}) =>
    purchasePrice - salvageValue;

/// قسطُ الشهر الواحد.
///
/// ⚠️ **القسطُ المتناقصُ مضاعفٌ** (`2 / (n×12)`) لا ٢٠٪ كما يفترض نصُّ
/// التصميم — منقولٌ عن الـDAO حرفاً. والسقفُ يمنع تجاوزَ المبلغ القابل
/// للإهلاك، وإسقاطُه يُهلك الأصلَ إلى ما تحت قيمته التخريديّة.
///
/// و[accumulatedDepreciation] صفرٌ لأصلٍ لم يُنشَأ بعد — وهي التي تجعل
/// المتناقصَ يتناقص.
double monthlyDepreciation({
  required double purchasePrice,
  required double salvageValue,
  required double usefulLifeYears,
  required String depreciationMethod,
  double accumulatedDepreciation = 0,
}) {
  // عمرٌ صفريٌّ أو سالبٌ يقسم على صفر — والـDAO يحميه بـ`<= 0 continue`
  // بعد الحساب، وهنا يُحمى قبله فلا تُنتَج `Infinity` تُعرَض للمستخدم.
  if (usefulLifeYears <= 0) return 0;

  final depreciable =
      depreciableAmount(purchasePrice: purchasePrice, salvageValue: salvageValue);
  double monthly;

  if (depreciationMethod == kDecliningBalance) {
    final rate = 2 / (usefulLifeYears * 12);
    final bookValue = purchasePrice - accumulatedDepreciation;
    monthly = bookValue * rate;
    if (accumulatedDepreciation + monthly > depreciable) {
      monthly = depreciable - accumulatedDepreciation;
    }
  } else {
    monthly = depreciable / (usefulLifeYears * 12);
    // Audit B ACC-001: straight-line stops at the salvage value too.
    if (accumulatedDepreciation + monthly > depreciable) {
      monthly = depreciable - accumulatedDepreciation;
    }
  }

  return monthly > 0 ? monthly : 0;
}

/// شهرُ انتهاءِ العمر الإنتاجيّ — `purchaseDate` مضافاً إليه العمرُ بالأشهر.
///
/// ⚠️ **تقديرٌ للعرض لا موعدُ إقفال**: المحرّكُ يوقف الإهلاك حين يبلغ المجمَّعُ
/// المبلغَ القابلَ للإهلاك، لا في تاريخٍ بعينه. والقسطُ المتناقصُ يقترب ولا
/// يبلغ فينتهي بالسقف — فتاريخُه الفعليُّ يخالف هذا التقدير.
DateTime endOfLife({
  required DateTime purchaseDate,
  required double usefulLifeYears,
}) {
  final months = (usefulLifeYears * 12).round();
  return DateTime(
    purchaseDate.year,
    purchaseDate.month + months,
    purchaseDate.day,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// العمرُ الإنتاجيّ: الشهورُ للعرض والسنواتُ للتخزين
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 **موضعٌ واحدٌ للتحويل، وهذا هو.**
//
// `FixedAssets.usefulLifeYears` عمودٌ **بالسنوات**، وكذلك
// `AssetCategories.defaultUsefulLife`، وكذلك كلُّ صيغةٍ في هذا الملفّ
// (`usefulLifeYears * 12`). وتصميمُ المالك `(8)`/`(9)` يعرض «٣٦ شهراً».
//
// والخطرُ ليس في العرض بل في **الرقم الذي يعود**: ٣٦ تُكتَب في حقلِ سنواتٍ
// تعني إهلاكاً على **ستٍّ وثلاثين سنةً** بدل ثلاث — فالقسطُ الشهريُّ يصير
// جزءاً من اثنَي عشرَ ممّا يجب، ومصروفُ الإهلاك منقوصٌ في قائمة الدخل
// والأصلُ مضخَّمٌ في الميزانيّة لعقودٍ قبل أن يلاحظه أحد. ولا فحصَ اتّزانٍ
// يمسك ذلك: القيدُ متّزنٌ على الرقم الخاطئ.
//
// فالتحويلُ دالّتان مسمّيتان تُنادَيان في حدود العرض وحدَها، ولا يُكتَب
// `* 12` ولا `/ 12` في ملفِّ شاشةٍ أبداً.

/// عمرٌ بالسنوات ⇒ شهوراً — للعرض.
int usefulLifeMonths(double usefulLifeYears) => (usefulLifeYears * 12).round();

/// شهورٌ ⇒ سنواتٍ — للتخزين.
///
/// ⚠️ **كسريّةٌ لا صحيحة**: ٣٠ شهراً = ٢٫٥ سنة، وتقريبُها إلى ٣ يُطيل العمرَ
/// سدسَه ويخفّض القسطَ بنفس النسبة. والعمودُ `real` فيحتملها.
double usefulLifeYearsFromMonths(int months) => months / 12;

/// هل كان الأصلُ على الدفاتر في [asOf]؟
///
/// 🔴 **شرطٌ لا زينة** لمرشِّح «كما في» في تصميم المالك `(10)`: بدونه يعرض
/// جردُ «٣٠ يونيو» أصلاً اشتُري في ديسمبر — بتكلفته كاملةً ومجمَّعِ صفرٍ
/// لأنّه بلا لقطة. فيبدو الجردُ التاريخيُّ سليماً وفيه أصلٌ لم يكن قد وُجد،
/// وتكبر التكلفةُ والصافي بقيمته كاملة.
///
/// ⚠️ **والمقارنةُ باليوم لا باللحظة**: `purchaseDate` يُخزَّن عند منتصف
/// الليل (منتقي التاريخ يعيد يوماً بلا وقت)، فأصلٌ اشتُري **في** يوم النظر
/// كان سيسقط لو قُورن بأوّل ذلك اليوم.
bool assetOnBooksAt(DateTime purchaseDate, DateTime asOf) {
  final bought = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
  final at = DateTime(asOf.year, asOf.month, asOf.day);
  return !bought.isAfter(at);
}

// ═══════════════════════════════════════════════════════════════════════════
// جدولُ الإهلاك — مُرحَّلٌ ومتوقَّعٌ في قائمةٍ واحدة
// ═══════════════════════════════════════════════════════════════════════════

/// سطرٌ واحدٌ في جدول إهلاك أصل.
class DepreciationScheduleRow {
  const DepreciationScheduleRow({
    required this.periodDate,
    required this.amount,
    required this.accumulated,
    required this.bookValue,
    required this.posted,
  });

  /// أوّلُ الشهر — لا تاريخُ الترحيل. `runMonthlyDepreciation` تُخزّن ما
  /// يُمرَّر إليها (‏٢٨ من الشهر عادةً)، والمقارنةُ هنا بالسنة والشهر.
  final DateTime periodDate;

  final double amount;
  final double accumulated;
  final double bookValue;

  /// 🔴 **على الصفّ لا على الجدول.** التصميمُ يضع وسمَ «معاينة غير مرحّلة»
  /// واحداً فوق الجدول كلِّه — وجدولُ أصلٍ نصفُه مُرحَّلٌ ونصفُه توقّعٌ هو
  /// **الحالةُ الطبيعيّة** بعد أوّل شهر. فوسمٌ واحدٌ إمّا يكذب على المرحَّل
  /// أو يكذب على المتوقَّع.
  final bool posted;
}

/// شهرُ التاريخ بلا يومٍ ولا وقت.
DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

/// صفُّ إهلاكٍ مُرحَّلٌ كما يصل من القاعدة — بلا أنواع drift.
typedef PostedDepreciation = ({
  DateTime periodDate,
  double amount,
  double accumulated,
  double bookValue,
});

/// يبني الجدولَ من شهر الاقتناء حتى [until]: ما رُحِّل يُقرأ كما هو، وما
/// بعده يُحسَب بنفس صيغة المحرّك.
///
/// ⚠️ **والمرحَّلُ لا يُعاد حسابُه**: صفُّ القاعدة هو ما دخل الأستاذَ فعلاً،
/// وإعادةُ حسابه هنا كانت ستُظهر رقماً يخالف القيدَ بعد أيّ إعادة تقييمٍ
/// (‏`revalueAsset` تغيّر `purchasePrice` ولا تكتب صفَّ إهلاك).
///
/// ⚠️ **والتوقّعُ يتوقّف عند استنفاد المبلغ القابل للإهلاك** — كما يتوقّف
/// المحرّك. وبلا ذلك يمتدّ الجدولُ إلى ما لا نهاية بقسطٍ صفريّ.
List<DepreciationScheduleRow> buildDepreciationSchedule({
  required double purchasePrice,
  required double salvageValue,
  required double usefulLifeYears,
  required String depreciationMethod,
  required DateTime purchaseDate,
  required DateTime until,
  List<PostedDepreciation> posted = const [],
}) {
  final rows = <DepreciationScheduleRow>[];
  final end = _monthOf(until);
  var cursor = _monthOf(purchaseDate);
  if (end.isBefore(cursor)) return rows;

  final byMonth = <DateTime, PostedDepreciation>{
    for (final p in posted) _monthOf(p.periodDate): p,
  };

  final depreciable =
      depreciableAmount(purchasePrice: purchasePrice, salvageValue: salvageValue);
  var running = 0.0;

  // سقفٌ صلبٌ يمنع حلقةً لا تنتهي لو جاء تاريخٌ بعيدٌ جدّاً — و`until` يأتي
  // من منتقي تاريخٍ يقبل أيَّ سنة.
  var guard = 0;
  while (!cursor.isAfter(end) && guard++ < 1200) {
    final hit = byMonth[cursor];
    if (hit != null) {
      running = hit.accumulated;
      rows.add(DepreciationScheduleRow(
        periodDate: hit.periodDate,
        amount: hit.amount,
        accumulated: hit.accumulated,
        bookValue: hit.bookValue,
        posted: true,
      ));
    } else {
      final amount = monthlyDepreciation(
        purchasePrice: purchasePrice,
        salvageValue: salvageValue,
        usefulLifeYears: usefulLifeYears,
        depreciationMethod: depreciationMethod,
        accumulatedDepreciation: running,
      );
      final capped =
          running + amount > depreciable ? depreciable - running : amount;
      if (capped <= 0.0000001) break;
      running += capped;
      rows.add(DepreciationScheduleRow(
        periodDate: cursor,
        amount: capped,
        accumulated: running,
        bookValue: purchasePrice - running,
        posted: false,
      ));
    }
    cursor = DateTime(cursor.year, cursor.month + 1);
  }

  return rows;
}

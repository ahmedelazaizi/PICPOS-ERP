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

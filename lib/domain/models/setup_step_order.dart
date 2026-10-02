// ترتيبُ خطوات معالج البدء — **مسارُ التنصيب، لا تفصيلُ واجهة**.
//
// ═══ لماذا خرج من الشاشة ═══
//
// المعالجُ ٣٨٤١ سطراً في ثمانية ملفّات و**بلا اختبارِ تخطيطٍ واحد**. وأخطرُ
// ما فيه ليس شكلَه بل ترتيبَ خطواته: هو الذي يقرّر ماذا يُسأل عنه كلُّ جهازٍ
// عند تنصيبه، وإسقاطُ خطوةٍ منه يترك تنصيباً ناقصاً لا يظهر نقصُه إلّا بعد
// أيّام.
//
// وحين تبدأ إعادةُ تنسيقٍ بصريّةٌ فوق ٣٨٤١ سطراً بلا شبكةِ أمان، تكون أوّلُ
// ضحاياها هذا الترتيبَ — تُنقَل كتلةٌ فتُزاح خطوة، ولا شيءَ يقول.
//
// ⇒ فالترتيبُ حسابٌ خالصٌ هنا يُقاس بلا تركيبِ شجرة، والشاشةُ تناديه.
//
// ═══ ⚠️ وهذا الترتيبُ **قرارُ مالكٍ مثبَّت** (‏2026-08-28) ═══
//
// تصميمُ `PicPos Setup Wizard.dc.html` يخالفه في الأنماط الأربعة: يحذف
// «المستخدمين» من العميل، ويضيف «المنتجات» و«المستخدمين» للخادم، ويُنزل
// المرآةَ إلى خمس خطوات. وسُئل المالكُ صراحةً فاختار **إبقاءَ المسار الحاليّ
// وإعادةَ التنسيق وحدَها**.
//
// 🔴 فأيُّ تعديلٍ هنا يحتاج قرارَ مالكٍ جديداً — لا مراجعةَ كود.
//
// ═══ ✅ وقد صدر القرارُ الجديد: بندُ المالك ٦ (المرحلة ح) ═══
//
// طلب المالكُ صراحةً **إعادةَ هيكلة** المعالج لا تنسيقَه وحدَه: ترحيبٌ ولغة
// ← الشركةُ والنشاط ← العملةُ والضريبة ← الفرعُ والمخزن ← الصناديقُ والبنوك
// ← دليلُ الحسابات ← المستخدمون ← المراجعةُ والبدء. فالمسارُ أدناه ينفّذه،
// وما كان خطوةً مستقلّةً صار قسماً في خطوته المنطقيّة بلا أن يسقط منه شيء:
//
//   • «نمطُ التشغيل» و«نمطُ الإدخال» (‏إعدادا جهاز) → خطوةُ الترحيب؛
//   • «ملفُّ النشاط» (‏`BusinessProfile`) → خطوةُ الشركة والنشاط؛
//   • «كلمةُ مرور المطوّر» → خطوةُ المستخدمين (‏قسمُ الأمان)؛
//   • «المنتجاتُ الأولى» → خطوةٌ اختياريّةٌ قبل المراجعة (‏المستقلّ والمرآة).
//
// وتبقى قيودُ الأنماط التي شرحها القرارُ القديم: العميلُ بلا منتجاتٍ ولا
// PostgreSQL، والخادمُ بلا منتجاتٍ ويُنهي تهيئةَ قاعدته قبل المراجعة.
library;

/// أنماطُ التشغيل — مرآةُ `NetworkMode` بلا استيراد `services/`.
///
/// ⚠️ **نسخةٌ لا استيراد**: `network_service.dart` يجرّ الشبكةَ وقاعدةَ
/// البيانات معه، وهذا الحسابُ يجب أن يُقاس بلا أيٍّ منهما. والقيمُ الأربعُ
/// مغلقةٌ منذ Feature 006، فالانحرافُ غيرُ وارد — ويمسكه
/// [setupStepOrderFor] بـ`switch` شاملٍ لو زيدت خامسة.
enum SetupDeploymentMode { standalone, server, client, mirror }

/// أرقامُ الخطوات الداخليّةُ كما يعرفها `_buildCurrentStep`.
///
/// ⚠️ **لا تعدّلها**: هي مفتاحُ الربط بين السجلّ (`kSetupSteps`) وجسمِ
/// الخطوة، وتبديلُها يعرض عنوانَ خطوةٍ فوقَ جسمِ أخرى بلا أن ينهار شيء.
class SetupStepIds {
  static const int company = 0;
  static const int branchAndMode = 1;
  static const int products = 2;
  static const int users = 3;
  static const int tax = 4;
  static const int postgres = 5;
  static const int provisioning = 6;
  static const int developerPassword = 7;
  static const int businessProfile = 8;
  static const int touchMode = 9;

  // ── بندُ المالك ٦ — خطواتُ المسار الجديد ──
  //
  // ⚠️ `businessProfile` (٨) و`touchMode` (٩) و`developerPassword` (٧) **لم
  //    تعد خطواتٍ في المسار**: صارت أقساماً داخلَ `company` و`welcome`
  //    و`users`. والأرقامُ تبقى معرَّفةً لأنّ سجلَّ الخطوات يحفظ نصوصَها، ولا
  //    يُعاد استعمالُها لخطوةٍ أخرى (‏تبديلُ الرقم يعرض عنوانَ خطوةٍ فوق
  //    جسمِ أخرى بلا أن ينهار شيء).
  static const int welcome = 10;
  static const int currencyTax = 11;
  static const int cashBanks = 12;
  static const int chartOfAccounts = 13;
  static const int review = 14;
}

/// خطواتٌ يُتجاوَز عنها بلا إدخال — «التالي» عليها يعني «تخطٍّ».
///
/// ⚠️ **الصناديقُ ودليلُ الحسابات اختياريّان لأنّ لهما افتراضيّاً مزروعاً**:
/// القاعدةُ تُزرَع بصناديقَ ثلاثةٍ وشجرةِ حساباتٍ كاملةٍ عند أوّل فتح، فتخطّيهما
/// يُبقي ما زُرع كما هو — وهو عينُ سلوك المعالج القديم الذي لم يسألهما.
const Set<int> kOptionalSetupSteps = {
  SetupStepIds.products,
  SetupStepIds.cashBanks,
  SetupStepIds.chartOfAccounts,
};

/// خطواتُ النمط بترتيبها.
///
/// • **العميل** (٧): لا منتجاتٍ ولا PostgreSQL — يأخذهما من الخادم بالمزامنة.
///   وفيه «المستخدمون» عمداً: العميلُ يحتاج كاشيراً محلّيّاً.
/// • **الخادم** (٧): لا منتجاتٍ ولا مستخدمين — يزرع المديرَ ويتوقّع إنشاءَهم
///   بعد الإعداد، والمنتجاتُ تُستورَد لا تُكتَب هنا.
/// • **المستقل والمرآة** (٨): المسارُ الكامل. والمرآةُ تُنهي اقترانَها داخلَ
///   الخطوة ١ فلا تحتاج خطوةً زائدة.
///
/// و«نمطُ الإدخال» (٩) في **نفس الموضع** في الأنماط كلِّها — بعد اختيار
/// الشبكة وقبل أوّل خطوةِ بيانٍ ثقيلة (‏Feature 031 · research D13).
///
/// ═══ المسارُ الجديد (‏بندُ المالك ٦) ═══
///
/// الأربعُ الأولى واحدةٌ في كلّ نمط: ترحيبٌ ← شركةٌ ← عملةٌ وضريبة ← فرع.
/// والمراجعةُ آخرُ كلّ مسار — هي وحدَها تشغّل الإعداد.
///
/// • **المستقلّ** (٩): المسارُ الكامل — ومعه الصناديقُ ودليلُ الحسابات
///   لأنّه وحدَه يملك قاعدتَه المحلّيّة المزروعة.
/// • **المرآة** (٨): كالمستقلّ بلا الصناديق — الكتابةُ فيها تذهب للسيرفر،
///   فإعادةُ تسمية صناديقِ HQ من جهاز المدير ليست من الإعداد الأوّل.
///   ودليلُ الحسابات **معاينةٌ** لا كتابةَ فيها فيبقى.
/// • **العميل** (٦): بلا صناديقَ ولا دليلٍ ولا منتجاتٍ ولا PostgreSQL —
///   يأخذها كلَّها من الخادم بالمزامنة. و«المستخدمون» فيه عمداً (‏كاشيرٌ
///   محلّيّ) كما قرّر المالكُ في 2026-08-28.
/// • **الخادم** (٨): PostgreSQL ثمّ التهيئةُ قبل المراجعة — والصناديقُ
///   والدليلُ تزرعهما التهيئةُ في قاعدة الخادم لا هنا.
List<int> setupStepOrderFor(SetupDeploymentMode mode) {
  switch (mode) {
    case SetupDeploymentMode.client:
      return const [
        SetupStepIds.welcome,
        SetupStepIds.company,
        SetupStepIds.currencyTax,
        SetupStepIds.branchAndMode,
        SetupStepIds.users,
        SetupStepIds.review,
      ];
    case SetupDeploymentMode.server:
      return const [
        SetupStepIds.welcome,
        SetupStepIds.company,
        SetupStepIds.currencyTax,
        SetupStepIds.branchAndMode,
        SetupStepIds.users,
        SetupStepIds.postgres,
        SetupStepIds.provisioning,
        SetupStepIds.review,
      ];
    case SetupDeploymentMode.mirror:
      return const [
        SetupStepIds.welcome,
        SetupStepIds.company,
        SetupStepIds.currencyTax,
        SetupStepIds.branchAndMode,
        SetupStepIds.chartOfAccounts,
        SetupStepIds.users,
        SetupStepIds.products,
        SetupStepIds.review,
      ];
    case SetupDeploymentMode.standalone:
      return const [
        SetupStepIds.welcome,
        SetupStepIds.company,
        SetupStepIds.currencyTax,
        SetupStepIds.branchAndMode,
        SetupStepIds.cashBanks,
        SetupStepIds.chartOfAccounts,
        SetupStepIds.users,
        SetupStepIds.products,
        SetupStepIds.review,
      ];
  }
}

/// الخطوةُ التالية، أو [current] نفسُها عند آخر خطوة.
///
/// ⚠️ **و[current] قد لا تكون في المسار**: تبديلُ نمط التشغيل في الخطوة ١
/// يبدّل المسارَ تحت المستخدم، فتصير خطوةٌ كان يقف عليها خارجَه.
/// و`indexOf` تُرجع `-1` حينها — و`-1 + 1 == 0` يقفز به إلى **أوّل** المسار
/// بلا سبب. فالغائبُ يُعاد كما هو ويتولّاه النداء.
int setupNextStep(List<int> order, int current) {
  final i = order.indexOf(current);
  if (i < 0 || i >= order.length - 1) return current;
  return order[i + 1];
}

/// الخطوةُ السابقة، أو [current] نفسُها عند أوّل خطوة.
int setupPreviousStep(List<int> order, int current) {
  final i = order.indexOf(current);
  if (i <= 0) return current;
  return order[i - 1];
}

/// نسبةُ التقدّم من صفرٍ إلى واحد — للشريط الذي يطلبه التصميم.
///
/// ⚠️ **مبنيّةٌ على الخطوة المكتملة لا الحاليّة**: الوقوفُ على أوّل خطوةٍ
/// تقدّمُه صفرٌ لا `1/8`. وشريطٌ يبدأ ممتلئاً جزئيّاً قبل أن يُكتَب حرفٌ
/// يَعِد بما لم يقع.
double setupProgress(List<int> order, int current) {
  if (order.isEmpty) return 0;
  final i = order.indexOf(current);
  if (i < 0) return 0;
  return i / order.length;
}

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
}

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
List<int> setupStepOrderFor(SetupDeploymentMode mode) {
  switch (mode) {
    case SetupDeploymentMode.client:
      return const [
        SetupStepIds.company,
        SetupStepIds.businessProfile,
        SetupStepIds.developerPassword,
        SetupStepIds.branchAndMode,
        SetupStepIds.touchMode,
        SetupStepIds.users,
        SetupStepIds.tax,
      ];
    case SetupDeploymentMode.server:
      return const [
        SetupStepIds.company,
        SetupStepIds.businessProfile,
        SetupStepIds.developerPassword,
        SetupStepIds.branchAndMode,
        SetupStepIds.touchMode,
        SetupStepIds.postgres,
        SetupStepIds.provisioning,
      ];
    case SetupDeploymentMode.standalone:
    case SetupDeploymentMode.mirror:
      return const [
        SetupStepIds.company,
        SetupStepIds.businessProfile,
        SetupStepIds.developerPassword,
        SetupStepIds.branchAndMode,
        SetupStepIds.touchMode,
        SetupStepIds.products,
        SetupStepIds.users,
        SetupStepIds.tax,
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

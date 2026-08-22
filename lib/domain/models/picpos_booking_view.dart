// حساباتُ شاشة الحجوزات — **خالصةٌ بلا واجهةٍ ولا قاعدة**.
//
// محلُّها `domain/models` لا `presentation/`: حارسُ
// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
// `data/database`، والقائمةُ البيضاء مقفولة. والحسابُ الخالصُ يُختبَر هنا
// بلا `ProviderScope` ولا قاعدةٍ مفتوحة.
import '../../core/utils/financial_utils.dart';

/// تصنيفُ العميل — `tier` في التصميم.
///
/// ⚠️ **لا عمودَ له في القاعدة، ولا يُخترَع له عمود** (قرارُ المالك
/// 2026-08-22): يُشتقّ من إجماليّ الإنفاق بعتباتٍ قابلةٍ للضبط. وعمودٌ
/// صريحٌ كان يتقادم بصمتٍ — عميلٌ أنفق أكثرَ يبقى «برونزيّاً» حتى يحرّره أحد.
enum BookingCustomerTier {
  bronze('برونزي'),
  silver('فضي'),
  gold('ذهبي'),
  platinum('بلاتيني');

  const BookingCustomerTier(this.label);
  final String label;
}

/// عتباتُ التصنيف — تُقرأ من إعدادات الحجوزات، وهذه قيمُها الافتراضيّة.
class BookingTierThresholds {
  const BookingTierThresholds({
    this.silver = 2000,
    this.gold = 8000,
    this.platinum = 15000,
  });

  final double silver;
  final double gold;
  final double platinum;

  /// ⚠️ **العتباتُ يجب أن تصعد.** إعدادٌ مقلوبٌ (ذهبيٌّ أقلُّ من فضّيّ) يجعل
  /// التصنيفَ يقفز فوق درجةٍ بلا سبب، ولا يظهر ذلك في الواجهة أبداً.
  bool get isMonotonic => silver <= gold && gold <= platinum;
}

/// تصنيفُ عميلٍ من إنفاقه.
///
/// المقارنةُ **بالوحدات الصغرى** لا بالعشريّات: عتبةٌ ٢٠٠٠٫٠٠ وإنفاقٌ
/// ١٩٩٩٫٩٩٩٩٩٩٩٩٨ (‏ناتجُ جمعٍ عشريّ) كان يسقط تحت العتبة بفارقٍ لا يراه
/// المستخدمُ في أيّ شاشة.
BookingCustomerTier bookingTierFor(
  double totalSpend, {
  BookingTierThresholds thresholds = const BookingTierThresholds(),
}) {
  final spend = FinancialUtils.toMinorUnits(totalSpend);
  if (spend >= FinancialUtils.toMinorUnits(thresholds.platinum)) {
    return BookingCustomerTier.platinum;
  }
  if (spend >= FinancialUtils.toMinorUnits(thresholds.gold)) {
    return BookingCustomerTier.gold;
  }
  if (spend >= FinancialUtils.toMinorUnits(thresholds.silver)) {
    return BookingCustomerTier.silver;
  }
  return BookingCustomerTier.bronze;
}

// ═══════════════════════════════════════════════════════════════════════════
// الورديّة — مدًى دائريٌّ لا خطّيّ
// ═══════════════════════════════════════════════════════════════════════════

/// هل تقع [minuteOfDay] داخلَ ورديّةٍ تبدأ [startMinutes] وتنتهي [endMinutes]؟
///
/// ⚠️ **المدى دائريٌّ**: ورديّةٌ ٢٠:٠٠ → ٠٢:٠٠ تعبر منتصفَ الليل وهي قائمةٌ
/// فعلاً في المطاعم. ولهذا **لا قيدَ `end > start`** في الجدول — والحسابُ
/// هو الذي يفهم الدورة، لا القاعدة.
///
/// وطرفٌ معدومٌ يعني «بلا حدّ»: مَن لم يُسجَّل دوامُه يُحجز له في أيّ وقت،
/// لا يُمنع منه.
bool isWithinShift(
  int minuteOfDay, {
  int? startMinutes,
  int? endMinutes,
}) {
  if (startMinutes == null || endMinutes == null) return true;
  if (startMinutes == endMinutes) return true; // دوامٌ كاملُ اليوم
  if (startMinutes < endMinutes) {
    return minuteOfDay >= startMinutes && minuteOfDay < endMinutes;
  }
  // تعبر منتصفَ الليل: داخلَها ما بعد البداية **أو** ما قبل النهاية.
  return minuteOfDay >= startMinutes || minuteOfDay < endMinutes;
}

/// دقائقُ من منتصف الليل لوقتٍ ما — الشكلُ الذي تُخزَّن به الورديّة.
int minuteOfDayFor(DateTime at) => at.hour * 60 + at.minute;

// ═══════════════════════════════════════════════════════════════════════════
// التذكيرات
// ═══════════════════════════════════════════════════════════════════════════

/// هل حان هذا التذكير؟
///
/// ⚠️ **يُحسَب ولا يُخزَّن.** التصميمُ يعرض حالةً اسمُها `due`، وعمودٌ يقولها
/// يحتاج من يحدّثه كلَّ دقيقة — وينحرف عن الساعة بصمتٍ إن لم يُحدَّث. والحالةُ
/// المخزَّنةُ ثلاثٌ فقط (‏`scheduled`/`opened`/`dismissed`) والاستحقاقُ سؤالٌ
/// يُسأل عن اللحظة.
bool isReminderDue({
  required String state,
  required DateTime scheduledAt,
  required DateTime now,
}) =>
    state == 'scheduled' && !scheduledAt.isAfter(now);

/// لحظةُ استحقاقِ تذكيرٍ لموعدٍ.
DateTime reminderScheduleFor(DateTime startsAt, int offsetMinutes) =>
    startsAt.subtract(Duration(minutes: offsetMinutes));

/// نصُّ رسالة التذكير — ويُعبَّأ في رابط `wa.me`.
///
/// دالّةٌ خالصةٌ كي يُقاس النصُّ بلا فتحِ متصفّح.
String bookingReminderMessage({
  required String customerName,
  required String serviceName,
  required String timeLabel,
  String? businessName,
}) {
  final who = businessName == null || businessName.trim().isEmpty
      ? ''
      : ' في $businessName';
  return 'مرحباً $customerName، نذكّرك بموعد «$serviceName»$who '
      'الساعة $timeLabel. بانتظارك!';
}

/// رابطُ `wa.me` برسالةٍ مُعبّأة.
///
/// ═══ ⚠️ الرقمُ يُنظَّف ولا يُمرَّر كما كُتب ═══
///
/// `wa.me` يقبل **أرقاماً فقط** بصيغةٍ دوليّةٍ بلا `+` ولا مسافاتٍ ولا
/// شرطات. ورقمٌ كما يكتبه المستخدم (`079-123 4567`) يُنتج رابطاً يفتح واتساب
/// على محادثةٍ فارغة — فيظنّ الموظَّفُ أنه أرسل ولم يُرسَل شيء.
///
/// و`null` تعني «لا رابطَ ممكن» — تُعرَض بزرٍّ معطَّلٍ لا برابطٍ يفشل صامتاً.
String? whatsappReminderLink({
  required String? phone,
  required String message,
}) {
  if (phone == null) return null;
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return 'https://wa.me/$digits?text=${Uri.encodeComponent(message)}';
}

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

/// صفُّ لوحةِ الحجوزات — حجزٌ **موصولٌ** بخدمته ومورده، جاهزٌ للعرض.
///
/// ═══ لماذا نموذجٌ هنا لا صفُّ drift ═══
///
/// حارسُ `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من
/// استيراد `data/database`، والقائمةُ البيضاء مقفولة. فلو مُرِّر `Booking`
/// كما هو لَاحتاجت الشاشةُ استيراداً محظوراً. والوصلُ يقع في طبقة البيانات
/// مرّةً واحدةً بدل استعلامٍ لكلّ صفّ.
class BookingBoardRow {
  const BookingBoardRow({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.customerName,
    required this.status,
    required this.depositAmount,
    required this.depositStatus,
    this.customerPhone,
    this.partyId,
    this.invoiceId,
    this.notes,
    this.serviceId = 0,
    this.serviceName = '',
    this.serviceColorHex = '#0250D3',
    this.servicePrice = 0,
    this.resourceId,
    this.resourceName,
    this.resourceRole,
    this.resourceKind,
    this.resourceColorHex,
  });

  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String customerName;
  final String? customerPhone;
  final int? partyId;
  final int? invoiceId;
  final String? notes;

  /// إحدى: `pending` · `confirmed` · `seated` · `in_service` · `completed`
  /// · `cancelled` · `no_show`.
  final String status;

  final double depositAmount;
  final String depositStatus;

  final int serviceId;
  final String serviceName;
  final String serviceColorHex;
  final double servicePrice;

  /// معدومٌ حين لا مورد — حجزٌ بلا موظَّفٍ مسموحٌ (لا أحدَ يتعارض عليه).
  final int? resourceId;
  final String? resourceName;
  final String? resourceRole;
  final String? resourceKind;
  final String? resourceColorHex;

  /// هل فُوتِر هذا الحجز؟ — `invoiceId` وحدَه هو الجواب.
  bool get isInvoiced => invoiceId != null;

  /// هل يشغل هذا الحجزُ وقتاً فعليّاً؟ الملغى والمتخلّف لا يشغلان — وهو
  /// نفسُ استثناءِ استعلامِ التداخل، فلا يفترق المعروضُ عن المحسوب.
  bool get occupiesTime => status != 'cancelled' && status != 'no_show';

  /// دقائقُ البداية من منتصف الليل — لتموضع الشريط على التقويم.
  int get startMinuteOfDay => minuteOfDayFor(startsAt);

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;
}

/// عرضُ حالةِ الحجز — التسميةُ والأيقونةُ ونغمةُ اللون.
///
/// ═══ ⚠️ سبعٌ لا ستٌّ — والسابعةُ هي المصيدة ═══
///
/// التصميمُ يسمّي **ستّاً** (`confirmed` · `pending` · `seated` ·
/// `in_service` · `cancelled` · `no_show`) بينما القيدُ في القاعدة يقبل
/// **سبعاً**: `completed` موجودةٌ ويحتاجها تحويلُ الحجز إلى فاتورة. فحالةٌ
/// بلا تسميةٍ تُرسم **فارغةً** على الشاشة — صفٌّ يقول عن نفسه لا شيء.
///
/// ولهذا الخريطةُ مقفولةٌ بحارسٍ يقارنها بمفردات القيد نفسِها: أيُّ حالةٍ
/// تُضاف للقاعدة ولا تُسمَّى هنا تُسقط الاختبار بدل أن تظهر فراغاً.
enum BookingStatusTone { neutral, info, success, warning, danger }

class BookingStatusView {
  const BookingStatusView(this.label, this.tone);
  final String label;
  final BookingStatusTone tone;
}

/// مفرداتُ الحالة كما يقبلها قيدُ `Bookings.status` — **بالترتيب نفسِه**.
const bookingStatusCodes = <String>[
  'pending',
  'confirmed',
  'seated',
  'in_service',
  'completed',
  'cancelled',
  'no_show',
];

const _bookingStatusViews = <String, BookingStatusView>{
  'pending': BookingStatusView('بانتظار التأكيد', BookingStatusTone.warning),
  'confirmed': BookingStatusView('مؤكد', BookingStatusTone.info),
  'seated': BookingStatusView('تم الحضور', BookingStatusTone.info),
  'in_service': BookingStatusView('قيد الخدمة', BookingStatusTone.success),
  'completed': BookingStatusView('مكتمل', BookingStatusTone.success),
  'cancelled': BookingStatusView('ملغي', BookingStatusTone.danger),
  'no_show': BookingStatusView('لم يحضر', BookingStatusTone.danger),
};

/// عرضُ الحالة — وحالةٌ غيرُ معروفةٍ تُسمّى بنصّها لا تُبتلع.
BookingStatusView bookingStatusView(String status) =>
    _bookingStatusViews[status] ??
    BookingStatusView(status, BookingStatusTone.neutral);

/// الفعلُ التالي المعروضُ على الصفّ — أو `null` حين لا فعلَ منطقيّ.
///
/// السلسلةُ: بانتظار ⇒ «تأكيد» · مؤكَّدٌ ⇒ «تسجيل حضور» · حاضرٌ ⇒ «بدء
/// الخدمة» · قيد الخدمة ⇒ «إنهاء» · مكتملٌ ⇒ «تفويتر» (ما لم يُفوتَر).
/// والملغى والمتخلّفُ بلا فعل.
({String label, String next})? bookingNextAction({
  required String status,
  required bool isInvoiced,
}) {
  switch (status) {
    case 'pending':
      return (label: 'تأكيد', next: 'confirmed');
    case 'confirmed':
      return (label: 'تسجيل حضور', next: 'seated');
    case 'seated':
      return (label: 'بدء الخدمة', next: 'in_service');
    case 'in_service':
      return (label: 'إنهاء', next: 'completed');
    case 'completed':
      // التفويترُ ليس تبديلَ حالةٍ — يفتح مسارَ نقطة البيع. و`next` فارغةٌ
      // تميّزه، فلا يُنادى `setStatus` بقيمةٍ لا يقبلها القيد.
      return isInvoiced ? null : (label: 'تفويتر', next: '');
    default:
      return null;
  }
}

/// صفُّ عميلٍ في وجهة «العملاء» — مُجمَّعٌ من تاريخ حجوزاته.
class BookingCustomerRow {
  const BookingCustomerRow({
    required this.name,
    required this.visits,
    required this.spend,
    this.phone,
    this.partyId,
    this.favouriteService,
    this.lastVisit,
  });

  final String name;
  final String? phone;
  final int? partyId;

  /// عددُ الزياراتِ **المنعقدة** — الملغى والمتخلّفُ ليسا زيارة.
  final int visits;

  /// إجماليُّ الإنفاق — من أسعار الخدمات المحجوزة.
  final double spend;

  final String? favouriteService;
  final DateTime? lastVisit;

  BookingCustomerTier get tier => bookingTierFor(spend);
}

/// صفُّ تذكيرٍ في وجهة «التذكيرات» — موصولٌ بحجزه وخدمته.
class BookingReminderRow {
  const BookingReminderRow({
    required this.id,
    required this.bookingId,
    required this.customerName,
    required this.serviceName,
    required this.bookingStartsAt,
    required this.scheduledAt,
    required this.channel,
    required this.state,
    required this.offsetMinutes,
    this.customerPhone,
  });

  final int id;
  final int bookingId;
  final String customerName;
  final String? customerPhone;
  final String serviceName;
  final DateTime bookingStartsAt;
  final DateTime scheduledAt;

  /// `whatsapp` · `sms`.
  final String channel;

  /// `scheduled` · `opened` · `dismissed` — **ولا `sent`**.
  final String state;

  final int offsetMinutes;

  /// هل حان وقتُه؟ — مجدولٌ ومرّ موعدُ جدولته.
  bool isDue(DateTime now) =>
      state == 'scheduled' && !scheduledAt.isAfter(now);
}

/// تسميةُ حالة التذكير.
///
/// ⚠️ **«فُتِح» لا «أُرسل»** — قرارُ المالك 2026-08-22: الإرسالُ عبر رابط
/// `wa.me` يفتح واتساب بالنصّ جاهزاً والموظَّفُ يضغط «إرسال». فالتطبيقُ لا
/// يعلم أنّ الرسالةَ وصلت ولا أنّها أُرسلت أصلاً؛ يعلم أنّ أحداً فتح الرابط.
/// والتصميمُ يكتب `sent` — والتسميةُ هنا تتبع الصدقَ لا التصميم.
String bookingReminderStateLabel(String state) => switch (state) {
      'opened' => 'فُتِح الرابط',
      'dismissed' => 'أُلغي',
      _ => 'بانتظار الإرسال',
    };

/// قناةُ التذكير بالعربيّة.
String bookingReminderChannelLabel(String channel) =>
    channel == 'sms' ? 'رسالة نصّيّة' : 'واتساب';

/// وجهاتُ شاشة الحجوزات الثمانِ — كما في التصميم.
enum BookingsDestination {
  board('لوحة اليوم'),
  waitlist('قائمة الانتظار'),
  resources('الموارد'),
  services('الخدمات'),
  customers('العملاء'),
  reminders('التذكيرات'),
  reports('التقارير'),
  settings('الإعدادات');

  const BookingsDestination(this.label);
  final String label;
}

/// حِملُ موردٍ في يومٍ واحد — يُشتقّ من الصفوف المعروضة لا من استعلامٍ ثانٍ.
class ResourceDayLoad {
  const ResourceDayLoad({
    required this.bookings,
    required this.revenue,
    required this.bookedMinutes,
    required this.loadPct,
  });

  final int bookings;
  final double revenue;
  final int bookedMinutes;

  /// نسبةُ إشغال الورديّة — `0` حين لا ورديّةَ معرّفة.
  final double loadPct;
}

/// يحسب حِملَ موردٍ من صفوف اليوم.
///
/// ⚠️ **الملغى والمتخلّفُ لا يُحسبان**: نسبةُ إشغالٍ تعدّ حجزاً ملغىً تكذب
/// على المدير — تقول «مشغول» عن ساعةٍ فارغة. وهو نفسُ استثناءِ استعلام
/// التداخل، فلا يفترق المعروضُ عن المحجوز فعلاً.
///
/// و[shiftStartMinutes]/[shiftEndMinutes] معدومان ⇒ لا ورديّةَ معرّفةٌ ⇒
/// النسبةُ صفر. والقسمةُ على صفرٍ في دارت لا ترمي بل تعطي `Infinity`، فتُرسم
/// شريطاً بلا نهاية — فتُحرَس صراحةً.
ResourceDayLoad resourceDayLoad({
  required int resourceId,
  required List<BookingBoardRow> rows,
  int? shiftStartMinutes,
  int? shiftEndMinutes,
}) {
  var count = 0;
  var revenue = 0.0;
  var minutes = 0;
  for (final r in rows) {
    if (!r.occupiesTime) continue;
    if (r.resourceId != resourceId) continue;
    count++;
    revenue += r.servicePrice;
    minutes += r.durationMinutes;
  }

  var pct = 0.0;
  if (shiftStartMinutes != null && shiftEndMinutes != null) {
    final span = shiftEndMinutes - shiftStartMinutes;
    if (span > 0) pct = (minutes / span * 100).clamp(0, 100).toDouble();
  }

  return ResourceDayLoad(
    bookings: count,
    revenue: revenue,
    bookedMinutes: minutes,
    loadPct: pct,
  );
}

/// الحرفان الأوّلان من أوّل كلمتين — «محمد علي» ⇒ «م.ع».
///
/// يُشتقّ ولا يُخزَّن: عمودٌ ثالثٌ للأحرف يتباعد عن الاسم عند إعادة التسمية.
String initialsFor(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, 1);
  return '${parts[0].substring(0, 1)}.${parts[1].substring(0, 1)}';
}

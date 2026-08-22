// نموذجُ عرضِ «سجل العمليات» بهويّة PicPos — **صياغةُ نصٍّ خالصةٌ بلا واجهةٍ
// ولا قاعدة**.
//
// ═══ ما يقع هنا وما لا يقع ═══
//
// يقع هنا: تجميعُ الخلايا الستِّ التي يرسمها التصميم من حقولٍ **محسومةٍ
// مسبقاً** (‏التسمياتُ مُرجَمةٌ في الشاشة من خرائطِها القائمة، واسمُ الفرع
// والدورِ من خرائطِ بحثٍ تُبنى مرّةً واحدة).
//
// لا يقع هنا: خريطةُ الأيقونات والألوان — تلك مئتا سطرٍ من `switch` على
// `action` تعيش في `activity_log_items_picpos.dart` منذ الفورك، ونقلُها كان
// سيكون نقلاً بلا فائدةِ اختبار: لا حسابَ فيها ولا قرار.
//
// ⚠️ **ولا حقلَ مخترَعاً**: كلُّ خليّةٍ مشتقّةٌ من عمودٍ في `activity_logs`
// أو من بحثٍ عن مفتاحٍ أجنبيٍّ فيه. راجع §الحقولُ الغائبة في النهاية.
import '../../core/constants/app_constants.dart';

/// صفٌّ واحدٌ في جدول سجل العمليات.
class PicPosActivityRow {
  const PicPosActivityRow({
    required this.id,
    required this.actionLabel,
    required this.entityLabel,
    required this.detail,
    required this.userName,
    required this.time,
    this.branchName,
    this.roleName,
    this.entityId,
    this.amount,
  });

  final int id;

  /// تسميةُ الإجراء بعد الترجمة من `actionLabels` — لا الكودُ الخام.
  final String actionLabel;

  /// تسميةُ نوع المستند بعد الترجمة من `entityLabels`.
  final String entityLabel;

  /// `description` كما خُزِّن.
  final String detail;

  final String userName;
  final DateTime time;

  /// اسمُ الفرع من `branchId` — `null` حين لا فرعَ مختوماً على السجلّ
  /// (سجلّاتٌ أقدمُ من v138) أو حين لا يُعرَف اسمُه.
  final String? branchName;

  /// اسمُ الدور من `userId → roleId → roles.name` — `null` حين لا مستخدمَ
  /// مرتبطاً أو لا دورَ له.
  final String? roleName;

  final int? entityId;
  final double? amount;

  /// مرجعُ المستند — `#42`. فارغٌ حين لا معرّفَ للكيان، فلا يُطبع `#null`.
  String get refLabel => entityId == null ? '' : '#$entityId';

  /// `14:05` — ساعةٌ ودقيقةٌ بخانتَين.
  String get timeLabel =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// `21/8` — يومٌ وشهرٌ مختصران، تحت الوقت.
  String get dateLabel => '${time.day}/${time.month}';

  /// السطرُ الخافتُ تحت الإجراء — الفرعُ أو لا شيء.
  String get branchLabel => branchName ?? '';

  /// السطرُ الخافتُ تحت المستخدم — الدورُ أو لا شيء.
  String get roleLabel => roleName ?? '';

  /// خليّةُ التفاصيل.
  ///
  /// ⚠️ **والمبلغُ يُضمّ هنا ولا يُسقَط.** التصميمُ يرسم عمودَ تفاصيلَ واحداً
  /// ولا عمودَ مبلغ، والشاشةُ قبل إعادة التصميم كانت تعرض `amount` في السطر
  /// الخافت. فإسقاطُه بحجّة «التصميمُ لا يرسمه» كان سيُخفي رقماً ماليّاً
  /// مسجَّلاً — وهو أسوأُ من عمودٍ زائد.
  String get detailLabel {
    final a = amount;
    if (a == null) return detail;
    final money = a.toStringAsFixed(AppConstants.decimalPlaces);
    return detail.isEmpty
        ? '$money ${AppConstants.currencySymbolEn}'
        : '$detail · $money ${AppConstants.currencySymbolEn}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// §الحقولُ الغائبة — مقصودةٌ ومكتوبة
// ═══════════════════════════════════════════════════════════════════════════
//
// لا شيءَ في التصميم أُسقط هنا: الأعمدةُ الستُّ كلُّها لها مصدرٌ حقيقيّ.
// و[branchName] و[roleName] **قد تغيبان بحقّ** لا بعطب: `branch_id` أُضيف في
// v138 فالسجلّاتُ الأقدمُ تحمله `null`، و`users.role_id` قابلٌ للغياب. وفي
// الحالتين يُترك السطرُ فارغاً — لا يُكتب «غير معروف» كأنه معلومة.

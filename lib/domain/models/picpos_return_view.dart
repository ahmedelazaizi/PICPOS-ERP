// نموذجُ عرضِ شاشتَي المرتجعات بهويّة PicPos — **حسابٌ خالصٌ بلا واجهةٍ ولا
// قاعدة**، ومشتركٌ بين توأمَي المبيعات والمشتريات.
//
// ═══ لماذا نوعٌ محايدٌ واحد ═══
//
// الشاشتان تعرضان نفسَ الشيء (قائمةَ فواتيرَ في مدىً + عدّاداتٍ فوقها) فوق
// حالتَين مختلفتَين تماماً: `SalesReturnState` تحمل `SalesInvoiceData`
// وخريطةَ أسماءِ عملاء، و`PurchaseReturnState` تحمل `PurchaseInvoiceData`
// وترشيحاً في SQL. فبناءُ ودجتَين متطابقتَين بصريّاً كان سيخلق ملفَّين
// ينحرفان بأوّل تعديل — وهي المصيدةُ نفسُها التي وقعت في الفوركين من قبل.
//
// فالودجتُ تستقبل [PicPosReturnInvoiceRow]، وكلُّ شاشةٍ تحوّل نوعَها إليه.
//
// ⚠️ **ولا يخترع هذا الملفُّ اسماً ولا رقماً**: [partyName] **قابلٌ للغياب**
// لأن `PurchaseReturnState` لا تحمل خريطةَ أسماءِ موردين أصلاً — فشاشةُ
// المشتريات تمرّر `null` ويظهر التاريخُ وحدَه، كما هي اليوم. اختلاقُ اسمٍ
// هناك كان سيتطلّب استعلاماً لكلّ صفٍّ (N+1) أو كذباً.
import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../core/utils/financial_utils.dart';

/// حالةُ الفاتورة كما تُعرَض في الشارة.
///
/// القيمُ النصّيّةُ هي **نفسُها** المخزَّنة في عمود `status`، والتسمياتُ
/// منقولةٌ حرفيّاً عن `_getStatusLabel` في شاشة مرتجع المبيعات.
enum PicPosReturnStatus {
  completed('completed', 'مكتملة'),
  returned('returned', 'مرتجعة'),
  partialReturn('partial_return', 'مرتجع جزئي'),
  voided('voided', 'ملغاة'),
  pending('', 'معلقة');

  const PicPosReturnStatus(this.code, this.label);

  final String code;
  final String label;

  String get displayLabel => tr(label);

  /// حالةٌ مجهولةٌ ترتدّ إلى «معلقة» — نفسُ `default` في الدالّة الأصليّة.
  static PicPosReturnStatus fromCode(String code) => values.firstWhere(
        (s) => s.code == code,
        orElse: () => PicPosReturnStatus.pending,
      );
}

/// صفُّ فاتورةٍ في قائمة المرتجعات.
class PicPosReturnInvoiceRow {
  const PicPosReturnInvoiceRow({
    required this.id,
    required this.number,
    required this.date,
    required this.total,
    required this.status,
    this.partyName,
  });

  final int id;
  final String number;
  final DateTime date;
  final double total;
  final PicPosReturnStatus status;

  /// اسمُ العميل — أو `null` حين لا يكون متاحاً بلا استعلامٍ إضافيّ (شاشةُ
  /// المشتريات). راجع تحذيرَ رأس الملفّ.
  final String? partyName;

  /// `18/8` — نفسُ الصيغة المختصرة في التصميم.
  String get shortDate => '${date.day}/${date.month}';

  /// سطرُ التفاصيل: «العميل · التاريخ» أو التاريخُ وحدَه.
  String get subtitle {
    final name = partyName?.trim();
    if (name == null || name.isEmpty) return shortDate;
    return '$name · $shortDate';
  }

  String get totalLabel =>
      '${total.toStringAsFixed(AppConstants.decimalPlaces)} '
      '${AppConstants.currencySymbolEn}';

  /// هل تطابق الفاتورةُ بحثاً برقمها؟
  ///
  /// دلالةٌ منقولةٌ كما هي عن ترشيحِ شاشة المبيعات: الرقمُ فقط، بلا حساسيّةٍ
  /// لحالة الأحرف. (‏شاشةُ المشتريات ترشّح في SQL فلا تستدعي هذه.)
  bool matchesNumber(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return number.toLowerCase().contains(q);
  }
}

/// عدّاداتُ البطاقات الأربعِ أعلى شاشة المرتجعات.
///
/// ⚠️ **كلُّها مشتقّةٌ من الفواتير المحمَّلة في المدى** — لا شيءَ منها يحتاج
/// استعلاماً إضافيّاً، ولا شيءَ منها مخترَع. وتحديداً: **لا «قيمةَ مرتجعاتِ
/// الفترة»** هنا، لأن الحالةَ لا تحمل مبالغَ المرتجعات المسجَّلة سابقاً —
/// تحمل حالةَ الفاتورة فقط. فعُدَّت الفواتيرُ ولم تُخترع مبالغُها.
class PicPosReturnKpis {
  const PicPosReturnKpis({
    required this.invoiceCount,
    required this.invoicesTotal,
    required this.fullyReturned,
    required this.partiallyReturned,
  });

  factory PicPosReturnKpis.from(Iterable<PicPosReturnInvoiceRow> rows) {
    var count = 0;
    var totalMinor = 0;
    var full = 0;
    var partial = 0;

    for (final r in rows) {
      count++;
      totalMinor += FinancialUtils.toMinorUnits(r.total);
      if (r.status == PicPosReturnStatus.returned) full++;
      if (r.status == PicPosReturnStatus.partialReturn) partial++;
    }

    return PicPosReturnKpis(
      invoiceCount: count,
      invoicesTotal: FinancialUtils.fromMinorUnits(totalMinor),
      fullyReturned: full,
      partiallyReturned: partial,
    );
  }

  final int invoiceCount;
  final double invoicesTotal;
  final int fullyReturned;
  final int partiallyReturned;

  String get invoicesTotalLabel =>
      invoicesTotal.toStringAsFixed(AppConstants.decimalPlaces);
}

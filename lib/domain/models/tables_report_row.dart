// ═══════════════════════════════════════════════════════════════════════════
// تقريرُ الطاولات — الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// ثمانيَ عشرةَ شاشةَ تقاريرَ في هذا المستودع ولا واحدةٌ تقيس الطاولة. وحين
// تُقاس، القاعدةُ التي تُنتج الرقمَ الكاذبَ ليست الجمعَ بل **ما يُستبعَد منه**:
// المستودعُ فيه دمجُ طلبات (`mergedToId`) ينقل بنودَ طلبٍ إلى آخرَ ويُغلق
// الأوّلَ موسوماً بهدفه. فجمعُ `total` على كلّ الصفوف يجمع نفسَ المال مرّتين.
//
// ولذلك يعيش الحسابُ هنا — خالصاً بلا Drift ولا Riverpod ولا ودجت — كي
// يُختبَر بالقيم لا بالشاشة، وكي لا تُنسَخ القاعدةُ في شاشةٍ ثانيةٍ غداً.
//
// ── القواعدُ الثلاث ────────────────────────────────────────────────────────
//   ١. **المدموجُ لا يُحسَب مطلقاً** (`mergedToId != null`): لا إيرادَ ولا
//      طلبَ ولا ضيفَ ولا مدّة. إجماليُّه انتقل إلى هدفه، وضيوفُه جلسوا على
//      الطاولة الهدف — فصفٌّ له يعدّ الجلسةَ الواحدةَ جلستَين.
//   ٢. **المفتوحُ إشغالٌ لا إيراد** (`closedAt == null`): يُحسَب في
//      `orderCount` و`guestCount` — الطاولةُ مشغولةٌ فعلاً — ولا يدخل
//      `revenue` ولا `discount` ولا متوسّطَ المدّة. المالُ لم يُحصَّل بعد،
//      والجلسةُ لم تنتهِ فلا مدّةَ لها.
//   ٣. **المدّةُ من `openedAt` إلى `closedAt`** بالدقائق، ومقامُ المتوسّط
//      عددُ **المغلقة وحدَها**. صفرٌ مقحَمٌ عن كلِّ مفتوحٍ كان يُنصّف
//      متوسّطَ الدوران بلا أن ينطق شيء.
//
// ── ما ليس من شأن هذا الملفّ ───────────────────────────────────────────────
// «أيُّ الطلبات تدخل التقريرَ أصلاً» قرارُ الاستعلام لا قرارُ التجميع: المدى
// الزمنيّ، ونطاقُ صلاحية الفروع، واستبعادُ الملغى (`status = 'cancelled'` —
// وهو يحمل `closedAt` كذلك، فيبدو مغلقاً هنا لو وصل). الاستعلامُ يقرّر ما
// الجلسةُ، وهذا يقرّر كيف تُجمَع الجلسات.

import 'dart:collection';

/// طلبُ طاولةٍ واحدٌ كما يدخل التقرير — قِيَمٌ عاريةٌ لا صفُّ Drift.
///
/// النوعُ خالصٌ عن قصد: يُبنى في طبقة البيانات من `TableOrders`، ويُختبَر هنا
/// بلا قاعدة. وكلُّ حقلٍ فيه إمّا عمودٌ قائمٌ أو مشتقٌّ من محرّكٍ واحد — لا
/// عمودَ جديدٌ أُضيف لأجل هذا التقرير.
class TableOrderInput {
  const TableOrderInput({
    required this.tableId,
    required this.tableName,
    required this.total,
    required this.guestCount,
    required this.discount,
    required this.openedAt,
    required this.closedAt,
    required this.mergedToId,
  });

  /// `RestaurantTables.id` — مفتاحُ التجميع.
  final int tableId;

  /// اسمُ الطاولة وقتَ الاستعلام. يُعرَض كما هو؛ ولو أُعيدت تسميةُ الطاولة
  /// بين طلبَين فالصفُّ يحمل الاسمَ الأوّلَ الوارد — الجمعُ بالمعرّف لا
  /// بالاسم، فالتسميةُ لا تشقّ الصفّ.
  final String tableName;

  /// `TableOrders.total` — مجموعُ صوافي البنود **قبل** خصم الطلب.
  ///
  /// هو ما يكتبه `_updateTableOrderTotal` حرفياً. والخصمُ يُطرح منه في
  /// [TablesReportRow.revenue]، فيبقى الثابت: `revenue + discount` = مجملُ
  /// الطلبات المغلقة.
  final double total;

  /// `TableOrders.guestCount` — عددُ مَن جلس، مقامُ «نصيبِ الضيف».
  final int guestCount;

  /// خصمُ الطلب **مبلغاً** مقصوصاً عند [total].
  ///
  /// لا يُشتقّ هنا من `discountType`/`discountValue`: قاعدةُ الخصم محرّكٌ
  /// واحدٌ في `TableOrderTotals.compute` تستعمله الشاشةُ والطباعةُ والتحصيل،
  /// ونسخُها هنا يصنع محرّكاً ثانياً. المستدعي يمرّ من ذلك المحرّك ويسلّم
  /// المبلغَ جاهزاً.
  final double discount;

  /// لحظةُ فتح الطلب — بدايةُ الجلسة.
  final DateTime openedAt;

  /// لحظةُ الإغلاق، أو `null` للطلب الحيّ.
  final DateTime? closedAt;

  /// معرّفُ الطلب الذي دُمج فيه هذا — `null` للطلب القائم بذاته.
  final int? mergedToId;

  /// هل هذا الطلبُ جلسةٌ مستقلّةٌ تُحسَب؟ (القاعدة ١)
  bool get isCountedVisit => mergedToId == null;

  /// هل انتهت الجلسةُ فصار لها مالٌ ومدّة؟ (القاعدتان ٢ و٣)
  bool get isSettledVisit => isCountedVisit && closedAt != null;
}

/// سطرُ تقريرٍ لطاولةٍ واحدةٍ خلال المدى المطلوب.
class TablesReportRow {
  const TablesReportRow({
    required this.tableId,
    required this.tableName,
    required this.orderCount,
    required this.guestCount,
    required this.revenue,
    required this.discount,
    required this.avgTurnMinutes,
  });

  final int tableId;
  final String tableName;

  /// عددُ الجلسات — المفتوحةُ والمغلقةُ معاً، بلا المدموجة.
  final int orderCount;

  /// مجموعُ الضيوف على تلك الجلسات.
  final int guestCount;

  /// المحصَّلُ من الجلسات **المغلقة** صافياً من خصمها.
  final double revenue;

  /// مجموعُ خصومِ تلك الجلسات نفسِها — يُعرَض إلى جانب [revenue] فيتّضح من
  /// أين نقص المجمل.
  final double discount;

  /// متوسّطُ مدّة الجلوس بالدقائق للجلسات المغلقة، و`null` إن لم تُغلق
  /// جلسةٌ واحدة — لا صفراً: «صفرُ دقيقة» رقمٌ يكذب، و«لا مدّةَ بعد» صدق.
  final double? avgTurnMinutes;

  /// نصيبُ الضيف الواحد من الإيراد — `null` حين لا ضيوف، لا قسمةً على صفر.
  double? get revenuePerGuest => guestCount > 0 ? revenue / guestCount : null;
}

/// يجمع طلباتِ الطاولات في سطرٍ لكلّ طاولة، بالقواعد الثلاث الموصوفة أعلاه.
///
/// الصفوفُ مرتَّبةٌ بالإيراد نزولاً ثم بالمعرّف صعوداً — ترتيبٌ حاسمٌ لا
/// يعتمد على ترتيب الوارد، فالتصديرُ والشاشةُ يقولان نفسَ الشيء دوماً.
List<TablesReportRow> aggregateTablesReport(List<TableOrderInput> orders) {
  final acc = LinkedHashMap<int, _TableAccumulator>();

  for (final order in orders) {
    // القاعدة ١ — المدموجُ يخرج قبل أيّ عدٍّ: لا صفَّ له ولا ضيوفَ ولا طلب.
    if (!order.isCountedVisit) continue;

    final bucket = acc.putIfAbsent(
      order.tableId,
      () => _TableAccumulator(order.tableId, order.tableName),
    );

    bucket.orderCount += 1;
    bucket.guestCount += order.guestCount;

    // القاعدتان ٢ و٣ — المالُ والمدّةُ للمغلقة وحدَها.
    if (order.isSettledVisit) {
      bucket.revenue += order.total - order.discount;
      bucket.discount += order.discount;
      bucket.turnMinutes +=
          order.closedAt!.difference(order.openedAt).inMilliseconds /
              Duration.millisecondsPerMinute;
      bucket.closedCount += 1;
    }
  }

  final rows = [for (final b in acc.values) b.toRow()];
  rows.sort((a, b) {
    final byRevenue = b.revenue.compareTo(a.revenue);
    return byRevenue != 0 ? byRevenue : a.tableId.compareTo(b.tableId);
  });
  return rows;
}

class _TableAccumulator {
  _TableAccumulator(this.tableId, this.tableName);

  final int tableId;
  final String tableName;
  int orderCount = 0;
  int guestCount = 0;
  double revenue = 0;
  double discount = 0;
  double turnMinutes = 0;
  int closedCount = 0;

  TablesReportRow toRow() => TablesReportRow(
        tableId: tableId,
        tableName: tableName,
        orderCount: orderCount,
        guestCount: guestCount,
        revenue: revenue,
        discount: discount,
        // المقامُ عددُ المغلقة — لا عددُ الطلبات. راجع القاعدة ٣.
        avgTurnMinutes: closedCount == 0 ? null : turnMinutes / closedCount,
      );
}

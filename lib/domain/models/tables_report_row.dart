// ═══════════════════════════════════════════════════════════════════════════
// تقريرُ الطاولات — الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// ثمانيَ عشرةَ شاشةَ تقاريرَ في هذا المستودع ولا واحدةٌ تقيس الطاولة. وحين
// تُقاس، القاعدةُ التي تُنتج الرقمَ الكاذبَ ليست الجمعَ بل **ما يُستبعَد منه**:
// المستودعُ فيه دمجُ طلبات (`mergedToId`) ينقل بنودَ طلبٍ إلى آخرَ ويُغلق
// الأوّلَ موسوماً بهدفه. فصفُّ المصدر يبقى في الجدول جلسةً مغلقةً كاملةَ
// الشكل — والازدواجُ الذي يُنتجه **على عدد الجلسات لا على المال**.
//
// ولذلك يعيش الحسابُ هنا — خالصاً بلا Drift ولا Riverpod ولا ودجت — كي
// يُختبَر بالقيم لا بالشاشة، وكي لا تُنسَخ القاعدةُ في شاشةٍ ثانيةٍ غداً.
//
// ── القواعدُ الثلاث ────────────────────────────────────────────────────────
//   ١. **المدموجُ لا يُنتج صفّاً ولا إيراداً ولا مدّة** (`mergedToId != null`)،
//      **وضيوفُه يُطوَون في صفّ هدفه**. والعلّةُ ليست ازدواجَ مال:
//      `TablesDao.mergeTableOrders` ينقل البنودَ ثم يعيد حسابَ الإجماليَّين،
//      فيصير إجماليُّ المصدر **صفراً** (`tables_dao.dart` — `// Should be 0`)
//      ولن يُضيف جمعُه شيئاً. العلّةُ أنّ المصدرَ يبقى **جلسةً** مغلقةً بلا
//      مال: فيتضخّم `orderCount`، ويهبط نصيبُ الجلسة الواحدة، وتدخل مدّتُها
//      متوسّطَ الدوران وهي نصفُ جلسةٍ لا جلسة. أمّا الضيوفُ فلا ينتقلون:
//      `guestCount` يُكتب مرّةً واحدةً عند فتح الطلب ولا يرفعه الدمجُ على
//      الهدف. فإسقاطُ المدموج كلِّه كان يُضيّع ضيوفَه — طاولةُ ثلاثةٍ تُدمج
//      في طاولةِ اثنين ⇒ الإيرادُ كاملٌ والضيوفُ اثنان ⇒ **نصيبُ الضيف
//      مضخَّم**. الطيُّ يعيدهم إلى الطاولة التي جلسوا عليها فعلاً.
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

/// طلبُ طاولةٍ واحدٌ كما يدخل التقرير — قِيَمٌ عاريةٌ لا صفُّ Drift.
///
/// النوعُ خالصٌ عن قصد: يُبنى في طبقة البيانات من `TableOrders`، ويُختبَر هنا
/// بلا قاعدة. وكلُّ حقلٍ فيه إمّا عمودٌ قائمٌ أو مشتقٌّ من محرّكٍ واحد — لا
/// عمودَ جديدٌ أُضيف لأجل هذا التقرير.
class TableOrderInput {
  const TableOrderInput({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.total,
    required this.guestCount,
    required this.discount,
    required this.openedAt,
    required this.closedAt,
    required this.mergedToId,
  });

  /// `TableOrders.id` — يلزم لأن [mergedToId] يشير إلى **طلبٍ** لا إلى
  /// طاولة، فبلا معرّفِ الطلب لا يُعرَف أيُّ صفٍّ يستضيف ضيوفَ المدموج.
  final int id;

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
  final acc = <int, _TableAccumulator>{};
  final byId = {for (final order in orders) order.id: order};

  // ── المرورُ الأوّل: الجلساتُ المستقلّةُ وحدَها تصنع الصفوف ────────────────
  for (final order in orders) {
    // القاعدة ١ — المدموجُ لا صفَّ له ولا طلبَ ولا مال؛ ضيوفُه في المرور الثاني.
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

  // ── المرورُ الثاني: ضيوفُ المدموج يُطوَون في صفّ الطاولة المضيفة ─────────
  //
  // الإيرادُ وحدَه هو ما ينتقل بالدمج؛ `guestCount` يبقى على الطلب الذي فُتح
  // به. فبلا هذا المرور تختفي أنفسٌ جلست فعلاً، ويُقسَم إيرادٌ كاملٌ على
  // ضيوفٍ أقلَّ ⇒ «نصيبُ الضيف» مضخَّم.
  for (final order in orders) {
    if (order.isCountedVisit) continue;
    final host = _terminalMergeTarget(order, byId);
    if (host == null) continue;
    final bucket = acc[host.tableId];
    if (bucket != null) bucket.guestCount += order.guestCount;
  }

  final rows = [for (final b in acc.values) b.toRow()];
  rows.sort((a, b) {
    final byRevenue = b.revenue.compareTo(a.revenue);
    return byRevenue != 0 ? byRevenue : a.tableId.compareTo(b.tableId);
  });
  return rows;
}

/// الطلبُ الذي استقرّ عليه الحسابُ في آخر سلسلة الدمج — أو `null`.
///
/// الدمجُ قد يتسلسل (‏أ ⇐ ب ⇐ ج)، فطيُّ الضيوف على الوسيط يضعهم على طاولةٍ
/// لم يعد عليها حساب. و`null` في حالتين، وكلتاهما إسقاطٌ مقصود:
///   • **الهدفُ خارج مجموعة التقرير** — مدىً زمنيٌّ أو قسمٌ أو فرعٌ أخرجه.
///     لا يُخترَع له صفٌّ من ضيوفٍ بلا إيراد.
///   • **حلقةٌ في البيانات** — لا تُدار إلى الأبد. مستحيلةٌ بالتصميم، ومقيسةٌ
///     لأن حلقةً في حلقةٍ لا نهائيّةٍ تُعلّق الشاشةَ لا تُخطئ رقماً.
TableOrderInput? _terminalMergeTarget(
  TableOrderInput start,
  Map<int, TableOrderInput> byId,
) {
  var current = start;
  final seen = <int>{start.id};
  while (current.mergedToId != null) {
    final next = byId[current.mergedToId];
    if (next == null) return null;
    if (!seen.add(next.id)) return null;
    current = next;
  }
  return current;
}

/// متوسّطُ مدّة الجلوس بالدقائق عبر **الجلسات** كلِّها لا عبر الطاولات.
///
/// بطاقةُ الرأس تحتاج رقماً واحداً، ومتوسّطُ متوسّطاتِ الصفوف ليس هو: طاولةٌ
/// جلست عليها جلسةٌ واحدةٌ ساعتين تزن في ذلك المتوسّط وزنَ طاولةٍ جلست عليها
/// عشرون جلسةً ربعَ ساعة. فالمقامُ هنا عددُ الجلسات المغلقة نفسِها.
///
/// و`null` حين لا جلسةَ مغلقةً — بنفس دلالة [TablesReportRow.avgTurnMinutes].
double? overallAvgTurnMinutes(List<TableOrderInput> orders) {
  var minutes = 0.0;
  var closed = 0;
  for (final order in orders) {
    if (!order.isSettledVisit) continue;
    minutes += order.closedAt!.difference(order.openedAt).inMilliseconds /
        Duration.millisecondsPerMinute;
    closed += 1;
  }
  return closed == 0 ? null : minutes / closed;
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

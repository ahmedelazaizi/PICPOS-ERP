// lib/domain/models/nav_search.dart
//
// بحثُ الشريط الجانبيّ — «خانة بحث عن الشاشات او ما داخلها» (‏أمرُ المالك
// 2026-09-12).
//
// ⚠️ **حسابٌ خالصٌ بلا ودجت.** المطابقةُ والتسويةُ والترتيبُ كلُّها قابلةٌ
// للقياس بلا شجرةٍ ولا `pumpWidget`، وهي المنطقُ الذي يُخطئ — لا الإطارُ
// الذي يعرضه.

/// التشكيلُ والتطويل — تُحذف قبل المطابقة.
final RegExp _marks = RegExp('[ً-ْٰـ]');
final RegExp _alefForms = RegExp('[أإآٱ]');
final RegExp _spaces = RegExp(r'\s+');

/// نصٌّ مُسوّىً للمطابقة.
///
/// ⚠️ **ولماذا لا تكفي `contains`**: التسمياتُ مكتوبةٌ كما كُتبت، و«الأصناف»
/// بهمزةٍ في المدخل و«الاصناف» بدونها في رأس المجموعة — **في نفس الملفّ**.
/// فمن يكتب ما يراه على الرأس لا يجد المدخل. وهما محرفان مختلفان بايتاً
/// (U+0623 و U+0627) لا شكلاً، فلا شيءَ في المقارنة النصّيّة يجمعهما.
String normalizeArabicForSearch(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(_marks, '');
  s = s.replaceAll(_alefForms, 'ا'); // أ إ آ ٱ ← ا
  s = s.replaceAll('ى', 'ي'); // ى ← ي
  s = s.replaceAll('ة', 'ه'); // ة ← ه
  s = s.replaceAll('ؤ', 'و'); // ؤ ← و
  s = s.replaceAll('ئ', 'ي'); // ئ ← ي
  return s.trim().replaceAll(_spaces, ' ');
}

/// نوعُ المدخل — يحكم الترتيبَ ومسارَ الفتح.
///
/// ⚠️ **والترتيبُ ليس ذوقاً.** «مبيعات» تطابق شاشةً وفئةً وتسعةَ تقارير؛
/// ومن كتبها يريد الشاشةَ أوّلاً. وبلا هذا التصنيف تغرق الشاشةُ الوحيدةُ
/// المطلوبةُ وسط ستّةٍ وأربعين تقريراً — فيصير البحثُ أسوأَ من غيابه.
enum NavSearchKind { screen, reportCategory, report }

/// مدخلٌ قابلٌ للبحث — الحدُّ الأدنى الذي تحتاجه المطابقة.
///
/// ⚠️ ولا يستورد `NavItemDef`: هذا الملفُّ في `domain` و`NavItemDef` في
/// `data/providers`، والمحوّلُ يعيش هناك فيبقى الاتّجاهُ data ← domain.
class NavSearchEntry {
  /// فهرسُ الشاشة — نفسُ `NavItemDef.index`.
  final int index;
  final String label;

  /// مفتاحُ المجموعة (‏`sales` · `inventory` …) — للعرض لا للمطابقة.
  final String? group;

  /// كلماتٌ تصف **ما داخلَ** الشاشة لا اسمَها.
  final List<String> keywords;

  final NavSearchKind kind;

  /// معرّفُ فئةِ التقارير — لمداخل الفئات والتقارير وحدَها.
  final String? reportCategoryId;

  /// معرّفُ التقرير — `null` لمدخل الفئة نفسِها.
  final String? reportId;

  /// اسمُ الحاوي (‏فئةُ التقرير) — يُعرَض سطراً ثانياً.
  ///
  /// ⚠️ وبلا ذلك يظهر «تقرير المبيعات» و«ملخّص المبيعات» متجاورَين بلا ما
  /// يقول من أيّ فئةٍ هما، وعناوينُ التقارير تتشابه بين الفئات.
  final String? parentLabel;

  const NavSearchEntry({
    required this.index,
    required this.label,
    this.group,
    this.keywords = const [],
    this.kind = NavSearchKind.screen,
    this.reportCategoryId,
    this.reportId,
    this.parentLabel,
  });
}

/// نتيجةُ مطابقة.
class NavSearchHit {
  final int index;
  final String label;
  final String? group;

  /// طابق الاسمُ نفسُه — لا كلمةٌ تصفه. يرفع النتيجةَ في الترتيب.
  final bool matchedInLabel;

  final NavSearchKind kind;
  final String? reportCategoryId;
  final String? reportId;
  final String? parentLabel;

  const NavSearchHit({
    required this.index,
    required this.label,
    required this.group,
    required this.matchedInLabel,
    this.kind = NavSearchKind.screen,
    this.reportCategoryId,
    this.reportId,
    this.parentLabel,
  });
}

/// مداخلُ [entries] المطابقةُ لـ[query]، مرتَّبةً: مطابقاتُ الاسم أوّلاً.
///
/// ⚠️ **وكلُّ كلمةٍ في الاستعلام لازمة** لا أيُّ واحدةٍ منها: «سند تحويل»
/// يجب أن يعطيَ سندَ التحويل، لا كلَّ ما فيه «سند» **زائداً** كلَّ ما فيه
/// «تحويل» — وهي نتيجةٌ تُغرق الصحيحَ في ضجيج.
///
/// واستعلامٌ فارغٌ يعود **فارغاً** لا بكلّ شيء: الشريطُ حينَها يعرض
/// مجموعاتِه المعتادة، وإعادةُ الكلّ تستبدل بها قائمةً مسطَّحةً بلا سبب.
List<NavSearchHit> searchNavEntries(String query, List<NavSearchEntry> entries) {
  final q = normalizeArabicForSearch(query);
  if (q.isEmpty) return const [];
  final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return const [];

  // دِلاءٌ مرتَّبة: مطابقةُ الاسم أوّلاً، وداخلَها شاشةٌ ثمّ فئةٌ ثمّ تقرير.
  final buckets = <List<NavSearchHit>>[
    for (var i = 0; i < 2 * NavSearchKind.values.length; i++) <NavSearchHit>[],
  ];

  for (final e in entries) {
    final label = normalizeArabicForSearch(e.label);
    final haystack = StringBuffer(label);
    for (final w in e.keywords) {
      haystack
        ..write(' ')
        ..write(normalizeArabicForSearch(w));
    }
    final all = haystack.toString();

    if (!tokens.every(all.contains)) continue;

    // مطابقةُ الاسم = كلُّ كلمةٍ موجودةٌ في التسمية وحدَها.
    final inLabel = tokens.every(label.contains);
    final hit = NavSearchHit(
      index: e.index,
      label: e.label,
      group: e.group,
      matchedInLabel: inLabel,
      kind: e.kind,
      reportCategoryId: e.reportCategoryId,
      reportId: e.reportId,
      parentLabel: e.parentLabel,
    );
    final slot = (inLabel ? 0 : NavSearchKind.values.length) + e.kind.index;
    buckets[slot].add(hit);
  }

  return [for (final b in buckets) ...b];
}

/// «ما داخلَ» كلِّ شاشة — بفهرسها في `kAllNavItemDefs`.
///
/// ⚠️ **وصفُ المحتوى لا مرادفُ الاسم**: أمرُ المالك «بحث عن الشاشات **او ما
/// داخلها**». فمن يبحث عن «كاشير» أو «باركود» أو «ضريبة» لا يعرف اسمَ
/// الشاشة أصلاً — وهو بالضبط من يحتاج البحث.
const kNavSearchKeywords = <int, List<String>>{
  0: ['لوحة', 'ملخص', 'احصائيات', 'مؤشرات'],
  1: ['كاشير', 'نقطة بيع', 'pos', 'سلة', 'دفع', 'فاتورة بيع', 'شيفت'],
  17: ['فواتير', 'مبيعات', 'ضريبة', 'عميل', 'اجل', 'نقدي'],
  37: ['اوردر', 'حجز صنف', 'عرض سعر'],
  3: ['مطعم', 'صالة', 'نادل', 'طلب', 'قسم', 'خريطة الصالة'],
  14: ['kds', 'شاشة المطبخ', 'تحضير', 'اوامر تشغيل', 'طلبات'],
  61: ['موعد', 'حجز', 'تقويم', 'مواعيد'],
  2: ['خصم', 'عرض', 'ترويج', 'باقة'],
  44: ['ارتجاع', 'استرداد', 'مرتجع'],
  9: ['مورد', 'شراء', 'فاتورة شراء'],
  30: ['امر شراء', 'طلب شراء', 'po'],
  45: ['ارتجاع مشتريات', 'رد للمورد'],
  4: ['صنف', 'منتج', 'باركود', 'سعر', 'وحدة', 'كولونيا', 'كارت صنف'],
  5: ['تصنيف', 'مجموعة', 'قسم اصناف'],
  8: ['رصيد', 'كمية', 'مخزن', 'جرد'],
  19: ['رصيد افتتاحي', 'كميات', 'مخزون'],
  20: ['تحويل', 'نقل بين المخازن', 'سند'],
  29: ['كارت صنف', 'حركة', 'وارد', 'منصرف'],
  25: ['تصنيع', 'تجميع', 'مكونات', 'bom', 'انتاج'],
  6: ['عميل', 'مورد', 'حساب', 'كشف حساب', 'رصيد عميل'],
  23: ['ولاء', 'نقاط', 'مكافات'],
  24: ['مندوب', 'خط سير', 'توصيل', 'دليفري'],
  16: ['موظف', 'راتب', 'حضور', 'اجازة', 'hr'],
  10: ['خزنة', 'نقدية', 'سند قبض', 'سند صرف', 'كاش'],
  56: ['تقفيل', 'وردية', 'شيفت', 'تسليم عهدة'],
  63: ['محاسبة', 'قيود', 'دليل حسابات', 'ميزان مراجعة'],
  34: ['شيك', 'كمبيالة', 'اوراق تجارية'],
  35: ['اصول', 'اهلاك', 'عهدة'],
  65: ['فئة اصول', 'تصنيف الاصول', 'العمر الافتراضي', 'حساب الاهلاك'],
  66: ['موقع', 'مواقع الاصول', 'توزيع', 'فرع الاصل'],
  67: ['قيد يدوي', 'سند قيد', 'مدين', 'دائن', 'تسوية'],
  68: ['تحصيل', 'قبض', 'سند قبض', 'شيك وارد', 'دفعة عميل'],
  69: ['صرف', 'دفع', 'سند صرف', 'شيك صادر', 'دفعة مورد'],
  22: ['فاتورة الكترونية', 'مصلحة الضرائب', 'eta', 'ضريبي'],
  26: ['مصروف', 'بند مصروف', 'ايجار', 'كهرباء'],
  11: ['تقرير', 'ارباح', 'مبيعات', 'احصائية'],
  15: ['رسم بياني', 'تحليل', 'مقارنة'],
  39: ['فروع', 'مقارنة فروع'],
  43: ['بناء تقرير', 'تصميم تقرير', 'تقرير مخصص'],
  13: ['فرع', 'مخزن', 'مستودع', 'موقع'],
  60: ['منطقة', 'نطاق'],
  21: ['ميزان', 'plu', 'وزن', 'سكيل'],
  12: ['اعدادات', 'ضبط', 'طابعة', 'ضريبة', 'عملة', 'نسخ احتياطي'],
  18: ['سجل', 'تدقيق', 'من عدل', 'audit'],
  64: ['قالب', 'طباعة', 'تصميم فاتورة'],
  40: ['مساعدة', 'دعم', 'شرح'],
};

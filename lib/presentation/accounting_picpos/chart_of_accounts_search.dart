// بحثُ دليل الحسابات — **يرشّح ويوسّع ويختار** (البند ١٩، المرحلة G).
//
// ═══ لماذا وحدةٌ خالصة ═══
//
// كان البحثُ سطرين داخل `build`: `name.contains(q) || code.contains(q)`.
// وعيبان فيه:
//
//  ‏١) **الاسمُ المخزَّنُ عربيٌّ** والواجهةُ قد تكون إنجليزيّة: من يكتب «Cash»
//     لا يجد «النقدية» وإن رآها مكتوبةً «Cash» في الشجرة (`trData`).
//  ‏٢) **الابنُ المطابقُ يُعرَض جذراً**: الأبُ لا يطابق فيُحذَف من القائمة،
//     فيظهر الحسابُ بلا سياقٍ في أعلى المجموعة. والدليلُ يُقرأ بموضعه.
//
// فالمطابقةُ هنا على الرمز والاسمِ المخزَّن واسمِ العرض معاً، والنتيجةُ
// تحمل **أسلافَ** كلِّ مطابقٍ ليُرسَم في مكانه ويُوسَّع إليه.
import '../../core/i18n/tr.dart';

/// صفُّ حسابٍ كما يحتاجه البحث — قيمٌ خالصةٌ لا صفُّ drift.
typedef CoaSearchRow = ({int id, int? parentId, String code, String name});

/// نتيجةُ البحث.
class CoaSearchResult {
  const CoaSearchResult({
    required this.matchIds,
    required this.visibleIds,
    required this.ancestorIds,
    required this.bestMatchId,
  });

  /// الحساباتُ المطابقةُ نفسُها.
  final Set<int> matchIds;

  /// المطابقةُ وأسلافُها — ما يُرسَم في الشجرة.
  final Set<int> visibleIds;

  /// الأسلافُ وحدَهم — ما يُوسَّع كي يظهر المطابق.
  final Set<int> ancestorIds;

  /// أقربُ مطابقةٍ تُختار في اللوح: رمزٌ مطابقٌ تماماً، ثمّ رمزٌ يبدأ
  /// بالنصّ، ثمّ أصغرُ رمزٍ مطابق. `null` ⇒ لا مطابقة.
  final int? bestMatchId;
}

/// هل يطابق الحسابُ النصَّ؟ على الرمز، والاسمِ المخزَّن، واسمِ العرض
/// (`trData`) — بلا حساسيّةٍ لحالة الأحرف اللاتينيّة.
bool coaMatches(String code, String name, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return code.toLowerCase().contains(q) ||
      name.toLowerCase().contains(q) ||
      trData(name).toLowerCase().contains(q);
}

/// يبحث في [rows] ويعيد المطابقَ وأسلافَه وأقربَ مطابقة.
CoaSearchResult coaSearch(List<CoaSearchRow> rows, String query) {
  final q = query.trim().toLowerCase();
  final byId = {for (final r in rows) r.id: r};
  final matches = <CoaSearchRow>[
    for (final r in rows)
      if (coaMatches(r.code, r.name, q)) r,
  ];

  final ancestors = <int>{};
  for (final m in matches) {
    // ⚠️ `seen` حارسُ حلقة: بياناتٌ تالفةٌ (أبٌ يشير إلى حفيده) كانت ستُدخل
    //    الحلقةَ بلا نهاية وتجمّد الشاشةَ مع كلّ ضغطةِ مفتاح.
    final seen = <int>{m.id};
    var parent = m.parentId;
    while (parent != null && seen.add(parent)) {
      ancestors.add(parent);
      parent = byId[parent]?.parentId;
    }
  }

  int? best;
  if (q.isNotEmpty && matches.isNotEmpty) {
    final sorted = [...matches]..sort((a, b) => a.code.compareTo(b.code));
    best = (sorted.where((r) => r.code.toLowerCase() == q).firstOrNull ??
            sorted.where((r) => r.code.toLowerCase().startsWith(q)).firstOrNull ??
            sorted.first)
        .id;
  }

  final matchIds = {for (final m in matches) m.id};
  return CoaSearchResult(
    matchIds: matchIds,
    visibleIds: {...matchIds, ...ancestors},
    ancestorIds: ancestors,
    bestMatchId: best,
  );
}

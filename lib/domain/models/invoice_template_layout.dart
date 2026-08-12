/// حسابُ ترتيب عناصر قالب الفاتورة — خالصٌ بلا قاعدةِ بياناتٍ ولا ودجت.
///
/// الخيارُ (ب) 2026-08-12: المطبوعُ يتبع `sortOrder`، و`sortOrder` يكتبه
/// محرّرُ الأقسام. فصار على المحرّر أن يرقّم **كلَّ** عنصرٍ في القالب لا ما
/// يقابله حقلٌ على الشاشة وحدَه.
library;

/// إعادةُ ترقيمٍ متسلسلةٍ تحفظ اليتامى في مواضعهم.
///
/// [elements] عناصرُ القالب بترتيبها الحاليّ المخزَّن (`sortOrder`).
/// [screenRank] خريطةُ `content` → رتبتِه على الشاشة، للحقول التي يعرضها
/// المحرّرُ فعلاً.
///
/// كلُّ عنصرٍ محتواه في [screenRank] يأخذ رتبةَ الشاشة. وما سواه — فاصلٌ بلا
/// محتوى، أو نصٌّ حرٌّ، أو حقلٌ لم يعُد المحرّرُ يعرضه — **يلحق بآخر عنصرٍ
/// معروفٍ يسبقه اليوم**، فلا يُنفى إلى الذيل ولا يطفو إلى الرأس.
///
/// المخرَج: `id` → `sortOrder` جديدٌ متسلسلٌ من الصفر بلا فجوات.
Map<int, int> resequenceTemplateElements({
  required List<({int id, String? content, int sortOrder})> elements,
  required Map<String, int> screenRank,
}) {
  final byCurrent = [...elements]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  // رتبةٌ كسريّة: المعروفُ يأخذ رتبةَ الشاشة صحيحةً، واليتيمُ يأخذ رتبةَ
  // سابقه مضافاً إليها كسرٌ متزايد — فيقع بينه وبين العنصر الذي يليه.
  final ranked = <({int id, double rank})>[];
  var lastKnown = -1.0;
  var orphanSeq = 0;
  for (final el in byCurrent) {
    final known = el.content == null ? null : screenRank[el.content!];
    if (known != null) {
      lastKnown = known.toDouble();
      orphanSeq = 0;
      ranked.add((id: el.id, rank: lastKnown));
    } else {
      orphanSeq++;
      // الكسرُ أصغرُ من أيّ فارقٍ بين رتبتَي شاشةٍ متجاورتَين (‏١)،
      // فلا يتخطّى اليتيمُ العنصرَ التالي مهما تعدّد اليتامى.
      ranked.add((id: el.id, rank: lastKnown + orphanSeq / (orphanSeq + 1.0) / 2));
    }
  }

  ranked.sort((a, b) => a.rank.compareTo(b.rank));
  return {for (var i = 0; i < ranked.length; i++) ranked[i].id: i};
}

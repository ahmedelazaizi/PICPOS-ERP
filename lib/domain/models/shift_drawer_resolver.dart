/// يحدّد «درجَ الوردية»: الخزنةَ النقديةَ التي تُنسب إليها حركاتُ الوردية.
///
/// انتُزع من `TreasuryDao._settleShift` (كان مضمَّناً في معاملةِ قاعدةٍ فلا
/// يُختبر إلا بقاعدةٍ كاملة). وانتزاعُه يمنع تعريفَين للدرج: الإقفالُ يسوّي
/// درجاً والمرتجعُ يصرف من آخر.
///
/// المطابقةُ حرفيةٌ للكتلةِ الأصليةِ لأنّ الدالّةَ ستحلّ محلَّها في تسوية
/// فرقِ الوردية، فأيُّ اختلافٍ يغيّر الدرجَ الذي يُكتب عليه صفُّ التسوية.
///
/// [cashSafeIdsInBranch] الخزائنُ النقدية في نطاق فرع الوردية.
/// [movedBySafeId] مجموعُ ما تحرّك على كلّ خزنة (قد يحوي خزائنَ خارجَ النطاق
/// فتُتجاهَل).
int? resolveShiftDrawer({
  required Set<int> cashSafeIdsInBranch,
  required Map<int, double> movedBySafeId,
}) {
  if (cashSafeIdsInBranch.isEmpty) return null;

  // فقط الخزائنُ التي لها حركاتٌ فعليةٌ وفي النطاق
  final eligible = movedBySafeId.entries
      .where((e) => cashSafeIdsInBranch.contains(e.key))
      .toList();

  if (eligible.isEmpty) {
    // لا حركاتَ إطلاقاً أو كلُّها خارجَ النطاق ⇒ أوّلُ خزنة
    return cashSafeIdsInBranch.first;
  }

  // الخزنةُ الأكثرُ حركة، مع إبقاء الأولى عند التعادل (ترتيبُ الخريطة)
  return eligible
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;
}

/// يحدّد «درجَ الوردية»: الخزنةَ النقديةَ التي تُنسب إليها حركاتُ الوردية.
///
/// انتُزع من `TreasuryDao._settleShift` (كان مضمَّناً في معاملةِ قاعدةٍ فلا
/// يُختبر إلا بقاعدةٍ كاملة). وانتزاعُه يمنع تعريفَين للدرج: الإقفالُ يسوّي
/// درجاً والمرتجعُ يصرف من آخر.
///
/// [cashSafeIdsInBranch] الخزائنُ النقدية في نطاق فرع الوردية.
/// [movedBySafeId] مجموعُ ما تحرّك على كلّ خزنة (قد يحوي خزائنَ خارجَ النطاق
/// فتُتجاهَل).
int? resolveShiftDrawer({
  required Set<int> cashSafeIdsInBranch,
  required Map<int, double> movedBySafeId,
}) {
  if (cashSafeIdsInBranch.isEmpty) return null;

  double best = -1;
  int? bestId;
  for (final id in cashSafeIdsInBranch) {
    final moved = movedBySafeId[id] ?? 0;
    if (moved > best) {
      best = moved;
      bestId = id;
    }
  }
  // كلُّها أصفار ⇒ `best == 0` و`bestId` أوّلُ عنصرٍ في ترتيب المجموعة،
  // وهو بعينه سلوكُ `drawerSafeIds.first` القائم.
  return bestId;
}

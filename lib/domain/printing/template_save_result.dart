// نتيجةُ حفظِ القالب — **بياناتٌ خالصةٌ يقرؤها الإشعار**.
//
// ── لماذا لا تحمل صفوفَ الرابطات ─────────────────────────────────────────
// عقدُ الأزرار يشترط أن يقول الإشعارُ **ما أُلغي بالاسم**: «الإلغاءُ الصامتُ
// يجعل المستخدمَ يظنّ قالبين مفعّلَين». والشاشةُ ممنوعةٌ من `data/database`،
// فحملُ صفٍّ من drift هنا يجعل هذه النتيجةَ غيرَ قابلةٍ للعرض أصلاً.
//
// فتُحمَل **أنواعُ المستندات** التي فُكَّت رابطاتُها، وتُترجَم في العرض.
library;

class TemplateSaveResult {
  /// كم عنصراً كُتب — الإشعارُ يقوله، وهو أيضاً ما يكشف حفظاً كتب صفراً.
  final int elementCount;

  final int visibleColumnCount;

  /// أنواعُ المستندات التي أُلغيت رابطاتُها بتفعيل هذا القالب.
  final List<String> cancelledDocumentTypes;

  final bool activated;

  const TemplateSaveResult({
    required this.elementCount,
    required this.visibleColumnCount,
    this.cancelledDocumentTypes = const [],
    this.activated = false,
  });
}

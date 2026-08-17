/// نطاقُ **النسبة** — إلى أيِّ وحدةٍ تنظيميّةٍ يجوز أن يُنسَب مستندٌ جديدٌ
/// على هذا الجهاز.
///
/// وهو سؤالٌ **غيرُ** سؤالِ الرؤية الذي يجيبه `ClientScope` وقصُّ الخادم في
/// `/api/sync/pull`. الفرقُ في الدلالة لا في الصياغة:
///
///   • **الرؤية متسامحة** — `branch_id = x OR branch_id IS NULL`. الصفُّ بلا
///     فرعٍ عامٌّ/مقرّيٌّ فيبقى ظاهراً (قرارُ مالكٍ موثّق في
///     `api_handler.dart:2301`)، والخادمُ يرسله للعميل فعلاً.
///
///   • **النسبة صارمة** — مساواةٌ فقط. لأن فرعَ المستند يُشتقُّ من مخزنه
///     (`purchase_dao.dart:589-594`)، وقصُّ القوائم يقرأ
///     `branch_id IN (…) OR branch_id IS NULL`. فمستندٌ نُسب إلى مخزنٍ بلا
///     فرعٍ يخرج `branch_id = NULL` فيظهر في **كلِّ** الفروع — عطبٌ أوسعُ من
///     «غائبٍ عن فرعه» ولا سبيلَ لتصحيحه من القائمة.
///
/// ⚠️ فلا تُوحَّد هذه الدالّةُ مع `clientScopeProvider` مهما تشابه شكلُهما.
library;

/// يقصُر [all] على صفوفِ [assignmentBranchId]، و[branchIdOf] يستخرج فرعَ الصفّ.
///
/// `assignmentBranchId == null` تعني «بلا حصر» (جهازٌ مستقلٌّ أو خادم).
///
/// وإن أفرغ الترشيحُ القائمةَ تعود الكاملةُ — احتياطُ Spec 103 المقصود:
/// قائمةٌ خاويةٌ تُوقف المحلَّ، وقائمةٌ واسعةٌ تُبقيه يعمل ويُصحَّح اختيارُها.
List<T> restrictForAssignment<T>(
  List<T> all,
  int? assignmentBranchId, {
  required int? Function(T item) branchIdOf,
}) {
  if (assignmentBranchId == null) return all;

  final scoped =
      all.where((item) => branchIdOf(item) == assignmentBranchId).toList();

  return scoped.isEmpty ? all : scoped;
}

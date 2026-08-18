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

/// ما يفعله المنتقي حين يكون النطاقُ محصوراً ولا يقع فيه صفٌّ واحد.
///
/// والاختيارُ بين الاثنين ليس ذوقاً بل **سابقةُ المالك 2026-08-04** في
/// `getWarehouseScopeForUser`: «الجهازُ المستقلُّ يبقى بسلوكه القديم عن قصد —
/// محلٌّ بجهازٍ واحد وكاشيرٌ محدش خصّصله مخازن ماينفعش يقف. الأجهزةُ التي
/// تسرّب فعلاً هي العميلُ والمرآة، وهي التي تُقفل».
enum EmptyScopePolicy {
  /// توسيعٌ إلى القائمة الكاملة — المستقلُّ والخادم.
  widen,

  /// رفضٌ مقفول — العميلُ والمرآة. والحفظُ يرفض حينئذٍ برسالةٍ قابلةٍ للإصلاح.
  refuse,
}

/// يقصُر [all] على صفوفِ [allowedBranchIds]، و[branchIdOf] يستخرج فرعَ الصفّ.
///
/// و**المجموعةُ لا الرقم** لأن «فرعي» ليس واحداً في كلِّ وضع: المرآةُ تحمل
/// فروعَ مستخدمِها كلَّها (قرارُ المالك 2026-08-04 + قصُّ الخادم FR-1)،
/// والخادمُ والمستقلُّ يحملان فروعَ المستخدمِ إن كان محصوراً. المصدرُ الوحيدُ
/// لهذه المجموعة هو `branchScopeProvider` — وهو الذي يحسم الأوضاعَ الأربعة.
///
/// دلالةُ [allowedBranchIds]:
///   • `null`  ⇒ بلا حصر.
///   • `{}`    ⇒ **فشلٌ مقفول** بقرارِ المزوّد نفسِه (مستخدمٌ سيّئُ التزويد،
///     أو مرآةٌ لغيرِ مميَّز). لا يُوسَّع مهما كانت [onEmpty] — وإلا صار كلُّ
///     حصرٍ فرعيٍّ في المستودع بلا أثر.
///   • `{ids}` ⇒ مساواةٌ صارمة. والصفُّ بلا فرعٍ يسقط: الرؤيةُ متسامحةٌ
///     والنسبةُ صارمة (انظر رأسَ الملفّ).
///
/// و[onEmpty] تحكم حالةً واحدةً فقط: نطاقٌ محصورٌ صحيحٌ لا يقع فيه شيء —
/// أي فرعٌ بلا مخزنٍ صالح.
List<T> restrictForAssignment<T>(
  List<T> all,
  Set<int>? allowedBranchIds, {
  required int? Function(T item) branchIdOf,
  EmptyScopePolicy onEmpty = EmptyScopePolicy.widen,
}) {
  if (allowedBranchIds == null) return all;
  if (allowedBranchIds.isEmpty) return <T>[];

  final scoped = all.where((item) {
    final branchId = branchIdOf(item);
    return branchId != null && allowedBranchIds.contains(branchId);
  }).toList();

  if (scoped.isNotEmpty) return scoped;
  return onEmpty == EmptyScopePolicy.widen ? all : <T>[];
}

/// يحسم مخزنَ المستندِ عند **الحفظ** من نفسِ المصدرِ الذي عرضه المنتقي.
///
/// منقولٌ عن `resolvePurchaseWarehouseId` في UralCash (قراءةٌ بإذنِ المالك):
/// ترشيحُ القائمةِ وحدَه تجميليّ — يحرس المعروضَ ولا يحرس المحفوظ. ومسارُ
/// الحفظ كان يثق بما يصله، فإن وصلته قيمةٌ خارجَ النطاق (من مُنادٍ آخر، أو من
/// حالةٍ بقيت بعد تبديلِ الفرع) خُتمت على المستند بلا اعتراض — ومنها يُشتقُّ
/// فرعُه ومركزُ تكلفته.
///
/// [scopedWarehouseIds] المعرّفاتُ المسموحة (‏`getAssignableWarehouses`).
/// [isEditMode] يُبقي مخزنَ المستندِ القائمِ وإن خرج عن النطاق: الحصرُ يمنع
/// ختماً **جديداً** خارجه ولا يجمّد ما هو مختومٌ فعلاً، وإلا صارت مستنداتُ
/// الفروعِ الأخرى غيرَ قابلةٍ للتحرير من جهازٍ مربوطٍ بفرع.
int resolveAssignedWarehouseId({
  required int? selected,
  required List<int> scopedWarehouseIds,
  bool isEditMode = false,
}) {
  if (isEditMode && selected != null) return selected;

  if (scopedWarehouseIds.isEmpty) {
    throw Exception(
        'لا يوجد مخزن متاح على هذا الجهاز — راجع ربط الفرع بمخزن نشط');
  }

  // بلا اختيارٍ صريح: أوّلُ مخزنٍ في النطاق — وهو نفسُه ما عرضه المنتقي.
  if (selected == null) return scopedWarehouseIds.first;

  if (!scopedWarehouseIds.contains(selected)) {
    throw Exception('المخزن المختار خارج نطاق فرع هذا الجهاز');
  }

  return selected;
}

// لازم للمُعامل `|` على `Expression<bool>` (شرط `OR branch_id IS NULL`).
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/branch_assignment_scope.dart';
import '../../domain/models/client_scope.dart';
import '../../services/network_service.dart';
import 'providers.dart';

/// Provider for the current client's operational scope.
///
/// - In **server/standalone** mode: returns [ClientScope.unrestricted]
/// - In **client** mode: resolves the assigned branch and its
///   warehouses, safes, and cost centers from the local database.
///
/// Usage: `ref.watch(clientScopeProvider)` returns an `AsyncValue<ClientScope>`.
///
/// ⚠️ **مفيش أي مُنادٍ للمزوّد ده في المستودع حالياً** — اتساب متعمّد. توصيله
/// بالشاشات تغيير سلوكي واسع لوحده. الإصلاحين اللي هنا (فشل مقفول + دلالة
/// `OR IS NULL`) الغرض منهم إنه يبقى **آمن ومتسق مع الخادم لحظة ما حد
/// يوصّله**، مش إنه يغيّر سلوك النهارده.
///
/// ⚠️⚠️ ومش ده جواب سؤال **النسبة** (`restrictForAssignment` +
/// `IBranchRepository.getAssignmentBranchId`). الاتنين بيقصّوا بالفرع فيبانوا
/// توأمين، وهما مختلفين في تلات حاجات، وكل واحدة منهم مقصودة:
///
///   ١. **الدلالة**: هنا `branch_id = x OR IS NULL` (رؤية — الصف بلا فرع عام
///      وبيفضل ظاهر، مطابقةً لقصّ الخادم). والنسبة **مساواة صارمة**، لأن
///      مستنداً يُنسب لمخزن بلا فرع بيخرج `branch_id = NULL` فيظهر في **كل**
///      الفروع.
///   ٢. **المُحدِّد**: هنا `NetworkService.isClient` (عميل بس). والنسبة
///      `SyncInterceptor.isClientMode` (عميل **ومرآة**) — وده سلوك Spec 103
///      القائم.
///   ٣. **الفشل**: هنا مقفول (`ClientScope.closed`). وهناك مفتوح، عشان جهاز
///      ناقص الاقتران يفضل قادر يصدّر مستنداته بدل ما يقف.
///
/// فمن يوحّدهما «تنظيفاً» يكسر واحدة من التلاتة صامتة.
final clientScopeProvider = FutureProvider<ClientScope>((ref) async {
  if (!NetworkService.instance.isClient) {
    return ClientScope.unrestricted;
  }

  final prefs = await SharedPreferences.getInstance();
  final branchId = prefs.getInt('client_branch_id');

  if (branchId == null) {
    // كان بيرجّع `unrestricted` — أي إن جهاز عميل **ناقص التنصيب** ياخد
    // وصولاً كاملاً. نقص الهوية لازم يفشل مقفولاً، زي سنتينل `-1` في G2.
    debugPrint('[ClientScope] ⚠ لا يوجد client_branch_id — نطاق مقفول');
    return ClientScope.closed;
  }

  final db = ref.read(databaseProvider);

  // Resolve branch name
  final branch = await (db.select(db.branches)
        ..where((b) => b.id.equals(branchId)))
      .getSingleOrNull();
  final branchName = branch?.name ?? 'فرع $branchId';

  // Resolve warehouses belonging to this branch.
  //
  // `OR branch_id IS NULL` مقصود ولازم يفضل: الخادم بيقصّ بنفس الدلالة في
  // `/api/sync/pull` (الصفوف اللي فرعها NULL = عامة/المقر وبتفضل ظاهرة).
  // `equals` لوحدها كانت هتخلّي الطرفين يختلفوا لحظة توصيل المزوّد ده:
  // الخادم بيبعت صفوف العميل ما بيشوفهاش، فتظهر مخازن «مفقودة» على الجهاز.
  final warehouses = await (db.select(db.warehouses)
        ..where((w) => w.branchId.equals(branchId) | w.branchId.isNull()))
      .get();
  final warehouseIds = warehouses.map((w) => w.id).toList();

  // Resolve safes belonging to this branch (same NULL = global semantics)
  final safes = await (db.select(db.safes)
        ..where((s) => s.branchId.equals(branchId) | s.branchId.isNull()))
      .get();
  final safeIds = safes.map((s) => s.id).toList();

  // Resolve cost centers: branch's own + warehouses' + safes'
  final costCenterIds = <int>{};
  if (branch?.costCenterId != null) costCenterIds.add(branch!.costCenterId!);
  for (final w in warehouses) {
    if (w.costCenterId != null) costCenterIds.add(w.costCenterId!);
  }
  for (final s in safes) {
    if (s.costCenterId != null) costCenterIds.add(s.costCenterId!);
  }

  final scope = ClientScope(
    branchId: branchId,
    branchName: branchName,
    allowedWarehouseIds: warehouseIds,
    allowedSafeIds: safeIds,
    allowedCostCenterIds: costCenterIds.toList(),
  );

  debugPrint('[ClientScope] Resolved: $scope');
  return scope;
});

// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ النسبة — «إلى أين يجوز أن يُنسَب مستندٌ جديد» في الأوضاع الأربعة
// ═══════════════════════════════════════════════════════════════════════════
//
// المصدرُ هو [branchScopeProvider] لا `client_branch_id`، لأن «فرعي» يختلف
// بالوضع، والمزوّدُ ذاك وحدَه يحسم الأربعة بقراراتٍ موثّقةٍ للمالك:
//
//   مستقل/خادم ⇒ فروعُ المستخدم (فكاشيرٌ محصورٌ يبقى محصوراً، وهو ما كان
//                يفوت `client_branch_id` لأنه لا يُكتب إلا في وضع العميل).
//   عميل       ⇒ فرعُ الجهاز (عزلُ المرحلة ٦)، ويُستثنى المديرُ المُرقّى.
//   مرآة       ⇒ فروعُ المستخدمِ **كلُّها** (قرارُ المالك 2026-08-04)، وهو
//                نفسُ ما يسلّمه الخادمُ بعد FR-1. و`client_branch_id` لا
//                يُكتب على المرآة أصلاً، فكان الحصرُ يسقط عنها بالكامل:
//                مديرٌ لفرعَي {أ،ب} كان يُنشئ فاتورةً على مخزنِ ج ثم لا يراها.
//
// وسياسةُ الخلوّ ([EmptyScopePolicy]) من سابقةِ المالك 2026-08-04 نفسِها:
// تُقفل الأجهزةُ التي تسرّب (عميل/مرآة) ولا يُوقَف محلٌّ بجهازٍ واحد.

/// العميلُ والمرآةُ هما الجهازان اللذان تُقفلهما سابقةُ 2026-08-04 — والمُحدِّدُ
/// واحدٌ في المستودع كلِّه: [NetworkService.isBranchScopedDevice].
EmptyScopePolicy get _deviceEmptyScopePolicy =>
    NetworkService.instance.isBranchScopedDevice
        ? EmptyScopePolicy.refuse
        : EmptyScopePolicy.widen;

/// المخازنُ التي يجوز نسبةُ مستندٍ جديدٍ إليها على هذا الجهاز، بهذا الترتيب:
/// الصالحُ ⇒ حصرُ الفرع ⇒ حصرُ المستخدمِ للمخازن ⇒ إبقاءُ المنتقى سلفاً.
///
/// [keepSelected] معرّفُ مخزنٍ محفوظٍ في صفٍّ قائم (مخزنُ فاتورةٍ قيدَ التعديل،
/// أو المخزنُ الافتراضيُّ لصنف). يُلحَق ولو خرج عن النطاق: قائمةٌ لا تحوي
/// قيمتَها المنتقاةَ تُسقط `DropdownButton` بتأكيدٍ صريح، وإسقاطُها صامتاً
/// يعيد كتابةَ بياناتِ صفٍّ قائمٍ عند الحفظ.
final assignableWarehousesProvider =
    FutureProvider.family<List<Warehouse>, int?>((ref, keepSelected) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  final userId = ref.watch(authProvider.select((s) => s.user?.id));

  // الصالحُ وحدَه: شاهدُ الحذفِ (`deletedAt`) يصل من الخادم عبر `DeltaPull`
  // فيبقى الصفُّ محلّياً، فلا يكفي الحذفُ المركزيُّ لإخفائه عن المنتقيات.
  final usable = await (db.select(db.warehouses)
        ..where((w) => w.isActive.equals(true) & w.deletedAt.isNull())
        ..orderBy([(w) => OrderingTerm.asc(w.name)]))
      .get();

  var result = restrictForAssignment(
    usable,
    scope.allowedBranchIds,
    branchIdOf: (w) => w.branchId,
    onEmpty: _deviceEmptyScopePolicy,
  );

  // حصرُ المستخدمِ على مستوى **المخزن** — نفسُ عقدِ `getWarehouseScopeForUser`
  // المطبَّقِ في `allWarehousesProvider`: `null` بلا حصر، و`{}` غيرُ مميَّزٍ
  // بلا تخصيصٍ ⇒ يُقفل على العميل/المرآة ويمرّ على المستقلّ (سابقة 2026-08-04).
  if (userId != null) {
    final warehouseScope = await db.getWarehouseScopeForUser(userId);
    if (warehouseScope != null) {
      result = warehouseScope.isEmpty
          ? (NetworkService.instance.isBranchScopedDevice
              ? <Warehouse>[]
              : result)
          : result.where((w) => warehouseScope.contains(w.id)).toList();
    }
  }

  if (keepSelected == null || result.any((w) => w.id == keepSelected)) {
    return result;
  }
  final kept = await (db.select(db.warehouses)
        ..where((w) => w.id.equals(keepSelected)))
      .getSingleOrNull();
  return kept == null ? result : [kept, ...result];
});

/// مراكزُ التكلفةِ التي يجوز نسبةُ مستندٍ جديدٍ إليها على هذا الجهاز.
///
/// و`CostCenters` بلا عمودِ فرع، فالانتماءُ **يُشتقُّ** كما يشتقّه خادمُ
/// PicPos حرفياً في `_resolveBranchCostCenterIds` (`api_handler.dart:2111`):
/// مركزُ الفرعِ نفسِه ∪ مراكزُ مخازنِه ∪ مراكزُ خزائنِه. والتطابقُ مقصود —
/// الخادمُ يقصّ مزامنةَ `cost_centers` بهذا الاشتقاق، فلو خالفته الواجهةُ
/// لعرضت مركزاً لا يصل الجهازَ أصلاً أو أخفت مركزاً وصله.
final assignableCostCentersProvider =
    FutureProvider<List<CostCenter>>((ref) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);

  final allActive = await db.getActiveCostCenters();
  final allowed = scope.allowedBranchIds;

  if (allowed == null) return allActive;
  if (allowed.isEmpty) return const <CostCenter>[];

  final scopedIds = await db.getBranchCostCenterIds(allowed);
  final scoped = allActive.where((c) => scopedIds.contains(c.id)).toList();
  if (scoped.isNotEmpty) return scoped;

  return _deviceEmptyScopePolicy == EmptyScopePolicy.widen
      ? allActive
      : const <CostCenter>[];
});

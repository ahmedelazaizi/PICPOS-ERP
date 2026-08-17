// لازم للمُعامل `|` على `Expression<bool>` (شرط `OR branch_id IS NULL`).
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

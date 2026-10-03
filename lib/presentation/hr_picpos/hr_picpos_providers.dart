// J4 — مزوّداتُ شاشات الموارد البشريّة في PicPos (سجلّ الموظفين وملفُّهم
// والأقسامُ والمسمّيات). كلُّ قراءةٍ تمرّ بـ`databaseProvider` كما في شاشة
// المناديب، والقائمةُ محصورةٌ بفروع المستخدم (H6).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../../domain/models/distribution_model.dart';
import '../../domain/models/hr_employee_file.dart';
import '../../domain/models/voucher_book.dart';

/// موظّفو نطاق المستخدم بملفّاتهم. ريثما يُحَلّ النطاقُ لا صفوف (H6).
final hrProfilesProvider =
    FutureProvider.autoDispose<List<EmployeeProfile>>((ref) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  final all = await db.listEmployeeProfiles();
  return [for (final p in all) if (scope.isAllowed(p.branchId)) p];
});

final hrDepartmentsProvider = FutureProvider.autoDispose<List<HrDepartment>>(
    (ref) => ref.watch(databaseProvider).listHrDepartments());

final hrJobTitlesProvider = FutureProvider.autoDispose<List<HrJobTitle>>(
    (ref) => ref.watch(databaseProvider).listHrJobTitles());

final hrBranchesProvider = FutureProvider.autoDispose<List<Branche>>(
    (ref) => ref.watch(databaseProvider).getBranches());

/// المستنداتُ المنتهية أو القريبةُ من الانتهاء لكلّ موظف.
final hrExpiringDocsProvider = FutureProvider.autoDispose<Map<int, int>>(
    (ref) => ref.watch(databaseProvider).expiringDocumentCounts());

final hrAllowancesProvider = FutureProvider.autoDispose
    .family<List<EmployeeAllowance>, int>((ref, id) =>
        ref.watch(databaseProvider).listEmployeeAllowances(id));

final hrDocumentsProvider = FutureProvider.autoDispose
    .family<List<EmployeeDocument>, int>((ref, id) =>
        ref.watch(databaseProvider).listEmployeeDocuments(id));

final hrHistoryProvider = FutureProvider.autoDispose
    .family<List<EmployeeHistoryEvent>, int>(
        (ref, id) => ref.watch(databaseProvider).listEmployeeHistory(id));

final hrProfileProvider = FutureProvider.autoDispose
    .family<EmployeeProfile?, int>(
        (ref, id) => ref.watch(databaseProvider).getEmployeeProfile(id));

/// المستخدمون المتاحون للربط بهذا الموظف (غيرُ المربوطين بغيره).
final hrLinkableUsersProvider = FutureProvider.autoDispose
    .family<List<User>, int>(
        (ref, id) => ref.watch(databaseProvider).linkableUsers(id));

final hrRolesProvider = FutureProvider.autoDispose<List<Role>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.roles).get();
});

/// ما يملكه المندوبُ في نموذج التوزيع: مساراتُه ومواردُه ودفاترُه.
class HrRepAssets {
  const HrRepAssets({
    required this.routes,
    required this.allRoutes,
    required this.resources,
    required this.books,
    required this.allBooks,
    required this.warehouses,
    required this.safes,
  });
  final List<DistributionRoute> routes;
  final List<DistributionRoute> allRoutes;
  final RepResources? resources;
  final List<VoucherBook> books;
  final List<VoucherBook> allBooks;
  final List<Warehouse> warehouses;
  final List<Safe> safes;
}

final hrRepAssetsProvider =
    FutureProvider.autoDispose.family<HrRepAssets, int>((ref, id) async {
  final db = ref.watch(databaseProvider);
  final routes = await db.listDistributionRoutes();
  final books = await db.listVoucherBooks();
  return HrRepAssets(
    routes: [for (final r in routes) if (r.repEmployeeId == id) r],
    allRoutes: routes,
    resources: await db.getRepResources(id),
    books: [for (final b in books) if (b.holderEmployeeId == id) b],
    allBooks: books,
    warehouses: await (db.select(db.warehouses)
          ..where((w) => w.isActive.equals(true)))
        .get(),
    safes: await (db.select(db.safes)..where((s) => s.deletedAt.isNull()))
        .get(),
  );
});

/// يُعيد قراءةَ كلِّ ما يتغيّر بعد حفظٍ في ملفّ الموظف.
void refreshHr(WidgetRef ref, [int? employeeId]) {
  ref.invalidate(hrProfilesProvider);
  ref.invalidate(hrDepartmentsProvider);
  ref.invalidate(hrJobTitlesProvider);
  ref.invalidate(hrExpiringDocsProvider);
  if (employeeId != null) {
    ref.invalidate(hrProfileProvider(employeeId));
    ref.invalidate(hrAllowancesProvider(employeeId));
    ref.invalidate(hrDocumentsProvider(employeeId));
    ref.invalidate(hrHistoryProvider(employeeId));
    ref.invalidate(hrLinkableUsersProvider(employeeId));
    ref.invalidate(hrRepAssetsProvider(employeeId));
  }
}

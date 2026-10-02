// مزوّداتُ شاشة «إدارة المناديب والتوزيع» (المرحلة و).
//
// كلُّ قراءةٍ تمرّ بـ`databaseProvider` (‏نفسُ نمط دفاتر السندات)، والشاشةُ
// لا تستورد `data/database` مباشرةً.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../data/providers/providers.dart';
import '../../domain/models/distribution_model.dart';
import '../../domain/models/voucher_book.dart';
import '../screens/providers/distribution_controller.dart';

final dmAreasProvider = FutureProvider.autoDispose<List<DistributionArea>>(
    (ref) => ref.watch(databaseProvider).listDistributionAreas());

final dmRoutesProvider = FutureProvider.autoDispose<List<DistributionRoute>>(
    (ref) => ref.watch(databaseProvider).listDistributionRoutes());

final dmRouteCustomersProvider = FutureProvider.autoDispose
    .family<List<RouteCustomer>, int>((ref, routeId) =>
        ref.watch(databaseProvider).listRouteCustomers(routeId));

/// موظّفو نطاق المستخدم — المناديبُ يُختارون منهم.
final dmEmployeesProvider = FutureProvider.autoDispose<List<Employee>>(
    (ref) => ref.watch(distributionControllerProvider).getAllEmployees());

final dmCustomersProvider = FutureProvider.autoDispose<List<Party>>(
    (ref) => ref.watch(distributionControllerProvider).getAllCustomers());

final dmRepResourcesProvider = FutureProvider.autoDispose<List<RepResources>>(
    (ref) => ref.watch(databaseProvider).listRepResources());

final dmWarehousesProvider = FutureProvider.autoDispose<List<Warehouse>>(
    (ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.warehouses)..where((w) => w.isActive.equals(true)))
      .get();
});

final dmSafesProvider = FutureProvider.autoDispose<List<Safe>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.safes)..where((s) => s.deletedAt.isNull())).get();
});

final dmProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)..where((p) => p.isActive.equals(true)))
      .get();
});

/// دفاترُ السندات كلُّها — تُصفّى لكلّ مندوبٍ بحامِلها.
final dmVoucherBooksProvider = FutureProvider.autoDispose<List<VoucherBook>>(
    (ref) => ref.watch(databaseProvider).listVoucherBooks());

/// المسارُ والمنطقةُ والمندوبُ (المشتقّ) لكلّ عميلٍ على مسار.
final dmCustomerRouteInfoProvider =
    FutureProvider.autoDispose<Map<int, CustomerRouteInfo>>(
        (ref) => ref.watch(databaseProvider).customerRouteInfoMap());

/// يُعيد قراءةَ كلِّ ما يتغيّر بعد عمليّةٍ على المسارات أو المناديب.
void refreshDistribution(WidgetRef ref) {
  ref.invalidate(dmAreasProvider);
  ref.invalidate(dmRoutesProvider);
  ref.invalidate(dmRouteCustomersProvider);
  ref.invalidate(dmRepResourcesProvider);
  ref.invalidate(dmCustomerRouteInfoProvider);
  ref.invalidate(dmSafesProvider);
}

/// أيّامُ الأسبوع ISO بأسمائها القصيرة.
Map<int, String> dmWeekdayLabels() => {
      6: tr('السبت'),
      7: tr('الأحد'),
      1: tr('الاثنين'),
      2: tr('الثلاثاء'),
      3: tr('الأربعاء'),
      4: tr('الخميس'),
      5: tr('الجمعة'),
    };

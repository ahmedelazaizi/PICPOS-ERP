import '../../domain/repositories/distribution_repository.dart';
import '../database/database.dart';
import '../database/extensions/distribution_dao.dart';

class DriftDistributionRepository implements IDistributionRepository {
  final AppDatabase _db;

  DriftDistributionRepository(this._db);

  @override
  Stream<List<SalesRoute>> watchSalesRoutes() => _db.watchSalesRoutes();

  @override
  Future<void> updateSalesRoute(int id, SalesRoutesCompanion data) =>
      _db.updateSalesRoute(id, data);

  @override
  Future<void> createSalesRoute(SalesRoutesCompanion data) =>
      _db.createSalesRoute(data);

  @override
  Future<void> deactivateSalesRoute(int id) => _db.deactivateSalesRoute(id);

  @override
  Stream<List<RouteVisit>> watchRouteVisits(
    int routeId,
    DateTime fromDate,
    DateTime toDate,
  ) => _db.watchRouteVisits(routeId, fromDate, toDate);

  @override
  Future<int> createRouteVisit(RouteVisitsCompanion visit) =>
      _db.createRouteVisit(visit);

  @override
  Future<void> updateRouteVisitStatus(
    int id,
    String status, {
    String? notes,
    int? saleId,
    double? orderAmount,
  }) => _db.updateRouteVisitStatus(
    id,
    status,
    notes: notes,
    saleId: saleId,
    orderAmount: orderAmount,
  );

  @override
  Stream<List<SalesRepTarget>> watchMonthlyTargets(int year, int month) =>
      _db.watchMonthlyTargets(year, month);

  @override
  Future<void> setSalesRepTarget({
    required int salesRepId,
    required int year,
    required int month,
    required double targetAmount,
    int targetVisits = 0,
  }) => _db.setSalesRepTarget(
    salesRepId: salesRepId,
    year: year,
    month: month,
    targetAmount: targetAmount,
    targetVisits: targetVisits,
  );

  @override
  Stream<List<SalesRepCollection>> watchAllCollections(
    DateTime fromDate,
    DateTime toDate,
  ) => _db.watchAllCollections(fromDate, toDate);

  @override
  Future<int> createCollection(SalesRepCollectionsCompanion collection) =>
      _db.createCollection(collection);
}

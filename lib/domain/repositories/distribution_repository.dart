import '../../data/database/database.dart';

abstract class IDistributionRepository {
  // Routes
  Stream<List<SalesRoute>> watchSalesRoutes();
  Future<void> updateSalesRoute(int id, SalesRoutesCompanion data);
  Future<void> createSalesRoute(SalesRoutesCompanion data);
  Future<void> deactivateSalesRoute(int id);

  // Visits
  Stream<List<RouteVisit>> watchRouteVisits(
    int routeId,
    DateTime fromDate,
    DateTime toDate,
  );
  Future<int> createRouteVisit(RouteVisitsCompanion visit);
  Future<void> updateRouteVisitStatus(
    int id,
    String status, {
    String? notes,
    int? saleId,
    double? orderAmount,
  });

  // Targets
  Stream<List<SalesRepTarget>> watchMonthlyTargets(int year, int month);
  Future<void> setSalesRepTarget({
    required int salesRepId,
    required int year,
    required int month,
    required double targetAmount,
    int targetVisits = 0,
  });

  // Collections
  Stream<List<SalesRepCollection>> watchAllCollections(
    DateTime fromDate,
    DateTime toDate,
  );
  Future<int> createCollection(SalesRepCollectionsCompanion collection);
}

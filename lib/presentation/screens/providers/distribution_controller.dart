import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../domain/repositories/hr_repository_interface.dart';
import '../../../domain/repositories/parties_repository.dart';
import '../../../data/database/database.dart';

class DistributionController {
  final Ref ref;
  DistributionController(this.ref);

  IDistributionRepository get _repo => ref.read(distributionRepositoryProvider);
  IHRRepository get _hrRepo => ref.read(hrRepositoryProvider);
  IPartiesRepository get _partiesRepo => ref.read(partiesRepositoryProvider);

  // Routes
  Stream<List<SalesRoute>> watchSalesRoutes() => _repo.watchSalesRoutes();
  Future<void> updateSalesRoute(int id, SalesRoutesCompanion data) =>
      _repo.updateSalesRoute(id, data);
  Future<void> createSalesRoute(SalesRoutesCompanion data) =>
      _repo.createSalesRoute(data);
  Future<void> deactivateSalesRoute(int id) => _repo.deactivateSalesRoute(id);

  // Visits
  Stream<List<RouteVisit>> watchRouteVisits(
    int routeId,
    DateTime fromDate,
    DateTime toDate,
  ) => _repo.watchRouteVisits(routeId, fromDate, toDate);

  Future<void> createRouteVisit(RouteVisitsCompanion visit) =>
      _repo.createRouteVisit(visit);

  Future<void> updateRouteVisitStatus(
    int id,
    String status, {
    String? notes,
    int? saleId,
    double? orderAmount,
  }) => _repo.updateRouteVisitStatus(
    id,
    status,
    notes: notes,
    saleId: saleId,
    orderAmount: orderAmount,
  );

  // Targets
  Stream<List<SalesRepTarget>> watchMonthlyTargets(int year, int month) =>
      _repo.watchMonthlyTargets(year, month);

  Future<void> setSalesRepTarget({
    required int salesRepId,
    required int year,
    required int month,
    required double targetAmount,
    int targetVisits = 0,
  }) => _repo.setSalesRepTarget(
    salesRepId: salesRepId,
    year: year,
    month: month,
    targetAmount: targetAmount,
    targetVisits: targetVisits,
  );

  // Collections
  Stream<List<SalesRepCollection>> watchAllCollections(
    DateTime fromDate,
    DateTime toDate,
  ) => _repo.watchAllCollections(fromDate, toDate);

  Future<void> createCollection(SalesRepCollectionsCompanion collection) =>
      _repo.createCollection(collection);

  // Helpers
  Future<Employee?> getEmployeeById(int id) => _hrRepo.getEmployeeById(id);
  Future<List<Employee>> getAllEmployees() => _hrRepo.getAllEmployees();

  Future<Party?> getPartyById(int id) => _partiesRepo.getPartyById(id);

  Future<List<Party>> getAllCustomers() => _partiesRepo.getParties(isCustomer: true);
}

final distributionControllerProvider = Provider(
  (ref) => DistributionController(ref),
);

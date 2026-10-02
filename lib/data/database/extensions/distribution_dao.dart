import 'package:drift/drift.dart';
import '../database.dart';
import '../../../domain/models/distribution_model.dart';

/// Extensions for Distribution & Sales Representatives system
extension DistributionExtensions on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // SALES ROUTES
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all active sales routes
  Stream<List<SalesRoute>> watchSalesRoutes() {
    return (select(salesRoutes)
          ..where((r) => r.isActive.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.name)]))
        .watch();
  }

  /// Get all sales routes
  Future<List<SalesRoute>> getAllSalesRoutes() {
    return (select(
      salesRoutes,
    )..orderBy([(r) => OrderingTerm.asc(r.name)])).get();
  }

  /// Create a sales route
  Future<int> createSalesRoute(SalesRoutesCompanion route) {
    return into(salesRoutes).insert(route);
  }

  /// Update sales route
  Future<bool> updateSalesRoute(int id, SalesRoutesCompanion data) {
    return (update(
      salesRoutes,
    )..where((r) => r.id.equals(id))).write(data).then((rows) => rows > 0);
  }

  /// Delete sales route (soft delete)
  Future<bool> deactivateSalesRoute(int id) {
    return (update(salesRoutes)..where((r) => r.id.equals(id)))
        .write(const SalesRoutesCompanion(isActive: Value(false)))
        .then((rows) => rows > 0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ROUTE VISITS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch visits for a specific route and date range
  Stream<List<RouteVisit>> watchRouteVisits(
    int routeId,
    DateTime from,
    DateTime to,
  ) {
    return (select(routeVisits)
          ..where(
            (v) =>
                v.routeId.equals(routeId) &
                v.visitDate.isBiggerOrEqual(Variable(from)) &
                v.visitDate.isSmallerThan(Variable(to)),
          )
          ..orderBy([(v) => OrderingTerm.asc(v.visitDate)]))
        .watch();
  }

  /// Watch visits for a specific sales rep and date range
  Stream<List<RouteVisit>> watchSalesRepVisits(
    int salesRepId,
    DateTime from,
    DateTime to,
  ) {
    return (select(routeVisits)
          ..where(
            (v) =>
                v.salesRepId.equals(salesRepId) &
                v.visitDate.isBiggerOrEqual(Variable(from)) &
                v.visitDate.isSmallerThan(Variable(to)),
          )
          ..orderBy([(v) => OrderingTerm.asc(v.visitDate)]))
        .watch();
  }

  /// Create a route visit
  Future<int> createRouteVisit(RouteVisitsCompanion visit) {
    return into(routeVisits).insert(visit);
  }

  /// Update visit status
  Future<bool> updateRouteVisitStatus(
    int id,
    String status, {
    String? notes,
    int? saleId,
    double? orderAmount,
  }) {
    return (update(routeVisits)..where((v) => v.id.equals(id)))
        .write(
          RouteVisitsCompanion(
            status: Value(status),
            notes: Value(notes),
            saleId: Value(saleId),
            orderAmount: Value(orderAmount ?? 0),
          ),
        )
        .then((rows) => rows > 0);
  }

  /// Get visits count by status for a rep in date range
  Future<Map<String, int>> getVisitStatusCounts(
    int salesRepId,
    DateTime from,
    DateTime to,
  ) async {
    final visits =
        await (select(routeVisits)..where(
              (v) =>
                  v.salesRepId.equals(salesRepId) &
                  v.visitDate.isBiggerOrEqual(Variable(from)) &
                  v.visitDate.isSmallerThan(Variable(to)),
            ))
            .get();

    final counts = <String, int>{
      'planned': 0,
      'completed': 0,
      'cancelled': 0,
      'skipped': 0,
    };
    for (final v in visits) {
      counts[v.status] = (counts[v.status] ?? 0) + 1;
    }
    return counts;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES REP TARGETS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get or create monthly target for a sales rep
  Future<SalesRepTarget> getOrCreateTarget(
    int salesRepId,
    int year,
    int month,
  ) async {
    final existing =
        await (select(salesRepTargets)..where(
              (t) =>
                  t.salesRepId.equals(salesRepId) &
                  t.year.equals(year) &
                  t.month.equals(month),
            ))
            .getSingleOrNull();

    if (existing != null) return existing;

    final id = await into(salesRepTargets).insert(
      SalesRepTargetsCompanion.insert(
        salesRepId: salesRepId,
        year: year,
        month: month,
        targetAmount: 0,
      ),
    );

    return (select(salesRepTargets)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Set sales rep monthly target
  Future<void> setSalesRepTarget({
    required int salesRepId,
    required int year,
    required int month,
    required double targetAmount,
    int targetVisits = 0,
  }) async {
    final target = await getOrCreateTarget(salesRepId, year, month);
    await (update(salesRepTargets)..where((t) => t.id.equals(target.id))).write(
      SalesRepTargetsCompanion(
        targetAmount: Value(targetAmount),
        targetVisits: Value(targetVisits),
      ),
    );
  }

  /// Update achieved amounts
  Future<void> updateTargetAchieved({
    required int salesRepId,
    required int year,
    required int month,
    double? achievedAmount,
    int? achievedVisits,
  }) async {
    final target = await getOrCreateTarget(salesRepId, year, month);
    await (update(salesRepTargets)..where((t) => t.id.equals(target.id))).write(
      SalesRepTargetsCompanion(
        achievedAmount: Value(achievedAmount ?? target.achievedAmount),
        achievedVisits: Value(achievedVisits ?? target.achievedVisits),
      ),
    );
  }

  /// Watch targets for all reps in a month
  Stream<List<SalesRepTarget>> watchMonthlyTargets(int year, int month) {
    return (select(
      salesRepTargets,
    )..where((t) => t.year.equals(year) & t.month.equals(month))).watch();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // COLLECTIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Record a collection. v185 — stamped with the collecting rep and the
  /// customer's current route at creation time.
  Future<int> createCollection(SalesRepCollectionsCompanion collection) async {
    final id = await into(salesRepCollections).insert(collection);
    final customerId =
        collection.customerId.present ? collection.customerId.value : null;
    final resolved = await resolveRepStamp(customerId);
    await stampDocumentRep('sales_rep_collections', id, customerId,
        explicit: RepStamp(
          repEmployeeId: collection.salesRepId.present
              ? collection.salesRepId.value
              : resolved.repEmployeeId,
          routeId: resolved.routeId,
        ));
    return id;
  }

  /// Watch collections for a sales rep in date range
  Stream<List<SalesRepCollection>> watchSalesRepCollections(
    int salesRepId,
    DateTime from,
    DateTime to,
  ) {
    return (select(salesRepCollections)
          ..where(
            (c) =>
                c.salesRepId.equals(salesRepId) &
                c.createdAt.isBiggerOrEqual(Variable(from)) &
                c.createdAt.isSmallerThan(Variable(to)),
          )
          ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
        .watch();
  }

  /// Get total collections for a sales rep in a period
  Future<double> getTotalCollections(
    int salesRepId,
    DateTime from,
    DateTime to,
  ) async {
    final collections =
        await (select(salesRepCollections)..where(
              (c) =>
                  c.salesRepId.equals(salesRepId) &
                  c.createdAt.isBiggerOrEqual(Variable(from)) &
                  c.createdAt.isSmallerThan(Variable(to)),
            ))
            .get();
    return collections.fold<double>(0.0, (sum, c) => sum + c.amount);
  }

  /// Watch all collections in a date range
  Stream<List<SalesRepCollection>> watchAllCollections(
    DateTime from,
    DateTime to,
  ) {
    return (select(salesRepCollections)
          ..where(
            (c) =>
                c.createdAt.isBiggerOrEqual(Variable(from)) &
                c.createdAt.isSmallerThan(Variable(to)),
          )
          ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
        .watch();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELIVERY DAO - Delivery Companies and Couriers Management
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

extension DeliveryDao on AppDatabase {
  // Companies
  Stream<List<DeliveryCompany>> watchDeliveryCompanies() =>
      select(deliveryCompanies).watch();
  Future<List<DeliveryCompany>> getDeliveryCompanies() =>
      select(deliveryCompanies).get();
  Future<int> insertDeliveryCompany(DeliveryCompaniesCompanion company) =>
      into(deliveryCompanies).insert(company);
  Future<bool> updateDeliveryCompany(DeliveryCompany company) =>
      update(deliveryCompanies).replace(company);
  Future<int> deleteDeliveryCompany(int id) =>
      (delete(deliveryCompanies)..where((t) => t.id.equals(id))).go();

  // Couriers
  Stream<List<Courier>> watchCouriers() => select(couriers).watch();
  Future<List<Courier>> getCouriers() => select(couriers).get();
  Future<Courier?> getCourierById(int id) =>
      (select(couriers)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<int> insertCourier(CouriersCompanion courier) =>
      into(couriers).insert(courier);
  Future<bool> updateCourier(Courier courier) =>
      update(couriers).replace(courier);
  Future<int> deleteCourier(int id) =>
      (delete(couriers)..where((t) => t.id.equals(id))).go();

  // Delivery Statistics Report
  Future<List<Map<String, dynamic>>> getDeliveryReport({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    final query = select(salesInvoices).join([
      leftOuterJoin(couriers, couriers.id.equalsExp(salesInvoices.courierId)),
      leftOuterJoin(
        deliveryCompanies,
        deliveryCompanies.id.equalsExp(salesInvoices.deliveryCompanyId),
      ),
    ]);

    if (from != null && to != null) {
      query.where(
        salesInvoices.invoiceDate.isBetween(Variable(from), Variable(to)),
      );
    }

    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where(salesInvoices.warehouseId.isIn(warehouseIds));
    }

    // Spec 151 Track-3: authoritative branch-scope cap. The delivery report
    // filtered by warehouse on the UI only, so a branch-restricted user with
    // no warehouse chosen saw every branch's delivery invoices. Same contract
    // as getSalesByDateRange: null = full access, {} = fail-closed, {ids} =
    // those branches OR NULL-branch (shared/head-office) rows stay visible.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(salesInvoices.branchId.isIn(const <int>[]));
      } else {
        query.where(salesInvoices.branchId.isIn(allowedBranchIds) |
            salesInvoices.branchId.isNull());
      }
    }

    query.where(salesInvoices.deliveryStatus.isNotNull());

    final results = await query.get();
    return results
        .map(
          (row) => {
            'invoice': row.readTable(salesInvoices),
            'courier': row.readTableOrNull(couriers),
            'company': row.readTableOrNull(deliveryCompanies),
          },
        )
        .toList();
  }
}

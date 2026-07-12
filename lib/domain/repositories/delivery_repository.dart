import '../../data/database/database.dart';

abstract class IDeliveryRepository {
  // Companies
  Stream<List<DeliveryCompany>> watchDeliveryCompanies();
  Future<List<DeliveryCompany>> getDeliveryCompanies();
  Future<int> insertDeliveryCompany(DeliveryCompaniesCompanion company);
  Future<bool> updateDeliveryCompany(DeliveryCompany company);
  Future<int> deleteDeliveryCompany(int id);

  // Couriers
  Stream<List<Courier>> watchCouriers();
  Future<List<Courier>> getCouriers();
  Future<Courier?> getCourierById(int id);
  Future<int> insertCourier(CouriersCompanion courier);
  Future<bool> updateCourier(Courier courier);
  Future<int> deleteCourier(int id);

  // Reports
  Future<List<Map<String, dynamic>>> getDeliveryReport({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
  });
}

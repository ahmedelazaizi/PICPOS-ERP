import '../../domain/repositories/delivery_repository.dart';
import '../database/database.dart';

class DriftDeliveryRepository implements IDeliveryRepository {
  final AppDatabase _db;

  DriftDeliveryRepository(this._db);

  @override
  Stream<List<DeliveryCompany>> watchDeliveryCompanies() =>
      _db.watchDeliveryCompanies();

  @override
  Future<List<DeliveryCompany>> getDeliveryCompanies() =>
      _db.getDeliveryCompanies();

  @override
  Future<int> insertDeliveryCompany(DeliveryCompaniesCompanion company) =>
      _db.insertDeliveryCompany(company);

  @override
  Future<bool> updateDeliveryCompany(DeliveryCompany company) =>
      _db.updateDeliveryCompany(company);

  @override
  Future<int> deleteDeliveryCompany(int id) => _db.deleteDeliveryCompany(id);

  @override
  Stream<List<Courier>> watchCouriers() => _db.watchCouriers();

  @override
  Future<List<Courier>> getCouriers() => _db.getCouriers();

  @override
  Future<Courier?> getCourierById(int id) => _db.getCourierById(id);

  @override
  Future<int> insertCourier(CouriersCompanion courier) =>
      _db.insertCourier(courier);

  @override
  Future<bool> updateCourier(Courier courier) => _db.updateCourier(courier);

  @override
  Future<int> deleteCourier(int id) => _db.deleteCourier(id);

  @override
  Future<List<Map<String, dynamic>>> getDeliveryReport({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
  }) =>
      _db.getDeliveryReport(from: from, to: to, warehouseIds: warehouseIds);
}

import '../database/database.dart';
import '../../domain/repositories/printers_repository.dart';

class PrintersRepositoryImpl implements IPrintersRepository {
  final AppDatabase _db;

  PrintersRepositoryImpl(this._db);

  @override
  Stream<List<Printer>> watchPrinters() => _db.watchPrinters();

  @override
  Future<List<Printer>> getPrinters() => _db.getAllPrinters();

  @override
  Future<List<Printer>> getActivePrinters() => _db.getActivePrinters();

  @override
  Future<Printer?> getActivePrinterByPurpose(String purpose) =>
      _db.getActivePrinterByPurpose(purpose);

  @override
  Future<int> insertPrinter({
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
  }) =>
      _db.insertPrinter(
        name: name,
        port: port,
        ipAddress: ipAddress,
        portNumber: portNumber,
        printerType: printerType,
        purpose: purpose,
        description: description,
      );

  @override
  Future<bool> updatePrinter({
    required int id,
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
    bool isActive = true,
  }) =>
      _db.updatePrinter(
        id: id,
        name: name,
        port: port,
        ipAddress: ipAddress,
        portNumber: portNumber,
        printerType: printerType,
        purpose: purpose,
        description: description,
        isActive: isActive,
      );

  @override
  Future<void> deletePrinter(int id) async {
    await _db.deletePrinter(id);
  }
}

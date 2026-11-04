import '../../data/database/database.dart';

abstract class IPrintersRepository {
  Stream<List<Printer>> watchPrinters();
  Future<List<Printer>> getPrinters();
  Future<List<Printer>> getActivePrinters();
  Future<Printer?> getActivePrinterByPurpose(String purpose);
  Future<int> insertPrinter({
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType,
    String purpose,
    String? description,
    double? paperWidthMm,
  });
  Future<bool> updatePrinter({
    required int id,
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType,
    String purpose,
    String? description,
    double? paperWidthMm,
    bool isActive,
  });
  Future<void> deletePrinter(int id);
}

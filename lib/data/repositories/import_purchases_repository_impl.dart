import '../../domain/models/import_purchase_plan.dart';
import '../../domain/repositories/import_purchases_repository.dart';
import '../database/database.dart';

class ImportPurchasesRepositoryImpl implements ImportPurchasesRepository {
  ImportPurchasesRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<ImportPurchaseRow>> getRows({int limit = 500}) =>
      _db.getImportPurchaseRows(limit: limit);

  @override
  Future<ImportPurchaseDetailData?> getForInvoice(int purchaseInvoiceId) =>
      _db.getImportPurchaseDetailsFor(purchaseInvoiceId);

  @override
  Future<void> updateDetails({
    required int purchaseInvoiceId,
    required ImportDocumentFields fields,
  }) =>
      _db.updateImportPurchaseDetails(
        purchaseInvoiceId: purchaseInvoiceId,
        fields: fields,
      );
}

import '../../domain/repositories/treasury_repository.dart';
import '../database/database.dart';
import 'base_repository.dart';

mixin OpenInvoiceReads on BaseRepository<Safe> {
  Future<List<OpenInvoiceSnapshot>> getOpenInvoicesForParty({
    required int partyId,
    required bool forSupplier,
  }) async {
    final rows = await db.getOpenInvoicesForParty(
      partyId: partyId,
      forSupplier: forSupplier,
    );
    return [
      for (final row in rows)
        OpenInvoiceSnapshot(
          invoiceType: row.invoiceType,
          id: row.id,
          number: row.number,
          date: row.date,
          total: row.total,
          paid: row.paid,
        ),
    ];
  }
}

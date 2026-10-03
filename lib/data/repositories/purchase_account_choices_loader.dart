import '../../core/i18n/tr.dart';
import '../../domain/models/picpos_invoice_draft.dart';
import '../../domain/models/picpos_purchase_account_choices.dart';
import '../database/database.dart';

/// J1b — loads the «حساب المشتريات» choices in the data layer (same source
/// as the C2 revenue-account choices: `AppDatabase` reached through
/// `databaseProvider` by the caller). [editingInvoiceId] adds the stored
/// account (an inactive stored account is NOT offered — the JE falls back to
/// the mapping for it).
Future<PicPosPurchaseAccountChoices> loadPurchaseAccountChoices(
  AppDatabase db, {
  int? editingInvoiceId,
}) async {
  final accounts = await db.getActivePurchaseDebitAccounts();
  final defaultAccount = await db.getLeafAccountByPurpose('inventory');
  int? stored;
  if (editingInvoiceId != null) {
    final resolved = await db.resolvePurchaseAccountOverride(editingInvoiceId);
    stored = resolved?.id;
  }
  return PicPosPurchaseAccountChoices(
    options: [
      for (final a in accounts)
        PicPosNamedOption(id: a.id, name: '${a.code} — ${trData(a.name)}'),
    ],
    defaultAccountId: defaultAccount?.id,
    storedAccountId: stored,
  );
}

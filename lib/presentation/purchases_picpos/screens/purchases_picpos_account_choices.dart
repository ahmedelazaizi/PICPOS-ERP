import '../../../core/i18n/tr.dart';
import '../../../data/database/database.dart';
import '../../../domain/models/picpos_invoice_draft.dart';

/// J1b — what the purchase invoice form's «حساب المشتريات» field needs.
class PicPosPurchaseAccountChoices {
  const PicPosPurchaseAccountChoices({
    this.options = const [],
    this.defaultAccountId,
    this.storedAccountId,
  });

  /// Active detail expense/asset accounts, `code — name` (name via [trData]).
  final List<PicPosNamedOption> options;

  /// The mapped account the purchase JE debits today (`'inventory'`).
  final int? defaultAccountId;

  /// The account stored on the invoice being edited (`null` ⇒ default).
  final int? storedAccountId;
}

/// Loads the choices; [editingInvoiceId] adds the stored account (an inactive
/// stored account is NOT offered — the JE falls back to the mapping for it).
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

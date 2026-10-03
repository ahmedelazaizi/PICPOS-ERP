import 'picpos_invoice_draft.dart';

/// J1b — what the purchase invoice form's «حساب المشتريات» field needs.
///
/// Lives in `domain/models` (not presentation) so the data-layer loader
/// (`data/repositories/purchase_account_choices_loader.dart`) can build it
/// without the screen importing `data/database` (D4-001 guard).
class PicPosPurchaseAccountChoices {
  const PicPosPurchaseAccountChoices({
    this.options = const [],
    this.defaultAccountId,
    this.storedAccountId,
  });

  /// Active detail expense/asset accounts, `code — name` (name via `trData`).
  final List<PicPosNamedOption> options;

  /// The mapped account the purchase JE debits today (`'inventory'`).
  final int? defaultAccountId;

  /// The account stored on the invoice being edited (`null` ⇒ default).
  final int? storedAccountId;
}

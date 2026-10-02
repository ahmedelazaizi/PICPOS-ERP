// أفعالُ صفوف سجلّ مردودات المشتريات — J2.
//
// حلّت محلَّ حوار «طباعة أو تعديل مرتجعٍ سابق»: السجلُّ (مكتبةٌ مستقلّة)
// يرث هذه الحالةَ المجرّدة التي تركّب mixin الاستمارة نفسَه
// (`_PurchaseReturnsPicposLogic`) وتكشف معالجاته القائمة باسماءٍ عامّة —
// بلا نسخةٍ ثانية (مصيدةُ النسخ §٥.٥).
part of 'purchase_returns_picpos_screen.dart';

abstract class PurchaseReturnRecordActionsState<
        W extends ConsumerStatefulWidget> extends ConsumerState<W>
    with _PurchaseReturnsPicposLogic<W> {
  /// «طباعة» صفٍّ معتمد — `_reprintHistoricalReturn` القائمُ نفسُه.
  Future<void> reprintPostedReturn(PurchaseInvoiceData invoice) =>
      _reprintHistoricalReturn(invoice);

  /// «عرض الأصناف» — `_showReturnDetails` القائمُ نفسُه.
  Future<void> showPostedReturnItems(PurchaseInvoiceData invoice) =>
      _showReturnDetails(invoice);

  /// «تعديل» مرتجعٍ مرحَّل (ميزة ٠١٥) — `_editPurchaseReturn` القائمُ نفسُه:
  /// عكسٌ ثمّ ترحيلٌ ذرّيّ، والمستندُ القديمُ يُبطَل فيظهر «ملغى» في السجلّ.
  Future<void> editPostedReturn(PurchaseInvoiceData invoice) =>
      _editPurchaseReturn(invoice);
}

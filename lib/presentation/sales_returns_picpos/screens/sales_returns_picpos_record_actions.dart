// أفعالُ صفوف سجلّ مرتجعات المبيعات — J2.
//
// السجلُّ مكتبةٌ مستقلّة (`sales_return_records_picpos_screen.dart`)، و
// معالجاتُ الطباعة والإلغاء خاصّةٌ في mixin الاستمارة (`_SalesReturnsPicposLogic`).
// فبدل نسخِها (مصيدةُ النسخ §٥.٥) يرث السجلُّ هذه الحالةَ المجرّدة التي
// تركّب الـmixin نفسَه وتكشف الفعلين باسمَين عامَّين.
part of 'sales_returns_picpos_screen.dart';

abstract class SalesReturnRecordActionsState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W> with _SalesReturnsPicposLogic<W> {
  /// إعادةُ الطباعة لا تحمل سببَ إرجاعٍ مكتوباً — الحقلُ فارغٌ عمداً.
  final _reprintReason = TextEditingController();

  @override
  TextEditingController get returnReasonController => _reprintReason;

  @override
  void dispose() {
    _reprintReason.dispose();
    super.dispose();
  }

  /// «طباعة» صفٍّ معتمد — `_printReturnReceipt` القائمُ نفسُه.
  Future<void> reprintPostedReturn({
    required String originalInvoiceNumber,
    required double returnTotal,
  }) =>
      _printReturnReceipt(
        invoiceNumber: originalInvoiceNumber,
        returnTotal: returnTotal,
      );

  /// زرُّ «طباعة» الصفّ — نفسُ حارس `sales_return_print` الذي كان في الحوار.
  Widget postedReturnPrintButton({required VoidCallback onPrint}) =>
      buildSalesReturnPrintButtonGuarded(onPrint: onPrint);

  /// زرُّ «إلغاء المرتجع» — نفسُ حارس `sales_return_delete` بتجاوز مدير.
  Widget postedReturnCancelButton({required VoidCallback onCancel}) =>
      buildSalesReturnDeleteButtonGuarded(onCancel: onCancel);

  /// «إلغاء المرتجع» — حوارُ التأكيد ثمّ `cancelSalesReturn` القائمُ نفسُه.
  /// `true` متى أُلغي فعلاً.
  Future<bool> cancelPostedReturn({
    required String originalInvoiceNumber,
    required double returnAmount,
    required SalesInvoiceData invoice,
  }) =>
      _confirmAndCancelReturn(
        context,
        originalInvoiceNumber: originalInvoiceNumber,
        returnAmount: returnAmount,
        invoice: invoice,
      );
}

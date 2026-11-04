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

  /// «طباعة» صفٍّ معتمد.
  ///
  /// [originalInvoiceId] حاضراً ⇒ `printPostedSalesReturn`: البنودُ المرتجعةُ
  /// فعلاً من حركات المخزون. كان `_printReturnReceipt` بلا جلسةٍ يطبع **كلَّ**
  /// بنود الفاتورة (فرعُ «من السجلّ»)، ويبقى سقوطاً حين يغيب المعرّف.
  Future<void> reprintPostedReturn({
    required String originalInvoiceNumber,
    required double returnTotal,
    int? originalInvoiceId,
  }) async {
    if (originalInvoiceId == null) {
      return _printReturnReceipt(
        invoiceNumber: originalInvoiceNumber,
        returnTotal: returnTotal,
      );
    }
    try {
      final outcome = await printPostedSalesReturn(
        db: ref.read(databaseProvider),
        returns: ref.read(returnsRepositoryProvider),
        products: ref.read(productRepositoryProvider),
        originalInvoiceId: originalInvoiceId,
        returnTotal: returnTotal,
        employeeName: ref.read(authProvider).user?.displayName,
      );
      if (!mounted) return;
      final args = {'invoiceNumber': originalInvoiceNumber};
      AppToast.show(
        context,
        switch (outcome) {
          PostedReturnPrintOutcome.printed =>
            tr('تم طباعة إيصال مرتجع فاتورة {invoiceNumber}', args),
          PostedReturnPrintOutcome.cancelled =>
            tr('أُلغيت طباعة إيصال مرتجع فاتورة {invoiceNumber}', args),
          PostedReturnPrintOutcome.noReturnData =>
            tr('لا مرتجعَ مرحَّلاً لهذه الفاتورة'),
        },
        type: outcome == PostedReturnPrintOutcome.printed
            ? ToastType.success
            : ToastType.warning,
      );
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }

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

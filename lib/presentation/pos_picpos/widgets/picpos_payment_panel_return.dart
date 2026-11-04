part of 'picpos_payment_panel.dart';

String _paymentPanelTotal(CartState cart, PosReturnMode? returnMode) =>
    returnMode == null
    ? NumberUtils.formatCurrency(cart.signedTotal)
    : returnMode.refundTotal.toStringAsFixed(2);

String _paymentCheckoutLabel(PosReturnMode? returnMode) => returnMode == null
    ? tr('دفع F4')
    : tr('استرداد {p0}', {'p0': returnMode.refundTotal.toStringAsFixed(2)});

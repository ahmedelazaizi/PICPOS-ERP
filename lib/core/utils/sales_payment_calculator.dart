class PaymentDistribution {
  final double cash;
  final double bank;
  final double click;

  const PaymentDistribution({this.cash = 0, this.bank = 0, this.click = 0});
}

class PaymentDiff {
  final double cashDiff;
  final double bankDiff;
  final double clickDiff;
  final PaymentDistribution newDistribution;

  const PaymentDiff({
    required this.cashDiff,
    required this.bankDiff,
    required this.clickDiff,
    required this.newDistribution,
  });
}

class SalesPaymentCalculator {
  static String getSafeType(String paymentMethod) {
    if (paymentMethod == 'multiple' || paymentMethod == 'mixed') return 'multiple';
    if (paymentMethod == 'click') return 'click';
    if (paymentMethod == 'transfer' || paymentMethod == 'card' || paymentMethod == 'bank') return 'bank';
    return 'cash';
  }

  static PaymentDistribution extractOldDistribution({
    required String paymentMethod,
    required double totalPaid,
    required double cashPaid,
    required double bankPaid,
    required double clickPaid,
  }) {
    final safeType = getSafeType(paymentMethod);
    if (safeType == 'multiple') {
      return PaymentDistribution(cash: cashPaid, bank: bankPaid, click: clickPaid);
    } else if (safeType == 'click') {
      return PaymentDistribution(click: totalPaid);
    } else if (safeType == 'bank') {
      return PaymentDistribution(bank: totalPaid);
    } else {
      return PaymentDistribution(cash: totalPaid);
    }
  }

  /// Calculates new distribution proportionally based on changes to total payment
  static PaymentDiff computeProportionalDiff({
    required String oldPaymentMethod,
    required double oldTotalPaid,
    required double oldCashPaid,
    required double oldBankPaid,
    required double oldClickPaid,
    required String newPaymentMethod,
    required double newTotalPaid,
  }) {
    final oldDist = extractOldDistribution(
      paymentMethod: oldPaymentMethod,
      totalPaid: oldTotalPaid,
      cashPaid: oldCashPaid,
      bankPaid: oldBankPaid,
      clickPaid: oldClickPaid,
    );

    double newCash = 0, newBank = 0, newClick = 0;

    if (getSafeType(newPaymentMethod) == 'multiple') {
      final cashRatio = oldTotalPaid > 0 ? (oldDist.cash / oldTotalPaid) : 0.5;
      final clickRatio = oldTotalPaid > 0 ? (oldDist.click / oldTotalPaid) : 0.0;
      newCash = newTotalPaid * cashRatio;
      newClick = newTotalPaid * clickRatio;
      newBank = newTotalPaid - newCash - newClick;
    } else if (getSafeType(newPaymentMethod) == 'click') {
      newClick = newTotalPaid;
    } else if (getSafeType(newPaymentMethod) == 'bank') {
      newBank = newTotalPaid;
    } else {
      newCash = newTotalPaid;
    }

    final newDist = PaymentDistribution(cash: newCash, bank: newBank, click: newClick);

    return PaymentDiff(
      cashDiff: newCash - oldDist.cash,
      bankDiff: newBank - oldDist.bank,
      clickDiff: newClick - oldDist.click,
      newDistribution: newDist,
    );
  }

  /// Calculates new distribution when only payment methods change
  static PaymentDiff computeMethodChangeDiff({
    required String oldPaymentMethod,
    required double totalPaid,
    required double oldCashPaid,
    required double oldBankPaid,
    required double oldClickPaid,
    required String newPaymentMethod,
    double? explicitlyProvidedNewCash,
    double? explicitlyProvidedNewBank,
  }) {
    final oldDist = extractOldDistribution(
      paymentMethod: oldPaymentMethod,
      totalPaid: totalPaid,
      cashPaid: oldCashPaid,
      bankPaid: oldBankPaid,
      clickPaid: oldClickPaid,
    );
    
    double newCash = 0, newBank = 0, newClick = 0;

    if (getSafeType(newPaymentMethod) == 'multiple') {
      newCash = explicitlyProvidedNewCash ?? 0;
      newBank = explicitlyProvidedNewBank ?? (totalPaid - newCash);
    } else if (getSafeType(newPaymentMethod) == 'click') {
      newClick = totalPaid;
    } else if (getSafeType(newPaymentMethod) == 'cash') {
      newCash = totalPaid;
    } else {
      newBank = totalPaid;
    }

    final newDist = PaymentDistribution(cash: newCash, bank: newBank, click: newClick);

    return PaymentDiff(
      cashDiff: newCash - oldDist.cash,
      bankDiff: newBank - oldDist.bank,
      clickDiff: newClick - oldDist.click,
      newDistribution: newDist,
    );
  }
}

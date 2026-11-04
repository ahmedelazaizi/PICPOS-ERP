/// Signed variance from the channel that governs the reason prompt title.
double quickSaleSignedGoverningShiftDiff({
  required double cash,
  required double bank,
  required double click,
}) {
  if (cash.abs() >= bank.abs() && cash.abs() >= click.abs()) return cash;
  if (bank.abs() >= click.abs()) return bank;
  return click;
}

String quickSaleShiftDiffTitle(double signedDifference) =>
    signedDifference < 0 ? 'عجزٌ في الدرج' : 'فائضٌ في الدرج';

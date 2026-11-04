import '../../../core/utils/financial_utils.dart';

typedef VoucherAllocationGuardRow = ({
  String invoiceType,
  int invoiceId,
  double amount,
});

typedef VoucherInvoiceLoader = Future<List<VoucherInvoiceSnapshot>> Function(
  int partyId,
  bool forSupplier,
);

class VoucherAllocationPreflightRequest {
  const VoucherAllocationPreflightRequest({
    required this.voucherAmount,
    required this.partyId,
    required this.forSupplier,
    required this.allocations,
  });

  final double voucherAmount;
  final int? partyId;
  final bool forSupplier;
  final List<VoucherAllocationGuardRow> allocations;
}

class VoucherInvoiceSnapshot {
  const VoucherInvoiceSnapshot({
    required this.invoiceType,
    required this.id,
    required this.number,
    required this.total,
    required this.paid,
  });

  final String invoiceType;
  final int id;
  final String number;
  final double total;
  final double paid;
}

String voucherAllocationKey(String invoiceType, int invoiceId) =>
    '$invoiceType:$invoiceId';

Future<void> preflightVoucherAllocations(
  VoucherAllocationPreflightRequest request,
  VoucherInvoiceLoader loadInvoices,
) async {
  if (request.allocations.isEmpty) return;
  final partyId = request.partyId;
  if (partyId == null) {
    throw StateError('لا يمكن تخصيص المبلغ دون تحديد الطرف.');
  }
  final invoices = await loadInvoices(partyId, request.forSupplier);
  final invoiceByKey = {
    for (final invoice in invoices)
      voucherAllocationKey(invoice.invoiceType, invoice.id): invoice,
  };
  validateAllocationAmounts(
    amount: request.voucherAmount,
    remainingByInvoice: {
      for (final entry in invoiceByKey.entries)
        entry.key: entry.value.total - entry.value.paid,
    },
    invoiceNumbers: {
      for (final entry in invoiceByKey.entries)
        entry.key: entry.value.number,
    },
    allocations: request.allocations,
  );
}

void validateAllocationAmounts({
  required double amount,
  required Map<String, double> remainingByInvoice,
  Map<String, String> invoiceNumbers = const {},
  required List<VoucherAllocationGuardRow> allocations,
}) {
  final grouped = _groupAllocationsByInvoice(allocations);
  _validateVoucherAllocationTotal(amount, grouped);
  _validateInvoiceRemainders(grouped, remainingByInvoice, invoiceNumbers);
}

Map<String, double> _groupAllocationsByInvoice(
  List<VoucherAllocationGuardRow> allocations,
) {
  final grouped = <String, double>{};
  for (final allocation in allocations) {
    if (allocation.amount <= 0) {
      throw ArgumentError(
        'مبلغُ التخصيص للفاتورة #${allocation.invoiceId} يجب أن يكون أكبر من صفر.',
      );
    }
    final key = voucherAllocationKey(allocation.invoiceType, allocation.invoiceId);
    grouped.update(key, (priorAmount) => priorAmount + allocation.amount,
        ifAbsent: () => allocation.amount);
  }
  return grouped;
}

void _validateVoucherAllocationTotal(
  double amount,
  Map<String, double> grouped,
) {
  final allocatedMinor = grouped.values.fold<int>(
    0,
    (sum, allocationAmount) =>
        sum + FinancialUtils.toMinorUnits(allocationAmount),
  );
  if (allocatedMinor > FinancialUtils.toMinorUnits(amount)) {
    throw StateError('مجموعُ التوزيع يتجاوز مبلغَ السند — وزّع ما لا يزيد عليه.');
  }
}

void _validateInvoiceRemainders(
  Map<String, double> grouped,
  Map<String, double> remainingByInvoice,
  Map<String, String> invoiceNumbers,
) {
  for (final entry in grouped.entries) {
    final remaining = remainingByInvoice[entry.key];
    if (remaining == null) {
      throw StateError('الفاتورة ${entry.key} غير موجودة أو لا تقبل التخصيص.');
    }
    if (FinancialUtils.toMinorUnits(entry.value) >
        FinancialUtils.toMinorUnits(remaining)) {
      final number = invoiceNumbers[entry.key] ?? entry.key.split(':').last;
      throw StateError(
        'التخصيصُ يتجاوز باقيَ الفاتورة $number '
        '(الباقي ${remaining.toStringAsFixed(2)}).',
      );
    }
  }
}

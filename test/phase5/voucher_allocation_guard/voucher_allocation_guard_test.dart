import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/treasury_picpos/screens/voucher_allocation_guard.dart';

void main() {
  VoucherAllocationGuardRow allocation(double amount) =>
      (invoiceType: 'sales', invoiceId: 1, amount: amount);

  test('rejects 250 against remaining 13.98', () => expect(
        () => validateAllocationAmounts(
          amount: 250,
          remainingByInvoice: {'sales:1': 13.98},
          allocations: [allocation(250)],
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('التخصيصُ يتجاوز باقيَ الفاتورة'),
        )),
      ));

  test('rejects zero and negative allocations', () {
    for (final invalidAmount in [0.0, -1.0]) {
      expect(
        () => validateAllocationAmounts(
          amount: 5,
          remainingByInvoice: {'sales:1': 13.98},
          allocations: [allocation(invalidAmount)],
        ),
        throwsArgumentError,
      );
    }
  });

  test('permits a valid allocation and exact remaining balance', () {
    validateAllocationAmounts(
      amount: 5,
      remainingByInvoice: {'sales:1': 13.98},
      allocations: [allocation(5)],
    );
    validateAllocationAmounts(
      amount: 13.98,
      remainingByInvoice: {'sales:1': 13.98},
      allocations: [allocation(13.98)],
    );
  });

  test('groups duplicate invoice allocations before comparing balance', () => expect(
        () => validateAllocationAmounts(
          amount: 20,
          remainingByInvoice: {'sales:1': 13.98},
          allocations: [allocation(7), allocation(7)],
        ),
        throwsStateError,
      ));

  test('rejects an invoice missing from the open-invoice query (including returns)', () async {
    await expectLater(
      preflightVoucherAllocations(
        VoucherAllocationPreflightRequest(
          voucherAmount: 5,
          partyId: 10,
          forSupplier: false,
          allocations: [allocation(5)],
        ),
        (partyId, forSupplier) async => const [],
      ),
      throwsStateError,
    );
  });

  test('rejects aggregate allocations above voucher amount', () => expect(
        () => validateAllocationAmounts(
          amount: 5,
          remainingByInvoice: {'sales:1': 20, 'sales:2': 20},
          allocations: [
            allocation(3),
            (invoiceType: 'sales', invoiceId: 2, amount: 3),
          ],
        ),
        throwsStateError,
      ));
}

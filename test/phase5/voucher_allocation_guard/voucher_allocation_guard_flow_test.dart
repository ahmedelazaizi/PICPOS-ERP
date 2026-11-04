import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/usecases/treasury/create_voucher_usecase.dart';
import 'package:picpos_erp/presentation/treasury_picpos/screens/voucher_allocation_guard.dart';

import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;
  late int product;
  late int customer;

  setUp(() async {
    world = await ScenarioWorld.create();
    await world.grant(PermissionCodes.treasuryReceiptsCreate);
    product = await world.addProduct('allocation-flow', price: 13.98, cost: 5, stock: 4);
    customer = await world.addCustomer('عميل تخصيص');
  });
  tearDown(() => world.dispose());

  test('preflight reject occurs before voucher, journal, safe, or payment writes', () async {
    await world.sell([world.line(product, 1, 13.98)], customerId: customer, method: 'credit');
    final invoice = (await world.db.getOpenInvoicesForParty(partyId: customer, forSupplier: false)).single;
    Future<List<VoucherInvoiceSnapshot>> loadInvoices(int id, bool supplier) async => [
      for (final row in await world.db.getOpenInvoicesForParty(partyId: id, forSupplier: supplier))
        VoucherInvoiceSnapshot(invoiceType: row.invoiceType, id: row.id, number: row.number, total: row.total, paid: row.paid),
    ];
    Future<int> count(String table) async => (await world.db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).data['n'] as int;
    final before = [for (final table in ['journal_entries', 'safe_transactions', 'payments']) await count(table)];
    final balanceBefore = await world.partyBalance(customer);

    Future<void> save(double amount) async {
      await preflightVoucherAllocations(
        VoucherAllocationPreflightRequest(
          voucherAmount: amount,
          partyId: customer,
          forSupplier: false,
          allocations: [
            (invoiceType: 'sales', invoiceId: invoice.id, amount: amount),
          ],
        ),
        loadInvoices,
      );
      final repo = world.container.read(treasuryRepositoryProvider);
      final voucherId = await CreateVoucherUseCase(repo).createReceipt(
        amount: amount, category: 'customer_payment', safeId: world.cashSafeId,
        partyId: customer, userId: world.userId,
      );
      await world.db.recordVoucherAllocations(
        paymentNumber: 'PHASE5-$amount', paymentDate: DateTime.now(), amount: amount,
        paymentMethod: 'cash', safeId: world.cashSafeId, paymentType: 'receipt',
        partyId: customer,
        allocations: [(invoiceType: 'sales', invoiceId: invoice.id, amount: amount)],
      );
      expect(voucherId, greaterThan(0));
    }

    await expectLater(save(250), throwsA(isA<StateError>()));
    final afterRejected = [for (final table in ['journal_entries', 'safe_transactions', 'payments']) await count(table)];
    expect(afterRejected, before);
    expect(await world.partyBalance(customer), balanceBefore);

    await save(5);
    expect(await world.db.getOpenInvoicesForParty(partyId: customer, forSupplier: false), hasLength(1));
    expect((await world.db.getOpenInvoicesForParty(partyId: customer, forSupplier: false)).single.paid, 5);
    expect(await world.partyBalance(customer), closeTo(balanceBefore - 5, kEps));
    expect(await world.safeBalance(), closeTo(5, kEps));
    expect(await world.unbalancedEntries(), isEmpty);
  }, tags: ['pg']);
}

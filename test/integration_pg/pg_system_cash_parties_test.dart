@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.select(fx.db.accounts).get();
  });

  tearDownAll(() async => fx.tearDown());

  test(
    'startup seeds distinct cash roles under the correct parent accounts',
    () async {
      final customerId = await fx.db.systemPartyId(kSystemRoleCashCustomer);
      final supplierId = await fx.db.systemPartyId(kSystemRoleCashSupplier);

      expect(customerId, isNotNull);
      expect(supplierId, isNotNull);
      expect(customerId, isNot(supplierId));

      final customer = await (fx.db.select(
        fx.db.parties,
      )..where((party) => party.id.equals(customerId!))).getSingle();
      final supplier = await (fx.db.select(
        fx.db.parties,
      )..where((party) => party.id.equals(supplierId!))).getSingle();

      expect(customer.isCustomer, isTrue);
      expect(customer.isSupplier, isFalse);
      expect(supplier.isCustomer, isFalse);
      expect(supplier.isSupplier, isTrue);
      expect(await fx.db.systemPartyRoles(), {
        customerId: kSystemRoleCashCustomer,
        supplierId: kSystemRoleCashSupplier,
      });

      final customerAccount =
          await (fx.db.select(fx.db.accounts)
                ..where((account) => account.id.equals(customer.accountId!)))
              .getSingle();
      final customerParent =
          await (fx.db.select(fx.db.accounts)..where(
                (account) => account.id.equals(customerAccount.parentId!),
              ))
              .getSingle();
      final supplierAccount =
          await (fx.db.select(fx.db.accounts)
                ..where((account) => account.id.equals(supplier.accountId!)))
              .getSingle();
      final supplierParent =
          await (fx.db.select(fx.db.accounts)..where(
                (account) => account.id.equals(supplierAccount.parentId!),
              ))
              .getSingle();

      expect(customerParent.code, '1121');
      expect(supplierParent.code, '2111');

      final partyCount = (await fx.db.select(fx.db.parties).get()).length;
      await fx.db.ensureSystemCashParties();
      expect((await fx.db.select(fx.db.parties).get()).length, partyCount);
      expect(await fx.db.systemPartyId(kSystemRoleCashCustomer), customerId);
      expect(await fx.db.systemPartyId(kSystemRoleCashSupplier), supplierId);
    },
  );
}

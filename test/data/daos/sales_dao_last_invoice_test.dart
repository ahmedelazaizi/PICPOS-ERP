import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';

/// Covers `watchLastInvoiceForUser` (the POS "آخر فاتورة" affordance) and the
/// return-exclusion fix on `watchTodaySalesForUser`.
void main() {
  late AppDatabase db;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'Test Warehouse'),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير النظام',
            isSystemRole: const Value(true),
          ),
        );
    await db.createUser(
      username: 'cashier1',
      password: 'test123',
      displayName: 'Cashier One',
      roleId: roleId,
    );
    await db.createUser(
      username: 'cashier2',
      password: 'test123',
      displayName: 'Cashier Two',
      roleId: roleId,
    );

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'P01',
        name: 'Product',
        salePrice: const Value(10.0),
        trackInventory: const Value(false),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<int> makeInvoice({
    required String number,
    required int userId,
    String saleType = 'default',
    DateTime? date,
    double total = 10.0,
  }) {
    return db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: 1,
      userId: userId,
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      paid: total,
      paymentMethod: 'cash',
      saleType: saleType,
      invoiceDate: date,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1.0,
          unitPrice: total,
          total: total,
        ),
      ],
    );
  }

  group('watchLastInvoiceForUser', () {
    test('emits null when the user has sold nothing', () async {
      expect(await db.watchLastInvoiceForUser(1).first, isNull);
    });

    test('returns only the requesting user\'s own invoice', () async {
      await makeInvoice(number: 'POS-1', userId: 1);
      // Another till / another user syncs a NEWER invoice in. Cashier 1 must
      // still see their own — this is the whole point of the user scope.
      await makeInvoice(number: 'POS-2', userId: 2);

      final forUser1 = await db.watchLastInvoiceForUser(1).first;
      final forUser2 = await db.watchLastInvoiceForUser(2).first;

      expect(forUser1?.invoiceNumber, 'POS-1');
      expect(forUser2?.invoiceNumber, 'POS-2');
    });

    test('excludes return invoices', () async {
      await makeInvoice(number: 'POS-1', userId: 1);
      await makeInvoice(number: 'SRET-1', userId: 1, saleType: 'return');

      final last = await db.watchLastInvoiceForUser(1).first;
      expect(last?.invoiceNumber, 'POS-1',
          reason: 'a sales return is not "the last invoice I sold"');
    });

    test('honours the `since` lower bound (open-shift window)', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await makeInvoice(number: 'POS-OLD', userId: 1, date: yesterday);

      final shiftStart = DateTime.now().subtract(const Duration(hours: 1));
      expect(await db.watchLastInvoiceForUser(1, since: shiftStart).first,
          isNull);
      // Without the bound the same row is visible, proving the filter did it.
      expect((await db.watchLastInvoiceForUser(1).first)?.invoiceNumber,
          'POS-OLD');
    });

    test('breaks same-timestamp ties by id, not at random', () async {
      // Two sales in the same second is routine on a busy till, and
      // invoiceDate alone is not a total order.
      final sameInstant = DateTime.now();
      await makeInvoice(number: 'POS-1', userId: 1, date: sameInstant);
      await makeInvoice(number: 'POS-2', userId: 1, date: sameInstant);

      final last = await db.watchLastInvoiceForUser(1).first;
      expect(last?.invoiceNumber, 'POS-2',
          reason: 'the higher id is the later sale');
    });

    test('excludes soft-deleted invoices', () async {
      await makeInvoice(number: 'POS-1', userId: 1);
      final id2 = await makeInvoice(number: 'POS-2', userId: 1);
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(id2)))
          .write(const SalesInvoicesCompanion(isDeleted: Value(true)));

      final last = await db.watchLastInvoiceForUser(1).first;
      expect(last?.invoiceNumber, 'POS-1');
    });
  });

  group('watchTodaySalesForUser', () {
    test('excludes returns, matching its three sibling streams', () async {
      await makeInvoice(number: 'POS-1', userId: 1);
      await makeInvoice(number: 'SRET-1', userId: 1, saleType: 'return');

      final rows = await db.watchTodaySalesForUser(1).first;

      expect(rows.map((r) => r.invoiceNumber), ['POS-1'],
          reason: 'a cashier with no open shift falls back to this stream, and '
              'the previous-invoices footer sums whatever it yields — a return '
              'in there overstates sales');
    });

    test('still returns the user\'s own non-return sales', () async {
      await makeInvoice(number: 'POS-1', userId: 1);
      await makeInvoice(number: 'POS-2', userId: 1);
      await makeInvoice(number: 'POS-3', userId: 2);

      final rows = await db.watchTodaySalesForUser(1).first;
      expect(rows.length, 2);
      expect(rows.every((r) => r.userId == 1), isTrue);
    });
  });
}

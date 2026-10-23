import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    final roleId = await database.into(database.roles).insert(
      RolesCompanion.insert(name: 'Admin', isSystemRole: const Value(true)),
    );
    await database.createUser(
      username: 'testuser',
      password: 'test123',
      displayName: 'Test User',
      roleId: roleId,
    );
    await database.into(database.warehouses).insert(
      WarehousesCompanion.insert(name: 'Main WH'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('PartyDao - CRUD', () {
    test('insert customer party', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'عميل اختبار',
          isCustomer: const Value(true),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.name, 'عميل اختبار');
      expect(party.isCustomer, true);
      expect(party.isSupplier, false);
    });

    test('insert supplier party', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'مورد اختبار',
          isSupplier: const Value(true),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.isSupplier, true);
    });

    test('fixedDiscount should persist', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Premium Client',
          isCustomer: const Value(true),
          fixedDiscount: const Value(15.0),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.fixedDiscount, 15.0);
    });

    test('creditLimit should persist', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Credit Client',
          isCustomer: const Value(true),
          creditLimit: const Value(10000.0),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.creditLimit, 10000.0);
    });

    test('balance defaults to zero', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Zero Balance'),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.balance, 0.0);
    });

    test('update party name', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Old Name'),
      );

      await (database.update(database.parties)
            ..where((p) => p.id.equals(id)))
          .write(const PartiesCompanion(name: Value('New Name')));

      final updated = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(updated.name, 'New Name');
    });

    test('delete party', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'To Delete'),
      );

      await (database.delete(database.parties)
            ..where((p) => p.id.equals(id)))
          .go();

      final result = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingleOrNull();
      expect(result, isNull);
    });
  });

  group('PartyDao - Dual Role', () {
    test('party can be both customer and supplier', () async {
      final id = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Dual Entity',
          isCustomer: const Value(true),
          isSupplier: const Value(true),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(party.isCustomer, true);
      expect(party.isSupplier, true);
    });
  });

  group('PartyDao - Search', () {
    test('search by name', () async {
      await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'أحمد محمد'),
      );
      await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'خالد سعيد'),
      );

      final results = await (database.select(database.parties)
            ..where((p) => p.name.like('%أحمد%')))
          .get();
      expect(results, hasLength(1));
      expect(results.first.name, 'أحمد محمد');
    });
  });
}

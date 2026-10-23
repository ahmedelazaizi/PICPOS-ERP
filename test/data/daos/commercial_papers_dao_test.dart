// ignore_for_file: avoid_dynamic_calls
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
      WarehousesCompanion.insert(name: 'Main Warehouse'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('CommercialPapersDao - CRUD', () {
    test('insert and retrieve a cheque', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Test Supplier',
          isSupplier: const Value(true),
        ),
      );

      final id = await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'CHQ-001',
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: 5000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 6, 1),
        ),
      );

      expect(id, isPositive);

      final paper = await database.getCommercialPaper(id);
      expect(paper, isNotNull);
      expect(paper!.paperNumber, 'CHQ-001');
      expect(paper.amount, 5000.0);
      expect(paper.direction, 'received');
    });

    test('update status via write', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Status Supplier'),
      );

      final id = await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'CHQ-002',
          type: 'cheque',
          direction: 'issued',
          partyId: partyId,
          amount: 3000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 5, 1),
        ),
      );

      await (database.update(database.commercialPapers)
            ..where((t) => t.id.equals(id)))
          .write(const CommercialPapersCompanion(status: Value('collected')));

      final updated = await database.getCommercialPaper(id);
      expect(updated!.status, 'collected');
    });

    test('filter by direction - received vs issued', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Dir Party'),
      );

      await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'CHQ-R1',
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: 1000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 4, 1),
        ),
      );
      await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'CHQ-I1',
          type: 'cheque',
          direction: 'issued',
          partyId: partyId,
          amount: 2000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 4, 1),
        ),
      );

      final received = await (database.select(database.commercialPapers)
            ..where((t) => t.direction.equals('received')))
          .get();
      final issued = await (database.select(database.commercialPapers)
            ..where((t) => t.direction.equals('issued')))
          .get();

      expect(received, hasLength(1));
      expect(issued, hasLength(1));
      expect(received.first.paperNumber, 'CHQ-R1');
      expect(issued.first.paperNumber, 'CHQ-I1');
    });
  });

  group('CommercialPapersDao - Status History', () {
    test('getPaperHistory returns recorded changes', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Hist Party'),
      );

      final paperId = await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'CHQ-HIST',
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: 4000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 6, 1),
        ),
      );

      // Record a status change via the history table
      await database.into(database.paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: 'pending',
          toStatus: 'deposited',
          changedBy: 1,
        ),
      );

      final history = await database.getPaperHistory(paperId);
      expect(history, hasLength(1));
      expect(history.first.fromStatus, 'pending');
      expect(history.first.toStatus, 'deposited');
    });
  });

  group('CommercialPapersDao - Summary', () {
    test('getCommercialPapersSummary returns correct totals', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Summary Party'),
      );

      // Insert received pending
      await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'SUM-R1',
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: 1000.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 4, 1),
          status: const Value('pending'),
        ),
      );
      // Insert issued pending
      await database.into(database.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: 'SUM-I1',
          type: 'cheque',
          direction: 'issued',
          partyId: partyId,
          amount: 500.0,
          issueDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 5, 1),
          status: const Value('pending'),
        ),
      );

      final summary = await database.getCommercialPapersSummary();
      expect(summary['received']!['pending'], 1000.0);
      expect(summary['issued']!['pending'], 500.0);
    });
  });
}
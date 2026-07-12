// SPEC 101 — Purchase Excel paid value + cheque rows in party statement

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Spec 101 — purchase Excel import paid handling', () {
    test('Excel import distinguishes explicit zero from omitted paid cell', () {
      final src = File('lib/data/services/excel_service.dart').readAsStringSync();

      expect(src, contains('paidProvided: paidCellValue != null'),
          reason: 'Import must preserve whether the paid cell was actually '
              'provided. Parsing alone turns blank and explicit 0 into 0.');
      // fix(110) refactored the single-expression guard into an if/else-if
      // chain: an explicit positive paid wins; otherwise cash → fully paid,
      // credit → fully unpaid (an explicit 0 stays unpaid). Pin the chain.
      expect(src, contains('if (firstRow.paidProvided && firstRow.paid > 0)'),
          reason: 'An explicit positive paid value must be honoured verbatim '
              '(capped at total), regardless of method label.');
      expect(src, contains("} else if (paymentMethod == 'cash') {"),
          reason: 'Cash imports may default to full payment only when the '
              'paid cell is omitted, not when the user explicitly enters 0.');
    });
  });

  group('Spec 101 — commercial papers in party statement', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await _seedUser(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('issued cheque appears as supplier statement debit', () async {
      final supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'مورد شيكات',
              isSupplier: const Value(true),
              // Parties.isCustomer defaults true; a dual-role party gets the
              // customer sign in getPartyStatement. Pin this as a pure
              // supplier so the issued-cheque debit reduces the AP balance.
              isCustomer: const Value(false),
            ),
          );

      final paperId = await db.into(db.commercialPapers).insert(
            CommercialPapersCompanion.insert(
              paperNumber: 'CHK-SUP-1',
              type: 'cheque',
              direction: 'issued',
              partyId: supplierId,
              amount: 250.0,
              issueDate: DateTime(2026, 5, 1),
              dueDate: DateTime(2026, 5, 30),
              createdAt: Value(DateTime(2026, 5, 2, 10)),
            ),
          );

      final entries = await db.getPartyStatement(
        supplierId,
        fromDate: DateTime(2026, 5, 1),
        toDate: DateTime(2026, 5, 31),
      );
      final cheque = entries.singleWhere(
        (e) => e.referenceType == 'commercial_paper' && e.referenceId == paperId,
      );

      expect(cheque.description, contains('إصدار شيك'));
      expect(cheque.invoiceNumber, 'CHK-SUP-1');
      expect(cheque.debit, 250.0);
      expect(cheque.credit, 0.0);
      expect(cheque.balance, -250.0,
          reason: 'For suppliers, debit rows reduce the AP running balance.');
    });

    test('bounced issued cheque restores supplier statement balance', () async {
      final supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'مورد مرتجع',
              isSupplier: const Value(true),
              // Pure supplier — see the 'مورد شيكات' insert above.
              isCustomer: const Value(false),
            ),
          );

      final paperId = await db.into(db.commercialPapers).insert(
            CommercialPapersCompanion.insert(
              paperNumber: 'CHK-SUP-2',
              type: 'cheque',
              direction: 'issued',
              partyId: supplierId,
              amount: 100.0,
              issueDate: DateTime(2026, 5, 1),
              dueDate: DateTime(2026, 5, 30),
              createdAt: Value(DateTime(2026, 5, 2, 10)),
            ),
          );
      await db.into(db.paperStatusHistory).insert(
            PaperStatusHistoryCompanion.insert(
              paperId: paperId,
              fromStatus: 'pending',
              toStatus: 'bounced',
              changedBy: 1,
              changedAt: Value(DateTime(2026, 5, 3, 10)),
            ),
          );

      final entries = await db.getPartyStatement(
        supplierId,
        fromDate: DateTime(2026, 5, 1),
        toDate: DateTime(2026, 5, 31),
      );
      final chequeRows = entries
          .where((e) => e.referenceType == 'commercial_paper' && e.referenceId == paperId)
          .toList();

      expect(chequeRows, hasLength(2));
      expect(chequeRows.first.debit, 100.0);
      expect(chequeRows.first.credit, 0.0);
      expect(chequeRows.last.debit, 0.0);
      expect(chequeRows.last.credit, 100.0);
      expect(chequeRows.last.balance, 0.0,
          reason: 'The bounced issued cheque restores the supplier AP balance.');
    });
  });
}

Future<void> _seedUser(AppDatabase db) async {
  final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'Admin', isSystemRole: const Value(true)),
      );
  await db.createUser(
    username: 'spec101',
    password: 'test123',
    displayName: 'Spec 101',
    roleId: roleId,
  );
}

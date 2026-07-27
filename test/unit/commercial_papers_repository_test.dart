// ═══════════════════════════════════════════════════════════════════════════
// COMMERCIAL PAPERS REPOSITORY — Unit Tests (PIR Phase 8)
//
// Tests the ICommercialPapersRepository contract against in-memory DB.
// Covers: CRUD, status lifecycle, partial collection, reissue, endorse,
//         renew, history audit trail.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/commercial_papers_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CommercialPapersRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = CommercialPapersRepositoryImpl(db);
    // paper_status_history.changed_by FKs to users. Calls that omit changedBy
    // resolve to the repo's `?? 0` fallback; seed that placeholder actor so the
    // FK resolves (the DAO's _ensureValidActor guard rejects an unseeded actor).
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(0), username: 'usr0', passwordHash: 'x', displayName: 'U0'));
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper: seed a party for FK constraint
  Future<int> seedParty(String name) async {
    return db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: name,
            isCustomer: const Value(true),
            isSupplier: const Value(false),
          ),
        );
  }

  /// Helper: create a paper via the repo
  Future<int> createTestPaper(int partyId, {
    String direction = 'received',
    double amount = 5000.0,
    String paperNumber = 'CHK-001',
  }) async {
    return repo.createPaper(
      paperNumber: paperNumber,
      type: 'cheque',
      direction: direction,
      partyId: partyId,
      amount: amount,
      issueDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 3, 1),
      bankName: 'بنك القاهرة',
    );
  }

  group('Commercial Papers — Create & Read', () {
    test('createPaper inserts a record and returns valid ID', () async {
      final partyId = await seedParty('عميل تجريبي');
      final paperId = await createTestPaper(partyId);

      expect(paperId, greaterThan(0));

      final paper = await repo.getPaperById(paperId);
      expect(paper, isNotNull);
      expect(paper!.paperNumber, 'CHK-001');
      expect(paper.amount, 5000.0);
      expect(paper.direction, 'received');
      expect(paper.status, 'pending'); // Default status
      expect(paper.bankName, 'بنك القاهرة');
    });

    test('getCommercialPapers filters by direction', () async {
      final partyId = await seedParty('عميل');
      await createTestPaper(partyId, direction: 'received', paperNumber: 'R-001');
      await createTestPaper(partyId, direction: 'issued', paperNumber: 'I-001');

      final received = await repo.getCommercialPapers(direction: 'received');
      final issued = await repo.getCommercialPapers(direction: 'issued');

      expect(received.length, 1);
      expect(received.first.paperNumber, 'R-001');
      expect(issued.length, 1);
      expect(issued.first.paperNumber, 'I-001');
    });

    test('getCommercialPapers filters by status', () async {
      final partyId = await seedParty('عميل');
      final id1 = await createTestPaper(partyId, paperNumber: 'S-001');
      await createTestPaper(partyId, paperNumber: 'S-002');

      // Change one to cashed
      await repo.updatePaperStatus(id1, 'cashed');

      final pending = await repo.getCommercialPapers(status: 'pending');
      final cashed = await repo.getCommercialPapers(status: 'cashed');

      expect(pending.length, 1);
      expect(cashed.length, 1);
      expect(cashed.first.paperNumber, 'S-001');
    });
  });

  group('Commercial Papers — Status Lifecycle', () {
    test('updatePaperStatus changes status correctly', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId);

      final result = await repo.updatePaperStatus(paperId, 'in_portfolio');
      expect(result, isTrue);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.status, 'in_portfolio');
    });

    test('updatePaperStatus records history', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId);

      await repo.updatePaperStatus(paperId, 'deposited', changedBy: 0);

      final history = await repo.getPaperHistory(paperId);
      expect(history.length, greaterThanOrEqualTo(1));
      expect(history.first.fromStatus, 'pending');
      expect(history.first.toStatus, 'deposited');
    });

    test('full lifecycle: pending → portfolio → deposited → cashed', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId);

      await repo.updatePaperStatus(paperId, 'in_portfolio');
      await repo.updatePaperStatus(paperId, 'deposited');
      await repo.updatePaperStatus(paperId, 'cashed');

      final paper = await repo.getPaperById(paperId);
      expect(paper!.status, 'cashed');

      final history = await repo.getPaperHistory(paperId);
      expect(history.length, greaterThanOrEqualTo(3));
    });
  });

  group('Commercial Papers — Advanced Operations', () {
    test('endorsePaper marks paper as endorsed', () async {
      final partyId = await seedParty('العميل الأصلي');
      final endorsedPartyId = await seedParty('الطرف المظهر إليه');
      final paperId = await createTestPaper(partyId);

      await repo.endorsePaper(paperId, endorsedPartyId, changedBy: 1);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.status, 'endorsed');
    });

    test('renewPaper extends due date without changing status', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId);

      final newDate = DateTime(2026, 6, 1);
      await repo.renewPaper(paperId, newDate, changedBy: 1);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.dueDate, newDate);
      expect(paper.status, 'pending'); // Status unchanged
    });

    test('reissuePaper marks paper as endorsed to new party', () async {
      final partyId = await seedParty('الطرف الأول');
      final newPartyId = await seedParty('الطرف الجديد');
      final paperId = await createTestPaper(partyId);

      await repo.reissuePaper(paperId, newPartyId, changedBy: 1);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.status, 'endorsed');
      expect(paper.endorsedToPartyId, newPartyId);
    });

    test('depositForCollection links paper to bank safe', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId);

      // Seed a bank safe
      final bankId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'البنك الأهلي',
              safeType: const Value('bank'),
            ),
          );

      await repo.depositForCollection(paperId, bankId, changedBy: 1);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.status, 'deposited_for_collection');
    });
  });

  group('Commercial Papers — Partial Collection', () {
    test('partialCollection reduces paper amount', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId, amount: 10000);

      await repo.partialCollection(paperId, 3000, changedBy: 1);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.amount, 7000.0); // 10000 - 3000
    });

    test('partialCollection records history entry', () async {
      final partyId = await seedParty('عميل');
      final paperId = await createTestPaper(partyId, amount: 10000);

      await repo.partialCollection(paperId, 4000, changedBy: 1, notes: 'دفعة أولى');

      final history = await repo.getPaperHistory(paperId);
      expect(history.length, greaterThanOrEqualTo(1));
      expect(history.first.toStatus, 'partial_collected');
    });
  });

  group('Commercial Papers — Summary', () {
    test('getPapersSummary returns correct totals by direction', () async {
      final partyId = await seedParty('عميل');
      await createTestPaper(partyId, direction: 'received', amount: 5000, paperNumber: 'R-001');
      await createTestPaper(partyId, direction: 'received', amount: 3000, paperNumber: 'R-002');
      await createTestPaper(partyId, direction: 'issued', amount: 2000, paperNumber: 'I-001');

      final summary = await repo.getPapersSummary(direction: 'received');
      expect(summary['total'], greaterThanOrEqualTo(8000));
      expect(summary['pending'], greaterThanOrEqualTo(8000));
    });
  });
}

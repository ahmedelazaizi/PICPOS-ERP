// Field 2026-07-21 — in-app maintenance action that re-attributes historical
// auto-posted journal entries stuck on the global «عام» (GEN) centre back to
// their branch's own cost center. Mirrors scripts/repair_branch_cost_centers.sql.
//
// The pre-fix state is simulated by posting a normal (now-correct) branch JE and
// then forcing it back onto «عام», exactly how legacy data looks on the server.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  Future<int> makeCc(String code, String name) => db.into(db.costCenters).insert(
        CostCentersCompanion.insert(code: code, name: name),
      );

  Future<int> postSaleJe({required int branchId}) async {
    final revenue = await (db.select(db.accounts)
          ..where((a) => a.code.equals('4121')))
        .getSingle();
    final cash = await (db.select(db.accounts)
          ..where((a) => a.code.equals('1111')))
        .getSingle();
    return db.createJournalEntry(
      description: 'اختبار إصلاح مركز التكلفة',
      date: DateTime(2026, 7, 1),
      referenceType: 'sale',
      isAutoPosted: true,
      branchId: branchId,
      lines: [
        JournalLine(accountId: cash.id, debit: 100),
        JournalLine(accountId: revenue.id, credit: 100),
      ],
    );
  }

  // Post a correct branch JE, then force it onto «عام» to mimic legacy data.
  Future<(int jeId, int branchCc, int genCc)> seedStuckOnGen() async {
    final branchCc = await makeCc('BR1', 'مركز الفرع أ');
    final genCc = await makeCc('GEN', 'عام');
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع أ',
            costCenterId: Value(branchCc),
          ),
        );
    final jeId = await postSaleJe(branchId: branchId);
    await (db.update(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .write(JournalEntriesCompanion(costCenterId: Value(genCc)));
    await (db.update(db.journalEntryLines)..where((l) => l.entryId.equals(jeId)))
        .write(JournalEntryLinesCompanion(costCenterId: Value(genCc)));
    return (jeId, branchCc, genCc);
  }

  test('dry-run previews the move and writes nothing', () async {
    final (jeId, _, genCc) = await seedStuckOnGen();

    final preview = await db.repairBranchCostCenterAttribution(dryRun: true);

    expect(preview.applied, isFalse);
    expect(preview.affectedEntries, 1);
    expect(preview.affectedLines, greaterThanOrEqualTo(1));

    // Nothing changed yet.
    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, genCc, reason: 'dry-run must not mutate');
  });

  test('apply moves both header and lines onto the branch centre', () async {
    final (jeId, branchCc, _) = await seedStuckOnGen();

    final res = await db.repairBranchCostCenterAttribution(dryRun: false);

    expect(res.applied, isTrue);
    expect(res.affectedEntries, 1);

    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, branchCc, reason: 'header moved to the branch centre');

    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(jeId)))
        .get();
    expect(lines.every((l) => l.costCenterId == branchCc), isTrue,
        reason: 'lines moved to the branch centre');

    // Idempotent: a second run finds nothing to do.
    final again = await db.repairBranchCostCenterAttribution(dryRun: true);
    expect(again.affectedEntries, 0);
  });

  test('a MANUAL «عام» entry is left untouched', () async {
    final branchCc = await makeCc('BR1', 'مركز الفرع أ');
    final genCc = await makeCc('GEN', 'عام');
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع أ',
            costCenterId: Value(branchCc),
          ),
        );
    final jeId = await postSaleJe(branchId: branchId);
    // Force onto «عام» AND mark as NOT auto-posted (a manual choice).
    await (db.update(db.journalEntries)..where((e) => e.id.equals(jeId))).write(
      JournalEntriesCompanion(
        costCenterId: Value(genCc),
        isAutoPosted: const Value(false),
      ),
    );

    final res = await db.repairBranchCostCenterAttribution(dryRun: false);
    expect(res.affectedEntries, 0, reason: 'manual entries are never moved');

    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, genCc, reason: 'manual «عام» choice preserved');
  });
}

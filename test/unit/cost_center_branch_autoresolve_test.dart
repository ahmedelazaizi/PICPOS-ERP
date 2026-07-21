// Field 2026-07-21 — a branch's auto-posted movements must land on the
// branch's OWN cost center, not the global «عام» (GEN).
//
// Root cause guarded here: createJournalEntry used to assign the GEN «عام»
// fallback FIRST (whenever a P&L line lacked a cost center), which made the
// later branch/region resolution dead code — every branch sale/purchase was
// attributed to «عام». The fix defers the GEN fallback to the very end, so the
// priority is: explicit → branch → region → GEN. These tests lock that order.
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

  // Post a minimal, balanced sale JE (cash debit / revenue credit) with NO
  // explicit costCenterId — the revenue line is what forces cost-center
  // resolution. Returns the JE id.
  Future<int> postSaleJe({required int branchId}) async {
    final revenue = await (db.select(db.accounts)
          ..where((a) => a.code.equals('4121'))) // sales revenue (P&L)
        .getSingle();
    final cash = await (db.select(db.accounts)
          ..where((a) => a.code.equals('1111'))) // cash on hand
        .getSingle();
    return db.createJournalEntry(
      description: 'اختبار مركز تكلفة الفرع',
      date: DateTime(2026, 7, 1),
      referenceType: 'sale',
      isAutoPosted: true,
      branchId: branchId,
      // costCenterId intentionally omitted (null) — the whole point.
      lines: [
        JournalLine(accountId: cash.id, debit: 100),
        JournalLine(accountId: revenue.id, credit: 100),
      ],
    );
  }

  test('branch WITH a cost center → JE posts to the branch centre, not «عام»',
      () async {
    final branchCc = await makeCc('BR1', 'مركز الفرع أ');
    // A pre-existing GEN «عام» that must NOT be chosen over the branch's own.
    final genCc = await makeCc('GEN', 'عام');
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع أ',
            costCenterId: Value(branchCc),
          ),
        );

    final jeId = await postSaleJe(branchId: branchId);

    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, branchCc,
        reason: 'JE header must carry the branch cost center');
    expect(je.costCenterId, isNot(genCc),
        reason: 'the global «عام» must never win over the branch centre');

    // The revenue line inherits the resolved header cost center too.
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(jeId)))
        .get();
    expect(lines.every((l) => l.costCenterId == branchCc), isTrue,
        reason: 'lines inherit the branch cost center');
  });

  test('branch withOUT a cost center → falls back to «عام» (GEN)', () async {
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'الفرع ب'), // no costCenterId
        );

    final jeId = await postSaleJe(branchId: branchId);

    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, isNotNull);
    final cc = await (db.select(db.costCenters)
          ..where((c) => c.id.equals(je.costCenterId!)))
        .getSingle();
    expect(cc.code, 'GEN',
        reason: 'last-resort fallback is the global «عام» centre');
  });

  test('branch with no CC but a region CC → region centre wins over «عام»',
      () async {
    final regionCc = await makeCc('RG1', 'مركز المنطقة');
    final regionId = await db.into(db.regions).insert(
          RegionsCompanion.insert(
            name: 'المنطقة',
            costCenterId: Value(regionCc),
          ),
        );
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع ج',
            regionId: Value(regionId),
          ),
        );

    final jeId = await postSaleJe(branchId: branchId);

    final je = await (db.select(db.journalEntries)..where((e) => e.id.equals(jeId)))
        .getSingle();
    expect(je.costCenterId, regionCc,
        reason: 'branch has no CC → its region CC wins over «عام»');
  });
}

// مجاميعُ القيود — **استعلامٌ واحدٌ مُجمَّع، وترشيحٌ يطابق القائمةَ حرفاً**.
//
// ═══ لماذا استعلامٌ مستقلّ ═══
//
// `journal_entries` **لا تحمل عمودَي مجموع**: الأرقامُ في
// `journal_entry_lines` وحدَها. وتصميمُ اليومية العامة يطلبها في موضعَين —
// عمودَي «إجمالي المدين/الدائن» و«الفرق» على كلّ صفّ، وشريطَ إجماليّاتِ
// الصفحة فوقها.
//
// 🔴 **وقراءتُها بنداءٍ لكلّ قيدٍ استعلامُ N+1**: صفحةٌ بمئة قيدٍ = مئةُ رحلةٍ
// إلى القاعدة في كلّ إعادةِ بناء. فالتجميعُ في القاعدة رحلةٌ واحدة.
//
// ═══ ⚠️ والخطرُ الحقيقيُّ في الترشيح ═══
//
// المجاميعُ تُقرأ بمدىً زمنيٍّ مستقلٍّ عن مجرى القائمة. فإن اختلف الترشيحان
// بحرفٍ واحد — يومٌ في الطرف، أو محذوفٌ يُعدّ — **جمع الشريطُ قيوداً لا
// تظهر تحته**، فيقرأ المستخدمُ إجماليّاً لا يطابق ما يعدّه بعينه على الشاشة
// ولا سبيلَ له لمعرفة السبب.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;
  late int cashId;
  late int rentId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedFiscalYear(db);
    cashId = await _seedAccount(db, '1111', 'الصندوق', 'asset');
    rentId = await _seedAccount(db, '5101', 'مصروف الإيجار', 'expense');
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  Future<int> makeEntry({
    required double amount,
    DateTime? date,
    bool asDraft = false,
  }) =>
      db.createJournalEntry(
        description: 'قيدُ قياس',
        date: date ?? DateTime.now(),
        lines: [
          JournalLine(accountId: rentId, debit: amount, credit: 0),
          JournalLine(accountId: cashId, debit: 0, credit: amount),
        ],
        referenceType: 'manual',
        asDraft: asDraft,
      );

  final wideFrom = DateTime(DateTime.now().year, 1, 1);
  final wideTo = DateTime(DateTime.now().year, 12, 31);

  Future<Map<int, ({double debit, double credit})>> totals({
    DateTime? from,
    DateTime? to,
  }) =>
      db.watchJournalEntryTotals(from: from ?? wideFrom, to: to ?? wideTo).first;

  test('كلُّ قيدٍ بمجموعَيه — استعلامٌ واحدٌ لا نداءٌ لكلّ صفّ', () async {
    final a = await makeEntry(amount: 1000);
    final b = await makeEntry(amount: 500);

    final map = await totals();
    expect(map[a]?.debit, closeTo(1000, 1e-9));
    expect(map[a]?.credit, closeTo(1000, 1e-9));
    expect(map[b]?.debit, closeTo(500, 1e-9));
    expect(map[b]?.credit, closeTo(500, 1e-9));
  });

  test('والمسوّدةُ تُعَدّ — الشاشةُ تعرضها وتحتاج أرقامَها', () async {
    // ⚠️ الفرقُ بين «مكتوبٌ في القيد» و«دخل الأستاذَ» يقوله عمودُ الحالة لا
    //    الإجماليّات. وإسقاطُها هنا يترك صفّاً بأصفارٍ على الشاشة.
    final draft = await makeEntry(amount: 250, asDraft: true);
    final map = await totals();
    expect(map[draft]?.debit, closeTo(250, 1e-9));
  });

  test('🔴 والمدى يطابق `watchJournalEntries` حرفاً — طرفاه داخلان', () async {
    // قيدٌ في **آخرِ يومٍ** من المدى: ترشيحٌ يقارن بمنتصف الليل يُسقطه من
    // المجاميع ويُبقيه في القائمة — فيقرأ المستخدمُ إجماليّاً ينقص صفّاً
    // يراه أمامه.
    final edge = DateTime(2026, 9, 30, 18, 45);
    final id = await makeEntry(amount: 700, date: edge);

    final listed = await db
        .watchJournalEntries(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30))
        .first;
    final map =
        await totals(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));

    expect(listed.map((e) => e.id), contains(id),
        reason: 'خطُّ الأساس: القائمةُ تعرضه');
    expect(map.containsKey(id), isTrue,
        reason: 'القائمةُ تعرضه والشريطُ لا يجمعه');
    expect(map[id]?.debit, closeTo(700, 1e-9));
  });

  test('وما خرج من المدى لا يُجمَع', () async {
    final inside = await makeEntry(amount: 100, date: DateTime(2026, 9, 15));
    final outside = await makeEntry(amount: 999, date: DateTime(2026, 8, 15));

    final map =
        await totals(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(map.containsKey(inside), isTrue);
    expect(map.containsKey(outside), isFalse,
        reason: 'قيدٌ خارجَ المدى دخل الإجماليَّ — والقائمةُ لا تعرضه');
  });

  test('والمحذوفُ منطقيّاً لا يُجمَع', () async {
    final id = await makeEntry(amount: 300);
    await (db.update(db.journalEntries)..where((e) => e.id.equals(id)))
        .write(const JournalEntriesCompanion(isDeleted: Value(true)));

    expect((await totals()).containsKey(id), isFalse,
        reason: 'محذوفٌ يُجمَع — والقائمةُ تُخفيه');
  });

  test('وقيدٌ بلا سطورٍ يغيب عن الخريطة — والشاشةُ تقرأ صفراً', () async {
    // `GROUP BY` لا يُنتج صفّاً لِما لا سطورَ له. والشاشةُ تسدّ الفجوةَ
    // بصفرٍ صريحٍ لا بانهيار.
    final id = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'JV-EMPTY',
            entryDate: DateTime.now(),
            description: const Value('بلا سطور'),
          ),
        );
    expect((await totals()).containsKey(id), isFalse);
  });
}

// ─────────────────────────────────────────────────────────────────────────────

Future<int> _seedAccount(AppDatabase db, String code, String name, String type) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          balance: const Value(0.0),
          isActive: const Value(true),
        ),
      );
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '${now.year}',
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year, 12, 31),
          isClosed: const Value(false),
        ),
      );
}

Future<void> _clearDatabase(AppDatabase db) async {
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  await db.delete(db.accounts).go();
  await db.delete(db.settings).go();
}

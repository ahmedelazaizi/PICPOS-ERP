// «العكسُ المباشر» — **ولا يُعكَس إلّا ما رُحِّل فعلاً**.
//
// ═══ قرارُ المالك 2026-09-18 وما قاسته الشيفرة ═══
//
// القرارُ على تصميم اليومية العامة: **عكسٌ مباشرٌ كما اليوم — لا «طلبُ عكس»**.
// وشريطُ التصميم السفليُّ يقرأ «طلب عكس القيد»، فالقرارُ يسقطه: العكسُ يقع
// فوراً بلا دورةِ اعتمادٍ ثانية.
//
// وقياسُ المسار المباشر كشف ثغرةً تحته:
//
// ═══ 🔴 مسوّدةٌ تُعكَس فتُحرّك الأستاذَ بلا ما يقابله ═══
//
// المسوّدةُ (`asDraft: true`) تُكتَب بـ`isPosted = false`، وسطورُها موجودةٌ في
// الجدول لكنّها **مستثناةٌ من حساب الأرصدة** (`WHERE je.is_posted = 1`).
// فالمسوّدةُ لم تمسّ الدليلَ بعد.
//
// و`reverseJournalEntryById` كانت تُحمّل القيدَ بمفتاحه الأساسيِّ **بلا فحص
// `isPosted`**، ثمّ تُنشئ عكسَه بـ`createJournalEntry` الذي `asDraft` فيه
// `false` افتراضاً — أي **عكسٌ مُرحَّلٌ لأصلٍ لم يُرحَّل**. فالأرصدةُ تتحرّك
// في اتّجاهٍ واحدٍ بلا شيءٍ يلغيه: نقرةٌ واحدةٌ على قيدٍ يحمل شارةَ «بانتظار
// الاعتماد» تُفسد الدليل.
//
// ⚠️ **وأسوأُ منه ما يلي**: المسوّدةُ تبقى `needsApproval = true`. فإن اعتُمدت
// بعدها أعادت `approveJournalEntry` حسابَ الأرصدة على السطور المُرحَّلة —
// وقد صار الطرفان مُرحَّلَين — فيتلاشى أثرُ القيد الذي أراده المستخدمُ
// واعتُمد. عمليّةٌ تمّت ولا أثرَ لها.
//
// ⚠️ **والحارسُ في الـDAO لا في الشاشة**: الشاشةُ تُعطّل الزرَّ فتُحسّن
// التجربة، لكنّ المسارَ يُبلَغ من الشاشةِ الأصليّةِ أيضاً ومن أيّ سكربت.
// وهو **قبل أيّ كتابة**، فالرفضُ لا يترك رصيداً تحرّك.

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

  Future<int> makeEntry({required bool asDraft, double amount = 500}) =>
      db.createJournalEntry(
        description: 'إثبات مصروف إيجار',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: rentId, debit: amount, credit: 0),
          JournalLine(accountId: cashId, debit: 0, credit: amount),
        ],
        referenceType: 'manual',
        asDraft: asDraft,
      );

  Future<double> balanceOf(int accountId) async =>
      (await (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
              .getSingle())
          .balance;

  Future<int> entryCount() async =>
      (await db.select(db.journalEntries).get()).length;

  group('🔴 مسوّدةٌ لا تُعكَس — العكسُ يخصُّ ما دخل الأستاذ', () {
    test('والمسوّدةُ لم تمسّ الأرصدةَ أصلاً — خطُّ الأساس', () async {
      await makeEntry(asDraft: true);
      expect(await balanceOf(rentId), closeTo(0, 1e-9));
      expect(await balanceOf(cashId), closeTo(0, 1e-9));
    });

    test('🔴 عكسُها لا يُحرّك رصيداً ولا يُنشئ قيداً', () async {
      // قبل الحارس: يُنشَأ عكسٌ **مُرحَّلٌ** فيصير الإيجارُ سالباً والصندوقُ
      // موجباً — بلا أن يكون الأصلُ قد حرّك شيئاً يُلغى.
      final draftId = await makeEntry(asDraft: true);
      final before = await entryCount();

      await expectLater(
        db.reverseJournalEntryById(entryId: draftId),
        throwsA(isA<Exception>()),
        reason: 'مسوّدةٌ عُكست بلا اعتراض — والأستاذُ تحرّك بلا مقابل',
      );

      expect(await entryCount(), before, reason: 'قيدُ عكسٍ كُتب لمسوّدة');
      expect(await balanceOf(rentId), closeTo(0, 1e-9),
          reason: 'رصيدُ المصروف تحرّك بعكسِ ما لم يُرحَّل');
      expect(await balanceOf(cashId), closeTo(0, 1e-9),
          reason: 'رصيدُ الصندوق تحرّك بعكسِ ما لم يُرحَّل');
    });

    test('🔴 والاعتمادُ بعدها يُنتج أثرَه كاملاً لا صفراً', () async {
      // هذا هو الضررُ الخفيّ: بلا الحارس يصير الطرفان مُرحَّلَين، فتُعيد
      // `approveJournalEntry` الحسابَ عليهما معاً فيتلاشى أثرُ القيد.
      final draftId = await makeEntry(asDraft: true);
      try {
        await db.reverseJournalEntryById(entryId: draftId);
      } catch (_) {
        // مرفوضٌ — وهذا المقصود.
      }
      await db.approveJournalEntry(draftId, 1);

      expect(await balanceOf(rentId), closeTo(500, 1e-9),
          reason: 'القيدُ اعتُمد ولا أثرَ له — ابتلعه عكسُ المسوّدة');
      expect(await balanceOf(cashId), closeTo(-500, 1e-9));
    });

    test('ورسالةُ الرفض تقول ما يُفعَل بدلاً منه', () async {
      final draftId = await makeEntry(asDraft: true);
      // «تعذّر العكس» وحدَها تترك المستخدمَ بلا سبيل؛ والمسوّدةُ تُعتمَد أو
      // تُعدَّل، ولا تُعكَس.
      await expectLater(
        db.reverseJournalEntryById(entryId: draftId),
        throwsA(predicate<Object>((e) => e.toString().contains('مسودة'),
            'رسالةٌ تذكر المسوّدة')),
      );
    });
  });

  group('والمُرحَّلُ يُعكَس كما كان — الحارسُ لا يُعطّل الفعل', () {
    test('قيدٌ مُرحَّلٌ يُعكَس وتعود الأرصدةُ إلى الصفر', () async {
      final postedId = await makeEntry(asDraft: false);
      expect(await balanceOf(rentId), closeTo(500, 1e-9),
          reason: 'خطُّ الأساس: القيدُ المُرحَّلُ حرّك الأرصدة');

      final reversalId = await db.reverseJournalEntryById(entryId: postedId);
      expect(reversalId, greaterThan(0));
      expect(await balanceOf(rentId), closeTo(0, 1e-9));
      expect(await balanceOf(cashId), closeTo(0, 1e-9));
    });

    test('والعكسُ نفسُه مُرحَّلٌ لا مسوّدة', () async {
      // عكسٌ يُكتَب مسوّدةً يعني أنّ الأستاذَ يبقى خاطئاً حتّى يعتمده أحدٌ —
      // وهو عينُ «طلب العكس» الذي أسقطه القرار.
      final postedId = await makeEntry(asDraft: false);
      final reversalId = await db.reverseJournalEntryById(entryId: postedId);
      final reversal = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(reversalId)))
          .getSingle();
      expect(reversal.isPosted, isTrue, reason: 'العكسُ صار «طلباً» ينتظر');
      expect(reversal.needsApproval, isFalse);
    });
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

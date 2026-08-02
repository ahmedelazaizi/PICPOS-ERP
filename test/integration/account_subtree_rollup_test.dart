// تجميع رصيد حساب أب: بالشجرة (`parent_id`) مش ببادئة الكود.
//
// ── عطلان من نفس الجذر ──────────────────────────────────────────────────────
//
// **١. تقرير مطابقة الذمم — إنذار كاذب بقيمة الـAR كلها.**
// `getArReconciliation` (`party_dao.dart:1772`) بيجمع سطور القيود على حساب
// **المراقبة** ١١٢١ بس. والقيود عمرها ما بتنزل عليه: `_resolvePartySubAccount`
// (`accounting_autopost_dao.dart`) بيرجّع `party.accountId` — الحساب الفرعي
// للعميل (`1121-00001`) اللي بيتخلق تحت ١١٢١ عند إنشاء أي عميل.
//
// فالنتيجة `totalGlBalance = 0` **دايماً**، و`difference` = كل رصيد العملاء.
// و`reconciliation_service.dart:377` بيسجّل الإنذار ده في `field_audit_logs`
// وشاشة التقارير بتعرضه. ده على الأغلب مصدر «الإيجابيات الكاذبة» في تقارير
// سابقة: الدفاتر سليمة ١٠٠٪ والتقرير بيقول فيه فرق.
//
// والاستعلام كمان **مش بيفلتر** `is_posted` و`is_deleted` — على عكس
// `getPartyBalanceMismatches` في نفس الملف اللي بيفلتر صح.
//
// **٢. كارت أستاذ ٦٢١ بيبلع حسابات شقيقة.**
// `getAccountLedger` (`accounting_dao_reads.dart:471`) بيستعمل
// `code LIKE '621%'`. والشجرة المزروعة فيها ٦٢١ «رواتب وأجور» **شقيق**
// لـ٦٢١٠…٦٢١٧ (كلهم `detail` تحت ٦٢) مش أب ليهم. فكارت الرواتب بيضم رخص
// حكومية ونظافة وسفر وإهلاك ومتنوعة وخصم مسموح و**عجز مخزون** و**عجز نقدي**.
// كارت الأستاذ بيقول رقم وميزان المراجعة بيقول رقم تاني لنفس الحساب.
//
// ── الحل الواحد ─────────────────────────────────────────────────────────────
// تجميع بالشجرة عبر `parent_id`: الحساب + أبناؤه فعلاً. البادئة النصية
// بتشتغل صح للأبناء الحقيقيين (`412` → `4121`) وبتكسر لما يبقى فيه شقيق
// بادئته أطول — وde موجود في الدليل المزروع فعلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });
  tearDown(() => db.close());

  Future<void> post(String drCode, String crCode, double amount) async {
    final dr = await db.getAccountByCode(drCode);
    final cr = await db.getAccountByCode(crCode);
    await db.createJournalEntry(
      description: 'test',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: dr!.id, debit: amount),
        JournalLine(accountId: cr!.id, credit: amount),
      ],
    );
  }

  group('accountSubtreeIds — الحساب وأبناؤه بالشجرة', () {
    test('حساب detail بلا أبناء بيرجّع نفسه بس', () async {
      final salaries = await db.getAccountByCode('621');
      final ids = await db.accountSubtreeIds(salaries!.id);
      expect(ids, [salaries.id]);
    });

    test('٦٢١ ما بيبلعش إخوته ٦٢١٠..٦٢١٧ — ده كان الباج', () async {
      final salaries = await db.getAccountByCode('621');
      final misc = await db.getAccountByCode('6214');
      final shrinkage = await db.getAccountByCode('6216');
      final ids = await db.accountSubtreeIds(salaries!.id);

      expect(ids, isNot(contains(misc!.id)));
      expect(ids, isNot(contains(shrinkage!.id)));
    });

    test('حساب view بيرجّع أبناءه الحقيقيين', () async {
      final admin = await db.getAccountByCode('62'); // view
      final salaries = await db.getAccountByCode('621');
      final misc = await db.getAccountByCode('6214');
      final ids = await db.accountSubtreeIds(admin!.id);

      expect(ids, contains(salaries!.id));
      expect(ids, contains(misc!.id));
      expect(ids, contains(admin.id), reason: 'الأب نفسه جزء من شجرته');
    });

    test('الأبناء الحقيقيين بالبادئة برضه بيتلقطوا (٤١٢ → ٤١٢١)', () async {
      final parent = await db.getAccountByCode('412');
      final child = await db.getAccountByCode('4121');
      if (parent == null || child == null) return; // دليل معدَّل
      expect(await db.accountSubtreeIds(parent.id), contains(child.id));
    });
  });

  group('كارت الأستاذ', () {
    test('كارت ٦٢١ ما بيضمش حركة ٦٢١٦', () async {
      await post('621', '1111', 1000); // رواتب
      await post('6216', '1111', 77); // عجز مخزون

      final ledger = await db.getAccountLedger(
        (await db.getAccountByCode('621'))!.id,
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      final total = ledger.fold<double>(
          0, (s, r) => s + ((r['debit'] as num?)?.toDouble() ?? 0));
      expect(total, closeTo(1000, 0.01),
          reason: 'الكارت بيقول 1077 وميزان المراجعة بيقول 1000');
    });
  });

  group('مطابقة الذمم', () {
    test('قيد على حساب فرعي لعميل بيتحسب في رصيد الأستاذ', () async {
      // إنشاء عميل بيخلق له حساب فرعي تحت ١١٢١.
      final partyId = await db.insertParty(PartiesCompanion.insert(
        name: 'عميل مطابقة',
        isCustomer: const Value(true),
      ));
      final party = await db.getPartyById(partyId);
      expect(party?.accountId, isNotNull,
          reason: 'الإعداد فشل — العميل مالوش حساب فرعي');

      final sub = await db.getAccountById(party!.accountId!);
      final revenue = await db.getAccountByCode('4121');
      await db.createJournalEntry(
        description: 'بيع آجل',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: sub!.id, debit: 1000),
          JournalLine(accountId: revenue!.id, credit: 1000),
        ],
      );

      // البيع الآجل الحقيقي بيحدّث رصيد البطاقة مع القيد. الاختبار بيحاكي
      // الحالة السليمة عشان يثبت إن التقرير بيقول «صفر فرق» — قبل الإصلاح
      // كان بيقول فرق = كل الـAR رغم إن الدفاتر مظبوطة.
      await (db.update(db.parties)..where((p) => p.id.equals(partyId)))
          .write(const PartiesCompanion(balance: Value(1000)));

      final rec = await db.getArReconciliation();
      expect(rec, isNotNull);
      expect(rec!.totalGlBalance, closeTo(1000, 0.01),
          reason: 'القيود بتنزل على الفرعي، والتقرير كان بيقرا المراقبة بس');
      expect(rec.difference, closeTo(0, 0.01),
          reason: 'الدفاتر سليمة — أي فرق هنا إنذار كاذب');
    });
  });
}

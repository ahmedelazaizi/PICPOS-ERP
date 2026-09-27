// ═══════════════════════════════════════════════════════════════════════════
// مانعٌ محاسبيٌّ حيٌّ لم يكن في الخارطة — قائمةُ التدفّقات النقديّة تُسقط
// كلَّ حركةٍ تقع على حسابِ خزنةٍ فرعيّ
// ═══════════════════════════════════════════════════════════════════════════
//
// شجرةُ النقديّة المزروعة:
//
//   111  «النقدية وما في حكمها»            (view)
//    ├── 1111 الصندوق الرئيسي              (detail)
//    ├── 1113 البنك الأهلي                  (detail)
//    ├── 1116 حساب Click                    (detail)
//    └── 111-0000N  ← حسابُ **كلِّ خزنةٍ** يُنشأ هنا
//
// و`linkUnlinkedSafesToSubAccounts` تربط كلَّ خزنةٍ بحسابها الفرعيّ عند
// الإقلاع (‏مرّةً لكلِّ تنصيب)، و`autoPostSale._resolveSaleLegAccount` ترحّل
// رِجْلَ النقد على حساب **الخزنة التي استلمت** لا على `1111`.
//
// 🔴 و`getCashFlowStatement` كانت ترشّح `WHERE a.code IN ('1111','1113')` —
// أي **الأخوَين وحدَهما**. فحسابُ الخزنة `111-0000N` لا يطابق أيّاً منهما،
// وكلُّ بيعةٍ نقديّةٍ تسقط من القائمة بصمت. لا خطأ، ولا صفر ظاهرٌ في مكانٍ
// آخر — فقط قائمةٌ تُقرأ وتُعتمَد وهي ناقصة.
//
// وهذا **قائمٌ اليوم** ومستقلٌّ عن أيِّ تغييرٍ في الخزينة: الترحيلُ على
// الحسابات الفرعيّة مشحونٌ منذ مواصفة ١٣٦.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  test('التجهيزة: الخزنةُ الافتراضيّةُ مرتبطةٌ بحسابٍ فرعيٍّ ليس 1111',
      () async {
    final safe = await db.getDefaultSafeByType('cash');
    expect(safe, isNotNull);
    expect(safe!.linkedAccountId, isNotNull,
        reason: 'الردمُ يربط كلَّ خزنةٍ عند الإقلاع — بدونه لا يقيس الاختبارُ '
            'شيئاً لأنّ الترحيلَ يسقط إلى 1111');

    final linked = await db.getAccountById(safe.linkedAccountId!);
    final generic = await db.getAccountByCode('1111');
    expect(linked, isNotNull);
    expect(generic, isNotNull);
    expect(linked!.id, isNot(generic!.id),
        reason: 'حسابُ الخزنة **شقيقٌ** لـ1111 لا هو — وهذا أصلُ العطب');
    expect(linked.parentId, equals(generic.parentId),
        reason: 'كلاهما تحت 111');
  });

  test('حركةٌ على حسابِ خزنةٍ فرعيٍّ تظهر في التدفّقات النقديّة', () async {
    final safe = await db.getDefaultSafeByType('cash');
    final safeAccountId = safe!.linkedAccountId!;
    final salesAcc = await db.getAccountByCode(
      await db.getMappedAccountCode(
          'sales', AccountingDao.accountPurposes['sales']!),
    );
    expect(salesAcc, isNotNull, reason: 'شرطٌ مسبق: حسابُ المبيعات مزروع');

    final when = DateTime(2026, 8, 15);
    await db.createJournalEntry(
      description: 'بيعةٌ نقديّةٌ على حساب الخزنة',
      date: when,
      referenceType: 'sale',
      referenceId: 1,
      isAutoPosted: true,
      lines: [
        JournalLine(
          accountId: safeAccountId,
          debit: 500.0,
          description: 'نقديّةٌ إلى درج الكاشير',
        ),
        JournalLine(
          accountId: salesAcc!.id,
          credit: 500.0,
          description: 'إيراد',
        ),
      ],
    );

    final cf = await db.getCashFlowStatement(
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 31),
    );
    final operating = cf['operating'] as Map<String, dynamic>;

    // 🔴 المعطوب: صفر — الحركةُ على `111-0000N` والترشيحُ على `1111` وحدَه.
    expect((operating['totalInflow'] as num).toDouble(), closeTo(500.0, 0.01),
        reason: 'التدفّقُ الداخلُ يشمل حركاتِ حسابات الخزائن الفرعيّة');
    expect((operating['net'] as num).toDouble(), closeTo(500.0, 0.01));
    expect((cf['netChange'] as num).toDouble(), closeTo(500.0, 0.01),
        reason: 'صافي التغيّر في النقديّة يساوي ما دخل فعلاً');
  });

  test('الحركةُ على 1111 العامِّ ما زالت تُحتسَب — لم يُكسَر المسارُ القديم',
      () async {
    final generic = await db.getAccountByCode('1111');
    final salesAcc = await db.getAccountByCode(
      await db.getMappedAccountCode(
          'sales', AccountingDao.accountPurposes['sales']!),
    );

    await db.createJournalEntry(
      description: 'حركةٌ على الحساب العامّ',
      date: DateTime(2026, 8, 15),
      referenceType: 'sale',
      referenceId: 2,
      isAutoPosted: true,
      lines: [
        JournalLine(accountId: generic!.id, debit: 200.0, description: 'نقد'),
        JournalLine(accountId: salesAcc!.id, credit: 200.0, description: 'إيراد'),
      ],
    );

    final cf = await db.getCashFlowStatement(
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 31),
    );
    final operating = cf['operating'] as Map<String, dynamic>;
    expect((operating['totalInflow'] as num).toDouble(), closeTo(200.0, 0.01));
  });
}

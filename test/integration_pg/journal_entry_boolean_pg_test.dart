// ═══════════════════════════════════════════════════════════════════════════
// كتابة القيد على PostgreSQL — `is_posted = 1` على عمود boolean
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **نتيجة هذا الملف: الادعاء مرفوض بالقياس.** تقرير تدقيق محاسبي قال
// إن كل قيد يومية بيفشل على PostgreSQL بسبب `is_posted = 1` على عمود
// boolean. القياس المباشر على PG 18.4 بيقول العكس:
//
//     information_schema: journal_entries.is_posted = boolean   ← فعلاً boolean
//     SELECT COUNT(*) FROM journal_entries WHERE is_posted = 1  ← **بينجح**
//
// والاختبار ده بيكتب قيداً كاملاً على PG وبيعدّي أخضر من أول مرة، بما فيه
// إعادة حساب الأرصدة. فالمسار سليم ومحدش محتاج يلمس الـ١٠١ موضع.
//
// اتساب هنا كحارس انحدار مش كإصلاح — لأنه بيسدّ فجوة تغطية حقيقية:
// سويّة PG كان فيها ٣٩ اختباراً و**مفيش ولا واحد بيرحّل قيداً**.
//
// ── السياق الأصلي ──────────────────────────────────────────────────────────
// `createJournalEntry` بتعيد حساب أرصدة الحسابات المتأثّرة بـSQL خام:
//
//     WHERE jel.account_id IN (…) AND je.is_posted = 1
//
// والاستعلام ده **جوّه الترانزاكشن** بتاعة إنشاء القيد. فلو كان بيرمي فعلاً،
// الترانزاكشن كانت هترجع، والقيد ما يتكتبش، وبما إن كل بيعة بترحّل قيداً
// كانت البيعة نفسها هترجع. الادعاء كان معقولاً — بس غلط.
//
// **ليه ما رماش؟** مقيس مش مستنتَج: على PG 18.4 المقارنة دي بتُحَل من غير
// خطأ. مش معنى كده إنها أسلوب سليم — `sqlBool()` (`database.dart:600`)
// أوضح وأأمن عبر النسخ — بس مفيش عطل إنتاجي هنا، ومفيش داعي نلمس ١٠١ موضع
// على أساس تقرير ما اتقاسش.
//
// 🔴 الدرس: تقرير وكيل مكتوب عليه «[مؤكَّد]» مش دليل. القياس هو الدليل.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;

  setUpAll(() async {
    fx = await bootPgTestSchema();
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  Future<int> seedAccount({
    required String code,
    required String name,
    required String type,
    required String normalBalance,
  }) {
    return fx.db.into(fx.db.accounts).insert(
          AccountsCompanion.insert(
            code: code,
            name: name,
            accountType: type,
            normalBalance: d.Value(normalBalance),
          ),
        );
  }

  test('قيد متزن بيتكتب فعلاً على PostgreSQL ورصيد الحساب بيتحدّث', () async {
    final cash = await seedAccount(
        code: 'PGJE-1111', name: 'الصندوق', type: 'asset', normalBalance: 'debit');
    final capital = await seedAccount(
        code: 'PGJE-3111', name: 'رأس المال', type: 'equity', normalBalance: 'credit');

    // أبسط قيد ممكن: مدين نقدية ١٠٠ / دائن رأس مال ١٠٠.
    final entryId = await fx.db.createJournalEntry(
      description: 'اختبار كتابة قيد على PostgreSQL',
      date: DateTime(2026, 8, 4),
      lines: [
        JournalLine(accountId: cash, debit: 100),
        JournalLine(accountId: capital, credit: 100),
      ],
    );

    expect(entryId, greaterThan(0), reason: 'القيد ما اتكتبش أصلاً');

    // الصف موجود فعلاً في القاعدة (مش مجرد id راجع من دالة).
    final stored = await (fx.db.select(fx.db.journalEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    expect(stored, isNotNull, reason: 'الترانزاكشن اترجعت — مفيش صف قيد');

    // والسطرين اتكتبوا ومتزنين.
    final lines = await (fx.db.select(fx.db.journalEntryLines)
          ..where((l) => l.entryId.equals(entryId)))
        .get();
    expect(lines, hasLength(2));
    final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
    expect(totalDebit, closeTo(totalCredit, 0.0005));

    // ── الجزء اللي بيسقط بالظبط على `is_posted = 1` ──────────────────────
    // إعادة حساب الأرصدة بتحصل بعد إدراج السطور وجوّه نفس الترانزاكشن.
    final cashRow = await (fx.db.select(fx.db.accounts)
          ..where((a) => a.id.equals(cash)))
        .getSingle();
    expect(cashRow.balance, closeTo(100, 0.0005),
        reason: 'رصيد الحساب ما اتحدّثش — استعلام إعادة الحساب رمى');

    final capitalRow = await (fx.db.select(fx.db.accounts)
          ..where((a) => a.id.equals(capital)))
        .getSingle();
    expect(capitalRow.balance, closeTo(-100, 0.0005));
  });
}

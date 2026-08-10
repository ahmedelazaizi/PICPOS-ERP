// ═══════════════════════════════════════════════════════════════════════════
// §٣-ج — اختبارُ ثباتٍ لقاعدة الإشارة · على قاعدةٍ حقيقية
// ═══════════════════════════════════════════════════════════════════════════
//
// `signedSafeDelta` قاعدةٌ **مستنبَطةٌ** من مواضع الكتابة، لا مصرَّحٌ بها في
// مكانٍ واحد: كلُّ موضعٍ يمرّر دلتا صريحةً لمسار تعديل الرصيد.
//
// ⚠️ ولا تُخلط بتصنيف Spec 106 (‏`withdrawal`/`transfer`/`closing` **محايدة**):
// ذاك يصنّف «قبضٌ مقابل صرف» لبطاقات التقرير — تحويلٌ داخليٌّ بين خزنتين
// ليس إيراداً ولا مصروفاً. أمّا هنا فالسؤالُ آخر: **هل تحرّك الرصيد؟**
// وسحبُ إقفال الوردية يُنقص الدرجَ فعلاً (`balanceAfter = balance − drain`).
// خلطُ التصنيفين كان سيجعل عمودَ الرصيد ينحرف عن الخزنة بلا أن ينطق شيء.
//
// فالحكمُ لهذا الاختبار: المشيُ فوق **كلّ** حركات الخزنة من صفرٍ يجب أن
// ينتهي عند `safes.balance` نفسِه. أيُّ نوعٍ تُخطئ إشارتُه يُسقطه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/safe_running_balance.dart';

void main() {
  late AppDatabase db;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
  });

  tearDown(() async => db.close());

  /// المشيُ فوق كلّ حركات الخزنة من صفر.
  Future<double> walkAll(int id) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) => t.safeId.equals(id) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
    final balances = runningBalances(
      rowsNewestFirst: [
        for (final r in rows)
          SafeMovementRow(id: r.id, type: r.transactionType, amount: r.amount),
      ],
      openingBalance: 0,
    );
    if (rows.isEmpty) return 0;
    // رصيدُ الصفّ الأحدث هو النهاية.
    return balances[rows.first.id]!;
  }

  Future<double> safeBalance(int id) async =>
      (await (db.select(db.safes)..where((s) => s.id.equals(id))).getSingle())
          .balance;

  test('قبضٌ ثم صرف — المشيُ ينتهي عند رصيد الخزنة', () async {
    await db.createReceiptVoucher(
        amount: 100, category: 'other', safeId: safeId, description: 'قبض');
    await db.createPaymentVoucher(
        amount: 40, category: 'other', safeId: safeId, description: 'صرف');

    expect(await safeBalance(safeId), 60.0, reason: 'تجهيزة');
    expect(await walkAll(safeId), await safeBalance(safeId));
  });

  test('صفُّ `memo` لا يحرّك الرصيدَ ولا يزيح المشي', () async {
    await db.createReceiptVoucher(
        amount: 100, category: 'other', safeId: safeId, description: 'قبض');
    final before = await safeBalance(safeId);

    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            safeId: safeId,
            transactionType: 'memo',
            voucherNumber: 'MEMO-1',
            amount: 999,
            balanceAfter: before,
            category: 'purchase_balance',
          ),
        );

    expect(await safeBalance(safeId), before,
        reason: 'المذكّرةُ لا تُدرَج عبر مسارٍ يحرّك الرصيد');
    expect(await walkAll(safeId), before,
        reason: 'ولو حُسبت «−٩٩٩» لانحرف العمودُ عن الخزنة بلا سبب');
  });

  test('إقفالُ الوردية — السحبُ يُنقص الدرجَ والمشيُ يتبعه', () async {
    // `withdrawal` **محايدٌ** في تصنيف Spec 106 لبطاقات «قبض/صرف»، لكنه
    // يُنقص الرصيدَ فعلاً. هذا الاختبارُ هو ما يمنع خلطَ التصنيفين.
    await db.createReceiptVoucher(
        amount: 200, category: 'other', safeId: safeId, description: 'قبض');
    final before = await safeBalance(safeId);

    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            safeId: safeId,
            transactionType: 'withdrawal',
            voucherNumber: 'WD-1',
            amount: 50,
            balanceAfter: before - 50,
            category: 'shift_closing',
          ),
        );
    await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
        .write(SafesCompanion(balance: Value(before - 50)));

    expect(await walkAll(safeId), await safeBalance(safeId));
  });

  test('الحذفُ الناعمُ يُخرج الحركةَ من المشي — وهو ما عجز عنه المخزَّن',
      () async {
    // العطبُ الأصليّ: `balanceAfter` لقطةٌ، فإلغاءُ حركةٍ سابقةٍ يترك لقطاتِ
    // ما بعدها على حالها فتصير كلُّها خاطئةً صامتة.
    await db.createReceiptVoucher(
        amount: 100, category: 'other', safeId: safeId, description: 'أولى');
    await db.createReceiptVoucher(
        amount: 30, category: 'other', safeId: safeId, description: 'ثانية');

    // نُلغي الأولى ونصحّح رصيدَ الخزنة كما يفعل مسارُ الحذف.
    await (db.update(db.safeTransactions)
          ..where((t) => t.voucherNumber.isNotNull() & t.amount.equals(100)))
        .write(SafeTransactionsCompanion(deletedAt: Value(DateTime.now())));
    await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
        .write(const SafesCompanion(balance: Value(30)));

    // المخزَّنُ في الصفّ الثاني ما زال يقول ١٣٠ — واللقطةُ لا تُصحَّح.
    final stale = await (db.select(db.safeTransactions)
          ..where((t) => t.deletedAt.isNull()))
        .getSingle();
    expect(stale.balanceAfter, 130.0,
        reason: 'اللقطةُ المخزَّنةُ بقيت على حالها — هذا هو العطب');

    // والمشيُ يعطي الصوابَ لأنه يُعيد الحسابَ من الحركات الحيّة.
    expect(await walkAll(safeId), 30.0);
    expect(await walkAll(safeId), await safeBalance(safeId));
  });
}

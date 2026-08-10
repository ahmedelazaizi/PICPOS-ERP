// ═══════════════════════════════════════════════════════════════════════════
// تقرير المصروفات — تسريب نطاق + الملخّص والتفصيل بيقيسوا مجموعتين مختلفتين.
// ═══════════════════════════════════════════════════════════════════════════
//
// شاشة تقرير المصروفات (٩١١ سطر) مالهاش **ولا ذكر واحد** لـbranchScopeProvider.
// بتبذر `_selectedBranchId` من `activeBranchIdProvider` وبتمرّره كـ`branchId`.
// ومستخدم غير مميّز بلا تخصيص فرع بيدّي `activeBranchIdProvider == null` ⇒
// `branchId: null` ⇒ **إجمالي مصروفات الشركة كلها**. يعني انقلاب من fail-closed
// لـfail-open: نفس المستخدم بياخد `{}` من branchScopeProvider («ما يشوفش حاجة»).
//
// وجوّه الـDAO نفسه فرقان مقيسان:
//   • الملخّص (الكارت) بيفلتر `(e.branch_id IS NULL OR e.branch_id = ?)`
//     والتفصيل (الجدول) بيفلتر `e.branch_id = ?` ⇒ مصروف بلا فرع بيتحسب في
//     الكارت وما بيظهرش في الجدول. و_averagePerEntry بيقسم إجمالي مجموعة على
//     عدد مجموعة تانية.
//   • استعلامات safe_transactions في التقرير ده مفيهاش `deleted_at IS NULL`
//     ⇒ سند صرف ملغي لسه محسوب كمصروف (باقي المنظومة بتستبعده — قارن
//     treasury_reports_dao.dart:485).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchAId;
  late int branchBId;
  late int categoryId;
  late int safeAId;
  late int safeBId;

  final from = DateTime(2025, 5, 1);
  final to = DateTime(2025, 5, 31, 23, 59, 59, 999);
  final at = DateTime(2025, 5, 10, 12);

  Future<void> insertOpExpense({
    required double amount,
    int? branchId,
    String? notes,
  }) =>
      db.into(db.opExpenses).insert(OpExpensesCompanion.insert(
            categoryId: categoryId,
            amount: amount,
            expenseDate: at,
            branchId: Value(branchId),
            notes: Value(notes),
            userId: 1,
          ));

  Future<void> insertSafePayment({
    required String voucher,
    required int safeId,
    required double amount,
    DateTime? deletedAt,
  }) =>
      db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safeId,
            transactionType: 'payment',
            category: 'utilities',
            amount: amount,
            balanceAfter: 0,
            userId: const Value(1),
            createdAt: Value(at),
            deletedAt: Value(deletedAt),
          ));

  double sumSummary(List<Map<String, dynamic>> rows) => rows.fold<double>(
      0, (s, r) => s + ((r['total_amount'] as num?)?.toDouble() ?? 0));

  double sumDetail(List<Map<String, dynamic>> rows) => rows.fold<double>(
      0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

  setUp(() async {
    db = AppDatabase.forTesting();
    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-exp-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-exp-b')));
    categoryId = await db
        .into(db.opExpenseCategories)
        .insert(OpExpenseCategoriesCompanion.insert(name: 'إيجار'));
    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'خزنة A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-exp-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'خزنة B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-exp-b')));

    // فرع A: مصروف ١٠٠ · فرع B: ٢٥٠ · بلا فرع (إدارة عامة): ٣٠
    await insertOpExpense(amount: 100, branchId: branchAId);
    await insertOpExpense(amount: 250, branchId: branchBId);
    await insertOpExpense(amount: 30, notes: 'مصروف إدارة عامة بلا فرع');
    // سندات صرف نقدية: ٤٠ على خزنة A · ٦٠ على خزنة B · و٥٠٠ ملغي على A
    await insertSafePayment(voucher: 'V-A', safeId: safeAId, amount: 40);
    await insertSafePayment(voucher: 'V-B', safeId: safeBId, amount: 60);
    await insertSafePayment(
        voucher: 'V-VOID',
        safeId: safeAId,
        amount: 500,
        deletedAt: DateTime(2025, 5, 12));
  });

  tearDown(() => db.close());

  group('الملخّص والتفصيل لازم يقيسوا نفس المجموعة', () {
    test('بفلتر فرع A: مجموع الجدول == مجموع الكارت', () async {
      final summary = await db.getMonthlyExpenseSummary(
          from: from, to: to, branchId: branchAId);
      final detail = await db.getExpensesForReport(
          from: from, to: to, branchId: branchAId);
      expect(sumDetail(detail), sumSummary(summary),
          reason: 'الكارت بيضم المصروف بلا فرع (٣٠) والجدول بيسقطه');
    });

    test('بدون فلتر: مجموع الجدول == مجموع الكارت', () async {
      final summary = await db.getMonthlyExpenseSummary(from: from, to: to);
      final detail = await db.getExpensesForReport(from: from, to: to);
      expect(sumDetail(detail), sumSummary(summary));
    });
  });

  group('الحذف الناعم — سند الصرف الملغي مش مصروف', () {
    test('الكارت بيستبعد السند الملغي', () async {
      final summary = await db.getMonthlyExpenseSummary(from: from, to: to);
      expect(sumSummary(summary), 480,
          reason: '100+250+30 مصروفات + 40+60 نقدية؛ الملغي ٥٠٠ مستبعد');
    });

    test('الجدول بيستبعد السند الملغي', () async {
      final detail = await db.getExpensesForReport(from: from, to: to);
      expect(detail.any((r) => r['reference'] == 'V-VOID'), isFalse,
          reason: 'سند صرف ملغي بـ٥٠٠ كان لسه بيتعرض كمصروف');
    });
  });

  group('حصر الفروع الآمر — allowedBranchIds', () {
    test('scope={A}: فرع A + بلا فرع فقط، وB مستبعد تماماً', () async {
      final summary = await db.getMonthlyExpenseSummary(
          from: from, to: to, allowedBranchIds: {branchAId});
      expect(sumSummary(summary), 170,
          reason: 'A 100 + بلا فرع 30 + نقدية خزنة A 40؛ B (250+60) مستبعد');

      final detail = await db.getExpensesForReport(
          from: from, to: to, allowedBranchIds: {branchAId});
      expect(sumDetail(detail), 170, reason: 'الجدول لازم يقيس نفس المجموعة');
      expect(detail.any((r) => r['branch_id'] == branchBId), isFalse,
          reason: 'مبالغ فرع B ما تتسربش لمستخدم محصور على A');
      expect(detail.any((r) => r['reference'] == 'V-B'), isFalse,
          reason: 'سند صرف خزنة B ما يظهرش');
    });

    test('scope={} بتفشل مقفولة — الانقلاب الأصلي', () async {
      final summary = await db.getMonthlyExpenseSummary(
          from: from, to: to, allowedBranchIds: <int>{});
      expect(sumSummary(summary), 0,
          reason: 'مستخدم بلا تخصيص فرع كان بيشوف إجمالي الشركة كلها');

      final detail = await db.getExpensesForReport(
          from: from, to: to, allowedBranchIds: <int>{});
      expect(detail, isEmpty);
    });

    test('scope=null لسه على مستوى الشركة (سلوك المدير غير متغيّر)', () async {
      final summary = await db.getMonthlyExpenseSummary(from: from, to: to);
      expect(sumSummary(summary), 480);
      final detail = await db.getExpensesForReport(from: from, to: to);
      expect(sumDetail(detail), 480);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // الخزنةُ بلا فرع — شقّا الاتحاد لازم يعاملا NULL بنفس المعنى
  // ═════════════════════════════════════════════════════════════════════════
  //
  // شقُّ `op_expenses` يقول صراحةً إن الصفَّ بلا فرعٍ **مشترَك**:
  //   `AND (e.branch_id IS NULL OR e.branch_id = ?)`
  // وحصرُ الصلاحية (`_expenseAuthScope`) يقول نفسَ الشيء على الشقّين:
  //   `AND ($col IN (…) OR $col IS NULL)`
  // وحدَه فلترُ الفرع على شقّ الخزنة يقول `AND s.branch_id = ?` — وNULL لا
  // تساوي شيئاً في SQL، فالصفُّ يسقط.
  //
  // وهذا ليس فرضاً نظرياً: الخزنةُ الافتراضية في تجهيزةٍ بفرعٍ واحد
  // `branch_id = NULL` (‏«صندوق الكاشير» في سجلّ البوابة). فأيُّ اختيارِ فرعٍ
  // يُخفي **كلَّ** سندات الصرف النقدية من التقرير بلا أن ينطق.

  group('الخزنةُ بلا فرع تُعامَل مشترَكةً كالمصروف بلا فرع', () {
    /// خزنةُ الإدارة العامة — بلا `branch_id`، وعليها سندُ صرفٍ ٧٠.
    Future<void> seedNoBranchSafePayment() async {
      final safeNoBranch = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'خزنة الإدارة',
              globalId: const Value('gid-safe-exp-null'),
            ),
          );
      await insertSafePayment(
          voucher: 'V-NULL', safeId: safeNoBranch, amount: 70);
    }

    test('الكارت بفلتر فرع A يضمّ سندَ الخزنة بلا فرع', () async {
      await seedNoBranchSafePayment();

      final summary = await db.getMonthlyExpenseSummary(
          from: from, to: to, branchId: branchAId);

      expect(
        sumSummary(summary),
        240,
        reason: 'مصروف A 100 + مصروف بلا فرع 30 + نقدية خزنة A 40 + نقدية '
            'الخزنة بلا فرع 70. لو رجع ١٧٠ فسندُ الخزنة بلا فرع سقط: '
            '`s.branch_id = ?` تُسقط NULL بينما الشقُّ الآخرُ يضمّها.',
      );
    });

    test('والجدولُ يقيس نفسَ المجموعة', () async {
      await seedNoBranchSafePayment();

      final summary = await db.getMonthlyExpenseSummary(
          from: from, to: to, branchId: branchAId);
      final detail = await db.getExpensesForReport(
          from: from, to: to, branchId: branchAId);

      expect(sumDetail(detail), sumSummary(summary),
          reason: 'الكارتُ والجدولُ لازم يتّفقا على معنى NULL أيضاً');
      expect(detail.any((r) => r['reference'] == 'V-NULL'), isTrue,
          reason: 'سندُ الخزنة بلا فرع لازم يظهر في التفصيل');
    });
  });
}

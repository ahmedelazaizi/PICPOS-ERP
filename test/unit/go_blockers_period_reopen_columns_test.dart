// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٣ — أعمدةُ تدقيقِ إعادة فتح الفترة غائبةٌ عن كلِّ قاعدةٍ جديدة
// ═══════════════════════════════════════════════════════════════════════════
//
// هجرةُ v82 تضيف ثلاثةَ أعمدةٍ بـ`ALTER TABLE`:
//   `accounting_periods.reopen_reason` · `reopened_by` · `reopened_at`
// وهي **غيرُ مُعلَنةٍ في صنف `AccountingPeriods`**. و`onCreate` يبني من كيانات
// drift لا من الهجرات، و`onUpgrade` لا يعمل على قاعدةٍ جديدةٍ ومتجاوَزٌ كلّيّاً
// على PostgreSQL — فالأعمدةُ غائبةٌ عن **كلّ** تنصيبة.
//
// و`reopenAccountingPeriodWithAudit` يكتبها بـ`customStatement`، فينهار
// بـ«no such column: reopen_reason». وهو **عينُ** عطبِ `approved_by` الذي
// عولج في هذا المستودع بنفس التعليل — والفارقُ أنّ هذا لم يُنادَ بعد، فكان
// كامناً لا نازفاً.
//
// ⚠️ وPicPos بلا تنصيباتٍ قديمةٍ أصلاً ⇒ «كلُّ قاعدةٍ جديدة» تعني **كلَّ**
// قاعدة.

// `isNull`/`isNotNull` مُعرَّفتان في drift وmatcher معاً — والمقصودُ هنا
// مطابِقُ الاختبار.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'محاسب', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'period_user',
      password: 'test',
      displayName: 'Period User',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  /// ⚠️ سنةٌ بعيدةٌ عمداً: الباذرُ يُنشئ فتراتِ السنة الجارية، و
  /// `(month, year)` عليه قيدُ تفرّد — فبذرةٌ على 2026 تصطدم به.
  var monthSeq = 0;

  Future<int> seedClosedPeriod() async {
    const year = 2099;
    final month = ++monthSeq; // فريدٌ لكلّ نداءٍ داخل الاختبار الواحد
    final fyId = await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '$year-$month',
            startDate: DateTime(year, 1, 1),
            endDate: DateTime(year, 12, 31),
          ),
        );
    return db.into(db.accountingPeriods).insert(
          AccountingPeriodsCompanion.insert(
            fiscalYearId: fyId,
            name: 'فترةُ اختبار $month',
            month: month,
            year: year,
            startDate: DateTime(year, month, 1),
            endDate: DateTime(year, month, 28),
            isClosed: const Value(true),
          ),
        );
  }

  test('أعمدةُ التدقيق الثلاثةُ موجودةٌ على قاعدةٍ جديدةٍ بلا هجرة', () async {
    final rows =
        await db.customSelect("PRAGMA table_info('accounting_periods')").get();
    final cols =
        rows.map((r) => (r.data['name'] as String).toLowerCase()).toSet();

    expect(cols, contains('is_closed'),
        reason: 'مرساة: الاستخراجُ يعمل وقرأ أعمدةَ الجدول فعلاً');
    expect(
      cols,
      containsAll(<String>['reopen_reason', 'reopened_by', 'reopened_at']),
      reason: 'أضافتها هجرةُ v82 وهي غيرُ مُعلَنةٍ في صنف drift — '
          'ما وُجد: ${cols.toList()..sort()}',
    );
  });

  test('إعادةُ فتح الفترة تكتب سببَها وفاعلَها ولا تنهار', () async {
    final periodId = await seedClosedPeriod();

    await db.reopenAccountingPeriodWithAudit(
      periodId: periodId,
      userId: userId,
      reason: 'تصحيحُ قيدٍ مرحَّلٍ خطأً',
    );

    final row = await db
        .customSelect(
          'SELECT is_closed, reopen_reason, reopened_by, reopened_at '
          'FROM accounting_periods WHERE id = ?',
          variables: [Variable<int>(periodId)],
        )
        .getSingle();

    expect(row.data['reopen_reason'], 'تصحيحُ قيدٍ مرحَّلٍ خطأً');
    expect((row.data['reopened_by'] as num?)?.toInt(), userId);
    expect(row.data['reopened_at'], isNotNull,
        reason: 'الطابعُ الزمنيُّ جزءٌ من أثر التدقيق');

    final closed = row.data['is_closed'];
    expect(closed == 0 || closed == false, isTrue,
        reason: 'الفترةُ يجب أن تُفتح فعلاً — لا أن يُكتَب الأثرُ وحدَه');
  });

  test('سببٌ فارغٌ يُرفض — أثرُ التدقيق لا يكون بلا سبب', () async {
    final periodId = await seedClosedPeriod();

    expect(
      () => db.reopenAccountingPeriodWithAudit(
        periodId: periodId,
        userId: userId,
        reason: '   ',
      ),
      throwsA(isA<Exception>()),
    );
  });
}

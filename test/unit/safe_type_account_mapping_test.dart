// سند القبض/الصرف على خزينة بنك أو كليك كان بيتقيّد على الصندوق الرئيسي.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `treasury_dao.dart` كان بيحلّ حساب الخزينة كده:
//
//     if (safe.linkedAccountId != null) → حساب الخزينة
//     cashAccount ??= getAccountByCode('1111')
//
// من غير **أي** احتياطي بحسب نوع الخزينة. والخزائن المزروعة عمرها ما بتتربط
// بحساب (السيدر مبيحطش `linkedAccountId`)، فده المسار الافتراضي مش الاستثناء.
//
// السيناريو: كاشير يعمل سند قبض ٥٠٠٠ من عميل على «الحساب البنكي» —
//   الخزينة:  رصيد خزينة البنك ‎+٥٠٠٠
//   الأستاذ:  مدين ١١١١ **الصندوق الرئيسي** ٥٠٠٠ / دائن العميل ٥٠٠٠
// النقدية في الأستاذ زايدة ٥٠٠٠ والبنك ناقص ٥٠٠٠، والخزينة بتقول العكس.
//
// والـdropdown في `receipt_voucher_dialog.dart:659` بيعرض **كل** الخزائن مش
// الكاش بس، فالمسار قابل للوصول عادي مش حالة نادرة.
//
// ── ليه الخريطة لازم تطابق مسار البيع ───────────────────────────────────────
// `_resolveBranchSafeAccount` (`accounting_autopost_dao.dart:58`) بيقع على
// حساب الغرض بحسب نوع الخزينة. أي انحراف هنا معناه إن **سند القبض النقدي
// بيتقيّد على حساب غير اللي البيع النقدي بيتقيّد عليه** — تناقض في نفس
// الدفتر أسوأ من الباج الأصلي. (المحاولة الأولى في الجلسة دي وجّهت الكاش
// لحساب درج منفصل وكسرت `sales_payment_idempotency_c05_test` بالظبط لده.)
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('kSafeTypeAccountCode', () {
    test('الأنواع التلاتة مغطّاة', () {
      expect(kSafeTypeAccountCode.keys, containsAll(['cash', 'bank', 'click']));
    });

    test('كل نوع على حساب مختلف عن التاني', () {
      expect(kSafeTypeAccountCode.values.toSet().length,
          kSafeTypeAccountCode.length);
    });

    test('كليك مش بيقع على حساب الكاش — ده كان الباج', () {
      // `safeType == 'click'` مش `'bank'`، فالشرط الثنائي القديم كان بيرميه
      // على fallback الكاش.
      expect(
          kSafeTypeAccountCode['click'], isNot(kSafeTypeAccountCode['cash']));
    });

    test('الخريطة مطابقة لأغراض مسار البيع الحي', () {
      expect(kSafeTypeAccountCode['cash'], '1111');
      expect(kSafeTypeAccountCode['bank'], '1113');
      expect(kSafeTypeAccountCode['click'], '1116');
    });
  });

  group('الحسابات موجودة فعلاً في الدليل المزروع', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
    });
    tearDown(() => db.close());

    test('كل كود في الخريطة له حساب', () async {
      for (final e in kSafeTypeAccountCode.entries) {
        expect(await db.getAccountByCode(e.value), isNotNull,
            reason: 'حساب نوع «${e.key}» (${e.value}) مش مزروع — '
                'السند هيقع على الاحتياطي الأخير');
      }
    });

    test('حساب غرض cash هو نفسه ١١١١ — الاتساق مع مسار البيع', () async {
      final byPurpose = await db.getAccountByPurpose('cash');
      final byCode = await db.getAccountByCode(kSafeTypeAccountCode['cash']!);
      expect(byPurpose!.id, byCode!.id);
    });
  });
}

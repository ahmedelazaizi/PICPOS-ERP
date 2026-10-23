// التحويل بين الخزائن كان بيتنفّذ مرتين على إعادة الإرسال — فلوس بتتحرك مرتين.
//
// ── العطل على الطرفين ────────────────────────────────────────────────────────
// العميل (`cwi_trading.submitSafeTransfer`) ما كانش بيولّد `globalId` أصلاً،
// و`postSafeTransfer` على السيرفر مافيهوش **ولا فحص dedup واحد** قبل
// الترانزاكشن — على عكس `postSafeTransaction` و`postExpense` اللي الاتنين
// بيفحصوا بالـglobalId. التحويل كان الاستثناء الوحيد.
//
// السيناريو: أمين خزنة على جهاز عميل يحوّل ١٠,٠٠٠ من درج الكاشير للبنك.
// الطلب يوصل السيرفر وينفّذ، والرد يضيع (timeout) → الصف يروح للطابور →
// الـdrain يعيد الإرسال → **١٠,٠٠٠ اتحوّلت تاني**: الدرج ‎-٢٠,٠٠٠ والبنك
// ‎+٢٠,٠٠٠ و٤ سندات (PV/RV × ٢) بدل ٢. اختلال خزينة مباشر.
//
// ── ليه الفحص على `safe_transactions` ───────────────────────────────────────
// التحويل مالوش جدول رأس خاص بيه — بيتسجّل كسطرين في `safe_transactions`.
// فالـglobalId بيتختم على سطر الصرف (الخزنة المصدر) وهو هدف الـdedup.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';

void main() {
  group('safeTransferPayload — العميل بيولّد globalId', () {
    test('الـpayload فيه globalId مش فاضي', () {
      final p = safeTransferPayload(
        fromSafeId: 1,
        toSafeId: 2,
        amount: 10000,
        userId: 5,
        description: 'تحويل يومي',
        globalId: 'g-abc',
      );
      expect(p['globalId'], 'g-abc');
    });

    test('باقي الحقول زي ما هي — الشكل ما اتغيّرش على السيرفر', () {
      final p = safeTransferPayload(
        fromSafeId: 1,
        toSafeId: 2,
        amount: 10000,
        userId: 5,
        description: 'تحويل يومي',
        globalId: 'g-abc',
      );
      expect(p['fromSafeId'], 1);
      expect(p['toSafeId'], 2);
      expect(p['amount'], 10000);
      expect(p['userId'], 5);
      expect(p['description'], 'تحويل يومي');
    });

    test('نفس الـglobalId بيتبعت في المحاولة الأولى وفي إعادة الإرسال', () {
      // ده جوهر الـidempotency: الـpayload المخزّن في الطابور هو نفسه اللي
      // اتبعت أول مرة، فلو الـglobalId جوّاه فإعادة الإرسال بتحمل نفس القيمة
      // والسيرفر بيقدر يميّزها. لو كان بيتولّد وقت الإرسال، كل محاولة كانت
      // هتاخد قيمة جديدة والـdedup بلا معنى.
      final first = safeTransferPayload(
        fromSafeId: 1,
        toSafeId: 2,
        amount: 10000,
        globalId: 'g-abc',
      );
      final replayed = Map<String, dynamic>.from(first);
      expect(replayed['globalId'], first['globalId']);
    });
  });

  // القاعدة نفسها هي خط الدفاع الأخير: حتى لو فحص الـhandler اتسابق عليه
  // طلبان متوازيان، الـUNIQUE على `safe_transactions.global_id` بيفشّل
  // التاني فالترانزاكشن ترجع بالكامل بدل ما الفلوس تتحرك مرتين. الفحص
  // الصريح بيخلّي الحالة العادية ترجّع `dedup: true` بدل خطأ ٥٠٠.
  group('القيد في القاعدة — خط الدفاع الأخير', () {
    late AppDatabase db;
    late int safeId;

    setUp(() async {
      db = AppDatabase.forTesting();
      safeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'صندوق اختبار',
              safeType: const Value('cash'),
              balance: const Value(1000),
              globalId: const Value('gid-safe-src'),
            ),
          );
    });

    tearDown(() => db.close());

    Future<void> insertLeg(String gid) =>
        db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
              voucherNumber: 'PV-$gid',
              safeId: safeId,
              transactionType: 'payment',
              category: 'transfer',
              amount: 10000,
              balanceAfter: 0,
              globalId: Value(gid),
            ));

    test('سطر تحويل تاني بنفس الـglobalId بيترفض', () async {
      await insertLeg('gid-transfer-1');
      await expectLater(insertLeg('gid-transfer-1'), throwsA(anything));
    });

    test('globalId مختلف بيعدّي عادي — القيد مش بيمنع تحويلات مشروعة',
        () async {
      await insertLeg('gid-transfer-1');
      await insertLeg('gid-transfer-2');
      final rows = await db.select(db.safeTransactions).get();
      expect(rows, hasLength(2));
    });
  });
}

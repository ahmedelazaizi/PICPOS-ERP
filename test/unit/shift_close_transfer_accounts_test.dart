// قيد إقفال الوردية كان بيقيّد **نفس الحساب** مدين ودائن → صافيه صفر.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// السيدر (`database_seeder.dart`) بيزرع الخزائن التلاتة **من غير
// `linkedAccountId`**، فعلى أي تركيبة `safe.linkedAccountId == null` دايماً.
// وساعتها `sourceAccount` و`destAccount` في `treasury_dao.dart:892-898` كانوا
// بيتحسبوا **بنفس التعبير بالحرف**:
//
//     safeType == 'bank' ? purpose('bank') : purpose('cash')
//
// فالسطرين بيطلعوا على نفس الحساب والقيد صافيه صفر — بينما
// `adjustSafeBalance(sId, -actualDrain)` قبلها بيخصم من الخزينة **فعلاً**.
//
// النتيجة: الدرج بيتفضّى والأستاذ ما بيتحركش. محل بيبيع ٥٠٠٠/يوم بيلاقي بعد
// شهر ~١٥٠ ألف وهمية في حساب النقدية والخزينة صفر. والميزانية بتفضل
// «متوازنة» لأن مفيش اختلال — الحركة كلها مش موجودة.
//
// **فرع تاني:** خزينة `click` مش `'bank'` فبتقع على fallback الكاش — قيدها
// كان بيروح على ١١١١ بدل ١١١٦.
//
// ── القرار (المالك، 2026-08-02) ─────────────────────────────────────────────
// الوجهة = **الصندوق الرئيسي** (`purpose('cash')` = ١١١١). وعشان ده يشتغل
// لازم كل خزينة يبقى لها حسابها الخاص كمصدر — وإلا رجعنا لنفس الحساب على
// الطرفين. فالخزائن المزروعة بقت مربوطة: درج الكاشير بحساب الدرج، وخزينة
// البنك بـ١١١٣، وخزينة كليك بـ١١١٦.
//
// ── الحارس ──────────────────────────────────────────────────────────────────
// لو المصدر والوجهة طلعوا نفس الحساب برضه (تركيبة معدَّلة، ربط ناقص)،
// **ما يتكتبش قيد** بدل قيد وهمي صافيه صفر. قيد بصفر بيخفي المشكلة؛ غيابه
// بيسيب فرق ظاهر في المطابقة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('resolveShiftCloseTransferAccounts — المصدر غير الوجهة', () {
    test('خزينة مربوطة: المصدر حسابها والوجهة الصندوق الرئيسي', () {
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: 55,
        safeTypeAccountId: 17,
        mainCashAccountId: 11,
      );
      expect(r.sourceAccountId, 55, reason: 'الربط الصريح بيغلب');
      expect(r.destAccountId, 11);
      expect(r.shouldPost, isTrue);
    });

    test('خزينة مش مربوطة: المصدر حساب نوعها مش نفس الوجهة', () {
      // ده الحال الفعلي على كل تركيبة قبل الإصلاح. الاحتياطي القديم كان بيقع
      // على **نفس** حساب الوجهة فالقيد صافيه صفر؛ الجديد بيقع على حساب النوع
      // (درج الكاشير ١١١٧) فالقيد بيتكتب صح حتى قبل ما الربط يشتغل.
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: null,
        safeTypeAccountId: 17,
        mainCashAccountId: 11,
      );
      expect(r.sourceAccountId, 17);
      expect(r.destAccountId, 11);
      expect(r.shouldPost, isTrue);
    });

    test('لا ربط ولا حساب نوع: مفيش قيد', () {
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: null,
        safeTypeAccountId: null,
        mainCashAccountId: 11,
      );
      expect(r.shouldPost, isFalse);
    });

    test('خزينة مربوطة بنفس حساب الوجهة: مفيش قيد', () {
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: 11,
        safeTypeAccountId: 17,
        mainCashAccountId: 11,
      );
      expect(r.shouldPost, isFalse,
          reason: 'قيد صافيه صفر بيخفي المشكلة بدل ما يوريها');
    });

    test('حساب النوع نفسه = الوجهة: مفيش قيد', () {
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: null,
        safeTypeAccountId: 11,
        mainCashAccountId: 11,
      );
      expect(r.shouldPost, isFalse);
    });

    test('حساب الوجهة مش موجود: مفيش قيد', () {
      final r = resolveShiftCloseTransferAccounts(
        linkedAccountId: 55,
        safeTypeAccountId: 17,
        mainCashAccountId: null,
      );
      expect(r.shouldPost, isFalse);
    });
  });

  group('السيدر بيربط كل خزينة بحسابها', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
    });
    tearDown(() => db.close());

    test('الخزائن المزروعة كلها مربوطة بحسابات مختلفة عن بعضها', () async {
      await db.linkSeededSafesToAccounts();
      final safes = await db.select(db.safes).get();
      expect(safes, isNotEmpty);

      final linked = safes.where((s) => s.linkedAccountId != null).toList();
      expect(linked.length, safes.length,
          reason: 'كل خزينة مزروعة لازم يبقى لها حساب');

      final ids = linked.map((s) => s.linkedAccountId!).toSet();
      expect(ids.length, linked.length,
          reason: 'خزنتين على نفس الحساب معناها قيد تحويل صافيه صفر');
    });

    test('ولا واحدة مربوطة بالصندوق الرئيسي — هو الوجهة مش المصدر', () async {
      await db.linkSeededSafesToAccounts();
      final mainCash = await db.getAccountByPurpose('cash');
      expect(mainCash, isNotNull);

      final safes = await db.select(db.safes).get();
      for (final s in safes) {
        expect(s.linkedAccountId, isNot(mainCash!.id),
            reason: 'خزينة «${s.name}» مربوطة بحساب الوجهة → قيدها هيبقى صفر');
      }
    });

    test('التشغيل مرتين ما بيغيّرش حاجة ولا بيدوس على ربط يدوي', () async {
      await db.linkSeededSafesToAccounts();
      final before = {
        for (final s in await db.select(db.safes).get()) s.id: s.linkedAccountId
      };

      await db.linkSeededSafesToAccounts();
      final after = {
        for (final s in await db.select(db.safes).get()) s.id: s.linkedAccountId
      };

      expect(after, before);
    });
  });
}

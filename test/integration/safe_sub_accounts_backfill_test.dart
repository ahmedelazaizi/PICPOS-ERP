// ═══════════════════════════════════════════════════════════════════════════
// §٣-ب — حسابٌ فرعيٌّ لكلّ خزنة تحت `111` · قرارُ المالك
// ═══════════════════════════════════════════════════════════════════════════
//
// العطب: خزنةٌ بلا `linkedAccountId` تسقط بحسب **نوعها** على حسابٍ واحدٍ
// مشترك (`kSafeTypeAccountCode`: cash→1111 · bank→1113 · click→1116). فكلُّ
// الخزائن النقدية تترحّل على `1111` ولا تُميَّز في الأستاذ: درجُ الكاشير
// والصندوقُ المركزيّ رقمٌ واحدٌ لا ينفصل، ولا سبيلَ لمطابقة رصيد خزنةٍ
// بعينها مع الدفاتر.
//
// والمقيسُ أن `createSafeWithLinkedAccount` **موجودةٌ بالفعل** وتفعل الصواب
// (‏تنشئ `111-NNNNN` وتربطها) منذ v142 — لكنّ **البذرة** لا تمرّ بها:
// `database_seeder.dart` يُدرج «صندوق الكاشير» و«الحساب البنكي» و«صندوق
// تحويل كليك» و«الصندوق الرئيسي» بـ`into(safes).insert` عارياً بلا ربط.
// فكلُّ تنصيبٍ جديدٍ يولد بالعطب كاملاً.
//
// ولأن PicPos لم يُطرح بعد (لا قواعدَ قديمة) فالمطلوب تصميمٌ صحيحٌ لا
// متوافق: إصلاحٌ **متعادل** يمرّ على كلّ خزنةٍ بلا ربطٍ فيمنحها حسابَها.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // دليلُ الحسابات الافتراضيّ — فيه `111` أباً من نوع `view`.
    await db.syncDefaultAccounts();
  });

  tearDown(() async => db.close());

  Future<int> bareSafe(String name, String type) =>
      db.into(db.safes).insert(SafesCompanion.insert(
            name: name,
            safeType: Value(type),
            globalId: Value('gid-$name'),
          ));

  Future<Account?> accountOf(int safeId) async {
    final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
        .getSingleOrNull();
    if (safe?.linkedAccountId == null) return null;
    return (db.select(db.accounts)
          ..where((a) => a.id.equals(safe!.linkedAccountId!)))
        .getSingleOrNull();
  }

  group('الإصلاح يمنح كلَّ خزنةٍ حسابَها', () {
    test('الخزائنُ **المبذورة** تُربط بالإقلاع وحدَه — وهي أصلُ العطب', () async {
      // ⚠️ مقيسٌ لا مفترَض: البذرةُ تُنشئ خزائنَ افتراضيةً (‏صندوق الكاشير ·
      // الحساب البنكي · كليك · الصندوق الرئيسي) بإدراجٍ عارٍ بلا
      // `linkedAccountId`، فكلُّ تنصيبٍ جديدٍ كان يولد بالعطب: كلُّ النقديّ
      // على `1111`.
      //
      // ولا نداءَ يدويٌّ هنا قصداً: المقيسُ أن **الإقلاع** يكفي. لو انفكّ
      // الوصلُ لعاد هذا أحمرَ فوراً.
      final safesAfterStartup = await db.select(db.safes).get();
      expect(safesAfterStartup, isNotEmpty,
          reason: 'البذرةُ تُنشئ خزائنَ افتراضية');
      expect(
        safesAfterStartup.where((s) => s.linkedAccountId == null),
        isEmpty,
        reason: 'الإقلاعُ وحدَه يجب أن يربط كلَّ خزنةٍ مبذورة',
      );

      // ولكلٍّ حسابُها هي — لا حسابٌ مشترك. هذا هو الفرقُ عن `1111`.
      final ids = safesAfterStartup.map((s) => s.linkedAccountId).toSet();
      expect(ids.length, safesAfterStartup.length);

      // وكلُّها تحت أب الخزائن.
      final parent = await db.getAccountByCode('111');
      for (final s in safesAfterStartup) {
        final acc = await accountOf(s.id);
        expect(acc!.parentId, parent!.id, reason: 'خزنة "${s.name}"');
      }
    });

    test('خزنتان نقديتان ⇒ حسابان **مختلفان** تحت 111', () async {
      // هذا هو البلاغُ حرفياً: الاثنتان كانتا تترحّلان على 1111.
      final drawer = await bareSafe('درج الكاشير', 'cash');
      final central = await bareSafe('الصندوق الرئيسي', 'cash');

      await db.linkUnlinkedSafesToSubAccounts();

      final a = await accountOf(drawer);
      final b = await accountOf(central);
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.id, isNot(b!.id), reason: 'حسابان متمايزان لا حسابٌ مشترك');

      // كلاهما تحت `111` مباشرةً.
      final parent = await db.getAccountByCode('111');
      expect(parent, isNotNull);
      expect(a.parentId, parent!.id);
      expect(b.parentId, parent.id);

      // والاسمُ يعكس الخزنةَ كي يراها المستخدمُ موصولةً.
      expect(a.name, 'درج الكاشير');
      expect(b.name, 'الصندوق الرئيسي');

      // والكودُ بصيغة الأب مع لاحقةٍ متسلسلة.
      expect(a.code, startsWith('111-'));
      expect(b.code, startsWith('111-'));
      expect(a.code, isNot(b.code));
    });

    test('البنكُ والكليك يُربطان كذلك — لا النقديّ وحدَه', () async {
      final bank = await bareSafe('الحساب البنكي', 'bank');
      final click = await bareSafe('صندوق تحويل كليك', 'click');

      await db.linkUnlinkedSafesToSubAccounts();

      expect(await accountOf(bank), isNotNull);
      expect(await accountOf(click), isNotNull);
    });

    test('متعادلٌ — تشغيلةٌ ثانيةٌ لا تنشئ شيئاً ولا تغيّر ربطاً', () async {
      final id = await bareSafe('درج الكاشير', 'cash');
      expect(await db.linkUnlinkedSafesToSubAccounts(), greaterThan(0));
      final first = await accountOf(id);

      final countBefore = (await db.select(db.accounts).get()).length;
      expect(await db.linkUnlinkedSafesToSubAccounts(), 0,
          reason: 'الإصلاحُ يعمل كلَّ إقلاع، فلو لم يكن متعادلاً لتكاثرت '
              'الحساباتُ حتى يمتلئ الدليل');
      final countAfter = (await db.select(db.accounts).get()).length;

      expect(countAfter, countBefore);
      expect((await accountOf(id))!.id, first!.id);
    });

    test('خزنةٌ مربوطةٌ سلفاً لا تُلمس', () async {
      final existing = await db.getAccountByCode('1112'); // صندوق العهد
      expect(existing, isNotNull);
      final id = await db.into(db.safes).insert(SafesCompanion.insert(
            name: 'خزنةٌ موصولةٌ يدوياً',
            safeType: const Value('cash'),
            linkedAccountId: Value(existing!.id),
            globalId: const Value('gid-manual'),
          ));

      await db.linkUnlinkedSafesToSubAccounts();
      expect((await accountOf(id))!.id, existing.id,
          reason: 'اختيارُ المستخدم الصريحُ أولى من أيّ إصلاح');
    });

    test('المحذوفةُ ناعماً لا تُمنح حساباً', () async {
      final id = await bareSafe('خزنةٌ مُزالة', 'cash');
      await (db.update(db.safes)..where((s) => s.id.equals(id)))
          .write(SafesCompanion(deletedAt: Value(DateTime(2026, 1, 1))));

      await db.linkUnlinkedSafesToSubAccounts();
      expect(await accountOf(id), isNull,
          reason: 'لا معنى لحسابٍ جديدٍ لخزنةٍ أُزيلت');
    });
  });

  group('الأثرُ في الأستاذ — وهو أصلُ الطلب', () {
    test('سندا قبضٍ على خزنتين ⇒ حسابا نقديةٍ مختلفان في القيد', () async {
      final drawer = await bareSafe('درج الكاشير', 'cash');
      final central = await bareSafe('الصندوق الرئيسي', 'cash');
      await db.linkUnlinkedSafesToSubAccounts();

      await db.createReceiptVoucher(
        amount: 100,
        category: 'other',
        safeId: drawer,
        description: 'قبضٌ على الدرج',
      );
      await db.createReceiptVoucher(
        amount: 250,
        category: 'other',
        safeId: central,
        description: 'قبضٌ على المركزي',
      );

      final drawerAccount = (await accountOf(drawer))!;
      final centralAccount = (await accountOf(central))!;

      // مدينُ كلّ قيدٍ يقع على حساب خزنته هو.
      final drawerDebit = await _debitOn(db, drawerAccount.id);
      final centralDebit = await _debitOn(db, centralAccount.id);

      expect(drawerDebit, 100.0);
      expect(centralDebit, 250.0);

      // ولا شيءَ منهما وقع على `1111` المشترك — وهو ما كان يحدث.
      final shared = await db.getAccountByCode('1111');
      expect(await _debitOn(db, shared!.id), 0.0,
          reason: 'كانت الخزنتان تترحّلان معاً على 1111 فلا تُميَّزان');
    });
  });
}

/// مجموعُ المدين على حسابٍ بعينه في كلّ بنود القيود.
Future<double> _debitOn(AppDatabase db, int accountId) async {
  final rows = await (db.select(db.journalEntryLines)
        ..where((l) => l.accountId.equals(accountId)))
      .get();
  return rows.fold<double>(0.0, (sum, l) => sum + l.debit);
}

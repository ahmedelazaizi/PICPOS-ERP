// إنشاءُ حسابٍ — **وثلاثةُ حقولٍ يعرف النظامُ اشتقاقَها ولا يشتقّها**.
//
// ═══ 🔴 ما قاسته الشيفرة (2026-09-19) ═══
//
// هجرةُ v110 أضافت `account_nature` و`normal_balance` و`level`، **وملأتها
// للقائم بقاعدةٍ صريحة**:
//
//   UPDATE accounts SET normal_balance = 'credit'
//     WHERE account_type IN ('liability','equity','revenue');
//   UPDATE accounts SET level = 1 WHERE parent_id IS NULL;   … وهكذا
//
// فالنظامُ **يعرف** القاعدة. و`createAccount` لا يكتب أيّاً منها، فتقع على
// افتراضات العمود: `'detail'` و`'debit'` و`1`.
//
// ⇒ **كلُّ حسابٍ أُنشئ من الشاشة منذ v110**:
//
// ‏١ — حسابُ إيراداتٍ أو التزاماتٍ طبيعتُه **مدينة** — يناقض قاعدةَ الهجرة
//     نفسِها، فأيُّ قارئٍ يحدّد الإشارةَ من `normal_balance` يعرضه مقلوباً.
// ‏٢ — وابنٌ في العمق الثالث مستواه **١**، فتقريرٌ يجمع بالمستوى يخلطه
//     بالجذور.
// ‏٣ — وحسابٌ أبٌ يبقى `detail` أي **قابلاً للترحيل**، بينما المزروعُ `view`
//     يرفضه حارسُ v110. فيُرحَّل على الأب وعلى أبنائه معاً — ويُعَدّ الرصيدُ
//     مرّتَين في كلّ تجميعٍ هرميّ.
//
// ⚠️ **والقاعدةُ موضعٌ واحدٌ في `domain/models`**: كتابتُها في SQL الهجرة
// وفي الكاتب معاً تجعلهما يفترقان بأوّل نوعٍ يُضاف.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/account_facts.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // ⚠️ الخزائنُ مشدودةٌ إلى الدليل (`safes.linkedAccountId`)، فمسحُ
    //    `accounts` بلا فكِّ الشدّ يسقط بـ787.
    await db
        .update(db.safes)
        .write(const SafesCompanion(linkedAccountId: Value(null)));
    // وكذلك الأطرافُ النظاميّة (J3: «عميل نقدي»/«مورد نقدي») لها حساباتٌ فرعيّة.
    await db
        .update(db.parties)
        .write(const PartiesCompanion(accountId: Value(null)));
    await db.customStatement('DELETE FROM journal_entry_lines');
    await db.customStatement('DELETE FROM account_mappings');
    await db.customStatement('DELETE FROM accounts');
  });

  tearDown(() => db.close());

  Future<Account> read(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  group('🔴 طبيعةُ الرصيد تُشتقُّ من نوع الحساب', () {
    test('الإيراداتُ والالتزاماتُ وحقوقُ الملكية دائنة', () async {
      for (final type in ['revenue', 'liability', 'equity']) {
        final id = await db.createAccount(
          code: 'C-$type',
          name: 'حساب $type',
          accountType: type,
        );
        expect((await read(id)).normalBalance, 'credit',
            reason: '$type طبيعتُه مدينةٌ — يناقض قاعدةَ هجرة v110 نفسِها');
      }
    });

    test('والأصولُ والمصروفاتُ مدينة', () async {
      for (final type in ['asset', 'expense']) {
        final id = await db.createAccount(
          code: 'D-$type',
          name: 'حساب $type',
          accountType: type,
        );
        expect((await read(id)).normalBalance, 'debit');
      }
    });

    test('والقاعدةُ موضعٌ واحدٌ يقرؤه الكاتب', () {
      // مرساةٌ على الوحدة الخالصة — وإلّا صار للقاعدة نسختان.
      expect(normalBalanceFor('revenue'), 'credit');
      expect(normalBalanceFor('asset'), 'debit');
      // ⚠️ نوعٌ غيرُ معروفٍ يقع على «مدين» لا يرمي: الكاتبُ لا يُفشِل إنشاءَ
      //    حسابٍ لأجل حقلٍ مشتقّ.
      expect(normalBalanceFor('something_else'), 'debit');
    });
  });

  group('🔴 والمستوى يُشتقُّ من عمق الأب', () {
    test('الجذرُ مستواه ١ وابنُه ٢ وحفيدُه ٣', () async {
      final root = await db.createAccount(
        code: '1', name: 'الأصول', accountType: 'asset');
      final child = await db.createAccount(
        code: '11', name: 'النقدية', accountType: 'asset', parentId: root);
      final grand = await db.createAccount(
        code: '1101', name: 'الصندوق', accountType: 'asset', parentId: child);

      expect((await read(root)).level, 1);
      expect((await read(child)).level, 2,
          reason: 'الابنُ مستواه ١ — فتقريرٌ يجمع بالمستوى يخلطه بالجذور');
      expect((await read(grand)).level, 3);
    });

    test('وأبٌ لا وجودَ له لا يُسقط الإنشاء', () async {
      // ⚠️ حقلٌ مشتقٌّ لا يُفشِل الكتابة: المفتاحُ الأجنبيُّ يحرس الوجودَ،
      //    وهذا الاشتقاقُ يقع على ١ حين لا يجد.
      final id = await db.createAccount(
        code: 'X', name: 'يتيم', accountType: 'asset', parentId: null);
      expect((await read(id)).level, 1);
    });
  });

  group('🔴 وطبيعةُ الحساب اختيارٌ لا افتراض', () {
    test('الافتراضُ `detail` — والحسابُ يُرحَّل عليه', () async {
      final id = await db.createAccount(
        code: '5101', name: 'إيجار', accountType: 'expense');
      expect((await read(id)).accountNature, 'detail');
    });

    test('🔴 وحسابٌ أبٌ يُنشأ `view` فلا يُرحَّل عليه', () async {
      // 🔴 قبلَه: الأبُ المُنشأُ من الشاشة `detail` بينما المزروعُ `view`.
      //    فيُرحَّل على الأب وعلى أبنائه — ويُعَدّ الرصيدُ مرّتَين في كلّ
      //    تجميعٍ هرميّ، ولا فحصَ اتّزانٍ يمسكه لأنّ القيدَ متّزن.
      final id = await db.createAccount(
        code: '5', name: 'المصروفات', accountType: 'expense',
        accountNature: 'view');
      expect((await read(id)).accountNature, 'view');
    });

    test('والتعديلُ يبدّلها — لحسابٍ لم يُرحَّل عليه', () async {
      final id = await db.createAccount(
        code: '6', name: 'أخرى', accountType: 'expense');
      await db.updateAccount(id, accountNature: 'view');
      expect((await read(id)).accountNature, 'view');
    });

    test('🔴 وحسابٌ عليه سطورُ قيدٍ لا يصير `view`', () async {
      // 🔴 التبديلُ بعد الترحيل يترك سطوراً على حسابٍ يرفضه الحارس: لا
      //    تُعكَس ولا تُعدَّل، والدفترُ يحمل ما يقول النظامُ إنّه ممنوع.
      final id = await db.createAccount(
        code: '7', name: 'مستعمَل', accountType: 'expense');
      // ⚠️ قيدٌ حقيقيٌّ أوّلاً: `entry_id` مفتاحٌ أجنبيٌّ، وصفٌّ مخترَعٌ
      //    يسقط بـ787 قبل أن يُقاس الحارس.
      final entryId = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JV-T1',
              entryDate: DateTime(2026, 9, 19),
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: entryId,
              accountId: id,
              debit: const Value(10),
            ),
          );

      await expectLater(
        db.updateAccount(id, accountNature: 'view'),
        throwsA(isA<Exception>()),
        reason: 'حسابٌ مُرحَّلٌ عليه صار رئيسيّاً — فسطورُه محبوسة',
      );
      expect((await read(id)).accountNature, 'detail');
    });
  });
}

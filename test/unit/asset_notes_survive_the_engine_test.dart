// 🔴 **ملاحظةُ الأصل تُمحى بإعادة التقييم** — وهي حقلُ مستخدمٍ لا خانةُ
//    محرّك.
//
// ═══ العطب ═══
//
// `revalueAsset` تكتب على البطاقة:
//
//     FixedAssetsCompanion(
//       purchasePrice: Value(...),
//       notes: Value('إعادة تقييم — القيمة العادلة: …'),
//     )
//
// و`notes` عمودٌ **يكتبه المستخدم**: `createFixedAsset(notes:)` و
// `updateFixedAsset(notes:)` كلاهما يأخذه من حقلٍ في الحوار. فإعادةُ تقييمٍ
// واحدةٌ تمسح كلَّ ما كتبه — رقمَ الضمان، اسمَ المورّد، مكانَ الجهاز في
// الطابق — بلا سؤالٍ وبلا أثر.
//
// وهو **حيٌّ اليوم**: `fixed_assets_dialogs.dart` ينادي `revalueAsset` من
// شاشة UralCash.
//
// ═══ ولماذا يُصلَح الآن ═══
//
// بطاقةُ الأصل في تصميم المالك `(9)` تجعل «ملاحظات» حقلاً ظاهراً يُحرَّر
// ويُحفَظ بـ«حفظ التعديلات». فما كان عموداً خفيّاً يُمحى صار حقلاً يكتبه
// المستخدمُ ويعود فلا يجده.
//
// ═══ والعلاجُ إضافةٌ لا استبدال ═══
//
// السجلُّ الدائمُ لإعادة التقييم هو **القيد** (`asset_revaluation`) وهو
// يُعرَض في تبويبة «الحركات» من البطاقة. وأثرُ المحرّك في حقلِ نصٍّ حرٍّ
// فتاتُ خبزٍ لا سجلّ — فيُضاف سطراً تحت ما كتبه المستخدم ولا يحلّ محلَّه.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int categoryId;

  Future<String?> notesOf(int assetId) async =>
      (await (db.select(db.fixedAssets)..where((a) => a.id.equals(assetId)))
              .getSingle())
          .notes;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '2026',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ),
        );
    categoryId = await db.createAssetCategory(
      name: 'أجهزةٌ مكتبيّة',
      accountId: (await db.getAccountByCode('1213'))!.id,
      depreciationAccountId: (await db.getAccountByCode('1219'))!.id,
    );
  });

  tearDown(() => db.close());

  Future<int> makeAsset({String? notes}) async => db.createFixedAsset(
        code: 'FA-N1',
        name: 'جهاز حاسوب',
        categoryId: categoryId,
        purchasePrice: 12000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
        notes: notes,
        contraAccountId: (await db.getAccountByCode('2111'))!.id,
      );

  test('⚓ مرساة: الملاحظةُ تُكتَب وتُقرأ أصلاً', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أدناه أخضرَ لو كانت الملاحظةُ لا تُحفَظ
    // من البداية — «غابت بعد التقييم» تُشبه «لم تُكتَب قطّ».
    final id = await makeAsset(notes: 'رقمُ الضمان 77-A · الطابقُ الثالث');
    expect(await notesOf(id), 'رقمُ الضمان 77-A · الطابقُ الثالث');
  });

  test('🔴 وإعادةُ التقييم لا تمحوها', () async {
    final id = await makeAsset(notes: 'رقمُ الضمان 77-A · الطابقُ الثالث');
    await db.revalueAsset(id, newFairValue: 15000);

    final after = await notesOf(id);
    expect(after, contains('رقمُ الضمان 77-A'),
        reason: '🔴 حقلُ المستخدم مُسح ليحلّ محلَّه أثرُ محرّك — والسجلُّ '
            'الدائمُ لإعادة التقييم هو القيدُ لا خانةُ نصٍّ حرّ');
    expect(after, contains('إعادة تقييم'),
        reason: 'وأثرُ المحرّك يبقى — الإصلاحُ إضافةٌ لا حذفُ الطرف الآخر');
  });

  test('وأصلٌ بلا ملاحظةٍ يأخذ أثرَ المحرّك وحدَه بلا أسطرَ فارغة', () async {
    final id = await makeAsset();
    await db.revalueAsset(id, newFairValue: 9000);

    final after = await notesOf(id) ?? '';
    expect(after.trim(), startsWith('إعادة تقييم'),
        reason: 'سطرٌ فارغٌ يتصدّر الملاحظةَ حين لا سابقَ لها');
    expect(after.contains('\n\n'), isFalse);
  });

  test('🔴 وتقييمان متتاليان يتراكمان ولا يتنافيان', () async {
    final id = await makeAsset(notes: 'الأصلُ في الفرع الرئيسي');
    await db.revalueAsset(id, newFairValue: 15000);
    await db.revalueAsset(id, newFairValue: 16000);

    final after = await notesOf(id) ?? '';
    expect(after, contains('الأصلُ في الفرع الرئيسي'));
    expect('إعادة تقييم'.allMatches(after).length, 2,
        reason: 'التقييمُ الثاني محا الأوّلَ — والعدُّ يمسك ما لا يمسكه '
            '`contains`');
  });

  test('وتغييرٌ لا يُذكَر لا يكتب شيئاً', () async {
    // `revalueAsset` ترجع مبكراً حين يقلّ الفرقُ عن قرش — فلا سطرَ يُضاف.
    final id = await makeAsset(notes: 'ملاحظةٌ وحيدة');
    await db.revalueAsset(id, newFairValue: 12000);
    expect(await notesOf(id), 'ملاحظةٌ وحيدة');
  });
}

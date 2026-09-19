// بطاقةُ الأصل — **المسؤولُ يُكتَب، و«كما في» تقرأ لقطةً، والحركاتُ تخصُّ
// الأصلَ وحدَه** (تصميمُ المالك `(9)` و`(10)`).
//
// ═══ ما يُقاس هنا ولماذا ═══
//
// ‏١) **`custodian_user_id` عمودٌ مزروعٌ منذ v174 بلا كاتبٍ ولا قارئ** —
//    مقيسٌ: `grep` على المستودع كلِّه لا يجد إلّا تعريفَ العمود. وبطاقةُ
//    الأصل أوّلُ مَن يكتبه، فيُقاس أنّه يُكتَب **ويُرفَع** (رفعُ العهدة فعلٌ
//    كالإسناد، و`null` وحدَها تعني «لا تلمس» في هذا التوقيع).
//
// ‏٢) **«كما في» لقطةٌ مخزَّنةٌ لا حسابٌ حيّ**: `fixed_assets.
//    accumulated_depreciation` رقمُ اليوم. وسؤالُ «كم كان في ٣٠ يونيو؟»
//    جوابُه صفُّ `asset_depreciations` لذلك الشهر.
//
// ‏٣) 🔴 **والحركاتُ بالرقم والنوع معاً**: `reference_id` رقمٌ مشتركٌ بين كلّ
//    الجداول، فقيدُ فاتورةٍ رقمُها يساوي رقمَ الأصل يحمل نفسَ الرقم —
//    والترشيحُ بالرقم وحدَه يُدخل في بطاقة الأصل قيوداً لا تخصّه وهي تبدو
//    حركاتِه تماماً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int categoryId;
  late int assetId;
  late int userA;
  late int userB;

  Future<FixedAssetData> asset() =>
      (db.select(db.fixedAssets)..where((a) => a.id.equals(assetId)))
          .getSingle();

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
    userA = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'ahmed_c', passwordHash: 'x', displayName: 'أحمد'));
    userB = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'sara_c', passwordHash: 'x', displayName: 'سارة'));
    categoryId = await db.createAssetCategory(
      name: 'أجهزةٌ مكتبيّة',
      accountId: (await db.getAccountByCode('1213'))!.id,
      depreciationAccountId: (await db.getAccountByCode('1219'))!.id,
    );
    // ١٢٠٠٠ على ٣ سنواتٍ = ٣٣٣٫٣٣… شهريّاً — مثالُ التصميم.
    assetId = await db.createFixedAsset(
      code: 'FA-001',
      name: 'جهاز حاسوب',
      categoryId: categoryId,
      purchasePrice: 12000,
      purchaseDate: DateTime(2026, 1, 1),
      usefulLifeYears: 3,
      contraAccountId: (await db.getAccountByCode('2111'))!.id,
    );
  });

  tearDown(() => db.close());

  group('🔴 المسؤولُ عن الأصل', () {
    test('⚓ مرساة: يبدأ فارغاً', () async {
      expect((await asset()).custodianUserId, isNull);
    });

    test('يُسنَد ويُبدَّل', () async {
      await db.updateFixedAsset(assetId, custodianUserId: userA);
      expect((await asset()).custodianUserId, userA);

      await db.updateFixedAsset(assetId, custodianUserId: userB);
      expect((await asset()).custodianUserId, userB);
    });

    test('🔴 وتُرفَع العهدةُ برايةٍ صريحة — لا بـ`null`', () async {
      await db.updateFixedAsset(assetId, custodianUserId: userA);

      // `null` وحدَها تعني «لا تلمس» في هذا التوقيع.
      await db.updateFixedAsset(assetId, name: 'جهاز حاسوب محمول');
      expect((await asset()).custodianUserId, userA,
          reason: 'تعديلُ الاسم رفع العهدةَ عن صاحبها بلا أن يطلب أحدٌ ذلك');

      await db.updateFixedAsset(assetId, clearCustodian: true);
      expect((await asset()).custodianUserId, isNull,
          reason: 'لا سبيلَ لرفع العهدة — والأصلُ يبقى في ذمّة مَن ترك العمل');
    });
  });

  group('🔴 «كما في» تقرأ لقطةً', () {
    test('لا لقطةَ قبل أوّل ترحيل', () async {
      final snaps = await db.getAssetSnapshotsAsOf(DateTime(2026, 6, 30));
      expect(snaps, isEmpty,
          reason: 'أصلٌ بلا صفِّ إهلاكٍ يغيب عن الخريطة — والمنادي يقرؤه '
              'بتكلفته ومجمَّعِ صفر');
    });

    test('والتاريخُ يختار الشهرَ لا آخرَ ما وقع', () async {
      for (final m in [1, 2, 3]) {
        await db.runMonthlyDepreciation(DateTime(2026, m, 28));
      }
      final live = (await asset()).accumulatedDepreciation;
      expect(live, closeTo(1000, 0.01), reason: 'ثلاثةُ أشهرٍ × ٣٣٣٫٣٣');

      final atFeb = await db.getAssetSnapshotsAsOf(DateTime(2026, 2, 28));
      expect(atFeb[assetId]!.accumulated, closeTo(666.67, 0.01),
          reason: '🔴 قراءةُ العمود الحيِّ كانت ستُعيد ١٠٠٠ لشهرِ فبراير');
      expect(atFeb[assetId]!.bookValue, closeTo(11333.33, 0.01));

      final atMar = await db.getAssetSnapshotsAsOf(DateTime(2026, 3, 31));
      expect(atMar[assetId]!.accumulated, closeTo(1000, 0.01));
    });

    test('🔴 والتكلفةُ تُشتقّ من اللقطة لا من العمود الحيّ', () async {
      await db.runMonthlyDepreciation(DateTime(2026, 1, 28));
      // إعادةُ تقييمٍ ترفع `purchase_price` ولا تكتب صفَّ إهلاك.
      await db.revalueAsset(assetId, newFairValue: 20000);

      final snap =
          (await db.getAssetSnapshotsAsOf(DateTime(2026, 1, 31)))[assetId]!;
      expect(snap.cost, closeTo(12000, 0.01),
          reason: 'قراءةُ `purchase_price` الحاليِّ مع مجمَّعٍ قديمٍ تُنتج '
              'قيمةً دفتريّةً لم تقع في أيّ تاريخ');
      expect(snap.cost - snap.accumulated, closeTo(snap.bookValue, 0.01));
    });
  });

  group('🔴 حركاتُ الأصل', () {
    test('الاقتناءُ والإهلاكُ يظهران', () async {
      await db.runMonthlyDepreciation(DateTime(2026, 1, 28));
      final moves = await db.getAssetMovements(assetId);
      final types = moves.map((e) => e.referenceType).toSet();
      expect(types, containsAll(<String>{'fixed_asset', 'asset_depreciation'}));
    });

    test('🔴 وقيدٌ بنفس الرقم ونوعٍ آخرَ لا يدخل البطاقة', () async {
      // قيدُ فاتورةِ مبيعاتٍ رقمُها يساوي رقمَ الأصل — حالةٌ عاديّةٌ تماماً.
      final cash = (await db.getAccountByCode('1111'))!;
      // حسابٌ تفصيليٌّ — الترحيلُ على الرئيسيِّ مرفوضٌ بحارس v110.
      final sales = (await db.getAccountByCode('2111'))!;
      await db.createJournalEntry(
        date: DateTime(2026, 2, 1),
        description: 'فاتورة مبيعات لا تخصّ الأصل',
        lines: [
          JournalLine(accountId: cash.id, debit: 50, credit: 0),
          JournalLine(accountId: sales.id, debit: 0, credit: 50),
        ],
        referenceType: 'sales_invoice',
        referenceId: assetId,
        isAutoPosted: true,
      );

      final moves = await db.getAssetMovements(assetId);
      expect(moves.any((e) => e.referenceType == 'sales_invoice'), isFalse,
          reason: 'الترشيحُ بالرقم وحدَه يُدخل في بطاقة الأصل قيوداً لا '
              'تخصّه — وهي تبدو حركاتِه تماماً');
      expect(moves, isNotEmpty, reason: 'ولم يُفرَّغ الجدولُ بالمرّة');
    });

    test('والاستبعادُ يظهر — وهو آخرُ ما يقع للأصل', () async {
      await db.disposeAsset(assetId,
          disposalValue: 9000, disposalDate: DateTime(2026, 4, 1));
      final moves = await db.getAssetMovements(assetId);
      expect(moves.map((e) => e.referenceType),
          contains('fixed_asset_disposal'));
    });
  });
}

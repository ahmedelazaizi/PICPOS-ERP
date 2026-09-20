// `AssetDisposalsDao` — أوّلُ كاتبٍ لجدول v174، وفرعُه المحاسبيُّ الجديد.
//
// ═══ 🔴 ما يُقاس هنا ولماذا ═══
//
// ‏١) **المسوّدةُ بلا أثر.** زرٌّ يقول «حفظ مسودة» ويُخرج أصلاً من الدفاتر
//    يجعل المستخدمَ يظنّ أنّه أجّل قراراً وقد وقع.
//
// ‏٢) 🔴 **والنقديُّ يحرّك درجاً.** `disposeAsset` القائمةُ تقيّد مدينَ
//    نقديّةٍ على `1111` **ولا تحرّك خزنةً** — فيزيد النقدُ في الأستاذ ولا
//    يزيد في أيّ درج، ويفترق رصيدُ الخزينة عن دفترها من أوّل أصلٍ يُباع.
//
// ‏٣) 🔴 **والآجلُ يُحمّل ذمّةً.** لم يكن له فرعٌ أصلاً: بيعٌ على ذمّة عميلٍ
//    كان يُقيَّد نقداً، فيدخل الدفترَ مالٌ لم يُقبَض ولا يُطالَب به أحد.
//
// ‏٤) 🔴 **وحسابٌ غائبٌ يُسقط الاعتمادَ لا القيدَ وحدَه.** الأصلُ كان يُختَم
//    «مستبعَداً» خارجَ شرطِ الحسابات، فتبقى تكلفتُه ومجمَّعُه في الأستاذ إلى
//    الأبد بلا بلاغ.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> account(String code, String name, String type) =>
      db.into(db.accounts).insert(
            AccountsCompanion.insert(
              code: code,
              name: name,
              accountType: type,
              accountNature: const Value('detail'),
              normalBalance: Value(type == 'asset' ? 'debit' : 'credit'),
              level: const Value(2),
              balance: const Value(0),
              isSystem: const Value(false),
            ),
          );

  /// أصلٌ نشطٌ بفئةٍ مربوطةٍ بحسابَيها.
  Future<({int assetId, int categoryId})> seedAsset({
    double cost = 12000,
    double accum = 2000,
    bool linkAccounts = true,
  }) async {
    final assetAcc = await account('1291', 'أجهزة', 'asset');
    final deprAcc = await account('1391', 'مجمع إهلاك أجهزة', 'asset');
    final categoryId = await db.into(db.assetCategories).insert(
          AssetCategoriesCompanion.insert(
            name: 'أجهزة حاسوب',
            accountId: Value(linkAccounts ? assetAcc : null),
            depreciationAccountId: Value(linkAccounts ? deprAcc : null),
          ),
        );
    final assetId = await db.into(db.fixedAssets).insert(
          FixedAssetsCompanion.insert(
            code: 'FA-001',
            name: 'جهاز حاسوب',
            categoryId: categoryId,
            purchasePrice: cost,
            purchaseDate: DateTime(2025, 1, 1),
            usefulLifeYears: 5,
            accumulatedDepreciation: Value(accum),
          ),
        );
    return (assetId: assetId, categoryId: categoryId);
  }

  Future<int> seedSafe({double balance = 1000}) => db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'خزنة الاختبار',
          balance: Value(balance),
        ),
      );

  Future<int> seedParty() => db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'مشترٍ', isCustomer: const Value(true)),
      );

  Future<List<JournalEntryLine>> linesOf(int assetId) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('fixed_asset_disposal'))
          ..where((e) => e.referenceId.equals(assetId)))
        .get();
    if (entries.isEmpty) return const [];
    final out = <JournalEntryLine>[];
    for (final e in entries) {
      out.addAll(await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(e.id)))
          .get());
    }
    return out;
  }

  Future<int> draft({
    required int assetId,
    String method = 'sale',
    double value = 9500,
    String collection = 'cash',
    int? buyer,
  }) =>
      db.createAssetDisposalRequest(
        assetId: assetId,
        disposalDate: DateTime(2026, 6, 30),
        method: method,
        disposalValue: value,
        collectionMethod: collection,
        reason: 'استبدال الجهاز',
        buyerPartyId: buyer,
      );

  group('🔴 المسوّدةُ بلا أثر', () {
    test('لا قيدَ ولا حركةَ خزنةٍ والأصلُ نشط', () async {
      final a = await seedAsset();
      final id = await draft(assetId: a.assetId);

      final req = await db.getAssetDisposal(id);
      expect(req!.status, 'draft');
      expect(req.disposalNumber, startsWith('ADP'),
          reason: 'رقمُ المستند يُولَّد داخلَ المعاملة — مواصفة ٠٦٦');

      expect(await linesOf(a.assetId), isEmpty,
          reason: '🔴 مسوّدةٌ قيّدت — والمستخدمُ يظنّ أنّه أجّل قراراً وقد وقع');
      final asset = await db.getFixedAssetById(a.assetId);
      expect(asset!.status, 'active');
    });

    test('وطلبٌ ثانٍ مفتوحٌ لنفس الأصل يُرفَض', () async {
      final a = await seedAsset();
      await draft(assetId: a.assetId);
      await expectLater(draft(assetId: a.assetId), throwsA(isA<Exception>()));
    });

    test('ومسوّدةٌ تُلغى ثمّ يُفتَح غيرُها', () async {
      final a = await seedAsset();
      final first = await draft(assetId: a.assetId);
      await db.cancelAssetDisposalRequest(first);
      expect((await db.getAssetDisposal(first))!.status, 'cancelled');
      expect(await draft(assetId: a.assetId), greaterThan(0));
    });
  });

  group('🔴 الاعتمادُ النقديّ', () {
    test('يقيّد ويحرّك الدرجَ معاً', () async {
      final a = await seedAsset();
      final safeId = await seedSafe(balance: 1000);
      final id = await draft(assetId: a.assetId);

      await db.approveAssetDisposal(id, safeId: safeId, approvedBy: null);

      // ‏١) القيدُ متّزن.
      final lines = await linesOf(a.assetId);
      expect(lines, isNotEmpty, reason: '🔴 اعتمادٌ بلا قيد');
      final debit = lines.fold<double>(0, (s, l) => s + l.debit);
      final credit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debit, closeTo(credit, 0.001));
      // مدين: مجمَّعٌ ٢٠٠٠ + نقديّةٌ ٩٥٠٠ + خسارةٌ ٥٠٠ = ١٢٠٠٠ = التكلفة.
      expect(debit, closeTo(12000, 0.001));

      // ‏٢) 🔴 والدرجُ تحرّك فعلاً.
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      expect(safe!.balance, closeTo(10500, 0.001),
          reason: '🔴 النقدُ زاد في الأستاذ ولم يزد في الدرج — ويفترق رصيدُ '
              'الخزينة عن دفترها من أوّل أصلٍ يُباع');

      final txns = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('asset_disposal')))
          .get();
      expect(txns, hasLength(1));
      expect(txns.single.amount, 9500);

      // ‏٣) والأصلُ خرج بوسمِ **بيع**.
      final asset = await db.getFixedAssetById(a.assetId);
      expect(asset!.status, 'sold',
          reason: '🔴 `sold` مقروءٌ في سبعة مواضعَ ولا كاتبَ له — فكلُّ مبيعٍ '
              'كان يُعرَض «إعدام»');
      expect(asset.disposalValue, 9500);

      expect((await db.getAssetDisposal(id))!.status, 'approved');
    });

    test('🔴 ويقيّد على حساب الخزنة المرتبط لا على `1111` عمياء', () async {
      final a = await seedAsset();
      final linked = await account('1119', 'خزنة الفرع', 'asset');
      final safeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'خزنة الفرع',
              balance: const Value(0),
              linkedAccountId: Value(linked),
            ),
          );
      final id = await draft(assetId: a.assetId);
      await db.approveAssetDisposal(id, safeId: safeId);

      final lines = await linesOf(a.assetId);
      expect(lines.where((l) => l.accountId == linked && l.debit == 9500),
          hasLength(1),
          reason: '🔴 قيدٌ على الصندوق الرئيسيِّ يَنسب المالَ إلى درجٍ لم '
              'يدخله');
    });

    test('وبلا خزنةٍ يُرفَض الاعتماد', () async {
      final a = await seedAsset();
      final id = await draft(assetId: a.assetId);
      await expectLater(
          db.approveAssetDisposal(id, safeId: null), throwsA(isA<Exception>()));
      expect((await db.getFixedAssetById(a.assetId))!.status, 'active');
    });
  });

  group('🔴 الاعتمادُ الآجل', () {
    test('يُحمّل ذمّةَ المشتري ولا يحرّك درجاً', () async {
      final a = await seedAsset();
      final buyer = await seedParty();
      final safeId = await seedSafe(balance: 1000);
      final id = await draft(
          assetId: a.assetId, collection: 'credit', buyer: buyer);

      await db.approveAssetDisposal(id, safeId: safeId);

      final party = await (db.select(db.parties)..where((p) => p.id.equals(buyer)))
          .getSingleOrNull();
      expect(party!.balance, closeTo(9500, 0.001),
          reason: '🔴 ذمّةٌ في الأستاذ وحدَها لا تُطالِب أحداً — الرصيدُ هو '
              'ما تقرؤه كشوفُ الحساب وحدُّ الائتمان');

      final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      expect(safe!.balance, closeTo(1000, 0.001),
          reason: '🔴 الآجلُ حرّك درجاً لم يدخله مال');
      expect(
          await (db.select(db.safeTransactions)
                ..where((t) => t.category.equals('asset_disposal')))
              .get(),
          isEmpty);

      final lines = await linesOf(a.assetId);
      expect(lines.fold<double>(0, (s, l) => s + l.debit),
          closeTo(lines.fold<double>(0, (s, l) => s + l.credit), 0.001));
    });

    test('وبلا مشترٍ مسجَّلٍ يُرفَض عند الحفظ أصلاً', () async {
      final a = await seedAsset();
      await expectLater(
        draft(assetId: a.assetId, collection: 'credit', buyer: null),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('🔴 الإعدامُ والتبرّع', () {
    test('خسارةُ القيمة الدفتريّة كلِّها بلا نقدٍ ولا ذمّة', () async {
      final a = await seedAsset();
      final id = await draft(assetId: a.assetId, method: 'scrap', value: 0);
      await db.approveAssetDisposal(id);

      final lines = await linesOf(a.assetId);
      final debit = lines.fold<double>(0, (s, l) => s + l.debit);
      expect(debit, closeTo(lines.fold<double>(0, (s, l) => s + l.credit), 0.001));
      // مدين: مجمَّعٌ ٢٠٠٠ + خسارةٌ ١٠٠٠٠ = ١٢٠٠٠.
      expect(debit, closeTo(12000, 0.001));

      expect(
          await (db.select(db.safeTransactions)
                ..where((t) => t.category.equals('asset_disposal')))
              .get(),
          isEmpty);

      expect((await db.getFixedAssetById(a.assetId))!.status, 'disposed');
    });

    test('وقيمةٌ على إعدامٍ تُرفَض عند الحفظ', () async {
      final a = await seedAsset();
      await expectLater(
        draft(assetId: a.assetId, method: 'scrap', value: 500),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('🔴 الحسابُ الغائبُ يُسقط الاعتمادَ كلَّه', () {
    test('فئةٌ بلا حسابَين ⇒ يُرمى ولا يُختَم الأصل', () async {
      final a = await seedAsset(linkAccounts: false);
      final safeId = await seedSafe();
      final id = await draft(assetId: a.assetId);

      await expectLater(
        db.approveAssetDisposal(id, safeId: safeId),
        throwsA(isA<Exception>()),
      );

      // 🔴 الأصلُ كان يُختَم «مستبعَداً» خارجَ شرطِ الحسابات، فتبقى تكلفتُه
      //    ومجمَّعُه في الأستاذ إلى الأبد ولا شيءَ يبلّغ.
      expect((await db.getFixedAssetById(a.assetId))!.status, 'active');
      expect((await db.getAssetDisposal(id))!.status, 'draft');
      expect(await linesOf(a.assetId), isEmpty);
    });
  });

  group('دورةُ الحياة', () {
    test('🔴 ولا يُعتمَد طلبٌ مرّتين', () async {
      final a = await seedAsset();
      final safeId = await seedSafe();
      final id = await draft(assetId: a.assetId);
      await db.approveAssetDisposal(id, safeId: safeId);

      // 🔴 اعتمادٌ ثانٍ يقيّد التكلفةَ والمجمَّعَ مرّةً أخرى — والقيدُ متّزنٌ
      //    فلا فحصَ اتّزانٍ يمسكه.
      await expectLater(db.approveAssetDisposal(id, safeId: safeId),
          throwsA(isA<Exception>()));
      expect(await linesOf(a.assetId), hasLength(greaterThan(0)));
      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('fixed_asset_disposal'))
            ..where((e) => e.referenceId.equals(a.assetId)))
          .get();
      expect(entries, hasLength(1), reason: '🔴 قيدان لاستبعادٍ واحد');
    });

    test('🔴 وطلبٌ ملغًى لا يُعتمَد — وأصلُه ما زال نشطاً فلا شيءَ يمنعه',
        () async {
      // 🔴 **هذه الحالةُ نجت من طفرةٍ حتى كُتبت.** فحصُ «الأصلُ نشط» يمسك
      //    الاعتمادَ المكرَّرَ وحدَه — أمّا الملغى فأصلُه **نشطٌ فعلاً**،
      //    فبلا فحصِ حالةِ الطلب يُعتمَد مستندٌ أُلغي ويخرج الأصلُ بقيدٍ
      //    لا مستندَ ساريَ له.
      final a = await seedAsset();
      final safeId = await seedSafe();
      final id = await draft(assetId: a.assetId);
      await db.cancelAssetDisposalRequest(id);

      await expectLater(db.approveAssetDisposal(id, safeId: safeId),
          throwsA(isA<Exception>()));
      expect((await db.getFixedAssetById(a.assetId))!.status, 'active');
      expect(await linesOf(a.assetId), isEmpty);
      expect((await db.getAssetDisposal(id))!.status, 'cancelled');
    });

    test('وطلبٌ مُعتمَدٌ لا يُعدَّل ولا يُلغى', () async {
      final a = await seedAsset();
      final safeId = await seedSafe();
      final id = await draft(assetId: a.assetId);
      await db.approveAssetDisposal(id, safeId: safeId);

      await expectLater(
        db.updateAssetDisposalRequest(
          id: id,
          disposalDate: DateTime(2026, 7, 1),
          method: 'sale',
          disposalValue: 1,
          collectionMethod: 'cash',
          reason: 'تغيير',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
          db.cancelAssetDisposalRequest(id), throwsA(isA<Exception>()));
    });

    test('وأصلٌ استُبعد لا يُطلَب استبعادُه ثانيةً', () async {
      final a = await seedAsset();
      final safeId = await seedSafe();
      final first = await draft(assetId: a.assetId);
      await db.approveAssetDisposal(first, safeId: safeId);
      await expectLater(draft(assetId: a.assetId), throwsA(isA<Exception>()));
    });
  });

  test('والأرباحُ تُقيَّد دائنةً حين يفوق الثمنُ الدفتريّة', () async {
    final a = await seedAsset(cost: 12000, accum: 11000);
    final safeId = await seedSafe();
    final id = await draft(assetId: a.assetId, value: 2000);
    await db.approveAssetDisposal(id, safeId: safeId);

    final gainAcc = await db.getAccountByCode('4314');
    final lines = await linesOf(a.assetId);
    expect(
      lines.where((l) => l.accountId == gainAcc!.id && l.credit == 1000),
      hasLength(1),
      reason: 'ربحُ ١٠٠٠ = ٢٠٠٠ ثمناً − ١٠٠٠ دفتريّة',
    );
  });
}

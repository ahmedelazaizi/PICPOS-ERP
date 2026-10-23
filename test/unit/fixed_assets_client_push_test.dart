// v166 / المرحلة ٢ — الأصولُ الثابتة: العميلُ يُرسل الحدثَ ولا يُرحّل.
//
// ═══ العطبان اللذان يمنعهما هذا الملفّ ═══
//
// 🔴 **١) قيدُ اقتناءٍ مضاعف.** مفتاحُ إزالة تكرار القيد المُرحَّل تلقائيّاً
// `(referenceType, referenceId)`، و`referenceId` هنا رقمُ الأصل **المحلّيّ**
// الذي يخالف رقمَه على الخادم. فترحيلُ الطرفين يُظهر الأصلَ في الأستاذ بضعف
// قيمته، ولا يمسك ذلك تكرارٌ لأنّ المفتاحين مختلفان.
//
// 🔴 **٢) إهلاكُ شهرٍ مضاعف.** الترحيلُ دفعةٌ على كلّ أصلٍ نشط، ومفتاحُ
// التخطّي `(assetId, periodDate)` يحمي القاعدةَ الواحدةَ لا الاثنتين. فجهازان
// يشغّلانه لنفس الشهر يُنتجان مجموعتَي قيودٍ كاملتَين على الخادم.
//
// ═══ ولماذا مرساةٌ موجبةٌ في الآخر ═══
//
// «لم يُرحَّل قيدٌ» تمرّ أيضاً لو كانت التجهيزةُ ناقصةً — حسابٌ غيرُ مهيَّأ
// يجعل الوضعَ المستقلَّ نفسَه لا يُرحّل. فالفحصُ الأخيرُ يشترط أنّ المستقلَّ
// **يُرحّل فعلاً**، وبدونه كلُّ فحصٍ قبله بلا معنى.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';

class _RecordingClient implements SyncInterceptor {
  int assetCalls = 0;
  int depreciationCalls = 0;
  Map<String, dynamic>? assetDoc;
  Map<String, dynamic>? depreciationReq;

  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  Future<void> submitFixedAssetCreate(Map<String, dynamic> doc) async {
    assetCalls++;
    assetDoc = doc;
  }

  @override
  Future<void> submitAssetDepreciationRun(Map<String, dynamic> req) async {
    depreciationCalls++;
    depreciationReq = req;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int categoryId;

  Future<int> createAsset({String code = 'FA-1'}) => db.createFixedAsset(
        code: code,
        name: 'ثلاجةُ عرض',
        categoryId: categoryId,
        purchasePrice: 12000,
        purchaseDate: DateTime(2026, 1, 15),
        usefulLifeYears: 5,
      );

  Future<List<JournalEntryData>> entriesOf(String refType) =>
      (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals(refType)))
          .get();

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final assetAcc = await db.getAccountByCode('1213'); // الآلات والمعدات
    final accumAcc = await db.getAccountByCode('1219'); // مجمع إهلاك الآلات
    categoryId = await db.createAssetCategory(
      name: 'أجهزةُ تبريد',
      accountId: assetAcc!.id,
      depreciationAccountId: accumAcc!.id,
    );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  test('الفئةُ تحمل هويّةً عند الإنشاء', () async {
    final cat = await (db.select(db.assetCategories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingle();
    expect(cat.globalId, isNotNull,
        reason: 'فئةٌ بلا هويّةٍ لا تُدفَع ولا تُدمَج — وكلُّ أصلٍ فيها '
            'يُردّ من الخادم.');
  });

  group('اقتناءُ أصلٍ من عميل', () {
    late _RecordingClient client;
    late int assetId;

    setUp(() async {
      client = _RecordingClient();
      SyncInterceptor.instance = client;
      assetId = await createAsset();
    });

    test('الصفُّ أُنشئ محلّيّاً كذاكرةٍ مؤقّتة', () async {
      final asset = await db.getFixedAssetById(assetId);
      expect(asset, isNotNull);
      expect(asset!.globalId, isNotNull);
    });

    test('🔴 ولا قيدَ اقتناءٍ رُحِّل محلّيّاً', () async {
      expect(
        await entriesOf('fixed_asset'),
        isEmpty,
        reason: 'العميلُ رحّل قيدَ اقتناء ⇒ الخادمُ سيُرحّل ثانياً، '
            'ومفتاحا الإزالة مختلفان فلا يمسكهما شيء: الأصلُ بضعف قيمته '
            'في الأستاذ.',
      );
    });

    test('والمستندُ أُرسل بهويّاتٍ لا بأرقام', () async {
      expect(client.assetCalls, 1);
      final doc = client.assetDoc!;
      final asset = await db.getFixedAssetById(assetId);

      expect(doc['globalId'], asset!.globalId,
          reason: 'هويّةٌ مختلفةٌ عن الصفّ المحلّيّ ⇒ صفّان لأصلٍ واحد '
              'عند سحب الدلتا.');
      expect(doc['linkedAccountGlobalId'], isNotNull,
          reason: 'بلا هويّةِ الحساب الفرعيّ يسكّ الخادمُ حساباً ثانياً '
              'لنفس الأصل.');

      final cat = doc['category'] as Map<String, dynamic>?;
      expect(cat, isNotNull,
          reason: 'الفئةُ تُرسَل كاملةً: فئةٌ أنشأها هذا الجهازُ لا وجودَ '
              'لها على الخادم، فإرسالُ معرّفها وحدَه يردّ الأصلَ أبداً.');
      expect(cat!['globalId'], isNotNull);
      expect(cat['name'], 'أجهزةُ تبريد');
    });
  });

  group('ترحيلُ الإهلاك من عميل', () {
    late _RecordingClient client;

    setUp(() async {
      // أصلٌ قائمٌ من قبلُ — أُنشئ في الوضع المستقلّ كي تكون التجهيزةُ واقعيّة.
      await createAsset(code: 'FA-SEED');
      client = _RecordingClient();
      SyncInterceptor.instance = client;
    });

    test('🔴 يُطلَب ولا يُحسَب', () async {
      final count = await db.runMonthlyDepreciation(DateTime(2026, 2, 1));

      expect(count, 0, reason: 'هذا الجهازُ لم يُرحّل شيئاً، فالصفرُ صادق.');
      expect(client.depreciationCalls, 1);
      expect(
        await entriesOf('asset_depreciation'),
        isEmpty,
        reason: 'العميلُ رحّل إهلاكاً ⇒ جهازان لنفس الشهر يُنتجان مجموعتَي '
            'قيودٍ كاملتَين على الخادم؛ ومفتاحُ التخطّي '
            '`(assetId, periodDate)` يحمي قاعدةً واحدةً لا اثنتين.',
      );
      expect(
        await db.select(db.assetDepreciations).get(),
        isEmpty,
        reason: 'صفُّ إهلاكٍ محلّيٌّ بلا قيدٍ يجعل بطاقةَ الأصل تخالف الأستاذ.',
      );
    });

    test('ويُرسَل التاريخُ لا قائمةُ الأصول', () async {
      await db.runMonthlyDepreciation(DateTime(2026, 2, 1));
      final req = client.depreciationReq!;
      expect(req['periodDate'], isNotNull);
      expect(req.containsKey('assets'), isFalse,
          reason: 'قائمةُ أصولِ العميل قد تنقص ما لم يصله بعد، فترحيلُها '
              'يُنتج شهراً ناقصاً على الخادم.');
    });
  });

  test('⚓ مرساة: الوضعُ المستقلُّ ما زال يُرحّل الاقتناءَ والإهلاك', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أعلاه أخضرَ لو كانت الحساباتُ غيرَ
    // مهيّأةٍ فلم يُرحَّل شيءٌ أصلاً — «لا شيء» يُشبه «مُنِع».
    SyncInterceptor.instance = null;
    await createAsset(code: 'FA-ANCHOR');

    expect(await entriesOf('fixed_asset'), isNotEmpty,
        reason: 'المستقلُّ لا يُرحّل الاقتناءَ ⇒ فحصُ المنعِ أعلاه بلا معنى.');

    final count = await db.runMonthlyDepreciation(DateTime(2026, 3, 1));
    expect(count, greaterThan(0));
    expect(await entriesOf('asset_depreciation'), isNotEmpty,
        reason: 'المستقلُّ لا يُرحّل الإهلاكَ ⇒ فحصُ المنعِ أعلاه بلا معنى.');
  });
}

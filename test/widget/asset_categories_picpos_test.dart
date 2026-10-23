// «فئات الأصول» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **الشاشةُ كاتبةٌ لا عارضة.** تبويبةُ «الفئات» التي خرجت منها كانت
//    جدولاً للقراءة وحدَه، وحوارا الإنشاء والتعديل `part` من شاشة UralCash
//    لا يبلغهما الفورك. فلا فئةَ تُنشأ في PicPos — و`createFixedAsset`
//    تشترط `categoryId`.
//
// ‏٢) 🔴 **والحساباتُ المعروضةُ تفصيليّةٌ نشطةٌ وحدَها.** قيدُ الاقتناء
//    يُرحَّل على حساب الفئة، والمحرّكُ يرفض الترحيلَ على حسابٍ رئيسيّ. فحسابٌ
//    رئيسيٌّ في الفئة = فئةٌ لا يُسجَّل تحتها أصلٌ أبداً، والرفضُ يقع في آخر
//    نموذجِ الأصل الطويل.
//
// ‏٣) 🔴 **والعمرُ بالشهور والتحويلُ موضعٌ واحد.** ٣٠ شهراً ٢٫٥ سنةٍ لا ٣ —
//    والتقريبُ يُطيل العمرَ سدسَه ويخفّض القسطَ بنفس النسبة.
//
// ‏٤) **وسببُ منعِ الحفظ يُقال.** زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/fixed_assets_repository.dart';
import 'package:picpos_erp/presentation/fixed_assets_picpos/screens/asset_categories_picpos_screen.dart';

db.AssetCategory _cat({
  required int id,
  required String name,
  double life = 7,
  String method = 'straight_line',
  int? accountId = 100,
  int? deprAccountId = 200,
}) =>
    db.AssetCategory(
      id: id,
      name: name,
      defaultUsefulLife: life,
      defaultDepreciationMethod: method,
      accountId: accountId,
      depreciationAccountId: deprAccountId,
      rowVersion: 0,
    );

final _categories = [
  _cat(id: 10, name: 'أجهزة تبريد'),
  // 🔴 فئةٌ ناقصةُ الربط — لا يُسجَّل تحتها أصلٌ أبداً وتبدو سليمةً تماماً.
  _cat(id: 11, name: 'آلات ومعدات', deprAccountId: null),
];

db.FixedAssetData _asset(int id, int categoryId) => db.FixedAssetData(
      id: id,
      code: 'AST-00$id',
      name: 'أصل $id',
      categoryId: categoryId,
      purchasePrice: 1000,
      purchaseDate: DateTime(2024, 1, 1),
      usefulLifeYears: 5,
      salvageValue: 0,
      depreciationMethod: 'straight_line',
      accumulatedDepreciation: 0,
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      rowVersion: 0,
    );

db.Account _account(
  int id,
  String code,
  String name, {
  String nature = 'detail',
  bool active = true,
}) =>
    db.Account(
      id: id,
      code: code,
      name: name,
      accountType: 'asset',
      accountNature: nature,
      normalBalance: 'debit',
      level: 2,
      balance: 0,
      isSystem: false,
      isActive: active,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

final _accounts = [
  _account(100, '1211', 'أجهزة'),
  _account(200, '1311', 'مجمع إهلاك أجهزة'),
  // 🔴 حسابٌ رئيسيٌّ — يُرفَض الترحيلُ عليه، فلا يُعرَض أصلاً.
  _account(12, '12', 'الأصول الثابتة', nature: 'view'),
  // وحسابٌ موقوفٌ يُختار اليومَ ويُرفَض غداً.
  _account(999, '1219', 'أجهزة قديمة', active: false),
];

class _FakeAssetsRepo implements IFixedAssetsRepository {
  _FakeAssetsRepo();

  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> updated = [];

  @override
  Stream<List<db.AssetCategory>> watchAssetCategories() =>
      Stream.value(_categories);

  @override
  Stream<List<db.FixedAssetData>> watchFixedAssets() =>
      Stream.value([_asset(1, 10), _asset(2, 10)]);

  @override
  Future<void> createAssetCategory({
    required String name,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
    int? accountId,
    int? depreciationAccountId,
  }) async {
    created.add({
      'name': name,
      'life': defaultUsefulLife,
      'method': defaultDepreciationMethod,
      'accountId': accountId,
      'deprAccountId': depreciationAccountId,
    });
  }

  @override
  Future<void> updateAssetCategoryById(
    int id, {
    required String name,
    int? accountId,
    int? depreciationAccountId,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
  }) async {
    updated.add({'id': id, 'name': name, 'life': defaultUsefulLife});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Stream<List<db.Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  _FakeAssetsRepo? repo,
  List<String> perms = const ['assets_view', 'assets_manage'],
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixedAssetsRepositoryProvider
            .overrideWithValue(repo ?? _FakeAssetsRepo()),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: AssetCategoriesPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// يبني اللوحَ وحدَه — أدقُّ من قيادته عبر الشاشة، ويقيس ما يخرج منه.
Future<List<AssetCategorySave>> _pumpPanel(
  WidgetTester tester, {
  AssetCategoryValue? value,
  List<AccountOption> accounts = const [
    (id: 100, code: '1211', name: 'أجهزة'),
    (id: 200, code: '1311', name: 'مجمع إهلاك أجهزة'),
  ],
}) async {
  final saved = <AssetCategorySave>[];
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserPermissionsProvider
          .overrideWith((ref) async => const ['assets_manage']),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AssetCategoryPanel(
            value: value,
            accounts: accounts,
            onClose: () {},
            onSave: (v) async => saved.add(v),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  group('الجدولُ والعدّادات', () {
    testWidgets('يعرض الفئاتِ وأعمارَها بالشهور', (tester) async {
      await _pump(tester);
      expect(find.text('فئات الأصول'), findsWidgets);
      expect(find.text('أجهزة تبريد'), findsOneWidget);
      // ٧ سنواتٍ = ٨٤ شهراً — والتصميمُ يعرض الشهور.
      expect(find.text('٨٤ شهراً'), findsWidgets);
      await _teardownTree(tester);
    });

    testWidgets('🔴 والفئةُ ناقصةُ الربطِ تُعَدّ وتُقال', (tester) async {
      await _pump(tester);
      expect(find.text('ناقصةُ الربط'), findsOneWidget);
      expect(find.text('— غير مربوط'), findsWidgets,
          reason: '🔴 فئةٌ بلا حسابٍ لا يُسجَّل تحتها أصلٌ أبداً — والرفضُ '
              'يقع في آخرِ نموذجٍ طويلٍ بعد أن مُلئ');
      await _teardownTree(tester);
    });

    testWidgets('وفئةٌ بلا أصولٍ تُقال صراحةً', (tester) async {
      await _pump(tester);
      expect(find.text('بلا أصول على الدفاتر'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('🔴 اللوحُ يكتب', () {
    testWidgets('«فئة جديدة» تفتح لوحاً فارغاً', (tester) async {
      await _pump(tester);
      expect(find.text('فئة جديدة'), findsOneWidget);
      await tester.tap(find.text('فئة جديدة'));
      await tester.pumpAndSettle();
      expect(find.text('حفظ الفئة'), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('ونقرُ صفٍّ يفتح تعديلَه', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('أجهزة تبريد'));
      await tester.pumpAndSettle();
      expect(find.text('تعديل الفئة'), findsOneWidget);
      expect(find.text('حفظ التعديل'), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('واللوحُ يُخرج ما كُتب فيه حرفاً', (tester) async {
      final saved = await _pumpPanel(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'اسم الفئة'), 'عدد وأدوات');
      await tester.enterText(
          find.widgetWithText(TextField, 'العمر الافتراضي (شهراً)'), '30');
      // الحسابان يُختاران من المنتقي — والبحثُ برقم الحساب.
      await _pickAccount(tester, 'حساب الأصل', '1211');
      await _pickAccount(tester, 'حساب مجمع الإهلاك', '1311');
      await tester.tap(find.text('حفظ الفئة'));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.usefulLifeMonths, 30);
      expect(saved.single.accountId, 100);
      expect(saved.single.depreciationAccountId, 200);
      await _teardownTree(tester);
    });

    // 🔴 **والتحويلُ يُقاس عند المستودع لا عند اللوح**: اللوحُ يعطي شهوراً
    //    والعمودُ سنواتٌ كسريّة. و٣٠ شهراً تمرّ كما هي = إهلاكٌ على ثلاثين
    //    سنةً بدل سنتَين ونصف: القسطُ جزءٌ من اثنَي عشرَ ممّا يجب، **والقيدُ
    //    متّزنٌ على الرقم الخاطئ** فلا فحصَ اتّزانٍ يمسكه.
    testWidgets('🔴 والمستودعُ يستقبل سنواتٍ كسريّةً لا شهوراً',
        (tester) async {
      final repo = _FakeAssetsRepo();
      await _pump(tester, repo: repo);
      await tester.tap(find.text('فئة جديدة'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'اسم الفئة'), 'عدد وأدوات');
      await tester.enterText(
          find.widgetWithText(TextField, 'العمر الافتراضي (شهراً)'), '30');
      await _pickAccount(tester, 'حساب الأصل', '1211');
      await _pickAccount(tester, 'حساب مجمع الإهلاك', '1311');
      await tester.tap(find.text('حفظ الفئة'));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1),
          reason: '🔴 لا كاتبَ لفئة الأصول في PicPos — و`createFixedAsset` '
              'تشترط `categoryId`');
      expect(repo.created.single['life'], 2.5,
          reason: '🔴 ٣٠ شهراً ٢٫٥ سنةٍ — والكسرُ يبقى كسراً');
      // ⚠️ رسالةُ النجاح مؤقّتٌ مفتوح — تُستنفَد قبل تفكيك الشجرة وإلّا
      //    سقط الاختبارُ على «A Timer is still pending».
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await _teardownTree(tester);
    });

    testWidgets('🔴 وسببُ المنع يُقال ولا يُبتلَع', (tester) async {
      await _pumpPanel(tester);
      // بلا اسمٍ: السببُ الأوّل.
      expect(find.text('اكتب اسم الفئة.'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'اسم الفئة'), 'عدد وأدوات');
      await tester.pumpAndSettle();
      expect(find.textContaining('اختر حساب الأصل'), findsWidgets,
          reason: '🔴 اشتراطُ الحسابَين هو Feature 050 نفسُها');

      final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'حفظ الفئة'));
      expect(save.onPressed, isNull,
          reason: 'زرٌّ يُقبَل وشرطُه ناقصٌ يكتب صفّاً لا يُستعمَل');
      await _teardownTree(tester);
    });

    testWidgets('🔴 والحساباتُ المعروضةُ تفصيليّةٌ نشطةٌ وحدَها',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('فئة جديدة'));
      await tester.pumpAndSettle();

      // فتحُ قائمة الاقتراحات بلا نصٍّ يعرض أوائلَ الخيارات.
      await tester.tap(find.widgetWithText(TextField, 'حساب الأصل'));
      await tester.enterText(
          find.widgetWithText(TextField, 'حساب الأصل'), '12');
      await tester.pumpAndSettle();

      expect(find.text('1211 - أجهزة'), findsWidgets);
      expect(find.text('12 - الأصول الثابتة'), findsNothing,
          reason: '🔴 حسابٌ رئيسيٌّ في الفئة = فئةٌ لا يُسجَّل تحتها أصلٌ '
              'أبداً — والمحرّكُ يرفض الترحيلَ عليه');
      expect(find.text('1219 - أجهزة قديمة'), findsNothing,
          reason: 'حسابٌ موقوفٌ يُختار اليومَ ويُرفَض غداً');
      await _teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('الشاشةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await _pump(tester, width: w);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('أجهزة تبريد'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'اللوحُ الجانبيُّ فاض عند $w');
        await _teardownTree(tester);
      });
    }
  });
}

/// يكتب في حقل الحساب ثمّ يختار أوّلَ اقتراحٍ يطابق [code].
Future<void> _pickAccount(
    WidgetTester tester, String label, String code) async {
  await tester.enterText(find.widgetWithText(TextField, label), code);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('$code - ').last);
  await tester.pumpAndSettle();
}

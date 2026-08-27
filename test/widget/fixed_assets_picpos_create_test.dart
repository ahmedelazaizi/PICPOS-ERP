// test/widget/fixed_assets_picpos_create_test.dart
//
// «أصل جديد» — الفعلُ الأوّلُ في رأس التصميم، وكان الفوركُ بلا أيٍّ منه.
//
// ═══ الفجوةُ المقيسة ═══
//
// `HEADS.main` في `PicPos Fixed Assets.dc.html` يعرّف فعلَين: `action:'أصل
// جديد'` و`alt:'ترحيل إهلاك الشهر'`. والفوركُ حمل **الثانيَ وحدَه** — فشاشةُ
// الأصول تعرض البطاقاتِ ولا تُنشئ أصلاً.
//
// ═══ وما يحرسه هذا الملفّ ═══
//
// 🔴 **حارسٌ مختلفٌ لكلّ فعل**: الإنشاءُ `assets_manage` والترحيلُ
//    `assets_depreciation`. وجمعُهما تحت حارسٍ واحدٍ يُعطي مَن يملك الترحيلَ
//    قدرةَ الإنشاء — وهما فعلان ماليّان مختلفان.
//
// 🔴 **وجدولُ الإهلاك في اللوحة محسوبٌ بصيغة المحرّك**: ما يُقرأ قبل الحفظ
//    هو ما سيُقيَّد. والقيمُ هنا **مثبَّتةٌ محسوبةً بيد** لا «تحرّكت».
//
// 🔴 **وتخريديّةٌ ≥ الثمن تمنع الحفظ**: المحرّكُ يتخطّى الأصلَ بـ
//    `if (monthly <= 0) continue` — فبدون هذا المنع يُنشَأ أصلٌ لا يُهلك
//    أبداً بلا أن يقول أحدٌ لماذا.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/fixed_assets_repository.dart';
import 'package:ural_erp/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';

final _categories = [
  db.AssetCategory(
    id: 10,
    name: 'أجهزة تبريد',
    defaultUsefulLife: 7,
    defaultDepreciationMethod: 'straight_line',
    accountId: 100,
    depreciationAccountId: 200,
    rowVersion: 0,
  ),
];

db.Account _account(int id, String code, String name, {int? parentId}) =>
    db.Account(
      id: id,
      code: code,
      name: name,
      parentId: parentId,
      accountType: 'asset',
      accountNature: 'debit',
      normalBalance: 'debit',
      level: 2,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

/// ‏١١ أبٌ و١١٠١ ابنٌ — والقائمةُ يجب أن تعرض الابنَ وحدَه.
final _accounts = [
  _account(1, '11', 'أصول متداولة'),
  _account(2, '1101', 'الخزينة الرئيسية', parentId: 1),
];

final _costCenters = [
  db.CostCenter(
    id: 3,
    code: 'CC-03',
    name: 'تشغيل أكتوبر',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 0,
  ),
];

/// يسجّل ما وصل المستودعَ — لا ما ظهر على الشاشة.
class _RecordingAssetsRepo implements IFixedAssetsRepository {
  final List<Map<String, Object?>> created = [];

  @override
  Stream<List<db.FixedAssetData>> watchFixedAssets() =>
      Stream.value(const []);

  @override
  Stream<List<db.AssetCategory>> watchAssetCategories() =>
      Stream.value(_categories);

  @override
  Stream<List<db.AssetDepreciationData>> watchAllDepreciations() =>
      Stream.value(const []);

  @override
  Future<int> createFixedAsset({
    required String code,
    required String name,
    required int categoryId,
    String? location,
    required double purchasePrice,
    required DateTime purchaseDate,
    required double usefulLifeYears,
    double salvageValue = 0,
    String depreciationMethod = 'straight_line',
    String? notes,
    int? costCenterId,
    int? contraAccountId,
  }) async {
    created.add({
      'code': code,
      'name': name,
      'categoryId': categoryId,
      'purchasePrice': purchasePrice,
      'usefulLifeYears': usefulLifeYears,
      'salvageValue': salvageValue,
      'depreciationMethod': depreciationMethod,
      'costCenterId': costCenterId,
      'contraAccountId': contraAccountId,
    });
    return created.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Stream<List<db.Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  Stream<List<db.CostCenter>> watchCostCenters() => Stream.value(_costCenters);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_RecordingAssetsRepo> _pump(
  WidgetTester tester,
  double width, {
  List<String> perms = const [
    'assets_view',
    'assets_manage',
    'assets_depreciation',
  ],
}) async {
  final repo = _RecordingAssetsRepo();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixedAssetsRepositoryProvider.overrideWithValue(repo),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: FixedAssetsPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return repo;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('أصل جديد'));
  await tester.pumpAndSettle();
}

Future<void> _fillMinimum(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'كود الأصل *'),
    'AST-019',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'اسم الأصل *'),
    'ثلاجة عرض 3م',
  );
  await tester.tap(find.byType(DropdownButtonFormField<int>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('أجهزة تبريد').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'ثمن الشراء *'),
    '64000',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'القيمة التخريدية'),
    '4000',
  );
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('المرساة: «أصل جديد» يظهر مع صلاحية assets_manage',
          (tester) async {
        await _pump(tester, width);
        expect(
          find.text('أصل جديد'),
          findsOneWidget,
          reason: 'الزرُّ غائبٌ حتّى مع الصلاحيّة — فنفيُ الفحص التالي '
              'سيقيس نمطَ البحث لا الحارس.',
        );
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وبلا assets_manage لا يظهر — ولو مَلَك الترحيل',
          (tester) async {
        await _pump(
          tester,
          width,
          perms: const ['assets_view', 'assets_depreciation'],
        );
        expect(find.text('أصل جديد'), findsNothing);
        // والترحيلُ ما زال ظاهراً — فالحارسان مختلفان فعلاً لا صدفةً.
        expect(find.text('ترحيل إهلاك الشهر'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('الفئةُ تُملي العمرَ — ٧ سنواتٍ من «أجهزة تبريد»',
          (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);
        await _fillMinimum(tester);

        final life = tester.widget<TextField>(
          find.widgetWithText(TextField, 'العمر الإنتاجي (سنوات) *'),
        );
        expect(life.controller!.text, '7');

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('جدولُ الإهلاك بصيغة المحرّك — ٧١٤.٢٩ لا رقمٌ يقاربه',
          (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);
        await _fillMinimum(tester);

        // (64,000 − 4,000) ÷ 84 = 714.285714… ⇒ «714.29» بتنسيق اللوحة.
        expect(find.text('60,000.00'), findsOneWidget); // القابل للإهلاك
        expect(find.text('714.29'), findsOneWidget); // القسط الشهري
        expect(find.text('8,571.43'), findsOneWidget); // القسط السنوي

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('تبديلُ الطريقة يُعيد الحساب — المتناقصُ ١,٥٢٣.٨١',
          (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);
        await _fillMinimum(tester);

        await tester.tap(find.text('القسط المتناقص'));
        await tester.pumpAndSettle();

        // 64,000 × 2/84 = 1,523.809523…
        expect(find.text('1,523.81'), findsOneWidget);
        expect(find.text('714.29'), findsNothing);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 تخريديّةٌ ≥ الثمن تمنع الحفظَ ويُقال السبب',
          (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);
        await _fillMinimum(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'القيمة التخريدية'),
          '64000',
        );
        await tester.pumpAndSettle();

        expect(
          find.text('القيمةُ التخريديّة يجب أن تقلّ عن ثمن الشراء'),
          findsOneWidget,
        );
        final btn = tester.widget<ElevatedButton>(
          find.ancestor(
            of: find.text('إنشاء الأصل'),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(btn.onPressed, isNull);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('الحفظُ يصل المستودعَ بالقيم المُدخَلة', (tester) async {
        final repo = await _pump(tester, width);
        await _openDialog(tester);
        await _fillMinimum(tester);

        await tester.tap(find.text('إنشاء الأصل'));
        await tester.pumpAndSettle();

        // ⚠️ ما يصل المستودعَ لا ما يظهر على الشاشة.
        expect(repo.created.length, 1);
        final row = repo.created.single;
        expect(row['code'], 'AST-019');
        expect(row['name'], 'ثلاجة عرض 3م');
        expect(row['categoryId'], 10);
        expect(row['purchasePrice'], 64000.0);
        expect(row['salvageValue'], 4000.0);
        expect(row['usefulLifeYears'], 7.0);
        expect(row['depreciationMethod'], 'straight_line');

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('قائمةُ الحساب المقابل ورقيّةٌ — الأبُ لا يُعرَض',
          (tester) async {
        // 🔴 القيدُ على حسابٍ أبٍ يجعل مجموعَ أبنائه يخالف رصيدَه، وميزانُ
        //    المراجعة لا يكشفه لأنّه يبقى متوازناً.
        await _pump(tester, width);
        await _openDialog(tester);

        await tester.tap(
          find.widgetWithText(
            DropdownButtonFormField<int>,
            'الحساب المقابل (ما دُفع منه)',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('1101 — الخزينة الرئيسية'), findsWidgets);
        expect(find.textContaining('11 — أصول متداولة'), findsNothing);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}

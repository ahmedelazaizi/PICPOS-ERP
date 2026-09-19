// تبويبُ «الأصول» مسطَّحاً — تصميمُ المالك `(10)`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) **شريطُ المرشِّحات الأربعة** (كما في · الفئة · الموقع · الحالة) مع
//    «إعادة تعيين» — وكلٌّ منها **يُرشِّح فعلاً**. مرشِّحٌ يُرسَم ولا يفعل
//    يكذب كزرٍّ لا يفعل.
//
// ‏٢) **ترقيمُ الصفحات**: التصميمُ يعطي الجدولَ الصفحةَ، وجدولٌ بلا ترقيمٍ
//    يرسم مئةَ صفٍّ في عمودٍ واحدٍ فتضيع المرشِّحاتُ فوقه.
//
// ‏٣) 👁 **يفتح البطاقةَ في مكان الشاشة** و«رجوع» يعيد الجدولَ — لا شاشةٌ
//    سادسةٌ بستّةِ مواضعِ توصيل.
//
// ‏٤) **والمؤشّراتُ شريطٌ نحيفٌ** لا خمسُ بطاقاتٍ تأكل الصفحة.
//
// ⚠️ **ولا قاعدةَ بيانات هنا**: المستودعاتُ تُستبدَل. فتحُ شاشةٍ على قاعدةٍ
// حيّةٍ في اختبار ودجت يعلّق — درسٌ مسجَّل لا تخمين.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/auth_repository.dart';
import 'package:ural_erp/domain/repositories/fixed_assets_repository.dart';
import 'package:ural_erp/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';

db.FixedAssetData _asset({
  required int id,
  required String code,
  required String name,
  int categoryId = 1,
  String? location = 'الإدارة',
  double price = 12000,
  double accum = 2000,
  DateTime? bought,
  String status = 'active',
}) =>
    db.FixedAssetData(
      id: id,
      code: code,
      name: name,
      categoryId: categoryId,
      location: location,
      purchasePrice: price,
      purchaseDate: bought ?? DateTime(2026, 1, 1),
      usefulLifeYears: 3,
      salvageValue: 0,
      depreciationMethod: 'straight_line',
      accumulatedDepreciation: accum,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0,
    );

db.AssetCategory _cat(int id, String name) => db.AssetCategory(
      id: id,
      name: name,
      defaultUsefulLife: 3,
      defaultDepreciationMethod: 'straight_line',
      rowVersion: 0,
    );

late List<db.FixedAssetData> _assets;

class _FakeAssetsRepo implements IFixedAssetsRepository {
  @override
  Stream<List<db.FixedAssetData>> watchFixedAssets() => Stream.value(_assets);

  @override
  Stream<List<db.AssetCategory>> watchAssetCategories() =>
      Stream.value([_cat(1, 'أجهزة مكتبية'), _cat(2, 'سيارات')]);

  @override
  Stream<List<db.AssetDepreciationData>> watchAllDepreciations() =>
      Stream.value(const []);

  @override
  Future<Map<int, ({double accumulated, double bookValue, double cost})>>
      getAssetSnapshotsAsOf(DateTime asOf) async => const {};

  @override
  Future<List<db.JournalEntryData>> getAssetMovements(int assetId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Stream<List<db.Account>> watchAllAccounts() => Stream.value(const []);

  @override
  Stream<List<db.CostCenter>> watchCostCenters() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAuthRepo implements IAuthRepository {
  @override
  Stream<List<db.UserWithRole>> watchAllUsers() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {double width = 1600}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixedAssetsRepositoryProvider.overrideWithValue(_FakeAssetsRepo()),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['assets_view']),
        hasPermissionProvider(PermissionCodes.assetsManage)
            .overrideWith((ref) async => true),
      ],
      child: const MaterialApp(home: FixedAssetsPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// ⚠️ **`ensureVisible` قبل النقر**: شريطُ الترقيم أسفلَ التبويبة داخلَ
/// `SingleChildScrollView`، ونقرةٌ على ما هو خارجَ الإطار تُسجَّل «ضائعة»
/// ولا ترمي — فيبدو الزرُّ معطَّلاً وهو سليم.
Future<void> _nextPage(WidgetTester tester) async {
  final next = find.byTooltip('التالي');
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() {
    _assets = [
      for (var i = 1; i <= 12; i++)
        _asset(
          id: i,
          code: 'FA-${i.toString().padLeft(3, '0')}',
          name: 'أصل $i',
          categoryId: i <= 9 ? 1 : 2,
          location: i.isEven ? 'الإدارة' : 'المخزن',
        ),
    ];
  });

  group('شريطُ المرشِّحات', () {
    testWidgets('الأربعةُ حاضرةٌ ومعها «إعادة تعيين»', (tester) async {
      await _pump(tester);
      for (final l in ['كما في', 'الفئة', 'الموقع', 'الحالة']) {
        expect(find.text(l), findsWidgets, reason: 'المرشِّح «$l» غائب');
      }
      expect(find.text('إعادة تعيين'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('🔴 ومرشِّحُ الفئة يُرشِّح فعلاً', (tester) async {
      await _pump(tester);
      expect(find.text('FA-010'), findsOneWidget);

      await tester.tap(find.text('كل الفئات').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('سيارات').last);
      await tester.pumpAndSettle();

      // ثلاثةُ أصولٍ في «سيارات» (‏١٠ · ١١ · ١٢).
      expect(find.text('FA-010'), findsOneWidget);
      expect(find.text('FA-001'), findsNothing,
          reason: 'مرشِّحٌ يُرسَم ولا يُرشِّح يكذب كزرٍّ لا يفعل');
      await _teardown(tester);
    });

    testWidgets('ومرشِّحُ الموقع كذلك', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('كل المواقع').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('المخزن').last);
      await tester.pumpAndSettle();

      // الفرديّةُ وحدَها في «المخزن».
      expect(find.text('FA-001'), findsOneWidget);
      expect(find.text('FA-002'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('و«إعادة تعيين» تُرجع الكلّ', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('كل الفئات').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('سيارات').last);
      await tester.pumpAndSettle();
      expect(find.text('FA-001'), findsNothing);

      await tester.tap(find.text('إعادة تعيين'));
      await tester.pumpAndSettle();
      expect(find.text('FA-001'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('🔴 ترقيمُ الصفحات', () {
    testWidgets('عشرةٌ في الصفحة والعدّادُ يقول الباقي', (tester) async {
      await _pump(tester);
      expect(find.text('FA-001'), findsOneWidget);
      expect(find.text('FA-011'), findsNothing,
          reason: 'الصفحةُ الأولى عشرةٌ — وجدولٌ بلا ترقيمٍ يرسم الاثنَي عشرَ');
      expect(find.textContaining('من ١٢ نتيجة'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('و«التالي» ينقل الصفحة', (tester) async {
      await _pump(tester);
      await _nextPage(tester);
      expect(find.text('FA-011'), findsOneWidget);
      expect(find.text('FA-001'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('🔴 والصفحةُ تُقصّ بعد ترشيحٍ يُقصّر القائمة', (tester) async {
      await _pump(tester);
      await _nextPage(tester);
      expect(find.text('FA-011'), findsOneWidget);

      // «سيارات» ثلاثةُ أصولٍ ⇒ صفحةٌ واحدة. والبقاءُ على الثانية يُفرغ
      // الجدولَ بلا سبب.
      await tester.tap(find.text('كل الفئات').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('سيارات').last);
      await tester.pumpAndSettle();

      expect(find.text('FA-010'), findsOneWidget,
          reason: 'الجدولُ فارغٌ لأنّ الصفحةَ بقيت خارجَ المدى');
      await _teardown(tester);
    });
  });

  group('🔴 البطاقةُ تُفتَح في مكان الشاشة', () {
    testWidgets('👁 يفتحها و«رجوع» يعيد الجدول', (tester) async {
      await _pump(tester);
      expect(find.text('بطاقات الأصول'), findsOneWidget);

      await tester.tap(find.text('البطاقة').first);
      await tester.pumpAndSettle();

      expect(find.text('بطاقات الأصول'), findsNothing,
          reason: 'الجدولُ باقٍ تحت البطاقة — وشريطُ التبويبات فوقها يوهم '
              'أنّ «الإهلاك» فيها و«الإهلاك الدوري» في الشاشة شيءٌ واحد');
      expect(find.text('FA-001'), findsWidgets);
      expect(find.text('بيانات الأصل'), findsWidgets);

      await tester.tap(find.text('رجوع'));
      await tester.pumpAndSettle();
      expect(find.text('بطاقات الأصول'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1280.0, 1600.0, 1920.0]) {
      testWidgets('الجدولُ والمرشِّحاتُ بلا فيضٍ عند ${w ~/ 1}',
          (tester) async {
        await _pump(tester, width: w);
        expect(tester.takeException(), isNull);
        expect(find.text('بطاقات الأصول'), findsOneWidget);
        await _teardown(tester);
      });
    }
  });
}

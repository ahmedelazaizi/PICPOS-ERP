// «التوزيع والمواقع» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) **التجميعُ على النشط وحدَه** — أصلٌ خرج من الدفاتر لا يشغل موقعاً،
//    ونسبتُه للمواقع تضخّم توزيعاً يُبنى عليه توزيعُ الإهلاك.
//
// ‏٢) 🔴 **والتسميةُ تكتب كلَّ أصلٍ يحمل القديم** — لا صفَّ جدولٍ واحداً.
//    العمودُ نصٌّ حرّ، فـ«فرع المعادي» و«فرع المعادي » موقعان في كلّ تجميع
//    والجدولُ صحيحٌ حرفاً بحرف.
//
// ‏٣) 🔴 **والدمجُ يُقال قبل وقوعه** — ولا يُفَكّ بعده إلّا بإعادة تسميةِ
//    كلِّ أصلٍ على حدة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/fixed_assets_repository.dart';
import 'package:ural_erp/presentation/fixed_assets_picpos/screens/asset_locations_picpos_screen.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_data_table.dart';

db.FixedAssetData _asset({
  required int id,
  required String code,
  required double cost,
  required double accumulated,
  String? location,
  String status = 'active',
}) =>
    db.FixedAssetData(
      id: id,
      code: code,
      name: 'أصل $code',
      categoryId: 10,
      location: location,
      purchasePrice: cost,
      purchaseDate: DateTime(2022, 1, 1),
      usefulLifeYears: 5,
      salvageValue: 0,
      depreciationMethod: 'straight_line',
      accumulatedDepreciation: accumulated,
      status: status,
      createdAt: DateTime(2022, 1, 1),
      rowVersion: 0,
    );

/// ⚠️ الصفّان ١ و٢ **نفسُ المكان** بمسافةٍ زائدةٍ في أحدهما — وهو عينُ ما
///    يجعل الجدولَ يعرض موقعَين لمكانٍ واحد.
final _assets = [
  _asset(id: 1, code: 'AST-001', cost: 86000, accumulated: 40000,
      location: 'فرع المعادي'),
  _asset(id: 2, code: 'AST-002', cost: 34000, accumulated: 10000,
      location: ' فرع المعادي '),
  _asset(id: 3, code: 'AST-003', cost: 20000, accumulated: 5000,
      location: 'فرع مصر الجديدة'),
  _asset(id: 4, code: 'AST-004', cost: 9000, accumulated: 1000),
  // مستبعدٌ — لا يشغل موقعاً.
  _asset(id: 5, code: 'AST-009', cost: 58200, accumulated: 49600,
      location: 'فرع طنطا', status: 'sold'),
];

class _FakeAssetsRepo implements IFixedAssetsRepository {
  final List<({int id, String? location})> writes = [];

  @override
  Stream<List<db.FixedAssetData>> watchFixedAssets() => Stream.value(_assets);

  @override
  Future<void> updateFixedAsset(
    int assetId, {
    String? name,
    String? location,
    double? salvageValue,
    String? notes,
    int? costCenterId,
    bool clearCostCenter = false,
    int? custodianUserId,
    bool clearCustodian = false,
  }) async {
    writes.add((id: assetId, location: location));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  _FakeAssetsRepo? repo,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixedAssetsRepositoryProvider
            .overrideWithValue(repo ?? _FakeAssetsRepo()),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['assets_view', 'assets_manage']),
      ],
      child: const MaterialApp(home: AssetLocationsPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// يفتح حوارَ إعادةِ التسمية لصفّ [location].
///
/// ⚠️ **البحثُ داخلَ الجدول وحدَه**: اسمُ الموقع مكتوبٌ في شريط النسب
/// **وفي الجدول** معاً، و`find.text` يلتقط الأوّلَ — أي صفَّ الشريط الذي
/// لا زرَّ فيه.
Future<void> _openRename(WidgetTester tester, String location) async {
  final inTable = find.descendant(
    of: find.byType(PicPosDataTable),
    matching: find.text(location),
  );
  final row = find.ancestor(of: inTable, matching: find.byType(Row));
  await tester.tap(find.descendant(
    of: row.last,
    matching: find.textContaining('تسمية'),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('التجميع', () {
    testWidgets('يجمع الأصولَ النشطةَ حسب الموقع', (tester) async {
      await _pump(tester);
      expect(find.text('القيمة الدفترية حسب الموقع'), findsOneWidget);
      expect(find.text('فرع المعادي'), findsWidgets);
      expect(find.text('فرع مصر الجديدة'), findsWidgets);
      await _teardownTree(tester);
    });

    testWidgets('والمستبعدُ لا يشغل موقعاً', (tester) async {
      await _pump(tester);
      expect(find.text('فرع طنطا'), findsNothing,
          reason: 'أصلٌ خرج من الدفاتر نُسب لموقعٍ — فتضخّم قيمتُه الدفترية');
      await _teardownTree(tester);
    });

    testWidgets('و«بلا موقع» تُقال ولا تُترَك خانةً فارغة', (tester) async {
      await _pump(tester);
      expect(find.text('بلا موقع'), findsWidgets);
      await _teardownTree(tester);
    });
  });

  group('🔴 إعادةُ التسمية', () {
    testWidgets('تكتب كلَّ أصلٍ يحمل الاسمَ القديم — والمشذَّبَ منها',
        (tester) async {
      final repo = _FakeAssetsRepo();
      await _pump(tester, repo: repo);
      await _openRename(tester, 'فرع المعادي');

      expect(find.text('إعادةُ تسميةِ موقع'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'الاسم الجديد'), 'فرع المعادي الجديد');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(repo.writes.map((w) => w.id).toList(), [1, 2],
          reason: '🔴 أصلٌ كُتب بمسافةٍ زائدةٍ بقي خلف الاسم القديم — '
              'والموقعُ يبقى مقسوماً');
      expect(repo.writes.every((w) => w.location == 'فرع المعادي الجديد'),
          isTrue);
      await _teardownTree(tester);
    });

    testWidgets('🔴 والدمجُ يُقال بعدده قبل وقوعه', (tester) async {
      await _pump(tester);
      await _openRename(tester, 'فرع المعادي');
      await tester.enterText(
          find.widgetWithText(TextField, 'الاسم الجديد'), 'فرع مصر الجديدة');
      await tester.pumpAndSettle();

      expect(find.textContaining('سيُدمَج'), findsOneWidget,
          reason: '🔴 دمجٌ صامتٌ لا يُفَكّ: الموقعان يصيران واحداً ولا اسمَ '
              'قديمٌ يبقى في أيّ صفّ');
      expect(find.widgetWithText(ElevatedButton, 'دمج'), findsOneWidget,
          reason: 'زرٌّ يقول «حفظ» على فعلٍ يدمج يُقرأ غيرَ ما يفعل');
      await _teardownTree(tester);
    });

    testWidgets('🔴 والاسمُ الفارغُ لا يُجرّد الأصولَ من مواقعها',
        (tester) async {
      final repo = _FakeAssetsRepo();
      await _pump(tester, repo: repo);
      await _openRename(tester, 'فرع المعادي');
      await tester.enterText(
          find.widgetWithText(TextField, 'الاسم الجديد'), '   ');
      await tester.pumpAndSettle();

      final save = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'حفظ'));
      expect(save.onPressed, isNull,
          reason: '🔴 حقلٌ تُرك فارغاً بالسهو كان سيُجرّد عشراتِ الأصول من '
              'مواقعها بلا رجعة');
      expect(repo.writes, isEmpty);
      await _teardownTree(tester);
    });

    testWidgets('و«بلا موقع» زرُّها يقول «إسناد» لا «إعادة تسمية»',
        (tester) async {
      await _pump(tester);
      expect(find.text('إسناد موقع'), findsOneWidget,
          reason: 'الإسنادُ ليس تصحيحاً — والزرُّ يقول ما يفعل');
      await _teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('الشاشةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await _pump(tester, width: w);
        expect(tester.takeException(), isNull);
        expect(find.text('الأصول حسب الموقع'), findsOneWidget);
        await _teardownTree(tester);
      });
    }
  });
}

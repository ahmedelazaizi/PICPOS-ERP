// شاشةُ «الفروع والمنشآت» — نسخةُ PicPos على التصميم.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التركيبُ على عرضين**: الشاشةُ ترويسةٌ وتبويباتٌ وسطرُ ملاحظةٍ وجسمٌ
//    فيه شبكاتٌ محسوبةُ العرض. وانهيارُ التخطيط لا يظهر في التحليل.
//
// ‏٢) **الشاراتُ والعدّاداتُ مشتقّةٌ لا مكتوبة**: شارةُ تبويبة «الفروع» يجب
//    أن تساوي عددَ الفروع القادمِ من المزوِّد. ورقمٌ مكتوبٌ بجانب ما يعدّه
//    يمرّ أخضرَ ويكذب على المشغّل.
//
// ‏٣) **الملاحظةُ تتبع التبويبةَ**: نصوصُ `TABS.branches[].note` قواعدُ عملٍ،
//    وثباتُها على نصٍّ واحدٍ يعني أنّ أربعةً منها لا تُقرأ أبداً.
//
// ⚠️ **ولا قاعدةَ بيانات هنا**: المزوِّداتُ تُستبدَل بقيمٍ ثابتة. فتح شاشةٍ
// على قاعدةٍ حيّةٍ في اختبار ودجت يعلّق (‏`db.close()` ينتظر مؤقّتَ drift
// في المنطقة الوهميّة) — وهو درسٌ مسجَّل، لا تخمين.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/branch_repository.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/branches_picpos_screen.dart';

Branche _branch(int id, String name, {bool active = true, String? code}) =>
    Branche(
      id: id,
      name: name,
      code: code,
      isActive: active,
      isSystemDefault: id == 1,
      rowVersion: 0,
    );

Warehouse _wh(
  int id,
  String name, {
  int? branchId,
  String type = 'general',
  bool isDefault = false,
  bool active = true,
}) =>
    Warehouse(
      id: id,
      name: name,
      branchId: branchId,
      type: type,
      isDefault: isDefault,
      isActive: active,
      isSystemDefault: false,
      rowVersion: 0,
    );

/// مستودعُ فروعٍ زائفٌ يخدم `watchAllWarehouses` وحدَها.
///
/// `noSuchMethod` تغطّي الباقي: أيُّ نداءٍ آخرَ يرمي — وهذا مقصود، فالشاشةُ
/// لا يجوز أن تنادي غيرَها من هذا المستودع.
class _FakeBranchRepo implements IBranchRepository {
  _FakeBranchRepo(this.warehouses);

  final List<Warehouse> warehouses;

  @override
  Stream<List<Warehouse>> watchAllWarehouses() => Stream.value(warehouses);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  final branches = [
    _branch(1, 'فرع المعادي', code: 'CAI'),
    _branch(2, 'فرع مدينة نصر', code: 'NSR'),
    _branch(3, 'فرع أكتوبر', active: false),
  ];

  final warehouses = [
    _wh(1, 'المخزن الرئيسي', branchId: 1, type: 'retail', isDefault: true),
    _wh(2, 'مخزن التالف', branchId: 1),
    _wh(3, 'مخزن الخامات', type: 'raw_materials', active: false),
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allBranchesProvider.overrideWith((ref) => Stream.value(branches)),
          // ⚠️ **يُتجاوَز المستودعُ لا المزوِّد**: مزوِّدُ صفوف المخازن خاصٌّ
          //    بالشاشة، وتجاوزُه يقتضي كشفَه. وتجاوزُ المستودع يمرّ بمنطق
          //    المزوِّد نفسِه فيختبر التوصيلَ لا يلتفّ عليه.
          branchRepositoryProvider.overrideWithValue(_FakeBranchRepo(warehouses)),
          allUsersProvider
              .overrideWith((ref) => Stream.value(const <UserWithRole>[])),
        ],
        child: const MaterialApp(home: BranchesPicposScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1500, 900)),
      ('عرضٌ ضيّق', Size(820, 760)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');

        // والمحتوى ظاهرٌ فعلاً — لا شجرةٌ فارغةٌ تمرّ.
        expect(find.text('الفروع والمنشآت'), findsOneWidget);
        expect(find.text('فرع المعادي'), findsWidgets);
        expect(find.text('فرع جديد'), findsOneWidget);
        await teardownTree(tester);
      });
    }
  });

  testWidgets('شاراتُ التبويبات مشتقّةٌ من المزوِّد لا مكتوبة', (tester) async {
    await open(tester, const Size(1500, 900));
    // ثلاثةُ فروعٍ وثلاثةُ مخازنَ في التجهيزة ⇒ الشارتان «3».
    expect(find.text('${branches.length}'), findsWidgets);
    expect(find.text('الفروع'), findsWidgets);
    expect(find.text('المخازن'), findsWidgets);
    await teardownTree(tester);
  });

  testWidgets('المؤشّراتُ تعدّ ما تعرضه الشجرةُ نفسُها', (tester) async {
    await open(tester, const Size(1500, 900));
    // فرعان نشطان من ثلاثة — والنصُّ الخافتُ يقول العددَ الكلّيّ.
    expect(find.text('الفروع النشطة'), findsOneWidget);
    expect(find.text('من ${branches.length} مسجلة'), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'عدّادُ النشطة ليس ٢');
    await teardownTree(tester);
  });

  testWidgets('ملاحظةُ التبويبة تتبدّل بتبدّل التبويبة', (tester) async {
    await open(tester, const Size(1500, 900));
    expect(
      find.text('الفرع يملك نقاط بيع ومخازن وتقويم عطلات مستقلاً'),
      findsOneWidget,
    );

    // إلى تبويبة «المخازن» — ملاحظتُها تصف قاعدةَ `Warehouses.branchId`.
    await tester.tap(find.text('المخازن').first);
    await tester.pumpAndSettle();
    expect(
      find.text('المخزن يتبع فرعاً واحداً — وبلا فرع يكون عاماً على المنشأة'),
      findsOneWidget,
    );
    expect(
      find.text('الفرع يملك نقاط بيع ومخازن وتقويم عطلات مستقلاً'),
      findsNothing,
      reason: 'الملاحظةُ ثابتةٌ — فأربعٌ من خمسٍ لا تُقرأ أبداً.',
    );

    // وجدولُ المخازن يميّز المخزنَ بلا فرعٍ بالنصّ لا بفراغ.
    expect(find.text('عامٌّ على المنشأة'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('جدولُ المخازن يحمل «الحالة» و«إجراء» من التصميم',
      (tester) async {
    // ⚠️ العمودان كانا ساقطَين لأنّ المصدرَ كان DTO نطاقٍ بلا `isActive`
    //    ولا يصلح لحوار التعديل. فهذا الفحصُ يحرس **مصدرَ البيانات** عبر
    //    ما يظهر منه: من يعيده إلى `allWarehousesProvider` يفقد العمودَين.
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('المخازن').first);
    await tester.pumpAndSettle();

    expect(find.text('الحالة'), findsOneWidget);
    expect(find.text('إجراء'), findsOneWidget);

    // مخزنان نشطان وواحدٌ موقوفٌ في التجهيزة.
    expect(find.text('نشط'), findsNWidgets(2));
    expect(find.text('موقوف'), findsOneWidget);

    // وزرُّ التعديل لكلّ صفّ.
    expect(find.text('تعديل'), findsNWidgets(3));
    await teardownTree(tester);
  });

  testWidgets('إجراءُ الترويسة يتبع التبويبةَ', (tester) async {
    await open(tester, const Size(1500, 900));
    expect(find.text('فرع جديد'), findsOneWidget);
    expect(find.text('مخزن جديد'), findsNothing);

    await tester.tap(find.text('المخازن').first);
    await tester.pumpAndSettle();
    expect(find.text('مخزن جديد'), findsOneWidget);
    expect(find.text('فرع جديد'), findsNothing);
    await teardownTree(tester);
  });
}

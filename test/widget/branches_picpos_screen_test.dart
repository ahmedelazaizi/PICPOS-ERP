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
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart'
    show WarehouseData;
import 'package:ural_erp/presentation/settings_picpos/screens/branches_picpos_screen.dart';

Branche _branch(int id, String name, {bool active = true, String? code}) =>
    Branche(
      id: id,
      name: name,
      code: code,
      isActive: active,
      isSystemDefault: id == 1,
      rowVersion: 0,
    );

void main() {
  final branches = [
    _branch(1, 'فرع المعادي', code: 'CAI'),
    _branch(2, 'فرع مدينة نصر', code: 'NSR'),
    _branch(3, 'فرع أكتوبر', active: false),
  ];

  const warehouses = [
    WarehouseData(id: 1, name: 'المخزن الرئيسي', isDefault: true, branchId: 1,
        type: 'retail'),
    WarehouseData(id: 2, name: 'مخزن التالف', isDefault: false, branchId: 1,
        type: 'general'),
    WarehouseData(id: 3, name: 'مخزن الخامات', isDefault: false,
        type: 'raw_materials'),
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allBranchesProvider.overrideWith((ref) => Stream.value(branches)),
          allWarehousesProvider
              .overrideWith((ref) => Stream.value(warehouses)),
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

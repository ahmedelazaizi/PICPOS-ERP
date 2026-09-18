// حوارُ اختيار طاولة الدمج — **طردٌ مزدوجٌ يُسقط الشاشةَ التي تحته.**
//
// ═══ بلاغُ المالك 2026-09-18 ═══
//
// «لما دمجت طاولتين الشاشة اسودت النظام اتجمد» — يتكرّر في كلّ مرّة.
//
// ولوجُ حزمة التشخيص (‏3.1.4+256) أعطى المسارَ كاملاً بلا تعليقٍ في أيّ خطوة:
//
//   10/ قبل فتح حوار الاختيار    06:48:32.769
//   11/ الحوارُ أُغلق target=null 06:48:34.280
//
// أي أنّ الحوارَ **فُتح**، ثمّ أُغلق **بلا نتيجة** — فلم يقع الدمجُ أصلاً،
// ولم يُرمَ استثناءٌ (معالجا `main.dart` يكتبان فوراً ولم يكتبا شيئاً).
//
// والسببُ سطران يطردان معاً:
//   • `merge_table_dialog.dart` : `Navigator.pop(context)` ثمّ `onMerge(table)`
//   • والمُنادي يمرّر           : `onMerge: (t) => Navigator.pop(ctx, t)`
//
// فالأوّلُ يُغلق الحوارَ (‏`showDialog` يعيد `null`)، والثاني لا يجد حواراً
// فيَطرد **الشاشةَ التي تحته** — ولا شيءَ تحتها، فسوادٌ وجمود. والطردُ فعلٌ
// مشروعٌ لا يرمي شيئاً، ولهذا كان اللوجُ صامتاً.
//
// ═══ ولماذا توكيدان لا واحد ═══
//
// `result` وحدَه يمسك «لم يقع الدمج»، وبقاءُ الشاشة وحدَه يمسك «السواد».
// والعطبُ واحدٌ يُنتجهما معاً، فإسقاطُ أحدهما يترك نصفَ البلاغ بلا حارس.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/presentation/screens/tables/merge_table_dialog.dart';

RestaurantTable _table(int id, String name) => RestaurantTable(
      id: id,
      sectionId: 1,
      name: name,
      capacity: 4,
      status: 'occupied',
      x: 0,
      y: 0,
      shape: 'square',
      lastStatusAt: DateTime(2026),
      isActive: true,
      createdAt: DateTime(2026),
      rowVersion: 0,
      rotation: 0,
    );

void main() {
  testWidgets('النقرُ على طاولةٍ يُعيدها ولا يُسقط الشاشةَ تحت الحوار',
      (tester) async {
    RestaurantTable? result;
    var dialogClosed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<RestaurantTable>(
                    context: context,
                    builder: (ctx) => MergeTableDialog(
                      sourceTable: _table(1, 'طاولة ١'),
                      otherOccupiedTables: [_table(2, 'طاولة ٢')],
                      onMerge: (t) => Navigator.pop(ctx, t),
                    ),
                  );
                  dialogClosed = true;
                },
                child: const Text('افتح الحوار'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('افتح الحوار'));
    await tester.pumpAndSettle();
    expect(find.text('دمج الطاولات'), findsOneWidget,
        reason: 'مرساةٌ — الحوارُ لم يُفتح أصلاً فما تحته لا يُقاس');

    await tester.tap(find.text('طاولة ٢'));
    await tester.pumpAndSettle();

    expect(dialogClosed, isTrue, reason: 'الحوارُ لم يعد');
    expect(result?.id, 2,
        reason: 'الحوارُ أعاد null — فلا دمجَ يقع، وهو عينُ `target=null` '
            'في لوج المالك');
    expect(find.text('افتح الحوار'), findsOneWidget,
        reason: 'الشاشةُ التي تحت الحوار طُردت — وهذا هو السوادُ والجمود');
  });

  testWidgets('و«إلغاء» يُغلق الحوارَ وحدَه ويُبقي ما تحته', (tester) async {
    // الطرفُ المقابل: لو «أصلحنا» بحذف الطرد الخطأ من الموضع الخطأ، صار
    // الإلغاءُ لا يُغلق شيئاً — أو طرد الشاشةَ كما يفعل النقرُ اليوم.
    RestaurantTable? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<RestaurantTable>(
                    context: context,
                    builder: (ctx) => MergeTableDialog(
                      sourceTable: _table(1, 'طاولة ١'),
                      otherOccupiedTables: [_table(2, 'طاولة ٢')],
                      onMerge: (t) => Navigator.pop(ctx, t),
                    ),
                  );
                },
                child: const Text('افتح الحوار'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('افتح الحوار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(result, isNull, reason: 'الإلغاءُ يجب ألّا يُعيد طاولة');
    expect(find.text('دمج الطاولات'), findsNothing,
        reason: 'الحوارُ لم يُغلَق بالإلغاء');
    expect(find.text('افتح الحوار'), findsOneWidget,
        reason: 'الإلغاءُ طرد الشاشةَ التي تحته');
  });
}

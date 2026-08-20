import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/tables_picpos/widgets/tables_status_rail.dart';

void main() {
  test('العدُّ يشمل كلَّ حالةٍ ولو كانت صفراً', () {
    final counts = countByStatus([
      TableStatus.available,
      TableStatus.available,
      TableStatus.occupied,
    ]);
    expect(counts[TableStatus.available], 2);
    expect(counts[TableStatus.occupied], 1);
    expect(counts[TableStatus.outOfService], 0,
        reason: 'الصفرُ يُعرَض ولا يُخفى — صورةُ المالك تعرض «غير متاحة ٠»');
    expect(counts.keys.toSet(), TableStatus.all.toSet());
  });

  testWidgets('الضغطُ على حالةٍ يبلّغ باختيارها، وإعادةُ الضغط تُلغيه',
      (tester) async {
    String? picked = 'sentinel';

    Future<void> pumpWith(String? selected) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TablesStatusRail(
                counts: countByStatus([TableStatus.available]),
                selected: selected,
                onSelect: (s) => picked = s,
              ),
            ),
          ),
        );

    await pumpWith(null);
    await tester.tap(find.text('متاحة'));
    expect(picked, TableStatus.available);

    // الشقُّ الثاني من اسم الاختبار — كان بلا توكيدٍ إطلاقاً. العمودُ عديمُ
    // الحالة، فالإلغاءُ يظهر حين يُعاد بناؤه بالحالة المختارة ثم يُضغَط عليها.
    picked = 'sentinel';
    await pumpWith(TableStatus.available);
    await tester.tap(find.text('متاحة'));
    expect(picked, isNull,
        reason: 'إعادةُ الضغط على الحالة المختارة لا تُلغي الترشيح — '
            'فالمستخدمُ يحبس نفسَه في حالةٍ واحدة');
  });

  // العمودُ كان يستقبل `selected` ولا يستعمله في الرسم إطلاقاً: يُرشَّح
  // المحتوى ولا يرى المستخدمُ أيَّ حالةٍ فعّالة.
  testWidgets('الحالةُ المختارة تُرسَم مختارةً — لا `selected` مهمَلة',
      (tester) async {
    Future<BoxDecoration> decorationOf(String status) async {
      final container = tester
          .widgetList<Container>(find.descendant(
            of: find.byKey(TablesStatusRail.tileKey(status)),
            matching: find.byType(Container),
          ))
          .first;
      return container.decoration! as BoxDecoration;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TablesStatusRail(
            counts: countByStatus([TableStatus.available]),
            selected: TableStatus.available,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    final chosen = await decorationOf(TableStatus.available);
    final other = await decorationOf(TableStatus.occupied);

    expect(chosen.color, isNotNull,
        reason: 'المختارةُ بلا تظليل — لا فرقَ بينها وبين غيرها');
    expect(chosen.border!.top.color, isNot(Colors.transparent),
        reason: 'المختارةُ بلا إطارٍ ملوّن');
    expect(other.color, isNull);
    expect(other.border!.top.color, Colors.transparent,
        reason: 'غيرُ المختارة تحمل إطاراً شفّافاً لا معدوماً — وإلّا قفز '
            'مقاسُ البطاقة عند الاختيار');
  });

  // العمودُ كان يقف عند خمسِ حالاتٍ فقط: من ينقر «متاحة» لا يجد سبيلاً
  // للعودة إلى الكلّ إلّا بإعادة نقر البطاقة نفسِها — وهو غيرُ مكتشَف.
  group('بطاقةُ «عرض الكل»', () {
    testWidgets('موجودةٌ، وتعرض مجموعَ الطاولات، وتقع بعد الحالات الخمس',
        (tester) async {
      final counts = countByStatus([
        TableStatus.available,
        TableStatus.available,
        TableStatus.occupied,
      ]);
      final total = counts.values.fold<int>(0, (a, b) => a + b);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TablesStatusRail(
              counts: counts,
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      final allTileFinder =
          find.byKey(TablesStatusRail.tileKey(TablesStatusRail.allKey));
      expect(allTileFinder, findsOneWidget);
      expect(
        find.descendant(of: allTileFinder, matching: find.text('عرض الكل')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: allTileFinder, matching: find.text('$total')),
        findsOneWidget,
        reason: 'مجموعُ البطاقة يجب أن يطابق مجموعَ الحالات الخمس، لا رقماً '
            'منفصلاً قد يتباعد عنه',
      );

      // بعد آخر حالةٍ (خارج الخدمة) في الترتيب — كما في نصّ المالك.
      final lastStatusTop = tester
          .getTopLeft(
              find.byKey(TablesStatusRail.tileKey(TableStatus.outOfService)))
          .dy;
      final allTileTop = tester.getTopLeft(allTileFinder).dy;
      expect(allTileTop, greaterThan(lastStatusTop),
          reason: 'بطاقةُ «عرض الكل» يجب أن تقع بعد الحالات الخمس لا بينها');
    });

    testWidgets('النقرُ عليها يُرجع المرشِّحَ إلى الكلّ', (tester) async {
      String? picked = TableStatus.available;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TablesStatusRail(
              counts: countByStatus([TableStatus.available]),
              selected: TableStatus.available,
              onSelect: (s) => picked = s,
            ),
          ),
        ),
      );

      await tester.tap(find.text('عرض الكل'));
      expect(picked, isNull,
          reason: 'النقرُ على «عرض الكل» يجب أن يُلغي أيَّ ترشيحٍ حالةٍ '
              'قائم، بصرف النظر عن الحالة المختارة سلفاً');
    });

    testWidgets('تُرسَم مختارةً حين يكون المرشِّحُ null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TablesStatusRail(
              counts: countByStatus([TableStatus.available]),
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      final decoration = tester
          .widgetList<Container>(find.descendant(
            of: find.byKey(TablesStatusRail.tileKey(TablesStatusRail.allKey)),
            matching: find.byType(Container),
          ))
          .first
          .decoration! as BoxDecoration;

      expect(decoration.color, isNotNull,
          reason: '«عرض الكل» بلا تظليل رغم كونها المرشِّحَ الفعّال');
      expect(decoration.border!.top.color, isNot(Colors.transparent),
          reason: '«عرض الكل» بلا إطارٍ ملوّن رغم كونها المرشِّحَ الفعّال');
    });
  });
}

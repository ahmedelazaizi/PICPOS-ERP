// ═══════════════════════════════════════════════════════════════════════════
// TableActionsMenu — قائمةُ كبسات الطاولة تُرسَم من `actionsForStatus`
// ═══════════════════════════════════════════════════════════════════════════
//
// `actionsForStatus` نفسُها مُختبَرةٌ في test/unit/table_actions_test.dart.
// المُختبَرُ هنا الوصلةُ التي لم يمسّها اختبار: أن الودجت تُرسَم **من**
// تلك الدالّة، وأن الفعلَ الهدّامَ يُميَّز شكلاً، وأن الضغطَ يُبلّغ الفعلَ
// الصحيح.
//
// الودجت مستقلّةٌ عن `TablesScreen` عمداً: اختباراتُ الويدجت في هذا
// المستودع تتعلّق عند فتح الشاشات لأن `db.close()` ينتظر مؤقّت drift في
// المنطقة الوهميّة — فلا قاعدةَ هنا ولا `ProviderScope` أصلاً.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_actions.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/screens/tables/widgets/table_actions_menu.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('المشغولةُ تعرض الدفعَ والإلغاءَ ولا تعرض الإغلاق',
      (tester) async {
    await tester.pumpWidget(_wrap(TableActionsMenu(
      status: TableStatus.occupied,
      onSelected: (_) {},
    )));

    expect(find.text('الدفع'), findsOneWidget);
    expect(find.text('إلغاء الطلب'), findsOneWidget);
    expect(find.text('تقسيم الفاتورة'), findsOneWidget);
    expect(find.text('إغلاق الطاولة'), findsNothing);
    expect(find.text('فتح طاولة'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('المدفوعةُ تعرض الإغلاقَ ولا تعرض الدفعَ ولا الإلغاء',
      (tester) async {
    await tester.pumpWidget(_wrap(TableActionsMenu(
      status: TableStatus.paid,
      onSelected: (_) {},
    )));

    expect(find.text('إغلاق الطاولة'), findsOneWidget);
    expect(find.text('إضافة طلب'), findsOneWidget);
    expect(find.text('الدفع'), findsNothing);
    expect(find.text('إلغاء الطلب'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('كلُّ كبسةٍ معروضةٍ تطابق actionsForStatus عدداً ونصّاً',
      (tester) async {
    for (final status in TableStatus.all) {
      await tester.pumpWidget(_wrap(TableActionsMenu(
        status: status,
        onSelected: (_) {},
      )));

      final expected = actionsForStatus(status);
      expect(find.byType(TableActionButton), findsNWidgets(expected.length),
          reason: status);
      for (final action in expected) {
        expect(find.text(tableActionLabels[action]!), findsOneWidget,
            reason: '$status → $action');
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('الهدمُ وحدَه ممتلئٌ والباقي محدَّدٌ بإطار', (tester) async {
    await tester.pumpWidget(_wrap(TableActionsMenu(
      status: TableStatus.occupied,
      onSelected: (_) {},
    )));

    // «إلغاء الطلب» يمحو طلباً حيّاً؛ «إغلاق الطاولة» روتينٌ بعد سداد. لو
    // تساويا شكلاً محا النادلُ طلباً وهو يظنّ أنه ينظّف طاولة.
    final destructive = find.ancestor(
      of: find.text('إلغاء الطلب'),
      matching: find.byType(ElevatedButton),
    );
    expect(destructive, findsOneWidget);
    expect(isDestructiveTableAction(TableAction.cancelOrder), isTrue);

    for (final label in ['الدفع', 'نقل الطلب', 'تقسيم الفاتورة']) {
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(ElevatedButton),
        ),
        findsNothing,
        reason: '$label ليس هدماً',
      );
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
        reason: label,
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('الضغطُ يُبلّغ الفعلَ الذي عليه النصّ', (tester) async {
    final tapped = <TableAction>[];
    await tester.pumpWidget(_wrap(TableActionsMenu(
      status: TableStatus.occupied,
      onSelected: tapped.add,
    )));

    await tester.tap(find.text('الدفع'));
    await tester.pump();
    await tester.tap(find.text('إلغاء الطلب'));
    await tester.pump();

    expect(tapped, [TableAction.pay, TableAction.cancelOrder]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

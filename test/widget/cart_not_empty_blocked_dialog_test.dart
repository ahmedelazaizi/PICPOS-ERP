// حوار منع التنقّل/الخروج والسلّة غير فارغة (قرار المالك): خياران فقط —
// «تعليق الفاتورة ثم المتابعة» (true) و«إلغاء والبقاء» (false)؛ لا متابعة
// بدون تعليق أو تفريغ.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/cart_not_empty_close_dialog.dart';

void main() {
  const cases = <(String, String)>[
    ('لا يمكن مغادرة شاشة البيع', 'تعليق الفاتورة ثم الانتقال'),
    ('لا يمكن تسجيل الخروج', 'تعليق الفاتورة ثم تسجيل الخروج'),
  ];

  for (final (title, holdLabel) in cases) {
    Future<Future<bool>> open(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      final result = showCartNotEmptyBlockedDialog(
        ctx,
        title: title,
        holdLabel: holdLabel,
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('«$title»: الرسالة + زرّان فقط (تعليق / إلغاء والبقاء)',
        (tester) async {
      final result = await open(tester);
      bool? value;
      result.then((v) => value = v);

      expect(find.text(title), findsOneWidget);
      expect(
        find.text('السلة غير فارغة: أكمل البيع أو أفرغ السلة'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, holdLabel), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'إلغاء والبقاء'), findsOneWidget);
      // لا خيار «متابعة» ثالث.
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, holdLabel));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('«$title»: «إلغاء والبقاء» ⇒ false', (tester) async {
      final result = await open(tester);
      bool? value;
      result.then((v) => value = v);

      await tester.tap(find.widgetWithText(TextButton, 'إلغاء والبقاء'));
      await tester.pumpAndSettle();
      expect(value, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('«$title»: النقر خارج الحوار ⇒ false (بقاء)', (tester) async {
      final result = await open(tester);
      bool? value;
      result.then((v) => value = v);

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(value, isFalse);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/app.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/screens/customer_screen.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('unpaired device shows pairing; pairing then PIN login reaches today route (Arabic RTL)',
      (tester) async {
    final api = FakeCloudApi();
    final c = AppController(store: MemoryLocalStore(), api: api, clock: () => DateTime(2026, 5, 1, 10));
    await c.init();
    await tester.pumpWidget(PicposVanApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('ربط الجهاز'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.rtl);

    await tester.enterText(find.byKey(const Key('pairingCode')), 'ABCDEFGH');
    await tester.tap(find.text('ربط'));
    await tester.pumpAndSettle();
    expect(find.text('دخول المندوب'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin')), '0000');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('الرمز السري غير صحيح'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin')), '1234');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('خط اليوم'), findsWidgets);
    expect(find.text('بقالة الأمل'), findsOneWidget);
    expect(find.text('سوبرماركت النور'), findsOneWidget);
    expect(find.text('لم تتم الزيارة'), findsNWidgets(2));
  });

  testWidgets('English locale renders LTR', (tester) async {
    final (c, _) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c, initialLocale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text("Today's route"), findsWidgets);
    expect(Directionality.of(tester.element(find.byType(Scaffold).first)), TextDirection.ltr);
  });

  testWidgets('customer card shows balance and credit limit; scan + save a cash sale', (tester) async {
    final (c, _) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بقالة الأمل'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerScreen), findsOneWidget);
    expect(find.text('90.00'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);

    await tester.tap(find.text('فاتورة بيع'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode')), '6251234567890');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('2.90'), findsWidgets); // total 2.5 + 16 %
    await tester.tap(find.byKey(const Key('saveSale')));
    await tester.pumpAndSettle();
    final ob = await c.store.outbox();
    expect(ob.single.payload['number'], 'VS-100000');
    expect(ob.single.payload['paid'], 2.9);
  });

  testWidgets('collection screen pre-fills the next free voucher leaf', (tester) async {
    final (c, _) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سوبرماركت النور'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سند قبض'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '1003'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '15');
    await tester.tap(find.byKey(const Key('saveCollection')));
    await tester.pumpAndSettle();
    expect((await c.store.outbox()).single.payload['bookNumber'], 1003);
  });

  testWidgets('sync tab shows status and syncs on demand', (tester) async {
    final (c, api) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المزامنة').last);
    await tester.pumpAndSettle();
    expect(find.text('زامن الآن'), findsOneWidget);
    expect(find.text('لا توجد مستندات معلّقة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('syncNow')));
    await tester.pumpAndSettle();
    expect(api.pushed, isEmpty, reason: 'nothing pending → no push');
  });
}

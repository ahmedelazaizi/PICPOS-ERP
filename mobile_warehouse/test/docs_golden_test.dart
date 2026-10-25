// Goldens of the W2-W5 screens (documents hub, receive, blind count, approvals,
// labels, outbox). Four variants each, covering AR/EN, light/dark and the
// phone / handheld / tablet sizes. Generated on the Windows dev machine;
// regenerate deliberately: `flutter test --update-goldens test/docs_golden_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import 'docs_flow_test.dart';
import 'fake_office.dart';
import 'support.dart';

typedef _Go = Future<void> Function(WidgetTester t, FakeOffice office);

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);

  final screens = <String, (int dest, _Go go)>{
    'hub': (2, (t, o) async {}),
    'receive': (2, (t, o) async {
      await _tap(t, 'doc.receive');
      await _tap(t, 'po.PO1');
      await scan(t, '6221234567890');
      await typeQty(t, '6');
      await _tap(t, 'line.add');
    }),
    'count': (2, (t, o) async {
      await _tap(t, 'doc.count');
      await _tap(t, 'task.T1');
      await scan(t, '6221234567890');
      await typeQty(t, '130');
    }),
    'approvals': (2, (t, o) async => _tap(t, 'doc.approvals')),
    'labels': (2, (t, o) async {
      await _tap(t, 'doc.labels');
      await scan(t, '6221234567890');
    }),
    'outbox': (3, (t, o) async {}),
  };

  final variants = <String, ({Locale locale, ThemeMode mode, Size size})>{
    'ar_light_phone': (locale: const Locale('ar'), mode: ThemeMode.light, size: kPhone),
    'en_dark_phone': (locale: const Locale('en'), mode: ThemeMode.dark, size: kPhone),
    'ar_dark_handheld': (locale: const Locale('ar'), mode: ThemeMode.dark, size: kHandheld),
    'en_light_tablet': (locale: const Locale('en'), mode: ThemeMode.light, size: kTablet),
  };

  for (final MapEntry(key: name, value: (dest, go)) in screens.entries) {
    for (final MapEntry(key: vname, value: v) in variants.entries) {
      testWidgets('golden $name $vname', (tester) async {
        final office = FakeOffice()..permissions = [...kSupervisor];
        final store = await _storeWith(name == 'outbox', office);
        await openApp(tester, office, dest: dest, locale: v.locale, mode: v.mode, size: v.size, store: store);
        await go(tester, office);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/docs_${name}_$vname.png'));
      });
    }
  }
}

/// The outbox screen needs something to show: one accepted and one rejected entry.
Future<WhLocalStore> _storeWith(bool outbox, FakeOffice office) async {
  final store = WhLocalStore.memory();
  if (!outbox) return store;
  final ob = WhOutbox(store, await signedIn(office), WhSyncState());
  await ob.enqueue('receipt_lines', '/api/m1/wh/po/PO1/receipts', {'globalId': 'r1'});
  await ob.drain();
  office.rejectWith = 'over_receipt';
  await ob.enqueue('receipt_submit', '/api/m1/wh/receipts/r1/submit', const {});
  await ob.drain();
  office.rejectWith = null;
  return store;
}

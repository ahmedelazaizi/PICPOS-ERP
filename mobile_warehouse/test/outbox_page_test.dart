// NEW-03: a dead-lettered entry has a «Retry» action and every rejected entry
// is discarded only after a confirmation (AR/EN, light/dark).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import 'docs_flow_test.dart' show openApp, signedIn;
import 'fake_office.dart';
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  for (final (locale, mode, retry, discard) in [
    (const Locale('en'), ThemeMode.light, 'Retry', 'Discard'),
    (const Locale('ar'), ThemeMode.dark, 'إعادة المحاولة', 'تجاهل'),
  ]) {
    testWidgets('${locale.languageCode}/${mode.name}: retry re-queues a dead_letter entry; discard asks first', (tester) async {
      final office = FakeOffice();
      final store = WhLocalStore.memory();
      final session = await signedIn(office);
      final outbox = WhOutbox(store, session, WhSyncState());
      final dead = await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
      final refused = await outbox.enqueue('transfer_dispatch', '/api/m1/wh/transfers/t1/dispatch', const {});
      for (final id in [dead, refused]) {
        final e = (await store.store.outboxEntry(id))!
          ..status = OutboxStatus.rejected
          ..error = id == dead ? 'dead_letter' : 'stock_changed';
        await store.store.updateOutbox(e);
      }

      await openApp(tester, office, dest: 3, store: store, session: session, locale: locale, mode: mode);
      expect((tester.widget<Text>(find.byKey(const Key('outbox.counts')))).data, contains('\u2066'), reason: 'WH-022: numbers are LTR-isolated in RTL text');
      expect(find.byKey(Key('outbox.retry.$dead')), findsOneWidget);
      expect(find.byKey(Key('outbox.retry.$refused')), findsNothing, reason: 'a normal refusal is final: no retry');
      expect(find.byTooltip(retry), findsOneWidget);

      // discard asks first; «cancel» keeps the entry
      await tester.tap(find.byKey(Key('outbox.dismiss.$refused')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outbox.discardDialog')), findsOneWidget);
      expect(find.text(discard), findsOneWidget);
      await tester.tap(find.byKey(const Key('outbox.discard.no')));
      await tester.pumpAndSettle();
      expect((await store.store.outboxEntry(refused))!.error, 'stock_changed');
      await tester.tap(find.byKey(Key('outbox.dismiss.$refused')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('outbox.discard.yes')));
      await tester.pumpAndSettle();
      expect((await store.store.outboxEntry(refused))!.error, 'dismissed');

      await tester.tap(find.byKey(Key('outbox.retry.$dead')));
      await tester.pumpAndSettle();
      final e = (await store.store.outboxEntry(dead))!;
      expect(e.error, isNull);
      expect(e.status, isNot(OutboxStatus.rejected), reason: 'back in the queue (or already sent by the shell)');
      expect(find.byKey(Key('outbox.retry.$dead')), findsNothing);
    });
  }
}

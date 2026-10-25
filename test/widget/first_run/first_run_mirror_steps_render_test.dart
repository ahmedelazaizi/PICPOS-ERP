// A1: the NEW mirror steps (link by code, first sync, first-user account with
// the temporary-password change) render and behave in AR/EN x light/dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'EN' : 'AR'}/${dark ? 'dark' : 'light'}';
      testWidgets('[$tag] mirror: code link -> sync -> first user (temporary '
          'password) -> review', (tester) async {
        useLocale(english: english);
        final h = FirstRunHarness();
        await h.pump(tester, dark: dark);
        await tester.ensureVisible(find.byKey(const Key('first_run_advanced')));
        await tester.tap(find.byKey(const Key('first_run_advanced')));
        await tester.pumpAndSettle();
        await tapKey(tester, 'first_run_path_mirror');
        await tapKey(tester, 'first_run_next');

        // link: code + device name (no admin credentials, no key)
        expect(find.byKey(const Key('first_run_link_code')), findsOneWidget);
        expect(find.byKey(const Key('first_run_link_device')), findsOneWidget);
        expect(find.byKey(const Key('first_run_link_admin')), findsNothing);
        expect(find.byKey(const Key('first_run_link_admin_password')), findsNothing);
        expect(tester.takeException(), isNull);
        await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
        await enterKey(tester, 'first_run_link_device', 'MGR-1');
        await enterKey(tester, 'first_run_link_code', 'MIRR1234');
        await tapKey(tester, 'first_run_link_connect');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('first_run_link_badge')), findsOneWidget);

        await tapKey(tester, 'first_run_next');
        expect(find.byKey(const Key('first_run_sync_start')), findsOneWidget);
        await tapKey(tester, 'first_run_sync_start');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('first_run_sync_branch_7')), findsNothing,
            reason: 'a mirror is not branch-bound');
        await tapKey(tester, 'first_run_next');

        // account: temporary password -> a new-password field appears
        await enterKey(tester, 'first_run_account_username', 'mgr1');
        await enterKey(tester, 'first_run_account_password', 'Temp#Pass1');
        await tapKey(tester, 'first_run_account_verify');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('first_run_account_new_password')), findsOneWidget);
        expect(find.byKey(const Key('first_run_account_error')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await enterKey(tester, 'first_run_account_new_password', 'Brand#New123');
        await tapKey(tester, 'first_run_account_verify');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('first_run_account_badge')), findsOneWidget);
        expect(find.byKey(const Key('first_run_account_result')), findsOneWidget);
        expect(h.container.read(firstRunControllerProvider).draft.path,
            FirstRunPath.mirror);
        expect(tester.takeException(), isNull);
        await h.teardown(tester);
      });
    }
  }
}

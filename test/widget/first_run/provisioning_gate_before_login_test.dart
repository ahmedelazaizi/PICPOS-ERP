// A1: the gate wraps `MaterialApp.home` BEFORE the login.
//  * new device            -> the first-run setup, WITHOUT any login
//  * networked + restarted -> the one-time self-check, then the login
//  * provisioned           -> the login (child) untouched
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_self_check_screen.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_setup_screen.dart';
import 'package:picpos_erp/presentation/screens/first_run/provisioning_gate.dart';
import 'package:picpos_erp/presentation/screens/first_run/provisioning_providers.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';

import 'first_run_test_kit.dart';

class _Runner implements SelfCheckRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<SelfCheckReport> run() async => const SelfCheckReport([
        SelfCheckItem(SelfCheckId.record, SelfCheckStatus.pass),
      ]);
}

Future<void> _pump(WidgetTester tester, AppDatabase db, FirstRunHarness h) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        selfCheckRunnerProvider.overrideWithValue(_Runner()),
        ...h.overrides,
      ],
      child: const MaterialApp(
        home: ProvisioningGate(child: Text('LOGIN', key: Key('login_screen'))),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(loadEnglishCatalog);
  setUp(() => ProvisioningApplier.last = const AdoptReport());
  tearDown(() => useLocale(english: false));

  testWidgets('new device: the setup comes FIRST, with no login in sight',
      (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() => db.getBranches());
    final h = FirstRunHarness();
    await _pump(tester, db, h);
    expect(find.byType(FirstRunSetupScreen), findsOneWidget);
    expect(find.byKey(const Key('login_screen')), findsNothing);
    await h.teardown(tester);
  });

  testWidgets('provisioned (and verified): the login child is shown, the setup '
      'is skipped and nothing is written', (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      await db.setSetting('setup_completed', 'true');
    });
    final h = FirstRunHarness();
    await _pump(tester, db, h);
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    expect(find.byType(FirstRunSetupScreen), findsNothing);
    expect(find.byType(FirstRunSelfCheckScreen), findsNothing);
    expect(h.settings.values, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a networked setup just finished: self-check BEFORE the login',
      (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      await db.setSetting('setup_completed', 'true');
      await ProvisioningStore.write(
          db,
          ProvisioningRecord(
            mode: 'mirror',
            deviceKind: 'mirror',
            setupCompletedAt: DateTime.now().toUtc(),
            selfCheckPending: true,
          ));
    });
    final h = FirstRunHarness();
    await _pump(tester, db, h);
    expect(find.byType(FirstRunSelfCheckScreen), findsOneWidget);
    expect(find.byKey(const Key('login_screen')), findsNothing);

    // pass -> pending cleared -> the gate re-evaluates -> the login
    await tester.tap(find.byKey(const Key('self_check_continue')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    final rec = await tester.runAsync(() => ProvisioningStore.read(db));
    expect(rec!.selfCheckPending, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('setup finished (standalone "start") -> the gate lets the login '
      'through', (tester) async {
    useLocale(english: false);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() => db.getBranches());
    final h = FirstRunHarness();
    await _pump(tester, db, h);
    expect(find.byType(FirstRunSetupScreen), findsOneWidget);

    await tester.runAsync(() => db.setSetting('setup_completed', 'true'));
    ProviderScope.containerOf(tester.element(find.byType(FirstRunSetupScreen)))
        .invalidate(gateStageProvider);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

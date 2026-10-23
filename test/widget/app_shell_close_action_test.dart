// «إغلاق البرنامج» (manual close button) must consult the dirty-screens
// registry before it offers to exit; a refusal keeps the app open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/dirty_screens_registry.dart';
import 'package:picpos_erp/presentation/shell/app_shell_close_action.dart';

void main() {
  late List<String> log;
  late DirtyScreensRegistry registry;

  setUp(() {
    log = [];
    registry = DirtyScreensRegistry();
  });

  Future<void> pumpAndRun(
    WidgetTester tester, {
    int cart = 0,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    // ignore: unawaited_futures
    runCloseAppAction(
      context: ctx,
      cartItemCount: cart,
      registry: registry,
      backup: () async => log.add('backup'),
      exitApp: () => log.add('exit'),
    );
    await tester.pumpAndSettle();
  }

  void registerDirty({required bool discard}) {
    registry.register(
      Object(),
      screenIndex: 3,
      isDirty: () => true,
      confirmDiscard: () async {
        log.add('confirmDiscard');
        return discard;
      },
    );
  }

  testWidgets('clean registry: goes straight to the exit dialog',
      (tester) async {
    await pumpAndRun(tester);
    expect(find.text('إغلاق البرنامج'), findsOneWidget);
    expect(log, isEmpty);
    await tester.tap(find.text('إغلاق وبالنسخ الاحتياطي'));
    await tester.pumpAndSettle();
    expect(log, ['backup', 'exit']);
  });

  testWidgets('dirty screen: asks to discard BEFORE the exit dialog',
      (tester) async {
    registerDirty(discard: true);
    await pumpAndRun(tester);
    expect(log, ['confirmDiscard']);
    expect(find.text('إغلاق البرنامج'), findsOneWidget);
    expect(log, isNot(contains('exit')));
  });

  testWidgets('dirty screen refused: no dialog, no backup, no exit',
      (tester) async {
    registerDirty(discard: false);
    await pumpAndRun(tester);
    expect(log, ['confirmDiscard']);
    expect(find.text('إغلاق البرنامج'), findsNothing);
  });

  testWidgets('non-empty cart blocks before the registry is consulted',
      (tester) async {
    registerDirty(discard: true);
    await pumpAndRun(tester, cart: 2);
    expect(log, isEmpty);
    expect(find.text('لا يمكن إغلاق البرنامج'), findsOneWidget);
  });
}

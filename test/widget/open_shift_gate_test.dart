// ═══════════════════════════════════════════════════════════════════════════
// `ensureShiftClosed` — the forced shift-close gate shared by TWO paths:
//   • تسجيل الخروج            (app_shell.dart)
//   • تحويل المستخدم في نقطة البيع (picpos_switch_user_dialog.dart)
//
// The gate used to return `blocked` for BOTH "user cancelled" and "shift was
// closed successfully". That was invisible while logout was its only caller —
// the closing dialog logs the user out itself, so nothing needed to continue.
// But it made the switch-user path impossible: after closing the shift the
// switch dialog was never reached and the cashier landed on the login screen.
//
// These tests pin the three-way result, because collapsing `closed` back into
// `blocked` breaks switch-user, and treating `closed` as "proceed" in the
// LOGOUT path would show a logout dialog to an already-logged-out user.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/pos/logic/open_shift_gate.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

/// Only `getCurrentOpenShift` matters here; `noSuchMethod` absorbs the rest of
/// the 30-plus member interface so this fake doesn't rot every time it grows.
class _FakeTreasuryRepo implements ITreasuryRepository {
  /// Queue of answers, consumed one per call. The gate asks TWICE — once to
  /// detect the open shift, once after the closing dialog to verify it really
  /// closed — so the two answers must be independently controllable.
  final List<ShiftData?> answers;
  int calls = 0;

  _FakeTreasuryRepo(this.answers);

  @override
  Future<ShiftData?> getCurrentOpenShift(int userId) async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls++;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ShiftData _openShift() => ShiftData(
      id: 7,
      userId: 42,
      startTime: DateTime(2026, 1, 1, 8),
      openingBalance: 0,
      status: 'open',
    );

UserWithRole _cashier() {
  final role = Role(
    id: 1,
    name: 'كاشير',
    isSystemRole: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: 42,
    username: 'cashier',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: 'كاشير',
    roleId: 1,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

void main() {
  setUp(() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    WebSocketSyncClient.instance.connected.value = false;
  });

  /// Drives the gate inside a real widget tree (it shows dialogs).
  ///
  /// [confirmClose] taps «إغلاق الوردية» on the warning dialog when true, and
  /// «إلغاء» when false. [onClosingDialog] stands in for the brand closing
  /// dialog so no financial code runs here.
  Future<ShiftGateResult> runGate(
    WidgetTester tester, {
    required List<ShiftData?> shiftAnswers,
    required bool confirmClose,
    bool signedIn = true,
    VoidCallback? onClosingDialog,
  }) async {
    ShiftGateResult? result;

    // Signing in BEFORE pumping: calling `login()` from inside `build` trips
    // Riverpod's "modified a provider while the tree was building" assert.
    final container = ProviderContainer(
      overrides: [
        treasuryRepositoryProvider
            .overrideWithValue(_FakeTreasuryRepo(shiftAnswers)),
      ],
    );
    addTearDown(container.dispose);
    if (signedIn) container.read(authProvider.notifier).login(_cashier());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await ensureShiftClosed(
                    context: context,
                    ref: ref,
                    reason: 'اختبار',
                    showClosingDialog: (ctx) async {
                      onClosingDialog?.call();
                    },
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // The «وردية مفتوحة» warning only appears when a shift was found.
    if (find.text('وردية مفتوحة').evaluate().isNotEmpty) {
      await tester.tap(find.text(confirmClose ? 'إغلاق الوردية' : 'إلغاء'));
      await tester.pumpAndSettle();
    }
    return result!;
  }

  testWidgets('no open shift → clear (the caller proceeds untouched)',
      (tester) async {
    final result = await runGate(tester,
        shiftAnswers: [null], confirmClose: false);
    expect(result, ShiftGateResult.clear);
  });

  testWidgets('not signed in → clear', (tester) async {
    final result = await runGate(tester,
        shiftAnswers: [_openShift()], confirmClose: false, signedIn: false);
    expect(result, ShiftGateResult.clear,
        reason: 'no user means no shift to attribute');
  });

  testWidgets('open shift + cashier cancels → blocked', (tester) async {
    var closingShown = false;
    final result = await runGate(
      tester,
      shiftAnswers: [_openShift(), _openShift()],
      confirmClose: false,
      onClosingDialog: () => closingShown = true,
    );

    expect(result, ShiftGateResult.blocked);
    expect(closingShown, isFalse,
        reason: 'cancelling must not open the closing dialog');
  });

  testWidgets('open shift + closed successfully → closed', (tester) async {
    var closingShown = false;
    final result = await runGate(
      tester,
      // First answer: the shift exists. Second: it is gone → really closed.
      shiftAnswers: [_openShift(), null],
      confirmClose: true,
      onClosingDialog: () => closingShown = true,
    );

    expect(closingShown, isTrue);
    expect(result, ShiftGateResult.closed,
        reason: 'switch-user relies on this to continue to its own dialog');
  });

  testWidgets('closing dialog dismissed without closing → blocked',
      (tester) async {
    // The cashier opened the closing dialog and backed out of it. The gate
    // must not take "the dialog returned" as "the shift closed" — it re-reads
    // the shift, which is still open.
    final result = await runGate(
      tester,
      shiftAnswers: [_openShift(), _openShift()],
      confirmClose: true,
      onClosingDialog: () {},
    );

    expect(result, ShiftGateResult.blocked,
        reason: 'the shift is still open, so nobody may proceed');
  });

  testWidgets('the shift is re-read after the closing dialog', (tester) async {
    final repo = _FakeTreasuryRepo([_openShift(), null]);
    ShiftGateResult? result;

    final container = ProviderContainer(
      overrides: [treasuryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.read(authProvider.notifier).login(_cashier());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () async => result = await ensureShiftClosed(
                  context: context,
                  ref: ref,
                  reason: 'اختبار',
                  showClosingDialog: (ctx) async {},
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إغلاق الوردية'));
    await tester.pumpAndSettle();

    expect(result, ShiftGateResult.closed);
    expect(repo.calls, 2,
        reason: 'the DB is the source of truth, not the dialog returning — '
            'showClosingDialog is Future<void> and cannot report success');
  });
}

// M2 (plan 2026-10-24, MIR-008): the console turns READ-ONLY by itself.
//
// Before: `mutationGuardProvider` was only re-evaluated when auth / the socket /
// MirrorState changed, and a FAILED heartbeat changes none of them - so a console
// left on a list view stayed "writable" for ever after the main went away.
// Now the provider schedules a timer for the exact moment the link crosses the
// 5-minute threshold (fake clock: no sleeping), and a failed heartbeat bumps the
// revision.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/providers/mutation_guard_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/services/mirror_connectivity.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: true);
}

class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(mutationGuardProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(g.canMutate ? 'WRITABLE' : 'READ-ONLY'),
    );
  }
}

void main() {
  var now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorConnectivity.debugUseClock(() => now);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'hq:8080',
      lastHandshakeAt: now.subtract(const Duration(seconds: 10)),
    );
  });
  tearDown(() {
    MirrorConnectivity.debugReset();
    MirrorState.instance.debugSetForTests();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  Future<void> pumpProbe(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith(_Auth.new)],
          child: const _Probe(),
        ),
      );

  testWidgets('five minutes of silence flip the guard to read-only with NO '
      'interaction and no state change', (tester) async {
    await pumpProbe(tester);
    expect(find.text('WRITABLE'), findsOneWidget);

    // nothing happens for 4 minutes: still writable
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(minutes: 4));
    expect(find.text('WRITABLE'), findsOneWidget);

    // the threshold (5 min after the last answer) passes: the timer fires
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('READ-ONLY'), findsOneWidget);
    expect(MutationGuard.current.canMutate, isFalse,
        reason: 'the static snapshot the DAOs consult agrees');
  });

  testWidgets('a heartbeat that comes back restores writing', (tester) async {
    await pumpProbe(tester);
    now = now.add(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    await tester.pump();
    expect(find.text('READ-ONLY'), findsOneWidget);

    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'hq:8080',
      lastHandshakeAt: now,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('WRITABLE'), findsOneWidget);
  });

  testWidgets('off a mirror the guard never goes read-only on silence',
      (tester) async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    await pumpProbe(tester);
    now = now.add(const Duration(hours: 3));
    await tester.pump(const Duration(hours: 3));
    expect(find.text('WRITABLE'), findsOneWidget);
  });
}

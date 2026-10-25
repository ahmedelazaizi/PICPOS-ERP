// A1 (adoption contract §C.7-7): the gate that wraps `MaterialApp.home`.
//
//   not provisioned  -> the first-run setup, WITHOUT a login (a new device never
//                       needs the seeded admin/admin)
//   self-check due   -> the self-check screen, then the login
//   otherwise        -> [child] (the login screen / the app)
//
// Re-provisioning later is only possible from inside a session (settings) or
// from the self-check / Fatal screens with a confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/deployment/gate_stage.dart';
import 'first_run_self_check_screen.dart';
import 'first_run_setup_screen.dart';
import 'provisioning_providers.dart';

class ProvisioningGate extends ConsumerWidget {
  const ProvisioningGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(gateStageProvider);
    return stage.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // Never lock the owner out on a read failure: the login screen decides.
      error: (_, _) => child,
      data: (s) => switch (s) {
        GateStage.setup => FirstRunSetupScreen(
            // "Start" (standalone): re-evaluate -> the login screen.
            onStart: () => ref.invalidate(gateStageProvider),
          ),
        GateStage.selfCheck => FirstRunSelfCheckScreen(
            onPassed: () => ref.invalidate(gateStageProvider),
          ),
        GateStage.ready => child,
      },
    );
  }
}

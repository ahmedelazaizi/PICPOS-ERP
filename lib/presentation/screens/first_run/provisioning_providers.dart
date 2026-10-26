// A1: providers of the provisioning gate / self-check / re-provision entry.
// All replaceable in tests; presentation never touches the database type.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../../services/deployment/gate_stage.dart';
import '../../../services/deployment/provisioning_reset.dart';
import '../../../services/deployment/self_check.dart';
import '../../../services/network_service.dart';
import '../../../services/server_proxy.dart';

/// What the boot shows before the login (re-evaluate with `ref.invalidate`).
final gateStageProvider = FutureProvider.autoDispose<GateStage>(
  (ref) => resolveGateStage(ref.read(databaseProvider)),
);

/// The self-check runner (probes the main through the paired connection).
final selfCheckRunnerProvider = Provider.autoDispose<SelfCheckRunner>((ref) {
  return SelfCheckRunner(
    db: ref.read(databaseProvider),
    probeServer: () async {
      final ns = NetworkService.instance;
      final r = await ns.testServerConnection(
          ns.serverAddress ?? '', ns.serverPort);
      return r['success'] == true;
    },
    // One real delta page through the authenticated sync endpoint (the runner
    // enforces the 60 s budget).
    deltaPull: () async =>
        await ServerProxy.instance.fetchDelta('settings',
            since: DateTime.now().subtract(const Duration(minutes: 1)),
            limit: 1) !=
        null,
    // The main's settings through this device's own token (no shared key).
    fetchMainSettings: () async {
      final token = ServerProxy.instance.apiToken;
      if (token == null || token.isEmpty) return null;
      final feed =
          await ServerProxy.instance.fetchFeedWithToken('/api/settings', token);
      final s = feed?['settings'];
      if (s is! Map) return null;
      return {for (final e in s.entries) '${e.key}': '${e.value}'};
    },
  );
});

/// Writes behind the self-check / re-provision screens.
class ProvisioningActions {
  ProvisioningActions(this._ref);
  final Ref _ref;

  Future<void> markSelfCheckPassed() =>
      markSelfCheckPassedIn(_ref.read(databaseProvider));

  /// The ONE way to change the mode afterwards: forget the mode, the pairing and
  /// the first-run flags; the next launch starts the first-run setup.
  Future<void> reprovision() => resetProvisioning(_ref.read(databaseProvider));
}

final provisioningActionsProvider =
    Provider<ProvisioningActions>(ProvisioningActions.new);

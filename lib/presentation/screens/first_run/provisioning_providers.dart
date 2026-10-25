// A1: providers of the provisioning gate / self-check / re-provision entry.
// All replaceable in tests; presentation never touches the database type.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../../services/deployment/gate_stage.dart';
import '../../../services/deployment/provisioning_reset.dart';
import '../../../services/deployment/self_check.dart';
import '../../../services/network_service.dart';

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

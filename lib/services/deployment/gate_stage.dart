// A1: what the boot shows BEFORE the login screen, decided from the device
// record - not from a user session (first run needs no login, no seeded admin).
//
//   setup     the device is not provisioned  -> first-run setup, no login
//   selfCheck a networked setup just finished (restart done) or the pairing
//             identity needs repair          -> self-check screen, then login
//   ready     provisioned and verified       -> the login screen / the app
library;

import '../../data/database/database.dart';
import 'provisioning_applier.dart';
import 'provisioning_record.dart';

enum GateStage { setup, selfCheck, ready }

Future<GateStage> resolveGateStage(AppDatabase db) async {
  final completed =
      (await db.getSettingValue('setup_completed'))?.trim() == 'true';
  if (!completed) return GateStage.setup;
  final record = await ProvisioningStore.read(db);
  if (ProvisioningApplier.last.rePairRequired) return GateStage.selfCheck;
  if (record != null && record.selfCheckPending) return GateStage.selfCheck;
  return GateStage.ready;
}

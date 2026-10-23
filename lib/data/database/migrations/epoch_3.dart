part of '../database.dart';

extension Epoch3Migrations on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // EPOCH 3: v81 → v111 — Enterprise, advanced features, latest PIR
  // ═══════════════════════════════════════════════════════════════════════════
  /// Epoch 3 entry point. The step bodies live in the `epoch_3_vNNN_vNNN.dart`
  /// parts (pure move); they MUST stay called in this exact order — it is the
  /// literal execution order of the original single method.
  Future<void> _migrateEpoch3(Migrator m, int from) async {
    await _migrateEpoch3V081ToV093(m, from);
    await _migrateEpoch3V094ToV118(m, from);
    await _migrateEpoch3V119ToV133(m, from);
    await _migrateEpoch3V134ToV147(m, from);
    await _migrateEpoch3V148ToV156(m, from);
    await _migrateEpoch3V157ToV166(m, from);
    await _migrateEpoch3V167ToV173(m, from);
    await _migrateEpoch3V174ToV195(m, from);
    await _migrateEpoch3V196ToV205(m, from);
  }
}

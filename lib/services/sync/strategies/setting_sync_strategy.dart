// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class SettingSyncStrategy extends SyncStrategy {
  SettingSyncStrategy(super.db);

  @override
  String get tableName => 'settings';

  @override
  String get apiEndpoint => '/api/settings';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final settingsMap = json['settings'] as Map<String, dynamic>;
    
    // إعدادات خاصة بالجهاز أو الفرع لا يجب طمسها من السيرفر الرئيسي
    const devSpecificKeys = [
      // ── Device identity / mode ──────────────────────────────────────
      // Spec 089: network_mode and deployment_mode are per-device. The
      // server stores 'server'; the client stores 'client'. Writing the
      // server's value into the client's DB causes the client to restart
      // as a server on the next boot (reconcileWithDb sees DB='server'
      // and promotes it). These keys MUST never be overwritten by sync.
      'network_mode',
      'deployment_mode',
      // Wizard completion flags are also per-device — overwriting them
      // with the server's value skips the wizard on a fresh client
      // install or incorrectly marks first-sync as done.
      'setup_completed',
      'client_first_sync_completed',
      // Mirror (Spec 131) uses the same first-sync contract. These flags are
      // per-device too — if the server payload ever carries them they must NOT
      // be written mid-performFirstSync (would flip isFirstSyncPending false
      // before the seeded-data wipe, leaving partial seeded master data — R8).
      'mirror_first_sync_completed',
      'mirror_cache_integrity_v1_applied',
      // client_branch_id records which branch THIS device belongs to.
      // The server has no client_branch_id of its own, but guard it
      // defensively so a misconfigured server row never clobbers the
      // client's branch assignment.
      'client_branch_id',
      // ── POS hardware mappings (per-terminal) ────────────────────────
      'pos_cash_safe_id',
      'pos_bank_safe_id',
      'pos_click_safe_id',
      'pos_default_warehouse_id',
      'device_id',
      'machine_id',
      'pos_receipt_printer',
      'pos_kitchen_printer',
      // Feature 031 — touch keyboard is per-device hardware preference
      // (FR-019). Server never overrides what the operator picked at
      // each terminal.
      'touchMode',
    ];

    for (final entry in settingsMap.entries) {
      if (!devSpecificKeys.contains(entry.key)) {
        await db.setSetting(entry.key, entry.value?.toString() ?? '');
      }
    }
    // Force UI refresh after sync
    if (settingsMap.isNotEmpty) {
      db.markTablesUpdated({db.settings});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    // Settings are handled differently in the DB (key-value pair)
    // For now, this is not used via generic upsert in the same way
    throw UnimplementedError('SettingSyncStrategy uses setSetting instead of upsert');
  }
}
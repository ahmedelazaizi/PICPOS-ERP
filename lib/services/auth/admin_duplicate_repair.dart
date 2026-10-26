// Login leftover #3: repairs a device that already has TWO active `admin` rows
// - the seeded/bootstrap row (id 1) and a later renumbered row an old sync
// created next to it (the prevention lives in `UserSyncStrategy`).
//
// Contract (idempotent, run at boot of a paired device and after a users sync):
//  * id 1 stays THE single active system admin;
//  * it adopts the main's credential (hash/salt/force flag), global id and
//    credential stamp from the stray that carries them;
//  * every stray is deactivated and renamed `__dup_<id>_admin` (the same
//    convention the sync dedupe uses) - NEVER deleted: invoices, journal and
//    audit rows that reference it keep resolving;
//  * nothing is touched unless a row with username `admin` AND id 1 exists with
//    at least one other active `admin` row.
library;

import 'package:drift/drift.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import 'credential_stamp_store.dart';

class AdminRepairReport {
  const AdminRepairReport({
    this.keptId,
    this.adoptedFromId,
    this.deactivatedIds = const [],
  });

  /// The surviving admin row (always 1 when anything was repaired).
  final int? keptId;

  /// The stray whose credential / global id was adopted (if any carried one).
  final int? adoptedFromId;
  final List<int> deactivatedIds;

  bool get changed => deactivatedIds.isNotEmpty;
}

const _adminName = 'admin';
const _systemAdminId = 1;

Future<AdminRepairReport> repairDuplicateAdmins(
  AppDatabase db, {
  CredentialStampStore? stamps,
}) async {
  try {
    return await _repair(db, stamps ?? CredentialStampStore.forDb(db));
  } catch (e) {
    // Never block a boot / a sync on the repair itself.
    await DiagnosticLogger.log('ADMIN-DEDUP', 'repair failed: $e');
    return const AdminRepairReport();
  }
}

Future<AdminRepairReport> _repair(
    AppDatabase db, CredentialStampStore stamps) async {
  final rows = await (db.select(db.users)
        ..where((u) => u.username.equals(_adminName)))
      .get();
  final keeper = rows.where((u) => u.id == _systemAdminId).firstOrNull;
  if (keeper == null) return const AdminRepairReport();
  final strays = rows.where((u) => u.id != _systemAdminId && u.isActive).toList();
  if (strays.isEmpty) return const AdminRepairReport();

  // The stray that carries the main's data: a usable credential first, then a
  // global id, then the newest row.
  bool usable(User u) => u.passwordHash.isNotEmpty;
  final ranked = [...strays]..sort((a, b) {
      int score(User u) => (usable(u) ? 2 : 0) + (u.globalId != null ? 1 : 0);
      final c = score(b).compareTo(score(a));
      return c != 0 ? c : b.id.compareTo(a.id);
    });
  final donor = ranked.first;
  final donorHasCredential = usable(donor);
  final donorStamp = donorHasCredential ? await stamps.read(donor.id) : null;

  await db.transaction(() async {
    // The unique global id must leave the stray BEFORE the keeper takes it.
    for (final s in strays) {
      await (db.update(db.users)..where((u) => u.id.equals(s.id))).write(
        UsersCompanion(
          username: Value('__dup_${s.id}_$_adminName'),
          isActive: const Value(false),
          globalId: const Value(null),
        ),
      );
    }
    await (db.update(db.users)..where((u) => u.id.equals(_systemAdminId))).write(
      UsersCompanion(
        // The main is the source of truth for the identity.
        globalId: donor.globalId != null
            ? Value(donor.globalId)
            : const Value.absent(),
        passwordHash:
            donorHasCredential ? Value(donor.passwordHash) : const Value.absent(),
        passwordSalt:
            donorHasCredential ? Value(donor.passwordSalt) : const Value.absent(),
        forcePasswordChange: donorHasCredential
            ? Value(donor.forcePasswordChange)
            : const Value.absent(),
        isActive: const Value(true),
      ),
    );
  });

  if (donorHasCredential) {
    try {
      await stamps.moveStamp(donor.id, _systemAdminId, donor.passwordHash,
          stamp: donorStamp);
    } catch (e) {
      await DiagnosticLogger.log('ADMIN-DEDUP', 'stamp move failed: $e');
    }
  }
  for (final s in strays) {
    if (s.id != donor.id) await stamps.revoke(s.id);
  }
  final report = AdminRepairReport(
    keptId: _systemAdminId,
    adoptedFromId: donorHasCredential || donor.globalId != null ? donor.id : null,
    deactivatedIds: [for (final s in strays) s.id],
  );
  await DiagnosticLogger.log(
      'ADMIN-DEDUP',
      'kept id=$_systemAdminId adopted_from=${report.adoptedFromId} '
          'deactivated=${report.deactivatedIds}');
  return report;
}

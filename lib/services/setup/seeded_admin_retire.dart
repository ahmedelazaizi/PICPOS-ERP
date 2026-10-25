// A1 (ADM-001/002): a paired branch / mirror device must not keep the seeded
// `admin`/`admin` login. After the first user's verification delivered the
// branch credentials the seeded credential is replaced by an UNUSABLE one (a
// random secret nobody knows - SEC-004): the row stays (invoices reference it)
// but nothing can sign in as `admin` until the main delivers the real admin
// credential. Idempotent: a no-op once `admin/admin` no longer verifies.
library;

import 'package:drift/drift.dart' show Value;

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../unusable_credential.dart';

/// Returns `true` when a seeded `admin/admin` credential was found and retired.
Future<bool> retireSeededAdmin(AppDatabase db) async {
  final seeded = await db.authenticateUser('admin', 'admin');
  if (seeded == null) return false;
  final cred = await UnusableCredential.mint();
  await (db.update(db.users)..where((u) => u.id.equals(seeded.user.id))).write(
    UsersCompanion(
      passwordHash: Value(cred.hash),
      passwordSalt: Value(cred.salt),
      forcePasswordChange: const Value(true),
    ),
  );
  await DiagnosticLogger.log(
      'ADMIN-RETIRE', 'seeded admin/admin credential retired (id=${seeded.user.id})');
  return true;
}

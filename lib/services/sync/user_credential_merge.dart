import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/unusable_credential.dart';

/// CRED-WIPE fix — the single rule deciding which password credential a
/// users sync/delta/full-sync merge keeps.
///
/// A credential is *complete* when it can verify a password on its own:
/// * Argon2id PHC (`$argon2…`) embeds its salt, so `password_salt == ''` is
///   the NORMAL form of every row written since the Week-8 upgrade;
/// * a legacy PBKDF2 hash needs a non-empty separate salt.
///
/// Requiring `salt.isNotEmpty` for everything (the old guard) classified every
/// Argon2id row as broken and replaced it with an unusable credential whenever
/// a pull arrived without credentials (no session, pairing window closed).
bool isCredentialComplete(String? hash, String? salt) {
  if (hash == null || hash.isEmpty) return false;
  if (hash.startsWith(r'$argon2')) return hash.split(r'$').length >= 6;
  return salt != null && salt.isNotEmpty;
}

enum CredentialSource { server, local, duplicate, unusable }

class CredentialResolution {
  const CredentialResolution(this.hash, this.salt, this.source);
  final String hash;
  final String salt;
  final CredentialSource source;
}

typedef UnusableMinter = Future<({String hash, String salt})> Function();

/// Priority: server (complete) → local row → deactivated offline duplicate →
/// freshly minted unusable credential. A complete local credential is NEVER
/// replaced by an unusable one.
Future<CredentialResolution> resolveCredential({
  String? serverHash,
  String? serverSalt,
  String? localHash,
  String? localSalt,
  String? dupHash,
  String? dupSalt,
  UnusableMinter mint = UnusableCredential.mint,
}) async {
  if (isCredentialComplete(serverHash, serverSalt)) {
    return CredentialResolution(serverHash!, serverSalt ?? '', CredentialSource.server);
  }
  if (isCredentialComplete(localHash, localSalt)) {
    return CredentialResolution(localHash!, localSalt ?? '', CredentialSource.local);
  }
  if (isCredentialComplete(dupHash, dupSalt)) {
    return CredentialResolution(dupHash!, dupSalt ?? '', CredentialSource.duplicate);
  }
  final u = await mint();
  return CredentialResolution(u.hash, u.salt, CredentialSource.unusable);
}

/// Delta-pull `users` row: the upsert is INSERT OR REPLACE, so every column
/// missing from the payload would be wiped. Re-attach the device-local
/// secrets (pin / card code / a complete local credential) the server withheld.
/// Returns a (possibly new) row map; [row] is not mutated.
Future<Map<String, dynamic>> preserveUserSecrets(
  AppDatabase db,
  Map<String, dynamic> row,
  int rowId,
) async {
  var out = row;
  try {
    final local = await db.customSelect(
      'SELECT pin, card_code, password_hash, password_salt FROM users '
      'WHERE id = ? LIMIT 1',
      variables: [Variable.withInt(rowId)],
    ).getSingleOrNull();
    if (local != null) {
      out = Map.of(out);
      out['pin'] ??= local.read<String?>('pin');
      out['card_code'] ??= local.read<String?>('card_code');
    }

    final sHash = out['password_hash'];
    final sSalt = out['password_salt'];
    if (isCredentialComplete(sHash is String ? sHash : null,
        sSalt is String ? sSalt : null)) {
      return out;
    }
    final username = out['username'] as String?;
    final lHash = local?.read<String?>('password_hash');
    final lSalt = local?.read<String?>('password_salt');
    final localOk = isCredentialComplete(lHash, lSalt);
    if (!localOk &&
        (username == null || username.isEmpty || username.startsWith('__dup_'))) {
      return out;
    }
    final r = await resolveCredential(localHash: lHash, localSalt: lSalt);
    out = Map.of(out);
    out['password_hash'] = r.hash;
    out['password_salt'] = r.salt;
    if (r.source == CredentialSource.unusable) {
      // Only a newly minted credential forces a change; a preserved one must
      // not re-flag a user who can log in (REPRO-R2-c).
      out['force_password_change'] = 1;
    }
    debugPrint('[DeltaPull] users id=$rowId: no credentials in payload — '
        'credential source=${r.source.name}');
  } catch (e) {
    debugPrint('[DeltaPull] users credential handling failed: $e');
  }
  return out;
}

/// Natural-key adoption for the bootstrap `admin`: a server `admin` whose
/// `global_id` differs from the seeded local one must map onto the local row
/// (single admin identity) instead of being renumbered next to it.
Future<int?> localAdminIdByUsername(AppDatabase db, Map<String, dynamic> row) async {
  if (row['username'] != 'admin') return null;
  final hit = await db.customSelect(
    "SELECT id FROM users WHERE username = 'admin' ORDER BY id LIMIT 1",
  ).getSingleOrNull();
  return hit?.read<int?>('id');
}

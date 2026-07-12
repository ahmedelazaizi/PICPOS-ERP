// Owner password-reset helper for UralCash ERP.
//
// Generates a `password_hash` + `password_salt` that are byte-compatible with
// the app's login check (SecurityService.verifyPassword), then prints a ready
// UPDATE statement. It does NOT touch the DB — paste the printed UPDATE into
// the same tool you use to query the (SQLCipher) database, on the machine that
// holds the encryption key.
//
// This is a legitimate RESET to a password YOU choose — it cannot and does not
// recover the existing password (that hash is one-way).
//
// Algorithm mirrors lib/services/security_service.dart EXACTLY:
//   salt = base64(32 secure-random bytes)
//   hash = base64( iterate 10000×: key = sha256(key) ; key0 = utf8(salt+password) )
//
// Usage:
//   dart run scripts/reset_user_password.dart <newPassword> [userId]
//   dart run scripts/reset_user_password.dart                 (password "admin", id 1)
//
// When [userId] is given the printed UPDATE targets that id exactly (fast +
// precise — avoids hitting a duplicated username like "عماد" twice).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

const int _saltLength = 32; // SecurityService._saltLength
const int _iterations = 10000; // SecurityService._iterations

String generateSalt() {
  final r = Random.secure();
  return base64Encode(List<int>.generate(_saltLength, (_) => r.nextInt(256)));
}

String hashPassword(String password, String salt) {
  List<int> key = utf8.encode('$salt$password');
  for (int i = 0; i < _iterations; i++) {
    key = sha256.convert(key).bytes;
  }
  return base64Encode(key);
}

void main(List<String> args) {
  final password = args.isNotEmpty ? args[0] : 'admin';
  final targetId = args.length > 1 ? int.tryParse(args[1]) : null;
  final salt = generateSalt();
  final hash = hashPassword(password, salt);

  // Self-check: prove the app's verifyPassword would accept this pair.
  final ok = hashPassword(password, salt) == hash;
  if (!ok || hash.length != 44 || salt.length != 44) {
    stderr.writeln('ERROR: self-check failed — do NOT use this output.');
    return;
  }

  print('-- ✅ self-check OK (matches SecurityService.verifyPassword)');
  print('-- new password : $password');
  print('-- password_salt: $salt   (len=${salt.length})');
  print('-- password_hash: $hash   (len=${hash.length})');
  print('--');
  final setClause =
      "SET password_hash = '$hash', password_salt = '$salt', "
      "force_password_change = 0, is_active = 1, is_locked = 0";
  if (targetId != null) {
    print('UPDATE users $setClause WHERE id = $targetId;');
  } else {
    print('-- target id 1 (default admin). Pass a 2nd arg for another user id.');
    print('UPDATE users $setClause WHERE id = 1;');
  }
}

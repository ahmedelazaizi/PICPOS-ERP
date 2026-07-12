// Spec 135 silent-drift (c) — structural guard: exactly ONE adjustPartyBalance.
//
// Two definitions used to exist: the atomic instance method in
// lib/data/database/daos/party_dao.dart (SQL `balance = balance + ?` +
// field-audit log) and a non-atomic duplicate (Dart read-modify-write, Lost
// Update race, no audit) as an extension method in parties_dao_ext.dart. The
// extension was permanently shadowed by the instance method, so it was dead —
// but a latent double-adjust trap if ever called explicitly. It was removed.
//
// This test pins that there is exactly one *definition* of adjustPartyBalance
// at the DATABASE/DAO layer, so the non-atomic copy can't quietly come back.
// (The repository layer — lib/data/repositories + lib/domain — legitimately
// declares its own delegating adjustPartyBalance; this guard only covers the
// db/dao layer where the duplicate lived.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exactly one adjustPartyBalance definition in lib/data/database', () {
    final libDir = Directory('lib/data/database');
    expect(libDir.existsSync(), isTrue, reason: 'run from package root');

    // Matches a method DEFINITION (returns Future<void>, named
    // adjustPartyBalance, with an opening paren) — not call sites.
    final defPattern = RegExp(r'Future<void>\s+adjustPartyBalance\s*\(');

    final hits = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      final count = defPattern.allMatches(content).length;
      if (count > 0) {
        hits.add('${entity.path}: $count');
      }
    }

    final total = hits.fold<int>(
      0,
      (sum, h) => sum + int.parse(h.split(': ').last),
    );

    expect(
      total,
      1,
      reason: 'Expected exactly ONE adjustPartyBalance definition '
          '(the atomic one in party_dao.dart). Found: $hits',
    );
  });
}

// Pre-deploy hardening (P2, sync audit 2026-07-13) — the settings-pull inside
// performFirstSync guards `client_first_sync_completed` in `devSpecificKeys`
// so it can't be set prematurely from the server payload, but the two MIRROR
// first-sync flags were NOT guarded. If the server's /api/settings ever carried
// `mirror_first_sync_completed`, syncFromJson would write it mid-first-sync →
// isFirstSyncPending() flips false BEFORE the seeded-data wipe → partial seeded
// master data survives (breaks the R8 "true = fully synced OR fully empty"
// invariant). Guard both mirror flags like the client flag.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const relPath = 'lib/services/sync/strategies/setting_sync_strategy.dart';
  late String source;

  setUpAll(() {
    final file = File(relPath);
    expect(file.existsSync(), isTrue, reason: 'expected strategy at $relPath');
    source = file.readAsStringSync();
  });

  test('devSpecificKeys guards mirror_first_sync_completed (R8)', () {
    expect(
      source.contains("'mirror_first_sync_completed'"),
      isTrue,
      reason: 'mirror_first_sync_completed must be in devSpecificKeys so a '
          'server settings payload cannot flip it mid-performFirstSync.',
    );
  });

  test('devSpecificKeys guards mirror_cache_integrity_v1_applied', () {
    expect(
      source.contains("'mirror_cache_integrity_v1_applied'"),
      isTrue,
      reason: 'mirror_cache_integrity_v1_applied must be in devSpecificKeys so '
          'the one-time re-sync flag is never overwritten by the server.',
    );
  });
}

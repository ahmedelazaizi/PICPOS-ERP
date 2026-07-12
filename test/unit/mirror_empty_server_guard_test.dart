// ═══════════════════════════════════════════════════════════════════════════
// Spec 131 — FR-008 mirror empty-server guard
// ═══════════════════════════════════════════════════════════════════════════
//
// After the mirror first-sync completes, if the server reported zero
// warehouses or zero branches, the committer MUST refuse to land the mirror
// in that state. The Arabic toast tells the user to set up the server first.
//
// These tests are source-level structural pins (the full committer flow
// requires a live SyncService + NetworkService stack — exercised by
// quickstart.md cells). The pins ensure the guard cannot regress silently.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/deployment/deployment_mode_committer.dart')
      .readAsStringSync();

  group('Spec 131 FR-008 — empty-server guard', () {
    test('committer invokes _checkMirrorMasterDataNonEmpty after first-sync',
        () {
      expect(src, contains('_checkMirrorMasterDataNonEmpty()'),
          reason: 'FR-008: committer must check warehouses + branches counts '
              'after a successful mirror first-sync.');
    });

    test('guard is mirror-only (not client)', () {
      // The call site is wrapped in `if (isMirror) { ... }`.
      final idx = src.indexOf('_checkMirrorMasterDataNonEmpty()');
      expect(idx, isNot(-1));
      // Look backwards in a small window for the gating `isMirror`.
      final window = src.substring((idx - 200).clamp(0, idx), idx);
      expect(window, contains('isMirror'),
          reason: 'Empty-server guard must only fire on mirror commits — '
              'clients can validly pair against a more empty server (they '
              'use a different flow + scope).');
    });

    test('helper reports Arabic refusal text and reasonCode', () {
      expect(src, contains("'MIRROR_SERVER_EMPTY'"),
          reason: 'reasonCode pin so log scanners can find the guard event.');
      expect(
          src,
          contains(
              'السيرفر لا يحتوى على فروع/مخازن — يرجى إعداد السيرفر'),
          reason: 'Arabic message must be present (Constitution VI).');
    });

    test('helper counts warehouses AND branches (both required)', () {
      expect(src, contains('FROM warehouses'));
      expect(src, contains('FROM branches'));
    });

    test('helper rolls back pairing when the guard trips', () {
      // The call site uses the same pairingDone / _rollbackPairing pattern as
      // the firstSync-failure branch, so a failed guard leaves no half-paired
      // state.
      expect(src, contains('await _rollbackPairing()'));
    });
  });

  group('Spec 136 ISS-3 — flag=true must re-verify, not commit blindly', () {
    test('the empty guard also runs on the sync-SKIPPED (flag=true) path', () {
      // Pre-fix the guard lived ONLY inside `if (needsSync)`, so a flag=true
      // boot skipped both sync AND the guard and could commit an empty
      // master-data window. The guard must now appear at least twice: once on
      // the needsSync path, once on the flag=true (else) path.
      final occurrences =
          RegExp('_checkMirrorMasterDataNonEmpty\\(\\)').allMatches(src).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: 'ISS-3: flag=true must still verify master-data is non-empty '
              'before committing.');
    });

    test('flag=true empty state triggers one forced re-pull recovery', () {
      expect(src, contains('COMMIT-RECOVER'),
          reason: 'ISS-3: an empty mirror on flag=true must attempt a forced '
              're-pull recovery (logged as COMMIT-RECOVER).');
      // The recovery forces first-sync (svc.reset + re-pull).
      expect(src, contains('_firstSync(contract, force: true)'),
          reason: 'ISS-3: recovery must force the re-pull, not rely on the '
              'already-true flag.');
    });

    test('recovery still fails loudly if the re-pull is still empty', () {
      // After the forced re-pull the guard runs again; if STILL empty it
      // returns the CommitFailed rather than proceeding to COMMIT-OK.
      expect(src, contains('stillEmpty'),
          reason: 'ISS-3: a re-pull that is still empty must block the commit, '
              'not land the cashier in a broken POS.');
    });
  });
}

// Spec 129 F5 / T043 — Structural guard against `[IDEM:` description-tag
// regressions.
//
// The legacy `[IDEM:cp-<paperId>-<status>]` description-tag dedup is being
// retired in favour of deterministic JE globalIds computed by
// `JournalEntryGid.compute` (see contracts/globalid-schema.md §3). The
// scanner stays alive for one release window (FR-503) so legacy rows still
// dedup, but no NEW write site may emit a `[IDEM:` literal (FR-504).
//
// This test walks `lib/` and fails if any production source file contains
// the literal `[IDEM:` outside the documented read-side allow-list. The
// allow-list is intentionally tight — every entry should be a scanner that
// CONSUMES tagged rows, not a writer that PRODUCES them.
//
// To add an allow-listed file, document why the read-side reference is
// needed and add a single line under `_allowedReadSideFiles` below.
// Promoting a write site requires migrating it to `JournalEntryGid` first.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Read-side scanners that must continue to recognise legacy `[IDEM:` rows
// during the transition window. Once those rows are zero in every
// production DB (verified by ops query), a follow-up spec deletes both the
// scanner and these entries.
const _allowedReadSideFiles = <String>{
  // commercial_papers_dao keeps `legacyIdemTag` matching in its dedup
  // predicate so existing tagged rows still cause skip-and-return. The
  // write path no longer emits new `[IDEM:` strings.
  'lib/data/database/daos/commercial_papers_dao.dart',
  // journal_entry_gid.dart's file-level doc explains what `[IDEM:…]` was;
  // no executable reference to the marker exists in this file.
  'lib/core/utils/journal_entry_gid.dart',
};

void main() {
  test('Spec 129 F5 / FR-504 — no new code emits [IDEM: literals', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'Test must run from URAL-ERP repo root.');

    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      // Normalise to forward slashes so the allow-list match is platform-stable.
      final normPath = entity.path.replaceAll(r'\', '/');
      if (_allowedReadSideFiles.contains(normPath)) continue;

      final content = entity.readAsStringSync();
      if (!content.contains('[IDEM:')) continue;

      // Find every line so the failure message points the developer at the
      // exact spot, not just the filename.
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('[IDEM:')) {
          offenders.add('$normPath:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '[no_idem_marker] New `[IDEM:` literal(s) found outside the read-side '
          'allow-list:\n${offenders.join('\n')}\n\n'
          'Migrate the write site to JournalEntryGid.compute(...) per '
          'specs/129-mirror-broadcast-discipline/contracts/globalid-schema.md §3.',
    );
  });
}

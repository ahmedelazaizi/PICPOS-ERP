// Spec 151 / BLOCKER C-01 — offline journal-entry dispatch + fail-loud default.
//
// Root cause (silent GL loss): the offline outbox producer
// (`_CwiSync.submitJournalEntry`, lib/services/interceptor/cwi_sync.dart:31-32)
// queues manual/auto journal entries with `tableName:'journal_entries'`. But
// `OfflineSyncWorker._replayOperation`'s switch had ONLY a (dead) `case
// 'journals':` and NO `case 'journal_entries':`, so every offline JE hit the
// switch's `default:` branch — which merely `debugPrint`'d and returned null
// WITHOUT throwing. `drainOutbox` then called `markAsSyncSuccess(item.id)`
// unconditionally, clearing the JE from the outbox. The GL write NEVER reached
// the server: silent double-entry loss, no dead-letter, no SYNC-WARN.
//
// This is a source-level guard (mirrors orchestrator_gate_predicate_test.dart):
// the real regression vector is a dispatch/switch gap, and `_replayOperation`
// is a private instance method that needs a live AppDatabase + ServerProxy to
// exercise end-to-end. The four assertions below each bite the exact defect:
//   1. a `case 'journal_entries'` now exists in the dispatch switch;
//   2. the `default:` branch THROWS (never silently returns null → success);
//   3. the permanent-error classifier routes an unknown table to dead-letter;
//   4. R9 — the journal-entries replay threads `globalId` into submitJournalEntry.
//
// All four FAIL against pre-fix source (no 'journal_entries' case, a
// debugPrint-only default, no 'Unknown sync table' classifier term, and a
// journals body that omitted globalId).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const relPath = 'lib/services/offline_sync_worker.dart';

  group('Offline JE dispatch + fail-loud default (Spec 151 / C-01)', () {
    late String source;

    setUpAll(() {
      final file = File(relPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'expected worker source at $relPath',
      );
      source = file.readAsStringSync();
    });

    test('_replayOperation has a journal_entries case (the producer\'s table name)',
        () {
      // The producer queues tableName:'journal_entries' (cwi_sync.dart:32).
      // Without a matching case the row falls through to `default:`.
      expect(
        source.contains("case 'journal_entries':"),
        isTrue,
        reason:
            "$relPath _replayOperation has no `case 'journal_entries':`. The "
            "outbox producer (cwi_sync.submitJournalEntry) queues offline "
            "journal entries under that exact table name; without the case they "
            "hit `default:` and are silently dropped from the GL. See Spec 151 "
            "BLOCKER C-01.",
      );
      // The 'journals' label is retained for the pull-side / websocket
      // subscription map (websocket_sync_client.dart:273). Guard against a
      // refactor deleting it.
      expect(
        source.contains("case 'journals':"),
        isTrue,
        reason:
            "$relPath dropped `case 'journals':`. It is still referenced by the "
            "pull-side subscription map; keep both labels folded onto the "
            "shared journal-entry replay body.",
      );
    });

    test('switch `default:` fails loud — throws, never silently returns null', () {
      // Anchor on the switch's `default:` CASE LABEL (a line-starting
      // `default:`) — the `\n\s*` prefix excludes inline-comment mentions like
      // `// default: slightly more...` elsewhere in the file. Confirm it throws
      // instead of the old debugPrint-and-skip. A silent default is precisely
      // what let the drain loop mark the item as synced and clear it.
      final defaultMatch = RegExp(r'\n\s*default:').firstMatch(source);
      expect(defaultMatch, isNotNull,
          reason: 'expected a `default:` case label in _replayOperation');
      final defaultIdx = defaultMatch!.start;
      final defaultBody = source.substring(
        defaultIdx,
        (defaultIdx + 700).clamp(0, source.length),
      );
      expect(
        defaultBody.contains("throw StateError('Unknown sync table"),
        isTrue,
        reason:
            "$relPath _replayOperation `default:` no longer throws on an "
            "unknown table. A silent default lets drainOutbox call "
            "markAsSyncSuccess and DROP the write (the C-01 GL-loss vector). "
            "It MUST throw StateError('Unknown sync table: ...').",
      );
      // Explicitly forbid the old silent-skip debugPrint text inside default.
      expect(
        defaultBody.contains('— skipping'),
        isFalse,
        reason:
            "$relPath _replayOperation `default:` still contains the old "
            "'— skipping' debugPrint. That path returns null → the item is "
            "marked synced and the write is silently lost.",
      );
    });

    test('unknown-table throw is classified permanent → dead-letter (not retried/synced)',
        () {
      // The thrown StateError message must be matched by the isPermanentError
      // classifier so the item routes to markAsSyncDeadLetter + SYNC-WARN
      // immediately instead of looping 10× or (worse) being marked synced.
      expect(
        source.contains("errorStr.contains('Unknown sync table')"),
        isTrue,
        reason:
            "$relPath isPermanentError classifier does not match 'Unknown sync "
            "table'. Without it, a thrown unknown-table would burn "
            "_maxSyncAttempts retries before dead-lettering — the fail-loud "
            "throw should surface as a visible dead-letter right away.",
      );
    });

    test('journal-entries replay threads globalId into submitJournalEntry (R9)',
        () {
      // Carve the journal replay body: from the first `case 'journal_entries':`
      // to the next `break;`. It must call submitJournalEntry AND pass globalId
      // (the legacy 'journals' body omitted globalId — a real R9 gap).
      final caseIdx = source.indexOf("case 'journal_entries':");
      expect(caseIdx, greaterThan(0),
          reason: "expected `case 'journal_entries':` in $relPath");
      final breakIdx = source.indexOf('break;', caseIdx);
      expect(breakIdx, greaterThan(caseIdx),
          reason: 'expected a `break;` closing the journal replay case');
      final body = source.substring(caseIdx, breakIdx);

      expect(
        body.contains('proxy.submitJournalEntry('),
        isTrue,
        reason:
            "$relPath journal replay case no longer calls "
            "proxy.submitJournalEntry — offline JEs will not reach the server.",
      );
      expect(
        RegExp(r'globalId:\s*\(payload\[').hasMatch(body),
        isTrue,
        reason:
            "$relPath journal replay case does not thread `globalId` into "
            "submitJournalEntry. R9 requires the caller-minted UUIDv7 be "
            "threaded end-to-end so the server dedups on retry instead of "
            "inserting a phantom duplicate JE. See Spec 151 BLOCKER C-01 / R9.",
      );
    });
  });
}

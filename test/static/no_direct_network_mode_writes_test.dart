// Spec 125 US4 / FR-004 — grep test that enforces:
// "All writes to network_mode (and the other Deployment-owned settings keys)
//  MUST go through DeploymentModeCommitter."
//
// Any direct `setSetting('network_mode', ...)` or `saveSetting('network_mode', ...)`
// in production code outside lib/services/deployment/ is a bug and fails this test.
//
// The committer itself uses `db.into(db.settings).insertOnConflictUpdate(...)`
// — that's the only DB write path allowed for these keys.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 125 FR-004 — no direct network_mode writes outside committer', () {
    // Patterns that indicate a direct write to a Deployment-owned settings key.
    // Each is a substring match (case-sensitive) — Dart code is case-sensitive.
    final forbiddenPatterns = <String>[
      "setSetting('network_mode'",
      'setSetting("network_mode"',
      "saveSetting('network_mode'",
      'saveSetting("network_mode"',
      "setSetting('standalone_setup_completed'",
      "setSetting('server_setup_completed'",
      "setSetting('last_committed_mode'",
      "saveSetting('standalone_setup_completed'",
      "saveSetting('server_setup_completed'",
      "saveSetting('last_committed_mode'",
    ];

    // Files allowed to contain these writes (the orchestrator + its delegates).
    final allowedFiles = <String>{
      // The committer is the sole legitimate writer.
      'lib\\services\\deployment\\deployment_mode_committer.dart',
      'lib/services/deployment/deployment_mode_committer.dart',

      // NetworkService.setMode / resetToStandalone are the canonical setMode
      // helpers that the committer delegates to. They are pre-existing
      // and represent the lower-level write primitive.
      'lib\\services\\network_service.dart',
      'lib/services/network_service.dart',

      // ClientFirstSyncService writes the per-mode first-sync completion
      // flags — that's R8 behavior, not a Deployment-owned write.
      'lib\\services\\sync\\client_first_sync_service.dart',
      'lib/services/sync/client_first_sync_service.dart',
    };

    test('no forbidden direct writes in lib/ outside allowed files', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      final offenders = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        // Skip allowed files (both path separators considered).
        if (allowedFiles.any((p) =>
            entity.path == p ||
            entity.path.replaceAll('\\', '/') == p.replaceAll('\\', '/'))) {
          continue;
        }

        final content = entity.readAsStringSync();
        final lines = content.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Skip pure-comment lines (// ...) and doc comments (/// ...).
          // Pattern matches inside string literals on commented lines (e.g.
          // historical references in change-log comments) are intentional
          // documentation, not real writes.
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          for (final pattern in forbiddenPatterns) {
            if (line.contains(pattern)) {
              offenders.add('${entity.path}:${i + 1}  →  $pattern');
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Direct writes to Deployment-owned settings keys found '
            'outside DeploymentModeCommitter. These bypass the atomic '
            'commit pipeline (Spec 125 FR-004). Route through '
            'DeploymentModeCommitter.commit(...) instead.\n\n'
            'Offenders:\n  ${offenders.join("\n  ")}',
      );
    });
  });
}

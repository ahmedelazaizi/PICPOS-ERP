// Spec 064 / SC-004 — Read-filter + UI-visibility gate predicate guard.
//
// The four sales/purchases/branch/auth repositories' watch streams gate
// their warehouse-id scoping on a "should I apply client-side scoping?"
// predicate. Historically this was `NetworkService.instance.isClient`,
// which returns FALSE in mirror mode — so mirror users silently saw EVERY
// branch's invoices regardless of their `user_branch_access` rows
// (QA audit 2026-05-15, finding D2-001).
//
// Spec 064 broadens the predicate to `SyncInterceptor.isClientMode`,
// which is TRUE for both `NetworkMode.client` AND `NetworkMode.mirror`.
// Two adjacent UI-visibility gates (delta-pull spinner + empty-state
// message) get the same treatment (finding D4-004).
//
// Some sibling sites in the same files are LEGITIMATELY strict-client —
// outbox-related affordances that have no semantic in mirror mode (mirror
// has no outbox by design). Those sites carry an inline allowlist marker
// `// keep-isClient: outbox` so this test exempts them.
//
// This test enforces the convention going forward: any reappearance of
// the bare `NetworkService.instance.isClient` reference inside the six
// affected files — without the allowlist marker — fails the build.
//
// Companion to test/unit/orchestrator_gate_predicate_test.dart, which
// covers the WRITE-gate side of the same predicate broadening.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Read-filter + UI-visibility gate predicate (Spec 064 / SC-004)', () {
    final affectedFiles = <String>[
      'lib/data/repositories/sales_repository_impl.dart',
      'lib/data/repositories/purchases_repository_impl.dart',
      'lib/data/repositories/branch_repository_impl.dart',
      'lib/data/repositories/auth_repository_impl.dart',
      'lib/presentation/shell/app_shell.dart',
      'lib/presentation/screens/reports/financial_statements_screen.dart',
    ];

    for (final relPath in affectedFiles) {
      test('$relPath has no un-allowlisted NetworkService.instance.isClient', () {
        final file = File(relPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'expected affected file to exist at $relPath',
        );

        final lines = file.readAsLinesSync();
        final offenders = <String>[];

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('NetworkService.instance.isClient')) continue;
          // Allowlist: legitimate strict-client gates (outbox-related, where
          // mirror has no semantic) MUST carry this inline marker on the
          // same line so they're explicit and self-documenting.
          if (line.contains('// keep-isClient: outbox')) continue;
          offenders.add('  L${i + 1}: ${line.trim()}');
        }

        expect(
          offenders,
          isEmpty,
          reason:
              '$relPath still references NetworkService.instance.isClient '
              'on the following lines without the allowlist marker:\n'
              '${offenders.join('\n')}\n\n'
              'Either:\n'
              '  (a) Use SyncInterceptor.isClientMode — true for both client '
              'and mirror modes (see ENGINEERING_GUIDELINES.md §R9).\n'
              '  (b) If the gate is LEGITIMATELY strict-client (outbox-related, '
              'mirror has no outbox), add the marker `// keep-isClient: outbox` '
              'on the same line.\n\n'
              'See specs/064-mirror-read-scope-parity/spec.md for the original '
              'finding (D2-001 P0 + D4-004 cross-link).',
        );
      });
    }
  });
}

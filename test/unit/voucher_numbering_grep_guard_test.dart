// Spec 066 / SC-003 — Grep guard: every generateInvoiceNumber(...) call
// MUST sit inside a containing `transaction(` block in the same method.
//
// Rationale (D5-001): the counter advance MUST be atomic with the
// dependent voucher insert. Drift's nested transaction() becomes a
// SAVEPOINT only when the caller is already in a transaction. A bare
// caller's inner txn commits independently and a subsequent insert
// failure leaves an Egyptian-VAT-illegal gap in the printed sequence.
//
// This test walks every .dart file under lib/ (skipping the canonical
// generator at lib/data/database/database.dart and the .bak copy) and
// fails if any `generateInvoiceNumber(` token is not preceded — within
// the same method body — by a `transaction(` token.
//
// Opt-out: a future legitimate exception may carry the marker on the
// immediately preceding line:
//   // allow-bare-generateInvoiceNumber: <one-line reason>
//
// Companion to test/unit/voucher_numbering_atomicity_test.dart, which
// exercises the runtime guard + rollback semantics.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Voucher numbering grep guard (Spec 066 / SC-003)', () {
    test(
      'every generateInvoiceNumber(...) call is wrapped in transaction(',
      () {
        // Files exempted from the rule:
        //  - database.dart: defines the function itself.
        //  - database.dart.bak: stale snapshot, gitignored content.
        //  - test/: tests legitimately exercise the function in controlled
        //    contexts (and are themselves wrapped via in-memory db).
        final exempt = <String>{
          'lib/data/database/database.dart',
          'lib/data/database/database.dart.bak',
        };

        final libDir = Directory('lib');
        expect(
          libDir.existsSync(),
          isTrue,
          reason: 'lib/ directory must exist (run from repo root)',
        );

        final offenders = <String>[];

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;

          // Normalize to forward-slash relative path for cross-platform
          // exempt-list comparison.
          final relPath = entity.path
              .replaceAll('\\', '/')
              .replaceFirst(RegExp(r'^\./'), '');
          if (exempt.contains(relPath)) continue;

          final content = entity.readAsStringSync();
          if (!content.contains('generateInvoiceNumber(')) continue;

          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (!line.contains('generateInvoiceNumber(')) continue;
            // Skip the function-definition / interface declaration itself —
            // a line that starts with `Future<String> generateInvoiceNumber(`
            // is the signature, not a call.
            if (RegExp(r'\bFuture<.*>\s+generateInvoiceNumber\s*\(')
                .hasMatch(line)) {
              continue;
            }
            // Skip override-decl lines: `Future<String> generateInvoiceNumber(...)`
            // already filtered above. Still: skip a comment-only mention.
            if (line.trim().startsWith('//')) continue;
            // Skip string literals containing the token (debug log strings).
            // Heuristic: if the only occurrence of the token is inside single
            // or double quotes that span the whole match, ignore.
            final occIdx = line.indexOf('generateInvoiceNumber(');
            final beforeOcc = line.substring(0, occIdx);
            final singleBefore = "'".allMatches(beforeOcc).length;
            final doubleBefore = '"'.allMatches(beforeOcc).length;
            if (singleBefore.isOdd || doubleBefore.isOdd) {
              // Inside a string literal — skip.
              continue;
            }

            // Allow-list marker on the immediately preceding line.
            if (i > 0 &&
                lines[i - 1].contains('// allow-bare-generateInvoiceNumber:')) {
              continue;
            }

            // Walk backwards from this line up to a method-signature line
            // OR until we've scanned 600 lines, whichever comes first.
            // Within that window, require either `transaction(` token or
            // a `db.transaction` / `_db.transaction` reference.
            final scanLimit = (i - 600).clamp(0, i);
            bool sawTransaction = false;
            // Method-signature heuristic: a line at lower indentation that
            // matches `^(\s+)(Future|Stream|void|int|double|String|bool|...)\s+\w+\s*\(`
            // — this catches DAO methods, repo methods, and top-level helpers.
            final sigPattern = RegExp(
              r'^\s*(Future<.*>|void|Stream<.*>|int|double|String|bool|num)\s+'
              r'_?[a-zA-Z][a-zA-Z0-9_]*\s*\(',
            );

            for (var j = i - 1; j >= scanLimit; j--) {
              final back = lines[j];
              if (back.contains('transaction(')) {
                sawTransaction = true;
                break;
              }
              if (sigPattern.hasMatch(back)) {
                // Hit the method signature without finding a transaction(
                // token in between.
                break;
              }
            }

            if (!sawTransaction) {
              offenders.add('$relPath:${i + 1}: ${line.trim()}');
            }
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'Spec 066 / D5-001: every generateInvoiceNumber(...) call must '
              'sit inside an enclosing transaction(...) block in the same '
              'method (Drift will then nest the inner txn as a SAVEPOINT). '
              'Found ${offenders.length} bare call(s):\n'
              '${offenders.join("\n")}\n'
              '\nFix: wrap the call in db.transaction(() async { ... }) '
              'or add the marker `// allow-bare-generateInvoiceNumber: '
              '<reason>` on the immediately preceding line.\n'
              'See specs/066-voucher-numbering-atomicity/contracts/'
              'numbering-atomicity.md',
        );
      },
    );
  });
}

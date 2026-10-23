// Audit B BKP-004 — PostgreSQL mode has no in-app backup, so the operator
// script + runbook must exist and contain the safety properties that matter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('scripts/backup_postgres.ps1');
  final doc = File('docs/ops/POSTGRES-BACKUP.md');

  test('operator backup script and runbook exist', () {
    expect(script.existsSync(), isTrue);
    expect(doc.existsSync(), isTrue);
  });

  test('script dumps, verifies the dump, and never takes the password on the CLI', () {
    final s = script.readAsStringSync();
    expect(s, contains('pg_dump'));
    expect(s, contains('--format=custom'));
    expect(s, contains('pg_restore'), reason: 'dump must be verified (--list)');
    expect(s, contains('--list'));
    expect(s, contains('KeepDays'), reason: 'retention');
    expect(s, contains('PGPASSWORD'), reason: 'documents the password channel');
    expect(RegExp(r'--password|-W\b').hasMatch(s), isFalse);
  });

  test('runbook states the operator responsibility and the restore drill', () {
    final d = doc.readAsStringSync();
    expect(d, contains('operator'));
    expect(d, contains('Restore drill'));
    expect(d, contains('scripts/backup_postgres.ps1'));
    expect(d, contains('off the server'));
  });
}

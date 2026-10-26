// WH-025: a FAILED first attempt to create the phone-document tables is not
// remembered. The first call fails (a view squats on the name, standing in for a
// locked file / PG hiccup), the next call after the cause is gone succeeds and
// the tables really exist; concurrent callers share one attempt.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';

void main() {
  test('a failed ensure is retried by the next call (no 500 until restart)', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.customStatement('CREATE VIEW wh_mobile_docs AS SELECT 1 AS x');

    await expectLater(db.ensureWhMobileDocsSchema(), throwsA(anything));
    // the cause goes away
    await db.customStatement('DROP VIEW wh_mobile_docs');
    await db.ensureWhMobileDocsSchema();

    final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'wh_mobile_doc%'").get();
    expect(tables.map((r) => r.data['name']).toSet(), {'wh_mobile_docs', 'wh_mobile_doc_lines', 'wh_mobile_doc_events'});
  });

  test('concurrent callers share one attempt and a success is remembered', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final a = db.ensureWhMobileDocsSchema();
    final b = db.ensureWhMobileDocsSchema();
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(identical(db.ensureWhMobileDocsSchema(), a), isTrue);
  });
}
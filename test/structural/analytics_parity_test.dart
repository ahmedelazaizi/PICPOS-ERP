// The analytics classifier cannot import `account_mapping_purposes.dart`
// (it pulls in Flutter UI), so it hard-codes purpose keys and chart code
// prefixes. This guard keeps those copies from drifting: renaming or removing
// a purpose key, or a seeded account the classifier relies on, fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/analytics/account_classifier.dart';

void main() {
  const purposesPath =
      'lib/presentation/accounting_picpos/account_mapping_purposes.dart';
  const seederPath = 'lib/data/database/database_seeder_accounts.dart';
  const reportsDaoPath = 'lib/data/database/daos/accounting_reports_dao.dart';

  /// Purpose keys the classifier reads that are NOT user-mappable screens'
  /// entries but are still resolved by the report DAO. Each must be read by
  /// `accounting_reports_dao.dart` (asserted below).
  const reportOnlyPurposes = {'depreciation_expense'};

  late String purposesSrc;
  late String seederSrc;

  setUpAll(() {
    for (final p in [purposesPath, seederPath, reportsDaoPath]) {
      expect(File(p).existsSync(), isTrue, reason: 'update the path: $p');
    }
    purposesSrc = File(purposesPath).readAsStringSync();
    seederSrc = File(seederPath).readAsStringSync();
  });

  Set<String> purposeKeys() => RegExp(r"AccountMappingPurpose\(\s*'([a-z0-9_]+)'")
      .allMatches(purposesSrc)
      .map((m) => m.group(1)!)
      .toSet();

  test('the purposes file is parsed (guard against an empty extraction)', () {
    final keys = purposeKeys();
    expect(keys.length, greaterThan(40));
    expect(keys, containsAll(['cash', 'receivables', 'payables']));
  });

  test('every purpose key the classifier uses exists in the purposes file', () {
    final known = purposeKeys();
    final used = classifierPurposeKeys;
    expect(used, isNotEmpty);
    final missing = used.difference(known).difference(reportOnlyPurposes);
    expect(missing, isEmpty,
        reason: 'Classifier purpose keys not in $purposesPath: $missing. '
            'Rename them in account_classifier.dart too.');
  });

  test('report-only purpose keys are still read by the reports DAO', () {
    final dao = File(reportsDaoPath).readAsStringSync();
    for (final key in reportOnlyPurposes) {
      expect(classifierPurposeKeys, contains(key),
          reason: '$key is no longer used by the classifier; drop it here');
      expect(dao, contains("'$key'"),
          reason: '$key is no longer resolved by the reports DAO');
    }
  });

  test('every code prefix the classifier uses is a seeded account (source)',
      () {
    // _acct('<code>', '<ar>', '<en>', '<type>', ...)
    final seeded = <String, String>{
      for (final m in RegExp(
              r"_acct\(\s*'([0-9][0-9-]*)'\s*,\s*'[^']*'\s*,\s*'[^']*'\s*,\s*'([a-z_]+)'")
          .allMatches(seederSrc))
        m.group(1)!: m.group(2)!,
    };
    expect(seeded.length, greaterThan(100));
    final prefixes = classifierCodePrefixes;
    expect(prefixes, isNotEmpty);
    for (final e in prefixes.entries) {
      expect(seeded.containsKey(e.key), isTrue,
          reason: 'classifier prefix ${e.key} is not a seeded account code');
      expect(e.value, contains(seeded[e.key]),
          reason: 'seeded ${e.key} has type ${seeded[e.key]}, the classifier '
              'accepts ${e.value}');
    }
  });

  test('every classifier prefix exists in the seeded in-memory chart', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final rows = await db.select(db.accounts).get();
    final byCode = {for (final a in rows) a.code: a.accountType};
    for (final e in classifierCodePrefixes.entries) {
      expect(byCode.containsKey(e.key), isTrue,
          reason: 'prefix ${e.key} missing from the seeded chart');
      expect(e.value, contains(byCode[e.key]));
      // the prefix must actually select at least one account of the family
      expect(
        rows.any((a) => a.code.startsWith(e.key) && e.value.contains(a.accountType)),
        isTrue,
      );
    }
  });

  test('seeded default purpose accounts used by the classifier exist',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final mapped = (await db.select(db.accountMappings).get())
        .where((m) => m.costCenterId == null)
        .map((m) => m.purpose)
        .toSet();
    // Purposes whose absence from the seeded mappings would silently push the
    // classifier onto the prefix fallback.
    const core = {'cash', 'bank', 'receivables', 'payables', 'inventory'};
    expect(mapped.containsAll(core), isTrue,
        reason: 'unmapped core purposes: ${core.difference(mapped)}');
  });
}

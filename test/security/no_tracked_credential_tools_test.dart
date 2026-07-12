// Day-0 credential purge — guard test.
//
// Two liabilities were found tracked in git (MAINTENANCE_REPORT_2026-07-05
// P0-3 / P0-4):
//   * license/keygen tooling — anyone cloning the repo could mint valid
//     activation keys.
//   * a reset script + web seed baking a known 'admin' password — a permanent
//     backdoor for any install that ran them.
//
// They were untracked / removed. This test fails the build if any of them
// reappear in the index. There is no CI (the repo has no remote), so this runs
// as part of `flutter test`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no license/keygen/backdoor files are tracked in git', () {
    final result = Process.runSync('git', ['ls-files']);
    expect(
      result.exitCode,
      0,
      reason: 'git ls-files failed: ${result.stderr}',
    );

    // Anchored to the actual liabilities, not any file mentioning "license"
    // (e.g. a LICENSE legal file is fine).
    final forbidden = RegExp(
      r'keygen'
      r'|UralCash_License_Tool'
      r'|tools/license\.txt'
      r'|reset_pg_admin_password',
      caseSensitive: false,
    );

    final offenders = (result.stdout as String)
        .split('\n')
        .where((f) => f.isNotEmpty && forbidden.hasMatch(f))
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: 'These must NOT be tracked (credential/keygen liability):\n'
          '${offenders.join('\n')}',
    );
  });
}

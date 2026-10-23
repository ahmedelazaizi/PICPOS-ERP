// Phase 1 diagnostics — DiagnosticLogger.logError formats a failure entry
// (tag + operation + error) into the Documents log so field problems are
// traceable to their origin, not lost to console-only debugPrint.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';

void main() {
  test('logError captures tag, op and error into the diagnostic log', () async {
    DiagnosticLogger.enableTestMode();
    await DiagnosticLogger.logError(
        DiagnosticLogger.migration, 'v103 add parties.account_id',
        Exception('boom'));

    final log = DiagnosticLogger.testLog;
    expect(log.length, 1);
    expect(log.first, contains('[MIGRATION]'));
    expect(log.first, contains('v103 add parties.account_id'));
    expect(log.first, contains('boom'));
  });
}

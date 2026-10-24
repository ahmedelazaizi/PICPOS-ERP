// SYNC-005 — a uniqueness conflict with a DIFFERENT record must be surfaced
// (dead-lettered), not folded into "synced" with the local change dropped.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';

void main() {
  const productConflict = 'Exception: Server error (409): '
      '{"error":"هذا الكود مستخدم بالفعل لصنف آخر","code":"UNIQUE_CONFLICT",'
      '"conflictWithProductId":7,"conflictWithGlobalId":"g-other"}';

  test('a product code/barcode owned by another product is terminal (shown in sync failures)', () {
    expect(isTerminalBusinessConflict(productConflict), isTrue);
  });

  test('the structured code alone is enough, the Arabic prose is irrelevant', () {
    expect(isTerminalBusinessConflict('Server error (409): {"code":"UNIQUE_CONFLICT"}'), isTrue);
    expect(kUniqueConflictCode, 'UNIQUE_CONFLICT');
  });

  test('conflicts naming another record are terminal even without the code (older host)', () {
    expect(isTerminalBusinessConflict('409 {"conflictWithGlobalId":"x"}'), isTrue);
  });

  test('benign wording of the same row still folds into success (unchanged contract)', () {
    expect(isTerminalBusinessConflict('409 Conflict: already exists'), isFalse);
    expect(isTerminalBusinessConflict('UNIQUE constraint failed'), isFalse);
    expect(isTerminalBusinessConflict('duplicate'), isFalse);
  });
}

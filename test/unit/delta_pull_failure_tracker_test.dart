// SYNC-002 (audit 2026-10-23): row failures hold the watermark (bounded).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/delta_pull_failure_tracker.dart';

void main() {
  test('a clean cycle advances', () {
    final t = DeltaPullFailureTracker()..begin('parties');
    expect(t.decide('parties').advance, isTrue);
  });

  test('a cycle with one bad row holds the watermark', () {
    final t = DeltaPullFailureTracker()
      ..begin('parties')
      ..recordRowFailure('parties');
    expect(t.decide('parties').advance, isFalse);
  });

  test('the hold is bounded: advances (forced) after maxHeldCycles', () {
    final t = DeltaPullFailureTracker();
    for (var i = 1; i < DeltaPullFailureTracker.maxHeldCycles; i++) {
      t
        ..begin('x')
        ..recordRowFailure('x');
      expect(t.decide('x').advance, isFalse, reason: 'cycle $i');
    }
    t
      ..begin('x')
      ..recordRowFailure('x');
    final d = t.decide('x');
    expect(d.advance, isTrue);
    expect(d.forced, isTrue);
  });

  test('a clean cycle resets the budget; tables are independent', () {
    final t = DeltaPullFailureTracker()
      ..begin('a')
      ..recordRowFailure('a');
    expect(t.decide('a').advance, isFalse);
    t.begin('b');
    expect(t.decide('b').advance, isTrue);
    t.begin('a');
    expect(t.decide('a').advance, isTrue);
  });
}

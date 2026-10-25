// P5: the proof a device holds between approval and delivery to the main.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/services/approval/approval_proof_carrier.dart';

void main() {
  final c = ApprovalProofCarrier.instance;
  var now = DateTime(2026, 10, 25, 12);

  setUp(() {
    now = DateTime(2026, 10, 25, 12);
    c.debugReset();
    c.debugUseClock(() => now);
  });
  tearDown(c.debugReset);

  test('holds a proof for the window only', () {
    expect(c.proof, isNull);
    c.hold('P', permission: 'pos_expense');
    expect(c.proof, 'P');
    expect(c.permission, 'pos_expense');
    now = now.add(ApprovalProofCarrier.window - const Duration(seconds: 1));
    expect(c.proof, 'P');
    now = now.add(const Duration(seconds: 2));
    expect(c.proof, isNull, reason: 'window over: nothing is attached any more');
    expect(c.permission, isNull);
  });

  test('stamp puts the proof into a write payload (outbox) and is a no-op '
      'without one', () {
    final a = <String, dynamic>{'x': 1};
    c.stamp(a);
    expect(a, {'x': 1});
    c.hold('P', permission: 'pos_expense');
    final b = <String, dynamic>{'x': 1};
    c.stamp(b);
    expect(b, {'x': 1, ApprovalProofCarrier.payloadKey: 'P'});
  });

  test('clear drops the proof at once', () {
    c.hold('P', permission: 'pos_expense');
    c.clear();
    expect(c.proof, isNull);
  });
}

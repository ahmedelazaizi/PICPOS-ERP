// End-to-end skeleton of the Warehouse app. W0-W1 behaviour is covered by the
// widget/session tests and by the desktop-side `test/integration/m1_wh_read_scope_test.dart`
// (real middleware + router on an in-memory database). Later phases fill the skipped
// cases in (plan 2026-10-23 W2-W5); none of them is simulated before then.
import 'package:flutter_test/flutter_test.dart';

void main() {
  const later = 'arrives with its plan phase; not implemented yet';

  test('W2: receive a purchase order offline, outbox drains with the same idempotency key', () {},
      skip: later);
  test('W3: request -> approve -> dispatch -> receive a transfer across two phones', () {}, skip: later);
  test('W4: blind count never exposes expected quantities to the counter', () {}, skip: later);
  test('W5: label printing and hardware scanner profiles', () {}, skip: later);
}

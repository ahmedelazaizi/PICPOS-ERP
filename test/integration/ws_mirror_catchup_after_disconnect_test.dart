// Spec 129 F1 / FR-103 + SC-006 — catch-up after WebSocket disconnect.
//
// STATUS: stub — field-smoke owns verification.
//
// Why no automated integration test landed in this slice: the project
// has no existing in-process WebSocket-server test harness. Building one
// requires (a) booting `shelf` + `shelf_web_socket` on a real port, (b)
// wiring a test `ApiHandler` with a fresh DB, (c) coordinating real async
// timing for disconnect → mutation → reconnect → DeltaPull windows. That
// scaffold is ~200 LOC of test infrastructure that would belong in a
// separate spec dedicated to a WS test harness.
//
// The catch-up logic itself reuses [`_refreshTokenAndDrain`](../../lib/services/websocket_sync_client.dart)
// verbatim — this is the same code path client mode has used since Feature 005.
// What changes for Spec 129 is just that the path is also now reachable for
// mirror mode (FR-101 connect-gate relaxation).
//
// Verification today:
//   • [quickstart.md §3 cell 11](../../specs/129-mirror-broadcast-discipline/quickstart.md)
//     spells out the manual smoke: disconnect mirror Wi-Fi for 60 s while
//     server processes 5 sales + 2 returns + 3 vouchers, reconnect, assert
//     all 10 mutations visible within 5 s and `[WS-DISCONNECT]` +
//     `[WS-CONNECT]` bracket the gap.
//
// Follow-up: a dedicated spec (130+) should ship the WS test harness, and
// this file becomes the first consumer of it. Re-enable the test by
// removing the @Skip below and implementing the body against the new
// harness.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mirror reflects every server mutation within 5 s of WS reconnect (SC-006)',
    () async {
      // see file header — pending WS test harness in a follow-up spec.
    },
    skip: 'pending in-process WS test harness — quickstart §3 cell 11 owns smoke',
  );
}

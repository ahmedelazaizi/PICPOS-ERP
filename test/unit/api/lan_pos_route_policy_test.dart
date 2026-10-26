import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/lan_device_route_policy.dart';

/// The `pos` kind (Cashier tablets AND paired desktop sessions) keeps the sales
/// surface but must not reach the warehouse phone API or the mirror console;
/// the accountant's receipts desk is the one carve-out (a desktop surface).
void main() {
  test('pos: phone API and mirror console are closed', () {
    for (final p in [
      '/api/m1/wh/docs',
      '/api/m1/wh/counts/1/recount',
      '/api/m1/wh/approvals/proof',
      '/api/mirror/context',
    ]) {
      expect(LanDeviceRoutePolicy.allows('pos', p), isFalse, reason: p);
    }
  });

  test('pos: the receipts desk stays open (desktop session)', () {
    expect(LanDeviceRoutePolicy.allows('pos', '/api/m1/wh/desk/receipts'), isTrue);
    expect(
      LanDeviceRoutePolicy.allows('pos', '/api/m1/wh/desk/receipts/convert'),
      isTrue,
    );
  });

  test('pos: ordinary sales routes are open; other kinds are unchanged', () {
    expect(LanDeviceRoutePolicy.allows('pos', '/api/sales'), isTrue);
    expect(LanDeviceRoutePolicy.allows('warehouse', '/api/sales'), isFalse);
    // The warehouse phone passes the PATH policy under /api/m1/wh; the desk is
    // refused to it inside the handler (WhHttp.runDesk), covered by
    // wh_receipts_inbox_test.
  });
}
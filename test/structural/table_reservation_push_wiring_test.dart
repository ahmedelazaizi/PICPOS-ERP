// Audit B DATA-001 wiring guard: a client reservation write travels
// repository -> client push -> CWI -> proxy -> outbox replay -> host route.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('every hop of the table-reservation push exists', () {
    expect(_read('lib/services/server_proxy/server_proxy_master_data.dart'),
        contains("post('/api/table-reservations'"));
    expect(_read('lib/services/interceptor/cwi_sync_foundation.dart'),
        contains("tableName: 'table_reservations'"));
    expect(_read('lib/services/interceptor/cwi_core.dart'),
        contains('submitTableReservation'));
    expect(
        _read('lib/services/offline_sync_worker/offline_sync_worker_replay_finance.dart'),
        contains("case 'table_reservations':"),
        reason: 'offline replay must know the queued table_reservations rows');
    expect(_read('lib/services/api/routes/api_routes_write.dart'),
        contains("router.post('/api/table-reservations'"));
    expect(_read('lib/services/api/data/api_data_operations.dart'),
        contains('applyTableReservationSnapshot'));
  });

  test('both writers call the push after the local write', () {
    expect(_read('lib/data/repositories/restaurant_repository_impl.dart'),
        contains('pushTableReservation('));
    expect(_read('lib/services/table_session_service.dart'),
        contains('pushTableReservation('));
  });
}

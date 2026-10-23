// Client side of audit B DATA-001: after a table reservation is written to the
// local DB on a LAN client, push its full snapshot (global ids only) to the
// host through the client write interceptor / outbox. No-op outside client
// mode. The host applies it idempotently by `globalId`.
import 'package:drift/drift.dart' show Value;

import '../core/utils/uuid_v7.dart';
import '../data/database/database.dart';
import '../data/database/sync_interceptor.dart';
import 'client_write_interceptor.dart';

Future<void> pushTableReservation(AppDatabase db, int reservationId) async {
  if (!SyncInterceptor.isClientMode) return;
  final r = await (db.select(db.tableReservations)
        ..where((x) => x.id.equals(reservationId)))
      .getSingleOrNull();
  if (r == null) return;

  var gid = r.globalId;
  if (gid == null || gid.isEmpty) {
    gid = UuidV7.generate();
    await (db.update(db.tableReservations)
          ..where((x) => x.id.equals(reservationId)))
        .write(TableReservationsCompanion(globalId: Value(gid)));
  }
  final table = await (db.select(db.restaurantTables)
        ..where((t) => t.id.equals(r.tableId)))
      .getSingleOrNull();
  final tableGid = table?.globalId;
  if (tableGid == null || tableGid.isEmpty) return; // table never synced

  String? partyGid;
  if (r.partyId != null) {
    partyGid = (await (db.select(db.parties)
              ..where((p) => p.id.equals(r.partyId!)))
            .getSingleOrNull())
        ?.globalId;
  }

  final doc = buildTableReservationDocument(
    r,
    globalId: gid,
    tableGlobalId: tableGid,
    partyGlobalId: partyGid,
  );
  await ClientWriteInterceptor.dispatchWrite(
    () => ClientWriteInterceptor.submitTableReservation(doc),
    tag: 'TABLE-RESERVATION-SYNC',
  );
}

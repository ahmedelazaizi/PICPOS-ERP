// Table reservations made on a LAN client must reach the host (audit B
// DATA-001). Pure document builder (client side) + idempotent applier (host
// side). The wire document identifies everything by GLOBAL ids — local
// integer ids differ between devices.
//
// Document (full snapshot, so replaying it any number of times is harmless):
//   { globalId, tableGlobalId, customerName, customerPhone, partyGlobalId,
//     reservationTime (ISO-8601), partySize, notes, status }
//
// Ordering guard: the outbox replays in order, but a stale `pending` snapshot
// can still arrive after a newer `cancelled`/`seated` one (offline replay after
// a host-side change). A terminal status is never regressed to an active one.
part of 'database.dart';

/// Statuses after which a reservation is no longer waiting for the guest.
const Set<String> kTerminalReservationStatuses = {
  'cancelled',
  'seated',
  'completed',
  'no_show',
};

/// Raised on the host when the reservation's table (or section) has not
/// arrived yet — the API answers 409 + retry so the client queue replays it.
class TableReservationDependencyMissing implements Exception {
  const TableReservationDependencyMissing(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Builds the wire snapshot of a locally stored reservation.
Map<String, dynamic> buildTableReservationDocument(
  TableReservation reservation, {
  required String globalId,
  required String tableGlobalId,
  String? partyGlobalId,
}) =>
    <String, dynamic>{
      'globalId': globalId,
      'tableGlobalId': tableGlobalId,
      'customerName': reservation.customerName,
      'customerPhone': reservation.customerPhone,
      'partyGlobalId': partyGlobalId,
      'reservationTime': reservation.reservationTime.toIso8601String(),
      'partySize': reservation.partySize,
      'notes': reservation.notes,
      'status': reservation.status,
    };

/// Applies a client snapshot on the host. Idempotent by `globalId`.
/// Returns the host row id.
Future<int> applyTableReservationSnapshot(
  AppDatabase db,
  Map<String, dynamic> doc,
) async {
  final gid = (doc['globalId'] as String?)?.trim();
  final tableGid = (doc['tableGlobalId'] as String?)?.trim();
  final name = (doc['customerName'] as String?)?.trim();
  final status = (doc['status'] as String?)?.trim();
  final timeRaw = doc['reservationTime'] as String?;
  if (gid == null ||
      gid.isEmpty ||
      tableGid == null ||
      tableGid.isEmpty ||
      name == null ||
      name.isEmpty ||
      status == null ||
      status.isEmpty ||
      status.length > 20 ||
      timeRaw == null) {
    throw ArgumentError('invalid table reservation document');
  }
  final time = DateTime.tryParse(timeRaw);
  if (time == null) throw ArgumentError('invalid reservationTime');

  return db.transaction(() async {
    final table = await (db.select(db.restaurantTables)
          ..where((t) => t.globalId.equals(tableGid))
          ..limit(1))
        .getSingleOrNull();
    if (table == null) {
      throw const TableReservationDependencyMissing('الطاولةُ لم تصل الخادمَ بعد');
    }
    int? partyId;
    final partyGid = (doc['partyGlobalId'] as String?)?.trim();
    if (partyGid != null && partyGid.isNotEmpty) {
      partyId = (await (db.select(db.parties)
                ..where((p) => p.globalId.equals(partyGid))
                ..limit(1))
              .getSingleOrNull())
          ?.id;
    }

    final existing = await (db.select(db.tableReservations)
          ..where((r) => r.globalId.equals(gid))
          ..limit(1))
        .getSingleOrNull();

    final int id;
    var effectiveStatus = status;
    if (existing == null) {
      id = await db.into(db.tableReservations).insert(
            TableReservationsCompanion.insert(
              tableId: table.id,
              customerName: name,
              customerPhone: Value(doc['customerPhone'] as String?),
              partyId: Value(partyId),
              reservationTime: time,
              partySize: Value((doc['partySize'] as num?)?.toInt() ?? 2),
              notes: Value(doc['notes'] as String?),
              status: Value(status),
              globalId: Value(gid),
            ),
          );
    } else {
      id = existing.id;
      // Never regress a terminal status to an active one (stale replay).
      if (kTerminalReservationStatuses.contains(existing.status) &&
          !kTerminalReservationStatuses.contains(status)) {
        effectiveStatus = existing.status;
      }
      await (db.update(db.tableReservations)..where((r) => r.id.equals(id)))
          .write(TableReservationsCompanion(
        tableId: Value(table.id),
        customerName: Value(name),
        customerPhone: Value(doc['customerPhone'] as String?),
        partyId: Value(partyId),
        reservationTime: Value(time),
        partySize: Value((doc['partySize'] as num?)?.toInt() ?? existing.partySize),
        notes: Value(doc['notes'] as String?),
        status: Value(effectiveStatus),
      ));
    }

    // Table status follows the reservation, never clobbering an open order.
    if (effectiveStatus == 'pending' || effectiveStatus == 'confirmed') {
      if (table.status == 'available') {
        await db.updateTableStatus(table.id, 'reserved');
      }
    } else if (effectiveStatus == 'cancelled') {
      final others = await (db.select(db.tableReservations)
            ..where((r) => r.tableId.equals(table.id))
            ..where((r) => r.id.equals(id).not())
            ..where((r) => r.status.isIn(['pending', 'confirmed'])))
          .get();
      if (others.isEmpty && table.status == 'reserved') {
        await db.updateTableStatus(table.id, 'available');
      }
    }
    return id;
  });
}

// A-11: the v196 reservation→customer backfill (owner rules F.1) on real
// PostgreSQL: portable SQL (sqlBool, ON CONFLICT DO NOTHING), same outcomes as
// the SQLite test test/integration/v196_reservation_parties_migration_test.dart.
@Tags(['pg'])
library;

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase db;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    db = fx.db;
    await db.customSelect('SELECT 1').get();
    await db.syncDefaultAccounts();
  });

  tearDownAll(() => fx.tearDown());

  Future<int> party(String name, {String? phone, bool customer = true}) =>
      db.into(db.parties).insert(PartiesCompanion.insert(
            name: name,
            phone: d.Value(phone),
            isCustomer: d.Value(customer),
          ));

  Future<int?> partyOf(String table, int id) async {
    final r = await db
        .customSelect('SELECT party_id FROM $table WHERE id = $id')
        .getSingle();
    return r.data['party_id'] as int?;
  }

  test('backfill runs on PostgreSQL: F.1 rules a/b/c/d/e + A-3 audit row',
      () async {
    final layla = await party('ليلى محمد', phone: '+20 100 111 2222');
    final sami = await party('سامي علي'); // no phone → rule (b)
    final mona = await party('منى حسن', phone: '01055550000'); // rule (c)
    final inactive = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'محذوف',
          phone: const d.Value('01500000001'),
          isCustomer: const d.Value(true),
          isActive: const d.Value(false),
        ));

    final tableId = await db
        .into(db.restaurantTables)
        .insert(RestaurantTablesCompanion.insert(name: 'T1'));
    final when = DateTime(2030, 1, 1, 19);
    Future<int> res(String name, String? phone) =>
        db.into(db.tableReservations).insert(TableReservationsCompanion.insert(
              tableId: tableId,
              customerName: name,
              customerPhone: d.Value(phone),
              reservationTime: when,
            ));
    final rA = await res('ليلى', '01001112222');
    final rB = await res('سامي علي', '01077778888');
    final rC = await res('منى حسن', '01066660000');
    final rD1 = await res('زبون جديد', '01088889999');
    final rD2 = await res('زبون جديد', '+20 108 888 9999');
    final rE = await res('ضيف', null);
    final rDead = await res('محذوف', '01500000001');

    final svc = await db
        .into(db.bookingServices)
        .insert(BookingServicesCompanion.insert(name: 'خدمة'));
    final bk = await db.into(db.bookings).insert(BookingsCompanion.insert(
          customerName: 'عميل حجز',
          customerPhone: const d.Value('01012121212'),
          serviceId: svc,
          startsAt: when,
          endsAt: when.add(const Duration(minutes: 30)),
        ));

    final result = await db.backfillReservationParties();
    expect(result.skipped, isNull, reason: 'must not be skipped on postgres');
    expect(result.failedGroups, 0, reason: result.toLogLine());
    expect(result.error, isNull);
    expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey), '1');

    // (a) same phone after normalisation → linked, nothing created
    expect(await partyOf('table_reservations', rA), layla);
    // (b) same name, no phone → linked and phone filled
    expect(await partyOf('table_reservations', rB), sami);
    final samiPhone = (await db
            .customSelect('SELECT phone FROM parties WHERE id = $sami')
            .getSingle())
        .data['phone'];
    expect(samiPhone, '01077778888');
    // (c) same name, different phone → a new customer, no merge
    final newMona = await partyOf('table_reservations', rC);
    expect(newMona, isNotNull);
    expect(newMona, isNot(mona));
    // (d) one customer per unique phone
    final fresh = await partyOf('table_reservations', rD1);
    expect(fresh, isNotNull);
    expect(await partyOf('table_reservations', rD2), fresh);
    expect(await partyOf('bookings', bk), isNotNull);
    // (e) no phone → guest
    expect(await partyOf('table_reservations', rE), isNull);
    // inactive customer is not matched → new customer
    final forDead = await partyOf('table_reservations', rDead);
    expect(forDead, isNotNull);
    expect(forDead, isNot(inactive));

    final suspects = await db.listPartyDedupSuspects();
    final filled = suspects.where((s) => s.reason == 'name_match_phone_filled');
    expect(filled.length, 1);
    expect(filled.single.newPartyId, sami);
    expect(filled.single.newPhone, '01077778888');
    expect(
        suspects
            .where((s) => s.reason == 'same_name_different_phone')
            .map((s) => (s.newPartyId, s.existingPartyId)),
        [(newMona!, mona)]);

    // idempotent: a forced second run changes nothing
    final partiesBefore = (await db
            .customSelect('SELECT COUNT(*) AS c FROM parties')
            .getSingle())
        .data['c'];
    final again = await db.backfillReservationParties(force: true);
    expect(again.partiesCreated, 0);
    expect(again.rows, 0);
    expect(
        (await db.customSelect('SELECT COUNT(*) AS c FROM parties').getSingle())
            .data['c'],
        partiesBefore);
  });

  test('already-done flag short-circuits on PostgreSQL', () async {
    final r = await db.backfillReservationParties();
    expect(r.skipped, 'already done');
  });
}

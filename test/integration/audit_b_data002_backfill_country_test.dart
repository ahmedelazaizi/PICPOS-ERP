// Audit B DATA-002 — v196 backfill must not merge customers whose phones carry
// DIFFERENT explicit country codes, while F.1 (local vs international merge)
// stays intact.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../helpers/v195_reservations_db.dart';

void main() {
  late AppDatabase db;
  late int t1;

  setUp(() async {
    db = await openV195ReservationsDb();
    t1 = await insertTestTable(db, 'T1');
  });

  Future<int?> pid(int id) async =>
      (await rowOf(db, 'table_reservations', id))['party_id'] as int?;

  test('+966 and +971 with the same national number become two customers',
      () async {
    final a = await insertTestReservation(db, t1, 'سعودي', '+966501234567',
        hasPartyColumn: false);
    final b = await insertTestReservation(db, t1, 'إماراتي', '+971501234567',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await pid(a), isNotNull);
    expect(await pid(b), isNotNull);
    expect(await pid(a), isNot(await pid(b)));
  });

  test('F.1 intact: local and international forms of one number share a customer',
      () async {
    final a = await insertTestReservation(db, t1, 'سعودي', '+966501234567',
        hasPartyColumn: false);
    final b = await insertTestReservation(db, t1, 'سعودي', '0501234567',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await pid(a), isNotNull);
    expect(await pid(a), await pid(b));
  });

  test('MIG-005(b): several customers on one phone -> lowest id wins, rest are suspects',
      () async {
    final first = await insertTestParty(db, 'أول', phone: '0501234567');
    final second = await insertTestParty(db, 'ثان', phone: '+966 50 123 4567');
    final r = await insertTestReservation(db, t1, 'زبون', '0501234567',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await pid(r), first);
    final sus = (await db.listPartyDedupSuspects())
        .where((s) => s.reason == 'multiple_phone_matches')
        .toList();
    expect(sus, hasLength(1));
    expect(sus.single.newPartyId, second);
    expect(sus.single.existingPartyId, first);
  });

  test('an existing customer with a different explicit country is not reused',
      () async {
    final existing = await insertTestParty(db, 'إماراتي', phone: '+971 50 123 4567');
    final r = await insertTestReservation(db, t1, 'سعودي', '+966501234567',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await pid(r), isNot(existing));
  });
}

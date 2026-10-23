// Audit B ACC-004 — a booking deposit must land on customer advances (2134)
// and requires a registered customer; otherwise it fails closed (no booking,
// no voucher, no revenue 4299).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int partyId;

  setUp(() async {
    db = AppDatabase.forTesting();
    serviceId = await db.into(db.bookingServices).insert(
        BookingServicesCompanion.insert(name: 's', price: const Value(100)));
    partyId = await db.insertParty(
        PartiesCompanion.insert(name: 'c', isCustomer: const Value(true)));
  });
  tearDown(() => db.close());

  Future<int> book({int? party, double deposit = 100}) => db.createBooking(
        customerName: 'c',
        partyId: party,
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        depositAmount: deposit,
        createdBy: 1,
      );

  test('guest booking with a deposit is rejected atomically', () async {
    await expectLater(book(), throwsA(isA<StateError>()));
    expect(await db.select(db.bookings).get(), isEmpty);
    expect(await db.select(db.safeTransactions).get(), isEmpty);
  });

  test('missing 2134 rejects the booking instead of posting to revenue',
      () async {
    await db.customStatement("UPDATE accounts SET code = '2134-x' WHERE code = '2134'");
    await expectLater(book(party: partyId), throwsA(isA<StateError>()));
    expect(await db.select(db.bookings).get(), isEmpty);
    expect(await db.select(db.safeTransactions).get(), isEmpty);
    expect(await db.getAccountByCode('4299'), isNull);
  });

  test('guest booking without a deposit is still allowed', () async {
    expect(await book(deposit: 0), greaterThan(0));
  });
}

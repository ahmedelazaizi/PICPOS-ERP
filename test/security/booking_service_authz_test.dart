// AUTHZ-008 — booking create / status / cancel / reassign are enforced in the
// SERVICE layer, not only by the UI gates. Actor-attributed calls need the code;
// userId == null is the system / sync-replay path.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/booking_actions_service.dart';

void main() {
  late AppDatabase db;
  late BookingActionsService svc;
  late int serviceId;

  setUp(() async {
    db = AppDatabase.forTesting();
    svc = BookingActionsService(db: db);
    serviceId = await db.into(db.bookingServices).insert(BookingServicesCompanion.insert(name: 'قص شعر'));
  });

  Future<int> userWith(List<String> codes, {Map<String, String> modes = const {}}) async {
    final roleId = await db.insertRole(name: 'role-${codes.join('-')}-${modes.length}');
    final all = await db.getAllPermissions();
    final ids = [for (final c in codes) all.firstWhere((p) => p.code == c).id];
    final idModes = {
      for (final e in modes.entries) all.firstWhere((p) => p.code == e.key).id: e.value,
    };
    await db.setRolePermissions(roleId, ids, modes: idModes);
    return db.into(db.users).insert(UsersCompanion.insert(
          username: 'u${DateTime.now().microsecondsSinceEpoch}$roleId',
          passwordHash: 'x',
          displayName: 'مستخدم',
          roleId: Value(roleId),
        ));
  }

  Future<int> seedBooking() => db.into(db.bookings).insert(BookingsCompanion.insert(
        customerName: 'أحمد',
        serviceId: serviceId,
        startsAt: DateTime(2026, 8, 22, 10),
        endsAt: DateTime(2026, 8, 22, 10, 45),
      ));

  Future<int> create(int? userId, {double deposit = 0}) => svc.create(
        customerName: 'سارة',
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 30)),
        depositAmount: deposit,
        userId: userId,
        userName: 'x',
      );

  test('create without bookings_add is denied (nothing written)', () async {
    final u = await userWith([PermissionCodes.bookingsView]);
    await expectLater(create(u), throwsA(isA<PermissionDeniedException>()));
    expect(await db.select(db.bookings).get(), isEmpty);
  });

  test('create with bookings_add works; a deposit also needs bookings_deposit', () async {
    final u = await userWith([PermissionCodes.bookingsAdd]);
    expect(await create(u), greaterThan(0));
    await expectLater(create(u, deposit: 50), throwsA(isA<PermissionDeniedException>()));
    final u2 = await userWith([PermissionCodes.bookingsAdd, PermissionCodes.bookingsDeposit]);
    // Holding the code passes the gate and reaches the DAO's own precondition
    // (a deposit needs a registered customer) - i.e. NOT a PermissionDenied.
    await expectLater(create(u2, deposit: 50), throwsA(isA<StateError>()));
  });

  test('status change needs bookings_status; cancelling needs bookings_cancel', () async {
    final id = await seedBooking();
    final onlyStatus = await userWith([PermissionCodes.bookingsStatus]);
    await svc.setStatus(id, 'confirmed', userId: onlyStatus, userName: 'x');
    await expectLater(svc.setStatus(id, 'cancelled', userId: onlyStatus, userName: 'x'),
        throwsA(isA<PermissionDeniedException>()));
    await expectLater(svc.cancel(id, userId: onlyStatus, userName: 'x'),
        throwsA(isA<PermissionDeniedException>()));

    final canceller = await userWith([PermissionCodes.bookingsCancel]);
    await expectLater(svc.setStatus(id, 'seated', userId: canceller, userName: 'x'),
        throwsA(isA<PermissionDeniedException>()));
    await svc.cancel(id, reason: 'r', userId: canceller, userName: 'x');
    expect((await db.select(db.bookings).getSingle()).status, 'cancelled');
  });

  test('reassign needs bookings_assign', () async {
    final id = await seedBooking();
    final u = await userWith([PermissionCodes.bookingsStatus]);
    await expectLater(
        svc.reassign(id, startsAt: DateTime(2026, 8, 23, 10), userId: u, userName: 'x'),
        throwsA(isA<PermissionDeniedException>()));
  });

  test('a CONDITIONAL grant passes the service (manager approval happens in the UI)', () async {
    final u = await userWith([PermissionCodes.bookingsAdd],
        modes: {PermissionCodes.bookingsAdd: PermissionCodes.grantConditional});
    expect(await create(u), greaterThan(0));
  });

  test('system / sync-replay callers (userId null) are not blocked', () async {
    expect(await create(null), greaterThan(0));
  });
}

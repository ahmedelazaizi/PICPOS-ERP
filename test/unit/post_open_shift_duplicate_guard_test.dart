// Feature 048 (v130) — Server-side `postOpenShift` duplicate-open guard.
//
// Field evidence (2026-05-13): server's shift-report screen showed FOUR
// shifts simultaneously open for admin (user=2): #1, #2, #3, #5. Every
// mirror open call to /api/shifts/open INSERTed a fresh row without
// checking whether the user already had one open server-side. The
// cascade:
//   - getCurrentOpenShift(userId) returns non-deterministic ids across
//     subsequent reads (admin saw openShiftId=1 then 3 then 5)
//   - shift-close calls target whichever id getCurrentOpenShift just
//     returned, so the OTHER opens are stranded
//   - the closing report's time-window starts at the wrong shift's
//     startTime, bundling the wrong invoices
//
// This DAO-level test exercises only the data condition the server
// guard relies on: the guard is "the user has at least one shift with
// status='open' BEFORE this open call". The actual HTTP handler in
// api_data_handler.dart returns the existing shift's id when this
// condition fires (idempotent). Covering the handler path requires
// spinning up a shelf router which is overkill for this guarantee.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-048',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_048',
      password: 'pw',
      displayName: 'F048',
      roleId: roleId,
    );
  });

  tearDown(() => db.close());

  test('detects existing open shift for user → guard fires', () async {
    final firstId = await db.openShift(userId, 0);

    // Simulate the handler's guard: query for user's open shift before
    // INSERT. This must find the row.
    final existingOpen = await (db.select(db.shifts)
          ..where((s) =>
              s.userId.equals(userId) & s.status.equals('open'))
          ..orderBy([(s) => OrderingTerm.desc(s.id)])
          ..limit(1))
        .getSingleOrNull();

    expect(existingOpen, isNotNull,
        reason: 'after one open, the user has one row with status=open '
            '— the guard MUST find it and the handler returns its id '
            'instead of creating a phantom duplicate');
    expect(existingOpen!.id, firstId);
  });

  test('after the user closes their open shift, the guard does NOT '
      'fire — a fresh open is legitimate', () async {
    final firstId = await db.openShift(userId, 0);
    await db.closeShiftWithAudit(firstId, 0);

    final existingOpen = await (db.select(db.shifts)
          ..where((s) =>
              s.userId.equals(userId) & s.status.equals('open'))
          ..limit(1))
        .getSingleOrNull();
    expect(existingOpen, isNull,
        reason: 'after a clean close, no open shift exists for the '
            'user → the guard MUST allow a new open to proceed');
  });

  test('guard is per-user — user A having open shift does NOT block '
      'user B from opening their own', () async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-048b',
            isSystemRole: const Value(false),
          ),
        );
    final userB = await db.createUser(
      username: 'cashier_048b',
      // كلمةٌ مغايرةٌ عن `cashier_048` عن قصد: `createUser` صار يرفض تكرارَ
      // كلمة المرور (§١) — والتجهيزةُ هنا تشاركتها بالمصادفة لا بالنيّة.
      // ونيّةُ الاختبار «الحارسُ لكلّ مستخدمٍ على حدة»، وهي محفوظةٌ كما هي.
      password: 'pw-b',
      displayName: 'B',
      roleId: roleId,
    );

    await db.openShift(userId, 0);

    final existingOpenForB = await (db.select(db.shifts)
          ..where((s) =>
              s.userId.equals(userB) & s.status.equals('open'))
          ..limit(1))
        .getSingleOrNull();
    expect(existingOpenForB, isNull,
        reason: 'the guard MUST scope by userId — user A\'s open '
            'shift does not affect user B\'s open call');
  });

  test('latest-open-wins ordering: multiple stale opens still return '
      'the newest one (resilient to existing data drift)', () async {
    // Simulate the field scenario: 4 opens accumulated before v130.
    // Even with this data drift, the guard returns the LATEST so the
    // mirror's close call targets a shift it actually knows about
    // (which matches the most recent open call).
    final id1 = await db.openShift(userId, 0);
    // Force a closed shift in the middle (won't be returned).
    final mid = await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userId,
            status: 'closed',
            globalId: const Value('gid-mid-048'),
          ),
        );
    final id3 = await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now().add(const Duration(minutes: 1)),
            userId: userId,
            status: 'open',
            globalId: const Value('gid-id3-048'),
          ),
        );

    final picked = await (db.select(db.shifts)
          ..where((s) =>
              s.userId.equals(userId) & s.status.equals('open'))
          ..orderBy([(s) => OrderingTerm.desc(s.id)])
          ..limit(1))
        .getSingleOrNull();

    expect(picked, isNotNull);
    expect(picked!.id, id3,
        reason: 'the guard prefers the LATEST open shift (highest id) '
            'so the mirror\'s subsequent close targets a known row, '
            'not a stale orphan');
    expect(picked.id, isNot(id1));
    expect(picked.id, isNot(mid));
  });
}

// المهمّةُ ٣ (2026-08-16) — العطبُ المقيس: المرتجعُ كان يضرب
// `getDefaultSafeByType('cash')` — خزنةً عامّةً تتجاهل الفرع — بينما البيعُ
// والإقفالُ ينسبان للفرع. فمرتجعٌ في الفرع «ب» كان يُنقص خزنةَ الفرع «أ».
//
// هذا الاختبارُ يثبّت العقدَ: `resolveRefundSafe` تُرجع درجَ فرع الوردية
// المفتوحة لمستخدم المرتجع، لا الخزنةَ الافتراضيةَ العامّة.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async => db.close());

  test('المرتجعُ يُصرف من درج فرع الوردية لا من الخزنة العامّة', () async {
    // فرعان، ولكلٍّ خزنتُه النقدية.
    final branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع أ'),
        );
    final branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع ب'),
        );
    final safeA = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج أ',
            safeType: const Value('cash'),
            branchId: Value(branchA),
          ),
        );
    final safeB = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج ب',
            safeType: const Value('cash'),
            branchId: Value(branchB),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    // ملحوظة: `createUser` لا يقبل `branchId` — فرعُ الكاشير هنا يُحدَّد عبر
    // `shift.branchId` (مطابقةٌ لما يستهلكه `resolveRefundSafe` فعلياً)، لا
    // عبر جدول المستخدم.
    final userB = await db.createUser(
      username: 'cashier_b',
      password: 'x',
      displayName: 'كاشير ب',
      roleId: roleId,
    );

    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userB,
            status: 'open',
            branchId: Value(branchB),
          ),
        );

    final resolved = await db.resolveRefundSafe(userId: userB);

    expect(resolved, isNotNull);
    expect(resolved!.id, safeB,
        reason: 'كاشيرُ الفرع ب يجب أن يصرف من درج فرعه لا من $safeA');
  });
}

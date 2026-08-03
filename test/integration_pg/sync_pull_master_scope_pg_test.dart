// المرحلة ١ / G1 — حصر البيانات الأساسية على `/api/sync/pull`.
//
// قبل الإصلاح: `_syncPullBranchColumn` يحتوي خمسة جداول تعاملية فقط، فسحب
// `warehouses` بـ`branch_id=1` يعيد مخازن كل الفروع. DeltaPull يعمل كل
// دورة ⇒ يعيد ملء قاعدة العميل ببيانات الشركة كاملة، مُلغياً حصر المزامنة
// الكاملة الذي يعمل بشكل صحيح.
@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get(); // اطبع أخطاء الترحيل مبكراً
  });

  tearDownAll(() async => fx.tearDown());

  setUp(() async {
    await fx.db.delete(fx.db.warehouses).go();
    await fx.db.delete(fx.db.safes).go();
    await fx.db.delete(fx.db.userBranchAccess).go();
    await fx.db.delete(fx.db.users).go();
    await fx.db.delete(fx.db.roles).go();
    await fx.db.delete(fx.db.branches).go();

    // فرعان حقيقيان — PostgreSQL ينفّذ الـFK الذي كان SQLite يتجاهله.
    await fx.db.customStatement(
      "INSERT INTO branches (id, name) VALUES (1,'فرع أ'),(2,'فرع ب') "
      'ON CONFLICT (id) DO NOTHING',
    );
    handler = ApiHandler(fx.db);
  });

  /// يستدعي `/api/sync/pull` كمستخدم مُعرَّف. حقن الهوية عبر
  /// `request.change(context: ...)` هو ما يفعله `api_auth_middleware:139`
  /// بعد التحقّق من التوكن — بدونه `_extractBranchId` يرى مستدعياً بلا
  /// هوية ويسلك مساراً مختلفاً تماماً، فيصير الاختبار بلا معنى.
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    int? branchId,
    int? userId,
  }) async {
    final qs = branchId == null ? '' : '&branch_id=$branchId';
    var request = shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/sync/pull?table=$table$qs'),
    );
    if (userId != null) {
      request = request.change(context: {ApiUserCtx.userIdKey: userId});
    }
    final response = await handler.buildRouter().call(request);
    final body = jsonDecode(await response.readAsString())
        as Map<String, dynamic>;
    return (body['rows'] as List).cast<Map<String, dynamic>>();
  }

  /// مستخدم مقيَّد على [branchId] — يحتاج صف `userBranchAccess` وإلا
  /// عاملَه `_extractBranchId` كـ«مُساء التزويد» وقصّه على السنتينل.
  Future<void> seedScopedUser(int userId, int branchId) async {
    await fx.db.into(fx.db.roles).insert(
          RolesCompanion.insert(name: 'كاشير')
              .copyWith(id: const d.Value(9)),
        );
    await fx.db.into(fx.db.users).insert(
          UsersCompanion.insert(
            username: 'u$userId',
            passwordHash: 'h',
            displayName: 'u$userId',
            roleId: const d.Value(9),
          ).copyWith(id: d.Value(userId)),
        );
    await fx.db.into(fx.db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(
            userId: userId,
            branchId: branchId,
          ),
        );
  }

  group('G1 — الجداول الأساسية تُحصَر على الفرع', () {
    test('warehouses: الفرع ١ لا يرى مخزن الفرع ٢', () async {
      await seedScopedUser(10, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 10);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(
        names,
        isNot(contains('مخزن ب')),
        reason: 'مخزن الفرع ٢ تسرّب لجهاز مربوط بالفرع ١ — هذا هو G1',
      );
    });

    test('safes: الفرع ١ لا يرى خزنة الفرع ٢', () async {
      await seedScopedUser(11, 1);
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('safes', branchId: 1, userId: 11);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('خزنة أ'));
      expect(names, isNot(contains('خزنة ب')));
    });

    test('الصفوف بلا فرع تظل ظاهرة (قرار المالك §٢-ب)', () async {
      await seedScopedUser(12, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن يتيم'),
          ); // branchId يبقى NULL
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 12);
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        contains('مخزن يتيم'),
        reason: 'الحصر الصارم يُخفي مخازن مشروعة من أجهزة قائمة',
      );
      expect(names, isNot(contains('مخزن ب')));
    });

    test('branches: الجهاز يرى فرعه فقط', () async {
      await seedScopedUser(13, 1);

      final rows = await pull('branches', branchId: 1, userId: 13);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('فرع أ'));
      expect(
        names,
        isNot(contains('فرع ب')),
        reason: 'قائمة الفروع كاملة تصل لجهاز مربوط بفرع واحد',
      );
    });

    test('cost_centers: مشتقّة عكسياً من الفرع ومخازنه وخزائنه', () async {
      await seedScopedUser(14, 1);

      // ⚠️ `CostCenters.code` مطلوب وبلا قيمة افتراضية
      // (accounting_tables.dart:109) — إغفاله يفشل بـNOT NULL لا بمنطق
      // الحصر، فيبدو الاختبار أحمر للسبب الخطأ.
      await fx.db.customStatement(
        'INSERT INTO cost_centers (id, code, name) VALUES '
        "(101,'CC101','مركز الفرع أ'),(102,'CC102','مركز مخزن أ'),"
        "(103,'CC103','مركز خزنة أ'),(201,'CC201','مركز الفرع ب') "
        'ON CONFLICT (id) DO NOTHING',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 101 WHERE id = 1',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 201 WHERE id = 2',
      );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(102),
            ),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(103),
            ),
          );

      final rows = await pull('cost_centers', branchId: 1, userId: 14);
      final ids = rows.map((r) => r['id']).toSet();

      expect(ids, containsAll(<int>[101, 102, 103]));
      expect(
        ids,
        isNot(contains(201)),
        reason: 'مركز تكلفة الفرع ٢ تسرّب — الاشتقاق العكسي لا يعمل',
      );
    });

    test('cost_centers: فرع بلا أي ارتباط ⇒ صفر صفوف لا كل الصفوف', () async {
      await seedScopedUser(15, 1);
      await fx.db.customStatement(
        "INSERT INTO cost_centers (id, code, name) VALUES "
        "(301,'CC301','مركز غريب') ON CONFLICT (id) DO NOTHING",
      );

      final rows = await pull('cost_centers', branchId: 1, userId: 15);

      expect(
        rows,
        isEmpty,
        reason: 'مجموعة فارغة انقلبت إلى «بلا حصر» — نفس فئة الفشل المفتوح '
            'التي أغلقها سنتينل _kNoBranchAccess',
      );
    });
  });
}

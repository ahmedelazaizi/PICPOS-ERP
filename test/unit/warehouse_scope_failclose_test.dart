// ═══════════════════════════════════════════════════════════════════════════
// ٣-٢ — حصر المخازن: `[]` كانت بتعني «بلا حصر» و«بلا وصول» في نفس الوقت
// ═══════════════════════════════════════════════════════════════════════════
//
// `getUserAccessibleWarehouseIds` بترجّع `List<int>` وتوثيقها بيقول:
// «Returns empty list if user has no restrictions (= full access)».
// فالقائمة الفاضية بتحمل معنيين متضادين:
//
//   • مستخدم **مميّز** (صاحب البرنامج / مدير النظام / مدير مالي) ⇒ بلا حصر.
//   • مستخدم **غير مميّز ومحدش خصّصله مخازن** ⇒ برضه بلا حصر!
//
// النتيجة: أقلّ مستخدم صلاحيةً وأعلاه بياخدوا **نفس النتيجة**. وده توأم باج
// الفروع اللي اتقفل في Spec 151 Track-3 بـ`isFullBranchAccessUser` ولم
// يُقفل للمخازن.
//
// ── قرار المالك (2026-08-04) ───────────────────────────────────────────────
// الإغلاق **على أجهزة العميل/المرآة فقط**. الجهاز المستقل (server/standalone)
// بيفضل بسلوكه القديم عن قصد: محل بجهاز واحد وكاشير محدش خصّصله مخازن
// ماينفعش يقف. الأجهزة اللي بتسرّب فعلاً هي العميل والمرآة — وهي اللي
// بتتقفل هنا.
//
// العقد الجديد `getWarehouseScopeForUser` بيفصل المعنيين بالنوع نفسه، فمفيش
// مُنادٍ يقدر ينسى التفرقة:
//   null   ⇒ مميّز — بلا حصر
//   {}     ⇒ غير مميّز وبلا تخصيص — فشل مقفول (على العميل/المرآة)
//   {ids}  ⇒ محصور على المخازن دي

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/providers/client_scope_provider.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/client_scope.dart';
import 'package:ural_erp/services/network_service.dart';

class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int warehouseA;
  late int warehouseB;
  late int adminRoleId;
  late int cashierRoleId;

  setUp(() async {
    db = AppDatabase.forTesting();

    warehouseA = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن أ'),
        );
    warehouseB = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن ب'),
        );

    // اسم الدور هو معيار الامتياز الفعلي في `isFullBranchAccessUser` —
    // بنزرع الاتنين عشان نمسك الحالتين بنفس التجهيزة.
    adminRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير النظام',
            isSystemRole: const Value(true),
            globalId: const Value('gid-role-admin-wh'),
          ),
        );
    cashierRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'كاشير',
            // ⚠️ الكاشير `isSystemRole == true` كمان — عشان كده الامتياز
            //    بيتحدد بالاسم لا بالعلم ده. جلسة سابقة استعملت العلم
            //    كفحص «مدير نظام» فطلع الإصلاح أوسع من الثغرة.
            isSystemRole: const Value(true),
            globalId: const Value('gid-role-cashier-wh'),
          ),
        );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  Future<int> insertUser({required String username, int? roleId}) {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'x',
            displayName: username,
            roleId: Value(roleId),
          ),
        );
  }

  group('٣-٢ — getWarehouseScopeForUser بيفرّق بين «بلا حصر» و«بلا وصول»', () {
    test('صاحب البرنامج (userId==1) بلا حصر ⇒ null', () async {
      // صاحب البرنامج هو الصف رقم ١ اللي بيزرعه الإقلاع.
      expect(await db.getWarehouseScopeForUser(1), isNull);
    });

    test('مدير النظام بلا حصر ⇒ null', () async {
      final id = await insertUser(username: 'sysadmin_wh', roleId: adminRoleId);
      expect(await db.getWarehouseScopeForUser(id), isNull);
    });

    test('كاشير بلا أي تخصيص ⇒ مجموعة فاضية، مش null', () async {
      final id = await insertUser(username: 'cashier_none', roleId: cashierRoleId);

      final scope = await db.getWarehouseScopeForUser(id);
      expect(scope, isNotNull,
          reason: 'غير مميّز ⇒ محصور، مش «بلا حصر»');
      expect(scope, isEmpty);
    });

    test('كاشير مخصَّصله مخزن واحد ⇒ المخزن ده بس', () async {
      final id = await insertUser(username: 'cashier_one', roleId: cashierRoleId);
      await db.into(db.userWarehouseAccess).insert(
            UserWarehouseAccessCompanion.insert(
              userId: id,
              warehouseId: warehouseA,
            ),
          );

      expect(await db.getWarehouseScopeForUser(id), {warehouseA});
    });
  });

  group('٣-٢ — الحصر الفعلي على قائمة المخازن', () {
    /// نفس المنطق اللي بيطبّقه `allWarehousesProvider`، معزول عن Riverpod
    /// عشان الاختبار يقيس **القرار** لا التوصيل.
    Future<List<int>> visibleWarehouseIds(int userId) async {
      final all = [warehouseA, warehouseB];
      final scope = await db.getWarehouseScopeForUser(userId);
      if (scope == null) return all;
      if (scope.isEmpty) {
        return SyncInterceptor.isClientMode ? const <int>[] : all;
      }
      return all.where(scope.contains).toList();
    }

    test('كاشير بلا تخصيص على جهاز عميل ⇒ صفر مخازن (فشل مقفول)', () async {
      SyncInterceptor.instance = _ClientModeInterceptor();
      final id = await insertUser(username: 'cashier_client', roleId: cashierRoleId);

      expect(await visibleWarehouseIds(id), isEmpty,
          reason: 'الجهاز اللي بيسرّب هو ده — لازم يقفل');
    });

    test('كاشير بلا تخصيص على جهاز مستقل ⇒ كل المخازن (قرار المالك)',
        () async {
      // مفيش interceptor ⇒ isClientMode == false ⇒ جهاز مستقل.
      final id = await insertUser(username: 'cashier_standalone', roleId: cashierRoleId);

      expect(await visibleWarehouseIds(id), [warehouseA, warehouseB],
          reason: 'محل الجهاز الواحد ماينفعش يقف — قرار مقصود مش سهو');
    });

    test('كاشير مخصَّصله مخزن واحد على جهاز عميل ⇒ المخزن ده بس', () async {
      SyncInterceptor.instance = _ClientModeInterceptor();
      final id = await insertUser(username: 'cashier_scoped', roleId: cashierRoleId);
      await db.into(db.userWarehouseAccess).insert(
            UserWarehouseAccessCompanion.insert(
              userId: id,
              warehouseId: warehouseA,
            ),
          );

      expect(await visibleWarehouseIds(id), [warehouseA]);
    });

    test('مدير النظام على جهاز عميل ⇒ كل المخازن', () async {
      SyncInterceptor.instance = _ClientModeInterceptor();
      final id = await insertUser(username: 'sysadmin_client', roleId: adminRoleId);

      expect(await visibleWarehouseIds(id), [warehouseA, warehouseB],
          reason: 'الامتياز لازم يفضل شغّال حتى على جهاز عميل');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // clientScopeProvider — مزوّد غير موصول، لكن فشله المفتوح كان فخاً
  // ═════════════════════════════════════════════════════════════════════════
  group('٣-٢ — clientScopeProvider', () {
    late ProviderContainer container;

    Future<ClientScope> resolveScope({
      required String mode,
      int? clientBranchId,
    }) async {
      final prefs = <String, Object>{'network_mode': mode};
      if (clientBranchId != null) prefs['client_branch_id'] = clientBranchId;
      SharedPreferences.setMockInitialValues(prefs);
      await NetworkService.instance.loadSettings();

      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      return container.read(clientScopeProvider.future);
    }

    tearDown(() async {
      // ما نسيبش الجهاز في وضع «عميل» للاختبارات اللي بعدها.
      SharedPreferences.setMockInitialValues({});
      await NetworkService.instance.loadSettings();
    });

    test('جهاز عميل بلا client_branch_id ⇒ نطاق مقفول مش unrestricted',
        () async {
      final scope = await resolveScope(mode: 'client');

      expect(scope.isWarehouseAllowed(warehouseA), isFalse,
          reason: 'جهاز ناقص التنصيب كان بياخد وصولاً كاملاً');
      expect(scope.isSafeAllowed(1), isFalse);
      expect(scope.isCostCenterAllowed(1), isFalse);
    });

    test('جهاز مستقل ⇒ بلا حصر (السلوك ده مقصود ومش بيتغيّر)', () async {
      final scope = await resolveScope(mode: 'standalone');
      expect(scope.isWarehouseAllowed(warehouseA), isTrue);
    });

    test('المخازن اللي فرعها NULL بتفضل في النطاق (دلالة الخادم OR IS NULL)',
        () async {
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع العميل',
              globalId: const Value('gid-branch-clientscope'),
            ),
          );
      final ownWarehouse = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزن الفرع',
              branchId: Value(branchId),
            ),
          );
      // `warehouseA` و`warehouseB` من التجهيزة الأصلية فرعهم NULL — عامة/المقر.

      final scope = await resolveScope(mode: 'client', clientBranchId: branchId);

      expect(scope.isWarehouseAllowed(ownWarehouse), isTrue);
      expect(scope.isWarehouseAllowed(warehouseA), isTrue,
          reason: 'الخادم بيمرّر صفوف branch_id IS NULL — لو العميل قصّها '
              'الطرفان هيختلفوا وتظهر مخازن «مفقودة» على الجهاز');
    });
  });
}

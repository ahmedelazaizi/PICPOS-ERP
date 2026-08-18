// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ النسبة في الأوضاع الأربعة — مستقلّ · خادم · عميل · مرآة
// ═══════════════════════════════════════════════════════════════════════════
//
// «فرعي» ليس جواباً واحداً، وبناءُ النطاق على `client_branch_id` وحدَه كان
// يترك ثقبين مقيسين:
//
//   • **المرآة**: المعالجُ لا يكتب `client_branch_id` إلا في وضع العميل
//     (`setup_wizard_screen.dart:1062`)، فكان الحصرُ يسقط عن المرآة بالكامل —
//     ومديرٌ مخصَّصٌ له {أ} يُنشئ فاتورةً على مخزنِ ب ثم **لا يراها**، لأن
//     الخادمَ بعد FR-1 يقصّ قراءتَه على فروعه.
//   • **الخادم/المستقلّ**: `client_branch_id` معدومٌ هناك ⇒ بلا حصر، فكاشيرٌ
//     مخصَّصٌ لفرعٍ واحدٍ كان يرى مخازنَ الفروع كلِّها في الفاتورة.
//
// فصار المصدرُ `branchScopeProvider` — وهو الذي يحسم الأربعة بقراراتٍ موثّقةٍ
// للمالك (مرآةٌ محصورةٌ بفروعِ مستخدمها 2026-08-04 · عزلُ العميل · المديرُ
// المُرقّى · فشلٌ مقفولٌ لسيّئ التزويد).

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/mirror_state.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/sync_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

UserWithRole _user({
  required int userId,
  required int roleId,
  required String roleName,
}) {
  final role = Role(
    id: roleId,
    name: roleName,
    isSystemRole: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: userId,
    username: 'user_$userId',
    passwordHash: 'h',
    passwordSalt: 's',
    displayName: 'user_$userId',
    roleId: roleId,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int branchA, branchB;
  late int warehouseA, warehouseA2, warehouseB;
  late int ccOfBranchA, ccOfWarehouseA, ccOfSafeA, ccOfBranchB, ccUnattached;
  late int cashierId, cashierRoleId, adminId, adminRoleId, orphanId;

  Future<int> insertCostCenter(String code) => db.into(db.costCenters).insert(
        CostCentersCompanion.insert(
          code: code,
          name: 'مركز $code',
          globalId: drift.Value('gid-cc-$code'),
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    WebSocketSyncClient.instance.connected.value = false;
    ElevationSnapshot.isCrossBranchElevated = false;

    db = AppDatabase.forTesting();

    ccOfBranchA = await insertCostCenter('BR-A');
    ccOfWarehouseA = await insertCostCenter('WH-A');
    ccOfSafeA = await insertCostCenter('SF-A');
    ccOfBranchB = await insertCostCenter('BR-B');
    ccUnattached = await insertCostCenter('NONE');

    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع أ',
            costCenterId: drift.Value(ccOfBranchA),
            globalId: const drift.Value('gid-br-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع ب',
            costCenterId: drift.Value(ccOfBranchB),
            globalId: const drift.Value('gid-br-b'),
          ),
        );

    warehouseA = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن أ',
            branchId: drift.Value(branchA),
            costCenterId: drift.Value(ccOfWarehouseA),
            globalId: const drift.Value('gid-wh-a'),
          ),
        );
    warehouseA2 = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن أ٢',
            branchId: drift.Value(branchA),
            globalId: const drift.Value('gid-wh-a2'),
          ),
        );
    warehouseB = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن ب',
            branchId: drift.Value(branchB),
            globalId: const drift.Value('gid-wh-b'),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'خزنة أ',
            branchId: drift.Value(branchA),
            costCenterId: drift.Value(ccOfSafeA),
            globalId: const drift.Value('gid-sf-a'),
          ),
        );

    cashierRoleId =
        await db.into(db.roles).insert(RolesCompanion.insert(name: 'كاشير'));
    adminRoleId = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'مدير النظام'));

    cashierId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'cashier_a',
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: 'كاشير أ',
            roleId: drift.Value(cashierRoleId),
          ),
        );
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: cashierId, branchId: branchA),
        );

    adminId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'sysadmin',
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: 'مدير',
            roleId: drift.Value(adminRoleId),
          ),
        );

    // مستخدمٌ سيّئُ التزويد: غيرُ مميَّزٍ وبلا أيِّ تخصيصِ فرع.
    orphanId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'orphan',
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: 'بلا فرع',
            roleId: drift.Value(cashierRoleId),
          ),
        );

    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    SharedPreferences.setMockInitialValues({});
    await db.close();
  });

  void loginAs(int userId, int roleId, String roleName) {
    container.read(authProvider);
    container
        .read(authProvider.notifier)
        .login(_user(userId: userId, roleId: roleId, roleName: roleName));
  }

  void loginCashier() => loginAs(cashierId, cashierRoleId, 'كاشير');

  Future<List<int>> warehouseIds({int? keepSelected}) async =>
      (await container.read(assignableWarehousesProvider(keepSelected).future))
          .map((w) => w.id)
          .toList();

  Future<List<int>> costCenterIds() async =>
      (await container.read(assignableCostCentersProvider.future))
          .map((c) => c.id)
          .toList();

  Future<void> enterMirrorMode() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'fake-server',
      adminUserId: 1,
      lastHandshakeAt: DateTime.now().toUtc(),
    );
    expect(MirrorState.instance.isConfigured, isTrue);
  }

  Future<void> enterClientMode({required int deviceBranchId}) async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SharedPreferences.setMockInitialValues({'client_branch_id': deviceBranchId});
    // ذراعُ عزلِ العميل تشترط `SyncService.instance` غيرَ معدومةٍ وعلَمَ
    // السحبِ المعاملاتي مطفأً (الافتراضي على عميلٍ مربوط).
    SyncService(serverUrl: 'http://fake-server', localDb: db);
    expect(SyncService.instance?.clientPullsTransactionalEnabled, isFalse);
  }

  group('المخازن — الأوضاعُ الأربعة', () {
    test('مستقلّ/خادم + كاشيرٌ مخصَّصٌ لفرعٍ ⇒ مخازنُ فرعِه وحدَها', () async {
      loginCashier();

      expect(await warehouseIds(), [warehouseA, warehouseA2],
          reason: 'الثقبُ الأوّل: `client_branch_id` معدومٌ على الخادم '
              'والمستقلّ فكان الكاشيرُ يرى مخازنَ الفروعِ كلَّها');
    });

    test('مستقلّ + مستخدمٌ مميَّز ⇒ كلُّ المخازن', () async {
      loginAs(adminId, adminRoleId, 'مدير النظام');

      expect(await warehouseIds(), containsAll([warehouseA, warehouseB]));
    });

    test('مرآة + مستخدمٌ مخصَّصٌ لفرعٍ ⇒ مخازنُ فروعِه وحدَها', () async {
      // على المرآة يُقفل حصرُ المخزنِ للمستخدم أيضاً (سابقة 2026-08-04)،
      // فنمنحه مخازنَ فرعِه صراحةً كي يقيسَ هذا الاختبارُ **حصرَ الفرع** وحدَه.
      for (final id in [warehouseA, warehouseA2]) {
        await db.into(db.userWarehouseAccess).insert(
              UserWarehouseAccessCompanion.insert(
                userId: cashierId,
                warehouseId: id,
              ),
            );
      }
      await enterMirrorMode();
      loginCashier();

      expect(await warehouseIds(), [warehouseA, warehouseA2],
          reason: 'الثقبُ الثاني: المرآةُ بلا `client_branch_id` فكان الحصرُ '
              'يسقط عنها — والخادمُ بعد FR-1 يقصّ قراءتَه على فروعه');
    });

    test('مرآة + مستخدمٌ بلا تخصيصِ مخازن ⇒ صفر (فشلٌ مقفولٌ قائم)', () async {
      await enterMirrorMode();
      loginCashier();

      expect(await warehouseIds(), isEmpty,
          reason: 'حصرُ الفرعِ وحدَه لا يكفي على العميل/المرآة: '
              '`getWarehouseScopeForUser` يُرجع `{}` لغيرِ المميَّزِ بلا '
              'تخصيص، وهو فشلٌ مقفولٌ بقرارِ المالك 2026-08-04');
    });

    test('مرآة + مديرٌ مميَّز ⇒ كلُّ المخازن (الجهازُ غيرُ محصور)', () async {
      await enterMirrorMode();
      loginAs(adminId, adminRoleId, 'مدير النظام');

      expect(await warehouseIds(), containsAll([warehouseA, warehouseB]));
    });

    test('عميلٌ مربوطٌ بفرعِ ب ⇒ مخزنُ ب ولو كان المستخدمُ مميَّزاً', () async {
      await enterClientMode(deviceBranchId: branchB);
      loginAs(adminId, adminRoleId, 'مدير النظام');

      expect(await warehouseIds(), [warehouseB],
          reason: 'عزلُ المرحلة ٦: ربطُ الجهازِ يحصر حتى المميَّز');
    });

    test('مستخدمٌ سيّئُ التزويد ⇒ لا شيء، ولا توسيع', () async {
      loginAs(orphanId, cashierRoleId, 'كاشير');

      expect(await warehouseIds(), isEmpty,
          reason: '`{}` فشلٌ مقفولٌ قرّره `branchScopeProvider`، وتوسيعُه '
              'يُبطل كلَّ حصرٍ فرعيٍّ في المستودع');
    });

    // ── نافذةُ الانفتاح التي أُغلقت بتوحيدِ الإشارة ───────────────────────
    //
    // `SyncInterceptor.isClientMode` = `isClient || WriteRouter.isMirrorActive`،
    // و`isMirrorActive` تشترط `MirrorState.isConfigured`. فمرآةٌ لم يكتمل
    // تصافحُها كانت تُقرأ «جهازاً مستقلاً» ⇒ يُوسَّع لها بدل أن تُقفل.
    // والمُحدِّدُ صار `NetworkService.isBranchScopedDevice` (هويّةُ الجهاز).
    test('مرآةٌ لم يكتمل تصافحُها ⇒ تبقى مقفولةً لا مفتوحة', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      MirrorState.instance.debugSetForTests(); // بلا تصافح ⇒ isConfigured=false
      expect(MirrorState.instance.isConfigured, isFalse);
      loginCashier(); // مخصَّصٌ لفرعِ أ وبلا تخصيصِ مخازن

      expect(await warehouseIds(), isEmpty,
          reason: 'الإشارةُ القديمةُ كانت تنفتح هنا فتُسلّمه مخازنَ فرعِه '
              'كاملةً رغم أنه غيرُ مميَّزٍ وبلا تخصيص');
    });
  });

  group('المخازن — الصلاحيةُ والصلاحُ وإبقاءُ المنتقى', () {
    test('حصرُ المستخدمِ على مستوى المخزن يُطبَّق فوق حصرِ الفرع', () async {
      await db.into(db.userWarehouseAccess).insert(
            UserWarehouseAccessCompanion.insert(
              userId: cashierId,
              warehouseId: warehouseA2,
            ),
          );
      loginCashier();

      expect(await warehouseIds(), [warehouseA2],
          reason: 'كاشيرٌ مخصَّصٌ لمخزنٍ واحدٍ كان يرى مخازنَ فرعِه كلَّها');
    });

    test('المحذوفُ ناعماً والمعطَّلُ خارجَ القائمة', () async {
      final deleted = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزنٌ محذوف',
              branchId: drift.Value(branchA),
              deletedAt: drift.Value(DateTime(2026, 8, 1)),
              globalId: const drift.Value('gid-wh-del'),
            ),
          );
      final inactive = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزنٌ معطَّل',
              branchId: drift.Value(branchA),
              isActive: const drift.Value(false),
              globalId: const drift.Value('gid-wh-off'),
            ),
          );
      loginCashier();

      final ids = await warehouseIds();
      expect(ids, isNot(contains(deleted)));
      expect(ids, isNot(contains(inactive)));
    });

    test('keepSelected يُبقي مخزناً خارجَ النطاق حاضراً', () async {
      loginCashier();

      expect(await warehouseIds(keepSelected: warehouseB), contains(warehouseB),
          reason: 'قائمةٌ بلا قيمتِها المنتقاةِ تُسقط `DropdownButton`، '
              'وإسقاطُها صامتاً يعيد كتابةَ صفٍّ قائم');
    });

    test('فرعٌ بلا مخازنَ صالحة: توسيعٌ على المستقلّ ورفضٌ على العميل',
        () async {
      await (db.delete(db.warehouses)..where((w) => w.branchId.equals(branchA)))
          .go();
      loginCashier();

      expect(await warehouseIds(), isNotEmpty,
          reason: 'محلٌّ بجهازٍ واحدٍ ما ينفعش يقف — سابقةُ المالك 2026-08-04');

      await enterClientMode(deviceBranchId: branchA);
      container.invalidate(branchScopeProvider);
      expect(await warehouseIds(), isEmpty,
          reason: 'الأجهزةُ التي تسرّب تُقفل، والحفظُ يرفض برسالةٍ قابلةٍ للإصلاح');
    });
  });

  group('توحيدُ إشارةِ الجهاز — المُحدِّدُ نفسُه خارجَ منتقي الفاتورة', () {
    // ⚠️ توأمُه `allWarehousesProvider` يحمل القرارَ نفسَه بالسطر نفسِه، ولا
    // يُقاس هنا: مزوّدُ تدفّقٍ فوق drift لا يُصدر داخلَ `ProviderContainer`
    // مجرّدةً من ربطِ الودجت فينتهي بمهلةِ ٣٠ث. قِيس بالتحليل لا بالاختبار.
    test('userAccessibleWarehousesProvider يُقفل على مرآةٍ ناقصةِ التصافح',
        () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      MirrorState.instance.debugSetForTests();
      loginCashier();

      expect(await container.read(userAccessibleWarehousesProvider.future),
          isEmpty,
          reason: 'نفسُ قرارِ 2026-08-04 بنفسِ الإشارة — وإلا اختلف منتقي '
              'الفاتورةِ عن بقيّةِ الشاشات على الجهازِ نفسِه');
    });
  });

  group('مراكزُ التكلفة — اشتقاقٌ كخادمِ PicPos', () {
    test('كاشيرُ فرعِ أ ⇒ مركزُ الفرعِ ومخزنِه وخزنتِه لا غير', () async {
      loginCashier();

      final ids = await costCenterIds();

      expect(ids, containsAll([ccOfBranchA, ccOfWarehouseA, ccOfSafeA]),
          reason: 'نفسُ اشتقاقِ `_resolveBranchCostCenterIds` في الخادم');
      expect(ids, isNot(contains(ccOfBranchB)));
      expect(ids, isNot(contains(ccUnattached)),
          reason: 'مركزٌ لا يشير إليه فرعٌ ولا مخزنٌ ولا خزنةٌ خارجَ النطاق');
    });

    test('مستخدمٌ مميَّز ⇒ كلُّ المراكز', () async {
      loginAs(adminId, adminRoleId, 'مدير النظام');

      expect(await costCenterIds(), containsAll([ccOfBranchB, ccUnattached]));
    });

    test('مستخدمٌ سيّئُ التزويد ⇒ لا مراكز', () async {
      loginAs(orphanId, cashierRoleId, 'كاشير');

      expect(await costCenterIds(), isEmpty);
    });
  });
}

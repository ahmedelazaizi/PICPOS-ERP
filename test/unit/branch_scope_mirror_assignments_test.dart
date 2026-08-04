// ═══════════════════════════════════════════════════════════════════════════
// حصر المرآة على فروع المستخدم المخصَّصة — بطلب المالك (2026-08-04)
// ═══════════════════════════════════════════════════════════════════════════
//
// كان مسار المرآة في `branchScopeProvider` يرمي `accessIds` كاملةً ويُرجِع
// `BranchScope.fullAccess()` بلا شرط، فمدير فرعين على الخادم كان يرى كل
// الفروع على المرآة. المتطلَّب: «الميرور لما يكون المستخدم الادارى متحددله
// فروع معينه بينحصر عرض الفروع له على الفروع اللى تم تحديدها من السيرفر».
//
// هذا يجعل الواجهة تتّفق مع الخادم بعد FR-1: `_resolveBranchScope` صار يقصّ
// المستدعي متعدّد الفروع على `IN (allowed)` بدل التثبيت على فرعه الرئيسي —
// فالخادم يسلّم فروع المستخدم فقط، والواجهة تعلن نفسها.
//
// الملف يثبّت أربع حالات — أهمّها الثالثة: مستخدم غير مميّز سيّئ التزويد
// على مرآة كان يرى **كل شيء** وصار **لا يرى شيئاً** (فشل مقفول)، وهو أثر
// جانبي للاتّساق يحتاج إقرار المالك.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// `providers.dart` يعيد تصدير `branch_scope_provider.dart`، ومنه
// `resolveForeignRowScope` — فاستيراده صراحةً زائد ويكسر خطّ الأساس.
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/mirror_state.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/sync_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

UserWithRole _userWithRole({
  required int userId,
  required int roleId,
  required String roleName,
  required bool isSystemRole,
}) {
  final role = Role(
    id: roleId,
    name: roleName,
    isSystemRole: isSystemRole,
    createdAt: DateTime.now(),
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
    createdAt: DateTime.now(),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // قناة SharedPreferences

  late AppDatabase db;
  late ProviderContainer container;
  late int branchA;
  late int branchB;
  late int branchC;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    WebSocketSyncClient.instance.connected.value = false;
    ElevationSnapshot.isCrossBranchElevated = false;

    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_A',
            globalId: const drift.Value('gid-ma-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_B',
            globalId: const drift.Value('gid-ma-b'),
          ),
        );
    // فرع ثالث لا يُخصَّص لأحد — لولاه لكانت «كل الفروع» و«الفروع
    // المخصَّصة» نفس المجموعة، فتمرّ الحالة ١ بلا إصلاح.
    branchC = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'branch_C',
            globalId: const drift.Value('gid-ma-c'),
          ),
        );

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    container.read(authProvider);
  });

  tearDown(() async {
    container.dispose();
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await db.close();
  });

  Future<(int userId, int roleId)> insertUser(
    String username,
    String roleName,
  ) async {
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: roleName),
        );
    final userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'h',
            passwordSalt: const drift.Value('s'),
            displayName: username,
            roleId: drift.Value(roleId),
          ),
        );
    return (userId, roleId);
  }

  void becomeConfiguredMirror() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'hq.example.com:8080',
      lastHandshakeAt: DateTime.now().toUtc(),
    );
    // FutureProvider لا يبطل نفسه حين تتغيّر المفردات العامة التي يقرأها.
    container.invalidate(branchScopeProvider);
  }

  group('branchScopeProvider — المرآة تحترم تخصيص الفروع', () {
    test('١. مرآة + مدير مخصَّص له فرعان ⇒ ينحصر عليهما', () async {
      final (userId, roleId) = await insertUser('mgr_ab', 'مدير فرع');
      for (final b in [branchA, branchB]) {
        await db.into(db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: userId, branchId: b),
            );
      }
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'مدير فرع',
            isSystemRole: false,
          ));

      becomeConfiguredMirror();
      final scope = await container.read(branchScopeProvider.future);

      expect(scope.hasFullAccess, isFalse,
          reason: 'المرآة كانت ترمي accessIds وتُرجِع fullAccess بلا شرط');
      expect(scope.allowedBranchIds, equals({branchA, branchB}));
      expect(scope.isAllowed(branchC), isFalse,
          reason: 'فرع غير مخصَّص على الخادم يجب ألا يظهر على المرآة');
      // ⚠️ هذا التوقّع **يوثّق ولا يميّز**: حاولتُ جعله يفرّق بين
      // `getUserBranchId` و`accessIds.first` بعكس ترتيب الإدخال، فأثبت
      // التشغيل أن `WHERE user_id = ?` يستعمل فهرس المفتاح الأساسي
      // `(user_id, branch_id)` فترجع الصفوف مرتّبة `branch_id ASC` أصلاً ⇒
      // الحلّان يعطيان `branchA` هنا مهما كان ترتيب الإدخال.
      //
      // الافتراق الحقيقي في مستخدم وصولُه **بمنحة منطقة فقط**: عندئذ
      // `accessIds.first` فرعٌ ما بينما `getUserBranchId` تعطي `null` (تقرأ
      // `user_branch_access` المباشر وحده). لم يُثبَّت هنا لأن تثبيته يقفل
      // `null` كسلوك مقصود، وهو حافّة قائمة في ذراع user-assignments أيضاً
      // ومرشّحة لتذكرة مستقلة — لا شيء تقرّره هذه المهمة.
      expect(scope.primaryBranchId, equals(branchA),
          reason: 'الفرع الرئيسي = أصغر branchId، اتّساقاً مع ذراع '
              'user-assignments (getUserBranchId)');
    });

    test('٢. مرآة + مدير نظام بلا تخصيص ⇒ كل الفروع (قرار المالك الصريح)',
        () async {
      final (userId, roleId) = await insertUser('sysadmin', 'مدير النظام');
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'مدير النظام',
            isSystemRole: true,
          ));

      becomeConfiguredMirror();
      final scope = await container.read(branchScopeProvider.future);

      expect(scope.allowedBranchIds, isNull,
          reason: 'حارس ارتداد: المالك أقرّ حرفياً أن مدير النظام يظل يرى كل '
              'الفروع على المرآة');
      expect(scope.isAllowed(branchC), isTrue);
    });

    test('٣. مرآة + مستخدم غير مميّز سيّئ التزويد ⇒ يفشل مقفولاً', () async {
      // تغيير سلوك: قبل هذا الإصلاح كان يرى **كل** الفروع على المرآة.
      // الشكل المتّسق (نفس ما تفعله ذراع accessIds.isEmpty العامة ونفس ما
      // يفعله الخادم في _resolveBranchScope) يجعله لا يرى شيئاً حتى يُخصَّص.
      final (userId, roleId) = await insertUser('cashier_none', 'كاشير');
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'كاشير',
            isSystemRole: false,
          ));

      becomeConfiguredMirror();
      final scope = await container.read(branchScopeProvider.future);

      expect(scope.hasFullAccess, isFalse,
          reason: 'بلا تخصيص وبلا امتياز = لا وصول كامل');
      expect(scope.allowedBranchIds, isEmpty);
      expect(scope.isAllowed(branchA), isFalse);
    });

    test('٤. جهاز عميل مربوط لم يتغيّر ⇒ ما زال محصوراً على client_branch_id',
        () async {
      final (userId, roleId) = await insertUser('mgr_client', 'مدير فرع');
      for (final b in [branchA, branchB]) {
        await db.into(db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: userId, branchId: b),
            );
      }
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'مدير فرع',
            isSystemRole: false,
          ));

      SharedPreferences.setMockInitialValues({'client_branch_id': branchB});
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      MirrorState.instance.debugSetForTests();
      // ذراع عزل العميل تشترط `SyncService.instance` غير معدومة وعلَم السحب
      // المعاملاتي مطفأً (الافتراضي على عميل مربوط).
      SyncService(serverUrl: 'http://fake-server', localDb: db);
      expect(SyncService.instance?.clientPullsTransactionalEnabled, isFalse);

      container.invalidate(branchScopeProvider);
      final scope = await container.read(branchScopeProvider.future);

      expect(scope.allowedBranchIds, equals({branchB}),
          reason: 'ربط الجهاز يتقدّم على تخصيص المستخدم على مسار العميل — '
              'هذه المهمة تمسّ مسار المرآة وحده');
      expect(scope.primaryBranchId, equals(branchB));
    });

    // ⚠️ حرج — أداة التنظيف على المرآة.
    //
    // `resolveForeignRowScope` كانت تفحص النطاق قبل سياق الجهاز. قبل حصر
    // المرآة كان كل مستخدم عليها `hasFullAccess` فيسقط لحارس السياق ويأخذ
    // `{}` — أي أن الأداة كانت معطّلة على المرآة **بالصدفة**. بعد الحصر صار
    // المدير المخصَّص `hasFullAccess == false` فيرجع السطر الأول `{A, B}`
    // ولا يُبلَغ حارس المرآة ⇒ `wipeForeignBranchData` تُسلَّح على وحدة تحكّم
    // المقر وتحذف صفوف الفرع C من قاعدتها المحلية (فواتير · قيود · حركات
    // مخزون · سجلّ عمليات). إصلاحان صحيحان ظاهرياً ركّبا مساراً مدمّراً.
    test('٥. مرآة + مستخدم مخصَّص ⇒ أداة التنظيف تبقى معطّلة', () async {
      final (userId, roleId) = await insertUser('mgr_wipe', 'مدير فرع');
      for (final b in [branchA, branchB]) {
        await db.into(db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: userId, branchId: b),
            );
      }
      container.read(authProvider.notifier).login(_userWithRole(
            userId: userId,
            roleId: roleId,
            roleName: 'مدير فرع',
            isSystemRole: false,
          ));

      becomeConfiguredMirror();
      final scope = await container.read(branchScopeProvider.future);
      expect(scope.hasFullAccess, isFalse,
          reason: 'حارس الفرضية: بدون الحصر يسقط الاختبار على الحارس القديم '
              'ولا يقيس الترتيب');

      expect(await resolveForeignRowScope(scope), isEmpty,
          reason: 'المرآة ليست جهازاً مربوطاً بفرع، فلا حدّ تُقاس عليه '
              '«الغرابة» — وقاعدتها نسخة من قاعدة السيرفر. أي مجموعة غير '
              'فارغة هنا تعني حذفاً فعلياً لصفوف فروع أخرى من وحدة تحكّم '
              'المقر (توثيق الدالة نفسه يسمّي المرآة سياقاً يجب أن يعطي {})');
    });
  });
}

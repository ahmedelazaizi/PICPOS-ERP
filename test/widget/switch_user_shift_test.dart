// ═══════════════════════════════════════════════════════════════════════════
// بعد تبديل المستخدم، الكاشير الجاي لازم يتسأل يفتح ورديته.
//
// ── الفخ اللي الاختبار ده موجود عشانه ──────────────────────────────────────
// `_enforceShiftForCashier` كانت بتتنادى من **مكان واحد بس**: `initState` في
// `app_main_screen.dart`. و`switchUser()` **مقصود** إنها ما تهدّش شجرة
// الودجت (عشان ديالوج التبديل ما يموتش مع مفتاح `MaterialApp` في
// main.dart:1217) — فـ`initState` ما بتتنفّذش تاني.
//
// قبل إلغاء الإغلاق الإجباري ده كان متغطّى **بالصدفة**: ديالوج الإغلاق كان
// بيسجّل الخروج، فالشجرة تتهد و«ب» يدخل من الأول. بعد الإلغاء الغطا اتشال،
// و«ب» كان هيبيع بلا وردية مفتوحة خالص — وفواتيره ما تتنسبش لأي وردية
// وتقرير الإغلاق يضيّعها.
//
// عشان كده المنطق اتحوّل لدالة عليا `enforceShiftForUser` بينادوها المسارين.
// الاختبارات هنا بتشغّلها مباشرةً بمخزن وهمي — بلا شاشة كاملة وبلا قاعدة
// بيانات (درس دفعة ٦أ: شاشة حقيقية على AppDatabase.forTesting بتوصل مهلة
// عشر دقايق).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/app_main_screen.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/branch_scope_provider.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_opening_balance_dialog.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/shift_dialog_session_guard.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

/// `getCurrentOpenShift` هي الوحيدة المهمة هنا؛ `openShift` بتتسجّل عشان
/// نتأكد إن فتح وردية «ب» ما بيلمسش وردية «أ».
class _FakeTreasuryRepo implements ITreasuryRepository {
  /// وردية مفتوحة لكل مستخدم — بالظبط زي `shifts.userId` في الاسكيما.
  final Map<int, ShiftData> openByUser;

  final List<int> openedFor = [];

  _FakeTreasuryRepo(this.openByUser);

  @override
  Future<ShiftData?> getCurrentOpenShift(int userId) async =>
      openByUser[userId];

  @override
  Future<int> openShift(int userId, double openingBalance,
      {int? branchId}) async {
    openedFor.add(userId);
    openByUser[userId] = ShiftData(
      id: 100 + userId,
      userId: userId,
      startTime: DateTime(2026, 1, 1, 9),
      openingBalance: openingBalance,
      status: 'open',
    );
    return 100 + userId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ShiftData _shiftFor(int userId) => ShiftData(
      id: userId,
      userId: userId,
      startTime: DateTime(2026, 1, 1, 8),
      openingBalance: 0,
      status: 'open',
    );

UserWithRole _cashier(int id, String name) {
  final role = Role(
    id: 1,
    name: 'كاشير',
    isSystemRole: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: id,
    username: 'u$id',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: name,
    roleId: 1,
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
  setUp(() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    WebSocketSyncClient.instance.connected.value = false;
    DiagnosticLogger.enableTestMode();
    // الحارس ده عالمي وبيفضل بين الاختبارات — `switchUser()` بتفضّيه في
    // الإنتاج، فبنفضّيه هنا بنفس المنطق.
    clearShiftDialogPromptedUsers();
  });

  /// بتنادي `enforceShiftForUser` جوه شجرة صغيرة (بتعرض ديالوج) وبترجّع
  /// المخزن الوهمي عشان الاختبار يفحص أثره.
  Future<_FakeTreasuryRepo> runEnforce(
    WidgetTester tester, {
    required UserWithRole signedInAs,
    required Map<int, ShiftData> openShifts,
  }) async {
    final repo = _FakeTreasuryRepo(openShifts);

    final container = ProviderContainer(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(repo),
        // من غير التخطّي ده الدالة بتوصل لقاعدة بيانات حقيقية عشان تحدد
        // الفرع. الكود بيمسك أي فشل هنا ويكمّل، بس التخطّي أوضح وأسرع.
        branchScopeProvider.overrideWith(
          (ref) async => const BranchScope.fullAccess(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider.notifier).login(signedInAs);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => enforceShiftForUser(context, ref,
                    callSite: 'test'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('كاشير بلا وردية مفتوحة → ديالوج فتح الوردية بيظهر',
      (tester) async {
    final repo = await runEnforce(
      tester,
      signedInAs: _cashier(2, 'كاشير ب'),
      openShifts: {},
    );

    expect(
      find.byType(PosOpeningBalanceDialog),
      findsOneWidget,
      reason: 'ده اللي كان بيضيع بعد التبديل — switchUser ما بتهدّش الشجرة '
          'فـinitState ما بتشتغلش',
    );
    expect(repo.openedFor, isEmpty, reason: 'لسه ما دخلش رصيد افتتاحي');
  });

  testWidgets('كاشير عنده وردية مفتوحة → مفيش ديالوج', (tester) async {
    await runEnforce(
      tester,
      signedInAs: _cashier(2, 'كاشير ب'),
      openShifts: {2: _shiftFor(2)},
    );

    expect(find.byType(PosOpeningBalanceDialog), findsNothing,
        reason: '«ب» راجع لورديته اللي سابها مفتوحة — ما يتسألش تاني');
  });

  testWidgets('وردية «أ» بتفضل مفتوحة بعد ما «ب» يفتح ورديته', (tester) async {
    // جوهر «وردية لكل كاشير»: الوردية مفتاحها `userId`، ففتح وردية «ب»
    // ما بيلمسش وردية «أ» خالص.
    final openShifts = {1: _shiftFor(1)};

    final repo = await runEnforce(
      tester,
      signedInAs: _cashier(2, 'كاشير ب'),
      openShifts: openShifts,
    );

    expect(find.byType(PosOpeningBalanceDialog), findsOneWidget);

    // «ب» بيدخل رصيد افتتاحي ويكمّل.
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('بدء الوردية'));
    await tester.pumpAndSettle();

    expect(repo.openedFor, [2], reason: 'وردية «ب» هي اللي اتفتحت');
    expect(repo.openByUser[1]?.status, 'open',
        reason: 'وردية «أ» ما اتقفلتش — دي كل فكرة وردية لكل كاشير');
    expect(repo.openByUser[2], isNotNull);
  });

  testWidgets('مدير النظام ما بيتسألش يفتح وردية (Spec 135 NOTE 2)',
      (tester) async {
    final adminRole = Role(
      id: 9,
      name: 'مدير النظام',
      isSystemRole: true,
      createdAt: DateTime(2026),
      rowVersion: 0,
    );
    final admin = UserWithRole(
      user: _cashier(9, 'مدير').user.copyWith(roleId: const Value(9)),
      role: adminRole,
    );

    await runEnforce(tester, signedInAs: admin, openShifts: {});

    expect(find.byType(PosOpeningBalanceDialog), findsNothing,
        reason: 'المدير بيدخل على وردية الكاشير عشان يرصّدها، '
            'مش بيفتح وردية باسمه');
  });
}

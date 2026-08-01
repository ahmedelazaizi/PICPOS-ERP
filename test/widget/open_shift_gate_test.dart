// ═══════════════════════════════════════════════════════════════════════════
// `notifyOpenShift` — إشعار غير مانع بوجود وردية مفتوحة، بيتنادى من مسارين:
//   • تسجيل الخروج            (app_shell.dart)
//   • تحويل المستخدم في نقطة البيع (picpos_switch_user_dialog.dart)
//
// ── ليه اتغير ──────────────────────────────────────────────────────────────
// كان اسمه `ensureShiftClosed` وكان **بوابة مانعة**: بيجبر الكاشير يرصّد
// ورديته قبل الخروج أو التبديل، والتعليق كان بيقول صراحة إنها مالهاش تجاوز
// ولا حتى لمدير النظام. المستخدم راجع القرار وطلب إن الوردية تفضل مفتوحة
// ويكمّلها صاحبها لما يرجع، أو يقفلها اللي عنده `pos_shift_close`.
//
// ── ليه ده مش بيكسر نسبة المبيعات ──────────────────────────────────────────
// `shifts.userId` عمود موجود من الأول، و`getCurrentOpenShift(userId)` مفلترة
// بيه وبـ`status='open'`. يعني وردية كل كاشير مستقلة أصلاً: مبيعات «ب» بتروح
// لوردية «ب» مهما كانت وردية «أ» لسه مفتوحة. البوابة ما كانتش بتحمي النسبة —
// كانت بتفرض انضباط الترصيد، وده اتنقل لشاشة الورديات المتروكة.
//
// الاختبارات دي بتثبّت **إن المستدعي بيكمّل دايماً** — دي كل نقطة التغيير.
// أي رجوع لقيمة يتفرّع عليها المستدعي بيحوّلها لبوابة تاني بالغلط.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/pos/logic/open_shift_gate.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

/// Only `getCurrentOpenShift` matters here; `noSuchMethod` absorbs the rest of
/// the 30-plus member interface so this fake doesn't rot every time it grows.
class _FakeTreasuryRepo implements ITreasuryRepository {
  final ShiftData? answer;

  /// لما تبقى `true` الاستعلام بيرمي — عشان نثبت إن فشل الاستعلام
  /// **ما يعطّلش** المستدعي (الفشل الآمن اتقلب مع تغيير السلوك).
  final bool throws;

  int calls = 0;

  _FakeTreasuryRepo(this.answer, {this.throws = false});

  @override
  Future<ShiftData?> getCurrentOpenShift(int userId) async {
    calls++;
    if (throws) throw StateError('db down');
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ShiftData _openShift() => ShiftData(
      id: 7,
      userId: 42,
      startTime: DateTime(2026, 1, 1, 8),
      openingBalance: 0,
      status: 'open',
    );

UserWithRole _cashier() {
  final role = Role(
    id: 1,
    name: 'كاشير',
    isSystemRole: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: 42,
    username: 'cashier',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: 'كاشير',
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
  });

  /// بتشغّل `notifyOpenShift` جوه شجرة حقيقية (بيعرض توست)، وبترجّع الـfake
  /// عشان الاختبار يتأكد من عدد الاستعلامات.
  ///
  /// [proceeded] بتتحط `true` **بعد** رجوع الدالة — لو الدالة اتحوّلت لبوابة
  /// بأي شكل، السطر ده مش هيتنفّذ أو هيتأخر، والتوقّع بيفشل.
  Future<_FakeTreasuryRepo> runNotify(
    WidgetTester tester, {
    required ShiftData? shift,
    bool signedIn = true,
    bool repoThrows = false,
    required void Function() onReturn,
  }) async {
    final repo = _FakeTreasuryRepo(shift, throws: repoThrows);

    // Signing in BEFORE pumping: calling `login()` from inside `build` trips
    // Riverpod's "modified a provider while the tree was building" assert.
    final container = ProviderContainer(
      overrides: [treasuryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    if (signedIn) container.read(authProvider.notifier).login(_cashier());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await notifyOpenShift(
                    context: context,
                    ref: ref,
                    reason: 'اختبار',
                  );
                  onReturn();
                },
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

  /// `AppToast.show` بيجدول مؤقّت إخفاء تلقائي (٥ ثواني للتحذير) وبيشيل
  /// الـ`OverlayEntry` بعده. من غير تصريف المؤقّت ده، الاختبار بيموت بـ
  /// «A Timer is still pending even after the widget tree was disposed».
  /// بيتنادى **بعد** التأكيدات عشان التوست يكون لسه ظاهر وقتها.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets('وردية مفتوحة → الإشعار بيظهر والمستدعي بيكمّل', (tester) async {
    var proceeded = false;
    await runNotify(
      tester,
      shift: _openShift(),
      onReturn: () => proceeded = true,
    );

    expect(proceeded, isTrue,
        reason: 'الإشعار ما يمنعش — دي كل نقطة التغيير');
    expect(find.textContaining('ورديتك (#7)'), findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('مفيش وردية مفتوحة → مفيش إشعار والمستدعي بيكمّل', (tester) async {
    var proceeded = false;
    await runNotify(tester, shift: null, onReturn: () => proceeded = true);

    expect(proceeded, isTrue);
    expect(find.textContaining('ورديتك'), findsNothing);
  });

  testWidgets('مش مسجّل دخول → مفيش إشعار ولا استعلام', (tester) async {
    var proceeded = false;
    final repo = await runNotify(
      tester,
      shift: _openShift(),
      signedIn: false,
      onReturn: () => proceeded = true,
    );

    expect(proceeded, isTrue);
    expect(repo.calls, 0, reason: 'مفيش مستخدم يعني مفيش وردية تتنسب له');
    expect(find.textContaining('ورديتك'), findsNothing);
  });

  testWidgets('فشل الاستعلام ما يوقفش المستدعي', (tester) async {
    // الفشل الآمن اتقلب: قبل كده «مقدرناش نتأكد → امنع» — وده كان صح وقت ما
    // كانت بوابة. دلوقتي تعطيل الخروج على إشعار هو الضرر الأكبر.
    var proceeded = false;
    await runNotify(
      tester,
      shift: _openShift(),
      repoThrows: true,
      onReturn: () => proceeded = true,
    );

    expect(proceeded, isTrue);
    expect(find.textContaining('ورديتك'), findsNothing);
  });

  testWidgets('استعلام واحد بس — مفيش إعادة قراءة بعد إغلاق', (tester) async {
    // البوابة القديمة كانت بتستعلم مرتين (قبل الديالوج وبعده) عشان تتأكد إن
    // الوردية قفلت فعلاً. الإشعار مالوش ديالوج إغلاق أصلاً، فاستعلام واحد.
    final repo = await runNotify(
      tester,
      shift: _openShift(),
      onReturn: () {},
    );

    expect(repo.calls, 1);
    await drainToast(tester);
  });
}

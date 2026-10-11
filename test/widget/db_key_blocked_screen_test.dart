// شاشةُ حجب مفتاح القاعدة (E-01): تظهر بدل إنشاء قاعدةٍ فارغة، وتتيح الاسترداد
// برمز، وإعادةَ المحاولة، والرجوعَ بتأكيد، وتصديرَ تشخيص. لا تتجاوز 1366×768.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/db_key/db_key_blocked_screen.dart';
import 'package:ural_erp/services/db_key_blocked_actions.dart';
import 'package:ural_erp/services/db_key_types.dart';

class _Actions implements DbKeyBlockedActions {
  DbKeyResolution retryResult = const DbKeyUnavailable(
      DbKeyUnavailableReason.keyMissing,
      canRecoverWithCode: true);
  String goodCode = 'GOOD-CODE';
  final codes = <String>[];
  int retries = 0;
  int diagnostics = 0;
  bool exited = false;
  bool rollbackSource = true;
  DbKeyRollbackResult rollbackResult = DbKeyRollbackResult.done;
  int rollbacks = 0;

  @override
  Future<DbKeyResolution> retry() async {
    retries++;
    return retryResult;
  }

  @override
  Future<DbKeyResolution> recoverWithCode(String code) async {
    codes.add(code);
    if (code == goodCode) {
      return DbKeyReady(DbKey.raw('a' * 64), DbKeySource.recoveryCode);
    }
    return const DbKeyUnavailable(DbKeyUnavailableReason.recoveryFailed,
        canRecoverWithCode: true);
  }

  @override
  Future<bool> hasRollbackSource() async => rollbackSource;

  @override
  Future<DbKeyRollbackResult> rollbackToPreMigration() async {
    rollbacks++;
    return rollbackResult;
  }

  @override
  Future<String> exportDiagnostics(DbKeyUnavailable why) async {
    diagnostics++;
    return r'C:\tmp\diag.txt';
  }

  @override
  void exitApp() => exited = true;
}

Future<void> _pump(WidgetTester tester, _Actions a,
    {DbKeyUnavailable? res, Size size = const Size(1366, 768)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(DbKeyBlockedApp(
    resolution: res ??
        const DbKeyUnavailable(DbKeyUnavailableReason.keyMissing,
            canRecoverWithCode: true, preMigrationCopyAvailable: true),
    actions: a,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('تُعرض الشاشة بالسبب وتحذير عدم الحذف، بلا overflow', (tester) async {
    await _pump(tester, _Actions());
    expect(find.byKey(const Key('dbkey_blocked_screen')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_reason')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_code_field')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_retry_btn')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_rollback_btn')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_diag_btn')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1366, 768), Size(1024, 600), Size(800, 500)]) {
    testWidgets('لا overflow على ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
      await _pump(tester, _Actions(), size: size);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('بلا غلاف استرداد لا يظهر حقلُ الرمز', (tester) async {
    await _pump(tester, _Actions(),
        res: const DbKeyUnavailable(DbKeyUnavailableReason.wrongKey));
    expect(find.byKey(const Key('dbkey_code_field')), findsNothing);
    expect(find.byKey(const Key('dbkey_retry_btn')), findsOneWidget);
  });

  testWidgets('رمزٌ خاطئ يبقى محجوبًا مع رسالة، والصحيح يعيد الوصول',
      (tester) async {
    final a = _Actions();
    await _pump(tester, a);
    await tester.enterText(find.byKey(const Key('dbkey_code_field')), 'WRONG');
    await tester.tap(find.byKey(const Key('dbkey_recover_btn')));
    await tester.pumpAndSettle();
    expect(a.codes, ['WRONG']);
    expect(find.byKey(const Key('dbkey_message')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_exit_btn')), findsNothing);

    await tester.enterText(find.byKey(const Key('dbkey_code_field')), 'GOOD-CODE');
    await tester.tap(find.byKey(const Key('dbkey_recover_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dbkey_exit_btn')), findsOneWidget);
    expect(find.byKey(const Key('dbkey_retry_btn')), findsNothing);
    await tester.tap(find.byKey(const Key('dbkey_exit_btn')));
    expect(a.exited, isTrue);
  });

  testWidgets('إعادة المحاولة تستدعي الخدمة وتبقى محجوبة إن فشلت', (tester) async {
    final a = _Actions();
    await _pump(tester, a);
    await tester.tap(find.byKey(const Key('dbkey_retry_btn')));
    await tester.pumpAndSettle();
    expect(a.retries, 1);
    expect(find.byKey(const Key('dbkey_blocked_screen')), findsOneWidget);

    a.retryResult =
        DbKeyReady(DbKey.raw('b' * 64), DbKeySource.primarySlot);
    await tester.tap(find.byKey(const Key('dbkey_retry_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dbkey_exit_btn')), findsOneWidget);
  });

  testWidgets('الرجوع لنسخة ما قبل الترحيل يطلب تأكيدًا ولا ينفَّذ بدونه',
      (tester) async {
    final a = _Actions();
    await _pump(tester, a);
    await tester.tap(find.byKey(const Key('dbkey_rollback_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dbkey_rollback_confirm')), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(a.rollbacks, 0);

    a.retryResult = DbKeyReady(
        const DbKey(DbKeyKind.legacyDerived, 'cc'), DbKeySource.legacyDerived);
    await tester.tap(find.byKey(const Key('dbkey_rollback_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dbkey_rollback_yes')));
    await tester.pumpAndSettle();
    expect(a.rollbacks, 1);
    expect(find.byKey(const Key('dbkey_exit_btn')), findsOneWidget);
  });

  testWidgets('الرجوع غير متاح ⇒ رسالة ولا يظهر الزر بلا مصدر', (tester) async {
    final a = _Actions()..rollbackSource = false;
    await _pump(tester, a,
        res: const DbKeyUnavailable(DbKeyUnavailableReason.keyMissing));
    expect(find.byKey(const Key('dbkey_rollback_btn')), findsNothing);
  });

  testWidgets('تصدير التشخيص يستدعي الخدمة ويعرض المسار', (tester) async {
    final a = _Actions();
    await _pump(tester, a);
    await tester.tap(find.byKey(const Key('dbkey_diag_btn')));
    await tester.pumpAndSettle();
    expect(a.diagnostics, 1);
    expect(find.textContaining('diag.txt'), findsOneWidget);
  });
}

// م3-8 — نطاق شاشات الويب وغلاف التنقّل: القوائم متّسقة، والمستبعد/المؤجّل لا
// يتسرّب، والقائمة الجانبية تُبنى من صلاحيات الجلسة.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/web/web_screen_registry.dart';
import 'package:ural_erp/web/web_screen_scope.dart';
import 'package:ural_erp/web/web_session.dart';
import 'package:ural_erp/web/web_shell.dart';

WebSession _session({
  required List<String> codes,
  bool system = false,
  String role = 'محاسب',
}) =>
    WebSession(
      baseUrl: 'http://x',
      token: 't',
      userId: 1,
      username: 'u',
      displayName: 'U',
      roleId: 1,
      roleName: role,
      roleIsSystem: system,
      permissionCodes: codes,
      isPostgres: false,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

void main() {
  test('المستبعد والمؤجّل لا يدخلان نطاق الويب', () {
    expect(kWebScreenIds.intersection(kWebExcludedScreenIds), isEmpty);
    expect(kWebScreenIds.intersection(kWebDeferredScreenIds), isEmpty);
    for (final s in const [
      ScreenId.pos,
      ScreenId.tables,
      ScreenId.kitchen,
      ScreenId.shiftClose,
      ScreenId.scalePlu,
      ScreenId.floorPlanDesigner,
      ScreenId.bookings,
      ScreenId.hr,
      ScreenId.manufacturing,
      ScreenId.distribution,
    ]) {
      expect(kWebScreenIds.contains(s), isFalse, reason: '$s');
    }
  });

  test('كل شاشة مترجَمة (لها باني) ضمن النطاق', () {
    final stray = kWebScreenBuilders.keys.where((s) => !kWebScreenIds.contains(s));
    expect(stray, isEmpty);
  });

  test('لا شاشة مشمولة بلا باني («قريبًا») بعد م3-9', () {
    final soon = kWebScreenIds.where((s) => !kWebScreenBuilders.containsKey(s));
    expect(soon.toSet(), isEmpty);
  });

  test('م3-9: الشاشات الخمس السابقة صارت مترجَمة', () {
    for (final s in [
      ScreenId.salesReturns,
      ScreenId.purchaseReturns,
      ScreenId.settings,
      ScreenId.branches,
      ScreenId.users,
    ]) {
      expect(kWebScreenBuilders.containsKey(s), isTrue, reason: '$s');
    }
  });

  test('مدير النظام يرى كل مداخل النطاق، بلا POS ولا مؤجّل', () {
    final items = webNavItemsFor(
      _session(codes: const ['system_admin'], system: true, role: 'مدير النظام'),
      allowed: ScreenId.values,
    );
    final indexes = items.map((i) => i.index).toSet();
    expect(indexes, contains(ScreenId.dashboard.navigationIndex));
    expect(indexes, contains(ScreenId.receiptVoucher.navigationIndex));
    expect(indexes, contains(ScreenId.trialBalance.navigationIndex));
    for (final banned in [
      ...kWebExcludedScreenIds,
      ...kWebDeferredScreenIds,
    ]) {
      // نفس الفهرس قد يخصّ اسماً بديلاً مشمولاً (cycleCounting/fieldAudit).
      if (kWebScreenIds.any((s) => s.navigationIndex == banned.navigationIndex)) {
        continue;
      }
      expect(indexes.contains(banned.navigationIndex), isFalse, reason: '$banned');
    }
  });

  test('مستخدم محدود الصلاحيات يرى ما صُرّح له فقط', () {
    final items = webNavItemsFor(
      _session(codes: const ['dashboard_access', 'treasury_view']),
      allowed: ScreenId.values,
    );
    final indexes = items.map((i) => i.index).toSet();
    expect(indexes, contains(ScreenId.dashboard.navigationIndex));
    expect(indexes, contains(ScreenId.treasury.navigationIndex));
    expect(indexes, contains(ScreenId.receiptVoucher.navigationIndex));
    expect(indexes, isNot(contains(ScreenId.salesInvoices.navigationIndex)));
    expect(indexes, isNot(contains(ScreenId.generalLedger.navigationIndex)));
  });

  test('بلا صلاحيات: لا مداخل', () {
    expect(
      webNavItemsFor(_session(codes: const []), allowed: ScreenId.values),
      isEmpty,
    );
  });

  test('نطاق البروفايل يقطع القائمة (لا يوسّعها)', () {
    final items = webNavItemsFor(
      _session(codes: const ['system_admin'], system: true, role: 'مدير النظام'),
      allowed: const [ScreenId.dashboard, ScreenId.pos],
    );
    expect(items.map((i) => i.index), [ScreenId.dashboard.navigationIndex]);
  });
}

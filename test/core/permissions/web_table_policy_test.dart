import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/role_grant_matrix.dart';
import 'package:ural_erp/core/permissions/web_table_policy.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late Set<String> dbTables;

  setUpAll(() {
    db = AppDatabase.forTesting();
    dbTables = db.allTables.map((t) => t.actualTableName).toSet();
  });
  tearDownAll(() => db.close());

  test('كلُّ جدولٍ في AppDatabase.allTables له تصنيف', () {
    final missing = dbTables.where((t) => !WebTablePolicy.isClassified(t));
    expect(
      missing,
      isEmpty,
      reason: 'جداولُ بلا تصنيف في web_table_policy.dart',
    );
  });

  test('لا تصنيفَ لجدولٍ غير موجود (يمنع التقادم)', () {
    final stale = WebTablePolicy.rules.keys.where((t) => !dbTables.contains(t));
    expect(stale, isEmpty);
  });

  test('كلُّ كودٍ مذكور في السياسة معرَّفٌ في permission_codes.dart', () {
    final src = File(
      'lib/core/permissions/permission_codes.dart',
    ).readAsStringSync();
    final known = RegExp(
      "static const String \\w+ = '(\\w+)'",
    ).allMatches(src).map((m) => m.group(1)!).toSet();
    final used = {for (final r in WebTablePolicy.rules.values) ...r.anyOf};
    expect(used.difference(known), isEmpty);
  });

  test('ممنوعو الويب لا يدخلون حتى لو مُنح كلُّ كود', () {
    final all = {
      for (final r in WebTablePolicy.rules.values) ...r.anyOf,
      'system_admin',
    };
    final allowed = WebTablePolicy.allowedTables(all);
    for (final t in WebTablePolicy.forbiddenTables) {
      expect(allowed, isNot(contains(t)), reason: t);
    }
    for (final t in const [
      'held_orders',
      'work_orders',
      'restaurant_tables',
      'table_orders',
      'label_scales',
      'printers',
      'receipt_settings',
      'shifts',
      'kitchen_stations',
      'attachment_blobs',
      'sync_outbox',
    ]) {
      expect(WebTablePolicy.forbiddenTables, contains(t));
    }
  });

  test('بلا أيّ صلاحية: المرجعيّ فقط', () {
    final allowed = WebTablePolicy.allowedTables(const []);
    final always = {
      for (final e in WebTablePolicy.rules.entries)
        if (e.value.access == WebTableAccess.always) e.key,
    };
    expect(allowed, always);
    expect(allowed, contains('settings'));
    expect(allowed, isNot(contains('users')));
  });

  test('جداول HR والرواتب تحتاج hr_payroll_view حصراً', () {
    final hrTables = dbTables.where(
      (t) =>
          t.startsWith('employee') ||
          t.startsWith('salary') ||
          t.startsWith('leave_') ||
          t.startsWith('overtime') ||
          t.startsWith('performance_') ||
          t == 'work_holidays' ||
          t == 'fingerprint_devices',
    );
    expect(hrTables, isNotEmpty);
    // أكواد HR الأخرى كلّها لا تكفي.
    final otherHr = {
      'hr_view',
      'hr_manage',
      'hr_advance_record',
      'hr_payroll_process',
      'hr_attendance_view',
      'hr_attendance_edit',
      'hr_leave_request',
      'hr_leave_approve',
      'hr_shifts_manage',
      'hr_payroll_edit',
      'hr_payroll_approve',
      'hr_payroll_post',
      'hr_advances_manage',
      'hr_commissions_manage',
    };
    final without = WebTablePolicy.allowedTables(otherHr);
    final withPayroll = WebTablePolicy.allowedTables({'hr_payroll_view'});
    for (final t in hrTables) {
      expect(without, isNot(contains(t)), reason: t);
      expect(withPayroll, contains(t), reason: t);
    }
  });

  test('المنح المشروط (cond:) لا يكفي، والكود الواحد يفتح جداوله فقط', () {
    final cond = WebTablePolicy.allowedTables({
      'hr_payroll_view',
      'cond:hr_payroll_view',
    });
    expect(cond, isNot(contains('employees')));
    final plain = WebTablePolicy.allowedTables({'sales_view'});
    expect(plain, contains('sales_invoices'));
    expect(plain, isNot(contains('purchase_invoices')));
  });

  test('الأدوار الافتراضية: لا أحد غير من يملك hr_payroll_view يقرأ hr_*', () {
    for (final entry in RoleGrantMatrix.defaultGrants.entries) {
      final allowed = WebTablePolicy.allowedTables(entry.value);
      final canPayroll = entry.value.contains('hr_payroll_view');
      for (final t in ['employees', 'salary_payments', 'employee_contracts']) {
        expect(allowed.contains(t), canPayroll, reason: '${entry.key} / $t');
      }
    }
  });

  test('الكاشير الافتراضي: يقرأ المبيعات ولا يقرأ HR ولا المحاسبة', () {
    final cashier = RoleGrantMatrix.defaultGrants['كاشير']!;
    final allowed = WebTablePolicy.allowedTables(cashier);
    expect(allowed, contains('sales_invoices'));
    final hr = dbTables.where(
      (t) =>
          t.startsWith('employee') ||
          t.startsWith('salary') ||
          t.startsWith('hr_') ||
          t.startsWith('leave_') ||
          t.startsWith('overtime') ||
          t.startsWith('performance_'),
    );
    for (final t in hr) {
      expect(allowed, isNot(contains(t)), reason: t);
    }
    expect(allowed, isNot(contains('journal_entries')));
    expect(allowed, isNot(contains('users')));
    expect(allowed, isNot(contains('held_orders')));
  });
}

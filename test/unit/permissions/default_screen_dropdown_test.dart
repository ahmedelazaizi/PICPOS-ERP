// P2 (2026-10-18) — خيارات قائمة «الشاشة الافتراضية» مشتقّةٌ من السجلّ الحيّ
// ومن ما يفتحه الدورُ المختار؛ لا أربعة خياراتٍ يدويّة ولا خيارٌ ميّت.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/permissions/screen_access_resolver.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/presentation/shared_widgets/default_screen_dropdown.dart';

List<DefaultScreenOption> _options(
  Iterable<String> perms, {
  bool bypass = false,
  bool eInvoice = false,
}) =>
    defaultScreenOptions(
      rolePermissions: perms,
      bypass: bypass,
      eInvoiceAvailable: eInvoice,
      navItems: kAllNavItemDefs,
      flavorAllowed: ScreenId.values.toSet(),
      brandVisible: (_) => true,
    );

void main() {
  const cashier = [
    'pos_access',
    'tables_reserve', // كود فعلٍ فقط — يفتح الطاولات
    'products_edit', // كود فعلٍ فقط — يفتح الأصناف
    'bookings_add',
    'sales_view',
    'inventory_view',
  ];

  test('دور كاشير يرى ≥ 5 شاشات، وكلُّها يفتحها فعلاً', () {
    final opts = _options(cashier);
    expect(opts.length, greaterThanOrEqualTo(5));
    for (final o in opts) {
      expect(
        canOpenScreen(cashier, o.id,
            primaryCode: screenPermissionMap[o.id], bypass: false),
        isTrue,
        reason: 'خيارٌ ميّت: ${o.id}',
      );
    }
    final names = opts.map((o) => o.value).toSet();
    expect(names,
        containsAll(['pos', 'tables', 'products', 'bookings', 'salesInvoices']));
  });

  test('لا تظهر شاشةٌ لا يملك الدورُ أيَّ كودٍ لها', () {
    final names = _options(cashier).map((o) => o.value).toSet();
    for (final hidden in ['treasury', 'settings', 'hr', 'reports', 'branches']) {
      expect(names.contains(hidden), isFalse, reason: hidden);
    }
  });

  test('القيمةُ المخزَّنة ScreenId.name', () {
    for (final o in _options(cashier)) {
      expect(o.value, o.id.name);
      expect(ScreenId.values.byName(o.value), o.id);
    }
  });

  test('مديرُ النظام يرى الكثير، ولا يرى شاشات الأدوات', () {
    final names = _options(const [], bypass: true).map((o) => o.value).toSet();
    expect(names.length, greaterThan(20));
    for (final tool in ['floorPlanDesigner', 'helpCenter', 'syncConflicts']) {
      expect(names.contains(tool), isFalse, reason: tool);
    }
  });

  test('لا تكرارَ في القيم', () {
    final values = _options(const [], bypass: true).map((o) => o.value).toList();
    expect(values.toSet().length, values.length);
  });

  test('الفوترة الإلكترونية بلا منصّة لا تظهر لغير المدير', () {
    final perms = ['einvoice_view'];
    expect(_options(perms).map((o) => o.value), isNot(contains('eInvoice')));
    expect(_options(perms, eInvoice: true).map((o) => o.value),
        contains('eInvoice'));
  });

  test('قيمةٌ قديمةٌ تُطبَّع، وغيرُ المتاحة تصير null بدل assertion', () {
    final opts = _options(cashier);
    expect(normalizeDefaultScreenValue('pos', opts), 'pos');
    expect(normalizeDefaultScreenValue('0', opts), isNull); // لوحة التحكم غير متاحة
    expect(normalizeDefaultScreenValue('1', opts), 'pos');
    expect(normalizeDefaultScreenValue('treasury', opts), isNull);
    expect(normalizeDefaultScreenValue('garbage', opts), isNull);
    expect(normalizeDefaultScreenValue(null, opts), isNull);
  });

  testWidgets('الودجت: قيمةٌ قديمة غير متاحة لا تكسر الـDropdown', (tester) async {
    // الدورُ لم يُحمَّل بعد (بلا مزوّد) ⇒ لا خيارات ولا assertion.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropdownButtonFormField<String>(
          initialValue: normalizeDefaultScreenValue(
              '0', _options(const ['pos_access'])),
          items: [
            for (final o in _options(const ['pos_access']))
              DropdownMenuItem(value: o.value, child: Text(o.value)),
          ],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}

// خطوات المقرّ والفرع والمرآة × العربية/الإنجليزية × الفاتح/الداكن على 1366×768:
// بلا فيض ولا استثناء، وفي الإنجليزية بلا مفتاح ناقص، ثم تمرّ رحلتا المقرّ والفرع
// كاملتين بالإنجليزية والداكن حتى صفحة النجاح بلا مفتاح ناقص.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_steps.dart';

import 'first_run_server_kit.dart';
import 'first_run_test_kit.dart';

MemorySettings _seeded(FirstRunPath path, int step) {
  final last = stepsFor(path).length - 1;
  final d = const FirstRunDraft(draftId: 'sweep').copyWith(
    path: path,
    step: step,
    maxStep: last,
    pack: FirstRunPack.full,
    companyName: 'شركة الأمل',
    currency: 'JOD',
    vatRate: 16,
    branchName: 'الفرع الرئيسي',
    warehouseName: 'المخزن الرئيسي',
    endpoint: '192.168.1.10',
    deviceName: 'POS-1',
    accountUsername: 'cash.amm',
    selectedBranchId: 7,
    selectedBranchName: 'فرع عمّان',
    selectedBranchCode: 'AMM',
    branches: const [FirstRunBranchRow(code: 'AMM', name: 'فرع عمّان')],
    hqUsers: const [
      FirstRunUserRow(
          name: 'كاشير', username: 'c1', roleId: 2, roleName: 'كاشير', scope: 'AMM', rowId: 1),
    ],
  );
  return MemorySettings()..values['setup_draft_v2'] = jsonEncode(d.toJson());
}

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final path in [FirstRunPath.hq, FirstRunPath.branch, FirstRunPath.mirror]) {
    for (final english in [false, true]) {
      for (final dark in [false, true]) {
        final tag =
            '${path.name} · ${english ? 'EN/LTR' : 'AR/RTL'} · ${dark ? 'dark' : 'light'}';
        group(tag, () {
          for (var step = 0; step < stepsFor(path).length; step++) {
            testWidgets('الخطوة ${step + 1} بلا فيض', (tester) async {
              useLocale(english: english);
              final h = FirstRunHarness(settings: _seeded(path, step));
              await h.pump(tester, dark: dark);
              await tester.pump(const Duration(milliseconds: 100));
              expect(tester.takeException(), isNull);
              expect(find.byKey(const Key('first_run_step_title')), findsOneWidget);
              if (english) {
                expect(I18nCatalog.missingKeys, isEmpty,
                    reason: '${I18nCatalog.missingKeys}');
              }
              await h.teardown(tester);
            });
          }
        });
      }
    }
  }

  testWidgets('رحلة المقر كاملة بالإنجليزية والداكن بلا مفتاح ناقص', (tester) async {
    useLocale(english: true);
    final h = FirstRunHarness();
    await h.pump(tester, dark: true);
    await fillHqUntilReview(tester);
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    expect(find.byKey(const Key('first_run_restart')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(I18nCatalog.missingKeys, isEmpty, reason: '${I18nCatalog.missingKeys}');
    await h.teardown(tester);
  });

  testWidgets('رحلة الفرع كاملة بالإنجليزية والداكن بلا مفتاح ناقص', (tester) async {
    useLocale(english: true);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester, dark: true);
    await fillBranchUntilReview(tester);
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_success_connection')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(I18nCatalog.missingKeys, isEmpty, reason: '${I18nCatalog.missingKeys}');
    await h.teardown(tester);
  });

  testWidgets('عرض ضيّق 700 لخطوة المستخدمين والتخزين في المقر بلا فيض', (tester) async {
    for (final step in [2, 3]) {
      useLocale(english: true);
      final h = FirstRunHarness(settings: _seeded(FirstRunPath.hq, step));
      await h.pump(tester, size: const Size(700, 900));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'step $step');
      await h.teardown(tester);
    }
  });
}

// كل خطوة × العربية/الإنجليزية × الفاتح/الداكن على 1366×768 (وعرض ضيّق 700):
// بلا فيض ولا استثناء، والاتجاه من اللغة، وفي الإنجليزية بلا مفتاح ناقص،
// وفي الداكن تباينُ النص الأساسي والخافت ≥ 3.0 على خلفيّته.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

import 'first_run_test_kit.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

MemorySettings _seeded(int step) {
  final d = const FirstRunDraft(draftId: 'sweep').copyWith(
    step: step,
    maxStep: 5,
    pack: FirstRunPack.restaurant,
    companyName: 'مطعم الياسمين',
    currency: 'JOD',
    vatRate: 16,
    branchName: 'الفرع الرئيسي',
    warehouseName: 'المخزن الرئيسي',
  );
  return MemorySettings()..values['setup_draft_v2'] = jsonEncode(d.toJson());
}

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'EN/LTR' : 'AR/RTL'} · ${dark ? 'dark' : 'light'}';
      group(tag, () {
        for (var step = 0; step < 6; step++) {
          testWidgets('الخطوة ${step + 1} بلا فيض', (tester) async {
            useLocale(english: english);
            final h = FirstRunHarness(settings: _seeded(step));
            await h.pump(tester, dark: dark);
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('first_run_step_title')), findsOneWidget);

            final dir = tester.widget<Directionality>(find
                .ancestor(
                  of: find.byType(Scaffold),
                  matching: find.byType(Directionality),
                )
                .first);
            expect(dir.textDirection,
                english ? TextDirection.ltr : TextDirection.rtl);
            if (english) {
              expect(I18nCatalog.missingKeys, isEmpty,
                  reason: '${I18nCatalog.missingKeys}');
            }
            if (dark) {
              final ctx = tester.element(find.byKey(const Key('first_run_step_title')));
              final bg = Theme.of(ctx).scaffoldBackgroundColor;
              final title = tester
                  .widget<Text>(find.byKey(const Key('first_run_step_title')))
                  .style!
                  .color!;
              expect(_contrast(title, bg), greaterThanOrEqualTo(3.0));
              expect(_contrast(ctx.picposMuted, ctx.picposCard),
                  greaterThanOrEqualTo(3.0));
              expect(_contrast(ctx.picposBrandInk, ctx.picposCard),
                  greaterThanOrEqualTo(3.0));
            }
            await h.teardown(tester);
          });
        }
      });
    }
  }

  testWidgets('عرض ضيّق 700 يستعمل ستيبراً مضغوطاً بلا فيض', (tester) async {
    useLocale(english: true);
    final h = FirstRunHarness(settings: _seeded(1));
    await h.pump(tester, size: const Size(700, 900));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Step 2 of 6'), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('125% و150% DPI على 1366×768 بلا فيض في خطوتي الشركة والمراجعة',
      (tester) async {
    for (final scale in [1.25, 1.5]) {
      for (final step in [1, 5]) {
        useLocale(english: false);
        final h = FirstRunHarness(settings: _seeded(step));
        await h.pump(tester, size: Size(1366 / scale, 768 / scale));
        expect(tester.takeException(), isNull, reason: 'scale $scale step $step');
        await h.teardown(tester);
      }
    }
  });
}

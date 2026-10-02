// دليلُ الحسابات — **الرئيسيّ/التفصيليّ** (البند ١٩ للمالك، المرحلة G).
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏• الشجرةُ واللوحُ **ظاهران معاً**: قبل الاختيار حالةٌ فارغةٌ مرشدة،
//   والشجرةُ ~٤٠٪ واللوحُ ~٦٠٪ على عرض ١٣٦٦؛
// ‏• الاختيارُ يعرض الترويسةَ ومسارَ الآباء والرصيدَ (مدين · دائن · صافٍ)
//   وآخرَ الحركات وعددَ الأبناء — والأرقامُ من `getAccountLedger` **بنطاق
//   الفروع الأمنيّ** وبمدى السنة الماليّة الجارية؛
// ‏• «عرض في دفتر الأستاذ» يفتح الدفترَ مرشَّحاً على الحساب؛
// ‏• التحريرُ داخلَ اللوح يحفظ عبر `updateAccount` نفسِه، وأخطاءُ التحقّق
//   تظهر ولا تكتب؛
// ‏• البحثُ يرشّح ويوسّع ويختار — بالرمز، وبالاسم الإنجليزيّ (`trData`)؛
// ‏• RTL/LTR × فاتح/داكن على ١٣٦٦×٧٦٨ بلا فيض، وبلا نصٍّ عربيٍّ في اللوح
//   الإنجليزيّ، وبتباينٍ مقروءٍ في الداكن.
//
// ⚠️ ولا `pumpAndSettle`: مؤشّرُ التحميل يدور بلا نهاية قبل أن يُحلّ الطلب.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/picpos_theme.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/chart_of_accounts_overview.dart';
import 'package:ural_erp/presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';
import 'package:ural_erp/presentation/accounting_picpos/general_ledger_picpos_screen.dart';
import 'package:ural_erp/presentation/screens/coa/coa_shared.dart';

final _arabic = RegExp(r'[\u0600-\u06FF]');

class _FakeRepo implements IAccountingRepository {
  _FakeRepo(this.accounts);
  final List<Account> accounts;

  final ledgerCalls = <({int id, DateTime from, DateTime to, Set<int>? allowed})>[];
  final updates = <Map<String, Object?>>[];

  @override
  Stream<List<Account>> watchAllAccounts() => Stream.value(accounts);

  @override
  Future<List<Account>> getAllAccounts() async => accounts;

  @override
  Future<FiscalYearData?> getCurrentFiscalYear() async => FiscalYearData(
        id: 1,
        name: 'FY 2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        isClosed: false,
        isCurrent: true,
        createdAt: DateTime(2026, 1, 1),
        rowVersion: 1,
      );

  @override
  Future<List<Map<String, dynamic>>> getAccountLedger(
    int accountId,
    DateTime from,
    DateTime to, {
    int? costCenterId,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async {
    ledgerCalls.add((id: accountId, from: from, to: to, allowed: allowedBranchIds));
    return [
      {'is_opening': true, 'entry_date': from, 'balance': 100.0, 'debit': 0.0, 'credit': 0.0},
      {'entry_number': 'JE-0001', 'entry_date': DateTime(2026, 1, 5), 'description': 'Opening cash', 'debit': 1000.0, 'credit': 0.0},
      {'entry_number': 'JE-0002', 'entry_date': DateTime(2026, 2, 10), 'description': 'Supplier payment', 'debit': 0.0, 'credit': 250.0},
      {'entry_number': 'JE-0003', 'entry_date': DateTime(2026, 3, 15), 'description': 'Cash sale', 'debit': 500.0, 'credit': 0.0},
    ];
  }

  @override
  Future<List<CostCenter>> getActiveCostCenters() async => const [];

  @override
  Future<int> updateAccount(int id,
      {String? name,
      String? code,
      bool? isActive,
      bool? isHiddenFromEntries,
      String? accountNature}) async {
    updates.add({'id': id, 'name': name, 'code': code, 'nature': accountNature});
    return 1;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc({
  required int id,
  required String code,
  required String name,
  required String type,
  int? parentId,
  bool isSystem = false,
  String nature = 'detail',
}) =>
    Account(
      id: id,
      code: code,
      name: name,
      accountType: type,
      accountNature: nature,
      normalBalance: type == 'revenue' ? 'credit' : 'debit',
      level: parentId == null ? 1 : 2,
      parentId: parentId,
      balance: 0,
      isSystem: isSystem,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

// ⚠️ أسماءٌ مزروعةٌ كلُّها (`trData` يترجمها) — كي يُقاس «لا عربيَّ في اللوح
//    الإنجليزيّ» على الواجهة لا على بياناتٍ أدخلها مستخدم.
List<Account> _accounts() => [
      _acc(id: 1, code: '1000', name: 'الأصول', type: 'asset', nature: 'view'),
      _acc(id: 2, code: '1101', name: 'الصندوق الرئيسي', type: 'asset', parentId: 1, isSystem: true),
      _acc(id: 3, code: '1102', name: 'أوراق القبض', type: 'asset', parentId: 1),
      _acc(id: 4, code: '4100', name: 'إيرادات المبيعات', type: 'revenue'),
    ];

Future<_FakeRepo> _pump(
  WidgetTester tester, {
  bool english = false,
  Brightness brightness = Brightness.light,
  BranchScope scope = const BranchScope.fullAccess(),
  List<String>? overflows,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  I18nCatalog.setLocale(english ? const Locale('en') : const Locale('ar', 'EG'));
  addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));

  final repo = _FakeRepo(_accounts());
  final previous = FlutterError.onError;
  if (overflows != null) {
    FlutterError.onError = (d) {
      final s = d.toString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        previous?.call(d);
      }
    };
  }
  try {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountingRepositoryProvider.overrideWithValue(repo),
        branchScopeProvider.overrideWith((ref) async => scope),
        branchListProvider.overrideWith((ref) async => const <Branche>[]),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? PicPosTheme.darkTheme
            : PicPosTheme.lightTheme,
        locale: english ? const Locale('en') : const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const ChartOfAccountsPicPosScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  } finally {
    if (overflows != null) FlutterError.onError = previous;
  }
  return repo;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 150));
}

/// يُفكّك الشجرة ويُطلق مؤقّتاتِ الإشعارات (٢٫٥ ث) داخلَ جسم الاختبار.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

/// يختار حساباً بنقر اسمه في الشجرة (الأبُ يُوسَّع ويُختار معاً).
Future<void> _select(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(
    of: find.byKey(const Key('coa_tree')),
    matching: find.text(trData(name)),
  ).first);
  await _settle(tester);
}

Finder get _overview => find.byType(AccountOverviewPanel);

String _tileValue(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
  return texts.last;
}

void main() {
  setUpAll(() {
    final raw = File('assets/i18n/en.json').readAsStringSync();
    I18nCatalog.setCatalog({
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        if (e.value is String) e.key: e.value as String,
    });
  });

  testWidgets('قبل الاختيار: الشجرةُ واللوحُ ظاهران، واللوحُ حالةٌ فارغةٌ مرشدة',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('coa_tree')), findsOneWidget);
    expect(find.byKey(const Key('coa_empty_panel')), findsOneWidget);
    expect(find.text('اختر حساباً من الشجرة'), findsOneWidget);
    expect(_overview, findsNothing);

    // ٤٠ / ٦٠ على ١٣٦٦.
    final tree = tester.getSize(find.byKey(const Key('coa_tree'))).width;
    final panel = tester.getSize(find.byType(CoaEmptyPanel)).width;
    final share = tree / (tree + panel);
    expect(share, closeTo(0.4, 0.02), reason: 'نسبةُ الشجرة $share');
    await _teardown(tester);
  });

  testWidgets(
      'الاختيارُ يعرض الترويسةَ والمسارَ والرصيدَ والحركاتِ وعددَ الأبناء — '
      'بنطاق الفروع ومدى السنة الماليّة', (tester) async {
    final repo = await _pump(tester,
        scope: const BranchScope(allowedBranchIds: {2}, primaryBranchId: 2));
    await _select(tester, 'الأصول'); // يُوسَّع الأبُ
    await _select(tester, 'الصندوق الرئيسي');

    expect(_overview, findsOneWidget);
    expect(find.byKey(const Key('coa_empty_panel')), findsNothing);
    final code = tester.widget<Text>(find.byKey(const Key('coa_overview_code')));
    expect(code.data, '1101');
    final name = tester.widget<Text>(find.byKey(const Key('coa_overview_name')));
    expect(name.data, 'الصندوق الرئيسي');
    // شاراتُ النوع والحالة والنظام.
    expect(find.descendant(of: _overview, matching: find.text('نشط')), findsOneWidget);
    expect(find.descendant(of: _overview, matching: find.text('حساب نظام')),
        findsOneWidget);
    expect(
        find.descendant(of: _overview, matching: find.text('طبيعته مدينة')),
        findsOneWidget);
    // مسارُ الآباء.
    expect(
        find.descendant(
            of: find.byKey(const Key('coa_overview_breadcrumb')),
            matching: find.text('1000 الأصول')),
        findsOneWidget);

    // الطلبُ: الحسابُ نفسُه، السنةُ الماليّة، ونطاقُ الفروع الأمنيّ.
    expect(repo.ledgerCalls, isNotEmpty);
    final call = repo.ledgerCalls.last;
    expect(call.id, 2);
    expect(call.from, DateTime(2026, 1, 1));
    expect(call.to, DateTime(2026, 12, 31));
    expect(call.allowed, {2},
        reason: '🔴 نطاقُ الفروع سقط — مستخدمٌ محصورٌ يرى حركاتِ فروعٍ أخرى');

    // الرصيد: الحركاتُ وحدَها (الافتتاحيُّ ليس حركةَ السنة).
    expect(_tileValue(tester, 'coa_balance_debit'), formatAccountAmount(1500));
    expect(_tileValue(tester, 'coa_balance_credit'), formatAccountAmount(250));
    expect(_tileValue(tester, 'coa_balance_net'), formatAccountAmount(1250));
    expect(_tileValue(tester, 'coa_child_count'), '0');

    // آخرُ الحركات — الأحدثُ أوّلاً.
    final firstRow = tester.getTopLeft(find.text('JE-0003')).dy;
    final lastRow = tester.getTopLeft(find.text('JE-0001')).dy;
    expect(firstRow, lessThan(lastRow));
    expect(find.text('Cash sale'), findsOneWidget);
    expect(find.text('2026/03/15'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('عددُ الأبناء ونقرُ الأب في المسار يختاره', (tester) async {
    await _pump(tester);
    await _select(tester, 'الأصول');
    expect(_tileValue(tester, 'coa_child_count'), '2');
    await _select(tester, 'أوراق القبض');
    await tester.tap(find.text('1000 الأصول'));
    await _settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('coa_overview_code'))).data,
        '1000');
    await _teardown(tester);
  });

  testWidgets('«عرض في دفتر الأستاذ» يفتح الدفترَ مرشَّحاً على الحساب',
      (tester) async {
    await _pump(tester);
    await _select(tester, 'إيرادات المبيعات');
    await tester.tap(find.byKey(const Key('coa_open_ledger')));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final gl = tester.widget<GeneralLedgerPicPosScreen>(
        find.byType(GeneralLedgerPicPosScreen));
    expect(gl.initialAccountId, 4);
    expect(gl.initialFrom, DateTime(2026, 1, 1));
    expect(gl.initialTo, DateTime(2026, 12, 31));
    expect(gl.initialAccountLabel, contains('4100'));
    await _teardown(tester);
  });

  group('التحريرُ داخلَ اللوح', () {
    testWidgets('يحفظ عبر updateAccount ويعود إلى العرض', (tester) async {
      final repo = await _pump(tester);
      await _select(tester, 'إيرادات المبيعات');
      await tester.tap(find.byKey(const Key('coa_overview_edit')));
      await _settle(tester);

      // النموذجُ في مكان اللوح — لا حوار.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('تفاصيل الحساب'), findsOneWidget);

      final fields = find.descendant(
          of: find.byKey(const ValueKey('coa_panel_4')),
          matching: find.byType(TextField));
      await tester.enterText(fields.at(1), 'Sales revenue');
      await tester.tap(find.text('تعديل الحساب'));
      await _settle(tester);

      expect(repo.updates, hasLength(1));
      expect(repo.updates.single['id'], 4);
      expect(repo.updates.single['name'], 'Sales revenue');
      expect(repo.updates.single['code'], '4100');
      expect(_overview, findsOneWidget, reason: 'بعد الحفظ يعود اللوحُ إلى العرض');
      await _teardown(tester);
    });

    testWidgets('خطأُ التحقّق يظهر ولا يكتب', (tester) async {
      final repo = await _pump(tester);
      await _select(tester, 'إيرادات المبيعات');
      await tester.tap(find.byKey(const Key('coa_overview_edit')));
      await _settle(tester);

      final fields = find.descendant(
          of: find.byKey(const ValueKey('coa_panel_4')),
          matching: find.byType(TextField));
      await tester.enterText(fields.at(1), '   ');
      await tester.tap(find.text('تعديل الحساب'));
      await _settle(tester);

      expect(find.text('الرمزُ والاسمُ مطلوبان'), findsOneWidget);
      expect(repo.updates, isEmpty);
      expect(find.text('تفاصيل الحساب'), findsOneWidget,
          reason: 'النموذجُ يبقى مفتوحاً على ما كُتب');
      await _teardown(tester);
    });

    testWidgets('🔴 حسابُ النظام: رمزُه معطَّلٌ ولا يُمرَّر', (tester) async {
      final repo = await _pump(tester);
      await _select(tester, 'الأصول');
      await _select(tester, 'الصندوق الرئيسي');
      await tester.tap(find.byKey(const Key('coa_overview_edit')));
      await _settle(tester);

      final fields = find.descendant(
          of: find.byKey(const ValueKey('coa_panel_2')),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(fields.first).enabled, isFalse);
      await tester.tap(find.text('تعديل الحساب'));
      await _settle(tester);
      expect(repo.updates.single['code'], isNull,
          reason: 'رمزُ حساب النظام كُتب — والمحرّكُ يقرؤه بالرمز');
      await _teardown(tester);
    });

    testWidgets('«إضافة حساب فرعي» من اللوح يفتح نموذجَ الإنشاء تحت الحساب',
        (tester) async {
      await _pump(tester);
      await _select(tester, 'الأصول');
      await tester.tap(find.byKey(const Key('coa_overview_add_child')));
      await _settle(tester);
      expect(find.text('حساب جديد'), findsOneWidget);
      // الرمزُ يبدأ برمز الأب.
      final code = tester.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey('coa_panel_new_1')),
          matching: find.byType(TextField)).first);
      expect(code.controller!.text, '1000');
      // «رجوع» يعود إلى الحساب الذي كان مختاراً.
      await tester.tap(find.text('رجوع'));
      await _settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('coa_overview_code'))).data,
          '1000');
      await _teardown(tester);
    });
  });

  group('البحث', () {
    testWidgets('بالرمز: يرشّح الشجرةَ ويوسّع إلى المطابق ويختاره',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('coa_search')), '1102');
      await _settle(tester);

      expect(tester.widget<Text>(find.byKey(const Key('coa_overview_code'))).data,
          '1102');
      final tree = find.byKey(const Key('coa_tree'));
      // المطابقُ ظاهرٌ تحت أبيه، والأبُ ظاهرٌ سياقاً، وغيرُ المطابق مُرشَّح.
      expect(find.descendant(of: tree, matching: find.text('أوراق القبض')),
          findsOneWidget);
      expect(find.descendant(of: tree, matching: find.text('الأصول')),
          findsOneWidget);
      expect(find.descendant(of: tree, matching: find.text('إيرادات المبيعات')),
          findsNothing);
      expect(find.descendant(of: tree, matching: find.text('الصندوق الرئيسي')),
          findsNothing);
      await _teardown(tester);
    });

    testWidgets('بالاسم الإنجليزيّ (trData) في الواجهة الإنجليزيّة',
        (tester) async {
      await _pump(tester, english: true);
      await tester.enterText(find.byKey(const Key('coa_search')), 'notes rec');
      await _settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('coa_overview_code'))).data,
          '1102');
      expect(tester.widget<Text>(find.byKey(const Key('coa_overview_name'))).data,
          trData('أوراق القبض'));
      await _teardown(tester);
    });
  });

  group('RTL/LTR × فاتح/داكن على ١٣٦٦×٧٦٨', () {
    for (final english in [false, true]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            '${english ? 'LTR/en' : 'RTL/ar'} · ${brightness.name} — بلا فيض',
            (tester) async {
          final overflows = <String>[];
          await _pump(tester,
              english: english, brightness: brightness, overflows: overflows);
          expect(overflows, isEmpty, reason: overflows.join('\n'));

          // الحالةُ الفارغة ثمّ حسابٌ مختارٌ بحركاته — كلاهما بلا فيض.
          final previous = FlutterError.onError;
          FlutterError.onError = (d) {
            final s = d.toString();
            if (s.contains('overflowed')) {
              overflows.add(s.split('\n').first);
            } else {
              previous?.call(d);
            }
          };
          try {
            await _select(tester, 'الأصول');
            await _select(tester, 'الصندوق الرئيسي');
          } finally {
            FlutterError.onError = previous;
          }
          expect(overflows, isEmpty, reason: overflows.join('\n'));
          expect(tester.takeException(), isNull);

          final dir = Directionality.of(tester.element(_overview));
          expect(dir, english ? TextDirection.ltr : TextDirection.rtl);

          final panelTexts = [
            for (final t in tester.widgetList<Text>(
                find.descendant(of: _overview, matching: find.byType(Text))))
              t.data ?? t.textSpan?.toPlainText() ?? '',
          ];
          expect(panelTexts, isNotEmpty);
          if (english) {
            final arabic = panelTexts.where((s) => s.contains(_arabic)).toList();
            expect(arabic, isEmpty, reason: 'نصٌّ عربيٌّ في اللوح الإنجليزيّ: $arabic');
          }

          if (brightness == Brightness.dark) {
            // كلُّ نصٍّ في اللوح مقروءٌ على بطاقة الوضع الداكن.
            final card = PicPosTheme.darkTheme.cardColor;
            final bad = <String>[];
            // ⚠️ يُستثنى نصُّ الزرّ المصمت (أرضيّتُه لونُ الزرّ لا البطاقة)
            //    وحروفُ الأيقونات.
            final onFill = {
              ...tester.renderObjectList<RenderParagraph>(find.descendant(
                  of: find.byType(FilledButton), matching: find.byType(RichText))),
              ...tester.renderObjectList<RenderParagraph>(find.descendant(
                  of: find.byType(Icon), matching: find.byType(RichText))),
            };
            for (final p in tester
                .renderObjectList<RenderParagraph>(find.descendant(
                    of: _overview, matching: find.byType(RichText)))
                .where((p) => !onFill.contains(p))) {
              final color = p.text.style?.color;
              if (color == null || color.a < 0.5) continue;
              final ratio = _contrast(color, card);
              if (ratio < 3.0) {
                bad.add('${p.text.toPlainText()} → ${ratio.toStringAsFixed(2)}');
              }
            }
            expect(bad, isEmpty, reason: 'تباينٌ ضعيفٌ في الداكن: $bad');
          }
          await _teardown(tester);
        });
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

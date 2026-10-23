// أدواتٌ مشتركةٌ لاختبارات ودجتات «المؤشرات والنسب المالية» العرضيّة.
// المدخلات تُبنى يدويّاً (بلا قاعدة بيانات ولا مزوّدات).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/domain/analytics/financial_snapshot.dart';
import 'package:picpos_erp/domain/analytics/ratio_engine.dart';

/// نسبةٌ مبنيّةٌ يدويّاً.
Ratio mkRatio({
  String key = 'current_ratio',
  RatioGroup group = RatioGroup.liquidity,
  Bilingual label = const Bilingual('نسبة التداول', 'Current ratio'),
  String formula = 'currentAssets / currentLiabilities',
  double? value = 1.8,
  RatioUnit unit = RatioUnit.times,
  RatioStatus status = RatioStatus.good,
  Bilingual interpretation =
      const Bilingual('السيولة كافية', 'Liquidity is sufficient'),
}) =>
    Ratio(
      key: key,
      group: group,
      label: label,
      formula: formula,
      value: value,
      unit: unit,
      direction: GoodDirection.higherBetter,
      status: status,
      interpretation: interpretation,
    );

/// يضبط لغة الواجهة (العربيّة أو الإنجليزيّة بكتالوج en.json الحقيقيّ).
void setUiLocale({required bool english}) {
  if (english) {
    I18nCatalog.setCatalog(Map<String, String>.from(
        jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
    I18nCatalog.setLocale(const Locale('en'));
  } else {
    I18nCatalog.setLocale(const Locale('ar', 'EG'));
  }
  addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
}

Future<void> pumpFin(
  WidgetTester tester,
  Widget child, {
  bool english = false,
  bool dark = false,
  double width = 900,
}) async {
  setUiLocale(english: english);
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: english ? const Locale('en') : const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

/// لونُ نصٍّ عُثر عليه بمفتاحه (للتحقق من الأخضر/الأحمر).
Color? textColorByKey(WidgetTester tester, Key key) {
  final finder = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Text),
  );
  if (finder.evaluate().isNotEmpty) {
    return tester.widget<Text>(finder.first).style?.color;
  }
  return tester.widget<Text>(find.byKey(key)).style?.color;
}

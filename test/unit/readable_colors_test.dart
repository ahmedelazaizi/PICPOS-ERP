import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/readable_colors.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Future<BuildContext> _ctx(WidgetTester t, Brightness b) async {
  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: b),
    home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }),
  ));
  return ctx;
}

void main() {
  testWidgets('فاتح: لون مقروء يبقى كما هو، والعلامة primaryDark', (t) async {
    final c = await _ctx(t, Brightness.light);
    const ink = Color(0xFF0A0A0A);
    expect(readableOn(c, ink), ink);
    expect(readableBrand(c), AppColors.primaryDark);
  });

  testWidgets('داكن: الأحمر والعلامة والتسمية ≥ 4.5 على كرت الداكن', (t) async {
    final c = await _ctx(t, Brightness.dark);
    const card = AppColors.cardDark;
    expect(_ratio(readableOn(c, AppColors.error), card), greaterThanOrEqualTo(4.5));
    expect(_ratio(readableBrand(c), card), greaterThanOrEqualTo(4.5));
    expect(_ratio(readableLabel(c), card), greaterThanOrEqualTo(4.5));
  });
}

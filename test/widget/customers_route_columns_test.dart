// المرحلة و — بطاقةُ العميل تعرض المسارَ والمنطقةَ والمندوبَ **المشتقّ**،
// و«إسناد إلى مسار» لا يظهر إلّا بصلاحيّة؛ وحوارُ الطرف «العنوان» وحدَه.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/domain/models/picpos_party_view.dart';
import 'package:picpos_erp/presentation/parties_picpos/screens/parties_picpos_screen.dart';

const _onRoute = PicPosPartyCard(
  id: 7,
  name: 'بقالة النور',
  balance: 120,
  creditLimit: 0,
  isCustomer: true,
  routeName: 'مسار السبت',
  areaName: 'المنطقة الشرقية',
  repName: 'مندوب الشرق',
);

const _offRoute = PicPosPartyCard(
  id: 8,
  name: 'عميل نقدي',
  balance: 0,
  creditLimit: 0,
  isCustomer: true,
);

void main() {
  Future<void> show(WidgetTester tester, Widget child,
      {ThemeData? theme, TextDirection dir = TextDirection.rtl}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Scaffold(
          body: Directionality(textDirection: dir, child: child)),
    ));
    await tester.pumpAndSettle();
  }

  PartyCardActions actions(List<String> log, {bool canAssign = true}) =>
      PartyCardActions(
        onStatement: (_) {},
        onEdit: (_) {},
        onVoucher: (_) {},
        onDelete: (_) {},
        onWhatsApp: (_) {},
        onAssignRoute: canAssign ? (c) => log.add('assign:${c.id}') : null,
      );

  for (final dark in [false, true]) {
    for (final dir in TextDirection.values) {
      testWidgets('الشبكةُ تعرض المسار والمنطقة والمندوب — '
          '${dark ? 'dark' : 'light'}/${dir.name}', (tester) async {
        final log = <String>[];
        await show(
          tester,
          PartiesCardGrid(
            parties: const [_onRoute, _offRoute],
            actions: actions(log),
            showRoute: true,
          ),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          dir: dir,
        );
        expect(find.text('مسار السبت'), findsOneWidget);
        expect(find.text('المنطقة الشرقية'), findsOneWidget);
        expect(find.text('مندوب الشرق'), findsOneWidget);
        expect(find.text('ليس على مسار'), findsOneWidget);
        await tester.tap(find.byKey(const Key('party-assign-route-7')));
        expect(log, ['assign:7']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('بلا صلاحيّةٍ لا زرَّ إسناد', (tester) async {
    await show(
      tester,
      PartiesCardGrid(
        parties: const [_onRoute],
        actions: actions([], canAssign: false),
        showRoute: true,
      ),
    );
    expect(find.text('مسار السبت'), findsOneWidget);
    expect(find.byKey(const Key('party-assign-route-7')), findsNothing);
  });

  testWidgets('قائمةُ الموردين بلا صفّ المسار', (tester) async {
    await show(
      tester,
      PartiesCardGrid(parties: const [_onRoute], actions: actions([])),
    );
    expect(find.byKey(const Key('party-route-7')), findsNothing);
  });

  test('حوارُ الطرف: «العنوان» وحدَه لا «العنوان / المنطقة»', () {
    final src = File(
            'lib/presentation/parties_picpos/dialogs/add_party_dialog_picpos.dart')
        .readAsStringSync();
    expect(src.contains("tr('العنوان / المنطقة')"), isFalse);
    expect(src.contains("labelText: tr('العنوان')"), isTrue);
  });
}

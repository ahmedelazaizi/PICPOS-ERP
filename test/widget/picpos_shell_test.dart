import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_page_header.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_content_card.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_screen_scaffold.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: PicPosTheme.lightTheme,
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      );

  group('PicPosPageHeader', () {
    testWidgets('يعرض العنوان والوصف والأزرار', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosPageHeader(
          title: 'الأصناف',
          subtitle: 'إدارة المنتجات والتسعير',
          icon: PhosphorIconsBold.package,
          actions: [Text('زر')],
        ),
      )));
      expect(find.text('الأصناف'), findsOneWidget);
      expect(find.text('إدارة المنتجات والتسعير'), findsOneWidget);
      expect(find.text('زر'), findsOneWidget);
    });

    testWidgets('يرسم شريحة لونية سفلية بلون العلامة', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosPageHeader(title: 'ت'),
      )));
      // الحاوية الجذر فيها Border سفلي بلون AppColors.primary.
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PicPosPageHeader),
          matching: find.byType(Container),
        ).first,
      );
      final deco = container.decoration as BoxDecoration;
      expect(deco.border!.bottom.color, AppColors.primary);
      expect(deco.border!.bottom.width, 2.5);
    });
  });

  group('PicPosContentCard', () {
    testWidgets('مسطّح (elevation صفر) بحد شعري', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosContentCard(child: Text('محتوى')),
      )));
      expect(find.text('محتوى'), findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PicPosContentCard),
          matching: find.byType(Container),
        ).first,
      );
      final deco = container.decoration as BoxDecoration;
      expect(deco.border, isA<Border>());
      expect(deco.boxShadow, anyOf(isNull, isEmpty));
    });
  });

  group('PicPosScreenScaffold', () {
    testWidgets('يركّب الهيدر والجسم في RTL', (tester) async {
      await tester.pumpWidget(wrap(const PicPosScreenScaffold(
        title: 'المخزون',
        body: Text('الجسم'),
      )));
      expect(find.text('المخزون'), findsOneWidget);
      expect(find.text('الجسم'), findsOneWidget);
      final dir = tester.widget<Directionality>(
        find.descendant(
          of: find.byType(PicPosScreenScaffold),
          matching: find.byType(Directionality),
        ).first,
      );
      expect(dir.textDirection, TextDirection.rtl);
    });
  });
}

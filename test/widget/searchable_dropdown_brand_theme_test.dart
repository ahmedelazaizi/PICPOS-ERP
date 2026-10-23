import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/presentation/widgets/searchable_dropdown.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  testWidgets(
    'UralCash dropdown retains its theme colors with readable dark placeholders',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<void> verifyTheme({
        required ThemeData theme,
        required Color muted,
        required Color secondary,
        required Color primary,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(theme.brightness),
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Theme(
              data: theme,
              child: Scaffold(
                body: Center(
                  child: SearchableDropdown<String>(
                    items: const ['North'],
                    label: 'الفرع',
                    hint: 'اختر فرعاً',
                    searchHint: 'بحث الفرع',
                    labelBuilder: (item) => item,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

        final surface = theme.cardColor;
        final field = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('اختر فرعاً'),
                matching: find.byType(Container),
              )
              .first,
        );
        final fieldDecoration = field.decoration! as BoxDecoration;
        final placeholder = tester.widget<Text>(find.text('اختر فرعاً'));
        final label = tester.widget<Text>(find.text('الفرع'));

        expect(placeholder.style!.color, muted);
        expect(label.style!.color, secondary);
        expect(fieldDecoration.color, surface);
        expect(
          (fieldDecoration.border! as Border).top.color,
          theme.inputDecorationTheme.enabledBorder!.borderSide.color,
        );
        expect(_contrast(muted, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(secondary, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(primary, surface), greaterThanOrEqualTo(4.5));

        await tester.tap(find.text('اختر فرعاً'));
        await tester.pumpAndSettle();
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.decoration!.hintStyle!.color, muted);
        final option = tester.widget<Text>(find.text('North'));
        expect(option.style!.color, primary);
        expect(_contrast(primary, surface), greaterThanOrEqualTo(4.5));
      }

      await verifyTheme(
        theme: AppTheme.lightTheme,
        muted: AppColors.textMuted,
        secondary: AppColors.textSecondary,
        primary: AppColors.textPrimary,
      );
      await verifyTheme(
        theme: AppTheme.darkTheme,
        muted: Colors.white70,
        secondary: Colors.white70,
        primary: Colors.white,
      );
    },
    skip: !Brand.isUralCash,
  );
}

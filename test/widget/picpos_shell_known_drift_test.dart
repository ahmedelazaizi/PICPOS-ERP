// «الانحرافاتُ المعروفة» في DESIGN.md — ما أُصلح منها وكيف يبقى مُصلَحاً.
//
// ‏أ) حدٌّ واحدٌ وتعبئةٌ واحدة: `picposHairline`/`picposField` في الفاتح هما
//    حدُّ الثيم (`dividerColor`) وتعبئةُ حقوله — لا `AppColors.border`/
//    `surface` المتقاربان. والداكنُ لم يتغيّر.
// ‏ب) الودجتاتُ الخمسُ ذاتُ الرماديّ الثابت تقرأ في الداكن (تباين ≥ ٤٫٥ على
//    البطاقة). `AppColors.textMuted` الثابتُ يعطي ~٣٫٦ و`textSecondary` ~١٫٦.
// ‏ج) تسمياتُ الأزرار الافتراضيّة تمرّ بـ`tr()`.
// ‏د) سهمُ الرجوع في الترويسة وشريط الأفعال يشير إلى بداية السطر في الاتجاهين.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_dialog.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_empty_state.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_form_action_bar.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_option_picker.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_page_header.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_section_header.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_stat_tile.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_totals_bar.dart';

Widget _app(Widget home, {bool english = false, bool dark = false}) =>
    MaterialApp(
      theme: dark ? PicPosTheme.darkTheme : PicPosTheme.lightTheme,
      locale: english ? const Locale('en') : const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Directionality(
        textDirection: english ? TextDirection.ltr : TextDirection.rtl,
        child: home,
      ),
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUpAll(() {
    final raw = File('assets/i18n/en.json').readAsStringSync();
    I18nCatalog.setCatalog({
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        if (e.value is String) e.key: e.value as String,
    });
  });
  tearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));

  group('أ) حدٌّ واحدٌ وتعبئةٌ واحدة', () {
    testWidgets('الفاتحُ = رموزُ الثيم، والداكنُ لم يتغيّر', (tester) async {
      late BuildContext light;
      late BuildContext dark;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        light = c;
        return const SizedBox();
      })));
      final lightTheme = Theme.of(light);
      expect(light.picposHairline, lightTheme.dividerColor);
      expect(light.picposHairline, lightTheme.dividerTheme.color);
      expect(light.picposField, lightTheme.inputDecorationTheme.fillColor);
      expect(picposDialogField(light), light.picposField,
          reason: 'تعبئةُ الحوار والمُلحق صارتا واحدة');

      await tester.pumpWidget(_app(dark: true, Builder(builder: (c) {
        dark = c;
        return const SizedBox();
      })));
      // `AnimatedTheme` ينتقل في ٢٠٠ مللي ثانية.
      await tester.pumpAndSettle();
      expect(dark.picposHairline, AppColors.borderDark);
      // وحدُّ الثيم الداكن واحدٌ أيضاً (لا `outline` المحسوب).
      expect(Theme.of(dark).dividerColor, Theme.of(dark).dividerTheme.color);
      expect(dark.picposField, const Color(0xFF18243A));
    });
  });

  group('ب) الرماديُّ الثابتُ صار تابعاً للوضع', () {
    testWidgets('الودجتاتُ الخمسُ مقروءةٌ على بطاقة الداكن (≥ ٤٫٥)',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(
        dark: true,
        Builder(
          builder: (c) => Scaffold(
            backgroundColor: c.picposCard,
            body: ListView(
              children: const [
                SizedBox(
                  height: 220,
                  child: PicPosEmptyState(
                    icon: PhosphorIconsBold.tray,
                    title: 'لا بيانات',
                    hint: 'وسّع المدى',
                  ),
                ),
                PicPosSectionHeader(title: 'قسم', subtitle: 'سطرٌ خافت'),
                PicPosStatTile(label: 'المبيعات', value: '10', caption: 'أمس'),
                PicPosTotalsBar(
                    items: [PicPosTotal(label: 'الإجمالي', value: '5')]),
                PicPosFormActionBar(hint: 'يتطلب الترحيل تساوي المدين والدائن'),
              ],
            ),
          ),
        ),
      ));

      final card = PicPosTheme.darkTheme.cardColor;
      final checked = <String>[];
      final bad = <String>[];
      for (final text in [
        'لا بيانات',
        'وسّع المدى',
        'سطرٌ خافت',
        'المبيعات',
        'أمس',
        'الإجمالي',
        'يتطلب الترحيل تساوي المدين والدائن',
      ]) {
        final p = tester.renderObject<RenderParagraph>(find.text(text));
        final color = p.text.style!.color!;
        final ratio = _contrast(color, card);
        checked.add(text);
        if (ratio < 4.5) bad.add('$text → ${ratio.toStringAsFixed(2)}');
      }
      expect(checked, hasLength(7));
      expect(bad, isEmpty, reason: 'تباينٌ ضعيفٌ في الداكن: $bad');
    });
  });

  group('ج) التسمياتُ الافتراضيّة تمرّ بـ tr()', () {
    testWidgets('شريطُ الأفعال: «Back» بالإنجليزيّة', (tester) async {
      I18nCatalog.setLocale(const Locale('en'));
      await tester.pumpWidget(_app(english: true,
          Scaffold(body: PicPosFormActionBar(onBack: () {}))));
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('رجوع'), findsNothing);
    });

    testWidgets('الحوار وحوارُ التأكيد ومنتقي الخيار', (tester) async {
      I18nCatalog.setLocale(const Locale('en'));
      late BuildContext ctx;
      await tester.pumpWidget(_app(english: true, Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      )));

      showPicPosConfirm(ctx,
          icon: PhosphorIconsBold.check, title: 'T', message: 'M');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));

      showPicPosOptionPicker<int>(
        context: ctx,
        title: 'T',
        options: const [
          PicPosOption(value: 1, label: 'One'),
          PicPosOption(value: 2, label: 'Two'),
        ],
        selected: 1,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('تطبيق'), findsNothing);
    });

    testWidgets('والعربيّةُ لم تتغيّر', (tester) async {
      await tester.pumpWidget(
          _app(Scaffold(body: PicPosFormActionBar(onBack: () {}))));
      expect(find.text('رجوع'), findsOneWidget);
    });
  });

  group('د) سهمُ الرجوع يشير إلى بداية السطر', () {
    // ‏`arrow_back`/`chevron_left` تحمل `matchTextDirection`: تُرسَم معكوسةً
    // (‏`Transform`) في RTL فتشير يميناً، وكما هي في LTR فتشير يساراً.
    bool mirrored(WidgetTester tester, IconData icon) => find
        .descendant(of: find.byIcon(icon), matching: find.byType(Transform))
        .evaluate()
        .isNotEmpty;

    Future<void> pushHeader(WidgetTester tester, {required bool english}) async {
      // شجرةٌ جديدة: وإلّا احتفظ `Navigator` بالمسار المدفوع من قبل.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(english: english, Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
                builder: (_) => Directionality(
                  textDirection:
                      english ? TextDirection.ltr : TextDirection.rtl,
                  child: const Scaffold(body: PicPosPageHeader(title: 'T')),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('الترويسة: → في RTL و← في LTR', (tester) async {
      await pushHeader(tester, english: false);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
      expect(mirrored(tester, Icons.arrow_back), isTrue);

      await pushHeader(tester, english: true);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(mirrored(tester, Icons.arrow_back), isFalse);
    });

    testWidgets('شريطُ الأفعال: › في RTL و‹ في LTR', (tester) async {
      await tester.pumpWidget(
          _app(Scaffold(body: PicPosFormActionBar(onBack: () {}))));
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(mirrored(tester, Icons.chevron_left), isTrue);

      await tester.pumpWidget(_app(english: true,
          Scaffold(body: PicPosFormActionBar(onBack: () {}))));
      expect(mirrored(tester, Icons.chevron_left), isFalse);
    });
  });
}

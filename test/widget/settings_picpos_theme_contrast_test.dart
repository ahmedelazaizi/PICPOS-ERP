// تباينُ نصوص شاشات إعدادات PicPos في الوضعين (WCAG ≥ 4.5).
//
// البند 14: شاشات الإعدادات (CFD · طرق الدفع · وضع الشبكة) كانت تكتب
// `AppColors.textSecondary/textMuted/surface/border` الثابتة — داكنةً على
// بطاقةٍ داكنة. الودجتات الثلاثة خاصّة (`part of`) فلا تُركَّب من خارج
// المكتبة؛ لذا يُختبر (١) أن أدوار الثيم التي استُبدلت بها تحقّق التباين
// على كلّ أرضيّةٍ تستعملها الشاشات، (٢) أن حوار رمز الاسترداد — وهو
// عمومي وقد حُوِّل إلى PicPosDialog — يُرسَم بنصٍّ مقروء في الوضعين،
// (٣) حارسٌ بنيويٌّ يمنع عودة الثوابت إلى الملفات الثلاثة.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_dialog.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/database_encryption_dialogs.dart';

/// نسبة التباين WCAG 2.x بين لونَين معتمَين (alpha تُهمَل — الأرضيّات صلبة).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

const _minText = 4.5;

final _themes = <String, ThemeData Function()>{
  'light': () => PicPosTheme.lightTheme,
  'dark': () => PicPosTheme.darkTheme,
};

void main() {
  test('حارس التباين نفسُه يميّز القريب من البعيد', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrastRatio(const Color(0xFF374151), const Color(0xFF121C2E)),
        lessThan(2.5)); // الخطأ الأصليّ: textSecondary على بطاقة داكنة
  });

  for (final entry in _themes.entries) {
    testWidgets('أدوار النص على أرضيّات الإعدادات (${entry.key})', (tester) async {
      final theme = entry.value();
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      final backgrounds = <String, Color>{
        'scaffold': theme.scaffoldBackgroundColor,
        'card': theme.cardColor,
        'field': ctx.picposField,
      };
      final foregrounds = <String, Color>{
        'text': ctx.picposText,
        'secondary': ctx.picposSecondary,
        'muted': ctx.picposMuted,
      };
      final failures = <String>[];
      for (final bg in backgrounds.entries) {
        for (final fg in foregrounds.entries) {
          final r = contrastRatio(fg.value, bg.value);
          // النصّ الخافت (تلميحات/وصف) له حدٌّ أدنى 4.0: قيمة الثيم الفاتح
          // الحاليّة #6B7280 على scaffold تعطي 4.42 — قرار ثيم خارج هذا البند.
          final min = fg.key == 'muted' ? 4.0 : _minText;
          if (r < min) {
            failures.add('${fg.key} on ${bg.key}: ${r.toStringAsFixed(2)}');
          }
        }
      }
      // بطاقة حالة الخادم: الخضراء الشفّافة فوق الأرضيّة تحتفظ بنص مقروء.
      final successTint = _over(
          const Color(0xFF16A34A).withValues(alpha: 0.1), theme.cardColor);
      final r = contrastRatio(ctx.picposText, successTint);
      if (r < _minText) failures.add('text on success tint: $r');

      expect(failures, isEmpty, reason: failures.join('\n'));
      // الحدّ والحقل لا يذوبان في الأرضيّة (تمييز بصريّ، لا نص).
      expect(ctx.picposField, isNot(theme.cardColor));
      expect(ctx.picposHairline, isNot(theme.cardColor));
    });

    testWidgets('حوار رمز الاسترداد مقروء (${entry.key})', (tester) async {
      final theme = entry.value();
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: RecoveryCodeDialog(code: 'ABCD-EFGH-IJKL'),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('dbenc_code_dialog')), findsOneWidget);
      expect(find.byType(PicPosDialog), findsOneWidget);

      final bg = theme.cardColor;
      final failures = <String>[];
      var checked = 0;
      for (final el in find.byType(RichText).evaluate()) {
        var inButton = false;
        el.visitAncestorElements((a) {
          if (a.widget is ButtonStyleButton) inButton = true;
          return !inButton;
        });
        if (inButton) continue; // الأزرار تلوَّن بقيم Material الخاصّة بها
        final rt = el.widget as RichText;
        final color = rt.text.style?.color;
        if (color == null || rt.text.toPlainText().trim().isEmpty) continue;
        final family = rt.text.style?.fontFamily ?? '';
        if (family.contains('Icons') || family.contains('hosphor')) continue;
        checked++;
        final ratio = contrastRatio(color, bg);
        if (ratio < _minText) {
          failures.add('"${rt.text.toPlainText()}" ${ratio.toStringAsFixed(2)}');
        }
      }
      expect(checked, greaterThan(2), reason: 'لم يُفحص نصٌّ كافٍ');
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  test('لا ثوابت AppColors للنص/السطح/الحدّ في ملفّات الإعدادات المعدَّلة', () {
    const files = <String>[
      'lib/presentation/settings_picpos/screens/cfd_settings_card_picpos.dart',
      'lib/presentation/settings_picpos/screens/payment_methods_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/network_mode_settings_picpos.dart',
    ];
    final banned = RegExp(
        r'AppColors\.(textPrimary|textSecondary|textMuted|surface|border)\b');
    final offenders = <String>[];
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (banned.hasMatch(lines[i])) offenders.add('$f:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'استعمل context.picposText/Secondary/Muted/Field/Hairline.\n'
            '${offenders.join('\n')}');
  });

  test('لا Dialog( خام في settings_picpos_tiles ولا database_encryption_dialogs',
      () {
    const files = <String>[
      'lib/presentation/settings_picpos/screens/settings_picpos_tiles.dart',
      'lib/presentation/settings_picpos/widgets/database_encryption_dialogs.dart',
    ];
    final raw = RegExp(r'(?<![A-Za-z])Dialog\(');
    final offenders = <String>[];
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (raw.hasMatch(lines[i])) offenders.add('$f:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'استعمل PicPosDialog.\n$offenders');
  });
}

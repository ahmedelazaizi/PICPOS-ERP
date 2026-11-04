// أداةُ تدقيق التباين (WCAG) لاختبارات الودجت — قابلةٌ لإعادة الاستعمال.
//
// الفكرة: نركّب ودجتاً داخل MaterialApp بثيم التطبيق الحقيقي (PicPosTheme)
// فاتحاً ثم داكناً، ثم نمرُّ على شجرة العناصر؛ لكلِّ نصٍّ/أيقونةٍ ظاهرة نحسب
// لونَ الخلفيّة الفعليّ من أقرب الأسلاف الرسّامة (DecoratedBox/ColoredBox/
// Material/Card/Scaffold) بدمج الشفافيّة طبقةً فوق طبقة، ثم تباينَ WCAG.
//
// الحدود: ٣:١ للأيقونات والنصّ الكبير (≥٢٤px أو ≥١٨٫٦٦px بولد)، و٤٫٥:١
// لغيره. الأداةُ تقريبيّةٌ عمداً — لا ترى الصور ولا CustomPaint ولا `Ink`
// ولا ظلالَ Material؛ فما لا تعرف خلفيّتَه تعود فيه إلى لون الـcanvas.
// التدرّجُ يُقاس على **أسوأ** لونٍ فيه.
//
// الاستعمال:
//   await tester.pumpWidget(auditApp(brightness: Brightness.dark, home: w));
//   await tester.pump();
//   expect(auditContrast(tester), isEmpty, reason: describeViolations(...));
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';

/// مخالفةُ تباينٍ واحدة.
class ContrastViolation {
  /// نصُّ العنصر، أو `icon U+XXXX` للأيقونات.
  final String label;
  final bool isIcon;
  final Color foreground;
  final Color background;
  final double ratio;
  final double required;

  /// مسارُ الودجت من الجذر (آخرُ ١٢ مستوى).
  final String path;

  const ContrastViolation({
    required this.label,
    required this.isIcon,
    required this.foreground,
    required this.background,
    required this.ratio,
    required this.required,
    required this.path,
  });

  @override
  String toString() =>
      '${isIcon ? "ICON" : "TEXT"} "$label" ${ratio.toStringAsFixed(2)}:1 '
      '(< ${required.toStringAsFixed(1)}) fg=${_hex(foreground)} '
      'bg=${_hex(background)}  @ $path';
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// MaterialApp بثيم التطبيق الحقيقي، داخل ProviderScope.
Widget auditApp({
  required Brightness brightness,
  required Widget home,
  List<Override> overrides = const [],
  TextDirection direction = TextDirection.rtl,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PicPosTheme.lightTheme,
      darkTheme: PicPosTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: home,
    ),
  );
}

/// نسبةُ تباين WCAG بين لونَين معتمَين.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// `top` فوق `bottom` (معتَم).
Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

/// طبقةُ خلفيّةٍ رسّامة: لونٌ واحدٌ أو عدّةُ ألوان (تدرّج).
List<Color>? _layerOf(Widget w, ThemeData theme) {
  if (w is DecoratedBox) {
    final d = w.decoration;
    if (d is BoxDecoration) {
      if (d.gradient is LinearGradient) {
        return (d.gradient as LinearGradient).colors;
      }
      if (d.gradient is RadialGradient) {
        return (d.gradient as RadialGradient).colors;
      }
      if (d.color != null) return [d.color!];
    }
    return null;
  }
  if (w is ColoredBox) return [w.color];
  if (w is Material) {
    if (w.type == MaterialType.transparency) return null;
    if (w.color != null) return [w.color!];
    return [
      switch (w.type) {
        MaterialType.card => theme.cardColor,
        _ => theme.canvasColor,
      }
    ];
  }
  return null;
}

/// الألوانُ المحتمَلة للخلفيّة خلف [element] (أكثر من لونٍ عند التدرّج).
List<Color> _backgroundsBehind(Element element, ThemeData theme) {
  final layers = <List<Color>>[]; // الأقربُ أولاً
  var opaque = false;
  element.visitAncestorElements((a) {
    final layer = _layerOf(a.widget, theme);
    if (layer != null) {
      layers.add(layer);
      if (layer.every((c) => c.a >= 0.999)) {
        opaque = true;
        return false;
      }
    }
    return true;
  });
  var candidates = <Color>[opaque ? const Color(0x00000000) : theme.canvasColor];
  for (final layer in layers.reversed) {
    candidates = [
      for (final c in layer)
        for (final b in candidates) _over(c, b),
    ];
  }
  return candidates.toSet().toList();
}

/// حاصلُ ضرب كلِّ `Opacity` فوق العنصر.
double _opacityAbove(Element element) {
  var o = 1.0;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Opacity) o *= w.opacity;
    return true;
  });
  return o;
}

bool _isHidden(Element element) {
  var hidden = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Offstage && w.offstage) hidden = true;
    if (w is Visibility && !w.visible) hidden = true;
    return !hidden;
  });
  if (hidden) return true;
  final ro = element.renderObject;
  if (ro is RenderBox && ro.hasSize && ro.size.isEmpty) return true;
  return false;
}

String _pathOf(Element element) {
  final names = <String>[element.widget.runtimeType.toString()];
  element.visitAncestorElements((a) {
    names.add(a.widget.runtimeType.toString());
    return true;
  });
  final top = names.reversed.toList();
  final tail = top.length > 12 ? top.sublist(top.length - 12) : top;
  return tail.join(' > ');
}

/// يمرُّ على الشجرة الحاليّة ويُرجع المخالفات. [within] يحصر الفحصَ في
/// ودجتٍ بعينه؛ [minNormal]/[minLarge] تُعدَّلان للاختبارات الاستثنائيّة.
List<ContrastViolation> auditContrast(
  WidgetTester tester, {
  Finder? within,
  double minNormal = 4.5,
  double minLarge = 3.0,
}) {
  final root = within == null
      ? tester.binding.rootElement!
      : tester.element(within.first);
  final theme = Theme.of(tester.element(find.byType(Scaffold).first));
  final out = <ContrastViolation>[];

  void visit(Element e) {
    final w = e.widget;
    if (w is RichText) {
      _check(e, w, theme, out, minNormal, minLarge);
    }
    e.visitChildren(visit);
  }

  visit(root);
  return out;
}

void _check(Element e, RichText w, ThemeData theme, List<ContrastViolation> out,
    double minNormal, double minLarge) {
  final text = w.text.toPlainText();
  if (text.trim().isEmpty || _isHidden(e)) return;

  var isIcon = false;
  e.visitAncestorElements((a) {
    if (a.widget is Icon) {
      isIcon = true;
      return false;
    }
    return true;
  });

  final style = w.text.style;
  final base = style?.color;
  if (base == null) return;
  final alpha = _opacityAbove(e);
  final fgRaw = base.withValues(alpha: base.a * alpha);

  final size = style?.fontSize ?? 14;
  final bold = (style?.fontWeight?.value ?? 400) >= 700;
  final large = isIcon || size >= 24 || (bold && size >= 18.66);
  final required = (isIcon || large) ? minLarge : minNormal;

  double worst = double.infinity;
  Color worstBg = const Color(0x00000000);
  Color worstFg = fgRaw;
  for (final bg in _backgroundsBehind(e, theme)) {
    final fg = _over(fgRaw, bg);
    final r = contrastRatio(fg, bg);
    if (r < worst) {
      worst = r;
      worstBg = bg;
      worstFg = fg;
    }
  }
  if (worst < required) {
    out.add(ContrastViolation(
      label: isIcon
          ? 'icon U+${text.runes.first.toRadixString(16).toUpperCase()}'
          : text.trim(),
      isIcon: isIcon,
      foreground: worstFg,
      background: worstBg,
      ratio: worst,
      required: required,
      path: _pathOf(e),
    ));
  }
}

/// نصٌّ مقروءٌ للمخالفات، يصلح `reason:` في `expect`.
String describeViolations(List<ContrastViolation> v) =>
    v.isEmpty ? 'none' : '\n${v.join('\n')}';

// حارسٌ بنيويّ — كلُّ عنصرٍ يعرضه محرِّرُ القوالب يرسمه الرسّام.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// عنصرٌ في لوحة المحرِّر بلا مقابلٍ في الرسّام: يُختار ويُحفظ في القالب ثم
// **يختفي** من المطبوع بلا أن ينطق شيء — لأن الرسّام يسقطه على `default`،
// وعنصرٌ بلا تسميةٍ وبلا قيمةٍ يرجع `SizedBox()`.
//
// مقيسٌ 2026-08-10: عشرون نوعاً كانت كذلك — ستّةَ عشرَ من عائلة `shift_*`
// (‏نوعُ قالبٍ كاملٌ لا يطبعه شيء) و`item_additions` و`item_options`.
// وهو ما رآه المالك: «حاجات مش بتظهر بعد اختيارها وحفظها في القالب».
//
// ⚠️ والوعدُ المكسورُ أسوأُ من الغياب: المستخدمُ يصمّم ويحفظ ويثق، ثم يطبع
// فلا يجد. لا رسالةَ خطأٍ ولا مربّعَ فارغ — لا شيء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _paletteFile =
    'lib/presentation/screens/invoice_designer/invoice_designer_ui.dart';
const _rendererFile = 'lib/services/templated_invoice_service.dart';

/// `_PaletteItem('التسمية', 'elementType', 'content', icon)` — الثالثُ هو
/// المحتوى، وهو ما يقارنه الرسّامُ بعد `resolveType`.
final _palette =
    RegExp(r"_PaletteItem\(\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*'([^']*)'");

/// أنواعٌ **بنيويةٌ** يرسمها الرسّام من `elementType` لا من المحتوى: شكلٌ
/// على الورق لا حقلُ بيانات.
const _structural = <String>{
  'text', 'line', 'rectangle', 'divider', 'spacer',
  'logo', 'image', 'qr_code', 'barcode', 'barcode_image', 'codabar',
  'items_table', 'custom_text',
};

void main() {
  test('كلُّ عنصرٍ في لوحة المحرِّر له مقابلٌ في الرسّام', () {
    final paletteSrc = File(_paletteFile).readAsStringSync();
    final rendererSrc = File(_rendererFile).readAsStringSync();

    final missing = <String>[];
    final seen = <String>{};

    for (final m in _palette.allMatches(paletteSrc)) {
      final elementType = m.group(1)!;
      final content = m.group(2)!;
      final key = content.isNotEmpty ? content : elementType;
      if (!seen.add(key)) continue;
      if (_structural.contains(key) || _structural.contains(elementType)) {
        continue;
      }
      // نفسُ ما يفعله الرسّام: `switch` على النوع المحلول.
      if (!rendererSrc.contains("case '$key'")) missing.add(key);
    }

    expect(
      missing,
      isEmpty,
      reason: 'أنواعٌ تُعرض وتُحفظ ولا تُرسم ⇒ تختفي من المطبوع بلا أن ينطق '
          'شيء. إمّا أن تُنفَّذ في `templated_invoice_service`، وإمّا أن '
          'تُرفع من اللوحة — وعرضُ ما لا يُرسم أسوأُ من غيابه. '
          'الناقص:\n  ${missing.join('\n  ')}',
    );
  });

  test('ضابط: الحارسُ يقرأ لوحةً فيها عناصرُ فعلاً', () {
    // بلا هذا، تغييرُ شكلِ `_PaletteItem` يجعل الحارسَ يمرّ على صفرِ عناصرٍ
    // ويُقرأ خُضرةً بينما اللوحةُ كلُّها بلا رسّام.
    final n = _palette.allMatches(File(_paletteFile).readAsStringSync()).length;
    expect(n, greaterThan(30),
        reason: 'عددُ عناصر اللوحة المرصودة $n — التعبيرُ النمطيُّ لم يعد '
            'يطابق شكلَ `_PaletteItem`');
  });
}

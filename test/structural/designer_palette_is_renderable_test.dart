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

/// مصدرا الرسم — **ملفّان لا ملفّ**.
///
/// كان الحارسُ يقرأ ملفَّ الخدمة وحدَه، وكان ذلك كافياً يومَ كان المبدّلُ
/// كلُّه فيه. ثمّ انتقل حسابُ قيم الحقول إلى `domain/printing/print_values`
/// كي يقرأه مسارا التخطيط معاً — فأبلغ الحارسُ عن سبعة أنواعٍ «لا تُرسم»
/// وهي مُنفَّذةٌ بحرفها، على بُعد ملفٍّ واحد.
///
/// وهذه فئةُ عطبٍ في الحارس نفسِه لا في الكود: **حارسٌ يقرأ ملفاً بعينه
/// يحرس موضعاً لا قدرة**، فيحمرّ عند كلِّ نقلٍ سليم ويُدرَّب القارئُ على
/// تجاهله. فالقائمةُ تتبع القدرةَ أينما سكنت.
const _rendererFiles = <String>[
  'lib/services/templated_invoice_service.dart',
  'lib/domain/printing/print_values.dart',
];

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
    final rendererSrc = _rendererSource();

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
          'شيء. إمّا أن تُنفَّذ في ${_rendererFiles.join(' أو ')}، وإمّا أن '
          'تُرفع من اللوحة — وعرضُ ما لا يُرسم أسوأُ من غيابه. '
          'الناقص:\n  ${missing.join('\n  ')}',
    );
  });

  test('ضابط: توسيعُ المصدر لم يجعل كلَّ شيءٍ يُطابِق', () {
    // ضمُّ ملفٍّ ثانٍ إلى المصدر يزيد فرصةَ المطابقة العرَضيّة. فلو صار
    // الحارسُ يجد **أيَّ** مفتاحٍ لما بقي حارساً — يقرأ خُضرةً وهو أعمى.
    final src = _rendererSource();
    expect(src.contains("case 'لا_وجودَ_لهذا_النوع_قطّ'"), isFalse,
        reason: 'الحارسُ صار يطابق ما لا وجودَ له');
    expect(src.contains("case 'total'"), isTrue,
        reason: 'الحارسُ لا يرى حالةً موجودةً بيقين — المصدرُ لم يُقرأ');
  });

  test('ضابط: كلُّ ملفِّ مصدرٍ موجودٌ وغيرُ فارغ', () {
    // مسارٌ بائتٌ بعد نقلِ ملفٍّ يجعل `readAsStringSync` ترمي — أو، لو
    // تُسومح معها، يجعل المصدرَ ينكمش صامتاً فيبلّغ عن فجواتٍ وهميّة.
    for (final f in _rendererFiles) {
      expect(File(f).existsSync(), isTrue, reason: 'مسارٌ بائت: $f');
      expect(File(f).lengthSync(), greaterThan(500), reason: 'ملفٌّ منكمش: $f');
    }
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

/// مصدرُ الرسم كلُّه في نصٍّ واحد.
String _rendererSource() =>
    [for (final f in _rendererFiles) File(f).readAsStringSync()].join('\n');

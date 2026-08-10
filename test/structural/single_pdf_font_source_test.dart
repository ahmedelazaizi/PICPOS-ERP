// حارسٌ بنيويّ — مصدرُ خطِّ الطباعة واحدٌ لكلّ المشروع.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// طابعةٌ تحمل خطَّها **الخاصّ** فتخرج من تحت الإصلاح المركزيّ.
//
// `BaseGenerator.newDocument()` يبني الثيم: الأساسُ Noto Naskh (يحمل أشكالَ
// العرض كلَّها) والاحتياطيُّ Cairo (للّاتينيّ والأرقام). لكنّ النمطَ المحلّيَّ
// `TextStyle(font: X)` **يدهس الأساس** — ولا يدهس الاحتياطيّ. فمن يكتب:
//
//     final doc = await BaseGenerator.newDocument();      // أساس Noto
//     final baseStyle = pw.TextStyle(font: cairo);        // ← صار Cairo
//
// تصير سلسلتُه **Cairo ← Cairo**: الأساسُ Cairo والاحتياطيُّ Cairo. ولا
// مصدرَ فيه الياءُ المنفصلة U+FEF1، فتسقط.
//
// ── المقيسُ ميدانياً 2026-08-10 ───────────────────────────────────────────
// إيصالٌ مطبوعٌ من `template_based_printer` طبع «صبري» والياءُ **راكبةٌ على
// الراء**، و«لوز ارباع» صارت «لوزارباع». وكلُّ اختبارات الخطوط خضراءُ في
// نفس اللحظة — لأنها تقيس `BaseGenerator`، والطابعةُ لا تمرُّ به.
//
// أربعُ طابعاتٍ كانت خارج المصدر الواحد: `template_based_printer` ·
// `template_pdf_renderer` · `templated_invoice_service` ·
// `audit_report_generator`. واثنتان كانتا سليمتَين
// (`report_pdf_generator` · `thermal_receipt_generator`) — فالقاعدةُ كانت
// معروفةً ومطبَّقةً نصفَ تطبيق، وهذا بالضبط ما يحتاج حارساً لا توثيقاً.
//
// وسببٌ ثانٍ مستقلّ: `PdfGoogleFonts.*` **تنزّل من الشبكة** وقت الطباعة.
// نقطةُ بيعٍ بلا إنترنت تفشل طباعتُها أو تتأخّر. الأصولُ محزومةٌ في
// `assets/fonts/` ويقرؤها `BaseGenerator` محلّياً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الموضعُ المشروعُ الوحيد — المصنعُ نفسُه، وفيه الشبكةُ **آخرَ** سبيلٍ بعد
/// الأصل المحزوم.
const _kFontFactory = 'lib/services/generators/base_generator.dart';

final _googleFonts = RegExp(r'\bPdfGoogleFonts\.');

bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
}

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

String _rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('لا طابعةَ تجلب خطَّها بنفسها — المصنعُ وحدَه', () {
    final offenders = <String>[];

    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (rel.endsWith(_kFontFactory)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_isComment(lines[i])) continue;
        if (_googleFonts.hasMatch(lines[i])) {
          offenders.add('$rel:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل `BaseGenerator.initFont()` — الأساسُ Noto Naskh وفيه '
          'أشكالُ العرض كلُّها، والاحتياطيُّ Cairo يأتي من الثيم. وجلبُ '
          'الخطِّ محلّياً يعمل بلا إنترنت. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('ضابط: المصنعُ نفسُه لسه فيه المصدرُ المشروع', () {
    // بلا هذا، حذفُ السطر من المصنع يجعل الحارسَ فوق أخضرَ على مشروعٍ بلا
    // خطٍّ عربيٍّ إطلاقاً.
    final src = File(_kFontFactory).readAsStringSync();
    expect(src.contains('NotoNaskhArabic'), isTrue,
        reason: 'الأساسُ العربيُّ اختفى من المصنع');
    expect(src.contains('Cairo-Regular.ttf'), isTrue,
        reason: 'الاحتياطيُّ اللاتينيُّ اختفى من المصنع');
  });

  test('ضابط: الحارسُ يمسح ملفاتٍ فعلاً', () {
    expect(_libDartFiles().length, greaterThan(100),
        reason: 'مسحُ lib/ رجع بلا ملفات — المسارُ غلط');
  });
}

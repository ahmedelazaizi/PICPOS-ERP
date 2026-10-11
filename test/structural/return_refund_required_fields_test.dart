// حارسٌ بنيويّ — `lineTotal` على `ReturnableLine` و`invoiceTotal` على
// `PosReturnMode.fromLines` **اختياريّان** بنيوياً (لاختباراتٍ قديمةٍ لا
// تُعنى بحساب الاسترداد — راجع توثيقهما)، لكنّ غيابَهما في موضعِ إنتاجٍ
// يُسقط الحسابَ **صامتاً** لنفس الصيغة المعطوبة التي أصلحتها مراجعةُ
// 2026-08-16، لا تقريباً — حرفاً بحرف:
//
//   · بلا `lineTotal`: `ReturnableLine.effectiveLineTotal` يشتقّ
//     `unitPrice * soldQty` (راجع `returnable_line.dart`).
//   · بلا `invoiceTotal`: `PosReturnMode.fromLines` يشتقّه من مجموع
//     `effectiveLineTotal` نفسِه، فيصير `factor` في
//     `calculateReturnRefundTotal` مساوياً `1` بالضبط.
//   ⇒ الناتجُ النهائيّ `Σ qty × unitPrice` — العطبُ المقيسُ بعينه: فاتورةٌ
//     بضريبة ١٤٪ بلا خصمٍ تعرض ١٠٠ (Σqty×unitPrice) بينما المصروفُ فعلياً
//     من الدرج ١١٤ (item.total شاملُ الضريبة). فائضٌ صامتٌ في الدرج يُقيَّد
//     لاحقاً «فائضَ نقدية» — إيرادٌ وهميّ. بلا رميٍ، بلا تحذيرٍ، بلا خطأِ
//     ترجمة؛ الكودُ يترجم ويعمل وهو معطوب.
//
// موضعُ الإنتاج الوحيد اليوم (`picpos_pos_operations.dart`) يمرّر الحقلَين.
// هذا الحارسُ يمنع موضعاً مستقبلياً من إسقاطهما بصمت.
//
// ── التمييزُ بين التعريف والنداء ─────────────────────────────────────────
// تعريفُ بانٍ/دالّةٍ بمعاملاتٍ مسمّاةٍ في Dart يفتح كتلةً `{...}` مباشرةً
// بعد `(` (`ReturnableLine({required this.x, ...})`،
// `factory PosReturnMode.fromLines({...})`)، بينما نداءَه الفعليّ لا يضع
// `{` هناك أبداً (`ReturnableLine(x: 1)`). فأيُّ ظهورٍ يتبعه `{` (بعد فراغٍ
// اختياريّ) هو التعريفُ نفسُه لا نداءً — يُستبعد نحوياً بلا حاجةٍ لاستثناء
// مسارِ ملفٍّ بعينه.
//
// ⚠️ التعليقاتُ **لا تُحتسب**: قياسُ النصّ الخام على تعليقٍ يُنتج حكماً
// كاذباً في الاتجاهَين — درسٌ مسجَّلٌ في هذا المستودع (راجع
// `picpos_permission_parity_test.dart`). فكلُّ فحصٍ هنا يعمل على نصٍّ مجرَّدٍ
// من `//` و`/* */` أوّلاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا تعليقات. نسخةٌ محليّةٌ متعمَّدةٌ — كلُّ حارسٍ بنيويٍّ في
/// هذا المجلد يعرّف نسخته كي لا يتشابك ملفّان في اختبارٍ واحد.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// نداءٌ واحد: موضعُ أوّل حرفٍ بعد `(` ونصُّ المعاملات حتى القوس المطابق.
class _CallSite {
  final int index;
  final String args;
  _CallSite(this.index, this.args);
}

/// كلُّ نداءٍ فعليٍّ لِـ[opener] في [text] — لا التعريف.
///
/// عدُّ الأقواس بسيطٌ (بلا وعيٍ بالسلاسل النصّية)؛ يكفي هنا إذ لا قيمةَ في
/// هذين النداءين تحمل قوساً حرفياً في الإنتاج اليوم — نفسُ حدود قبولِ
/// المخاطرة في `single_adjust_party_balance_def_test.dart` وأخواته.
List<_CallSite> _callSitesOf(String text, RegExp opener) {
  final sites = <_CallSite>[];
  for (final m in opener.allMatches(text)) {
    final afterParen = m.end;
    var j = afterParen;
    while (j < text.length && (text[j] == ' ' ||
        text[j] == '\n' ||
        text[j] == '\r' ||
        text[j] == '\t')) {
      j++;
    }
    if (j < text.length && text[j] == '{') continue; // تعريفٌ، لا نداء.

    var depth = 1;
    var k = afterParen;
    while (k < text.length && depth > 0) {
      if (text[k] == '(') depth++;
      if (text[k] == ')') depth--;
      k++;
    }
    sites.add(_CallSite(afterParen, text.substring(afterParen, k - 1)));
  }
  return sites;
}

int _lineOf(String text, int index) =>
    '\n'.allMatches(text.substring(0, index)).length + 1;

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

String _rel(File f) => f.path.replaceAll(r'\', '/');

final _returnableLineOpener = RegExp(r'\bReturnableLine\s*\(');
final _fromLinesOpener = RegExp(r'\bPosReturnMode\.fromLines\s*\(');

void main() {
  test('كلُّ نداءٍ لـReturnableLine( تحت lib/ يحمل lineTotal:', () {
    final offenders = <String>[];
    var filesScanned = 0;

    for (final file in _libDartFiles()) {
      filesScanned++;
      final raw = file.readAsStringSync();
      final stripped = _stripComments(raw);
      for (final site in _callSitesOf(stripped, _returnableLineOpener)) {
        if (!RegExp(r'\blineTotal\s*:').hasMatch(site.args)) {
          offenders.add('${_rel(file)}:${_lineOf(stripped, site.index)}');
        }
      }
    }

    expect(filesScanned, greaterThan(100),
        reason: 'مسحُ lib/ رجع بملفاتٍ قليلةٍ جداً — المسارُ غلط');
    expect(
      offenders,
      isEmpty,
      reason: 'نداءٌ لِـReturnableLine بلا lineTotal يُسقط '
          'effectiveLineTotal إلى unitPrice*soldQty صامتاً — الصيغةُ '
          'المعطوبةُ (١٠٠ بدل ١١٤ بضريبة ١٤٪) بلا رميٍ ولا تحذير. مرّر '
          '`lineTotal: item.total` صراحةً. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('كلُّ نداءٍ لـPosReturnMode.fromLines( تحت lib/ يحمل invoiceTotal:', () {
    final offenders = <String>[];
    var filesScanned = 0;

    for (final file in _libDartFiles()) {
      filesScanned++;
      final raw = file.readAsStringSync();
      final stripped = _stripComments(raw);
      for (final site in _callSitesOf(stripped, _fromLinesOpener)) {
        if (!RegExp(r'\binvoiceTotal\s*:').hasMatch(site.args)) {
          offenders.add('${_rel(file)}:${_lineOf(stripped, site.index)}');
        }
      }
    }

    expect(filesScanned, greaterThan(100),
        reason: 'مسحُ lib/ رجع بملفاتٍ قليلةٍ جداً — المسارُ غلط');
    expect(
      offenders,
      isEmpty,
      reason: 'نداءٌ لِـPosReturnMode.fromLines بلا invoiceTotal يجعل '
          '`factor` في calculateReturnRefundTotal يساوي ١ بالضبط، فيرجع '
          'الحسابُ للصيغة المعطوبة Σqty×unitPrice صامتاً. مرّر '
          '`invoiceTotal: invoice.total` صراحةً. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('التعليقُ ليس نداءً — لا يُحتسب', () {
    const commented = "// final x = ReturnableLine(invoiceItemId: 1);\n"
        "/* final y = PosReturnMode.fromLines(invoiceId: 1, lines: []); */\n"
        'final z = 1;';
    final stripped = _stripComments(commented);
    expect(_callSitesOf(stripped, _returnableLineOpener), isEmpty);
    expect(_callSitesOf(stripped, _fromLinesOpener), isEmpty);
    expect(stripped.contains('final z = 1;'), isTrue);
  });

  test(
      'ضابط: الملفّاتُ المتوقَّعةُ قُرئت وغيرُ فارغةٍ، وتحمل نداءاتٍ فعلية',
      () {
    final prodFile =
        File('lib/presentation/pos_picpos/screens/picpos_pos_return.dart');
    expect(prodFile.existsSync(), isTrue,
        reason: 'موضعُ الإنتاج الوحيد اليوم اختفى — حدّث هذا الحارس');
    final prodContent = prodFile.readAsStringSync();
    expect(prodContent, isNotEmpty,
        reason: 'الملفُّ قُرئ فارغاً — الحارسُ سيمرّ بلا فحصٍ فعليّ');
    expect(prodContent.contains('ReturnableLine('), isTrue);
    expect(prodContent.contains('PosReturnMode.fromLines('), isTrue);

    final defFile = File('lib/domain/models/returnable_line.dart');
    expect(defFile.existsSync(), isTrue);
    final defContent = defFile.readAsStringSync();
    expect(defContent, isNotEmpty,
        reason: 'الملفُّ قُرئ فارغاً — الحارسُ سيمرّ بلا فحصٍ فعليّ');

    final modeFile = File('lib/presentation/pos_picpos/state/pos_return_mode.dart');
    expect(modeFile.existsSync(), isTrue);
    final modeContent = modeFile.readAsStringSync();
    expect(modeContent, isNotEmpty,
        reason: 'الملفُّ قُرئ فارغاً — الحارسُ سيمرّ بلا فحصٍ فعليّ');
  });

  test('ضابط: الآليّةُ تميّز التعريفَ عن النداء وتُمسك نداءً ناقصاً فعلاً',
      () {
    // نداءٌ ناقصُ الحقل — يجب أن يُرصَد.
    const missing = '''
final x = ReturnableLine(
  invoiceItemId: 1,
  productId: 2,
  productName: 'ص',
  soldQty: 1,
  alreadyReturnedQty: 0,
  unitPrice: 1,
);
''';
    final missingSites =
        _callSitesOf(_stripComments(missing), _returnableLineOpener);
    expect(missingSites, hasLength(1));
    expect(RegExp(r'\blineTotal\s*:').hasMatch(missingSites.single.args),
        isFalse,
        reason: 'لو مرّ هذا صامتاً فالحارسُ لا يقيس شيئاً فعلاً');

    // نداءٌ كاملٌ — لا يُرصَد.
    const present = '''
final x = ReturnableLine(
  invoiceItemId: 1,
  lineTotal: 10,
);
''';
    final presentSites =
        _callSitesOf(_stripComments(present), _returnableLineOpener);
    expect(presentSites, hasLength(1));
    expect(RegExp(r'\blineTotal\s*:').hasMatch(presentSites.single.args),
        isTrue);

    // والتعريفُ نفسُه (معاملاتٌ مسمّاةٌ بكتلة `{...}`) لا يُحتسب نداءً
    // إطلاقاً — هذا ما يمنع الحارسَ من رفض ملفّ التعريف نفسه.
    const definition = 'const ReturnableLine({\n'
        '  required this.invoiceItemId,\n'
        '  this.lineTotal,\n'
        '});';
    expect(_callSitesOf(_stripComments(definition), _returnableLineOpener),
        isEmpty,
        reason: 'التعريفُ (يفتح كتلةَ `{` بعد `(`) لا يجوز أن يُحتسب نداءً '
            'ناقصاً — وإلا رفض الحارسُ ملفَّ التعريف نفسه');

    const factoryDef = 'factory PosReturnMode.fromLines({\n'
        '  required int invoiceId,\n'
        '});';
    expect(_callSitesOf(_stripComments(factoryDef), _fromLinesOpener),
        isEmpty);
  });
}

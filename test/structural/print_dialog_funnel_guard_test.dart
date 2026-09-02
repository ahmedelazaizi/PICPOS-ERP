// حارسُ القمع: حوارُ الطباعة الأصليُّ يُنادى من موضعٍ واحدٍ في `lib`.
//
// ═══ فئةُ العطب ═══
//
// `Printing.layoutPdf` تُرجع ردَّ المستخدم في حوار النظام. نداءٌ مباشرٌ لها
// خارجَ `PdfComputeHelper` يفقد ثلاثةَ أشياء دفعةً واحدة: سجلَّ التشخيص
// (`PDF-PRINT`)، وخطّافَ تسجيل الطباعة، **وقيمةَ الإلغاء** — فيعود «تمّت
// الطباعة» لمن ضغط «إلغاء». كان ذلك في ثلاثةَ عشرَ موضعاً (مقيس
// 2026-09-02) وأُغلقت كلُّها؛ وهذا يمنع عودتَها واحداً واحداً.
//
// والتعليقاتُ تُنزَع قبل القياس: أربعةُ ملفّاتٍ تذكر الاسمَ في تعليقٍ فحسب،
// ومطابقتُها كانت ستبلّغ عن فجواتٍ وهميّة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _funnel = 'lib/services/printing/pdf_compute_helper.dart';

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
  return noBlock.split('\n').map((line) {
    var i = line.indexOf('//');
    while (i > 0 && line[i - 1] == ':') {
      i = line.indexOf('//', i + 2);
    }
    return i < 0 ? line : line.substring(0, i);
  }).join('\n');
}

/// `Printing.layoutPdf(` بأيّ بادئةِ استيراد (`printing_pkg.` أو بلا).
final _directCall = RegExp(r'\bPrinting\.layoutPdf\(');

void main() {
  final offenders = <String>[];
  var funnelHits = 0;
  var filesScanned = 0;

  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    filesScanned++;
    final rel = f.path.replaceAll('\\', '/');
    final hits = _directCall.allMatches(_stripComments(f.readAsStringSync()));
    if (hits.isEmpty) continue;
    if (rel.endsWith(_funnel)) {
      funnelHits += hits.length;
    } else {
      offenders.add('$rel (${hits.length})');
    }
  }

  test('مرساة: المسحُ وجد ملفّاتٍ والقمعَ نفسَه', () {
    expect(filesScanned, greaterThan(500),
        reason: 'مسحُ `lib` عاد شبهَ فارغ — كلُّ حكمٍ بعده باطل');
    expect(funnelHits, 1,
        reason: 'القمعُ ينادي الحوارَ الأصليَّ مرّةً واحدةً بالضبط. صفرٌ ⇒ '
            'انكسر الكشفُ أو تغيّر القمع؛ أكثرُ ⇒ تفرّعٌ داخلَه.');
  });

  test('ومرساةُ النزع: ذكرٌ في تعليقٍ لا يُحسَب نداءً', () {
    const commentOnly = '// `Printing.layoutPdf()` on Windows opens…\n'
        'final x = 1;';
    expect(_directCall.hasMatch(_stripComments(commentOnly)), isFalse);
    expect(_directCall.hasMatch('await printing_pkg.Printing.layoutPdf('),
        isTrue);
  });

  test('🔴 لا نداءَ مباشرٌ لحوار الطباعة خارجَ القمع', () {
    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason: 'نداءاتٌ مباشرةٌ لـ`Printing.layoutPdf`:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'مرِّرها عبر `PdfComputeHelper.layoutPdf(pdf)` أو '
          '`PdfComputeHelper.layoutBytes(bytes)` وأعِد قيمتَها: نداءٌ مباشرٌ '
          'يفقد سجلَّ التشخيص وخطّافَ التسجيل وقيمةَ الإلغاء معاً.',
    );
  });
}

// حارسٌ بنيويّ — بنيةُ المستند ومحرّكُ التخطيط **بلا `package:pdf` ولا
// `package:flutter`**.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ──────────────────────────────────────────
// فئةُ العطب هنا: «استيرادٌ يتسلّل فيقفل الباب». الاختبارُ السلوكيُّ لا يمسكه
// إطلاقاً — الكودُ يعمل تماماً بعد التسلّل، والثمنُ يُدفع لاحقاً: اللحظةَ
// التي يستورد فيها `layout_engine` من `package:pdf` يصير رسمُ المعاينة
// مستحيلاً بنفس المحرّك، فيُكتب راسمٌ ثانٍ، ويعود عطبُ «المعاينة ≠ الورق»
// الذي بُني هذا كلُّه لمنعه.
//
// و`package:flutter` أسوأ: يجرّ `dart:ui` فيصير الاختبارُ محتاجاً بيئةَ
// ودجت، فتموت القدرةُ على قياس التخطيط بلا واجهة — وهي رأسُ مال هذا التصميم.
//
// ── ما يُستثنى ────────────────────────────────────────────────────────────
// لا شيء. الملفّان نقيّان بالتعريف، والاستثناءُ الأوّلُ هو أوّلُ الانهيار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الملفّاتُ المحروسة — نقيّةٌ بالتعريف.
const _guarded = <String>[
  'lib/domain/printing/template_document.dart',
  'lib/domain/printing/condition_evaluator.dart',
  'lib/domain/printing/template_mapper.dart',
  'lib/services/printing/layout_engine.dart',
];

/// الحزمُ الممنوعة، وسببُ منعِ كلٍّ منها.
const _forbidden = <String, String>{
  'package:pdf': 'يقفل المحرّكَ على قماشٍ واحد، فيُكتب راسمٌ ثانٍ للمعاينة',
  'package:printing': 'تبعيّةُ جهازٍ في طبقةِ حساب',
  'package:flutter': 'يجرّ dart:ui فيموت القياسُ بلا واجهة',
  'dart:ui': 'نفسُ الأثر بلا واسطة',
  'dart:io': 'طبقةُ الحساب لا تلمس قرصاً',
};

/// أيُّ استيرادٍ أو تصدير، بأيِّ اقتباس.
final _importLine = RegExp(
  r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",
  multiLine: true,
);

/// يُرجع الحزمَ الممنوعةَ التي يستوردها [source].
List<String> forbiddenImportsIn(String source) {
  final hits = <String>[];
  for (final m in _importLine.allMatches(source)) {
    final uri = m.group(1)!;
    for (final bad in _forbidden.keys) {
      if (uri == bad || uri.startsWith('$bad/')) hits.add(uri);
    }
  }
  return hits;
}

void main() {
  for (final path in _guarded) {
    test('$path بلا تبعيّةِ رسمٍ أو واجهة', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'الملفُّ المحروسُ اختفى — الحارسُ صار يقيس لا شيء');

      final offenders = forbiddenImportsIn(file.readAsStringSync());

      expect(
        offenders,
        isEmpty,
        reason: 'استيرادٌ ممنوعٌ في طبقةِ الحساب: ${offenders.join(' · ')}\n'
            'الأسباب:\n${_forbidden.entries.map((e) => '  ${e.key} — ${e.value}').join('\n')}',
      );
    });
  }

  // ── ضابطُ الحارس ────────────────────────────────────────────────────────
  // «صفرُ المطابقات» يعني نمطاً غلطاً أكثرَ ممّا يعني نظافةً. فيُختبَر
  // النمطُ على **عينِ** الحالة التي يحرسها قبل أن يُوثَق به.
  group('ضابط: النمطُ يمسك ما يدّعي', () {
    test('يمسك الاستيرادَ المباشر', () {
      expect(
        forbiddenImportsIn("import 'package:pdf/widgets.dart' as pw;"),
        ['package:pdf/widgets.dart'],
      );
    });

    test('يمسك الاقتباسَ المزدوجَ والمسافةَ البادئة', () {
      expect(
        forbiddenImportsIn('  import "package:flutter/material.dart";'),
        ['package:flutter/material.dart'],
      );
    });

    test('يمسك `export` لا `import` وحدَه', () {
      expect(
        forbiddenImportsIn("export 'dart:ui';"),
        ['dart:ui'],
      );
    });

    test('ولا يخلط حزمةً اسمُها يبدأ بنفس الحروف', () {
      // `package:pdfx` ليست `package:pdf` — الحدُّ على `/` لا على البادئة.
      expect(forbiddenImportsIn("import 'package:pdfx/pdfx.dart';"), isEmpty);
    });

    test('ويمرّ على الاستيراد المشروع', () {
      expect(
        forbiddenImportsIn("import '../../domain/printing/template_document.dart';"),
        isEmpty,
      );
    });
  });
}

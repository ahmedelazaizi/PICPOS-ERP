// Structural guard — every PDF document must come from
// `BaseGenerator.newDocument()`, never from a bare `pw.Document()`.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ──────────────────────────────────────────
// فئةُ العطب هنا: «مطبوعٌ **جديد** نسي الثيم». والاختبارُ السلوكيُّ لا يغطّي
// إلا المطبوعاتِ التي تذكّر أحدٌ أن يكتب لها اختباراً؛ وهذا يسقط لحظةَ أن
// يضيف أيٌّ كان مستنداً عارياً في أيّ مكان.
//
// والعطبُ صامتٌ تماماً: المستندُ العاري بلا `theme` يعني خطاً واحداً لكلّ
// النصّ، وأيُّ رسمٍ ينقصه ذلك الخطُّ **يُحذف بلا أثر** — لا مربّعٌ ولا خطأ.
// الفاتورةُ تُطبع، والاسمُ عليها ناقصُ حرف.
//
// اقرا `BaseGenerator.newDocument` للآلية كاملةً، و
// `test/unit/pdf_document_font_fallback_wiring_test.dart` للقياس السلوكيّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `pw.Document(` بلا وسائط — الشكلُ الوحيدُ الممنوع. المصنعُ نفسُه
/// (`base_generator.dart`) يُستثنى لأنه **موضعُ النداء المشروع الوحيد**.
final _bare = RegExp(r'\bpw\.Document\(\s*\)');

void main() {
  test('لا مستندَ PDF عارياً في lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.replaceAll(r'\', '/').endsWith(
          'lib/services/generators/base_generator.dart')) {
        continue; // موضعُ النداء المشروع الوحيد
      }

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // التعليقاتُ التوضيحية تذكر الشكلَ عمداً.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (_bare.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل `await BaseGenerator.newDocument()`. المستندُ العاري '
          'بلا ثيمٍ يعني خطاً واحداً لكلّ النصّ، والرسمُ الناقص يُحذف '
          'بالسكوت من المطبوع. المواضع:\n  ${offenders.join('\n  ')}',
    );
  });

  test('ضابط: المصنعُ نفسُه فيه النداءُ المشروع', () {
    final src =
        File('lib/services/generators/base_generator.dart').readAsStringSync();
    expect(src.contains('pw.Document('), isTrue,
        reason: 'لو اختفى فالحارسُ فوق ما بيقيسش حاجة');
    expect(src.contains('ThemeData.withFont'), isTrue,
        reason: 'المصنعُ لازم يفضل بيحطّ الثيم — وإلا الحارسُ يمرّ '
            'ومستنداتُ المشروع كلُّها بلا خطٍّ احتياطيّ');
  });
}

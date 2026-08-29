// حارسٌ بنيويّ — الراسمون يستهلكون `PaintOp` ولا يحسبون موضعاً.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ──────────────────────────────────────────
// فئةُ العطب: «راسمٌ يقرأ الهندسةَ من مصدرٍ ثانٍ». والاختبارُ السلوكيُّ لا
// يمسكها إلّا بالمصادفة — الراسمُ الذي يقرأ `page.tables` مباشرةً ويحسب
// أعمدتَه بنفسه **يعمل تماماً** ويعطي ورقاً صحيحاً... حتى تختلف حسبتُه عن
// حسبةِ راسم المعاينة بمليمتر، فيبدأ بلاغُ «الشكلُ في المعاينة غيرُه على
// الورق» الذي لا يُعاد إنتاجُه ولا يُصدَّق.
//
// وهذا ليس افتراضاً: `debugRenderItemsTable` موجودةٌ في الكود اليومَ كمِقبضِ
// اختبارٍ بُني خصّيصاً لقياس هذا الفرق. الحارسُ يمنع عودتَه.
//
// ── ما يُسمح ──────────────────────────────────────────────────────────────
// استيرادُ نوع `PositionedPage` مسموح (الراسمُ يستقبله). الممنوعُ **قراءةُ
// هندسته**: `.tables` · `.rows` · `.elements` · نداءُ `LayoutEngine`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الملفّاتُ المحروسة — كلُّ من يرسم على قماش.
const _painters = <String>[
  'lib/services/printing/pdf_painter.dart',
];

/// أنماطُ «قراءةِ الهندسة من مصدرٍ ثانٍ»، وسببُ منعِ كلٍّ منها.
final _banned = <RegExp, String>{
  RegExp(r'LayoutEngine\s*\.'):
      'الراسمُ يستقبل الصفحاتِ مخطَّطةً — إعادةُ تخطيطها فيه مسارٌ ثانٍ',
  RegExp(r'\.tables\b'): 'هندسةُ الجدول تصل عبر planPage لا بقراءةٍ مباشرة',
  RegExp(r'\.rows\b'): 'صفوفُ الجدول كذلك',
  RegExp(r'\.elements\b'): 'عناصرُ الصفحة كذلك',
  RegExp(r'\.headerCells\b'): 'رؤوسُ الأعمدة كذلك',
};

/// يُرجع المخالفاتِ في [source] — سطراً ونمطاً.
///
/// التعليقاتُ تُستثنى: هذا الملفُّ نفسُه يذكر الأنماطَ عمداً في شرحه.
List<String> layoutReadsIn(String source) {
  final hits = <String>[];
  final lines = source.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;

    for (final entry in _banned.entries) {
      if (entry.key.hasMatch(line)) {
        hits.add('${i + 1}: ${entry.value}');
      }
    }
  }
  return hits;
}

void main() {
  for (final path in _painters) {
    test('$path لا يحسب هندسةً', () {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'الملفُّ المحروسُ اختفى — الحارسُ صار يقيس لا شيء');

      final src = file.readAsStringSync();

      expect(
        layoutReadsIn(src),
        isEmpty,
        reason: 'الراسمُ يقرأ الهندسةَ من مصدرٍ ثانٍ:\n  '
            '${layoutReadsIn(src).join('\n  ')}\n'
            'المسارُ المشروعُ الوحيد: planPage(page) ثمّ ارسم PaintOp كما هي.',
      );

      // والضابطُ الموجب: لو اختفى النداءُ المشروعُ فالراسمُ لا يرسم شيئاً
      // أصلاً، والحارسُ فوق يمرّ على ملفٍّ فارغ.
      expect(src.contains('planPage('), isTrue,
          reason: 'الراسمُ لا ينادي planPage — فمن أين يأتي بالمواضع؟');
    });
  }

  // ── ضابطُ الحارس ────────────────────────────────────────────────────────
  // حارسٌ لا يُختبَر على الحالة التي يحرسها ليس حارساً. وهذه **عينُ** الشيفرة
  // التي يمنعها.
  group('ضابط: النمطُ يمسك ما يدّعي', () {
    test('يمسك إعادةَ التخطيط داخلَ الراسم', () {
      expect(
        layoutReadsIn('  final p = LayoutEngine.paginate(document: d);'),
        isNotEmpty,
      );
    });

    test('يمسك القراءةَ المباشرةَ لجداول الصفحة', () {
      expect(layoutReadsIn('  for (final t in page.tables) {'), isNotEmpty);
    });

    test('يمسك القراءةَ المباشرةَ للصفوف والعناصر', () {
      expect(layoutReadsIn('  page.rows.first;'), isNotEmpty);
      expect(layoutReadsIn('  page.elements.length;'), isNotEmpty);
    });

    test('ولا يشكو من تعليقٍ يذكر النمطَ شرحاً', () {
      expect(layoutReadsIn('  // لا تقرأ page.tables هنا'), isEmpty);
      expect(layoutReadsIn('  /// انظر page.elements'), isEmpty);
    });

    test('ولا يشكو من الاستهلاك المشروع', () {
      expect(
        layoutReadsIn('  final ops = planPage(page, direction: dir);'),
        isEmpty,
      );
    });
  });
}

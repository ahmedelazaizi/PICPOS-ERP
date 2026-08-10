// حارسٌ بنيويّ — قالبُ إغلاق الوردية موصولٌ بالطباعة.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// نوعُ قالبٍ كاملٌ في المحرِّر لا يطبعه شيء.
//
// المحرِّرُ يعرض `shift_closing` وستّةَ عشرَ عنصراً تحته، والبذرةُ تزرع قالباً
// افتراضياً باسم «تقرير إغلاق الوردية». والمستخدمُ يصمّم ويحفظ — ثم يطبع
// الإقفالُ من مولّدٍ **ثابت** لا يقرأ القالبَ إطلاقاً. فالتصميمُ يُحفظ ولا
// يُرى أبداً، ولا رسالةَ تقول لماذا.
//
// وهو أخفى من عنصرٍ ناقص: العناصرُ الستّةَ عشرَ كانت تسقط على
// `default: return ''`، وعنصرٌ بلا تسميةٍ وبلا قيمةٍ يرجع `SizedBox()` —
// أي يختفي بلا أثر.
//
// حارسٌ بنيويٌّ لا سلوكيّ: المقيسُ هنا **الوصل**. وصحّةُ القيم مقيسةٌ في
// `test/unit/shift_template_values_test.dart`، ومسارُ الطباعة نفسُه يحتاج
// طابعةً فلا يُنادى من اختبار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _printPath = 'lib/services/printing/shift_closing_print.dart';

bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains(name);
}

void main() {
  final f = File(_printPath);

  test('مسارُ إقفال الوردية يسأل عن قالبٍ افتراضيّ', () {
    expect(f.existsSync(), isTrue, reason: 'مسارُ ملفّ الطباعة تغيّر');
    final lines = f.readAsLinesSync();

    expect(
      lines.any((l) => _isCall(l, 'hasDefaultTemplate')),
      isTrue,
      reason: 'بلا هذا السؤال يبقى نوعُ القالب `shift_closing` واجهةً ميتة: '
          'يُصمَّم ويُحفظ ولا يُطبع. الفاتورةُ تسأل السؤالَ نفسَه في '
          '`printing_service.dart` — والوردية لا.',
    );
  });

  test('ويمرّر اللقطةَ للقالب كي تُحلَّ عناصرُ `shift_*`', () {
    final src = f.readAsStringSync();
    expect(src.contains('shift:'), isTrue,
        reason: 'بلا تمرير اللقطة تسقط العناصرُ الستّةَ عشرَ على القيمة '
            'الفارغة فتختفي — نفسُ العطب بشكلٍ آخر');
  });

  test('ويبقى المولّدُ الثابتُ بديلاً حين لا قالبَ', () {
    final src = f.readAsStringSync();
    expect(src.contains('printShiftClosingReport'), isTrue,
        reason: 'تجهيزةٌ بلا قالبٍ افتراضيٍّ لازم تفضل تطبع — الوصلُ '
            'إضافةٌ لا استبدال');
  });

  test('ضابط: الدالّةُ المقيسة موجودةٌ في الخدمة', () {
    final svc = File('lib/services/templated_invoice_service.dart');
    expect(svc.existsSync(), isTrue);
    final src = svc.readAsStringSync();
    expect(src.contains('resolveShiftValue'), isTrue,
        reason: 'الاسمُ تغيّر — حدّث الحارس، لا تحذفه');
  });
}

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
import '../helpers/library_source.dart';

const _printPath = 'lib/services/printing/shift_closing_print.dart';
const _servicePath = 'lib/services/templated_invoice_service.dart';
const _palettePath =
    'lib/presentation/screens/invoice_designer/invoice_designer_ui.dart';
const _sectionPath =
    'lib/presentation/screens/invoice_designer/invoice_section_editor.dart';
const _seederPath = 'lib/data/database/daos/invoice_template_seeder_dao.dart';

bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains(name);
}

void main() {
  final f = File(_printPath);

  // §٥-٢ — قناةُ دفعٍ تدخل الإجماليَّ ولا يعرضها القالبُ تجعل التقريرَ لا
  // يجمع. المرصود ميدانياً: `240,000 + 120,000` بإجمالي `560,000` — والفارقُ
  // «كليك»، حاضرةٌ في اللقطة وفي المجاميع، غائبةٌ عن **أربع** طبقات:
  // الحلُّ · لوحةُ المصمّم · محرِّرُ الأقسام · القالبُ المبذور.
  //
  // فحارسٌ على الطبقات الأربع معاً: إصلاحُ الحلِّ وحدَه يجعل القيمةَ قابلةً
  // للحلّ ولا يضعها في يد المستخدم ولا في المطبوع الافتراضيّ — أي يبقى
  // التقريرُ لا يجمع. وهذا يمتدّ لأيّ قناةٍ تُضاف لاحقاً.
  group('§٥-٢ — كلُّ قناةِ دفعٍ حاضرةٌ في الطبقات الأربع', () {
    const layers = <String, String>{
      _servicePath: 'الحلُّ — بلاها ترجع `null` فيختفي العنصر',
      _palettePath: 'لوحةُ المصمّم — بلاها لا يملك المستخدمُ وضعَها',
      _sectionPath: 'محرِّرُ الأقسام — بلاها لا تظهر في التحرير السريع',
      _seederPath: 'القالبُ المبذور — بلاها لا يجمع المطبوعُ الافتراضيّ',
    };

    for (final channel in const ['cash', 'card', 'click']) {
      for (final metric in const ['system', 'actual']) {
        final token = 'shift_${metric}_$channel';
        layers.forEach((path, why) {
          test('$token في ${path.split('/').last}', () {
            final file = File(path);
            expect(file.existsSync(), isTrue, reason: 'مسارُ $path تغيّر');
            expect(readLibrarySource(path).contains(token), isTrue,
                reason: '«$token» غائبٌ عن $why');
          });
        });
      }
    }
  });

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
    final src = readLibrarySource(svc.path);
    expect(src.contains('resolveShiftValue'), isTrue,
        reason: 'الاسمُ تغيّر — حدّث الحارس، لا تحذفه');
  });
}

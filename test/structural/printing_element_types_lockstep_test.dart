// ═══════════════════════════════════════════════════════════════════════════
// §٦‑١ — قائمةُ الأنواع المرسومة تبقى في خطوةٍ واحدةٍ مع الراسم
// ═══════════════════════════════════════════════════════════════════════════
//
// `layoutSequenceForPrint` تُرشِّح عناصرَ القالب قبل الرسم. وكانت تحمل قائمةً
// بيضاءَ **يدويّةً** بخمسةِ أنواعٍ بينما `_buildElementContent` يعالج تسعةً
// وثلاثين — فسقطت سبعةٌ وثلاثون نوعاً قبل أن تصل الراسمَ الذي يفهمها، وخمسةُ
// قوالبَ مشحونةٍ كانت تُطبع جدولَ أصنافٍ عارياً (‏٢١ من ٢١ عنصراً مُسقَطاً في
// `thermal_classic`).
//
// وجذرُ ذلك أنّ القائمةَ **نسخةٌ ثانيةٌ** لمعرفةٍ يملكها المُصيِّر. فصارت
// [kRenderableElementTypes] هي المصدرَ، وهذا الحارسُ يمنع افتراقَها عنه:
// أيُّ `case` يُضاف إلى المُصيِّر أو يُحذف منه ولا يقابله تغييرٌ في الثابت
// يُسقط الاختبار.
//
// ⚠️ والاستخراجُ **مُرسًى**: إن عاد فارغاً أو ضئيلاً سقط الاختبارُ بدل أن
// يمرَّ زوراً — فنمطٌ خاطئٌ لا يُنتج «لا فرق».

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/library_source.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

const _servicePath = 'lib/services/templated_invoice_service.dart';

/// كلُّ `case '...'` داخلَ جسم `_buildElementContent` وحدَه.
Set<String> _casesInBuildElementContent(String source) {
  final lines = source.split('\n');
  final start = lines.indexWhere(
      (l) => l.contains('static pw.Widget _buildElementContent('));
  if (start < 0) return const {};

  // نهايةُ الدالّة = أوّلُ عضوٍ ساكنٍ تالٍ على نفس الإزاحة.
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('  static ')) {
      end = i;
      break;
    }
  }

  final re = RegExp(r"case '([a-z_0-9]+)':");
  final out = <String>{};
  for (var i = start; i < end; i++) {
    for (final m in re.allMatches(lines[i])) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

void main() {
  test('kRenderableElementTypes يطابق مُصيِّرَ الراسم حرفاً بحرف', () {
    final file = File(_servicePath);
    expect(file.existsSync(), isTrue,
        reason: 'مرساة: مسارُ الخدمة صحيح — $_servicePath');

    final cases = _casesInBuildElementContent(readLibrarySource(_servicePath));

    // مرساةُ الاستخراج: نمطٌ منكسرٌ يعود بمجموعةٍ فارغةٍ فتبدو «لا فرق».
    expect(cases.length, greaterThan(20),
        reason: 'مرساة: الاستخراجُ يعمل — وُجد ${cases.length} نوعاً فقط، '
            'وهذا يعني نمطاً خاطئاً أو دالّةً أُعيدت تسميتُها');

    final missingFromConst = cases.difference(kRenderableElementTypes);
    final extraInConst = kRenderableElementTypes.difference(cases);

    expect(missingFromConst, isEmpty,
        reason: 'أنواعٌ يرسمها المُصيِّر ولا تمرُّ المرشِّحَ — ستسقط صامتةً '
            'من كلِّ قالبٍ يستعملها: $missingFromConst');
    expect(extraInConst, isEmpty,
        reason: 'أنواعٌ في الثابت لا يعرفها المُصيِّر — ستمرُّ المرشِّحَ ثمّ '
            'تُرسَم بالسلوك الافتراضيّ: $extraInConst');
  });

  test('أنواعُ الحاويات والمتكرّرةُ لا تتقاطعان تقاطعاً يُفسد الحذف', () {
    // `text` وحدَه يقع في الاثنتين عمداً: حاويةٌ (يُحسم محتواها) ونصٌّ ثابتٌ
    // يتكرّر. وما عداه يجب ألّا يكون حاويةً ومتكرّراً معاً.
    final both =
        kTemplateContainerElementTypes.intersection(kRepeatableElementTypes);
    expect(both, equals(<String>{'text'}),
        reason: 'تقاطعٌ غيرُ متوقَّع بين الحاويات والمتكرّرات: $both');
  });

  test('كلُّ متكرّرٍ نوعٌ يعرفه الراسم', () {
    final unknown = kRepeatableElementTypes.difference(kRenderableElementTypes);
    expect(unknown, isEmpty,
        reason: 'نوعٌ أُعفي من الحذف وهو مجهولٌ للراسم: $unknown');
  });
}

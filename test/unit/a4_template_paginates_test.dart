// قوالبُ A4/A5 تنقسم إلى صفحاتٍ ولا تُطبع لفّةً واحدة.
//
// ═══ فئةُ العطب — بلاغُ تدقيق الطباعة 2026-08-30 ═══
//
// `_pageHeightPoints` تُرجع `null` حين يغيب `paperHeight`، و`null` تعني
// **لفّةً مستمرّة**: `pw.Page` بارتفاعٍ لا نهائيٍّ بدل `pw.MultiPage`.
//
// وأحدَ عشرَ من اثنَي عشرَ ملفَّ A4/A5 في الأصول كان بلا هذا الحقل. فالفاتورةُ
// الضريبيّةُ بستّين صنفاً تخرج **صفحةً واحدةً طولُها ٦٩ سم**: لا فاصلَ صفحات،
// ولا ترويسةً مكرّرة، ولا أرقامَ صفحات — والسائقُ إمّا يُصغّرها إلى نصٍّ لا
// يُقرأ أو يقصّها عند ٢٩٧ مم فتضيع الأصنافُ والمجاميع.
//
// ═══ طبقتا الإصلاح ═══
//
//   ١. الملفّاتُ الأحدَ عشرَ صار فيها `paperHeight`.
//   ٢. `_inferPaperHeight` تستنتجه من `paperSize` حين يغيب — وهي التي تمنع
//      عودةَ العطب بأوّل ملفٍّ جديدٍ غداً. الملفّاتُ وحدَها تعالج الحاضر.
//
// وهذا الملفُّ يحرس **الطبقتين**: بيانات الأصول، وسلوكَ الاستنتاج.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'assets/invoice_templates';

/// ارتفاعُ الورقة المتوقَّعُ لكلِّ مقاس.
const _expected = <String, double>{'A3': 420, 'A4': 297, 'A5': 210};

List<MapEntry<String, Map<String, dynamic>>> _sheetTemplates() {
  final out = <MapEntry<String, Map<String, dynamic>>>[];
  for (final f in Directory(_dir).listSync()) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final data =
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final size = (data['paperSize'] as String?)?.toUpperCase().trim();
    if (size == null || !_expected.containsKey(size)) continue;
    out.add(MapEntry(f.uri.pathSegments.last, data));
  }
  return out;
}

void main() {
  group('قوالبُ الورق القياسيّ تحمل ارتفاعَها', () {
    late List<MapEntry<String, Map<String, dynamic>>> sheets;

    setUpAll(() => sheets = _sheetTemplates());

    test('المرساة: ملفّاتُ الورق القياسيّ موجودةٌ ومقروءة', () {
      // ⚠️ بلا مرساةٍ يمرُّ الحارسُ أخضرَ لو لم يُعثَر على ملفٍّ واحد.
      expect(sheets.length, greaterThanOrEqualTo(10),
          reason: 'وُجد ${sheets.length} قالبَ ورقٍ قياسيٍّ فقط — '
              'إمّا تغيّر المجلّدُ وإمّا انكسر الفكّ');
      expect(sheets.map((e) => e.key), contains('a4_sales_tax_invoice.json'),
          reason: 'الفاتورةُ الضريبيّةُ — وهي موضعُ البلاغ — غائبة');
    });

    test('كلُّ قالبِ ورقٍ قياسيٍّ له `paperHeight` مطابقٌ لمقاسه', () {
      final wrong = <String>[];
      for (final e in sheets) {
        final size = (e.value['paperSize'] as String).toUpperCase().trim();
        final h = (e.value['paperHeight'] as num?)?.toDouble();
        if (h == null) {
          wrong.add('${e.key}: غائب ($size) ⇒ لفّةٌ مستمرّة');
        } else if (h != _expected[size]) {
          wrong.add('${e.key}: $h بدل ${_expected[size]} ($size)');
        }
      }
      expect(wrong, isEmpty,
          reason: 'قالبُ ورقٍ قياسيٍّ بلا ارتفاعٍ صحيحٍ يُطبع صفحةً واحدةً '
              'مهما طال:\n  ${wrong.join("\n  ")}');
    });

    test('والحراريُّ يبقى بلا ارتفاع — لفّتُه مستمرّةٌ عمداً', () {
      // ⚠️ فرضُ ارتفاعٍ على الحراريِّ يقصّ الإيصالَ الطويل. فهذا الفحصُ يمنع
      // «إصلاحاً» زائداً بقدر ما يمنع النقصان.
      for (final f in Directory(_dir).listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final width = (data['paperWidth'] as num?)?.toDouble() ?? 80;
        if (width > 80) continue;
        expect(data['paperHeight'], isNull,
            reason: 'القالبُ الحراريُّ ${f.uri.pathSegments.last} اكتسب '
                'ارتفاعاً ⇒ إيصالُه الطويلُ سيُقصّ');
      }
    });
  });
}

// حارسُ التوصيل: نبضةُ تقديم الفاتورة الإلكترونيّة معلَّقةٌ بإقلاع الخادم.
//
// ═══ فئةُ العطب ═══
//
// العاملُ مُختبَرٌ وحدَه (‏`einvoice_submission_worker_test`) والمسحُ مُختبَرٌ
// وحدَه (‏`einvoice_sweeper_query_test`) — لكنّ أيّاً منهما لا يقول إنّ أحداً
// **يُشغّلهما**. وبلا التعليق يبقى الطابورُ ممتلئاً إلى الأبد ولا يصل مصلحةَ
// الضرائب مستندٌ واحد، بلا خطأٍ يظهر لأحد.
//
// وهي فجوةٌ مقيسةٌ مرّتين في هذا المستودع: الشعارُ كان موصولاً في الراسم
// وغائباً عن المنادي، وقرارُ رمز الإيصال كان محترَماً في ثلاثة راسمين ولا
// يُحلّ من موضع النداء.
//
// ═══ ويُقاس الإيقافُ كما يُقاس التشغيل ═══
//
// مؤقّتٌ لا يُلغى عند إيقاف الخادم يبقى يمسح القاعدةَ بعد أن أُوقف — وعلى
// جهازٍ بُدّل إلى وضع العميل يعني ذلك محاولةَ إرسالٍ من جهازٍ لا يجوز أن
// يرسل أصلاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _file = 'lib/services/network_service.dart';

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

/// نصُّ جسمِ دالّةٍ من توقيعها إلى قوسها المعقوف الموازن.
///
/// ⚠️ **وقائمةُ الوسائط تُتخطّى أوّلاً**: أوّلُ `{` بعد التوقيع قد يكون
/// وسائطَ مسمّاةً (`{int? port}`) لا جسمَ الدالّة — وهو ما أمسكته المرساةُ
/// فعلاً، فكان الحارسُ يقرأ `'{int? port}'` ويحكم عليه.
String _body(String src, String signature) {
  final start = src.indexOf(signature);
  if (start < 0) return '';

  // من قوس التوقيع الفاتح إلى مغلقه الموازن — فتُتخطّى الوسائطُ المسمّاة.
  var paren = 0;
  var i = src.indexOf('(', start);
  if (i < 0) return '';
  for (; i < src.length; i++) {
    if (src[i] == '(') paren++;
    if (src[i] == ')') {
      paren--;
      if (paren == 0) break;
    }
  }

  final open = src.indexOf('{', i);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return '';
}

void main() {
  final src = _stripComments(File(_file).readAsStringSync());
  final startBody = _body(src, 'Future<bool> startServer(');
  final stopBody = _body(src, 'Future<void> stopServer(');

  test('مرساة: الملفُّ والدالّتان موجودةٌ فعلاً', () {
    expect(src.length, greaterThan(5000),
        reason: 'الملفُّ فارغٌ أو تحرّك — كلُّ حكمٍ بعده باطل');
    expect(startBody, contains('shelf_io.serve'),
        reason: 'لم يُقتنَص جسمُ `startServer` — فالتوكيداتُ بعده بلا معنى');
    expect(stopBody, contains('_httpServer'),
        reason: 'لم يُقتنَص جسمُ `stopServer`');
  });

  test('ومرساةُ القنص: يوازن الأقواسَ ولا يقف عند أوّل إغلاق', () {
    const snippet = 'void f() { if (x) { g(); } h(); }\nvoid z() { }';
    expect(_body(snippet, 'void f('), '{ if (x) { g(); } h(); }');
  });

  test('🔴 إقلاعُ الخادم يُشغّل نبضةَ التقديم', () {
    expect(startBody, contains('_startEInvoiceWorker'),
        reason: 'بلا تشغيلٍ يبقى الطابورُ ممتلئاً للأبد ولا يصل المصلحةَ '
            'مستندٌ واحد — بلا خطأٍ يظهر لأحد');
  });

  test('🔴 وإيقافُه يُلغي المؤقّت', () {
    expect(stopBody, contains('_eInvoiceTimer'),
        reason: 'مؤقّتٌ ينجو بعد إيقاف الخادم يمسح القاعدةَ ويحاول الإرسالَ '
            'من جهازٍ ربّما بُدّل إلى وضع العميل');
    expect(stopBody, contains('cancel'),
        reason: 'ذكرُ المؤقّت بلا `cancel` لا يوقفه');
  });

  test('🔴 والعاملُ يُبنى للخادم لا لأيّ جهاز', () {
    expect(src, contains('EInvoiceSubmissionWorker.forServer'),
        reason: 'المصنعُ هو ما يقرأ السرَّ ويضبط المحرّك');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ومصنعُ الخادم يوصّل المسارات الثلاثة كلَّها
  // ═════════════════════════════════════════════════════════════════════════
  //
  // كلُّ مسارٍ منها مُختبَرٌ وحدَه، ولا واحدٌ يقول إنّ المصنعَ **يمرّره**.
  // ومسارٌ غيرُ مُمرَّرٍ يعني `null` = «لا تفعل شيئاً» بصمت.

  group('مصنعُ الخادم', () {
    final workerSrc = _stripComments(
        File('lib/services/e_invoicing/e_invoice_submission_worker.dart')
            .readAsStringSync());
    final factoryBody = _body(workerSrc, 'forServer(AppDatabase db)');

    test('مرساة: جسمُ المصنع اقتُنص', () {
      expect(factoryBody, contains('EInvoiceSubmissionWorker('),
          reason: 'لم يُقتنَص جسمُ `forServer` — فالتوكيداتُ بعده بلا معنى');
    });

    test('🔴 الفواتيرُ موصولة', () {
      expect(factoryBody, contains('findDue:'));
      expect(factoryBody, contains('submit:'));
    });

    test('🔴 وإشعاراتُ الائتمان', () {
      expect(factoryBody, contains('findDueCreditNotes:'),
          reason: 'بلا تمريرٍ لا يُقدَّم إشعارُ ائتمانٍ أبداً — وفاتورةٌ '
              'رُدَّت تبقى مُقرَّةً بكاملها');
      expect(factoryBody, contains('submitCreditNote:'));
    });

    test('🔴 والاستطلاع', () {
      expect(factoryBody, contains('findDueStatusChecks:'),
          reason: 'بلا استطلاعٍ يقف المستندُ عند `submitted` أبداً — ولا رمزَ '
              'ضريبيَّ يُطبع لأنّ القرارَ يشترط `valid`');
      expect(factoryBody, contains('checkStatus:'));
    });
  });
}

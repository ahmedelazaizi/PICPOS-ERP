// حارسُ التوصيل: إيصالُ البيع في `printing_service` يحلّ قرارَ الرمز ويمرّره
// إلى **كلِّ** مسارِ رسمٍ يسقط إليه.
//
// ═══ فئةُ العطب ═══
//
// القرارُ (‏`resolveReceiptQr`) والراسمون الثلاثةُ كلُّهم يحترمونه — لكن
// إن لم يُحلَّ ويُمرَّر من موضع النداء فكلُّ ذلك ميّت: `null` يعني «السلوكُ
// القديم» = رقمُ الفاتورة بلا وسم، وهو عينُ العطب. وهذه فجوةٌ مقيسةٌ سلفاً
// في هذا المستودع: الشعارُ كان موصولاً في الراسم وغائباً عن المنادي في مسارٍ
// حيٍّ كامل.
//
// والأخطرُ أنّ المنادي يمرّر إلى **مسارين**: القالبِ، ثمّ `InvoiceGenerator`
// الذي يسقط إلى التخطيط المكتوب صامتاً. فالتمريرُ إلى أحدهما دون الآخر
// يترك بابَ الرمز غير الضريبيّ مفتوحاً في المسار الذي لا يراه أحد.
//
// والقياسُ على نداءِ إيصال البيع وحدَه (`documentType: 'sales_receipt'`):
// المستنداتُ الأخرى في نفس الملفّ ليست إيصالَ بيعٍ ولا يُطلب لها قرار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _file = 'lib/services/printing_service.dart';

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

/// يعيد نصَّ كلِّ نداءٍ لـ[callee] من قوسه الفاتح إلى قوسه المغلق الموازن.
///
/// مسحٌ بالأقواس لا بالتعبير النمطيّ: النداءُ يمتدّ عشراتِ الأسطر وفيه أقواسٌ
/// متداخلة (`map(...)`, `Value(...)`)، فلا يكفي «حتى أوّل `);`».
List<String> _callBlocks(String src, String callee) {
  final out = <String>[];
  var from = 0;
  while (true) {
    final i = src.indexOf('$callee(', from);
    if (i < 0) return out;
    var depth = 0;
    var j = i + callee.length;
    for (; j < src.length; j++) {
      final c = src[j];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.add(src.substring(i, j + 1));
    from = j + 1;
  }
}

void main() {
  final src = _stripComments(File(_file).readAsStringSync());

  final templateCalls = _callBlocks(src, 'TemplatedInvoiceService.printWithTemplate')
      .where((b) => b.contains("documentType: 'sales_receipt'"))
      .toList();
  final fallbackCalls =
      _callBlocks(src, 'InvoiceGenerator.printThermalReceipt');

  test('مرساة: الملفُّ موجودٌ ونداءا إيصال البيع فيه', () {
    expect(src.length, greaterThan(5000),
        reason: 'الملفُّ فارغٌ أو تحرّك — كلُّ حكمٍ بعده باطل');
    expect(templateCalls, hasLength(1),
        reason: 'نداءُ القالب لإيصال البيع واحدٌ بالضبط');
    expect(fallbackCalls, hasLength(1),
        reason: 'نداءُ السقوط لإيصال البيع واحدٌ بالضبط');
  });

  test('ومرساةُ المسح: يوازن الأقواسَ المتداخلة ولا يقف عند أوّل قوس', () {
    const snippet = 'x = f(a, g(b, c), h(i(j)));\nf(z);';
    final blocks = _callBlocks(snippet, 'f');
    expect(blocks, ['f(a, g(b, c), h(i(j)))', 'f(z)']);
  });

  test('🔴 القرارُ يُحلّ من القاعدة في مسار إيصال البيع', () {
    expect(src.contains('resolveReceiptQrForSale('), isTrue,
        reason: 'لا حلَّ ⇒ القرارُ `null` ⇒ رقمُ الفاتورة بلا وسم — عينُ العطب');
  });

  test('🔴 ويُمرَّر إلى مسار القالب', () {
    expect(templateCalls.single.contains('receiptQr:'), isTrue);
  });

  test('🔴 ويُمرَّر إلى مسار السقوط — الذي لا يراه أحد', () {
    expect(fallbackCalls.single.contains('receiptQr:'), isTrue,
        reason: 'السقوطُ إلى التخطيط المكتوب صامت؛ فبدون التمرير هنا يبقى '
            'بابُ الرمز غير الضريبيّ مفتوحاً حيث لا يُرى');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // والفاتورةُ المبدئيّةُ للطاولات — ورقةٌ ليست إيصالاً أصلاً
  // ═════════════════════════════════════════════════════════════════════════

  group('الفاتورةُ المبدئيّة', () {
    const proformaFile = 'lib/presentation/screens/tables/table_operations.dart';
    final proformaSrc = _stripComments(File(proformaFile).readAsStringSync());
    final proformaCalls =
        _callBlocks(proformaSrc, 'InvoiceGenerator.printThermalReceipt');

    test('مرساة: نداءُ طباعة المبدئيّة موجودٌ وواحد', () {
      expect(proformaCalls, hasLength(1),
          reason: 'لم يُقتنَص نداءُ الطباعة — فالتوكيدُ بعده بلا معنى');
      expect(proformaCalls.single, contains('فاتورةٌ مبدئيّةٌ'),
          reason: 'المقنوصُ ليس نداءَ المبدئيّة');
    });

    test('🔴 تحلّ قرارَ الرمز وتمرّره', () {
      expect(proformaSrc, contains('resolveReceiptQrForProforma('),
          reason: 'بلا حلٍّ تُطبع رقمُ الفاتورة بلا وسم — رمزٌ يبدو إيصالاً '
              'على ورقةٍ مكتوبٌ عليها «ليست إيصالَ سداد»');
      expect(proformaCalls.single.contains('receiptQr:'), isTrue);
    });

    test('🔴 ولا تسأل عن تقديمٍ ببيعةٍ لا وجودَ لها', () {
      expect(proformaSrc.contains('resolveReceiptQrForSale('), isFalse,
          reason: 'المبدئيّةُ لا صفَّ بيعٍ لها — والسؤالُ بمعرّفٍ مُختلَقٍ '
              'قد يقرأ تقديمَ فاتورةٍ أخرى');
    });
  });
}

// §٥-٣ — صفُّ عناوين أعمدة الجدول: **يُرسم أم لا؟**
//
// البلاغ الميدانيّ (2026-08-11): «صفُّ عناوين أعمدة الجدول لا يظهر في
// الطباعة».
//
// وهذا الملفُّ يكتب المستندَ إلى القرص كي **يُرسَّم ويُنظر إليه**، لا كي
// يُستنتج. سببُه أن حراسَ المطبوع كلَّها كانت بنيويةً — تقرأ المصدرَ ولا ترى
// ورقة — وفي هذا المستودع فرضياتٌ معقولةٌ ثلاثٌ عن الطباعة كذّبها الرسمُ
// وحدَه.
//
// المخرَج: `build/receipt_header_probe.pdf`

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('يكتب جدولَ الأصناف كما يُرسَم فعلاً', () async {
    final bytes = await TemplatedInvoiceService.debugRenderItemsTable(
      items: [
        {
          'name': 'جبنة رومي صبري',
          'code': 'P-001',
          'quantity': 2.0,
          'price': 125.5,
          'discount': 0.0,
          'tax': 0.0,
          'total': 251.0,
        },
        {
          'name': 'زيت عافية ١ لتر',
          'code': 'P-002',
          'quantity': 3.0,
          'price': 90.0,
          'discount': 5.0,
          'tax': 0.0,
          'total': 265.0,
        },
      ],
    );

    final out = File('build/receipt_header_probe.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);

    expect(bytes.lengthInBytes, greaterThan(500),
        reason: 'وثيقةٌ فارغةٌ تعني أن الجدولَ لم يُبنَ أصلاً');
    // ignore: avoid_print
    print('PDF => ${out.absolute.path} (${bytes.lengthInBytes} bytes)');
  });

  test('الوجهُ العريضُ محمَّلٌ فعلاً — لا خاصيةً بلا ملفّ', () async {
    // الحزمةُ **لا تصطنع** العريض (‏`base_generator.dart:44`): بلا وجهٍ
    // عريضٍ محمَّلٍ يسقط `FontWeight.bold` على العاديّ بلا أثر. ورسمُ
    // الإيصال أرى ذلك بالعين قبل هذا الإصلاح: العناوينُ بوزن البدن نفسِه.
    //
    // والقياسُ باسم الوجه المضمَّن في الوثيقة لا بحجمها: الحجمُ يتعلّق
    // بالمحتوى (‏عتبةٌ بالبايت سقطت أمام صنفٍ واحدٍ قصيرِ الاسم)، واسمُ
    // الوجه لا يتعلّق إلا بما حُمِّل فعلاً.
    final bytes = await TemplatedInvoiceService.debugRenderItemsTable(
      items: [
        {
          'name': 'صنف',
          'quantity': 1.0,
          'price': 1.0,
          'discount': 0.0,
          'tax': 0.0,
          'total': 1.0,
        },
      ],
    );

    final raw = String.fromCharCodes(bytes);
    expect(raw.contains('Bold'), isTrue,
        reason: 'لا وجهَ عريضٌ مضمَّنٌ في الوثيقة ⇒ `FontWeight.bold` ساقطٌ '
            'على العاديّ، فصفُّ العناوين بلا تعبئةٍ ولا وزنٍ يذوب في البدن');
  });
}

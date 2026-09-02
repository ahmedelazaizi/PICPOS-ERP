// إلغاءُ حوار الطباعة ليس نجاحاً — عقدُ القمع الوحيد.
//
// ═══ فئةُ العطب — مقيسةٌ 2026-09-02 ═══
//
// `Printing.layoutPdf` تُرجع `bool`: `true` قُبلت المهمّةُ و`false` ألغى
// المستخدم. وكانت القيمةُ تُهمَل في `PdfComputeHelper` وفي ثلاثةَ عشرَ نداءً
// مباشراً — ٤٩ موضعاً في ١٨ ملفّاً — فمن ضغط «إلغاء» في حوار النظام رأى
// «تمّت الطباعة»، **وسُجِّل له سطرُ تدقيقٍ يقول إنّ المستندَ طُبع**.
//
// ═══ ما يُقاس هنا ═══
//
// الحوارُ الأصليُّ يحتاج قناةَ منصّةٍ فلا يعمل في اختبار وحدة؛ فالبديلُ
// `nativeLayoutOverride` يمثّله. والعقدُ ثلاثةُ أشياء:
//   ١) `false` من الحوار ⇒ `false` من القمع.
//   ٢) و**لا** نداءَ لخطّاف التسجيل عند الإلغاء — هذا هو السطرُ الكاذب.
//   ٣) و`true` ⇒ `true` والخطّافُ يُنادى مرّةً واحدةً بالاسم.
//
// ⚠️ والمرساةُ في (٣): لو كان الخطّافُ لا يُنادى أصلاً لمرّ (٢) أخضرَ
//    فارغاً. فالاتّجاهان معاً أو لا شيء.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ural_erp/services/printing/pdf_compute_helper.dart';

void main() {
  final hookCalls = <String>[];

  setUp(() {
    hookCalls.clear();
    PdfComputeHelper.onPrinted = (label) async => hookCalls.add(label);
  });

  tearDown(() {
    PdfComputeHelper.onPrinted = null;
    PdfComputeHelper.nativeLayoutOverride = null;
  });

  pw.Document doc() => pw.Document()
    ..addPage(pw.Page(build: (_) => pw.Text('x')));

  test('مرساة: قبولُ الحوار ⇒ true وخطّافُ التسجيل يُنادى مرّةً بالاسم',
      () async {
    PdfComputeHelper.nativeLayoutOverride = (bytes, name) async {
      expect(bytes, isNotEmpty, reason: 'البايتاتُ تصل الحوارَ فعلاً');
      return true;
    };

    final printed =
        await PdfComputeHelper.layoutPdf(doc(), documentLabel: 'تقرير');

    expect(printed, isTrue);
    expect(hookCalls, ['تقرير'],
        reason: 'الخطّافُ لا يُنادى أصلاً ⇒ فحصُ الإلغاء أدناه فارغُ المعنى');
  });

  test('🔴 إلغاءُ الحوار ⇒ false — ولا سطرَ تسجيلٍ يدّعي طباعة', () async {
    PdfComputeHelper.nativeLayoutOverride = (bytes, name) async => false;

    final printed =
        await PdfComputeHelper.layoutPdf(doc(), documentLabel: 'تقرير');

    expect(printed, isFalse,
        reason: 'القمعُ يُهمل ردَّ الحوار ⇒ كلُّ شاشةٍ تطبع تقول «تمّت '
            'الطباعة» لمن ألغى.');
    expect(hookCalls, isEmpty,
        reason: 'سُجِّل سطرُ «طُبع المستند» لطباعةٍ أُلغيت — سجلُّ الطباعة '
            'يكذب على المراجع.');
  });

  test('وبلا وسمٍ لا تسجيلَ حتى عند القبول — عقدُ الفواتير', () async {
    // الفواتيرُ تسجّلها `PrintingServiceImpl` بمعرِّفها ومبلغها؛ سطرٌ ثانٍ
    // من هنا يكتب طباعةً واحدةً مرّتين.
    PdfComputeHelper.nativeLayoutOverride = (bytes, name) async => true;

    expect(await PdfComputeHelper.layoutPdf(doc()), isTrue);
    expect(hookCalls, isEmpty);
  });

  test('و`layoutBytes` يمرّر الاسمَ إلى الحوار', () async {
    String? seen;
    PdfComputeHelper.nativeLayoutOverride = (bytes, name) async {
      seen = name;
      return true;
    };
    await PdfComputeHelper.layoutBytes(
      await PdfComputeHelper.saveToBytes(doc()),
      name: 'Barcode_123_x2',
    );
    expect(seen, 'Barcode_123_x2');
  });
}

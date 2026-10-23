// فاتورةُ A4 تنقسم صفحاتٍ — لا ورقةً واحدةً بلا نهاية.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// المُصيِّرُ كان يبني كلَّ مستندٍ بـ`pw.Page` وارتفاعٍ `double.infinity`:
//     PdfPageFormat(canvasWidth, double.infinity, marginAll: …)
// وهو الصوابُ للورق الحراريّ — لفّةٌ مستمرّةٌ تُقصّ عند آخر سطر. أمّا A4
// فورقٌ مقصوصٌ سلفاً بارتفاعٍ ثابت، و`paperHeight = 297` مخزَّنٌ في القالب
// (`invoice_template_seeder_dao.dart`) و**لا يُقرأ في أيّ موضع**.
//
// فستّون صنفاً تخرج صفحةً واحدةً يمتدّ طولُها بعددها: لا فواصلَ صفحات، ولا
// تكرارَ لصفّ عناوين الأعمدة، ولا ترقيم. والطابعةُ تقصّها حيث اتّفق أو
// تضغطها في صفحة.
//
// ── وحارسُ الحراريّ لازم ──────────────────────────────────────────────────
// الإصلاحُ يجب ألّا يمسّ الإيصالَ الحراريّ: تقسيمُ لفّةٍ مستمرّةٍ إلى صفحاتٍ
// بارتفاعٍ ثابتٍ يُخرج ورقاً أبيضَ بين الإيصالات. فالضابطُ هنا ليس زينةً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> items(int n) => List.generate(
        n,
        (i) => {
          'name': 'صنفٌ تجريبيٌّ باسمٍ طويلٍ نسبياً رقم ${i + 1}',
          'code': 'P-${(i + 1).toString().padLeft(4, '0')}',
          'quantity': 2.0,
          'price': 125.5,
          'discount': 0.0,
          'tax': 0.0,
          'total': 251.0,
        },
      );

  test('ستّون صنفاً على A4 تخرج في أكثرَ من صفحة', () async {
    final pages = await TemplatedInvoiceService.debugPageCount(
      items: items(60),
      paperWidthMm: 210,
      paperHeightMm: 297,
    );

    expect(pages, greaterThan(1),
        reason: 'ورقةٌ واحدةٌ ممتدّةٌ بلا نهاية — `paperHeight` لا يُقرأ');
  });

  test('صنفان على A4 يكفيهما صفحةٌ واحدة', () async {
    final pages = await TemplatedInvoiceService.debugPageCount(
      items: items(2),
      paperWidthMm: 210,
      paperHeightMm: 297,
    );

    expect(pages, 1);
  });

  test('ضابط: الحراريُّ يبقى لفّةً مستمرّةً مهما طال', () async {
    // ورقُ ٨٠mm لا ارتفاعَ له — تقسيمُه يُخرج بياضاً بين الإيصالات.
    final pages = await TemplatedInvoiceService.debugPageCount(
      items: items(60),
      paperWidthMm: 80,
      paperHeightMm: null,
    );

    expect(pages, 1);
  });

  test('يكتب مستنداً على القرص كي يُنظر إليه', () async {
    final bytes = await TemplatedInvoiceService.debugRenderPaginated(
      items: items(60),
      paperWidthMm: 210,
      paperHeightMm: 297,
    );

    final out = File('build/a4_pagination_probe.pdf');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes);

    expect(bytes.length, greaterThan(1000));
    // تكرارُ صفّ العناوين لا يُقاس آلياً من بايتات مضغوطة — يُنظر إليه هنا.
  });
}

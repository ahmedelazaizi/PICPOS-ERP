// إضافاتُ الصنف وخياراتُه على المطبوع.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// محرِّرُ القوالب يعرض عنصرَي `item_additions` و`item_options` ويعاينهما
// («الإضافات: كاتشب، مايونيز»)، والرسّامُ لا يعرفهما — فيسقطان على
// `default` ويرجعان `SizedBox()` أي **يختفيان**.
//
// ── مصدرُ البيانات ────────────────────────────────────────────────────────
// السلّةُ تركّب الاختياراتِ في نصٍّ واحدٍ (`composeCartItemNote`) يُخزَّن في
// `sales_invoice_items.note` ويصل المطبوعَ في `item['note']`:
//
//   الخيار  ⇒ `(اسمُ المجموعة: [مستوى] الاسم)`   — بين قوسين
//   الإضافة ⇒ `+الاسم [سعر عملة]`                 — بادئتُها +
//   ملاحظةُ الكاشير ⇒ `📝 نصّ`
//   والفصلُ بـ` | `
//
// فالاستخراجُ حتميٌّ من هذا الشكل. والملاحظةُ اليدوية **لا** تُخلط بهما:
// «بدون بصل» ليست إضافةً ولا خياراً، وخلطُها يجعل المطبخَ يقرأ طلباً
// لم يُطلب.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

List<Map<String, dynamic>> _items(List<String?> notes) => [
      for (final n in notes)
        <String, dynamic>{'name': 'صنف', 'quantity': 1, 'price': 1, 'note': n},
    ];

void main() {
  group('استخراجُ الإضافات', () {
    test('تلتقط ما بادئتُه + وتُسقط السعر', () {
      final out = TemplatedInvoiceService.extractItemAdditions(
          _items(['+كاتشب | +مايونيز 5 EGP']));
      expect(out, 'كاتشب، مايونيز');
    });

    test('لا تلتقط الخيارات ولا ملاحظةَ الكاشير', () {
      final out = TemplatedInvoiceService.extractItemAdditions(
          _items(['(الحجم: كبير) | +جبنة | 📝 بدون بصل']));
      expect(out, 'جبنة',
          reason: '«بدون بصل» ملاحظةٌ لا إضافة، و«كبير» خيارٌ لا إضافة — '
              'خلطُها يجعل المطبخَ يقرأ طلباً لم يُطلب');
    });

    test('تجمع من كلّ البنود بلا تكرار', () {
      final out = TemplatedInvoiceService.extractItemAdditions(
          _items(['+جبنة', '+جبنة | +زيتون']));
      expect(out, 'جبنة، زيتون');
    });

    test('بلا إضافاتٍ ترجّع فارغاً — فيختفي العنصرُ بدل سطرٍ أجوف', () {
      expect(TemplatedInvoiceService.extractItemAdditions(_items([null, ''])),
          isEmpty);
      expect(
          TemplatedInvoiceService.extractItemAdditions(
              _items(['📝 ملاحظة فقط'])),
          isEmpty);
    });
  });

  group('استخراجُ الخيارات', () {
    test('تلتقط ما بين القوسين بمستواه', () {
      final out = TemplatedInvoiceService.extractItemOptions(
          _items(['(الحجم: كبير) | (الصلصة: قليل بندورة)']));
      expect(out, 'كبير، قليل بندورة');
    });

    test('لا تلتقط الإضافات ولا الملاحظة', () {
      final out = TemplatedInvoiceService.extractItemOptions(
          _items(['+جبنة | (الحجم: وسط) | 📝 سريع']));
      expect(out, 'وسط');
    });

    test('بلا خياراتٍ ترجّع فارغاً', () {
      expect(TemplatedInvoiceService.extractItemOptions(_items(['+جبنة'])),
          isEmpty);
    });
  });

  test('ضابط: نصٌّ حرٌّ بلا علاماتٍ لا يُقرأ إضافةً ولا خياراً', () {
    // لولا هذا لمرّ الحلُّ بإرجاع الملاحظة كلها في الاثنين.
    final free = _items(['ملاحظة حرة بلا رموز']);
    expect(TemplatedInvoiceService.extractItemAdditions(free), isEmpty);
    expect(TemplatedInvoiceService.extractItemOptions(free), isEmpty);
  });
}

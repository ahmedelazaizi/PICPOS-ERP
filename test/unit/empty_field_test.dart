// حقلٌ بلا قيمةٍ لا يطبع تسميةً معلَّقة، وعنصرٌ لم يتحقّق شرطُه لا يُطبع.
//
// ── العطبُ الذي يمنعه — مرصودٌ ميدانيّاً ─────────────────────────────────
// إيصالٌ مطبوعٌ (2026-08-11) حمل «الكاشير:» و«المخزن:» — تسمياتٍ بلا قيم.
// وتسميةٌ وحدَها **أسوأُ من لا شيء**: القارئُ يظنّ البيانَ ناقصاً لا الحقلَ
// غيرَ مفعَّل. الحارسُ البنيويُّ الحاليُّ يمنع عودةَ الشرط `&&` في الراسم
// القديم؛ وهذا يقيس السلوكَ في المحرّك الجديد.
//
// والنصُّ الثابتُ (‏`contentKey` فارغ) يبقى — «شكراً لزيارتكم» ليس حقلاً
// بلا قيمةٍ بل نصٌّ هو نفسُه القيمة. خلطُ الاثنين يمحو تذييلَ كلِّ إيصال.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

TemplateDocument _doc(List<TemplateElement> elements) => TemplateDocument(
      paper: _a4,
      bands: [TemplateBand(id: BandId.totals, heightMm: 40, elements: elements)],
    );

Set<String> _idsOn(TemplateDocument doc, Map<String, String> values) =>
    LayoutEngine.paginate(document: doc, rows: const [], values: values)
        .single
        .elements
        .map((e) => e.id)
        .toSet();

void main() {
  group('التسميةُ المعلَّقة', () {
    final doc = _doc(const [
      TemplateElement(
        id: 'cashier',
        contentKey: 'cashier_name',
        xMm: 0,
        yMm: 0,
        wMm: 60,
        hMm: 6,
        labelAr: 'الكاشير',
      ),
      TemplateElement(
        id: 'total',
        contentKey: 'total_amount',
        xMm: 0,
        yMm: 10,
        wMm: 60,
        hMm: 6,
        labelAr: 'الإجمالي',
      ),
    ]);

    test('حقلٌ بقيمةٍ فارغةٍ يسقط ولو كانت له تسمية', () {
      expect(
        _idsOn(doc, {'cashier_name': '', 'total_amount': '250.00'}),
        {'total'},
        reason: '«الكاشير:» بلا قيمةٍ هو عينُ ما رُصد على ورقٍ حقيقيّ',
      );
    });

    test('وحقلٌ غائبٌ عن الخريطة أصلاً يسقط كذلك', () {
      expect(_idsOn(doc, {'total_amount': '250.00'}), {'total'});
    });

    test('وبقيمةٍ حاضرةٍ يظهر الاثنان', () {
      // الضابط: لولاه لمرّ ما سبق على محرّكٍ يحذف كلَّ شيء.
      expect(
        _idsOn(doc, {'cashier_name': 'أحمد', 'total_amount': '250.00'}),
        {'cashier', 'total'},
      );
    });

    test('والصفرُ قيمةٌ لا فراغ', () {
      expect(
        _idsOn(doc, {'cashier_name': 'أحمد', 'total_amount': '0'}),
        {'cashier', 'total'},
        reason: 'إجماليٌّ صفرٌ يُطبع — حذفُه يخفي فاتورةً مجّانيّةً مشروعة',
      );
    });
  });

  test('النصُّ الثابتُ يبقى ولو لم تُمرَّر له قيمة', () {
    final doc = _doc(const [
      TemplateElement(
        id: 'thanks',
        contentKey: '',
        xMm: 0,
        yMm: 0,
        wMm: 60,
        hMm: 6,
        labelAr: 'شكراً لزيارتكم',
      ),
    ]);

    expect(
      _idsOn(doc, const {}),
      {'thanks'},
      reason: 'النصُّ الثابتُ هو نفسُه القيمة — خلطُه بالحقلِ الفارغ يمحو '
          'تذييلَ كلِّ إيصال',
    );
  });

  group('شرطُ الإظهار', () {
    TemplateDocument condDoc() => _doc(const [
          TemplateElement(
            id: 'discount_line',
            contentKey: 'discount',
            xMm: 0,
            yMm: 0,
            wMm: 60,
            hMm: 6,
            labelAr: 'الخصم',
            condition: 'discount > 0',
          ),
          TemplateElement(
            id: 'total',
            contentKey: 'total_amount',
            xMm: 0,
            yMm: 10,
            wMm: 60,
            hMm: 6,
          ),
        ]);

    test('بلا خصمٍ يغيب سطرُ الخصم', () {
      expect(
        _idsOn(condDoc(), {'discount': '0', 'total_amount': '200'}),
        {'total'},
      );
    });

    test('وبخصمٍ يظهر', () {
      expect(
        _idsOn(condDoc(), {'discount': '15', 'total_amount': '200'}),
        {'discount_line', 'total'},
      );
    });

    test('وغيابُه لا يزحزح ما بعده — الإحداثيُّ مطلقٌ داخلَ النطاق', () {
      final withDiscount = LayoutEngine.paginate(
        document: condDoc(),
        rows: const [],
        values: {'discount': '15', 'total_amount': '200'},
      ).single.elements.firstWhere((e) => e.id == 'total').yMm;

      final without = LayoutEngine.paginate(
        document: condDoc(),
        rows: const [],
        values: {'discount': '0', 'total_amount': '200'},
      ).single.elements.firstWhere((e) => e.id == 'total').yMm;

      expect(withDiscount, without,
          reason: 'العنصرُ المحذوفُ لا يترك فراغاً ولا يسحب ما بعده');
    });
  });
}

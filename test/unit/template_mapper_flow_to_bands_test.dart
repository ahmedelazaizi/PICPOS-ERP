// اشتقاقُ النطاقات من التدفّق — **بلا تغييرِ مطبوعٍ واحد**.
//
// ── القاعدةُ الحاكمة ──────────────────────────────────────────────────────
// القالبُ الذي لم يمسّه المستخدمُ يجب أن يطبع بعد الهجرة نفسَ ما كان يطبعه
// قبلها. ولذلك الهجرةُ **لا تقرأ `xPosition`/`yPosition` إطلاقاً**: الراسمُ
// القديمُ كان يتجاهلهما ويبني تدفّقاً من `sortOrder` + `flexWidth`، فقراءتُهما
// الآن تعني تحريكَ عناصرَ لم تتحرّك يوماً على الورق.
//
// المواضعُ تُشتقّ من التدفّق نفسِه: `flexWidth` نسبةً من العرض المتاح،
// و`sortOrder` ترتيباً، والصفُّ يُغلَق حين يبلغ مجموعُ النسب مئة.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/domain/printing/template_mapper.dart';

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

LegacyElement _e(
  String type, {
  String? content,
  String section = 'body',
  int sortOrder = 0,
  double flexWidth = 100,
  double fontSize = 10,
}) =>
    LegacyElement(
      elementType: type,
      content: content,
      section: section,
      sortOrder: sortOrder,
      flexWidth: flexWidth,
      fontSize: fontSize,
    );

TemplateBand _band(TemplateDocument d, BandId id) => d.bandById(id)!;

void main() {
  group('توزيعُ العرض من flexWidth', () {
    test('عنصران بـ٥٠٪ يتقاسمان الصفَّ ولا يتراكبان', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('invoice_number',
              content: 'invoice_number', sortOrder: 0, flexWidth: 50),
          _e('date', content: 'date', sortOrder: 1, flexWidth: 50),
        ],
      );

      final els = _band(doc, BandId.info).elements;
      expect(els, hasLength(2));

      // العرضُ المتاح ١٩٠مم ⇒ ٩٥ لكلٍّ منهما.
      expect(els[0].xMm, 0);
      expect(els[0].wMm, 95);
      expect(els[1].xMm, 95);
      expect(els[1].wMm, 95);

      expect(els[0].yMm, els[1].yMm,
          reason: 'عنصرا صفٍّ واحدٍ على نفس الارتفاع');
    });

    // ⚠️ المفتاحان كلاهما من نطاق «البيانات» عمداً. كان الأوّلُ
    //    `company_name` — ومنذ صار المُخطِّطُ يشتقّ النطاقَ من المفتاح لم
    //    يعد يقع في `info` أصلاً بل في `header`، فسقط الاختبارُ بـRangeError
    //    لا بخللٍ في رصّ الصفوف. وموضوعُ هذا الاختبار **الرصُّ** لا التوزيع،
    //    فالمفتاحُ تفصيلٌ فيه: يُبدَّل ولا يُضعَّف التوكيد.
    test('عنصرٌ بـ١٠٠٪ ينفرد بصفِّه ويدفع ما بعده لأسفل', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('invoice_number', content: 'invoice_number', sortOrder: 0),
          _e('date', content: 'date', sortOrder: 1),
        ],
      );

      final els = _band(doc, BandId.info).elements;
      expect(els[0].wMm, 190);
      expect(els[1].yMm, greaterThan(els[0].yMm),
          reason: 'العنصرُ التالي في صفٍّ جديدٍ لا فوقَ سابقه');
      expect(els[1].xMm, 0);
    });

    test('ثلاثةٌ بـ٣٣٪ ثمّ رابعٌ — الرابعُ في صفٍّ جديد', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('a', content: 'a', sortOrder: 0, flexWidth: 33),
          _e('b', content: 'b', sortOrder: 1, flexWidth: 33),
          _e('c', content: 'c', sortOrder: 2, flexWidth: 33),
          _e('d', content: 'd', sortOrder: 3, flexWidth: 50),
        ],
      );

      final els = _band(doc, BandId.info).elements;
      expect(els[0].yMm, els[1].yMm);
      expect(els[1].yMm, els[2].yMm);
      expect(els[3].yMm, greaterThan(els[2].yMm));
      expect(els[3].xMm, 0, reason: 'الصفُّ الجديد يبدأ من حافّة النطاق');
    });

    test('الترتيبُ من sortOrder لا من ترتيب الإدخال', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('second', content: 'second', sortOrder: 5),
          _e('first', content: 'first', sortOrder: 1),
        ],
      );

      final els = _band(doc, BandId.info).elements;
      expect(els.map((e) => e.contentKey).toList(), ['first', 'second']);
      expect(els[0].yMm, lessThan(els[1].yMm));
    });
  });

  group('توزيعُ العناصر على النطاقات', () {
    test('`body` ينقسم إلى info ثمّ party بمفاتيحِ الطرف المعروفة', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('invoice_number', content: 'invoice_number', sortOrder: 0),
          _e('customer_name', content: 'customer_name', sortOrder: 1),
        ],
      );

      expect(
        _band(doc, BandId.info).elements.map((e) => e.contentKey),
        ['invoice_number'],
      );
      expect(
        _band(doc, BandId.party).elements.map((e) => e.contentKey),
        ['customer_name'],
      );
    });

    test('`footer` ينقسم إلى totals ثمّ footer بمفاتيحِ المجاميع', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('total', content: 'total_amount', section: 'footer', sortOrder: 0),
          _e('footer', content: 'شكراً', section: 'footer', sortOrder: 1),
        ],
      );

      expect(
        _band(doc, BandId.totals).elements.map((e) => e.contentKey),
        ['total_amount'],
      );
      expect(_band(doc, BandId.footer).elements, hasLength(1));
    });

    test('`header` و`details` يمرّان كما هما', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [
          _e('company_name', content: 'company_name', section: 'header'),
          _e('items_table', content: 'items_table', section: 'details'),
        ],
      );

      expect(_band(doc, BandId.header).elements, hasLength(1));
      expect(_band(doc, BandId.details).elements, hasLength(1));
    });
  });

  group('أعلامُ النطاقات', () {
    final doc = TemplateMapper.fromLegacy(paper: _a4, elements: [
      _e('company_name', content: 'company_name', section: 'header'),
      _e('items_table', content: 'items_table', section: 'details'),
      _e('footer', content: 'شكراً', section: 'footer'),
    ]);

    test('details وحدَه يتمدّد بالبيانات', () {
      for (final b in doc.bands) {
        expect(b.growsWithData, b.id == BandId.details,
            reason: 'النطاق ${b.id.name}');
      }
    });

    test('الرأسُ والتذييلُ وحدَهما يتكرّران', () {
      for (final b in doc.bands) {
        expect(b.repeatEachPage, b.id.repeatsByDefault,
            reason: 'النطاق ${b.id.name}');
      }
    });
  });

  group('العنصرُ بلا content — القوالبُ المبذورةُ الثمانية', () {
    // العطبُ المرصود: `assets/invoice_templates/*.json` تكتب
    // {"type":"company_name"} بلا `content`، و`_fullSyncWithElements` يفهرس
    // بـ`content` — فالحقلُ يُطبع على الورق والمحرّرُ يعتبره مخفيّاً.
    test('يُستنتَج المفتاحُ من elementType فيصير مرئيّاً في المحرّر', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [_e('company_name', section: 'header')],
      );

      expect(
        _band(doc, BandId.header).elements.single.contentKey,
        'company_name',
        reason: 'هذا وحدَه ما يجعل القوالبَ الثمانيةَ مرئيّةً في المحرّر '
            'لأوّل مرّة',
      );
    });

    test('و`text` بمحتوىً حرٍّ يبقى نصّاً ثابتاً بمفتاحٍ فارغ', () {
      final doc = TemplateMapper.fromLegacy(
        paper: _a4,
        elements: [_e('text', content: 'شكراً لزيارتكم', section: 'footer')],
      );

      final el = _band(doc, BandId.footer).elements.single;
      expect(el.contentKey, isEmpty,
          reason: 'النصُّ الثابتُ ليس حقلاً — ومفتاحٌ له يجعله يسقط بقاعدة '
              '«لا تسميةَ معلَّقة»');
      expect(el.labelAr, 'شكراً لزيارتكم');
    });
  });

  test('ارتفاعُ النطاق يساوي ما شغلته صفوفُه', () {
    final one = TemplateMapper.fromLegacy(
      paper: _a4,
      elements: [_e('a', content: 'a', section: 'header', sortOrder: 0)],
    );
    final three = TemplateMapper.fromLegacy(
      paper: _a4,
      elements: [
        _e('a', content: 'a', section: 'header', sortOrder: 0),
        _e('b', content: 'b', section: 'header', sortOrder: 1),
        _e('c', content: 'c', section: 'header', sortOrder: 2),
      ],
    );

    final h1 = _band(one, BandId.header).heightMm;
    final h3 = _band(three, BandId.header).heightMm;

    expect(h1, greaterThan(0));
    expect(h3, greaterThan(h1),
        reason: 'ارتفاعٌ ثابتٌ يقصّ العناصرَ الزائدة أو يترك فراغاً ميّتاً');
  });
}

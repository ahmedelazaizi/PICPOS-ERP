// test/unit/template_edits_test.dart
//
// عمليّاتُ التحرير — خالصةٌ، فتُقاس بلا شاشةٍ ولا قاعدة.
//
// ⚠️ وأهمُّ ما فيها **القصُّ عند الحدود**: عنصرٌ يخرج من نطاقه يُرسم فوق
// النطاق التالي أو خارجَ الورقة، والراسمُ يقصّه صامتاً. فكلُّ عمليّةٍ هنا
// تُقاس عند حدَّيها لا في وسطها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/domain/printing/template_edits.dart';

const _margins = MarginsMm(top: 10, right: 10, bottom: 10, left: 10);

TemplateDocument _doc({double paperWidth = 210}) => TemplateDocument(
      paper: PaperSpec(
          widthMm: paperWidth, heightMm: 297, margins: _margins),
      bands: const [
        TemplateBand(id: BandId.header, heightMm: 30, elements: [
          TemplateElement(
              id: 'a',
              contentKey: 'company_name',
              xMm: 10,
              yMm: 4,
              wMm: 60,
              hMm: 8,
              labelAr: 'اسم الشركة'),
        ]),
        TemplateBand(id: BandId.details, heightMm: 100, growsWithData: true),
      ],
      table: const TableSpec(columns: [
        TableColumn(key: 'index', labelAr: 'م', flex: 0.8),
        TableColumn(key: 'name', labelAr: 'الصنف', flex: 3),
        TableColumn(key: 'total', labelAr: 'الإجمالي', flex: 1.5),
      ]),
    );

TemplateElement _el(TemplateDocument d, [String id = 'a']) => d.bands
    .expand((b) => b.elements)
    .firstWhere((e) => e.id == id);

void main() {
  group('التحريكُ محصورٌ داخل النطاق', () {
    test('حركةٌ عاديّةٌ تُطبَّق بالمليمتر', () {
      final d = moveElement(_doc(),
          bandId: BandId.header, elementId: 'a', xMm: 20, yMm: 10);
      expect(_el(d).xMm, 20);
      expect(_el(d).yMm, 10);
    });

    test('ولا يخرج من الحافّة اليمنى — عرضُ المحتوى ١٩٠ لا ٢١٠', () {
      // ‏٢١٠ − هامشَي ١٠ = ١٩٠. وعنصرٌ عرضُه ٦٠ لا يبدأ بعد ١٣٠.
      final d = moveElement(_doc(),
          bandId: BandId.header, elementId: 'a', xMm: 400, yMm: 0);
      expect(_el(d).xMm, 130,
          reason: 'الحدُّ هو عرضُ المحتوى ناقصَ عرضِ العنصر');
    });

    test('ولا يخرج من قاع النطاق', () {
      // نطاقٌ ٣٠ وعنصرٌ ٨ ⇒ أقصى `y` = ٢٢.
      final d = moveElement(_doc(),
          bandId: BandId.header, elementId: 'a', xMm: 0, yMm: 900);
      expect(_el(d).yMm, 22);
    });

    test('ولا يسبق الحافّةَ — لا إحداثيَّ سالب', () {
      final d = moveElement(_doc(),
          bandId: BandId.header, elementId: 'a', xMm: -50, yMm: -50);
      expect(_el(d).xMm, 0);
      expect(_el(d).yMm, 0);
    });

    test('والمحاذاةُ للشبكة تقرّب لأقرب ٢مم', () {
      final d = moveElement(_doc(),
          bandId: BandId.header, elementId: 'a', xMm: 23.4, yMm: 9.1);
      expect(d.bands.first.elements.first.xMm, 24);
      expect(d.bands.first.elements.first.yMm, 10);
    });

    test('وبإطفائها تُحفظ العُشور', () {
      final d = moveElement(_doc(),
          bandId: BandId.header,
          elementId: 'a',
          xMm: 23.44,
          yMm: 9.16,
          snap: false);
      expect(_el(d).xMm, 23.4);
      expect(_el(d).yMm, 9.2);
    });
  });

  group('التحجيمُ له حدٌّ أدنى وحدٌّ أعلى', () {
    test('لا يقلّ عن ٨×٤', () {
      final d = resizeElement(_doc(),
          bandId: BandId.header, elementId: 'a', wMm: 1, hMm: 1);
      expect(_el(d).wMm, minElementWidthMm);
      expect(_el(d).hMm, minElementHeightMm);
    });

    test('ولا يتجاوز عرضَ المحتوى من موضعه', () {
      // العنصرُ عند `x = 10` وعرضُ المحتوى ١٩٠ ⇒ أقصى عرضٍ ١٨٠.
      final d = resizeElement(_doc(),
          bandId: BandId.header, elementId: 'a', wMm: 500, hMm: 8);
      expect(_el(d).wMm, 180);
    });

    test('ولا يتجاوز قاعَ النطاق من موضعه', () {
      // العنصرُ عند `y = 4` والنطاقُ ٣٠ ⇒ أقصى ارتفاعٍ ٢٦.
      final d = resizeElement(_doc(),
          bandId: BandId.header, elementId: 'a', wMm: 60, hMm: 500);
      expect(_el(d).hMm, 26);
    });
  });

  group('خصائصُ العنصر', () {
    test('التسميةُ تُكتب وتصل العنصرَ', () {
      final d = editElement(_doc(),
          bandId: BandId.header, elementId: 'a', labelAr: 'البيان',
          labelEn: 'Item');
      expect(_el(d).labelAr, 'البيان');
      expect(_el(d).labelEn, 'Item');
    });

    test('وحجمُ الخطّ محصورٌ بين ٤ و٤٨', () {
      expect(
          _el(editElement(_doc(),
                  bandId: BandId.header, elementId: 'a', fontSize: 0))
              .fontSize,
          minFontSize);
      expect(
          _el(editElement(_doc(),
                  bandId: BandId.header, elementId: 'a', fontSize: 900))
              .fontSize,
          maxFontSize);
    });

    test('والشرطُ يُكتب ويُمحى', () {
      var d = editElement(_doc(),
          bandId: BandId.header, elementId: 'a', condition: 'discount > 0');
      expect(_el(d).condition, 'discount > 0');

      d = editElement(d,
          bandId: BandId.header, elementId: 'a', condition: '');
      expect(_el(d).condition, isEmpty,
          reason: 'شرطٌ لا يُمحى يعني عنصراً لا يعود يظهر أبداً');
    });

    test('والحذفُ يزيل العنصرَ من نطاقه وحدَه', () {
      final d = removeElement(_doc(),
          bandId: BandId.header, elementId: 'a');
      expect(d.bands.first.elements, isEmpty);
      expect(d.bands, hasLength(2), reason: 'النطاقُ لا يُحذف مع عنصره');
    });
  });

  group('الإضافةُ لا تُسقط عنصراً فوق آخر', () {
    test('العنصرُ الجديدُ يقع أسفلَ آخرِ ما في النطاق', () {
      final d = addElement(_doc(),
          bandId: BandId.header,
          id: 'new:1',
          contentKey: 'company_phone',
          hMm: 6);
      final added = _el(d, 'new:1');
      expect(added.yMm, 12, reason: '‏٤ + ٨ = ١٢ — أسفلَ العنصر القائم');
    });

    test('وما لا يسعه الارتفاعُ يُوضع في الأعلى لا خارجَ النطاق', () {
      var d = _doc();
      // نملأ الرأسَ حتى قاعه.
      d = resizeElement(d,
          bandId: BandId.header, elementId: 'a', wMm: 60, hMm: 26);
      d = addElement(d,
          bandId: BandId.header, id: 'new:1', contentKey: 'x', hMm: 6);
      final added = _el(d, 'new:1');
      expect(added.yMm, 0);
      expect(added.yMm + added.hMm, lessThanOrEqualTo(30));
    });
  });

  group('الجدولُ — والعمودُ الأخيرُ لا يُطفأ', () {
    test('التبديلُ يُخفي ويُظهر', () {
      final d = toggleColumn(_doc(), 'index');
      expect(d.table!.columns.firstWhere((c) => c.key == 'index').visible,
          isFalse);
      expect(d.table!.visibleColumns, hasLength(2));
    });

    test('ولا يُطفأ آخرُ عمودٍ ظاهر', () {
      var d = _doc();
      d = toggleColumn(d, 'index');
      d = toggleColumn(d, 'name');
      expect(d.table!.visibleColumns, hasLength(1));

      final before = d;
      d = toggleColumn(d, 'total');
      expect(d.table!.visibleColumns, hasLength(1),
          reason: 'جدولٌ بلا أعمدةٍ يختفي من الورقة بلا رسالة');
      expect(identical(d, before), isTrue,
          reason: 'العمليّةُ المرفوضةُ تُرجع المستندَ كما هو');
    });

    test('والترتيبُ يتبدّل خطوةً ولا يخرج عن الطرفين', () {
      var d = moveColumn(_doc(), 'name', -1);
      expect(d.table!.columns.map((c) => c.key).toList(),
          ['name', 'index', 'total']);

      d = moveColumn(d, 'name', -1);
      expect(d.table!.columns.map((c) => c.key).toList(),
          ['name', 'index', 'total'],
          reason: 'أوّلُ عمودٍ لا يصعد أكثر');
    });

    test('وعنوانُ العمود يُكتب — وهو ما يُنهي الحرفيّات في الراسم', () {
      final d = editColumn(_doc(), 'name', labelAr: 'البيان', labelEn: 'Item');
      final c = d.table!.columns.firstWhere((x) => x.key == 'name');
      expect(c.labelAr, 'البيان');
      expect(c.labelEn, 'Item');
    });

    test('وعرضُ العمود محصورٌ بين ٠٫٤ و٦', () {
      expect(
          editColumn(_doc(), 'name', flex: 0)
              .table!
              .columns
              .firstWhere((c) => c.key == 'name')
              .flex,
          minColumnFlex);
      expect(
          editColumn(_doc(), 'name', flex: 99)
              .table!
              .columns
              .firstWhere((c) => c.key == 'name')
              .flex,
          maxColumnFlex);
    });

    test('والمنازلُ بين صفرٍ وأربعة', () {
      expect(
          editColumn(_doc(), 'total', decimals: 9)
              .table!
              .columns
              .firstWhere((c) => c.key == 'total')
              .decimals,
          4);
    });
  });

  group('النطاقُ — وأعلامُه', () {
    test('التكرارُ والظهورُ والارتفاعُ التلقائيّ تُبدَّل', () {
      final d = editBand(_doc(),
          bandId: BandId.header,
          repeatEachPage: true,
          autoHeight: true,
          visible: false);
      final b = d.bands.first;
      expect(b.repeatEachPage, isTrue);
      expect(b.autoHeight, isTrue);
      expect(b.visible, isFalse);
    });

    test('و`growsWithData` غيرُ قابلٍ للتبديل — لا وسيطَ له أصلاً', () {
      // إيقافُه يكسر كلَّ قالبٍ فيه جدول، فالقفلُ في التوقيع لا في الشرط.
      final d = editBand(_doc(), bandId: BandId.details, visible: false);
      expect(d.bands.last.growsWithData, isTrue);
    });
  });

  group('تبديلُ الورق يقصّ ما خرج — ولا يؤجّله للطباعة', () {
    test('عنصرٌ أعرضُ من الورق الجديد يضيق', () {
      // ‏٥٨مم بهامشَي ١٠ ⇒ عرضُ المحتوى ٣٨. وعنصرُنا ٦٠.
      final d = setPaper(_doc(), widthMm: 58, heightMm: null);
      expect(_el(d).wMm, 38);
      expect(_el(d).xMm, 0, reason: 'ما عاد له موضعٌ غيرُ الحافّة');
    });

    test('وعنصرٌ يسع الورقَ الجديدَ لا يُلمَس', () {
      final d = setPaper(_doc(), widthMm: 148, heightMm: 210);
      // ‏١٤٨ − ٢٠ = ١٢٨، والعنصرُ عند ١٠ بعرض ٦٠ ⇒ ينتهي عند ٧٠.
      expect(_el(d).wMm, 60);
      expect(_el(d).xMm, 10);
    });

    test('والورقُ المتّصلُ يبقى بلا ارتفاع', () {
      final d = setPaper(_doc(), widthMm: 80, heightMm: null);
      expect(d.paper.isContinuous, isTrue);
    });
  });

  group('ضابط: كلُّ عمليّةٍ لا تلمس ما لم تُطلَب منه', () {
    test('تحريكُ عنصرٍ لا يغيّر الجدولَ ولا النطاقاتِ الأخرى', () {
      final before = _doc();
      final after = moveElement(before,
          bandId: BandId.header, elementId: 'a', xMm: 30, yMm: 10);

      expect(after.table!.columns.length, before.table!.columns.length);
      expect(after.bands.length, before.bands.length);
      expect(after.bands.last.growsWithData, isTrue);
      expect(after.paper.widthMm, before.paper.widthMm);
    });

    test('ومعرِّفٌ لا وجودَ له يُرجع المستندَ كما هو', () {
      final before = _doc();
      final after = moveElement(before,
          bandId: BandId.header, elementId: 'لا-يوجد', xMm: 30, yMm: 10);
      expect(_el(after).xMm, _el(before).xMm);
    });
  });
}

// test/unit/print_probe_test.dart
//
// فحوصُ المطبوع — وهي **حاكمٌ** لا زينة: زرُّ الطباعة يُرفض على الأحمر.
//
// ⚠️ ولذلك يُقاس الحكمُ في الاتّجاهين: أنّ الفحصَ يحمرّ على العطب الذي يدّعيه،
// **وأنّه لا يحمرّ على ما لا عيبَ فيه**. فحصٌ متزمّتٌ يقفل الشاشةَ على كلّ
// قالبٍ سليمٍ فيُطفئه المستخدمُ في ذهنه ويتجاهله — وهو موتُ الحارس.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/print_probe.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';
import 'package:ural_erp/services/printing/paint_plan.dart';

const _margins = MarginsMm(top: 10, right: 10, bottom: 10, left: 10);

TemplateDocument _doc({
  double width = 210,
  double? height = 297,
  bool withTotals = true,
}) =>
    TemplateDocument(
      paper: height == null
          ? PaperSpec.continuous(widthMm: width, margins: _margins)
          : PaperSpec(widthMm: width, heightMm: height, margins: _margins),
      bands: [
        const TemplateBand(id: BandId.header, heightMm: 30, elements: [
          TemplateElement(
              id: 'h1', kind: ElementKind.text, contentKey: 'company_name',
              xMm: 0, yMm: 0, wMm: 80, hMm: 6),
        ]),
        const TemplateBand(id: BandId.details, heightMm: 100,
            growsWithData: true),
        if (withTotals)
          const TemplateBand(id: BandId.totals, heightMm: 20, elements: [
            TemplateElement(
                id: 't1', kind: ElementKind.text, contentKey: 'total',
                xMm: 0, yMm: 0, wMm: 60, hMm: 6),
          ]),
      ],
    );

PaintOp _op({
  required String id,
  PaintKind kind = PaintKind.text,
  double left = 10,
  double top = 10,
  double width = 40,
  double height = 6,
  String text = 'نصّ',
  BandId? band,
}) =>
    PaintOp(
      id: id,
      kind: kind,
      leftMm: left,
      topMm: top,
      widthMm: width,
      heightMm: height,
      text: text,
      band: band,
    );

ProbedPage _page(
  List<PaintOp> ops, {
  int number = 1,
  int count = 1,
  double width = 210,
  double height = 297,
}) =>
    ProbedPage(
      PositionedPage(
        pageNumber: number,
        pageCount: count,
        widthMm: width,
        heightMm: height,
        elements: const [],
        tables: const [],
      ),
      ops,
    );

/// ورقةٌ سليمةٌ في كلِّ وجه — أساسُ كلِّ حالةٍ أدناه.
List<ProbedPage> _healthy() => [
      _page([
        _op(id: 'a', band: BandId.header),
        _op(id: 'h', kind: PaintKind.tableHeader, top: 40, width: 30),
        _op(id: 'c', kind: PaintKind.tableCell, top: 50, width: 30),
        _op(id: 'z', band: BandId.totals, top: 200, width: 60),
      ]),
    ];

PrintCheck _find(List<PrintCheck> checks, String fragment) =>
    checks.firstWhere((c) => c.title.contains(fragment),
        orElse: () => throw StateError(
            'لا فحصَ عنوانُه يحوي «$fragment» — العناوينُ: '
            '${checks.map((c) => c.title).toList()}'));

void main() {
  group('الورقةُ السليمةُ تمرّ — ولا فحصَ متزمّت', () {
    test('بلا فشلٍ ولا تحذير', () {
      final checks =
          probePrintout(pages: _healthy(), document: _doc());

      expect(hasBlockingFailure(checks), isFalse,
          reason: 'الفاشلةُ: ${checks.where((c) => c.level == ProbeLevel.fail).map((c) => c.title).toList()}');
      expect(checks.where((c) => c.level == ProbeLevel.warn), isEmpty,
          reason: 'المحذِّرةُ: ${checks.where((c) => c.level == ProbeLevel.warn).map((c) => c.title).toList()}');
    });

    test('وكلُّ فحصٍ يحمل عنواناً وشرحاً', () {
      for (final c in probePrintout(pages: _healthy(), document: _doc())) {
        expect(c.title, isNotEmpty);
        expect(c.note, isNotEmpty);
      }
    });

    test('والترتيبُ الأسوأُ أوّلاً', () {
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'x', left: 190, width: 40, band: BandId.totals)]),
        ],
        document: _doc(),
      );
      expect(checks.first.level, ProbeLevel.fail,
          reason: 'المستخدمُ يقرأ الأوّلَ ويتصرّف');
    });
  });

  group('التجاوزُ الأفقيُّ — «يُقصّ صامتاً»', () {
    test('عنصرٌ يتجاوز الحافّةَ اليمنى ⇒ فشل', () {
      final checks = probePrintout(
        pages: [
          _page([
            _op(id: 'wide', left: 180, width: 40, text: 'الإجمالي المستحق',
                band: BandId.totals),
          ]),
        ],
        document: _doc(),
      );
      final c = _find(checks, 'يتجاوز حافّةَ الورق');
      expect(c.level, ProbeLevel.fail);
      expect(c.note, contains('10.0مم'), reason: '‏٢٢٠ − ٢١٠ = ١٠');
      expect(c.note, contains('الإجمالي المستحق'),
          reason: 'العنصرُ المسمّى يُقصّر التحقيق');
    });

    test('وعنصرٌ يبدأ قبل الحافّة ⇒ فشلٌ كذلك', () {
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'neg', left: -5, band: BandId.totals)]),
        ],
        document: _doc(),
      );
      expect(_find(checks, 'يتجاوز حافّةَ الورق').level, ProbeLevel.fail);
    });

    test('وفرقٌ مجهريٌّ لا يُعدّ تجاوزاً', () {
      // الحسابُ بالنقاط العشريّة يُنتج ٢١٠.٢ حيث يُقصد ٢١٠.
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'edge', left: 170.2, width: 40, band: BandId.totals)]),
        ],
        document: _doc(),
      );
      expect(hasBlockingFailure(checks), isFalse);
    });
  });

  group('التجاوزُ الرأسيُّ — والحراريُّ لا قاعَ له', () {
    test('عنصرٌ يتجاوز قاعَ الورق الثابت ⇒ فشل', () {
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'deep', top: 295, height: 10, band: BandId.totals)]),
        ],
        document: _doc(),
      );
      expect(_find(checks, 'يتجاوز قاعَ الصفحة').level, ProbeLevel.fail);
    });

    test('ونفسُه على ورقٍ متّصلٍ لا يُعدّ عطباً', () {
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'deep', top: 295, height: 10, band: BandId.totals)],
              width: 80, height: 0),
        ],
        document: _doc(width: 80, height: null),
      );
      expect(_find(checks, 'ورقٌ متّصلٌ بلا قاع').level, ProbeLevel.pass);
      expect(hasBlockingFailure(checks), isFalse);
    });
  });

  group('المجاميعُ تبلغ الورقَ — وإلّا فاتورةٌ بلا إجمالي', () {
    test('نطاقٌ معلَنٌ لم يخرج ⇒ فشل', () {
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'a', band: BandId.header)]),
        ],
        document: _doc(),
      );
      expect(_find(checks, 'المجاميع لم يصل الورق').level, ProbeLevel.fail);
    });

    test('وقالبٌ بلا نطاقِ مجاميعَ لا يُحاسَب عليه', () {
      // الكشوفُ والتقاريرُ بلا مجاميعَ نطاقيّة — والفحصُ لا يسري.
      final checks = probePrintout(
        pages: [
          _page([_op(id: 'a', band: BandId.header)]),
        ],
        document: _doc(withTotals: false),
      );
      expect(hasBlockingFailure(checks), isFalse);
    });
  });

  group('رؤوسُ الأعمدة على كلِّ صفحة', () {
    test('صفحةُ جدولٍ بلا رؤوسٍ ⇒ تحذيرٌ لا منع', () {
      final checks = probePrintout(
        pages: [
          _page([
            _op(id: 'h', kind: PaintKind.tableHeader, width: 30),
            _op(id: 'c1', kind: PaintKind.tableCell, top: 50, width: 30),
            _op(id: 'z', band: BandId.totals, top: 200, width: 60),
          ], number: 1, count: 2),
          _page([
            _op(id: 'c2', kind: PaintKind.tableCell, top: 50, width: 30),
          ], number: 2, count: 2),
        ],
        document: _doc(),
      );
      final c = _find(checks, 'رؤوسُ الأعمدة غائبة');
      expect(c.level, ProbeLevel.warn,
          reason: 'ورقٌ يُقرأ بصعوبةٍ لا ورقٌ يفقد بياناً');
      expect(c.note, contains('2'), reason: 'يُسمّي الصفحةَ الناقصة');
    });

    test('وجدولٌ في صفحةٍ واحدةٍ لا يُحاسَب على التكرار', () {
      final checks = probePrintout(pages: _healthy(), document: _doc());
      expect(_find(checks, 'الجدولُ في صفحةٍ واحدة').level, ProbeLevel.pass);
    });
  });

  group('أضيقُ عمودٍ — حدُّ القراءة لا حدُّ الذوق', () {
    test('تحتَ ١٢مم ⇒ فشل', () {
      final checks = probePrintout(
        pages: [
          _page([
            _op(id: 'h', kind: PaintKind.tableHeader, width: 9),
            _op(id: 'z', band: BandId.totals, top: 200, width: 60),
          ]),
        ],
        document: _doc(),
      );
      final c = _find(checks, 'أضيقُ عمودٍ');
      expect(c.level, ProbeLevel.fail);
      expect(c.title, contains('9.0'));
    });

    test('وبين ١٢ و١٦ ⇒ تحذير', () {
      final checks = probePrintout(
        pages: [
          _page([
            _op(id: 'h', kind: PaintKind.tableHeader, width: 14),
            _op(id: 'z', band: BandId.totals, top: 200, width: 60),
          ]),
        ],
        document: _doc(),
      );
      expect(_find(checks, 'أضيقُ عمودٍ').level, ProbeLevel.warn);
    });

    test('وفوقَ ١٦ ⇒ سليم', () {
      expect(_find(probePrintout(pages: _healthy(), document: _doc()),
              'أضيقُ عمودٍ')
          .level,
          ProbeLevel.pass);
    });
  });

  group('عرضُ الطابعة — ولا حكمَ على المجهول', () {
    test('قالبُ A4 على طابعةٍ ٨٠مم ⇒ فشل', () {
      final checks = probePrintout(
          pages: _healthy(), document: _doc(), printerWidthMm: 80);
      expect(_find(checks, 'يتجاوز الطابعة').level, ProbeLevel.fail);
      expect(hasBlockingFailure(checks), isTrue);
    });

    test('وأضيقُ من الطابعة ⇒ تحذيرٌ لا منع', () {
      final checks = probePrintout(
          pages: [
            _page([
              _op(id: 'a', band: BandId.totals, width: 40),
              _op(id: 'h', kind: PaintKind.tableHeader, width: 30),
            ], width: 80, height: 0),
          ],
          document: _doc(width: 80, height: null),
          printerWidthMm: 210);
      expect(_find(checks, 'أضيقُ من الطابعة').level, ProbeLevel.warn);
      expect(hasBlockingFailure(checks), isFalse);
    });

    test('وطابعةٌ بلا عرضٍ مسجَّلٍ لا تُمنع', () {
      // المنعُ على المجهول يقفل الربطَ على كلِّ طابعةٍ لم تُعرَّف بعد.
      final checks = probePrintout(
          pages: _healthy(), document: _doc(), printerWidthMm: null);
      expect(_find(checks, 'غيرُ مسجَّل').level, ProbeLevel.pass);
    });
  });

  group('ضابط: البوّابةُ تفتح وتُغلق', () {
    test('`hasBlockingFailure` تفرّق التحذيرَ من الفشل', () {
      const warnOnly = [
        PrintCheck(ProbeLevel.warn, 'ت', 'ش'),
        PrintCheck(ProbeLevel.pass, 'ت', 'ش'),
      ];
      const withFail = [
        PrintCheck(ProbeLevel.warn, 'ت', 'ش'),
        PrintCheck(ProbeLevel.fail, 'ت', 'ش'),
      ];
      expect(hasBlockingFailure(warnOnly), isFalse,
          reason: 'المنعُ على التحذير يقفل الشاشةَ على كلِّ قالبٍ فيُتجاهَل');
      expect(hasBlockingFailure(withFail), isTrue);
    });

    test('ومطبوعٌ بلا صفحاتٍ يُمنع', () {
      final checks = probePrintout(pages: const [], document: _doc());
      expect(hasBlockingFailure(checks), isTrue);
    });
  });
}

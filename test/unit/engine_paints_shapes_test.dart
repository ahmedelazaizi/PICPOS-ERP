// المحرّكُ يرسم الأشكالَ لا النصَّ وحدَه — شعارٌ ورمزٌ وفاصلٌ ومستطيل.
//
// ── الفجوةُ التي يسدّها ───────────────────────────────────────────────────
// `PaintKind` كانت ثلاثةً: نصٌّ ورأسُ جدولٍ وخليّة. فالشعارُ يُخطَّط بموضعٍ
// وحجمٍ صحيحين ثمّ يصل الراسمَ فلا يجد نوعاً يرسمه به — فيخرج نصّاً فارغاً.
//
// ومقيسٌ أنّ `LOGO` كان **آخرَ ما يضيع** من الورقة عند الهجرة: بعد إصلاح
// التسمياتِ والكميّةِ وملاحظاتِ الأصناف بقي وحدَه في قائمة الضياع.
//
// والفرقُ بين «لا صورة» و«صورةٌ لم تصل» ليس تجميليّاً: الشعارُ هويّةُ
// المنشأة على مستندٍ رسميّ، وفاتورةٌ ضريبيّةٌ بلا مربّع QR ناقصةٌ نظاميّاً.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';
import 'package:ural_erp/services/printing/paint_plan.dart';
import 'package:ural_erp/services/printing/pdf_painter.dart';

import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الخطّةُ تُميّز الأشكال', () {
    test('لكلِّ نوعِ عنصرٍ نوعُ رسمٍ يخصّه', () {
      final ops = planPage(_pageWith(const [
        _E('a', ElementKind.image, 'logo'),
        _E('b', ElementKind.qrCode, 'qr_code'),
        _E('c', ElementKind.barcode, 'barcode'),
        _E('d', ElementKind.line, 'line'),
        _E('e', ElementKind.rect, 'rectangle'),
        _E('f', ElementKind.text, 'company_name'),
      ]));

      final kinds = {for (final o in ops) o.id: o.kind};
      expect(kinds['a'], PaintKind.image);
      expect(kinds['b'], PaintKind.qrCode);
      expect(kinds['c'], PaintKind.barcode);
      expect(kinds['d'], PaintKind.line);
      expect(kinds['e'], PaintKind.rect);
      expect(kinds['f'], PaintKind.text);
    });

    test('والفراغُ لا يُنشئ عمليّةَ رسمٍ أصلاً', () {
      // يحجز مكانَه في التخطيط وكفى. وعمليّةٌ فارغةٌ تُنشئ ودجتاً بلا محتوى
      // في كلِّ صفحة — كلفةٌ بلا أثر.
      final ops = planPage(_pageWith(const [
        _E('s', ElementKind.spacer, 'spacer'),
        _E('t', ElementKind.text, 'company_name'),
      ]));
      expect(ops.map((o) => o.id), ['t']);
    });
  });

  group('الراسمُ يُخرج الأشكالَ على الورق', () {
    test('بلا صورةٍ مرفوعةٍ يُرسم إطارُ الشعار باسمه', () async {
      // نفسُ ما يفعله المسارُ القديم. وحذفُه يعني أن كلَّ قالبٍ بلا شعارٍ
      // مرفوعٍ يفقد كتلةً كانت على ورقه.
      final probe = probePdf(await PdfPainter.paint(
        pages: _pageList(const [_E('a', ElementKind.image, 'logo')]),
      ));
      expect(probe.allTexts.map((r) => r.text), contains('LOGO'));
    });

    test('وبصورةٍ مرفوعةٍ لا يُطبع النصُّ البديل', () async {
      final probe = probePdf(await PdfPainter.paint(
        pages: _pageList(const [_E('a', ElementKind.image, 'logo')]),
        logoBytes: _pngPixel,
      ));
      expect(probe.allTexts.map((r) => r.text), isNot(contains('LOGO')),
          reason: 'رُسمت الصورةُ **ومعها** نصُّها البديل — كلاهما على الورقة');
    });

    test('ومربّعُ QR يُرسم من حمولته', () async {
      // لا يُقاس بالنصّ: الرمزُ رسمٌ لا حروف. فالمقيسُ أنّ الورقةَ نمت
      // بمستطيلاتٍ حيث لم يكن شيء.
      final withCode = probePdf(await PdfPainter.paint(
        pages: _pageList(const [_E('a', ElementKind.qrCode, 'qr_code')],
            value: 'SINV-1'),
      ));
      final withoutCode = probePdf(await PdfPainter.paint(
        pages: _pageList(const [_E('a', ElementKind.qrCode, 'qr_code')]),
      ));

      expect(withCode.pages.first.rects.length,
          greaterThan(withoutCode.pages.first.rects.length),
          reason: 'الرمزُ لم يُرسم — أو رُسم بلا حمولةٍ فخرج مربّعاً أسودَ '
              'لا يقرؤه ماسح');
    });

    test('والفاصلُ يصل الورقةَ خطّاً', () async {
      final probe = probePdf(await PdfPainter.paint(
        pages: _pageList(const [_E('a', ElementKind.line, 'line')]),
      ));
      expect(probe.pages.first.rects, isNotEmpty,
          reason: 'الفاصلُ لا يُرسم — ورقةٌ بلا خطوطٍ فاصلة');
    });
  });

  test('ضابط: الاختبارُ يرسم ورقاً فعلاً', () async {
    // بلا هذا يمرّ كلُّ ما فوقه على وثيقةٍ فارغة.
    final bytes = await PdfPainter.paint(
      pages: _pageList(const [_E('a', ElementKind.text, 'company_name')],
          value: 'شركةُ الاختبار'),
    );
    expect(bytes.lengthInBytes, greaterThan(500));
    expect(probePdf(bytes).allTexts, isNotEmpty);
  });
}

// ═══════════════════════════════════════════════════════════════════════════

class _E {
  const _E(this.id, this.kind, this.key);
  final String id;
  final ElementKind kind;
  final String key;
}

const _paper =
    PaperSpec(widthMm: 210, heightMm: 297, margins: MarginsMm.all(10));

List<PositionedPage> _pageList(List<_E> els, {String value = ''}) =>
    LayoutEngine.paginate(
      document: TemplateDocument(
        paper: _paper,
        bands: [
          TemplateBand(
            id: BandId.info,
            heightMm: 60,
            elements: [
              for (var i = 0; i < els.length; i++)
                TemplateElement(
                  id: els[i].id,
                  contentKey: els[i].key,
                  xMm: 0,
                  yMm: i * 12.0,
                  wMm: 40,
                  hMm: 10,
                  kind: els[i].kind,
                ),
            ],
          ),
        ],
      ),
      rows: const [],
      values: {for (final e in els) e.key: value},
    );

PositionedPage _pageWith(List<_E> els) => _pageList(els, value: 'X').first;

/// أصغرُ PNG صالح — بكسلٌ شفّافٌ واحد.
final _pngPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

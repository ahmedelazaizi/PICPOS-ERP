// المعاينةُ والورقُ يقرآن **نفسَ** خطّةِ الرسم.
//
// ── العطبُ الذي يمنعه ─────────────────────────────────────────────────────
// كان في المشروع ثلاثةُ رُسّامٍ لكلٍّ منها حسابُ تخطيطٍ خاصّ: راسمُ الـPDF،
// ونافذةُ المعاينة، ومعاينةُ محرّر الأقسام. ووجودُ `debugRenderItemsTable`
// كمِقبضِ اختبارٍ في الكود دليلٌ **مكتوب** على أنّهم اكتووا من «المعاينة ≠
// الورق» وبنوا مِقبضاً ليقيسوه.
//
// والعلاجُ ليس «انتبهوا» بل بنيةٌ تجعل الاختلافَ مستحيلاً: `planPage` تُنتج
// عمليّاتِ رسمٍ بإحداثيّاتٍ **نهائيّةٍ من حافّة اليسار**، والراسمان يأخذانها
// كما هي ولا يحسب أحدُهما شيئاً.
//
// ── ولماذا الانعكاسُ هنا لا في الراسمين ──────────────────────────────────
// المحرّكُ يعمل بإحداثيّاتٍ من **حافّة البداية** (اليمينُ في RTL). ولو تُرك
// قلبُها لكلِّ راسمٍ لانقلب أحدُهما ونسي الآخر — وهو بالضبط شكلُ العطب الذي
// نمنعه. فيُقلب مرّةً واحدةً هنا.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/printing/paint_plan.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';

const _a4 = PaperSpec(
  widthMm: 210,
  heightMm: 297,
  margins: MarginsMm.all(10),
);

TemplateDocument _doc() => const TemplateDocument(
      paper: _a4,
      table: TableSpec(
        columns: [
          TableColumn(key: 'name', labelAr: 'الصنف', flex: 3),
          TableColumn(key: 'total', labelAr: 'الإجمالي'),
        ],
        rowHeightMm: 6,
      ),
      bands: [
        TemplateBand(
          id: BandId.header,
          heightMm: 20,
          elements: [
            TemplateElement(
              id: 'company',
              contentKey: 'company_name',
              xMm: 0,
              yMm: 4,
              wMm: 60,
              hMm: 6,
            ),
          ],
        ),
        TemplateBand(id: BandId.details, heightMm: 20, growsWithData: true),
      ],
    );

List<PositionedPage> _pages() => LayoutEngine.paginate(
      document: _doc(),
      rows: const [
        ['قلم', '10.00'],
        ['دفتر', '25.00'],
      ],
      values: const {'company_name': 'شركة الاختبار'},
    );

void main() {
  test('نداءان متتاليان يعطيان نفسَ الخطّة بالضبط', () {
    // لو حمل الراسمُ حالةً أو عشوائيّةً لاختلف النداءان — وهذا أوّلُ ما
    // يجعل المعاينةَ تفترق عن الورق.
    final a = planPage(_pages().first, direction: PaintDirection.rtl);
    final b = planPage(_pages().first, direction: PaintDirection.rtl);

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].leftMm, b[i].leftMm);
      expect(a[i].topMm, b[i].topMm);
      expect(a[i].widthMm, b[i].widthMm);
      expect(a[i].text, b[i].text);
    }
  });

  group('الانعكاسُ في RTL يقع مرّةً واحدةً هنا', () {
    test('عنصرٌ عند البداية ينتهي عند حافّة اليمين', () {
      final ops = planPage(_pages().first, direction: PaintDirection.rtl);
      final company = ops.firstWhere((o) => o.id == 'company');

      // الهامشُ الأيمنُ ١٠، والعرضُ ٦٠ ⇒ يبدأ من اليسار عند ٢١٠−١٠−٦٠ = ١٤٠.
      expect(company.leftMm, 140.0);
      expect(company.widthMm, 60.0);
    });

    test('ونفسُ العنصر في LTR يبدأ عند الهامش الأيسر', () {
      final ops = planPage(_pages().first, direction: PaintDirection.ltr);
      final company = ops.firstWhere((o) => o.id == 'company');
      expect(company.leftMm, 10.0);
    });

    test('والارتفاعُ لا ينقلب في الحالتين', () {
      final rtl = planPage(_pages().first, direction: PaintDirection.rtl)
          .firstWhere((o) => o.id == 'company');
      final ltr = planPage(_pages().first, direction: PaintDirection.ltr)
          .firstWhere((o) => o.id == 'company');
      expect(rtl.topMm, ltr.topMm, reason: 'الرأسيُّ لا شأنَ له باتّجاه النصّ');
    });

    test('لا عمليّةَ تخرج عن حدود الورقة', () {
      for (final dir in PaintDirection.values) {
        for (final op in planPage(_pages().first, direction: dir)) {
          expect(op.leftMm, greaterThanOrEqualTo(-0.001),
              reason: '${op.id} خرج من اليسار في $dir');
          expect(op.leftMm + op.widthMm, lessThanOrEqualTo(210.001),
              reason: '${op.id} خرج من اليمين في $dir');
        }
      }
    });
  });

  group('الخطّةُ تحمل الجدولَ كما تحمل العناصر', () {
    test('كلُّ خليّةِ بياناتٍ تصير عمليّةَ رسم', () {
      final ops = planPage(_pages().first, direction: PaintDirection.rtl);
      final texts = ops.map((o) => o.text).toSet();

      expect(texts, containsAll(['قلم', '10.00', 'دفتر', '25.00']));
      expect(texts, contains('شركة الاختبار'));
    });

    test('ورؤوسُ الأعمدة كذلك', () {
      final ops = planPage(_pages().first, direction: PaintDirection.rtl);
      expect(ops.map((o) => o.text), containsAll(['الصنف', 'الإجمالي']));
    });

    test('ورأسُ الجدول موسومٌ ليُرسم بأسلوبٍ مختلف', () {
      final ops = planPage(_pages().first, direction: PaintDirection.rtl);
      final headers = ops.where((o) => o.kind == PaintKind.tableHeader);
      expect(headers, hasLength(2));
      expect(headers.map((o) => o.text), ['الصنف', 'الإجمالي']);
    });
  });

  test('عمودُ الجدول ينعكس في RTL فيبدأ الأوّلُ من اليمين', () {
    final ops = planPage(_pages().first, direction: PaintDirection.rtl)
        .where((o) => o.kind == PaintKind.tableHeader)
        .toList();

    // العرضُ المتاح ١٩٠: «الصنف» flex 3 ⇒ ١٤٢.٥ · «الإجمالي» flex 1 ⇒ ٤٧.٥
    // في RTL يبدأ «الصنف» من اليمين ⇒ يساره ٢١٠ − ١٠ − ١٤٢.٥ = ٥٧.٥
    expect(ops[0].text, 'الصنف');
    expect(ops[0].leftMm, closeTo(57.5, 0.001));
    expect(ops[1].text, 'الإجمالي');
    expect(ops[1].leftMm, closeTo(10.0, 0.001),
        reason: 'آخرُ عمودٍ في RTL يلامس الهامشَ الأيسر');
  });
}

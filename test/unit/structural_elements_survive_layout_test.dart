// الفواصلُ والشعارُ ومربّعُ QR تصل الورقةَ — لا تسقط بقاعدةٍ تحرس غيرَها.
//
// ── العطبُ الذي يمنعه ─────────────────────────────────────────────────────
// `LayoutEngine._shows` تُسقط كلَّ عنصرٍ ذي مفتاحٍ بقيمةٍ فارغة. وهي قاعدةٌ
// صائبةٌ لحقلِ بيانات: «الكاشير:» بلا اسمٍ يجعل القارئَ يظنّ البيانَ ناقصاً
// لا الحقلَ غيرَ مفعَّل — وهو عطبٌ رُصد على ورقٍ حقيقيّ.
//
// لكنّ **الفاصلَ لا قيمةَ له أصلاً**. فكانت القاعدةُ تبتلعه هو والشعارَ
// ومربّعَ QR، وقالبُ الفاتورة الضريبيّة يضع ١٤ عنصراً من ٣٠ على الورق.
//
// والنيّةُ كانت مكتوبةً منذ البداية في `_nonTextTypes` بالمُخطِّط —
// «أنواعٌ لا تحمل نصّاً، لا تسقط بقاعدة لا تسميةَ معلَّقة» — ولم يكن يحملها
// شيءٌ إلى المحرّك: `TemplateElement` بلا وسمٍ يميّزها.
//
// وهو عطبٌ لا تراه اختباراتُ المحرّك الثمانيةُ لأنها تبني مستنداتِها بيدها
// فتضع لكلِّ عنصرٍ قيمة. ولا يظهر إلّا بالمرور على قالبٍ حقيقيّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/printing/print_values.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/services/printing/layout_engine.dart';
import 'package:ural_erp/services/printing/template_render_pipeline.dart';

const _assetDir = 'assets/invoice_templates';

/// حمولةٌ **كلُّ حقولها مملوءة** — كي يكون كلُّ سقوطٍ سببُه البنيةَ لا فراغَ
/// البيانات.
final _full = PrintPayload(
  invoiceNumber: 'SINV-1',
  date: DateTime.utc(2026, 3, 14),
  companyName: 'شركة',
  companyAddress: 'عنوان',
  companyPhone: '0100',
  companyTaxId: '310',
  customerName: 'عميل',
  customerPhone: '0111',
  customerAddress: 'عنوانه',
  cashierName: 'كاشير',
  notes: 'ملاحظة',
  paymentMethod: 'cash',
  orderNumber: '7',
  subtotal: 100,
  discount: 5,
  tax: 10,
  deliveryFee: 2,
  total: 107,
  paid: 100,
  remaining: 7,
  cashAmount: 60,
  bankAmount: 40,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('عنصرٌ بنيويٌّ يصل الورقةَ ولو لم تكن له قيمة', () async {
    final placed = await _placedKinds(db, 'a4_sales_tax_invoice.json');

    // الأنواعُ البنيويّةُ في هذا القالب — مقيسةٌ من الملفّ نفسِه.
    expect(placed, contains('line'),
        reason: 'الفواصلُ تسقط ⇒ الورقةُ بلا خطوطٍ فاصلة');
    expect(placed, contains('logo'),
        reason: 'الشعارُ يسقط ⇒ ترويسةٌ بلا علامة');
    expect(placed, contains('qr_code'),
        reason: 'مربّعُ QR يسقط ⇒ فاتورةٌ ضريبيّةٌ ناقصة');
  });

  test('أغلبُ عناصر القالب تصل الورقة — لا نصفُها', () async {
    final id = await _import(db, 'a4_sales_tax_invoice.json');
    final els = await db.getTemplateElements(id);
    final pages = await _paginate(db, id);

    var placed = 0;
    for (final p in pages) {
      placed += p.elements.length;
    }

    // القيمةُ المقيسةُ قبل الإصلاح: ١٤ من ٣٠. والحدُّ هنا نسبةٌ لا رقمٌ
    // مجمَّد: القالبُ قد ينمو، لكنّ سقوطَ نصفِه ليس تفصيلاً.
    expect(placed, greaterThan(els.length * 0.75),
        reason: 'سقط أكثرُ من ربع القالب — $placed من ${els.length}');
  });

  group('ضابط: القاعدةُ الأصليّةُ ما زالت تحرس', () {
    test('حقلُ بياناتٍ بقيمةٍ فارغةٍ **يبقى** ساقطاً', () async {
      // لولا هذا لكان الإصلاحُ قد ألغى القاعدةَ بدل أن يستثني منها:
      // «الكاشير:» بلا اسمٍ يعود إلى الورق.
      final doc = _docWith(const [
        TemplateElement(
          id: 'a',
          contentKey: 'cashier_name',
          xMm: 0,
          yMm: 0,
          wMm: 40,
          hMm: 5,
          labelAr: 'الكاشير',
        ),
      ]);

      final withValue = LayoutEngine.paginate(
          document: doc, rows: const [], values: {'cashier_name': 'سالم'});
      final without = LayoutEngine.paginate(
          document: doc, rows: const [], values: const {'cashier_name': ''});

      expect(withValue.first.elements, hasLength(1));
      expect(without.first.elements, isEmpty,
          reason: 'حقلٌ فارغٌ عاد يُطبع — الاستثناءُ ابتلع القاعدة');
    });

    test('وعنصرٌ بنيويٌّ بنفس الفراغ **يمرّ**', () async {
      final doc = _docWith(const [
        TemplateElement(
          id: 'a',
          contentKey: 'line',
          xMm: 0,
          yMm: 0,
          wMm: 40,
          hMm: 1,
          kind: ElementKind.line,
        ),
      ]);

      final pages = LayoutEngine.paginate(
          document: doc, rows: const [], values: const {'line': ''});
      expect(pages.first.elements, hasLength(1),
          reason: 'الوسمُ لا يُقرأ — الاستثناءُ غيرُ موصول');
    });

    test('والشرطُ ما زال يُسقط البنيويَّ كذلك', () async {
      // الوسمُ يستثني من قاعدةِ الفراغ وحدَها. شرطُ الإظهار حاجزٌ آخرُ ولا
      // يجوز أن يخترقه شيء — وإلّا ظهر فاصلُ قسمٍ محذوفٍ بأكمله.
      final doc = _docWith(const [
        TemplateElement(
          id: 'a',
          contentKey: 'line',
          xMm: 0,
          yMm: 0,
          wMm: 40,
          hMm: 1,
          kind: ElementKind.line,
          condition: 'discount > 0',
        ),
      ]);

      final hidden = LayoutEngine.paginate(
          document: doc, rows: const [], values: const {'discount': '0'});
      expect(hidden.first.elements, isEmpty,
          reason: 'عنصرٌ بنيويٌّ تجاوز شرطَ الإظهار');

      final shown = LayoutEngine.paginate(
          document: doc, rows: const [], values: const {'discount': '5'});
      expect(shown.first.elements, hasLength(1));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════

TemplateDocument _docWith(List<TemplateElement> els) => TemplateDocument(
      paper: const PaperSpec(
          widthMm: 210, heightMm: 297, margins: MarginsMm.all(10)),
      bands: [
        TemplateBand(id: BandId.info, heightMm: 20, elements: els),
      ],
    );

Future<int> _import(AppDatabase db, String file) async =>
    db.importTemplateFromJson(await File('$_assetDir/$file').readAsString());

Future<List<PositionedPage>> _paginate(AppDatabase db, int id) async {
  final t = (await db.getTemplateById(id))!;
  final els = await db.getTemplateElements(id);
  final doc = TemplateRenderPipeline.buildDocument(
    template: t,
    orderedElements: els,
    tableSettings: await db.getTableSettings(id),
  );
  return LayoutEngine.paginate(
    document: doc,
    rows: const [],
    values: TemplateRenderPipeline.buildValues(doc, _full),
  );
}

/// أنواعُ العناصر التي وصلت الورقةَ فعلاً، مشتقّةً من مفاتيحها.
Future<Set<String>> _placedKinds(AppDatabase db, String file) async {
  final id = await _import(db, file);
  final pages = await _paginate(db, id);
  return {
    for (final p in pages)
      for (final e in p.elements) e.contentKey,
  };
}

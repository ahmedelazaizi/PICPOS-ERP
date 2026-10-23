// المعاينةُ التجريبيّة — التركيبُ، وصدقُ الفحوص، **ورفضُ الطباعة على الأحمر**.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التركيبُ على عرضين**: ثلاثُ لوحاتٍ تُطوى تدريجيّاً، وورقةٌ بعرضٍ
//    محسوبٍ بالمليمتر. وانهيارُ التخطيط لا يظهر في `analyze`.
//
// ‏٢) **الورقةُ تُرسم من `PaintOp`**: نصُّ العنصر يظهر فعلاً — لا كتلٌ ولا
//    شجرةٌ فارغةٌ تمرّ خضراء.
//
// ‏٣) **الفحوصُ مشتقّةٌ من المطبوع**: قالبٌ سليمٌ لا يُنتج فشلاً، وقالبٌ
//    يتجاوز الحافّةَ يُنتجه — بلا أن يُكتب اسمُ الحالة في شرطٍ أحدهما.
//
// ‏٤) **الزرُّ يرفض** حين يكون في الفحوص أحمر — وهو الغرضُ من الشاشة.
//
// ⚠️ ولا قاعدةَ بيانات: المستودعاتُ تُستبدَل والمزوِّدُ يبقى.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/print_test_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/printing/print_probe.dart';
import 'package:picpos_erp/domain/repositories/invoice_templates_repository.dart';
import 'package:picpos_erp/domain/repositories/printers_repository.dart';
import 'package:picpos_erp/presentation/print_test_picpos/screens/print_test_picpos_screen.dart';

final _t0 = DateTime.utc(2026, 1, 1);

InvoiceTemplate _template({double width = 210, String name = 'قالب اختبار'}) =>
    InvoiceTemplate(
      id: 1,
      name: name,
      type: 'a4',
      templateCategory: 'invoice',
      isDefault: true,
      paperSize: 'A4',
      paperWidth: width,
      paperHeight: 297,
      margins: '10,10,10,10',
      defaultFont: 'Cairo',
      defaultFontSize: 10,
      isActive: true,
      layoutVersion: 2,
      createdAt: _t0,
      updatedAt: _t0,
    );

/// عنصرٌ بإحداثيّاتٍ — `layoutVersion 2` يقتضي أن يحمل كلُّ عنصرٍ نطاقَه
/// وموضعَه، وإلّا سلك البناءُ مسارَ التدفّق القديم.
InvoiceTemplateElement _el({
  required int id,
  required String band,
  required String content,
  double x = 0,
  double y = 0,
  double w = 80,
  double h = 6,
  int sort = 0,
}) =>
    InvoiceTemplateElement(
      id: id,
      templateId: 1,
      elementType: 'variable',
      content: content,
      rowIndex: 0,
      sortOrder: sort,
      flexWidth: 1,
      xPosition: 0,
      yPosition: 0,
      width: 0,
      height: 0,
      textAlign: 'right',
      fontSize: 10,
      isBold: false,
      isItalic: false,
      fontColor: '#000000',
      borderWidth: 0,
      isVisible: true,
      section: 'body',
      bandId: band,
      xMm: x,
      yMm: y,
      wMm: w,
      hMm: h,
    );

class _FakeTemplatesRepo implements IInvoiceTemplatesRepository {
  _FakeTemplatesRepo(this.template, this.elements);

  final InvoiceTemplate template;
  final List<InvoiceTemplateElement> elements;

  @override
  Future<List<InvoiceTemplate>> getAllTemplates() async => [template];

  @override
  Future<List<TemplateBinding>> getAllBindings() async => const [];

  @override
  Future<List<InvoiceTemplateElement>> getTemplateElements(int id) async =>
      elements;

  @override
  Future<InvoiceTableSetting?> getTableSettings(int id) async => null;

  @override
  Future<InvoiceTemplateWithData?> getTemplateWithData(int id) async =>
      InvoiceTemplateWithData(
        template: template,
        elements: elements,
        tableSettings: null,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrintersRepo implements IPrintersRepository {
  @override
  Future<List<Printer>> getPrinters() async => const [];

  @override
  Future<List<Printer>> getActivePrinters() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// قالبٌ سليم: رأسٌ ومجاميعُ داخلَ عرض الورق.
  final healthy = <InvoiceTemplateElement>[
    _el(id: 1, band: 'header', content: 'company_name', x: 10, y: 4, w: 90),
    _el(id: 2, band: 'info', content: 'invoice_number', x: 10, y: 2, w: 70,
        sort: 1),
    _el(id: 3, band: 'totals', content: 'total', x: 10, y: 2, w: 60, sort: 2),
  ];

  /// نفسُه وقد خرج عنصرُ المجاميع عن حافّة الورق — عطبٌ يُقاس لا يُدَّعى.
  final overflowing = <InvoiceTemplateElement>[
    _el(id: 1, band: 'header', content: 'company_name', x: 10, y: 4, w: 90),
    _el(id: 2, band: 'totals', content: 'total', x: 180, y: 2, w: 60, sort: 1),
  ];

  Future<void> open(
    WidgetTester tester,
    Size size, {
    required List<InvoiceTemplateElement> elements,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceTemplatesRepositoryProvider.overrideWithValue(
              _FakeTemplatesRepo(_template(), elements)),
          printersRepositoryProvider.overrideWithValue(_FakePrintersRepo()),
        ],
        child: const MaterialApp(
          home: PrintTestPicposScreen(templateId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    // ⚠️ الإشعارُ يعيش ٥ ثوانٍ بمؤقّتٍ حيّ، وتفكيكُ الشجرة قبل انقضائه
    //    يُسقط الاختبارَ بـ`!timersPending` **بعد** أن يكون قد نجح — فيبدو
    //    الفشلُ آتياً من الفحص لا من التنظيف.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1920, 1080)),
      ('عرضٌ متوسّط', Size(1280, 800)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2, elements: healthy);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');
        expect(find.text('معاينة وطباعة تجريبية'), findsOneWidget);
        expect(find.text('طباعة تجريبية'), findsOneWidget);
        await teardownTree(tester);
      });
    }

    testWidgets('واللوحتان تُطويان على الضيّق وتبقى الورقة', (tester) async {
      await open(tester, const Size(900, 760), elements: healthy);
      expect(tester.takeException(), isNull);
      expect(find.text('حالات الاختبار'), findsNothing);
      expect(find.text('فحوص المطبوع'), findsNothing);
      expect(find.textContaining('صفحة 1 من'), findsOneWidget,
          reason: 'الورقةُ هي آخرُ ما يُطوى');
      await teardownTree(tester);
    });
  });

  group('الفحوصُ مشتقّةٌ من المطبوع لا مكتوبةٌ بجانبه', () {
    testWidgets('قالبٌ سليمٌ ⇒ لا فشلَ والزرُّ يمرّ', (tester) async {
      await open(tester, const Size(1920, 1080), elements: healthy);

      expect(find.text('كل الفحوص سليمة'), findsOneWidget);

      await tester.tap(find.text('طباعة تجريبية'));
      await tester.pumpAndSettle();
      expect(find.textContaining('الطباعة موقوفة'), findsNothing,
          reason: 'رفضٌ على قالبٍ سليمٍ يُفقد الحارسَ معناه');
      expect(find.textContaining('صفحةً جاهزة'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('وقالبٌ يتجاوز الحافّةَ ⇒ فشلٌ **ورفضُ الطباعة**',
        (tester) async {
      // ⚠️ نفسُ الشاشةِ ونفسُ الحالة — الفرقُ في **البيانات** وحدَها.
      //    فالرفضُ يقع على العطب لا على اسمٍ مكتوبٍ في شرط.
      await open(tester, const Size(1920, 1080), elements: overflowing);

      expect(find.textContaining('يتجاوز حافّةَ الورق'), findsWidgets);

      await tester.tap(find.text('طباعة تجريبية'));
      await tester.pumpAndSettle();
      expect(find.textContaining('الطباعة موقوفة'), findsOneWidget,
          reason: 'الغرضُ من الشاشة منعُ الورق المعطوب لا إنتاجُه');
      await teardownTree(tester);
    });
  });

  group('الورقةُ تُرسم من خطّة الرسم', () {
    testWidgets('ترقيمُ الصفحة يظهر تحت الورقة', (tester) async {
      await open(tester, const Size(1920, 1080), elements: healthy);
      expect(find.textContaining('صفحة 1 من 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });
  });

  // ⚠️ **الورقةُ تُرسم على قماشٍ لا بودجتات نصّ**، فـ`find.text` لا تراها —
  //    وهذا صحيحٌ ومقصود: الرسمُ يستهلك [PaintOp] كما يستهلكها راسمُ الـPDF.
  //    فمحتوى الورقة يُقاس عند مصدره: مزوِّدُ النتيجة.
  group('محتوى الورقة يُقاس من المزوِّد لا من الشجرة', () {
    ProviderContainer container(List<InvoiceTemplateElement> elements) {
      final c = ProviderContainer(overrides: [
        invoiceTemplatesRepositoryProvider
            .overrideWithValue(_FakeTemplatesRepo(_template(), elements)),
        printersRepositoryProvider.overrideWithValue(_FakePrintersRepo()),
      ]);
      addTearDown(c.dispose);
      c.read(printTestTemplateProvider.notifier).set(1);
      return c;
    }

    test('نصُّ العنصر يبلغ خطّةَ الرسم بقيمته المحلولة', () async {
      final c = container(healthy);
      final r = await c.read(printTestResultProvider.future);

      expect(r, isNotNull);
      final texts = r!.pages.expand((p) => p.ops).map((o) => o.text).toList();
      expect(texts.join(' '), contains('INV-2026-1040'),
          reason: 'المتغيّرُ لم يُحلّ — الورقةُ تحمل مفتاحاً لا قيمة');
      expect(texts.join(' '), contains('شركة بيك بوس للتجارة'));
    });

    test('وتبديلُ الحالة يعيد الحسابَ لا يُبقي القديم', () async {
      final c = container(healthy);
      await c.read(printTestResultProvider.future);

      c.read(printTestScenarioProvider.notifier).set('overflow');
      final r = await c.read(printTestResultProvider.future);

      final joined =
          r!.pages.expand((p) => p.ops).map((o) => o.text).join(' ');
      expect(joined, contains('INV-2026-1041'));
      expect(joined, isNot(contains('INV-2026-1040')),
          reason: 'ورقةٌ قديمةٌ باقيةٌ فوق حالةٍ جديدة');
    });

    test('والقالبُ المتجاوزُ يُنتج فشلاً — والسليمُ لا يُنتجه', () async {
      final good = await container(healthy).read(printTestResultProvider.future);
      final bad =
          await container(overflowing).read(printTestResultProvider.future);

      expect(good!.isBlocked, isFalse,
          reason: 'الفاشلةُ: '
              '${good.checks.where((x) => x.level == ProbeLevel.fail).map((x) => x.title).toList()}');
      expect(bad!.isBlocked, isTrue);
      expect(bad.checks.first.title, contains('يتجاوز حافّةَ الورق'));
    });
  });

  group('ضابط: البوّابةُ تقرأ الفشلَ لا التحذير', () {
    test('`hasBlockingFailure` هي التي يناديها الزرّ', () {
      expect(
          hasBlockingFailure(
              const [PrintCheck(ProbeLevel.warn, 'ت', 'ش')]),
          isFalse);
      expect(
          hasBlockingFailure(
              const [PrintCheck(ProbeLevel.fail, 'ت', 'ش')]),
          isTrue);
    });
  });
}

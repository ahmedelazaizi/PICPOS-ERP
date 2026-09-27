// محرّرُ النماذج — التركيبُ، وأنّ التعديلَ يصل **المستندَ** لا الشاشةَ وحدَها.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التركيبُ على عرضين**: ثلاثُ لوحاتٍ وكانفاسٌ بمقياس المليمتر.
//
// ‏٢) **شارةُ «تعديلاتٌ غير محفوظة» مشتقّةٌ من المحتوى**: عَلَمٌ يُرفع يدويّاً
//    يُنسى، فيغادر المستخدمُ ويفقد عملَه بلا سؤال.
//
// ‏٣) **التعديلُ يصل `TemplateDocument`**: وهو ما يُحفظ ويُطبع. وقياسُ ظهور
//    النصّ على الشاشة وحدَه يمرّ على محرّرٍ لا يكتب شيئاً.
//
// ‏٤) **وضعُ المعاينة يستدعي المحرّكَ** لا راسماً ثانياً.
//
// ⚠️ ولا قاعدةَ بيانات: المستودعُ يُستبدَل والمزوِّدُ يبقى.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/printing/template_document.dart';
import 'package:ural_erp/domain/printing/template_save_result.dart';
import 'package:ural_erp/domain/repositories/invoice_templates_repository.dart';
import 'package:ural_erp/presentation/template_editor_picpos/screens/template_editor_picpos_screen.dart';

final _t0 = DateTime.utc(2026, 1, 1);

InvoiceTemplate _template() => InvoiceTemplate(
      id: 1,
      name: 'فاتورة مبيعات ضريبية — A4',
      type: 'a4',
      templateCategory: 'invoice',
      isDefault: true,
      paperSize: 'A4',
      paperWidth: 210,
      paperHeight: 297,
      margins: '10,10,10,10',
      defaultFont: 'Cairo',
      defaultFontSize: 10,
      isActive: true,
      layoutVersion: 2,
      createdAt: _t0,
      updatedAt: _t0,
    );

InvoiceTemplateElement _el({
  required int id,
  required String band,
  required String content,
  String? labelAr,
  double x = 0,
  double y = 2,
  double w = 80,
  double h = 6,
  int sort = 0,
}) =>
    InvoiceTemplateElement(
      id: id,
      templateId: 1,
      elementType: 'variable',
      content: content,
      labelAr: labelAr,
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
      section: band,
      bandId: band,
      xMm: x,
      yMm: y,
      wMm: w,
      hMm: h,
    );

/// إعداداتُ جدولٍ بأعمدةٍ مسمّاة — لازمةٌ ليظهر محرّرُ الأعمدة أصلاً.
InvoiceTableSetting _tableSettings() => const InvoiceTableSetting(
      id: 1,
      templateId: 1,
      xPosition: 0,
      yPosition: 200,
      width: 500,
      fontSize: 9,
      showIndex: true,
      showProductCode: false,
      showProductName: true,
      showQuantity: true,
      showUnitPrice: true,
      showDiscount: false,
      showTax: false,
      showTotal: true,
      showUnit: false,
      showBarcode: false,
      showNotes: false,
      headerBgColor: '#333333',
      headerTextColor: '#FFFFFF',
      headerFontSize: 9,
      rowBgColor: '#FFFFFF',
      rowHeight: 6,
      tableKind: 'items',
      columnsJson:
          '[{"key":"index","labelAr":"م","flex":0.8,"decimals":0,"align":"center","visible":true},'
          '{"key":"name","labelAr":"الصنف","labelEn":"Item","flex":3,"decimals":0,"align":"start","visible":true},'
          '{"key":"total","labelAr":"الإجمالي","flex":1.5,"decimals":2,"align":"end","visible":true}]',
    );

class _FakeRepo implements IInvoiceTemplatesRepository {
  _FakeRepo(this.elements);

  final List<InvoiceTemplateElement> elements;

  /// آخرُ مستندٍ وصل الحفظَ — به يُقاس أنّ التعديلَ خرج من الشاشة.
  TemplateDocument? savedDocument;
  String? activatedType;
  int saveCalls = 0;

  @override
  Future<bool> migrateTemplateLayout(int id) async => false;

  @override
  Future<InvoiceTemplateWithData?> getTemplateWithData(int id) async =>
      InvoiceTemplateWithData(
        template: _template(),
        elements: elements,
        tableSettings: _tableSettings(),
      );

  @override
  Future<TemplateSaveResult> saveTemplateLayout({
    required int templateId,
    required TemplateDocument document,
    String? name,
    String? activateForDocumentType,
    int? activateBranchId,
    String? activateLocale,
  }) async {
    saveCalls++;
    savedDocument = document;
    activatedType = activateForDocumentType;
    final count =
        document.bands.fold<int>(0, (a, b) => a + b.elements.length);
    return TemplateSaveResult(
      elementCount: count,
      visibleColumnCount: document.table?.visibleColumns.length ?? 0,
      activated: activateForDocumentType != null,
    );
  }

  @override
  Future<List<InvoiceTemplate>> getAllTemplates() async => [_template()];

  @override
  Future<List<TemplateBinding>> getAllBindings() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRepo repo;

  final elements = [
    _el(id: 1, band: 'header', content: 'company_name',
        labelAr: 'اسم الشركة', w: 90, h: 8),
    _el(id: 2, band: 'totals', content: 'total',
        labelAr: 'الإجمالي المستحق', x: 110, w: 60, h: 8, sort: 1),
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    repo = _FakeRepo(elements);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceTemplatesRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: TemplateEditorPicposScreen(templateId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    // الإشعارُ يعيش خمسَ ثوانٍ بمؤقّتٍ حيّ — يُستهلَك قبل تفكيك الشجرة.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1920, 1080)),
      ('عرضٌ متوسّط', Size(1400, 900)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');
        expect(find.text('فاتورة مبيعات ضريبية — A4'), findsOneWidget);
        expect(find.text('بنية المستند'), findsOneWidget);
        await teardownTree(tester);
      });
    }

    testWidgets('واللوحتان تُطويان على الضيّق ويبقى الكانفاس', (tester) async {
      await open(tester, const Size(1100, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('بنية المستند'), findsNothing);
      expect(find.text('حفظ'), findsOneWidget,
          reason: 'الحفظُ لا يُطوى — بدونه يُفقد العمل');
      await teardownTree(tester);
    });
  });

  group('شارةُ التعديلات مشتقّةٌ من المحتوى', () {
    testWidgets('غائبةٌ عند الفتح', (tester) async {
      await open(tester, const Size(1920, 1080));
      expect(find.text('تعديلات غير محفوظة'), findsNothing);
      await teardownTree(tester);
    });

    testWidgets('وتظهر بعد أوّل تعديلٍ حقيقيّ', (tester) async {
      await open(tester, const Size(1920, 1080));

      await tester.tap(find.text('اسم الشركة').first);
      await tester.pumpAndSettle();
      // «عريض» في لوحة المظهر — تعديلٌ يمسّ المستند.
      await tester.tap(find.text('عريض'));
      await tester.pumpAndSettle();

      expect(find.text('تعديلات غير محفوظة'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('ولا تظهر بعد تحديدٍ مجرَّد — التحديدُ ليس تعديلاً',
        (tester) async {
      await open(tester, const Size(1920, 1080));
      await tester.tap(find.text('اسم الشركة').first);
      await tester.pumpAndSettle();
      expect(find.text('تعديلات غير محفوظة'), findsNothing,
          reason: 'شارةٌ تظهر بلا تعديلٍ تُدرَّب على تجاهلِها');
      await teardownTree(tester);
    });
  });

  group('التعديلُ يصل المستندَ المحفوظ', () {
    testWidgets('«حفظ» يمرّر المستندَ بتعديله — فحصُ القبول §٥', (tester) async {
      await open(tester, const Size(1920, 1080));

      await tester.tap(find.text('اسم الشركة').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عريض'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(repo.saveCalls, 1);
      final saved = repo.savedDocument!;
      final el = saved.bands
          .expand((b) => b.elements)
          .firstWhere((e) => e.contentKey == 'company_name');
      expect(el.bold, isTrue,
          reason: 'التعديلُ بقي في الشاشة ولم يصل ما يُحفَظ');
      expect(repo.activatedType, isNull,
          reason: '«حفظ» وحدَه لا يلمس الرابطات');
      await teardownTree(tester);
    });

    testWidgets('وعنوانُ العمود المعدَّلُ يصل المستند — فحصُ القبول §٢',
        (tester) async {
      await open(tester, const Size(1920, 1080));

      // محرّرُ الأعمدة يُبلَغ من **بنية المستند**: رأسُ الجدول على الورقة
      // هدفٌ صغيرٌ قد يقع خارجَ المرئيّ حين تطول.
      await tester.tap(find.text('جدول الأصناف'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, 'الصنف');
      expect(field, findsOneWidget,
          reason: 'حقلُ عنوان العمود غائبٌ — لا سبيلَ لتغييره');

      await tester.enterText(field, 'البيان');
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      final col = repo.savedDocument!.table!.columns
          .firstWhere((c) => c.key == 'name');
      expect(col.labelAr, 'البيان');
      await teardownTree(tester);
    });

    testWidgets('و«حفظ وتفعيل» يمرّر نوعَ المستند المختار', (tester) async {
      await open(tester, const Size(1920, 1080));

      await tester.tap(find.text('حفظ وتفعيل كافتراضي'));
      await tester.pumpAndSettle();

      expect(find.text('تفعيل كافتراضي لأيِّ مستند؟'), findsOneWidget);
      await tester.tap(find.text('فاتورة مبيعات'));
      await tester.pumpAndSettle();

      expect(repo.activatedType, 'sales_invoice');
      await teardownTree(tester);
    });
  });

  group('المعاينةُ بالمحرّك نفسِه', () {
    testWidgets('التبديلُ يعرض ورقةً مرقَّمةً لا كانفاساً', (tester) async {
      await open(tester, const Size(1920, 1080));

      expect(find.textContaining('صفحة'), findsNothing);
      await tester.tap(find.text('معاينة بالبيانات'));
      await tester.pumpAndSettle();

      // الترقيمُ يأتي من `LayoutEngine` — لا يوجد في وضع التحرير أصلاً.
      expect(find.textContaining('صفحة 1 من'), findsOneWidget,
          reason: 'المعاينةُ لم تمرّ بالمحرّك');
      expect(find.text('عودة للتحرير'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('ضابط: النطاقُ المقفولُ يشرح ولا يصمت', () {
    testWidgets('«يتمدّد بالبيانات» لا يُبدَّل ويقول لماذا', (tester) async {
      await open(tester, const Size(1920, 1080));

      await tester.tap(find.text('التفاصيل').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('يتمدّد بالبيانات'));
      await tester.pumpAndSettle();

      expect(
          find.text('لا يُبدَّل — هو ما يمنع الجدولَ من دهس ما بعده'),
          findsOneWidget,
          reason: 'الضغطُ على المقفول يشرح — وإلّا ظنّه المستخدمُ معطوباً');
      await teardownTree(tester);
    });
  });
}

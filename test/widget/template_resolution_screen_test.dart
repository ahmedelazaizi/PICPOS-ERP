// شاشةُ حسم القوالب — التركيبُ وصدقُ ما تعرضه.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التركيبُ على عرضين**: الشاشةُ جدولُ ستّةِ أعمدةٍ ولوحةٌ بعرض ٤٣٠.
//    وانهيارُ التخطيط لا يظهر في `analyze` إطلاقاً.
//
// ‏٢) **الحالُ مشتقٌّ من القاعدة لا مكتوب**: قالبٌ مربوطٌ ⇒ «مضبوط»، وبلا
//    رابطةٍ ولا افتراضيٍّ ⇒ «بلا قالب». وشارةٌ مكتوبةٌ بجانب ما تصفه تمرّ
//    خضراءَ وتكذب على المالك.
//
// ‏٣) **اللوحةُ تعرض الستّةَ كلَّها**: عرضُ الفائز وحدَه يجيب «ماذا» ولا يجيب
//    «لماذا لم تفز قاعدتي» — وهو السؤالُ الذي بُنيت له الشاشة.
//
// ⚠️ **ولا قاعدةَ بيانات هنا**: المستودعاتُ تُستبدَل بزائفةٍ **والمزوِّدُ
// يبقى** — فيُقاس توصيلُه لا يُلتفّ عليه. وفتحُ شاشةٍ على قاعدةٍ حيّةٍ في
// اختبار ودجت يعلّق (‏`db.close()` ينتظر مؤقّتَ drift في المنطقة الوهميّة).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/invoice_templates_repository.dart';
import 'package:ural_erp/domain/repositories/printers_repository.dart';
import 'package:ural_erp/presentation/template_resolution_picpos/screens/template_resolution_picpos_screen.dart';

final _t0 = DateTime.utc(2026, 1, 1);

InvoiceTemplate _template(
  int id,
  String name, {
  required String type,
  required String category,
  double width = 210,
  bool isDefault = false,
}) =>
    InvoiceTemplate(
      id: id,
      name: name,
      type: type,
      templateCategory: category,
      isDefault: isDefault,
      paperSize: width > 100 ? 'A4' : 'thermal',
      paperWidth: width,
      margins: '10,10,10,10',
      defaultFont: 'Cairo',
      defaultFontSize: 10,
      isActive: true,
      layoutVersion: 1,
      createdAt: _t0,
      updatedAt: _t0,
    );

TemplateBinding _binding(
  int id, {
  required String documentType,
  required int templateId,
  int? branchId,
  String? locale,
  int copies = 1,
}) =>
    TemplateBinding(
      id: id,
      documentType: documentType,
      templateId: templateId,
      branchId: branchId,
      locale: locale,
      copies: copies,
      directPrint: false,
      priority: 0,
      createdAt: _t0,
      updatedAt: _t0,
    );

/// مستودعُ قوالبَ زائفٌ يخدم الثلاثَ التي تقرؤها الشاشة.
///
/// `noSuchMethod` تغطّي الباقي فترمي: الشاشةُ لا يجوز أن تنادي غيرَها.
class _FakeTemplatesRepo implements IInvoiceTemplatesRepository {
  _FakeTemplatesRepo(this.templates, this.bindings);

  final List<InvoiceTemplate> templates;
  final List<TemplateBinding> bindings;

  @override
  Future<List<InvoiceTemplate>> getAllTemplates() async => templates;

  @override
  Future<List<TemplateBinding>> getAllBindings() async => bindings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrintersRepo implements IPrintersRepository {
  _FakePrintersRepo(this.printers);

  final List<Printer> printers;

  @override
  Future<List<Printer>> getPrinters() async => printers;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // تجهيزةٌ تُنتج ثلاثةَ أحوالٍ مختلفةٍ **من البيانات وحدَها**:
  //   • `sales_invoice` ⇐ رابطةٌ عامّةٌ صريحة        ⇒ «مضبوط»
  //   • `sales_receipt` ⇐ افتراضيُّ فئةٍ لا يتقاسمه أحد ⇒ «بالفئة»
  //   • ما عداهما بلا رابطةٍ ولا افتراضيّ            ⇒ «بلا قالب»
  final templates = [
    _template(1, 'فاتورة مبيعات ضريبية — A4',
        type: 'a4', category: 'invoice'),
    _template(2, 'بيع سريع حراري — 80mm',
        type: 'thermal', category: 'receipt', width: 80, isDefault: true),
  ];

  final bindings = [
    _binding(1, documentType: 'sales_invoice', templateId: 1, copies: 2),
  ];

  const branches = [
    Branche(id: 1, name: 'فرع المعادي', isActive: true,
        isSystemDefault: true, rowVersion: 0),
    Branche(id: 2, name: 'فرع مدينة نصر', isActive: true,
        isSystemDefault: false, rowVersion: 0),
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceTemplatesRepositoryProvider
              .overrideWithValue(_FakeTemplatesRepo(templates, bindings)),
          printersRepositoryProvider
              .overrideWithValue(_FakePrintersRepo(const [])),
          allBranchesProvider.overrideWith((ref) => Stream.value(branches)),
        ],
        child: const MaterialApp(home: TemplateResolutionPicposScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1920, 1080)),
      ('عرضٌ ضيّق', Size(1280, 800)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');

        // ومحتوىً ظاهرٌ فعلاً — لا شجرةٌ فارغةٌ تمرّ خضراء.
        expect(find.text('حسم القوالب والطابعات'), findsOneWidget);
        expect(find.text('فاتورة مبيعات'), findsWidgets);
        expect(find.text('طلب مطبخ'), findsWidgets);
        await teardownTree(tester);
      });
    }

    testWidgets('واللوحةُ تُطوى تحت العرض الأدنى ولا تنهار', (tester) async {
      await open(tester, const Size(900, 760));
      expect(tester.takeException(), isNull);
      expect(find.text('حسم القوالب والطابعات'), findsOneWidget);
      // الجدولُ باقٍ واللوحةُ غائبة.
      expect(find.text('فاتورة مبيعات'), findsWidgets);
      expect(find.text('سلسلة السقوط'), findsNothing);
      await teardownTree(tester);
    });
  });

  group('الحالُ مشتقٌّ من القاعدة لا مكتوب', () {
    testWidgets('رابطةٌ صريحةٌ ⇒ «مضبوط» · افتراضيُّ فئةٍ ⇒ «بالفئة»',
        (tester) async {
      await open(tester, const Size(1920, 1080));

      // `sales_invoice` أوّلُ صفٍّ فهو المحدَّد ابتداءً، فحالُه يظهر
      // **مرّتين**: شارةً في الجدول وعنواناً لصندوق الحكم في اللوحة.
      expect(find.text('مضبوط'), findsNWidgets(2),
          reason: 'رابطةُ `sales_invoice` وحدَها صريحة — شارةٌ وحكم');
      expect(find.text('بالفئة'), findsOneWidget,
          reason: 'افتراضيُّ (thermal, receipt) يخدم `sales_receipt` وحدَه، '
              'وهو غيرُ محدَّدٍ فلا حكمَ له في اللوحة');

      // والقالبُ المحسومُ يُقرأ باسمه من القاعدة.
      expect(find.text('فاتورة مبيعات ضريبية — A4'), findsWidgets);
      await teardownTree(tester);
    });

    testWidgets('وما لا قالبَ له ⇒ «بلا قالب» — بعدد الأنواع الباقية',
        (tester) async {
      await open(tester, const Size(1920, 1080));
      // عشرةُ أنواعٍ، اثنان محسومان ⇒ ثمانيةٌ بلا قالب.
      expect(find.text('بلا قالب'), findsNWidgets(8));
      await teardownTree(tester);
    });

    testWidgets('وعدّادُ الترويسة يعدّ ما تعرضه الشجرةُ نفسُها',
        (tester) async {
      await open(tester, const Size(1920, 1080));
      expect(find.text('مسارات الطباعة'), findsWidgets);
      expect(find.text('حسم سليم'), findsOneWidget);
      expect(find.text('يحتاج معالجة'), findsOneWidget);
      // ثمانيةٌ «بلا قالب» — وهي الحمراءُ الوحيدةُ في هذه التجهيزة.
      expect(find.text('8'), findsWidgets, reason: 'عدّادُ «يحتاج معالجة» ليس ٨');
      await teardownTree(tester);
    });
  });

  group('اللوحةُ تشرح السلسلةَ كاملةً', () {
    testWidgets('المستوياتُ الستّةُ معروضةٌ وفائزٌ واحدٌ موسوم', (tester) async {
      await open(tester, const Size(1920, 1080));

      expect(find.text('سلسلة السقوط'), findsOneWidget);
      for (final level in const [
        '١ · مستند + فرع + طابعة + لغة',
        '٢ · مستند + فرع + لغة',
        '٣ · مستند + لغة',
        '٤ · مستند',
        '٥ · الفئة (السلوك القائم)',
        '٦ · التصميم المدمج في الكود',
      ]) {
        expect(find.text(level), findsOneWidget, reason: 'المستوى «$level» غائب');
      }

      expect(find.text('المُطبَّق'), findsOneWidget,
          reason: 'فائزان معروضان = سلسلةٌ تكذب');
      await teardownTree(tester);
    });

    testWidgets('والمفتاحُ المعروضُ يتبع الفرعَ المختار', (tester) async {
      await open(tester, const Size(1920, 1080));

      // «كل الفروع» ابتداءً: الأوّلُ يشترط فرعاً ولم يُعطَ، فشَرطةٌ لا نجمة.
      expect(find.text('sales_invoice · — · — · ar'), findsOneWidget);
      expect(find.text('sales_invoice · * · * · ar'), findsOneWidget);

      await tester.tap(find.text('فرع مدينة نصر'));
      await tester.pumpAndSettle();

      expect(find.text('sales_invoice · 2 · — · ar'), findsOneWidget,
          reason: 'المفتاحُ لا يتبع المرشِّح — فالشاشةُ تصف حسماً غيرَ '
              'المطلوب');
      expect(find.text('sales_invoice · 2 · * · ar'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('والمستوياتُ الأربعةُ الأولى بمفاتيحَ متمايزة', (tester) async {
      // أربعةُ سطورٍ بمفتاحٍ واحدٍ لا تقول أيُّها أخفق ولماذا.
      await open(tester, const Size(1920, 1080));
      for (final key in const [
        'sales_invoice · — · — · ar',
        'sales_invoice · — · * · ar',
        'sales_invoice · * · * · ar',
        'sales_invoice · * · * · *',
      ]) {
        expect(find.text(key), findsOneWidget, reason: 'المفتاحُ «$key»');
      }
      await teardownTree(tester);
    });

    testWidgets('واللغةُ كذلك تدخل المفتاح', (tester) async {
      await open(tester, const Size(1920, 1080));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('sales_invoice · * · * · en'), findsOneWidget);
      await teardownTree(tester);
    });
  });
}

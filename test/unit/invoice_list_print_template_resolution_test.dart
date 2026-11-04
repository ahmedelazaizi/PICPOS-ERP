// زرُّ «طباعة» في قائمة فواتير البيع وتفاصيلها يحسم القالبَ المربوط.
//
// الجولة الحيّة 2026-11-04 (`docs/plans/2026-11-04-live-final4.md`) على قاعدة
// sandbox فيها:
//   sales_invoice → طابعة «QA A4» (‏210مم) → «فاتورة A4»
//   sales_return  → طابعة «QA 80» (‏80مم)  → «إيصال مرتجع مبيعات»
// والطابعتان كلتاهما بغرض `pos_receipt`.
//
// العيبان: (١) SINV-6 خرجت بالقالب الحراريّ الافتراضيّ بعرض ٧٢مم داخل صفحة
// A4 — المنادي `printReceipt` (‏`sales_receipt`) لا يستشير رابطةَ
// `sales_invoice` أصلاً. (٢) «طباعة» تفاصيل SINV-7 المرتجَعة أخرجت الفاتورةَ
// الأصليّة، لا إيصالَ المرتجع.
//
// كلُّ شيءٍ هنا بلا طابعة: `PdfComputeHelper.nativeLayoutOverride` يلتقط
// البايتات التي كانت ستذهب إلى الحوار/الطابعة، و`probePdf` يقرأ الصفحة.
//
// `PICPOS_PRINT_FIX_OUT` (‏متغيّرُ بيئة) يحفظ ملفّاتِ PDF الناتجة للتقرير.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart'
    show returnsRepositoryProvider, productRepositoryProvider,
        salesRepositoryProvider;
import 'package:picpos_erp/services/printing/document_print_route.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:picpos_erp/services/printing/posted_sales_return_print.dart';
import 'package:picpos_erp/services/printing/template_migration.dart';
import 'package:picpos_erp/services/printing_service.dart';

import '../helpers/pdf_probe.dart';
import '../scenarios/scenario_world.dart';

const _mmToPt = 72 / 25.4;
const _a4WidthPt = 210 * _mmToPt;

/// عالَمُ الجولة الحيّة: القوالبُ المبذورة (‏A4 والمرتجع مهاجَران إلى v2 كما
/// في sandbox)، وطابعتان بغرض `pos_receipt` — A4 أوّلاً كما في الحاوية.
class _LiveWorld {
  _LiveWorld(this.w, this.thermalReceiptId, this.a4InvoiceId, this.returnId,
      this.a4Printer, this.printer80);

  final ScenarioWorld w;
  final int thermalReceiptId;
  final int a4InvoiceId;
  final int returnId;
  final int a4Printer;
  final int printer80;

  AppDatabase get db => w.db;

  PrintingServiceImpl get printing =>
      PrintingServiceImpl(db, w.container.read(salesRepositoryProvider));

  static Future<_LiveWorld> create() async {
    final w = await ScenarioWorld.create();
    final db = w.db;
    await db.seedDefaultTemplates();
    final all = await db.getAllTemplates();
    int idOf(String type, String category) => all
        .firstWhere((t) =>
            t.type == type && t.templateCategory == category && t.isDefault)
        .id;
    final thermal = idOf('thermal', 'receipt');
    final a4 = idOf('a4', 'invoice');
    final ret = idOf('thermal', 'sales_return');
    await TemplateMigration.migrate(db, a4);
    await TemplateMigration.migrate(db, ret);
    final a4Printer = await db.insertPrinter(
        name: 'QA A4', port: 'PicPos QA PDF A4', paperWidthMm: 210);
    final printer80 = await db.insertPrinter(
        name: 'QA 80', port: 'PicPos QA PDF 80', paperWidthMm: 80);
    return _LiveWorld(w, thermal, a4, ret, a4Printer, printer80);
  }

  Future<void> bindLikeSandbox() async {
    await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: a4InvoiceId,
        printerId: a4Printer,
        locale: 'ar');
    await db.activateBinding(
        documentType: 'sales_return',
        templateId: returnId,
        printerId: printer80,
        locale: 'ar');
  }

  /// فاتورةٌ بصنفين (٢ × 6.99 و١ × 37) — ثمّ مرتجعُ قطعةٍ واحدةٍ من الأوّل.
  Future<({int invoiceId, int returnedProduct})> sellAndReturnOne() async {
    final a = await w.addProduct('A1', price: 6.99, cost: 3, stock: 10);
    final b = await w.addProduct('B2', price: 37, cost: 20, stock: 10);
    final sale = await w.sell([w.line(a, 2, 6.99), w.line(b, 1, 37)]);
    final id = sale.invoiceId!;
    expect(await w.returnItems(id, a, 1), isTrue, reason: 'مرساة: المرتجعُ رُحِّل');
    return (invoiceId: id, returnedProduct: a);
  }
}

/// كلُّ ما «طُبع» في الاختبار — بايتاتٌ لا ورق.
final _captured = <Uint8List>[];

Future<void> _save(String name, Uint8List bytes) async {
  final dir = Platform.environment['PICPOS_PRINT_FIX_OUT'];
  if (dir == null || dir.isEmpty) return;
  await Directory(dir).create(recursive: true);
  await File('$dir/$name').writeAsBytes(bytes);
}

String _texts(PdfProbe p) => p.allTexts.map((t) => t.text).join(' ');

/// أرقامٌ بخانتين لا تنكسر: «0.0» ثمّ «0» على سطرٍ تالٍ هو التفافُ العمود.
List<String> _brokenNumbers(PdfProbe p) => [
      for (final t in p.allTexts)
        if (RegExp(r'^\d+\.\d$').hasMatch(t.text.trim())) t.text,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LiveWorld lw;
  setUp(() async {
    _captured.clear();
    PdfComputeHelper.nativeLayoutOverride = (bytes, _) async {
      _captured.add(bytes);
      return true;
    };
    PdfComputeHelper.directPrintOverride = (_, bytes) async {
      _captured.add(bytes);
      return true;
    };
    lw = await _LiveWorld.create();
  });
  tearDown(() async {
    PdfComputeHelper.nativeLayoutOverride = null;
    PdfComputeHelper.directPrintOverride = null;
    await lw.w.dispose();
  });

  test('(١) فاتورة بيع من القائمة ⇒ قالب A4 المربوط بعرض A4 كامل', () async {
    await lw.bindLikeSandbox();
    final sale = await lw.sellAndReturnOne();

    // الطابعةُ المحسومة هي المربوطة لا «أوّلُ pos_receipt».
    expect(
      await resolveDocumentPrinterId(lw.db,
          documentType: 'sales_invoice', locale: 'ar'),
      lw.a4Printer,
    );
    final bound = await boundDocumentTemplate(lw.db,
        documentType: 'sales_invoice',
        category: 'invoice',
        printerId: lw.a4Printer,
        locale: 'ar');
    expect(bound?.template.id, lw.a4InvoiceId,
        reason: 'القالبُ المختار يجب أن يكون «فاتورة A4» المربوط');

    // «قبل»: المسارُ القديمُ نفسُه (‏printReceipt) — القالبُ الحراريّ.
    expect(await lw.printing.printReceipt(sale.invoiceId), isTrue);
    final beforeBytes = _captured.removeLast();
    await _save('before_sales_invoice_receipt_path.pdf', beforeBytes);
    final before = probePdf(beforeBytes);

    expect(await lw.printing.printSalesInvoiceDocument(sale.invoiceId), isTrue);
    expect(_captured, hasLength(1));
    final bytes = _captured.single;
    await _save('after_sales_invoice_a4.pdf', bytes);
    final after = probePdf(bytes);

    expect(before.pages.first.widthPts, lessThan(90 * _mmToPt),
        reason: 'مرساة: المسارُ القديمُ يرسم الإيصالَ الحراريّ');
    expect(after.pages.first.widthPts, closeTo(_a4WidthPt, 1),
        reason: 'صفحةُ A4 بعرضها الكامل');
    final xs = [for (final t in after.allTexts) t.x];
    final span = xs.reduce((a, b) => a > b ? a : b) -
        xs.reduce((a, b) => a < b ? a : b);
    expect(span, greaterThan(120 * _mmToPt),
        reason: 'المحتوى ممتدٌّ على عرض A4 لا محصورٌ في ٧٢مم');
    expect(_brokenNumbers(before), isNotEmpty,
        reason: 'مرساة: الفحصُ يرى «0.0» المكسورة في الإيصال الضيّق (عيبُ SINV-6)');
    expect(_brokenNumbers(after), isEmpty,
        reason: 'لا التفافَ لأعمدة الجدول الرقميّة');
    final invoice = await lw.db.getSalesInvoiceById(sale.invoiceId);
    expect(_texts(after), contains(invoice!.invoiceNumber));
    expect(after.fingerprint(), isNot(before.fingerprint()));

    // والسجلُّ يقول بأيِّ قالبٍ طُبعت.
    final log = await (lw.db.select(lw.db.activityLogs)
          ..where((l) => l.action.equals('print_invoice')))
        .get();
    expect(log.last.description, contains('فاتورة A4'));
  });

  test('(٢) طباعة المرتجع ⇒ قالب sales_return المربوط وبيانات المرتجع', () async {
    await lw.bindLikeSandbox();
    final sale = await lw.sellAndReturnOne();

    expect(
      await resolveDocumentPrinterId(lw.db, documentType: 'sales_return'),
      lw.printer80,
      reason: 'طابعةُ A4 أُدرجت أوّلاً بنفس الغرض — والرابطةُ تفوز',
    );
    final resolved = await lw.db.resolveTemplateFor(
        documentType: 'sales_return',
        category: 'sales_return',
        printerId: lw.printer80,
        locale: 'ar',
        paperType: 'thermal');
    expect((resolved.templateId, resolved.level), (lw.returnId, 1));

    final outcome = await printPostedSalesReturn(
      db: lw.db,
      returns: lw.w.container.read(returnsRepositoryProvider),
      products: lw.w.container.read(productRepositoryProvider),
      originalInvoiceId: sale.invoiceId,
    );
    expect(outcome, PostedReturnPrintOutcome.printed);
    expect(_captured, hasLength(1));
    await _save('after_sales_return_80.pdf', _captured.single);
    final p = probePdf(_captured.single);

    // ورقُ ٨٠مم يُرسم بمساحته المطبوعة ٧٢مم (‏`TemplateRenderPipeline`).
    expect(p.pages.first.widthPts, closeTo(72 * _mmToPt, 1),
        reason: 'إيصالُ المرتجع ٨٠مم — لا صفحةُ الفاتورة A4');
    final text = _texts(p);
    expect(text, contains('6.99'), reason: 'المبلغُ المسترد = قطعةٌ واحدة');
    expect(text, isNot(contains('37.00')),
        reason: 'الصنفُ غيرُ المرتجَع لا يظهر على الإيصال');
    expect(text, isNot(contains('50.98')),
        reason: 'إجماليُّ الفاتورة الأصليّة ليس مبلغَ المرتجع');
    final invoice = await lw.db.getSalesInvoiceById(sale.invoiceId);
    expect(text, contains(invoice!.invoiceNumber),
        reason: 'رقمُ الفاتورة الأصليّة مرجعاً على الإيصال');
    expect(text, contains('SRET-'), reason: 'رقمُ سند المرتجع هو رقمُ المستند');

    // «قبل»: زرُّ التفاصيل الوحيد كان يطبع الفاتورةَ الأصليّة بمسار الإيصال.
    expect(await lw.printing.printReceipt(sale.invoiceId), isTrue);
    final oldBytes = _captured.removeLast();
    await _save('before_return_detail_receipt_path.pdf', oldBytes);
    final old = probePdf(oldBytes);
    expect(_texts(old), contains('37.00'),
        reason: 'مرساة: المسارُ القديمُ يطبع بنودَ الفاتورة كلَّها');
    expect(old.fingerprint(), isNot(p.fingerprint()));
  });

  test('ولا مرتجعَ مرحَّلاً ⇒ لا ورقة', () async {
    await lw.bindLikeSandbox();
    final a = await lw.w.addProduct('C3', price: 10, stock: 5);
    final sale = await lw.w.sell([lw.w.line(a, 1, 10)]);
    final outcome = await printPostedSalesReturn(
      db: lw.db,
      returns: lw.w.container.read(returnsRepositoryProvider),
      products: lw.w.container.read(productRepositoryProvider),
      originalInvoiceId: sale.invoiceId!,
    );
    expect(outcome, PostedReturnPrintOutcome.noReturnData);
    expect(_captured, isEmpty);
  });

  test('(٣) بلا ربط ⇒ السلوكُ القائم بحرفه (الإيصال الحراريّ)', () async {
    final sale = await lw.sellAndReturnOne();

    expect(await lw.printing.printReceipt(sale.invoiceId), isTrue);
    final legacy = probePdf(_captured.removeLast());
    expect(await lw.printing.printSalesInvoiceDocument(sale.invoiceId), isTrue);
    final nowBytes = _captured.removeLast();
    await _save('no_binding_sales_invoice.pdf', nowBytes);
    final now = probePdf(nowBytes);

    expect(now.fingerprint(), legacy.fingerprint(),
        reason: 'بلا رابطةٍ لا يتغيّر مطبوعُ أحد');
    expect(now.pages.first.widthPts, lessThan(90 * _mmToPt));
  });

  test('ورابطةٌ عامّةٌ لقالب A4 على طابعةٍ حراريّة ⇒ القالبُ الحراريّ لا القصّ',
      () async {
    // طابعةُ ٨٠مم وحدَها نشطة، ورابطةُ `sales_invoice` بلا طابعة إلى A4.
    await lw.db.updatePrinter(
        id: lw.a4Printer, name: 'QA A4', paperWidthMm: 210, isActive: false);
    await lw.db.activateBinding(
        documentType: 'sales_invoice', templateId: lw.a4InvoiceId);
    final sale = await lw.sellAndReturnOne();

    expect(
      await boundDocumentTemplate(lw.db,
          documentType: 'sales_invoice',
          category: 'invoice',
          printerId: lw.printer80,
          locale: 'ar'),
      isNull,
      reason: 'A4 ‏210مم على ٨٠مم يُرفض — `checkPaperFit`',
    );
    expect(await lw.printing.printSalesInvoiceDocument(sale.invoiceId), isTrue);
    final p = probePdf(_captured.single);
    expect(p.pages.first.widthPts, lessThan(90 * _mmToPt));
  });

  test('returnedSaleUnitsByItem — بسقف المباع وبوحدة البيع', () async {
    final sale = await lw.sellAndReturnOne();
    final items = await lw.db.getSalesInvoiceItems(sale.invoiceId);
    final q = returnedSaleUnitsByItem(
        items, await lw.db.getReturnedQuantitiesForInvoice(sale.invoiceId));
    final returned = items.firstWhere((i) => i.productId == sale.returnedProduct);
    expect(q[returned.id], closeTo(1, kEps));
    expect(
      [for (final i in items) if (i.id != returned.id) q[i.id]],
      everyElement(closeTo(0, kEps)),
    );
  });
}

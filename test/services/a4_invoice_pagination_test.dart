// ═══════════════════════════════════════════════════════════════════════════
// فاتورة A4 — كانت بتفقد سطوراً والإجماليات بالكامل، بصمت.
// ═══════════════════════════════════════════════════════════════════════════
//
// `printSalesInvoice` و`printPurchaseInvoice` كانوا بيستعملوا `pw.Page`
// (صفحة واحدة ثابتة) بينما باقي التقارير في **نفس الملف** بتستعمل `MultiPage`.
//
// و`pw.Table` في حزمة pdf هي SpanningWidget (pdf-3.12.0 table.dart:250)، بس
// بروتوكول التقسيم بيشغّله MultiPage بس. جوّه Page عادية الجدول بيقصّ عند:
//     if (totalHeight + lineHeight > constraints.maxHeight) { index--; break; }
//     (pdf-3.12.0/lib/src/widgets/table.dart:473)
// وبعده `_buildTotalsSection` بيتخطّط بره حدود الصفحة فما بيطبعش.
//
// النتيجة: فاتورة جملة بـ٣٥ سطر ⇒ ~٢٠ سطر مطبوع، **من غير أي إجمالي**، وبلا
// أي استثناء ولا لوج. مستند تجاري ناقص بيتسلّم للعميل.
//
// الاختبار ده بينده دالة بناء المستند **الإنتاجية** (اللي بيندهها
// printSalesInvoice بالظبط) — مش نسخة محاكية للمنطق.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ural_erp/services/printing/printing_models.dart';
import 'package:ural_erp/services/printing/report_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<InvoiceItem> itemsOf(int n) => List.generate(
        n,
        (i) => InvoiceItem(
          name: 'صنف رقم ${i + 1} بوصف طويل نسبياً زي الواقع',
          quantity: (i % 5) + 1,
          price: 12.5 + i,
          total: ((i % 5) + 1) * (12.5 + i),
          barcode: '62912340000${i.toString().padLeft(2, '0')}',
        ),
      );

  Future<int> salesPages(int itemCount) async {
    final doc = await ReportPdfGenerator.buildSalesInvoiceDocument(
      invoiceNumber: 'INV-1',
      date: DateTime(2026, 8, 5),
      customerName: 'عميل جملة',
      items: itemsOf(itemCount),
      subtotal: 1000,
      discount: 50,
      tax: 95,
      total: 1045,
      paid: 500,
      companyName: 'شركة الاختبار',
    );
    await doc.save();
    return doc.document.pdfPageList.pages.length;
  }

  Future<int> purchasePages(int itemCount) async {
    final doc = await ReportPdfGenerator.buildPurchaseInvoiceDocument(
      invoiceNumber: 'PINV-1',
      date: DateTime(2026, 8, 5),
      supplierName: 'مورد جملة',
      items: itemsOf(itemCount),
      total: 1045,
      paid: 500,
      companyName: 'شركة الاختبار',
    );
    await doc.save();
    return doc.document.pdfPageList.pages.length;
  }

  group('فاتورة مبيعات A4', () {
    test('فاتورة قصيرة تفضل صفحة واحدة (مفيش ارتداد للحالة العادية)', () async {
      expect(await salesPages(3), 1);
    });

    test('٦٠ صنف بتتقسّم على أكتر من صفحة بدل ما تتقصّ', () async {
      expect(await salesPages(60), greaterThan(1),
          reason: 'قبل الإصلاح: صفحة واحدة والباقي بيختفي بصمت');
    });

    test('عدد الصفحات بيزيد مع عدد الأصناف — مفيش سقف صامت', () async {
      final p60 = await salesPages(60);
      final p160 = await salesPages(160);
      expect(p160, greaterThan(p60),
          reason: 'لو الرقم اتثبّت يبقى فيه قصّ تاني في مكان ما');
    });
  });

  // ضابط — بيرصد آلية العطل نفسها بدل ما يستنتجها. نفس الجدول بالظبط،
  // الفرق الوحيد Page مقابل MultiPage. لو الضابط ده وقع يوماً (يعني pw.Page
  // بقت بتقسّم لوحدها) يبقى مبرّر الإصلاح اتغيّر ولازم يتراجَع.
  group('ضابط: pw.Page بتقصّ، MultiPage لأ', () {
    pw.Table sixtyRowTable() => pw.Table(
          border: pw.TableBorder.all(),
          children: List.generate(
            60,
            (i) => pw.TableRow(
              children: [pw.Text('سطر رقم ${i + 1}')],
            ),
          ),
        );

    test('pw.Page بـ٦٠ صف = صفحة واحدة (الصفوف الزيادة بتختفي)', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(children: [sixtyRowTable()]),
      ));
      await doc.save();
      expect(doc.document.pdfPageList.pages.length, 1,
          reason: 'ده هو العطل: صفحة واحدة مهما كان عدد الصفوف');
    });

    test('MultiPage بنفس الجدول = أكتر من صفحة', () async {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [sixtyRowTable()],
      ));
      await doc.save();
      expect(doc.document.pdfPageList.pages.length, greaterThan(1),
          reason: 'نفس الجدول — الفرق الوحيد نوع الصفحة');
    });
  });

  group('فاتورة مشتريات A4', () {
    test('فاتورة قصيرة تفضل صفحة واحدة', () async {
      expect(await purchasePages(3), 1);
    });

    test('٦٠ صنف بتتقسّم على أكتر من صفحة', () async {
      expect(await purchasePages(60), greaterThan(1));
    });
  });
}

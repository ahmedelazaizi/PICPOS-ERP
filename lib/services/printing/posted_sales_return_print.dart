/// إيصالُ مرتجعٍ **مرحَّلٍ** لفاتورة بيع — من تفاصيل الفاتورة أو سجلّ المرتجعات.
///
/// ── العطبُ الذي يسدّه (الجولة الحيّة 2026-11-04) ─────────────────────────
/// زرُّ «طباعة» الوحيد في تفاصيل فاتورةٍ مرتجَعة (‏SINV-7) كان يطبع **الفاتورةَ
/// الأصلية** بمسار الإيصال — لا مسارَ في الواجهة يطبع إيصالَ المرتجع لفاتورةٍ
/// بعد الترحيل. وإعادةُ الطباعة من السجلّ كانت تُسقط الكمّيات المرتجعة فعلاً
/// وتطبع **كلَّ بنود الفاتورة** (فرعُ «من السجلّ» في
/// `getSalesReturnPrintData`)، فمرتجعُ صنفٍ من عشرةٍ يُطبع عشرة.
///
/// وهنا تُبنى البنودُ من الكمّيّات المرتجعة الصافية (‏`stock_movements` بعد
/// الإلغاءات — نفسُ قراءة سقف المرتجع)، ويُطبع المستندُ بنوع `sales_return`
/// على الطابعة المربوطة به (‏`InvoiceGenerator.printSalesReturnReceipt`).
library;

import '../../data/database/database.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../../domain/repositories/returns_repository.dart';
import '../invoice_generator.dart';

/// ما انتهت إليه محاولةُ طباعة إيصال المرتجع.
enum PostedReturnPrintOutcome {
  printed,

  /// أُلغي حوارُ الطباعة أو تعذّر الإرسال.
  cancelled,

  /// لا مرتجعَ مرحَّلاً لهذه الفاتورة — لا ورقةَ تُطبع.
  noReturnData,
}

/// الكمّيّاتُ المرتجعةُ بوحدة البيع لكلّ بند — `{معرّفُ البند: الكمّيّة}`.
///
/// [returnedBaseByProduct] بالوحدة الأساسيّة لكلّ صنف (‏`getReturnedQuantitiesForInvoice`)،
/// ويُوزَّع على بنود الصنف بالترتيب بسقف المباع — **نفسُ** خوارزمية
/// `SalesReturnNotifier` عند فتح الاستمارة، فلا يفترق المطبوعُ عن المعروض.
Map<int, double> returnedSaleUnitsByItem(
  List<SalesInvoiceItem> items,
  Map<int, double> returnedBaseByProduct,
) {
  final remaining = Map<int, double>.from(returnedBaseByProduct);
  final out = <int, double>{};
  for (final item in items) {
    final factor = item.quantityInBase > 0 ? item.quantityInBase : 1.0;
    final returnedBase = (remaining[item.productId] ?? 0)
        .clamp(0.0, item.quantity * factor)
        .toDouble();
    out[item.id] = returnedBase / factor;
    remaining[item.productId] = (remaining[item.productId] ?? 0) - returnedBase;
  }
  return out;
}

/// يطبع إيصالَ مرتجع [originalInvoiceId] ببنوده المرتجعة ومبلغه المسترد.
///
/// [returnTotal] المبلغُ المستردُّ كما يعرضه المنادي (عمودُ المرتجع في القائمة
/// أو صفُّ السجلّ). غيابُه ⇒ يُقرأ من `getReturnedAmountsForInvoices`.
Future<PostedReturnPrintOutcome> printPostedSalesReturn({
  required AppDatabase db,
  required IReturnsRepository returns,
  required IProductRepository products,
  required int originalInvoiceId,
  double? returnTotal,
  String? employeeName,
}) async {
  final invoice = await db.getSalesInvoiceById(originalInvoiceId);
  if (invoice == null) return PostedReturnPrintOutcome.noReturnData;

  final items = await returns.getSalesInvoiceItems(originalInvoiceId);
  final quantities = returnedSaleUnitsByItem(
    items,
    await returns.getReturnedQuantitiesForInvoice(originalInvoiceId),
  );
  final hasLines = quantities.values.any((q) => q > 0);
  final refund = (returnTotal != null && returnTotal > 0)
      ? returnTotal
      : ((await db.getReturnedAmountsForInvoices([originalInvoiceId]))[
                  originalInvoiceId] ??
              0)
          .abs();
  if (!hasLines && refund <= 0) return PostedReturnPrintOutcome.noReturnData;

  final cache = {
    for (final p in await products.getProductsByIds(
      items.map((i) => i.productId).toSet().toList(),
    ))
      p.id: p,
  };
  // بلا حركاتِ مخزونٍ محلّيّة (‏عميلٌ لم يسحب حركات الخادم بعد) يبقى فرعُ
  // «من السجلّ» القائمُ كما هو — أفضلُ من ألّا يُطبع شيء.
  final data = await returns.getSalesReturnPrintData(
    invoiceNumber: invoice.invoiceNumber,
    returnTotal: refund,
    selectedInvoice: hasLines ? invoice : null,
    invoiceItems: hasLines ? items : null,
    productCache: hasLines ? cache : null,
    returnQuantities: hasLines ? quantities : null,
  );
  if (data == null || data.items.isEmpty) {
    return PostedReturnPrintOutcome.noReturnData;
  }

  final total =
      refund > 0 ? refund : data.items.fold<double>(0, (s, i) => s + i.total);
  final printed = await InvoiceGenerator.printSalesReturnReceipt(
    db: db,
    returnVoucherNumber:
        data.returnVoucherNumber ?? 'SRET-${invoice.invoiceNumber}',
    originalInvoiceNumber: invoice.invoiceNumber,
    date: DateTime.now(),
    items: data.items,
    returnTotal: total,
    paymentMethod: data.paymentMethod,
    cashRefund: data.cashRefund,
    bankRefund: data.bankRefund,
    customerName: data.customerName,
    companyName: data.receiptSettings.companyName,
    companyPhone: data.receiptSettings.companyPhone,
    companyAddress: data.receiptSettings.companyAddress,
    employeeName: employeeName,
  );
  return printed
      ? PostedReturnPrintOutcome.printed
      : PostedReturnPrintOutcome.cancelled;
}

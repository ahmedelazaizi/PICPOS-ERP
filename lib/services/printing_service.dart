import '../data/database/database_barrel.dart';
import '../domain/repositories/sales_repository.dart';
import '../core/logging/app_logger.dart';
import 'invoice_generator.dart';
import 'templated_invoice_service.dart';
import 'printing/printing_models.dart' as print_models;
import '../data/services/receipt_qr_resolver.dart';
import '../domain/models/receipt_qr_decision.dart';

abstract class IPrintingService {
  /// يطبع إيصالَ نقطةِ البيع. يرجع `true` إن خرج الإيصالُ فعلاً.
  ///
  /// ⚠️ **والقيمةُ ليست زينة**: الجسمُ كلُّه ملفوفٌ في `try/catch` لا يُعيد
  /// الرمي، فالدالّةُ **لا ترمي أبداً**. ومناديها في نقطة البيع كان يستنتج
  /// النجاحَ من غياب الاستثناء — فيقول «تم حفظ وطباعة الفاتورة» ولا ورقةَ
  /// خرجت، ويبقى تحذيرُ «فشلت الطباعة» كوداً ميّتاً لا يظهر قطّ، وحلقةُ
  /// النسخِ تُعيد المحاولةَ على طابعةٍ عاطلةٍ لأنّ `if (!printed) break`
  /// لا تقطع. فمن غيّر هذا التوقيعَ فليُبقِ المخارجَ الأربعةَ صريحة.
  ///
  /// وحدُّه معلَن: `false` تعني «لم يُرسَل إلى الطابعة» (بياناتٌ ناقصةٌ أو
  /// إخفاقٌ رُمي، **أو إلغاءُ المستخدم في حوار الطباعة** — منذ 2026-09-02،
  /// فـ`PdfComputeHelper.layoutPdf` يرجع ما ردّه الحوار). أمّا ما خرج من
  /// الطابعة بعد قبولها المهمّةَ فلا يراه النظام.
  Future<bool> printReceipt(int invoiceId);

  /// Print an A4 sales invoice (regular invoices screen).
  /// POS continues using [printReceipt] which outputs thermal 80mm.
  ///
  /// يرجع `true` إن خرجت الورقة (أو قُبلت المهمّة)، و`false` إن ألغى
  /// المستخدمُ الحوارَ أو غابت البيانات — بنفس عقد [printReceipt].
  Future<bool> printSalesInvoiceA4(int invoiceId);

  /// Print an A4 purchase invoice — mirrors [printSalesInvoiceA4] but for
  /// the purchases flow so both screens share the same save-and-print path.
  Future<bool> printPurchaseInvoiceA4(int invoiceId);

  /// معاينةُ A4 لفاتورة مبيعاتٍ **لم تُحفَظ بعد** — تصميمُ المالك `12.02.29`.
  ///
  /// ═══ ⚠️ ولماذا لا رقمَ على الورقة ═══
  ///
  /// رقمُ الفاتورة يُولَّد **داخلَ معاملة الحفظ** (‏Spec 066 — `generateInvoiceNumber`
  /// والإدراجُ التابعُ له في نفس الدالّة). فقبل الحفظ لا رقمَ موجود، وتخمينُه
  /// يعني ورقةً تبدو مستنداً ضريبيّاً برقمٍ قد يذهب لغيرها: يطبع المستخدمُ
  /// «INV-1043» ثمّ يُحفَظ مستندُه «INV-1044» — ونسخةٌ ورقيّةٌ برقمٍ يخصّ
  /// فاتورةَ عميلٍ آخر.
  ///
  /// فالورقةُ **موسومةٌ في عنوانها** «غير محفوظة» وخانةُ الرقم فيها شرطة.
  ///
  /// ⚠️ **ولا تُسجَّل في سجلّ النشاط**: السجلُّ يربط الطباعةَ بمستندٍ
  /// (`entityId`)، ولا مستندَ هنا. وصفٌّ بلا معرِّفٍ يوهم بطباعة فاتورةٍ
  /// حُفظت.
  Future<bool> previewSalesInvoiceA4({
    required DateTime date,
    required String? customerName,
    required List<print_models.InvoiceItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    String? notes,
  });
}

class PrintingServiceImpl implements IPrintingService {
  final AppDatabase db;
  final SalesRepository salesRepository;

  PrintingServiceImpl(this.db, this.salesRepository);

  @override
  Future<bool> previewSalesInvoiceA4({
    required DateTime date,
    required String? customerName,
    required List<print_models.InvoiceItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    String? notes,
  }) async {
    try {
      final s = await db.getReceiptSettings();
      return await InvoiceGenerator.printSalesInvoice(
        // 🔴 شرطةٌ لا رقمٌ مخمَّن — راجع عقدَ [IPrintingService.previewSalesInvoiceA4].
        invoiceNumber: '—',
        title: 'معاينة فاتورة مبيعات — غير محفوظة',
        date: date,
        customerName: customerName,
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        paid: paid,
        companyName: s.companyName,
        companyAddress: s.companyAddress,
        companyPhone: s.companyPhone,
        companyTaxId: s.taxNumber,
        notes: notes,
        db: db,
      );
    } catch (e) {
      logger.warning('A4 preview failed: $e');
      return false;
    }
  }

  @override
  Future<bool> printSalesInvoiceA4(int invoiceId) async {
    try {
      final printData = await salesRepository.getSalesPrintData(invoiceId);
      if (printData == null) {
        logger.warning('A4 print failed: data not found for invoice $invoiceId');
        return false;
      }
      final s = printData.receiptSettings;
      final printed = await InvoiceGenerator.printSalesInvoice(
        invoiceNumber: printData.invoiceNumber,
        date: printData.date,
        customerName: printData.customerName ?? printData.adhocCustomerName,
        items: printData.items
            .map((i) => print_models.InvoiceItem(
                  name: i.name,
                  quantity: i.quantity,
                  price: i.price,
                  total: i.total,
                  note: i.note,
                ))
            .toList(),
        subtotal: printData.subtotal,
        discount: printData.discount,
        tax: printData.tax,
        // كان مفقوداً: المسارُ الحراريُّ يمرّره (`:176`) وA4 لا — فورقةُ
        // A4 وحدَها هي التي لا تجمع.
        deliveryFee: printData.deliveryFee,
        total: printData.total,
        paid: printData.paid,
        companyName: s.companyName,
        companyAddress: s.companyAddress,
        companyPhone: s.companyPhone,
        companyTaxId: s.taxNumber,
        notes: printData.notes,
        db: db,
      );
      // إلغاءٌ في الحوار ⇒ لا ورقةَ ولا سطرَ سجلٍّ يدّعي طباعةً.
      if (!printed) return false;
      await _logPrint(
        action: 'print_invoice',
        entityType: 'sales_invoice',
        entityId: invoiceId,
        description: 'طباعةُ فاتورة مبيعات A4 رقم ${printData.invoiceNumber}',
        amount: printData.total,
      );
      return true;
    } catch (e, stack) {
      logger.error('Failed to print A4 sales invoice', e, stack, 'PrintingService');
      return false;
    }
  }

  @override
  Future<bool> printPurchaseInvoiceA4(int invoiceId) async {
    try {
      final invoice = await db.getPurchaseInvoiceById(invoiceId);
      if (invoice == null) {
        logger.warning('A4 purchase print: invoice $invoiceId not found');
        return false;
      }
      final items = await db.getPurchaseInvoiceItemsWithProduct(invoiceId);
      final supplier = await db.getPartyById(invoice.supplierId);
      final companyName = await db.getSettingValue('company_name');

      final printed = await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        supplierName: supplier?.name ?? 'غير محدد',
        items: items
            .map((r) => print_models.InvoiceItem(
                  name: r.product.name,
                  quantity: r.item.quantity,
                  price: r.item.unitCost,
                  total: r.item.quantity * r.item.unitCost,
                  barcode: r.product.barcode,
                ))
            .toList(),
        total: invoice.total,
        paid: invoice.paid,
        companyName: companyName,
        db: db,
      );
      if (!printed) return false;
      await _logPrint(
        action: 'print_purchase_invoice',
        entityType: 'purchase_invoice',
        entityId: invoiceId,
        description: 'طباعةُ فاتورة مشتريات A4 رقم ${invoice.invoiceNumber}',
        amount: invoice.total,
      );
      return true;
    } catch (e, stack) {
      logger.error('Failed to print A4 purchase invoice', e, stack, 'PrintingService');
      return false;
    }
  }

  @override
  Future<bool> printReceipt(int invoiceId) async {
    try {
      final printData = await salesRepository.getSalesPrintData(invoiceId);

      if (printData == null) {
        logger.warning('Printing failed: Print data not found for invoice $invoiceId');
        return false;
      }

      final receiptSettings = printData.receiptSettings;

      // مرتجعٌ أم بيع؟ الفعلُ يتبع **المستندَ** لا الطابعة: «سجل
      // الطباعة» و«سجل الإلغاءات» يقرآن مفتاحَين مختلفين، ومفتاحٌ واحدٌ
      // للاثنين يخلط إيصالَ مرتجعٍ بفاتورةِ بيعٍ في كلَيهما.
      final isReturn = printData.saleType == 'return';
      final printAction = isReturn ? 'print_return' : 'print_invoice';
      final docLabel = isReturn ? 'إيصال مرتجع' : 'فاتورة';

      // Read invoice language preference
      String locale = 'ar';
      try {
        final langSetting = await db.getSettingValue('invoice_language');
        if (langSetting == 'en') locale = 'en';
      } catch (_) {}

      // قرارُ الرمز يُحلّ مرّةً ويُمرَّر إلى **المسارين** معاً — القالبِ،
      // و`InvoiceGenerator` الذي يسقط إلى التخطيط المكتوب صامتاً. وبدونه يبقى
      // `null` = رقمُ الفاتورة بلا وسم، وهو عينُ العطب على جهازٍ مسجَّل.
      // ولا يُبتلَع إخفاقُه: سقوطٌ صامتٌ إلى `null` يعيد العطبَ حيث لا يُرى.
      final receiptQr = await resolveReceiptQrForSale(
        db,
        saleId: invoiceId,
        sale: ReceiptSaleSummary.fromSale(
          invoiceNumber: printData.invoiceNumber,
          issuedAt: printData.date,
          total: printData.total,
          companyName: receiptSettings.companyName,
        ),
      );

      final hasTemplate = await TemplatedInvoiceService.hasDefaultTemplate(
        db,
        'thermal',
        category: 'receipt',
      );

      if (hasTemplate) {
        try {
          final itemsMaps = printData.items
              .map(
                (item) => <String, dynamic>{
                  'name': item.name,
                  'quantity': item.quantity,
                  'price': item.price,
                  'total': item.total,
                  'note': item.note ?? '',
                  'code': item.code,
                  'unit': item.unit,
                  'barcode': item.barcode,
                  'discount': item.discount,
                  'tax': item.tax,
                },
              )
              .toList();

          final r = await TemplatedInvoiceService.printWithTemplate(
            db: db,
            invoiceNumber: printData.invoiceNumber,
            date: printData.date,
            customerName: printData.customerName,
            customerPhone: printData.customerPhone,
            customerAddress: printData.customerAddress,
            items: itemsMaps,
            subtotal: printData.subtotal,
            discount: printData.discount,
            tax: printData.tax,
            deliveryFee: printData.deliveryFee,
            total: printData.total,
            paid: printData.paid,
            companyName: receiptSettings.companyName,
            companyAddress: receiptSettings.companyAddress ?? '',
            companyPhone: receiptSettings.companyPhone ?? '',
            companyTaxId: receiptSettings.taxNumber,
            logoBytes: receiptSettings.logoImage,
            paymentMethod: printData.paymentMethod,
            directPrint: true,
            category: 'receipt',
            documentType: 'sales_receipt',
            cashierName: printData.cashierName,
            notes: printData.notes,
            adhocCustomerName: printData.adhocCustomerName,
            adhocCustomerPhone: printData.adhocCustomerPhone,
            salesType: printData.salesTypeText,
            orderNumber: printData.platformOrderNumber ?? printData.orderNumber?.toString(),
            locale: locale,
            receiptQr: receiptQr,
          );
          // إلغاءٌ في حوار الطباعة ⇒ `false` بلا سقوطٍ إلى التخطيط الافتراضيّ
          // (السقوطُ كان سيفتح الحوارَ ثانيةً) وبلا سطرِ سجلٍّ يدّعي طباعة.
          if (!r.printed) return false;
          await _logPrint(
            action: printAction,
            entityType: 'sales_invoice',
            entityId: invoiceId,
            description: 'طباعةُ $docLabel حراريّة رقم ${printData.invoiceNumber}',
            amount: printData.total,
          );
          return true;
        } catch (e) {
          logger.error('Template print failed, falling back to default', e);
        }
      }

      // Default layout (fallback)
      final printed = await InvoiceGenerator.printThermalReceipt(
        invoiceNumber: printData.invoiceNumber,
        date: printData.date,
        items: printData.items.map((i) => print_models.InvoiceItem(
          name: i.name,
          quantity: i.quantity,
          price: i.price,
          total: i.total,
          note: i.note,
        )).toList(),
        total: printData.total,
        paid: printData.paid,
        change: printData.paid - printData.total > 0
            ? printData.paid - printData.total
            : 0,
        companyName: receiptSettings.companyName,
        companyPhone: receiptSettings.companyPhone,
        companyAddress: receiptSettings.companyAddress,
        taxId: receiptSettings.taxNumber,
        employeeName: printData.cashierName,
        registerNumber: '1',
        salesType: printData.salesTypeText,
        receiptCodeType: printData.codeType,
        footerText: receiptSettings.footerText,
        customerName: receiptSettings.showCustomerInfo
            ? (printData.customerName ?? printData.adhocCustomerName)
            : printData.adhocCustomerName,
        customerPhone: receiptSettings.showCustomerInfo
            ? (printData.customerPhone ?? printData.adhocCustomerPhone)
            : printData.adhocCustomerPhone,
        customerAddress: receiptSettings.showCustomerInfo
            ? printData.customerAddress
            : null,
        courierName: printData.courierName,
        courierPhone: printData.courierPhone,
        isDelivery: printData.isDelivery,
        discount: printData.discount,
        tax: receiptSettings.showTaxDetails ? printData.tax : null,
        deliveryFee: printData.deliveryFee > 0 ? printData.deliveryFee : null,
        directPrint: true,
        orderNumber: printData.orderNumber,
        notes: printData.notes,
        locale: locale,
        // نفسُ مصدرِ المسار الأوّل أعلاه (`printWithTemplate`). وبدونه كان
        // السقوطُ إلى هذا المسار يُفقد الشعارَ صامتاً.
        logoBytes: receiptSettings.logoImage,
        receiptQr: receiptQr,
        paperWidthMm: receiptSettings.paperWidth.toDouble(),
      );
      if (!printed) return false;
      await _logPrint(
        action: printAction,
        entityType: 'sales_invoice',
        entityId: invoiceId,
        description: 'طباعةُ $docLabel حراريّة رقم ${printData.invoiceNumber}',
        amount: printData.total,
      );
      return true;
    } catch (e, stack) {
      logger.error('Failed to print invoice', e, stack, 'PrintingService');
      return false;
    }
  }

  /// يسجّل طباعةَ مستندٍ في سجلّ النشاط.
  ///
  /// ── لماذا هنا لا في الشاشات ──────────────────────────────────────────
  /// الطباعةُ تُنادى من خمسةَ عشرَ موضعاً في الشاشات (نقطةُ البيع · الفواتير
  /// · المشتريات · حوارُ آخر فاتورة · إعادةُ الطباعة …). والتسجيلُ عند كلّ
  /// مُنادٍ يعني خمسةَ عشرَ تعديلاً وموضعاً يُنسى — والمنسيُّ لا يحمرّ، بل
  /// يترك ثغرةً في سجلٍّ يُفترَض أنّه كامل. فالمَخنقُ الوحيدُ هو هذه الخدمة.
  ///
  /// ⚠️ **ولا يُسجَّل إلّا ما طُبع فعلاً**: النداءُ بعد نجاح التوليد، وداخلَ
  /// `try` الذي يبتلع الإخفاق. فطباعةٌ فشلت لا تُكتب، وسطرُ سجلٍّ لطباعةٍ لم
  /// تقع أسوأُ من غيابه.
  ///
  /// ⚠️ **وإخفاقُ التسجيل لا يُسقط الطباعة**: القاعدةُ قد تكون مقفولةً أو
  /// المستخدمُ محذوفاً، والورقةُ خرجت من الطابعة فعلاً. فالخطأُ يُدوَّن ولا
  /// يُرمى.
  Future<void> _logPrint({
    required String action,
    required String entityType,
    required int entityId,
    required String description,
    double? amount,
  }) async {
    try {
      await db.logActivity(
        userId: ActorSnapshot.userId,
        userName: ActorSnapshot.userName,
        action: action,
        entityType: entityType,
        entityId: entityId,
        description: description,
        amount: amount,
      );
    } catch (e, stack) {
      logger.error('Failed to log print activity', e, stack, 'PrintingService');
    }
  }
}

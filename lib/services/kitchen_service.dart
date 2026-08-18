import '../domain/repositories/kitchen_repository.dart';
import '../domain/repositories/i_products_repository.dart';
import '../domain/repositories/printers_repository.dart';
import '../data/database/database.dart';
import '../core/logging/app_logger.dart';
import 'invoice_generator.dart';

/// Service for managing kitchen work orders and tickets
class KitchenService {
  final KitchenRepository _kitchenRepo;
  final IProductRepository _productRepo;
  final IPrintersRepository _printersRepo;
  final AppDatabase _db;

  KitchenService(this._kitchenRepo, this._productRepo, this._printersRepo, this._db);

  // ملحوظة: `generateKitchenWorkOrder` كانت هنا وأُزيلت (2026-08-18).
  //
  // كانت تُنادى من `SalesTransactionOrchestrator` على **كلِّ فاتورة مبيعاتٍ
  // بلا شرط**، فكان المرتجعُ يذهب إلى المطبخ ليُحضَّر، وكان صنفُ الطاولة
  // يُطلَب مرّتين (مرّةً عند الطلب ومرّةً عند التحصيل لأنه يُنشئ فاتورة).
  //
  // وقرارُ المالك: الطاولاتُ وحدَها تُحضَّر. فلمّا زال النداءُ لم يبقَ لها
  // مستدعٍ، وتركُها كان يُبقي نسخةً ثانيةً من منطق «التصنيف → المحطة» تُصان
  // بجوار نسخة `table_pos_operations.dart`. يحرسه
  // `test/structural/kitchen_work_orders_from_tables_only_test.dart`.
  //
  // والطباعةُ شيءٌ آخرُ لا علاقةَ له: `printKitchenOrders` أدناه باقيةٌ.

  /// Print kitchen orders for a specific invoice (items with kitchen printer assigned)
  Future<int> printKitchenOrders(int invoiceId) async {
    try {
      // Get invoice data for invoice number and order number
      final invoice = await _db.getSalesInvoiceById(invoiceId);
      if (invoice == null) return 0;

      // Get invoice items
      final items = await _db.getSalesInvoiceItems(invoiceId);
      if (items.isEmpty) return 0;

      // Group items by category printer
      final Map<int, List<Map<String, dynamic>>> itemsByPrinter = {};
      final Map<int, String> printerCategories = {};

      for (final item in items) {
        final product = await _productRepo.getProductById(item.productId);
        if (product != null && product.categoryId != null) {
          final category = await _productRepo.getCategoryById(product.categoryId!);
          if (category?.printerId != null) {
            final printerId = category!.printerId!;
            if (!itemsByPrinter.containsKey(printerId)) {
              itemsByPrinter[printerId] = [];
              printerCategories[printerId] = category.name;
            }
            itemsByPrinter[printerId]!.add({
              'name': product.name,
              'quantity': item.quantity,
              'price': item.unitPrice,
              'note': item.note,
            });
          }
        }
      }

      if (itemsByPrinter.isEmpty) return 0;

      // Use the actual invoice order number so kitchen receipt matches the invoice
      final orderNumber = invoice.orderNumber?.toString() ?? invoice.invoiceNumber;

      int printedCount = 0;
      for (final entry in itemsByPrinter.entries) {
        final printerId = entry.key;
        final printerItems = entry.value;
        final categoryName = printerCategories[printerId] ?? 'المطبخ';

        final invoiceItems = printerItems
            .map(
              (item) => InvoiceItem(
                name: item['name'] as String,
                quantity: (item['quantity'] as num).toDouble(),
                price: (item['price'] as num).toDouble(),
                total:
                    (item['quantity'] as num).toDouble() *
                    (item['price'] as num).toDouble(),
                note: item['note'] as String?,
              ),
            )
            .toList();

        try {
          await InvoiceGenerator.printWorkOrderReceipt(
            orderNumber: '$orderNumber${itemsByPrinter.length > 1 ? '-${printedCount + 1}' : ''}',
            date: DateTime.now(),
            categoryName: categoryName,
            items: invoiceItems,
            invoiceNumber: invoice.invoiceNumber,
            dailyOrderNumber: invoice.orderNumber,
            orderType: invoice.saleType,
            orderNotes: invoice.notes,
            customerName: invoice.platformOrderNumber ?? (
              (invoice.notes?.contains('|') ?? false)
                ? invoice.notes!.split('|').last.trim()
                : invoice.notes
            ), // Often used for Table Name in restaurant mode
            printersRepo: _printersRepo,
            db: _db,
          );
          printedCount++;
        } catch (e) {
          logger.warning('Failed to print kitchen order for $categoryName: $e');
        }
      }

      return printedCount;
    } catch (e) {
      logger.warning('Failed to print kitchen orders: $e');
      return 0;
    }
  }
}

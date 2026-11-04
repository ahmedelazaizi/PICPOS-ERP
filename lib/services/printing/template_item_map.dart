import '../generators/base_generator.dart' as generator;
import 'printing_models.dart';

Map<String, dynamic> templateItemMap(InvoiceItem invoiceItem) => {
  'name': invoiceItem.name,
  'quantity': invoiceItem.quantity,
  'price': invoiceItem.price,
  'total': invoiceItem.total,
  'note': invoiceItem.note ?? '',
  'code': invoiceItem.code,
  'unit': invoiceItem.unit,
  'discount': invoiceItem.discount,
  'tax': invoiceItem.tax,
};

Map<String, dynamic> templateItemMapWithBarcode(InvoiceItem invoiceItem) => {
  ...templateItemMap(invoiceItem),
  'barcode': invoiceItem.barcode,
};

Map<String, dynamic> generatorTemplateItemMap(
  generator.InvoiceItem invoiceItem,
) => {
  'name': invoiceItem.name,
  'quantity': invoiceItem.quantity,
  'price': invoiceItem.price,
  'total': invoiceItem.total,
  'note': invoiceItem.note ?? '',
  'code': invoiceItem.code,
  'unit': invoiceItem.unit,
  'discount': invoiceItem.discount,
  'tax': invoiceItem.tax,
};

Map<String, dynamic> generatorTemplateItemMapWithBarcode(
  generator.InvoiceItem invoiceItem,
) => {...generatorTemplateItemMap(invoiceItem), 'barcode': invoiceItem.barcode};

Map<String, dynamic> kitchenTemplateItemMap(InvoiceItem invoiceItem) => {
  ...templateItemMapWithBarcode(invoiceItem),
  // Preserve the section marker so it is not rendered as a zero-quantity item.
  'isCategoryHeader': invoiceItem.isCategoryHeader,
};

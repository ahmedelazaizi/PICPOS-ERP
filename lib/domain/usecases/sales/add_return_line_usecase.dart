import '../../entities/cart_item_entity.dart';

/// إضافةُ سطرِ **مرتجعٍ بلا فاتورة** إلى السلّة (بند ٤ — المرتجع السريع).
///
/// منطقٌ خالصٌ بلا واجهةٍ ولا قاعدة. الفروقُ المقصودة عن [AddToCartUseCase]:
///  * السطرُ `CartItemType.returned` بكميّةٍ **موجبة** — اتجاهُ المخزون يأتي من
///    `saleType='return'` على المستند لا من إشارة السطر.
///  * لا يندمج أبداً في سطرِ بيعٍ لنفس الصنف (وإلّا قلب سطرُ البيعِ مرتجعاً).
///  * يندمج في سطرِ مرتجعٍ سابقٍ لنفس الصنف **والسعر والوحدة** فقط: مسحتان لنفس
///    الصنف بنفس السعر = كميّة ٢، أمّا سعرٌ مختلف (أُدخل يدوياً) فسطرٌ منفصل.
class AddReturnLineUseCase {
  List<CartItemEntity> execute({
    required List<CartItemEntity> currentCart,
    required int productId,
    required String productName,
    required String productCode,
    required double unitPrice,
    double? customPrice,
    double quantity = 1,
    double taxRate = 0,
    bool taxExempt = false,
    bool isSoldByWeight = false,
    int? categoryId,
    String? barcode,
  }) {
    if (quantity <= 0) return currentCart;
    final price = customPrice ?? unitPrice;

    final existing = currentCart.indexWhere((i) =>
        i.itemType == CartItemType.returned &&
        i.productId == productId &&
        i.selectedUnitId == null &&
        i.effectivePrice == price &&
        i.discountPercent == 0);

    if (existing >= 0 && !isSoldByWeight) {
      final merged = currentCart[existing]
          .copyWith(quantity: currentCart[existing].quantity + quantity);
      return [
        ...currentCart.sublist(0, existing),
        merged,
        ...currentCart.sublist(existing + 1),
      ];
    }

    return [
      ...currentCart,
      CartItemEntity(
        productId: productId,
        categoryId: categoryId,
        productName: productName,
        productCode: productCode,
        barcode: barcode,
        quantity: quantity,
        unitPrice: unitPrice,
        customPrice: customPrice,
        taxRate: taxExempt ? 0 : taxRate,
        taxExempt: taxExempt,
        isSoldByWeight: isSoldByWeight,
        itemType: CartItemType.returned,
      ),
    ];
  }
}

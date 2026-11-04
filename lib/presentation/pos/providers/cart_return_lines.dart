import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/usecases/sales/add_return_line_usecase.dart';
import 'cart_controller.dart';

/// قراءاتٌ مشتقّة من [CartState] لسطور **المرتجع بلا فاتورة** (بند ٤).
///
/// في ملفٍّ مستقلّ حفاظاً على سقف حجم `cart_controller.dart`؛ يُعاد تصديره
/// من هناك فلا يحتاج المستدعون استيراداً جديداً.
extension CartReturnLines on CartState {
  bool get hasReturnLines =>
      items.any((i) => i.itemType == CartItemType.returned);

  bool get hasSaleLines =>
      items.any((i) => i.itemType != CartItemType.returned);

  /// سلّةُ مرتجعٍ خالصة (لا بيع فيها).
  bool get isReturnOnly => hasReturnLines && !hasSaleLines;

  /// سلّةٌ مختلطة: بيعٌ ومرتجعٌ بلا فاتورة معاً.
  bool get isMixedCart => hasReturnLines && hasSaleLines;

  /// الإجماليُّ **المُشار** للعرض: سالبٌ حين المرتجعُ يغلب (أو مرتجعٌ خالص).
  ///
  /// ⚠️ [CartState.total] لا يتغيّر لسلّة المرتجع الخالص (يبقى موجباً = قيمةَ
  /// الاسترداد، كما تقرؤه الشاشةُ القديمة)، ولسلّةٍ مختلطةٍ هو الصافي بإشارته.
  /// فالعرضُ وحدَه يقلب إشارةَ المرتجع الخالص.
  double get signedTotal => isReturnOnly ? -total : total;
}

/// [s] بعد إضافة سطر مرتجعٍ بلا فاتورة لـ[product] (انظر [AddReturnLineUseCase]).
///
/// [unitPrice] سعرُ البيع الحاليّ بقائمة الأسعار؛ و[price] سعرٌ يدويٌّ اختياريّ
/// تحرسه صلاحيةُ `pos_return_price_edit` عند المنادي.
CartState cartWithReturnLine(
  CartState s,
  ProductEntity product, {
  required double unitPrice,
  required double quantity,
  double? price,
}) =>
    s.copyWith(
      items: AddReturnLineUseCase().execute(
        currentCart: s.items,
        productId: product.id,
        productName: product.name,
        productCode: product.code,
        unitPrice: unitPrice,
        customPrice: price,
        quantity: quantity,
        taxRate: product.taxRate,
        taxExempt: product.taxExempt,
        isSoldByWeight: product.isSoldByWeight,
        categoryId: product.categoryId,
        barcode: product.barcode,
      ),
    );

/// [s] بعد إزالة الشقّ الذي حُفظ مستنداً: سطورِ المرتجع إن [returned]، وإلا
/// سطورِ البيع — ومعها خصمُ الفاتورة، فهو شقُّ البيع وحدَه.
CartState cartWithoutSettledLines(CartState s, {required bool returned}) {
  final kept = [
    for (final i in s.items)
      if ((i.itemType == CartItemType.returned) != returned) i,
  ];
  return returned
      ? s.copyWith(items: kept)
      : s.copyWith(items: kept, discountPercent: 0, invoiceDiscountAmount: null);
}

import '../../entities/cart_item_entity.dart';

/// Resolves the two cart-merge flags from the POS «منع تراكم الأصناف» setting.
///
/// The setting only ever meant one thing: **a weighed item gets its own line
/// per weighing**, so the cashier can see 0.750 + 0.400 as two readings from
/// the scale instead of an opaque 1.150. It was never meant to stop counted
/// items from accumulating — two taps on the same bottle of water is a
/// quantity of 2, not two lines.
///
/// The old call sites passed the raw setting as `forceNewEntry` for EVERY
/// product, which inverted it in practice: [AddToCartUseCase]'s
/// `(!isSoldByWeight || mergeWeight)` clause already blocked weighed items
/// from merging (callers never passed `mergeWeight` on the tap path), so the
/// toggle had no effect on weighed items at all and its entire effect landed
/// on counted ones — the exact opposite of its name and purpose.
///
/// Centralised here so the tap path, the barcode path and both product
/// brands can never drift apart on it again.
({bool forceNewEntry, bool mergeWeight}) resolveStackingFlags({
  required bool isSoldByWeight,
  required bool preventStacking,
}) =>
    (
      forceNewEntry: isSoldByWeight && preventStacking,
      mergeWeight: isSoldByWeight && !preventStacking,
    );

/// Use case for adding item to cart
///
/// Pure business logic - no UI or database dependencies
class AddToCartUseCase {
  /// Execute the use case
  ///
  /// Returns updated cart list with the new item added or quantity updated
  List<CartItemEntity> execute({
    required List<CartItemEntity> currentCart,
    required int productId,
    required String productName,
    required String productCode,
    required double unitPrice,
    double quantity = 1,
    double? customPrice,
    double taxRate = 0,
    bool taxExempt = false,
    bool isSoldByWeight = false,
    int? categoryId,
    bool forceNewEntry =
        false, // New: For offers - prevents merging with existing items
    bool mergeWeight =
        false, // When true, weight items accumulate quantity (barcode scans)
  }) {
    final existingIndex = currentCart.indexWhere(
      (item) => item.productId == productId,
    );

    // Don't merge if: sold by weight (unless mergeWeight), forced new entry, or price differs.
    // Exception 1: always merge when the existing item was auto-discounted by an offer
    // (note starts with 'عرض:'), so that adding more units doesn't create a competing
    // full-price line that later gets stripped by auto-apply, losing quantity.
    // Exception 2: also merge when existing item is a manually applied offer
    // (note starts with 'عرض (يدوي):') — user explicitly added from the offers dialog
    // and then continues tapping from the product grid.
    final existingNote = existingIndex >= 0 ? currentCart[existingIndex].note : null;
    final existingIsAutoDiscount = existingNote?.startsWith('عرض:') ?? false;
    final existingIsManualOffer = existingNote?.startsWith('عرض (يدوي):') ?? false;
    final existingIsAnyOffer = existingIsAutoDiscount || existingIsManualOffer;
    final shouldMerge =
        existingIndex >= 0 &&
        (!isSoldByWeight || mergeWeight) &&
        !forceNewEntry &&
        (customPrice == null ||
            customPrice == currentCart[existingIndex].effectivePrice ||
            existingIsAnyOffer);

    if (shouldMerge) {
      // Update existing item quantity (not for weight-based products)
      final existing = currentCart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);

      return [
        ...currentCart.sublist(0, existingIndex),
        updated,
        ...currentCart.sublist(existingIndex + 1),
      ];
    } else {
      // Add new item
      final newItem = CartItemEntity(
        productId: productId,
        productName: productName,
        productCode: productCode,
        quantity: quantity,
        unitPrice: unitPrice,
        customPrice: customPrice,
        // B3: an exempt line stores rate 0 (`effectiveItemTaxRate`).
        taxRate: taxExempt ? 0 : taxRate,
        taxAmount: taxExempt
            ? 0
            : (quantity * (customPrice ?? unitPrice)) * (taxRate / 100),
        taxExempt: taxExempt,
        categoryId: categoryId,
        isSoldByWeight: isSoldByWeight,
      );

      return [...currentCart, newItem];
    }
  }
}

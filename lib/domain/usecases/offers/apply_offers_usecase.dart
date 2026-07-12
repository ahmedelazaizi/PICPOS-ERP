import '../../entities/cart_item_entity.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/database/database.dart'; // Using DataClasses for now as domain entities for offers don't exist yet

/// UseCase to analyze a cart and apply matching bundles/offers automatically.
class ApplyOffersUseCase {
  final AppDatabase db;

  ApplyOffersUseCase(this.db);

  /// Logic:
  /// - Check if ALL offer products exist in cart with at least required quantities
  /// - Calculate how many times the offer can be applied (min of qty/required for all products)
  /// - Apply offer price for that many sets, regular price for excess quantities
  Future<List<CartItemEntity>> execute(List<CartItemEntity> currentCart) async {
    if (currentCart.isEmpty) return currentCart;

    try {
      final offers = await db.getActiveOffers();
      if (offers.isEmpty) return currentCart;

      // Create a map of productId -> total quantity in cart (excluding already-applied offers)
      final cartProductQty = <int, double>{};
      final cartProductIndices = <int, List<int>>{};

      for (int i = 0; i < currentCart.length; i++) {
        final item = currentCart[i];
        // Skip items already marked with offer
        if (item.note?.contains('عرض:') ?? false) continue;

        cartProductQty[item.productId] =
            (cartProductQty[item.productId] ?? 0) + item.quantity;
        cartProductIndices[item.productId] ??= [];
        cartProductIndices[item.productId]!.add(i);
      }

      // Check each offer
      for (final offer in offers) {
        final offerItems = await db.getOfferItems(offer.id);
        if (offerItems.isEmpty) continue;

        // Check if cart has ALL items matching offer with at least required quantity
        bool allItemsPresent = true;
        int offerMultiplier = 999999; // How many times can we apply this offer?

        for (final offerItem in offerItems) {
          final cartQty = cartProductQty[offerItem.productId] ?? 0;
          if (cartQty < offerItem.quantity) {
            allItemsPresent = false;
            break;
          }
          // Calculate how many complete offer sets we can make
          final timesForThisProduct = (cartQty / offerItem.quantity).floor();
          if (timesForThisProduct < offerMultiplier) {
            offerMultiplier = timesForThisProduct;
          }
        }

        if (!allItemsPresent || offerMultiplier == 0) continue;

        // Calculate original total price for offer items (at offer quantities)
        double totalNormalPrice = 0;
        for (final offerItem in offerItems) {
          final product = await db.getProductById(offerItem.productId);
          if (product != null) {
            totalNormalPrice += product.salePrice * offerItem.quantity;
          }
        }

        if (totalNormalPrice == 0 || offer.offerPrice >= totalNormalPrice) {
          continue;
        }

        // Calculate price adjustment factor for offer portion
        final factor = offer.offerPrice / totalNormalPrice;

        // Process cart items - apply offer price for (offerQty * multiplier), regular for excess
        final List<CartItemEntity> updatedCart = [];
        final Set<int> processedIndices = {};

        for (final offerItem in offerItems) {
          final product = await db.getProductById(offerItem.productId);
          if (product == null) continue;

          // BUG-H04: round the per-unit offer price to currency precision.
          final offerUnitPrice =
              NumberUtils.roundCurrency(product.salePrice * factor);
          final totalOfferQty = offerItem.quantity * offerMultiplier;
          final indices = cartProductIndices[offerItem.productId] ?? [];
          double remainingOfferQty = totalOfferQty;

          for (final idx in indices) {
            if (processedIndices.contains(idx)) continue;
            processedIndices.add(idx);

            final item = currentCart[idx];
            final cartQty = item.quantity;

            if (remainingOfferQty > 0) {
              if (cartQty <= remainingOfferQty) {
                // Entire item quantity is within offer limit
                updatedCart.add(
                  item.copyWith(
                    customPrice: offerUnitPrice,
                    note:
                        'عرض: ${offer.name}${offerMultiplier > 1 ? ' x$offerMultiplier' : ''}',
                  ),
                );
                remainingOfferQty -= cartQty;
              } else {
                // Split: part at offer price, part at regular price
                updatedCart.add(
                  item.copyWith(
                    quantity: remainingOfferQty,
                    customPrice: offerUnitPrice,
                    note:
                        'عرض: ${offer.name}${offerMultiplier > 1 ? ' x$offerMultiplier' : ''}',
                  ),
                );
                updatedCart.add(
                  item.copyWith(
                    quantity: cartQty - remainingOfferQty,
                    customPrice: null, // Regular price
                    note: null,
                  ),
                );
                remainingOfferQty = 0;
              }
            } else {
              updatedCart.add(item);
            }
          }
        }

        // Add remaining items not part of this specific offer
        for (int i = 0; i < currentCart.length; i++) {
          if (!processedIndices.contains(i)) {
            updatedCart.add(currentCart[i]);
          }
        }

        return updatedCart; // Successfully applied one offer
      }
    } catch (_) {
      // Return original cart on error
    }

    return currentCart;
  }
}

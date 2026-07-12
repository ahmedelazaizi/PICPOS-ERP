import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../../data/mappers/product_mapper.dart';

/// Request payload for offering matching
class ApplyOfferRequest {
  final Offer offer;

  ApplyOfferRequest({
    required this.offer,
  });
}

/// Item returned to controller
class PricedCartItem {
  final ProductEntity product;
  final double quantity;
  final double customPrice;

  PricedCartItem({
    required this.product,
    required this.quantity,
    required this.customPrice,
  });
}

/// A service to extract cart pricing logic (e.g. Offers) out of the UI controller.
class CartPricingService {
  final Ref _ref;

  CartPricingService(this._ref);

  /// Computes the offer bundle and returns the list of priced cart items to add
  Future<List<PricedCartItem>> calculateOfferItems(ApplyOfferRequest request) async {
    final db = _ref.read(databaseProvider);
    final offer = request.offer;
    final List<PricedCartItem> pricedItems = [];

    try {
      // NOTE: getOfferItems should return actual item bundles linked to the offer
      final items = await db.getOfferItems(offer.id);
      if (items.isEmpty) return pricedItems;

      double totalNormalPrice = 0;
      final List<Map<String, dynamic>> productsToAdd = [];

      final productMap = await db.getProductsByIds(items.map((i) => i.productId).toList());
      for (final item in items) {
        final product = productMap[item.productId];
        if (product != null) {
          totalNormalPrice += product.salePrice * item.quantity;
          productsToAdd.add({
            'product': product.toEntity(), // Convert to Domain entity if necessary based on your mapper
            'quantity': item.quantity,
          });
        }
      }

      if (totalNormalPrice == 0) return pricedItems;
      final factor = offer.offerPrice / totalNormalPrice;

      for (final p in productsToAdd) {
        final product = p['product'] as ProductEntity;
        final qty = p['quantity'] as double;
        // BUG-H04: round the per-unit offer price to currency precision so the
        // bundle line totals don't carry float tails. (Residual sub-fils drift
        // vs offer.offerPrice is inherent to per-unit pricing at 3dp.)
        final customPrice = NumberUtils.roundCurrency(product.salePrice * factor);

        pricedItems.add(
          PricedCartItem(
            product: product,
            quantity: qty,
            customPrice: customPrice,
          ),
        );
      }

      _logAction(
        'pos_apply_offer',
        offer.id,
        'تطبيق عرض: ${offer.name}',
        offer.offerPrice,
      );

      return pricedItems;
    } catch (e) {
      AppLogger.instance.error('Failed to calculate offer', e, null, 'CART_PRICING');
      return pricedItems;
    }
  }

  void _logAction(
    String action,
    int entityId,
    String description,
    double amount,
  ) {
    try {
      final activityLogRepo = _ref.read(activityLogRepositoryProvider);
      final auth = _ref.read(authProvider);
      activityLogRepo.logActivity(
        userId: auth.user?.id,
        userName: auth.user?.displayName ?? 'Admin',
        action: action,
        entityType: 'offer',
        entityId: entityId,
        description: description,
        amount: amount,
      );
    } catch (e) {
      AppLogger.instance.warning('_logAction($action): activity log failed (non-critical): $e');
    }
  }
}

final cartPricingServiceProvider = Provider<CartPricingService>((ref) {
  return CartPricingService(ref);
});

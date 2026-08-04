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

/// ليه العرض اترفض. الرفض هنا **ممنوع يكون صامت**: الكاشير ضغط على العرض
/// قدام الزبون، فلو مفيش حاجة حصلت ومفيش سبب ظاهر هيفضل يضغط ويشك في الجهاز.
enum OfferRejectionReason {
  /// العرض من غير أصناف، أو أصنافه مش موجودة/مجموع أسعارها صفر.
  noPricedItems,

  /// سعر العرض ≥ مجموع أسعار بيع أصنافه — يعني «عرض» بيغلّي مش بيخفّض.
  notADiscount,
}

/// تفاصيل رفض تطبيق عرض، عشان الواجهة تعرض رقم مش رسالة عامة.
class OfferRejection {
  final OfferRejectionReason reason;
  final double offerPrice;
  final double normalPrice;

  const OfferRejection({
    required this.reason,
    required this.offerPrice,
    required this.normalPrice,
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

  /// Computes the offer bundle and returns the list of priced cart items to add.
  ///
  /// [onRejected] بينده لما العرض يترفض، عشان اللي مناديها يقدر يقول للكاشير
  /// السبب. لو مبعتّش، الرفض بيفضل مكتوب في اللوج بس.
  Future<List<PricedCartItem>> calculateOfferItems(
    ApplyOfferRequest request, {
    void Function(OfferRejection rejection)? onRejected,
  }) async {
    final db = _ref.read(databaseProvider);
    final offer = request.offer;
    final List<PricedCartItem> pricedItems = [];

    try {
      // NOTE: getOfferItems should return actual item bundles linked to the offer
      final items = await db.getOfferItems(offer.id);
      if (items.isEmpty) {
        _reject(onRejected, OfferRejectionReason.noPricedItems, offer, 0);
        return pricedItems;
      }

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

      if (totalNormalPrice == 0) {
        _reject(onRejected, OfferRejectionReason.noPricedItems, offer, 0);
        return pricedItems;
      }

      // عرض سعره ≥ مجموع أسعار بيع أصنافه بيدّي `factor > 1`، فكل سطر بيتسعّر
      // **فوق** سعر بيعه العادي — «عرض» بيغرّم الزبون. الحارس ده كان موجود في
      // `apply_offers_usecase.dart:70` والمسار الحيّ ورث الشرط الناقص بس.
      //
      // وليه هنا بالذات مش عند إنشاء العرض: `products.salePrice` ممكن ينزل على
      // جهاز تاني **بعد** ما العرض اتحفظ، فعرض سليم يوصل مقلوب بعد المزامنة.
      // نقطة التطبيق هي الوحيدة اللي بتقفل الطريقين (غلطة كتابة + انحراف مزامنة).
      // مسار التطبيق التلقائي (`_applyBundleOffer`) عنده الحارس ده أصلاً؛
      // المكشوف كان المسار اليدوي/الباركود بس.
      if (offer.offerPrice >= totalNormalPrice) {
        _reject(onRejected, OfferRejectionReason.notADiscount, offer,
            totalNormalPrice);
        return pricedItems;
      }

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

  void _reject(
    void Function(OfferRejection)? onRejected,
    OfferRejectionReason reason,
    Offer offer,
    double normalPrice,
  ) {
    AppLogger.instance.warning(
      'رفض تطبيق عرض "${offer.name}" (#${offer.id}): $reason — '
      'سعر العرض ${offer.offerPrice}، مجموع أسعار البيع $normalPrice',
    );
    onRejected?.call(OfferRejection(
      reason: reason,
      offerPrice: offer.offerPrice,
      normalPrice: normalPrice,
    ));
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

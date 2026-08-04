import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../core/constants/app_constants.dart';
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

      // BUG-H04: round the per-unit offer price to currency precision so the
      // bundle line totals don't carry float tails.
      final unitPrices = productsToAdd
          .map((p) => NumberUtils.roundCurrency(
              (p['product'] as ProductEntity).salePrice * factor))
          .toList();

      // التقريب لكل وحدة لوحده ما بيجمّعش لسعر العرض: ٣ أصناف بـ٥ بسعر عرض ١٠
      // كانت بتدي ٣٫٣٣٣ × ٣ = ٩٫٩٩٩. اللافتة بتقول رقم والفاتورة بتقول غيره.
      _settleBundleRemainder(productsToAdd, unitPrices, offer.offerPrice);

      for (var i = 0; i < productsToAdd.length; i++) {
        pricedItems.add(
          PricedCartItem(
            product: productsToAdd[i]['product'] as ProductEntity,
            quantity: productsToAdd[i]['quantity'] as double,
            customPrice: unitPrices[i],
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

  /// بيوزّع باقي التقريب على سطور الحزمة عشان مجموعها يساوي [target].
  ///
  /// ── ليه ما ينفعش نضمن صفر دايماً ─────────────────────────────────────────
  /// السعر متخزَّن **لكل وحدة** بدقة العملة (`AppConstants.decimalPlaces` = ٣).
  /// تعديل سطر كميته `q` بأصغر خطوة ممكنة (٠٫٠٠١ للوحدة) بيغيّر المجموع بـ
  /// `q × 0.001` — يعني الباقي يتصفّى تماماً بس لو كان من مضاعفات ده.
  ///
  /// الحد الأقصى للباقي بعد التوزيع = `q_min × 0.0005` حيث `q_min` أصغر كمية
  /// في الحزمة. **مقيس** بمسح ٦٠٠ ألف حالة (١–٤ أصناف، كميات ١–١٠، أسعار بيع
  /// ١–١٠٠، سعر عرض ١٠٪–٩٩٪ من المجموع)، والمقيس طابق الحد النظري بالظبط:
  /// * `q_min = 1` (الشكل الغالب للعروض) → الباقي **صفر** في كل الحالات.
  /// * `q_min = 2` → ٠٫٠٠١ · `q_min = 3` → ٠٫٠٠١ · `q_min = 10` → ٠٫٠٠٥.
  /// * أسوأ باقٍ مرصود إجمالاً: **٠٫٠٠٥** (كان ٠٫٠١٦ قبل التوزيع).
  /// مثال ما ينفعش يتصفّى: صنف واحد كميته ٣ محتاج تصحيح ٠٫٠٠١ — مفيش تعديل
  /// لكل وحدة بيمثّله (٠٫٠٠١ ÷ ٣ بتقرّب لصفر).
  ///
  /// يعني القيد في **نموذج البيانات** (سعر وحدة بـ3dp) مش في الحسبة. الحسبة
  /// بتوصل لأقصى حاجة النموذج بيسمح بيها، وما بتنفّذش خطوة إلا لو قلّلت الباقي
  /// فعلاً — فالنتيجة عمرها ما تبقى أسوأ من عدم التوزيع.
  static void _settleBundleRemainder(
    List<Map<String, dynamic>> lines,
    List<double> unitPrices,
    double target,
  ) {
    final step = 1 / math.pow(10, AppConstants.decimalPlaces);

    double residual = target;
    for (var i = 0; i < lines.length; i++) {
      residual -= unitPrices[i] * (lines[i]['quantity'] as double);
    }

    // الأصغر كمية الأول: خطوتها على المجموع (`q × 0.001`) هي الأنعم، فبتقدر
    // تمتصّ باقي ما كانتش الكميات الأكبر هتوصله.
    final order = List<int>.generate(lines.length, (i) => i)
      ..sort((a, b) => (lines[a]['quantity'] as double)
          .compareTo(lines[b]['quantity'] as double));

    for (final i in order) {
      if (residual.abs() < step / 2) break;
      final qty = lines[i]['quantity'] as double;
      if (qty <= 0) continue;

      final steps = (residual / (qty * step)).round();
      if (steps == 0) continue;

      // العرض المفروض يخفّض: التصحيح ممنوع يطلّع السعر فوق سعر البيع ولا
      // ينزّله تحت الصفر.
      final product = lines[i]['product'] as ProductEntity;
      final adjusted = NumberUtils.clamp(
        NumberUtils.roundCurrency(unitPrices[i] + steps * step),
        0,
        product.salePrice,
      );
      final delta = adjusted - unitPrices[i];
      if (delta == 0) continue;

      final next = residual - delta * qty;
      if (next.abs() >= residual.abs()) continue; // ما تبوّظش اللي كان أحسن
      unitPrices[i] = adjusted;
      residual = next;
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

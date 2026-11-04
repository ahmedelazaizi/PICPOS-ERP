import '../../../core/utils/uuid_v7.dart';
import '../../../domain/entities/cart_item_entity.dart';

/// R3 — يثبّت `globalId` لـ«محاولة البيع» الواحدة.
///
/// في وضع العميل يُرسَل البيعُ للخادم قبل الحفظ المحلي. إن فشل الحفظُ المحلي
/// يرى الكاشير «فشل» ويعيد، وكان كلُّ استدعاءٍ يولّد `globalId` جديداً فلا يلتقطه
/// فحصُ `globalId` في `ApiSalesHandler` ⇒ فاتورةٌ مزدوجة. هنا يُعاد استعمالُ
/// المعرّف نفسه ما دامت **بصمةُ السلّة** نفسَها (تغيّرُ السلّة = بيعٌ مختلف =
/// معرّفٌ جديد)، ويُنسى عند النجاح.
class CheckoutAttemptId {
  String? _fingerprint;
  String? _globalId;

  /// بصمةٌ لمحتوى البيع: الأصنافُ والعميلُ والدفعُ ونوعُ المستند.
  static String fingerprint({
    required Iterable<CartItemEntity> items,
    required int? customerId,
    required String paymentMethod,
    required double paidAmount,
    required bool asReturn,
    required int warehouseId,
  }) {
    final lines = items
        .map((i) =>
            '${i.productId}:${i.quantity}:${i.unitPrice}:${i.discountPercent}:${i.itemType.name}')
        .join(',');
    return '$lines|$customerId|$paymentMethod|$paidAmount|$asReturn|$warehouseId';
  }

  /// المعرّفُ المحفوظ إن تطابقت البصمة، وإلا معرّفٌ جديد يُحفظ للمحاولة التالية.
  String idFor(String fingerprint, {String Function()? mint}) {
    if (_globalId != null && _fingerprint == fingerprint) return _globalId!;
    _fingerprint = fingerprint;
    return _globalId = (mint ?? UuidV7.generate)();
  }

  /// بعد نجاحٍ كاملٍ: البيعُ التالي (ولو بسلّةٍ مطابقة) بيعٌ جديد.
  void clear() {
    _fingerprint = null;
    _globalId = null;
  }
}

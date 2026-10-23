import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';

/// The POS out-of-stock guard, and the two escape hatches that unlock it.
///
/// ── Why this matters ──────────────────────────────────────────────────────
/// Selling an item whose stock is already zero drives inventory negative, so
/// the guard is a real control. But the ABILITY to do it deliberately is also
/// real — a shop that has physical stock the system hasn't received yet still
/// needs to sell it.
///
/// That ability used to be reachable only as a SIDE EFFECT of pre-selecting
/// «آجل» in the payment row. When the PicPos till moved payment selection into
/// the checkout dialog, the side effect disappeared with the buttons. The
/// `allowOversell` flag restores it under its own name; the `credit` condition
/// stays because UralCash still has those buttons and that workflow.
void main() {
  ProductEntity product({
    double currentStock = 0,
    bool trackInventory = true,
    bool allowNegativeSale = false,
  }) =>
      ProductEntity(
        id: 1,
        code: 'P01',
        name: 'صنف',
        salePrice: 10,
        costPrice: 5,
        currentStock: currentStock,
        minStock: 0,
        trackInventory: trackInventory,
        allowNegativeSale: allowNegativeSale,
      );

  group('blocksAdd — the guard fires', () {
    test('blocks a tracked item at zero stock', () {
      expect(
        const CartState().blocksAdd(product(), globalNegativeSales: false),
        isTrue,
      );
    });

    test('blocks at negative stock too', () {
      expect(
        const CartState()
            .blocksAdd(product(currentStock: -3), globalNegativeSales: false),
        isTrue,
      );
    });
  });

  group('blocksAdd — legitimate escapes', () {
    test('allows when stock is available', () {
      expect(
        const CartState()
            .blocksAdd(product(currentStock: 5), globalNegativeSales: false),
        isFalse,
      );
    });

    test('allows when the product is not inventory-tracked', () {
      expect(
        const CartState().blocksAdd(product(trackInventory: false),
            globalNegativeSales: false),
        isFalse,
      );
    });

    test('allows when the product permits negative sale', () {
      expect(
        const CartState().blocksAdd(product(allowNegativeSale: true),
            globalNegativeSales: false),
        isFalse,
      );
    });

    test('allows when the install-wide negative-sales setting is on', () {
      expect(
        const CartState().blocksAdd(product(), globalNegativeSales: true),
        isFalse,
        reason: 'shops that oversell routinely turn this on, and must not be '
            'asked to confirm on every scan',
      );
    });

    // ⛔ اختبار «allows in exchange mode» اتشال مع «وضع الاستبدال» نفسه.
    //
    // الوضع ده كان بيخزّن كميات **سالبة**، و`adjustStock` بياخد الاتجاه من
    // `saleType` وبيمرّر الكمية بإشارتها ⇒ سالب × مستند مرتجع = المخزون
    // **ينقص** بدل ما يزيد. مكسور في كل حالاته، مش في المختلطة بس.
    //
    // كان بيتخطّى حارس «غير متوفر» كمان (`!isExchangeMode` في `blocksAdd`) —
    // وده تخطٍّ **ضاع مع الوضع**. المرتجع دلوقتي بيمرّ من
    // `convertToQuickReturn` وهو بيشتغل على أصناف موجودة في السلة أصلاً،
    // فما بيحتاجش تخطّي الحارس.
    //
    // شوف test/unit/exchange_mode_removed_test.dart

    test('allows on credit — the UralCash workflow, deliberately preserved',
        () {
      expect(
        const CartState(paymentMethod: 'credit')
            .blocksAdd(product(), globalNegativeSales: false),
        isFalse,
      );
    });

    test('allows when allowOversell is set — the PicPos replacement path', () {
      expect(
        const CartState(allowOversell: true)
            .blocksAdd(product(), globalNegativeSales: false),
        isFalse,
      );
    });
  });

  group('allowOversell is per-invoice', () {
    test('defaults to off', () {
      expect(const CartState().allowOversell, isFalse);
    });

    test('survives copyWith when untouched', () {
      const state = CartState(allowOversell: true);
      expect(state.copyWith(discountPercent: 5).allowOversell, isTrue);
    });

    test('can be turned back off via copyWith', () {
      const state = CartState(allowOversell: true);
      expect(state.copyWith(allowOversell: false).allowOversell, isFalse);
    });

    test('a fresh CartState — what clearCart builds — has it off', () {
      // `CartController.clearCart` constructs a new CartState carrying only the
      // tax settings forward, so the permission cannot leak into the next
      // invoice. This pins that: if clearCart ever starts copying the flag,
      // the guard silently stops protecting subsequent sales.
      const cleared = CartState(taxEnabled: true, taxRate: 0.16);
      expect(cleared.allowOversell, isFalse);
    });
  });
}

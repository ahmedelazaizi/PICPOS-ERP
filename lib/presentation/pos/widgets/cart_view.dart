import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../services/invoice_generator.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:ural_erp/presentation/pos/providers/pos_controller.dart';
import 'package:ural_erp/presentation/pos/widgets/cart/cart_totals_panel.dart';
import 'package:ural_erp/presentation/pos/widgets/cart/cart_discount_dialog.dart';
import 'package:ural_erp/presentation/pos/widgets/cart_item_tile.dart';
// For HeldOrder type

/// Cart view widget
///
/// Displays the shopping cart with items, totals, and checkout controls

part 'cart_auto_scroll.dart';
part 'cart_display_settings.dart';

/// زرار «إظهار المنتجات» (توسيع الشبكة بعد طيّها) — مستخرج كودجت مستقل عن
/// `CartView.build` عشان يتعمله اختبار widget من غير ما نركّب الشاشة كلها.
///
/// `fallback` مش `allowManagerOverride`: طيّ/فتح الشبكة عرض واجهة بحت، مش
/// عملية كتابة — فمن غير الصلاحية الزرار يختفي تماماً، بدل ما يظهر بتصريح
/// مدير لحاجة مالهاش أثر مالي أو بيانات.
@visibleForTesting
Widget buildPosGridToggleButton({
  required VoidCallback onToggle,
  double scaleFactor = 1.0,
}) {
  return PermissionGuard(
    permission: PermissionCodes.posGridToggle,
    fallback: const SizedBox.shrink(),
    child: Tooltip(
      message: tr('توسيع القائمة / إظهار المنتجات'),
      child: TextButton.icon(
        onPressed: onToggle,
        icon: Icon(PhosphorIconsBold.caretDoubleRight,
            size: 16 * scaleFactor, color: AppColors.primary),
        label: Text(
          tr('إظهار المنتجات'),
          style: TextStyle(
            fontSize: 12 * scaleFactor,
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  );
}

class CartView extends ConsumerWidget {
  final VoidCallback? onCheckout;
  final VoidCallback? onClearCart;
  final Function(int index)? onEditItem;

  /// 4.3: Save & Print callback for supermarket mode
  final VoidCallback? onSaveAndPrint;

  /// Phase 3: New callbacks for enhanced checkout flow
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onSave;
  final VoidCallback? onSaveQuotation;

  /// Phase 4 & 5: Exchange and Quick Return callbacks
  final VoidCallback? onExchange;
  final VoidCallback? onQuickReturn;

  /// Phase 7: Previous Invoices callback
  final VoidCallback? onPreviousInvoices;

  /// Phase 8: Quick Expense callback
  final VoidCallback? onExpense;

  /// Phase 9: Deleted Items Report callback
  final VoidCallback? onDeletedItems;
  final VoidCallback? onViewReturns;

  /// Hold order & show held orders callbacks
  final VoidCallback? onHoldOrder;
  final VoidCallback? onShowHeldOrders;

  const CartView({
    super.key,
    this.onCheckout,
    this.onClearCart,
    this.onEditItem,
    this.onSaveAndPrint,
    this.onOpenDrawer,
    this.onSave,
    this.onSaveQuotation,

    this.onExchange,
    this.onQuickReturn,
    this.onViewReturns,
    this.onPreviousInvoices,
    this.onExpense,
    this.onDeletedItems,
    this.onHoldOrder,
    this.onShowHeldOrders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posState = ref.watch(posControllerProvider);
    final cartState = ref.watch(cartControllerProvider);
    final cart = cartState.items;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate scale factor based on cart width - reduced for compact UI
        final scaleFactor = (constraints.maxWidth / 500).clamp(0.55, 0.85);

        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              // (مرتجعات button moved to PosHeader)

              // Cart header (simplified) - FIXED TOP
              _buildHeader(
                context,
                cart,
                ref.read(cartControllerProvider.notifier),
                cartState,
                posState,
                scaleFactor,
                ref,
              ),

              // Cart items - MIDDLE FLEXIBLE AREA
              Expanded(
                child: cart.isEmpty
                    ? _buildEmptyCart()
                    : _buildCartList(
                        cart,
                        ref.read(cartControllerProvider.notifier),
                        cartState,
                      ),
              ),

              // Totals & Checkout section - MODULARIZED
              CartTotalsPanel(
                posState: posState,
                posController: ref.read(posControllerProvider.notifier),
                scaleFactor: scaleFactor,
                onOpenDrawer: onOpenDrawer,
                onPreviousInvoices: onPreviousInvoices,
                onExpense: onExpense,
                onSave: onSave,
                onSaveQuotation: onSaveQuotation,
                onCheckout: onCheckout,
                onSaveAndPrint: onSaveAndPrint,
                buildTaxToggle: _buildTaxToggle,
                buildDiscountButton: _buildDiscountButton,
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildHeader(
    BuildContext context,
    List<CartItemEntity> cart,
    CartController controller,
    CartState cartState,
    PosState posState,
    double scaleFactor,
    WidgetRef ref,
  ) {
    final padding = 12.0 * scaleFactor;

    // Check if current priceLevel is a delivery company
    final isDeliveryCompany = [
      'talabat',
      'careem',
      'ashyae',
    ].contains(cartState.priceLevel);
    final deliveryCompanyName = switch (cartState.priceLevel) {
      'talabat' => tr('طلبات'),
      'careem' => tr('كريم'),
      'ashyae' => tr('أشيائي'),
      _ => null,
    };

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Delivery Company Badge
          if (isDeliveryCompany && deliveryCompanyName != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                gradient: AppColors.errorGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    PhosphorIconsBold.motorcycle,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('{deliveryCompanyName} (آجل)', {'deliveryCompanyName': deliveryCompanyName}),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          // Phase 4: Platform Order Number field (shown for delivery companies)
          if (isDeliveryCompany)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                onChanged: (value) => ref.read(cartControllerProvider.notifier)
                    .setPlatformOrderNumber(value.isEmpty ? null : value),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('رقم طلب {deliveryCompanyName}', {'deliveryCompanyName': deliveryCompanyName}),
                  hintText: tr('أدخل رقم الطلب من التطبيق...'),
                  prefixIcon: const Icon(PhosphorIconsBold.hashStraight, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: AppColors.warning.withValues(alpha: 0.05),
                ),
                style: TextStyle(fontSize: 13 * scaleFactor, fontWeight: FontWeight.bold),
              ),
            ),

          // Cart title row (action buttons moved to PosHeader toolbar)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsBold.shoppingCart,
                  size: 16 * scaleFactor,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 8 * scaleFactor),
              Text(
                tr('السلة ({p0})', {'p0': cart.length}),
                style: TextStyle(
                  fontSize: 14 * scaleFactor,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const Spacer(),
              if (posState.isGridCollapsed &&
                  (ref.watch(showProductLayoutToggleInPOSProvider).value ?? true))
                buildPosGridToggleButton(
                  onToggle: () => ref.read(posControllerProvider.notifier).toggleGridCollapse(),
                  scaleFactor: scaleFactor,
                ),
              SizedBox(width: 4 * scaleFactor),
              // ⚙️ Cart display settings
              _CartDisplaySettingsBtn(scaleFactor: scaleFactor),
              SizedBox(width: 4 * scaleFactor),
              PermissionGuard(
                permission: PermissionCodes.posClearCart,
                allowManagerOverride: true,
                actionName: tr('مسح السلة'),
                child: TextButton.icon(
                  onPressed: () => _showClearConfirmation(
                    context,
                    ref.read(cartControllerProvider.notifier),
                  ),
                  icon: Icon(
                    PhosphorIconsBold.trash,
                    size: 16 * scaleFactor,
                    color: AppColors.error,
                  ),
                  label: Text(
                    tr('مسح الكل'),
                    style: TextStyle(
                      fontSize: 12 * scaleFactor,
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    backgroundColor: AppColors.error.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsBold.shoppingCartSimple,
            size: 64,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
           Text(
            tr('السلة فارغة'),
            style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            tr('اختر منتجات من القائمة أو امسح الباركود'),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(
    List<CartItemEntity> cart,
    CartController controller,
    CartState cartState,
  ) {
    return _AutoScrollCartList(
      cart: cart,
      controller: controller,
      cartState: cartState,
      onEditItem: onEditItem,
    );
  }

  // BUG-U36: reuse AppConfirmDialog (RTL-wrapped, consistent) instead of a
  // bare AlertDialog. Shared with the Delete-key shortcut (BUG-U04).
  Future<void> _showClearConfirmation(
      BuildContext context, CartController controller) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: tr('مسح السلة'),
      message: tr('هل أنت متأكد من مسح جميع المنتجات؟'),
      confirmLabel: tr('مسح'),
      isDangerous: true,
    );
    if (!ok) return;
    controller.clearCart();
    onClearCart?.call();
  }

  Widget _buildTaxToggle(
    CartState cartState,
    CartController cartController,
    double scaleFactor,
  ) {
    return Row(
      children: [
        Transform.scale(
          scale: 0.8 * scaleFactor,
          child: Switch(
            value: cartState.taxEnabled,
            onChanged: (val) => cartController.toggleTax(val),
            activeThumbColor: AppColors.primary,
          ),
        ),
        Text(
          tr('الضريبة ({p0}%)', {'p0': (cartState.taxRate * 100).toStringAsFixed(0)}),
          style: TextStyle(
            fontSize: 11 * scaleFactor,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountButton(
    WidgetRef ref,
    CartState cartState,
    CartController cartController,
    double scaleFactor,
    BuildContext context,
  ) {
    return PermissionGuard(
      permission: PermissionCodes.posDiscount,
      allowManagerOverride: true,
      actionName: tr('تطبيق خصم'),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (dialogContext) => CartDiscountDialog(
            subtotal: cartState.subtotal,
            currentDiscountPercent: cartState.discountPercent,
            onApply: (discount) => cartController.setDiscount(discount),
            onRemove: () {
              cartController.setDiscount(0);
              Navigator.pop(dialogContext);
            },
          ),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 8 * scaleFactor,
            vertical: 4 * scaleFactor,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIconsBold.tag,
                size: 14 * scaleFactor,
                color: AppColors.primary,
              ),
              SizedBox(width: 4 * scaleFactor),
              Text(
                tr('خصم %{p0}', {'p0': cartState.discountPercent.toStringAsFixed(0)}),
                style: TextStyle(
                  fontSize: 11 * scaleFactor,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto-scrolling cart list that scrolls to bottom when items are added

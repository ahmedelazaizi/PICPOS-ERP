import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../data/providers/settings_providers.dart';
import '../../../widgets/permission_guard.dart';
import '../../providers/cart_controller.dart';
import '../../providers/checkout_controller.dart';
import '../../providers/pos_controller.dart';
import '../customer_selector_v2.dart';
import 'total_row.dart';

class CartTotalsPanel extends ConsumerWidget {
  final PosState posState;
  final PosController posController;
  final double scaleFactor;

  // Callbacks
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onPreviousInvoices;
  final VoidCallback? onExpense;
  final VoidCallback? onSaveQuotation;
  final VoidCallback? onSave;
  final VoidCallback? onCheckout;
  final VoidCallback? onSaveAndPrint;

  // New Builder Callbacks for sub-widgets that need ref or context
  final Widget Function(CartState, CartController, double) buildTaxToggle;
  final Widget Function(
    WidgetRef,
    CartState,
    CartController,
    double,
    BuildContext,
  )
  buildDiscountButton;

  const CartTotalsPanel({
    super.key,
    required this.posState,
    required this.posController,
    required this.scaleFactor,
    this.onOpenDrawer,
    this.onPreviousInvoices,
    this.onExpense,
    this.onSaveQuotation,
    this.onSave,
    this.onCheckout,
    this.onSaveAndPrint,
    required this.buildTaxToggle,
    required this.buildDiscountButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartControllerProvider);
    // Spec 137 follow-up: memoize the totals once per build — the getter runs
    // the full net-base two-pass and was being recomputed 6× in this tree.
    final totals = cartState.totals;
    final cartController = ref.read(cartControllerProvider.notifier);
    final checkoutState = ref.watch(checkoutControllerProvider);

    // POS bottom panel settings
    final panelScale = ref.watch(posBottomPanelScaleProvider).value ?? 1.0;
    final btnHeight = ref.watch(posButtonHeightProvider).value ?? 40.0;
    final btnFontSize = ref.watch(posButtonFontSizeProvider).value ?? 13.0;
    final effectiveScale = scaleFactor * panelScale;

    final padding = (16.0 * effectiveScale).clamp(12.0, 20.0);
    final spacing = 12.0 * effectiveScale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Totals Information Section
        Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -4),
              ),
            ],
            border: const Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Error message display
              if (posState.error != null) ...[
                Container(
                  padding: EdgeInsets.all(12 * scaleFactor),
                  margin: EdgeInsets.only(bottom: spacing),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20 * scaleFactor,
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: Text(
                          posState.error!,
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 13 * scaleFactor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Customer selector
              if (ref.watch(showAddCustomerInPOSProvider).value ?? true)
                const PermissionGuard(
                  permission: PermissionCodes.posCustomerSelect,
                  allowManagerOverride: true,
                  actionName: 'اختيار عميل',
                  child: CustomerSelectorV2(),
                ),

              // Phase 4: Ad-hoc customer info (name/phone text fields)
              if (cartState.selectedCustomerId == null &&
                  (ref.watch(showAdhocCustomerInPOSProvider).value ?? true)) ...[
                SizedBox(height: spacing * 0.5),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => cartController.setAdhocCustomer(
                          name: v.isEmpty ? null : v,
                          phone: cartState.adhocCustomerPhone,
                          note: cartState.adhocCustomerNote,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'اسم العميل',
                          prefixIcon: const Icon(PhosphorIconsBold.user, size: 14, color: AppColors.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: TextStyle(fontSize: 11 * effectiveScale),
                      ),
                    ),
                    SizedBox(width: spacing * 0.5),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => cartController.setAdhocCustomer(
                          name: cartState.adhocCustomerName,
                          phone: v.isEmpty ? null : v,
                          note: cartState.adhocCustomerNote,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'رقم الهاتف',
                          prefixIcon: const Icon(PhosphorIconsBold.phone, size: 14, color: AppColors.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: TextStyle(fontSize: 11 * effectiveScale),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    SizedBox(width: spacing * 0.5),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => cartController.setAdhocCustomer(
                          name: cartState.adhocCustomerName,
                          phone: cartState.adhocCustomerPhone,
                          note: v.isEmpty ? null : v,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'ملاحظات',
                          prefixIcon: const Icon(PhosphorIconsBold.notepad, size: 14, color: AppColors.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: TextStyle(fontSize: 11 * effectiveScale),
                      ),
                    ),
                  ],
                ),
              ],

              // Phase 3: Order type toggle (داخلي / توصيل) for kitchen printing
              if (ref.watch(showOrderTypeInPOSProvider).value ?? true) ...[
                SizedBox(height: spacing * 0.5),
                Row(
                children: [
                  Text('نوع الطلب:', style: TextStyle(fontSize: 11 * effectiveScale, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                  SizedBox(width: spacing * 0.5),
                  _OrderTypeChip(
                    label: 'داخلي',
                    icon: PhosphorIconsBold.house,
                    isSelected: cartState.orderType == 'internal',
                    onTap: () => cartController.setOrderType('internal'),
                    scaleFactor: effectiveScale,
                  ),
                  const SizedBox(width: 6),
                  _OrderTypeChip(
                    label: 'توصيل',
                    icon: PhosphorIconsBold.motorcycle,
                    isSelected: cartState.orderType == 'delivery',
                    onTap: () => cartController.setOrderType('delivery'),
                    scaleFactor: effectiveScale,
                  ),
                ],
                ),
              ],
              SizedBox(height: spacing),

              // Tax toggle and Discount row
              Builder(
                builder: (context) {
                  final showTax =
                      ref.watch(showTaxButtonInPOSProvider).value ?? true;
                  final showDiscount =
                      ref.watch(showDiscountButtonInPOSProvider).value ?? true;

                  if (!showTax && !showDiscount) return const SizedBox.shrink();

                  return Row(
                    children: [
                      if (showTax)
                        Expanded(
                          child: PermissionGuard(
                            permission: PermissionCodes.posTaxToggle,
                            allowManagerOverride: true,
                            actionName: 'تغيير الضريبة',
                            child: buildTaxToggle(
                              cartState,
                              cartController,
                              effectiveScale,
                            ),
                          ),
                        ),
                      if (showTax && showDiscount) SizedBox(width: spacing),
                      if (showDiscount)
                        Expanded(
                          child: buildDiscountButton(
                            ref,
                            cartState,
                            cartController,
                            effectiveScale,
                            context,
                          ),
                        ),
                    ],
                  );
                },
              ),

              SizedBox(height: spacing),

              // Payment method moved to dialog (triggered on Save/Save&Print)

              SizedBox(height: spacing * 1.5),

              // Totals Breakdown
              Container(
                padding: EdgeInsets.all(12 * effectiveScale),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    if (ref.watch(showSubtotalInPOSProvider).value ?? true)
                      TotalRow(
                        label: 'المجموع الفرعي',
                        value: totals.subtotal,
                        scaleFactor: effectiveScale,
                      ),
                    if (totals.totalDiscount > 0) ...[
                      TotalRow(
                        label: 'الخصم المسموح به',
                        value: -totals.totalDiscount,
                        valueColor: AppColors.success,
                        scaleFactor: effectiveScale,
                        suffix: cartState.discountPercent > 0
                            ? '(${cartState.discountPercent.toStringAsFixed(0)}%)'
                            : null,
                      ),
                    ],
                    if ((ref.watch(showTaxButtonInPOSProvider).value ?? true) &&
                        cartState.taxEnabled) ...[
                      if (totals.taxAmount > 0)
                        TotalRow(
                          label: 'ضريبة القيمة المضافة',
                          value: totals.taxAmount,
                          scaleFactor: effectiveScale,
                          suffix:
                              '(${(cartState.taxRate * 100).toStringAsFixed(0)}%)',
                        ),
                    ],
                    if (cartState.deliveryFee > 0)
                      TotalRow(
                        label: 'رسوم التوصيل',
                        value: cartState.deliveryFee,
                        scaleFactor: effectiveScale,
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    TotalRow(
                      label: 'الإجمالي النهائي',
                      value: totals.total + cartState.deliveryFee,
                      isTotal: true,
                      scaleFactor: effectiveScale,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Checkout Actions Section (Extracted from _buildCheckoutButton)
        Container(
          padding: EdgeInsets.all(padding),
          decoration: const BoxDecoration(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick Action Row (Drawer, Invoices, Expense)
              Builder(
                builder: (context) {
                  final showDrawer =
                      ref.watch(showDrawerButtonInPOSProvider).value ?? true;
                  final showExpense =
                      ref.watch(showExpenseButtonInPOSProvider).value ?? true;

                  final List<Widget> buttons = [];

                  if (showDrawer) {
                    buttons.add(
                      Expanded(
                        child: PermissionGuard(
                          permission: PermissionCodes.posOpenDrawer,
                          allowManagerOverride: true,
                          actionName: 'فتح الدرج',
                          child: _buildSecondaryBtn(
                            label: 'الدرج',
                            icon: PhosphorIconsBold.stack,
                            color: AppColors.warning,
                            onTap: onOpenDrawer,
                            scaleFactor: effectiveScale,
                            btnHeight: btnHeight,
                            btnFontSize: btnFontSize,
                          ),
                        ),
                      ),
                    );
                  }

                  buttons.add(const SizedBox(width: 8));
                  buttons.add(
                    Expanded(
                      child: PermissionGuard(
                        permission: PermissionCodes.posPreviousInvoices,
                        allowManagerOverride: true,
                        actionName: 'الفواتير السابقة',
                        child: _buildSecondaryBtn(
                          label: 'فواتير',
                          icon: PhosphorIconsBold.archive,
                          color: AppColors.info,
                          onTap: onPreviousInvoices,
                          scaleFactor: effectiveScale,
                          btnHeight: btnHeight,
                          btnFontSize: btnFontSize,
                        ),
                      ),
                    ),
                  );

                  if (showExpense) {
                    buttons.add(const SizedBox(width: 8));
                    buttons.add(
                      Expanded(
                        child: PermissionGuard(
                          permission: PermissionCodes.posExpense,
                          allowManagerOverride: true,
                          actionName: 'إضافة مصروف',
                          child: _buildSecondaryBtn(
                            label: 'مصاريف',
                            icon: PhosphorIconsBold.money,
                            color: AppColors.error,
                            onTap: onExpense,
                            scaleFactor: effectiveScale,
                            btnHeight: btnHeight,
                            btnFontSize: btnFontSize,
                          ),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: buttons),
                  );
                },
              ),

              // Main Action Row: Save | Save & Print
              Row(
                children: [
                  if (ref.watch(showSaveOnlyInPOSProvider).value ?? true)
                    Expanded(
                      child: PermissionGuard(
                        permission: PermissionCodes.posSave,
                        allowManagerOverride: true,
                        actionName: 'حفظ البيع',
                        child: _buildPrimaryBtn(
                          label: checkoutState.isProcessing
                              ? 'جاري...'
                              : 'حفظ وفتح الدرج',
                          icon: PhosphorIconsBold.floppyDisk,
                          color: AppColors.primary,
                          onTap:
                              (cartState.items.isEmpty ||
                                  checkoutState.isProcessing)
                              ? null
                              : (onSave ?? onCheckout),
                          isLoading: checkoutState.isProcessing,
                          scaleFactor: effectiveScale,
                          btnHeight: btnHeight,
                          btnFontSize: btnFontSize,
                        ),
                      ),
                    ),
                  if (ref.watch(showSaveOnlyInPOSProvider).value ?? true)
                    const SizedBox(width: 10),
                  Expanded(
                    child: PermissionGuard(
                      permission: PermissionCodes.posPrint,
                      allowManagerOverride: true,
                      actionName: 'حفظ وطباعة',
                      child: _buildPrimaryBtn(
                        label: 'حفظ وطباعة',
                        icon: PhosphorIconsBold.printer,
                        color: AppColors.success,
                        onTap:
                            (cartState.items.isEmpty ||
                                checkoutState.isProcessing)
                            ? null
                            : (onSaveAndPrint ?? onCheckout),
                        featured: true,
                        scaleFactor: effectiveScale,
                        btnHeight: btnHeight,
                        btnFontSize: btnFontSize,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required double scaleFactor,
    double btnHeight = 40,
    double btnFontSize = 13,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: btnHeight * scaleFactor,
          padding: EdgeInsets.symmetric(horizontal: 8 * scaleFactor),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
            color: color.withValues(alpha: 0.1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: (btnFontSize + 4) * scaleFactor, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: btnFontSize * scaleFactor,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
    bool featured = false,
    required double scaleFactor,
    double btnHeight = 40,
    double btnFontSize = 13,
  }) {
    return Material(
      color: featured ? color : color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: (btnHeight + 10) * scaleFactor,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: featured
                ? null
                : Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    height: 20 * scaleFactor,
                    width: 20 * scaleFactor,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        featured ? Colors.white : color,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: featured ? Colors.white : color,
                        size: (btnFontSize + 4) * scaleFactor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: featured ? Colors.white : color,
                          fontWeight: FontWeight.w900,
                          fontSize: btnFontSize * scaleFactor,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Compact chip for order type selection (داخلي / توصيل)
class _OrderTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final double scaleFactor;

  const _OrderTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.scaleFactor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10 * scaleFactor, vertical: 5 * scaleFactor),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14 * scaleFactor, color: isSelected ? AppColors.primary : AppColors.textMuted),
            SizedBox(width: 4 * scaleFactor),
            Text(
              label,
              style: TextStyle(
                fontSize: 11 * scaleFactor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

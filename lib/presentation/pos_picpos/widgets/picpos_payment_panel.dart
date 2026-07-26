// ═══════════════════════════════════════════════════════════════════════════
// PICPOS — لوحة المجاميع والدفع
// ═══════════════════════════════════════════════════════════════════════════
//
// نسخة مستقلة عن `cart/cart_totals_panel.dart` و`cart/cart_payment_selector.dart`
// بتاعت UralCash، بقرار صريح من صاحب المشروع: «استنسخه من ural واشتغل عليه
// لشغل picpos».
//
// ── ليه نسخة وليس إعادة استخدام؟ ──────────────────────────────────────────
// `CartTotalsPanel` مش مكوّن مستقل: بياخد `buildTaxToggle` و`buildDiscountButton`
// **كدوال بناء** من جوّه `cart_view.dart`، فاستخدامه من برّه معناه تفكيك
// `cart_view.dart` — أخطر ملف في شاشة UralCash، ومفيش اختبارات widget تغطيه.
//
// ── إيه اللي **مش** منسوخ ─────────────────────────────────────────────────
// المنطق. كل قرار مالي هنا بيروح لنفس الكائنات: `cart_controller` للطرق
// والصناديق والخصم والضريبة، و`checkout_controller` للترحيل، و`PaymentSheet`
// للدفع المتعدد. الملف ده تخطيط وشكل وقراءة إعدادات — مفيش حساب فلوس فيه.
//
// ── إعدادات نقطة البيع ────────────────────────────────────────────────────
// اللوحة بتحترم إعدادات الإظهار والمقاسات اللي في «إعدادات نقطة البيع»:
//   الأزرار:  ضريبة · خصم · درج · مصاريف · حفظ-فقط · إجمالي فرعي
//   العميل:   إضافة عميل · عميل عابر · نوع الطلب
//   المقاسات: posBottomPanelScale · posButtonHeight · posButtonFontSize ·
//             paymentButtonHeight
// كل واحد بياخد نفس الافتراضي اللي شاشة UralCash بتاخده، فتركيب بينقل بين
// المنتجين مش بيلاقي سلوك مختلف من غير ما يغيّر إعداد.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../../pos/providers/cart_controller.dart';
import '../../widgets/permission_guard.dart';

class PicPosPaymentPanel extends ConsumerWidget {
  final VoidCallback onCheckout;
  final VoidCallback onSave;
  final VoidCallback onSaveAndPrint;
  final VoidCallback onEditDiscount;
  final VoidCallback onPickCustomer;
  final VoidCallback onPreviousInvoices;
  final VoidCallback onOpenDrawer;
  final VoidCallback onExpense;
  final VoidCallback onHold;
  final VoidCallback onHeldOrders;

  const PicPosPaymentPanel({
    super.key,
    required this.onCheckout,
    required this.onSave,
    required this.onSaveAndPrint,
    required this.onEditDiscount,
    required this.onPickCustomer,
    required this.onPreviousInvoices,
    required this.onOpenDrawer,
    required this.onExpense,
    required this.onHold,
    required this.onHeldOrders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final totals = cart.totals;

    // المفاتيح هي نفس مفاتيح UralCash. الافتراضيات لما الإعداد مش مضبوط
    // **أصغر** عن قصد: عمود الفاتورة هنا ضيّق (٤٠٪) مش نص الشاشة زي سلة
    // UralCash، وأول تنفيذ بافتراضيات UralCash خلّى اللوحة تاكل العمود
    // والجدول ينسحق لصفر — بلاغ ميداني: «الأزرار ضخمة ومغطية على السلة».
    // أي قيمة مضبوطة في الإعدادات بتكسب على الافتراضي ده.
    final scale = ref.watch(posBottomPanelScaleProvider).value ?? 1.0;
    final btnHeight = ref.watch(posButtonHeightProvider).value ?? 32.0;
    final btnFont = ref.watch(posButtonFontSizeProvider).value ?? 12.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.all(7 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // العميل ونوع الطلب على صف واحد — كانوا صفّين وكل واحد بارتفاع
          // كامل، وهما أقل حاجة الكاشير بيلمسها في اللوحة.
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _CustomerRow(
                    onPickCustomer: onPickCustomer, scale: scale),
              ),
              _OrderTypeRow(cart: cart, controller: controller, scale: scale),
            ],
          ),
          _TotalsBlock(
            cart: cart,
            controller: controller,
            totals: totals,
            scale: scale,
            onEditDiscount: onEditDiscount,
          ),
          SizedBox(height: 5 * scale),
          _PaymentMethodRow(cart: cart, controller: controller, scale: scale),
          SizedBox(height: 5 * scale),
          _ActionButtons(
            scale: scale,
            btnHeight: btnHeight,
            btnFont: btnFont,
            onCheckout: onCheckout,
            onSave: onSave,
            onSaveAndPrint: onSaveAndPrint,
            onPreviousInvoices: onPreviousInvoices,
            onOpenDrawer: onOpenDrawer,
            onExpense: onExpense,
            onHold: onHold,
            onHeldOrders: onHeldOrders,
          ),
        ],
      ),
    );
  }
}

// ── العميل ─────────────────────────────────────────────────────────────────

class _CustomerRow extends ConsumerWidget {
  final VoidCallback onPickCustomer;
  final double scale;

  const _CustomerRow({required this.onPickCustomer, required this.scale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(showAddCustomerInPOSProvider).value ?? true)) {
      return const SizedBox.shrink();
    }
    final cart = ref.watch(cartControllerProvider);
    final name = cart.selectedCustomerName ?? cart.adhocCustomerName;
    final isSet = name != null && name.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: InkWell(
        onTap: onPickCustomer,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9 * scale),
          decoration: BoxDecoration(
            color: isSet
                ? AppColors.primary.withValues(alpha: 0.07)
                : const Color(0xFFF4F7FC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSet ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.user,
                  size: 15, color: isSet ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSet ? name : 'عميل نقدي — اضغط للاختيار',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    fontWeight: isSet ? FontWeight.bold : FontWeight.normal,
                    color: isSet ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ),
              const Icon(PhosphorIconsBold.caretLeft,
                  size: 13, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── نوع الطلب ──────────────────────────────────────────────────────────────

class _OrderTypeRow extends ConsumerWidget {
  final CartState cart;
  final CartController controller;
  final double scale;

  const _OrderTypeRow({
    required this.cart,
    required this.controller,
    required this.scale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(showOrderTypeInPOSProvider).value ?? true)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: Row(
        children: [
          Expanded(
            child: _TypeChip(
              label: 'داخلي',
              icon: PhosphorIconsBold.storefront,
              selected: cart.orderType == 'internal',
              onTap: () => controller.setOrderType('internal'),
              scale: scale,
            ),
          ),
          SizedBox(width: 6 * scale),
          Expanded(
            child: _TypeChip(
              label: 'توصيل',
              icon: PhosphorIconsBold.moped,
              selected: cart.orderType == 'delivery',
              onTap: () => controller.setOrderType('delivery'),
              scale: scale,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double scale;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 7 * scale),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF4F7FC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── المجاميع ───────────────────────────────────────────────────────────────

class _TotalsBlock extends ConsumerWidget {
  final CartState cart;
  final CartController controller;
  final InvoiceTotals totals;
  final double scale;
  final VoidCallback onEditDiscount;

  const _TotalsBlock({
    required this.cart,
    required this.controller,
    required this.totals,
    required this.scale,
    required this.onEditDiscount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSubtotal = ref.watch(showSubtotalInPOSProvider).value ?? true;
    final showTax = ref.watch(showTaxButtonInPOSProvider).value ?? true;
    final showDiscount =
        ref.watch(showDiscountButtonInPOSProvider).value ?? true;

    return Column(
      children: [
        if (showTax || showDiscount)
          Padding(
            padding: EdgeInsets.only(bottom: 8 * scale),
            child: Row(
              children: [
                if (showTax)
                  Expanded(
                    child: _ToggleTile(
                      label: 'ضريبة',
                      icon: PhosphorIconsBold.receipt,
                      active: cart.taxEnabled,
                      // نفس الاستدعاء اللي شاشة UralCash بتعمله — الحساب كله
                      // جوّه `CartState.totals`، مفيش نسبة محسوبة هنا.
                      onTap: () => controller.toggleTax(!cart.taxEnabled),
                      scale: scale,
                    ),
                  ),
                if (showTax && showDiscount) SizedBox(width: 6 * scale),
                if (showDiscount)
                  Expanded(
                    child: _ToggleTile(
                      label: cart.discountPercent > 0
                          ? 'خصم ${NumberUtils.formatPercent(cart.discountPercent)}'
                          : 'خصم',
                      icon: PhosphorIconsBold.percent,
                      active: cart.discountPercent > 0,
                      onTap: onEditDiscount,
                      scale: scale,
                    ),
                  ),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              if (showSubtotal)
                _Line(
                  label: 'المجموع الفرعي',
                  value: totals.subtotal,
                  scale: scale,
                ),
              if (totals.totalDiscount > 0)
                _Line(
                  label: 'الخصم',
                  value: totals.totalDiscount,
                  scale: scale,
                  color: AppColors.error,
                  negative: true,
                ),
              if (showTax && cart.taxEnabled)
                _Line(
                  label: 'ضريبة القيمة المضافة',
                  value: totals.taxAmount,
                  scale: scale,
                ),
              if (cart.deliveryFee > 0)
                _Line(
                  label: 'رسوم التوصيل',
                  value: cart.deliveryFee,
                  scale: scale,
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 5 * scale),
                child: const Divider(height: 1),
              ),
              Row(
                children: [
                  Text(
                    'الإجمالي النهائي',
                    style: TextStyle(
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    NumberUtils.formatCurrency(cart.total),
                    style: TextStyle(
                      fontSize: 24 * scale,
                      fontWeight: FontWeight.bold,
                      color: cart.isNegative
                          ? AppColors.error
                          : AppColors.primaryDark,
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
}

class _Line extends StatelessWidget {
  final String label;
  final double value;
  final double scale;
  final Color? color;
  final bool negative;

  const _Line({
    required this.label,
    required this.value,
    required this.scale,
    this.color,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2 * scale),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12 * scale, color: AppColors.textMuted)),
          const Spacer(),
          Text(
            '${negative ? '− ' : ''}${NumberUtils.formatCurrency(value)}',
            style: TextStyle(
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final double scale;

  const _ToggleTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.10)
              : const Color(0xFFF4F7FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── طرق الدفع ──────────────────────────────────────────────────────────────

class _PaymentMethodRow extends ConsumerWidget {
  final CartState cart;
  final CartController controller;
  final double scale;

  const _PaymentMethodRow({
    required this.cart,
    required this.controller,
    required this.scale,
  });

  static bool _isBankMethod(String m) => m == 'card' || m == 'click';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = ref.watch(paymentButtonHeightProvider).value ?? 36.0;
    final bankSafes = ref.watch(branchBankSafesProvider).value ?? const <Safe>[];
    final cashSafes = ref.watch(branchCashSafesProvider).value ?? const <Safe>[];

    // شركات التوصيل بتتحاسب آجل — نفس القاعدة في شاشة UralCash. الطرق
    // التانية بتتعطّل بصرياً بدل ما تُخفى، عشان الكاشير يفهم إن ده قيد على
    // مستوى العميل مش زرار ناقص.
    final creditOnly =
        ['talabat', 'careem', 'ashyae'].contains(cart.priceLevel);

    return Column(
      children: [
        Row(
          children: [
            _method(context, ref, 'cash', 'نقدي', PhosphorIconsBold.money,
                AppColors.success, PermissionCodes.posPaymentCash,
                height: height, disabled: creditOnly, bankSafes: bankSafes),
            SizedBox(width: 4 * scale),
            _method(context, ref, 'card', 'بطاقة', PhosphorIconsBold.creditCard,
                AppColors.info, PermissionCodes.posPaymentCard,
                height: height, disabled: creditOnly, bankSafes: bankSafes),
            SizedBox(width: 4 * scale),
            _method(context, ref, 'click', 'كليك',
                PhosphorIconsBold.cellSignalFull, const Color(0xFF7C3AED),
                PermissionCodes.posPaymentTransfer,
                height: height, disabled: creditOnly, bankSafes: bankSafes),
            SizedBox(width: 4 * scale),
            _method(context, ref, 'credit', 'آجل', PhosphorIconsBold.timer,
                AppColors.warning, PermissionCodes.posPaymentCredit,
                height: height, bankSafes: bankSafes),
            SizedBox(width: 4 * scale),
            _method(context, ref, 'multiple', 'متعدد',
                PhosphorIconsBold.circlesThreePlus, AppColors.primary,
                PermissionCodes.posPaymentMultiple,
                height: height, disabled: creditOnly, bankSafes: bankSafes),
          ],
        ),
        if (_isBankMethod(cart.paymentMethod))
          _SafeChip(
            icon: PhosphorIconsBold.bank,
            color: AppColors.info,
            label: _bankName(bankSafes) ?? 'لا يوجد حساب بنكي',
            scale: scale,
            onTap: bankSafes.length > 1
                ? () => _pickBank(context, bankSafes)
                : null,
          ),
        if (cart.paymentMethod == 'cash' && cashSafes.isNotEmpty)
          _SafeChip(
            icon: PhosphorIconsBold.vault,
            color: AppColors.success,
            label: 'الصندوق: ${cashSafes.first.name}',
            scale: scale,
          ),
      ],
    );
  }

  Widget _method(
    BuildContext context,
    WidgetRef ref,
    String method,
    String label,
    IconData icon,
    Color color,
    String permission, {
    required double height,
    required List<Safe> bankSafes,
    bool disabled = false,
  }) {
    return Expanded(
      child: PermissionGuard(
        permission: permission,
        child: _MethodTile(
          label: label,
          icon: icon,
          color: color,
          height: height,
          scale: scale,
          selected: cart.paymentMethod == method,
          disabled: disabled,
          onTap: disabled
              ? null
              : () {
                  if (_isBankMethod(method)) {
                    _selectBank(context, method, bankSafes);
                  } else {
                    controller.setPaymentMethod(method);
                    controller.setBankSafe(null);
                  }
                },
        ),
      ),
    );
  }

  /// اختيار حساب بنكي: واحد → تلقائي، أكثر → قائمة، ولا شيء → `null` ويتولّى
  /// الـ DAO الاحتياطي. نفس السلوك بالحرف في شاشة UralCash — تغييره هنا كان
  /// معناه إن نفس الفاتورة تترحّل على صندوق مختلف حسب الشاشة.
  void _selectBank(BuildContext context, String method, List<Safe> bankSafes) {
    controller.setPaymentMethod(method);
    if (bankSafes.isEmpty) {
      controller.setBankSafe(null);
    } else if (bankSafes.length == 1) {
      controller.setBankSafe(bankSafes.first.id);
    } else {
      _pickBank(context, bankSafes);
    }
  }

  void _pickBank(BuildContext context, List<Safe> bankSafes) {
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlayBox),
        box.localToGlobal(box.size.bottomRight(Offset.zero),
            ancestor: overlayBox),
      ),
      Offset.zero & overlayBox.size,
    );
    showMenu<int>(
      context: context,
      position: position,
      items: [
        for (final safe in bankSafes)
          PopupMenuItem<int>(
            value: safe.id,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.bank,
                      size: 15,
                      color: cart.bankSafeId == safe.id
                          ? AppColors.primary
                          : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(safe.name)),
                  if (cart.bankSafeId == safe.id)
                    const Icon(PhosphorIconsBold.check,
                        size: 15, color: AppColors.primary),
                ],
              ),
            ),
          ),
      ],
    ).then((id) {
      if (id != null) controller.setBankSafe(id);
    });
  }

  String? _bankName(List<Safe> bankSafes) {
    if (bankSafes.isEmpty) return null;
    if (cart.bankSafeId != null) {
      final m = bankSafes.where((s) => s.id == cart.bankSafeId);
      if (m.isNotEmpty) return m.first.name;
    }
    return bankSafes.length == 1 ? bankSafes.first.name : 'اختر البنك';
  }
}

class _MethodTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final double height;
  final double scale;

  const _MethodTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.height,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final on = selected && !disabled;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: on ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? color : color.withValues(alpha: 0.30),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16 * scale, color: on ? Colors.white : color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11 * scale,
                  fontWeight: on ? FontWeight.bold : FontWeight.w600,
                  color: on ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafeChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double scale;
  final VoidCallback? onTap;

  const _SafeChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.scale,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11 * scale,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(PhosphorIconsBold.caretDown, size: 10, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── أزرار الأفعال ──────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final double scale;
  final double btnHeight;
  final double btnFont;
  final VoidCallback onCheckout;
  final VoidCallback onSave;
  final VoidCallback onSaveAndPrint;
  final VoidCallback onPreviousInvoices;
  final VoidCallback onOpenDrawer;
  final VoidCallback onExpense;
  final VoidCallback onHold;
  final VoidCallback onHeldOrders;

  const _ActionButtons({
    required this.scale,
    required this.btnHeight,
    required this.btnFont,
    required this.onCheckout,
    required this.onSave,
    required this.onSaveAndPrint,
    required this.onPreviousInvoices,
    required this.onOpenDrawer,
    required this.onExpense,
    required this.onHold,
    required this.onHeldOrders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDrawer = ref.watch(showDrawerButtonInPOSProvider).value ?? true;
    final showExpense = ref.watch(showExpenseButtonInPOSProvider).value ?? true;
    final showSaveOnly = ref.watch(showSaveOnlyInPOSProvider).value ?? true;
    final showHold = ref.watch(showHoldButtonInPOSProvider).value ?? true;
    final isEmpty =
        ref.watch(cartControllerProvider.select((s) => s.items.isEmpty));

    return Column(
      children: [
        // صف واحد: الدفع بارز وبياخد ضعف عرض جاره، والحفظ والطباعة جانبه.
        // كانوا تلات صفوف منفصلة، وده كان بياكل ~١٤٠ بكسل من الجدول.
        Row(
          children: [
            Expanded(
              flex: showSaveOnly ? 2 : 1,
              child: SizedBox(
                height: btnHeight + 6,
                child: ElevatedButton(
                  onPressed: isEmpty ? null : onCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    padding: EdgeInsets.zero,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsBold.money, size: btnFont + 4),
                      const SizedBox(width: 5),
                      Text('دفع F4',
                          style: TextStyle(
                              fontSize: btnFont + 1,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            if (showSaveOnly) ...[
              SizedBox(width: 5 * scale),
              Expanded(
                child: _Action(
                  label: 'حفظ F2',
                  icon: PhosphorIconsBold.floppyDisk,
                  onTap: isEmpty ? null : onSave,
                  height: btnHeight + 6,
                  font: btnFont,
                ),
              ),
              SizedBox(width: 5 * scale),
              Expanded(
                child: _Action(
                  label: 'طباعة F3',
                  icon: PhosphorIconsBold.printer,
                  onTap: isEmpty ? null : onSaveAndPrint,
                  height: btnHeight + 6,
                  font: btnFont,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 5 * scale),
        // الأفعال الثانوية: أيقونة + تسمية صغيرة. كل واحد خلف إعداد إظهاره.
        Row(
          children: [
            Expanded(
              child: _MiniAction(
                label: 'فواتير',
                icon: PhosphorIconsBold.receipt,
                onTap: onPreviousInvoices,
                height: btnHeight,
                font: btnFont - 1,
              ),
            ),
            if (showHold) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: 'تعليق',
                  icon: PhosphorIconsBold.pauseCircle,
                  onTap: isEmpty ? null : onHold,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: 'معلقة',
                  icon: PhosphorIconsBold.listChecks,
                  onTap: onHeldOrders,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
            if (showDrawer) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: 'الدرج',
                  icon: PhosphorIconsBold.money,
                  onTap: onOpenDrawer,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
            if (showExpense) ...[
              SizedBox(width: 4 * scale),
              Expanded(
                child: _MiniAction(
                  label: 'مصاريف',
                  icon: PhosphorIconsBold.coins,
                  onTap: onExpense,
                  height: btnHeight,
                  font: btnFont - 1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// زرار ثانوي مضغوط — أيقونة فوق تسمية، بلا إطار ثقيل.
class _MiniAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: font + 2, color: AppColors.primaryDark),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: font,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final double height;
  final double font;

  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.height,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.primaryDark,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: font, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../widgets/permission_guard.dart';
import '../../providers/cart_controller.dart';

class TablePosSummary extends ConsumerWidget {
  final VoidCallback onSendToKitchen;
  final VoidCallback onCheckout;
  final VoidCallback onClear;
  final VoidCallback onBack;

  /// تفعيلُ الضريبة على **الطلب** أو إطفاؤها. الشاشةُ هي من تنادي
  /// `TableSessionService.setOrderTax` — الودجت تبقى بلا خدمةٍ ولا قاعدة.
  final ValueChanged<bool> onToggleTax;

  const TablePosSummary({
    super.key,
    required this.onSendToKitchen,
    required this.onCheckout,
    required this.onClear,
    required this.onBack,
    required this.onToggleTax,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartControllerProvider);
    final taxRatePercent = (cartState.taxRate * 100).toStringAsFixed(0);
    final total = cartState.total;
    final hasItems = cartState.items.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0F172A)],
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          // Tax button
          _buildTaxToggle(cartState, taxRatePercent),
          
          const SizedBox(height: 10),

          // Total row
          _buildTotalRow(total),

          const SizedBox(height: 12),

          // Primary Actions (Kitchen + Checkout)
          Row(
            children: [
              Expanded(
                flex: 5,
                child: PermissionGuard(
                  permission: PermissionCodes.tablesAddItems,
                  allowManagerOverride: true,
                  actionName: tr('إرسال للمطبخ'),
                  child: _kitchenButton(hasItems),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: PermissionGuard(
                  permission: PermissionCodes.tablesCheckout,
                  allowManagerOverride: true,
                  actionName: tr('تحصيل الحساب'),
                  child: _checkoutButton(),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),

          // Secondary Actions (Clear + Back)
          Row(
            children: [
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.tablesCancel,
                  allowManagerOverride: true,
                  actionName: tr('إفراغ / إلغاء طلب الطاولة'),
                  child: _secondaryButton(
                    label: tr('إفراغ'),
                    icon: PhosphorIconsBold.trash,
                    color: const Color(0xFFEF4444),
                    onTap: onClear,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _secondaryButton(
                  label: tr('رجوع'),
                  icon: PhosphorIconsBold.arrowRight,
                  color: const Color(0xFF6B7280),
                  onTap: onBack,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// زرُّ الضريبة — شكلُه ونصُّه كما هما، ومقصدُه تغيّر.
  ///
  /// كان يكتب في السلّة وحدَها، فيضيع بمجرّد الخروج من الشاشة ولا يعرف به
  /// الطلب. صار يمرّ بـ[onToggleTax] التي تكتبه على `TableOrders.taxEnabled`
  /// ثم تُحدِّث السلّةَ مرآةً له — فالمعروضُ والمسجَّلُ شيءٌ واحد.
  Widget _buildTaxToggle(dynamic cartState, String taxRatePercent) {
    return InkWell(
      onTap: () => onToggleTax(!(cartState.taxEnabled as bool)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cartState.taxEnabled 
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cartState.taxEnabled 
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cartState.taxEnabled 
                        ? AppColors.primary 
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    PhosphorIconsFill.percent,
                    size: 14,
                    color: cartState.taxEnabled 
                        ? Colors.white 
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('ضريبة المبيعات'),
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      cartState.taxEnabled ? tr('مفعلة ({taxRatePercent}%)', {'taxRatePercent': taxRatePercent}) : tr('معطلة'),
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: cartState.taxEnabled 
                            ? AppColors.primary 
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _toggleIndicator(cartState.taxEnabled),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(double total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr('الإجمالي'),
              style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5))),
          Text(
              '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ],
      ),
    );
  }

  Widget _kitchenButton(bool hasItems) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasItems ? onSendToKitchen : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: hasItems
                ? const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)])
                : null,
            color: hasItems ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            boxShadow: hasItems
                ? [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsBold.cookingPot,
                  size: 20,
                  color: hasItems ? Colors.white : Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 8),
              Text(tr('إرسال للمطبخ'),
                  style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: hasItems ? Colors.white : Colors.white.withValues(alpha: 0.2))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCheckout,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(PhosphorIconsBold.receipt, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text(tr('تحصيل الحساب'),
                  style: GoogleFonts.cairo(
                      fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.cairo(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleIndicator(bool enabled) {
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: enabled ? AppColors.primary : Colors.white.withValues(alpha: 0.2), width: 2),
      ),
      padding: const EdgeInsets.all(2),
      child: enabled ? Container(decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)) : null,
    );
  }
}
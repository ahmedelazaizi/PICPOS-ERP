import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../data/providers/auth_providers.dart';
import '../../../../data/providers/settings_providers.dart';
import '../../../../data/database/database.dart';
import '../../../widgets/permission_guard.dart';
import '../../providers/cart_controller.dart';

class CartPaymentSelector extends ConsumerWidget {
  final CartState state;
  final CartController controller;
  final double scaleFactor;

  const CartPaymentSelector({
    super.key,
    required this.state,
    required this.controller,
    required this.scaleFactor,
  });

  /// Returns true if the given method routes to a bank safe
  static bool _isBankMethod(String method) =>
      method == 'card' || method == 'click';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use larger base sizes for clearer payment buttons
    final iconSize = 16.0 * scaleFactor;
    final fontSize = 12.0 * scaleFactor;
    final spacing = 4.0 * scaleFactor;

    // Configurable button height from settings
    final btnHeightAsync = ref.watch(paymentButtonHeightProvider);
    final buttonHeight = btnHeightAsync.value ?? 45.0;

    // Check if current price level is a delivery company - force credit only
    final isDeliveryCompany = [
      'talabat',
      'careem',
      'ashyae',
    ].contains(state.priceLevel);

    // Fetch branch bank safes
    final bankSafesAsync = ref.watch(branchBankSafesProvider);
    final bankSafes = bankSafesAsync.value ?? [];

    // Fetch branch cash safes
    final cashSafesAsync = ref.watch(branchCashSafesProvider);
    final cashSafes = cashSafesAsync.value ?? [];

    // Safe name displays
    final selectedBankName = _getSelectedBankName(bankSafes);
    final cashSafeName = cashSafes.isNotEmpty ? cashSafes.first.name : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posPaymentCash,
                child: _buildPaymentOption(
                  label: tr('نقدي'),
                  icon: PhosphorIconsBold.money,
                  isSelected: state.paymentMethod == 'cash',
                  onTap: isDeliveryCompany
                      ? null
                      : () {
                          controller.setPaymentMethod('cash');
                          controller.setBankSafe(null);
                        },
                  color: AppColors.success,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  buttonHeight: buttonHeight,
                  disabled: isDeliveryCompany,
                ),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posPaymentCard,
                child: _buildPaymentOption(
                  label: tr('بطاقة'),
                  icon: PhosphorIconsBold.creditCard,
                  isSelected: state.paymentMethod == 'card',
                  onTap: isDeliveryCompany
                      ? null
                      : () => _selectBankMethod(context, ref, 'card', bankSafes),
                  color: AppColors.info,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  buttonHeight: buttonHeight,
                  disabled: isDeliveryCompany,
                ),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posPaymentTransfer,
                child: _buildPaymentOption(
                  label: tr('كليك'),
                  icon: PhosphorIconsBold.cellSignalFull,
                  isSelected: state.paymentMethod == 'click',
                  onTap: isDeliveryCompany
                      ? null
                      : () => _selectBankMethod(context, ref, 'click', bankSafes),
                  color: const Color(0xFF7C3AED),
                  iconSize: iconSize,
                  fontSize: fontSize,
                  buttonHeight: buttonHeight,
                  disabled: isDeliveryCompany,
                ),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posPaymentCredit,
                child: _buildPaymentOption(
                  label: tr('آجل'),
                  icon: PhosphorIconsBold.timer,
                  isSelected: state.paymentMethod == 'credit',
                  onTap: () {
                    controller.setPaymentMethod('credit');
                    controller.setBankSafe(null);
                  },
                  color: AppColors.warning,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  buttonHeight: buttonHeight,
                ),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posPaymentMultiple,
                child: _buildPaymentOption(
                  label: tr('متعدد'),
                  icon: PhosphorIconsBold.circlesThreePlus,
                  isSelected: state.paymentMethod == 'multiple',
                  onTap: isDeliveryCompany
                      ? null
                      : () {
                          controller.setPaymentMethod('multiple');
                          controller.setBankSafe(null);
                        },
                  color: AppColors.primary,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  buttonHeight: buttonHeight,
                  disabled: isDeliveryCompany,
                ),
              ),
            ),
          ],
        ),
        // Show selected bank name when a bank method is active
        if (_isBankMethod(state.paymentMethod) && selectedBankName != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: bankSafes.length > 1
                  ? () => _showBankSelector(context, ref, bankSafes)
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsBold.bank, size: 12, color: AppColors.info),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        selectedBankName,
                        style: TextStyle(
                          fontSize: 10 * scaleFactor,
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (bankSafes.length > 1) ...[
                      const SizedBox(width: 4),
                      const Icon(PhosphorIconsBold.caretDown, size: 10, color: AppColors.info),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // Show cash safe name when cash method is active
        if (state.paymentMethod == 'cash' && cashSafeName != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.vault, size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      tr('الصندوق: {cashSafeName}', {'cashSafeName': cashSafeName}),
                      style: TextStyle(
                        fontSize: 10 * scaleFactor,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Multiple payment: handled via PaymentSheet dialog on save/checkout
      ],
    );
  }

  /// Handle bank method selection — auto-select if single bank, show picker if multiple
  void _selectBankMethod(
    BuildContext context,
    WidgetRef ref,
    String method,
    List<Safe> bankSafes,
  ) {
    controller.setPaymentMethod(method);

    if (bankSafes.isEmpty) {
      // No bank safes — use default fallback (DAO handles this)
      controller.setBankSafe(null);
    } else if (bankSafes.length == 1) {
      // Single bank — auto-select
      controller.setBankSafe(bankSafes.first.id);
    } else {
      // Multiple banks — show selector
      _showBankSelector(context, ref, bankSafes);
    }
  }

  /// Show bank selection popup
  void _showBankSelector(
    BuildContext context,
    WidgetRef ref,
    List<Safe> bankSafes,
  ) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: bankSafes.map<PopupMenuEntry>((safe) {
        final isSelected = state.bankSafeId == safe.id;
        return PopupMenuItem(
          value: safe.id,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                Icon(
                  PhosphorIconsBold.bank,
                  size: 16,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    safe.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.primary : null,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(PhosphorIconsBold.check, size: 16, color: AppColors.primary),
              ],
            ),
          ),
        );
      }).toList(),
    ).then((selectedId) {
      if (selectedId != null) {
        controller.setBankSafe(selectedId as int);
      }
    });
  }

  /// Get the display name for the currently selected bank safe
  String? _getSelectedBankName(List<Safe> bankSafes) {
    if (bankSafes.isEmpty) return null;
    if (state.bankSafeId != null) {
      final match = bankSafes.where((s) => s.id == state.bankSafeId);
      if (match.isNotEmpty) return match.first.name;
    }
    // Show first bank name if only one exists
    if (bankSafes.length == 1) return bankSafes.first.name;
    return tr('اختر البنك');
  }

  Widget _buildPaymentOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    VoidCallback? onTap,
    Color? color,
    double iconSize = 14,
    double fontSize = 9,
    required double buttonHeight,
    bool disabled = false,
  }) {
    final effectiveColor = disabled
        ? Colors.grey
        : (color ?? AppColors.primary);
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              vertical: (buttonHeight - iconSize - fontSize - 4) / 2,
              horizontal: 2,
            ),
            decoration: BoxDecoration(
              color: isSelected && !disabled
                  ? effectiveColor
                  : effectiveColor.withValues(alpha: 0.08),
              border: Border.all(
                color: isSelected && !disabled
                    ? effectiveColor
                    : effectiveColor.withValues(alpha: 0.3),
                width: isSelected && !disabled ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: isSelected && !disabled
                  ? [
                      BoxShadow(
                        color: effectiveColor.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: iconSize,
                  color: isSelected && !disabled
                      ? (ThemeData.estimateBrightnessForColor(effectiveColor) ==
                                Brightness.light
                            ? Colors.black
                            : Colors.white)
                      : effectiveColor,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: isSelected && !disabled
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: isSelected && !disabled
                        ? (ThemeData.estimateBrightnessForColor(
                                    effectiveColor,
                                  ) ==
                                  Brightness.light
                              ? Colors.black
                              : Colors.white)
                        : effectiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Helper: Build a compact split payment field row
  // ignore: unused_element
  Widget _buildSplitField({
    required IconData icon,
    required Color iconColor,
    required String label,
    required double scaleFactor,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text('$label:', style: TextStyle(fontSize: 11 * scaleFactor, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12 * scaleFactor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0.00',
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

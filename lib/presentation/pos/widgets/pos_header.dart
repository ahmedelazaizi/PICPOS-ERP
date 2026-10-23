import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:io';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/strategies/industry_mode_strategy.dart';
import '../providers/pos_controller.dart';
import '../providers/cart_controller.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';
import 'header/pos_header_button.dart';
import 'header/pos_status_indicators.dart';
import 'header/pos_notification_bell.dart';
import 'header/pos_low_stock_indicator.dart';

/// جرس الإشعارات وتنبيه نقص المخزون — عرض بحت (مفيش أي كتابة)، فالحارس هنا
/// `fallback` مش `allowManagerOverride`: من غير الصلاحية العنصر يختفي، ومفيش
/// داعي لتصريح مدير لمجرد إخفاء/إظهار widget. مستخرجين كدوال top-level عشان
/// يتعمل لهم اختبار wiring مباشر بدل ما نركّب PosHeader كله.
@visibleForTesting
Widget buildPosNotificationBellGuarded() => const PermissionGuard(
      permission: PermissionCodes.posNotifications,
      fallback: SizedBox.shrink(),
      child: PosNotificationBell(),
    );

@visibleForTesting
Widget buildPosLowStockIndicatorGuarded() => const PermissionGuard(
      permission: PermissionCodes.posLowStockAlert,
      fallback: SizedBox.shrink(),
      child: PosLowStockIndicator(),
    );

class PosHeader extends ConsumerWidget {
  final bool showBackButton;
  final String? tableName;
  final int? tableId;

  final VoidCallback onShowOffers;
  final VoidCallback onShowDelivery;
  final VoidCallback onShowHeldOrders;
  final VoidCallback onHoldOrder;
  final VoidCallback? onAdminAccess;
  final VoidCallback? onCashierClosing;
  // Cart action buttons (moved from cart header)
  final VoidCallback? onViewReturns;
  final VoidCallback? onExchange;
  final VoidCallback? onQuickReturn;

  const PosHeader({
    super.key,
    required this.showBackButton,
    this.tableName,
    this.tableId,
    required this.onShowOffers,
    required this.onShowDelivery,
    required this.onShowHeldOrders,
    required this.onHoldOrder,
    this.onAdminAccess,
    this.onCashierClosing,
    this.onViewReturns,
    this.onExchange,
    this.onQuickReturn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posState = ref.watch(posControllerProvider);
    final cartState = ref.watch(cartControllerProvider);
    final isBooking = posState.isBooking;
    final strategy = posState.industryMode.strategy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: isBooking
              ? [AppColors.booking, AppColors.bookingDark]
              : [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              icon: const Icon(
                PhosphorIconsBold.arrowRight,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            ),

          // App Logo/Icon & Title Area
          _buildAppInfo(posState, isBooking),

          const SizedBox(width: 14),

          // Status Indicators (Scale, Cloud Sync)
          PosStatusIndicators(showScaleIndicator: strategy.showScaleIndicator),

          const Spacer(),

          // Action Buttons Section
          _buildActions(context, ref, posState, cartState, strategy),

          // Notification & Alerts
          buildPosNotificationBellGuarded(),
          buildPosLowStockIndicatorGuarded(),

          // Cashier Shift Closing
          if (onCashierClosing != null) _buildShiftCloseButton(),
        ],
      ),
    );
  }

  Widget _buildAppInfo(PosState posState, bool isBooking) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            PhosphorIconsBold.storefront,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tableName != null
                  ? tr('طاولة: {tableName}', {'tableName': tableName})
                  : (posState.industryMode == IndustryMode.restaurant
                        ? tr('الصالات والطاولات')
                        : (isBooking ? tr('حجز مسبق') : tr('البيع السريع'))),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            if (isBooking)
              Text(
                tr('وضعية الحجز نشطة'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    PosState posState,
    CartState cartState,
    IndustryModeStrategy strategy,
  ) {
    final showOffers = ref.watch(showOffersButtonProvider).value ?? true;
    final showKeyboard = ref.watch(showKeyboardButtonProvider).value ?? true;
    final showDelivery = ref.watch(showDeliveryButtonProvider).value ?? true;
    final showReturns = ref.watch(showReturnButtonInPOSProvider).value ?? true;
    final showHold = ref.watch(showHoldButtonInPOSProvider).value ?? true;
    final showExchange = ref.watch(showExchangeButtonInPOSProvider).value ?? true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Restaurant Specific: Select Table
        if (strategy.showTableSelection &&
            tableId == null)
          PermissionGuard(
            permission: PermissionCodes.posTableSelect,
            allowManagerOverride: true,
            actionName: tr('اختيار طاولة'),
            child: PosHeaderButton(
              icon: PhosphorIconsBold.table,
              label: tr('اختيار طاولة'),
              onTap: () => Navigator.pop(context),
              color: AppColors.warning,
            ),
          ),


        // Grid toggle button removed per Issue 9


        // Booking Button
        if (!strategy.showBarcodeInput)
          PermissionGuard(
            permission: PermissionCodes.posBooking,
            allowManagerOverride: true,
            actionName: tr('حجز مسبق'),
            child: PosHeaderButton(
              icon: PhosphorIconsBold.calendarCheck,
              label: posState.isBooking ? tr('إلغاء الحجز') : tr('حجز مسبق'),
              onTap: () => ref
                  .read(posControllerProvider.notifier)
                  .toggleBooking(!posState.isBooking),
              color: posState.isBooking ? AppColors.warning : Colors.white24,
            ),
          ),

        const SizedBox(width: 8),

        // Offers Button
        if (showOffers)
          PermissionGuard(
          permission: PermissionCodes.posOffers,
          allowManagerOverride: true,
          actionName: tr('عرض العروض'),
          child: PosHeaderButton(
            icon: PhosphorIconsBold.tag,
            label: tr('العروض'),
            onTap: onShowOffers,
          ),
        ),

        const SizedBox(width: 8),

        // Delivery Button
        if (showDelivery && (strategy.showDeliveryOptions || tableId != null))
          PermissionGuard(
            permission: PermissionCodes.posDelivery,
            allowManagerOverride: true,
            actionName: tr('توصيل'),
            child: PosHeaderButton(
              icon: PhosphorIconsBold.moped,
              label: tr('توصيل'),
              onTap: onShowDelivery,
              color: cartState.deliveryStatus != null ? AppColors.info : null,
            ),
          ),

        const SizedBox(width: 8),

        // Table Specific Buttons
        if (tableId != null) ...[
          PermissionGuard(
            permission: PermissionCodes.posHoldOrder,
            allowManagerOverride: true,
            actionName: tr('تعليق السلة'),
            child: PosHeaderButton(
              icon: PhosphorIconsBold.pause,
              label: tr('تعليق السلة'),
              onTap: () async {
                await ref.read(cartControllerProvider.notifier).holdOrder();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
          const SizedBox(width: 8),
          PermissionGuard(
            permission: PermissionCodes.posTableBill,
            allowManagerOverride: true,
            actionName: tr('طلب الحساب'),
            child: PosHeaderButton(
              icon: PhosphorIconsBold.money,
              label: tr('طلب الحساب'),
              onTap: () async {
                final confirmed = await _confirmAction(
                  context,
                  tr('هل تريد طلب الحساب لهذه الطاولة؟'),
                );
                if (confirmed) {
                  await ref
                      .read(posControllerProvider.notifier)
                      .requestTableBill();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
        ],

        // Keyboard Button
        if (showKeyboard)
          PermissionGuard(
          permission: PermissionCodes.posKeyboard,
          allowManagerOverride: true,
          actionName: tr('لوحة المفاتيح'),
          child: PosHeaderButton(
            icon: PhosphorIconsBold.keyboard,
            label: tr('لوحة المفاتيح'),
            onTap: _openOnScreenKeyboard,
          ),
        ),

        const SizedBox(width: 8),

        // ── Cart action buttons (moved from cart header) ──
        if (tableId == null) ...[
          // مرتجعات button
          if (showReturns && onViewReturns != null)
            PermissionGuard(
              permission: PermissionCodes.posReturn,
              allowManagerOverride: true,
              actionName: tr('مرتجعات'),
              child: PosHeaderButton(
                icon: PhosphorIconsBold.arrowUUpLeft,
                label: tr('مرتجعات'),
                onTap: onViewReturns!,
                color: AppColors.error.withValues(alpha: 0.8),
              ),
            ),

          const SizedBox(width: 4),

          // المعلقة button
          if (showHold)
            PermissionGuard(
              permission: PermissionCodes.posHoldOrder,
              allowManagerOverride: true,
              actionName: tr('الطلبات المعلقة'),
              child: PosHeaderButton(
                icon: PhosphorIconsBold.clipboardText,
                label: tr('المعلقة'),
                onTap: onShowHeldOrders,
                color: AppColors.warning,
              ),
            ),

          if (showHold) const SizedBox(width: 4),

          // تعليق button
          if (showHold)
            PermissionGuard(
              permission: PermissionCodes.posHoldOrder,
              allowManagerOverride: true,
              actionName: tr('تعليق فاتورة'),
              child: PosHeaderButton(
                icon: PhosphorIconsBold.pause,
                label: tr('تعليق'),
                onTap: onHoldOrder,
                color: const Color(0xFF7E57C2),
              ),
            ),

          const SizedBox(width: 4),

          // استبدال button
          if (showExchange && onExchange != null)
            PermissionGuard(
              permission: PermissionCodes.posExchange,
              allowManagerOverride: true,
              actionName: tr('استبدال'),
              child: PosHeaderButton(
                icon: PhosphorIconsBold.arrowsLeftRight,
                label: tr('استبدال'),
                onTap: onExchange!,
                color: AppColors.info,
              ),
            ),

          const SizedBox(width: 4),

          // مرتجع button
          if (onQuickReturn != null)
            PermissionGuard(
              permission: PermissionCodes.posReturn,
              allowManagerOverride: true,
              actionName: tr('مرتجع'),
              child: PosHeaderButton(
                icon: PhosphorIconsBold.arrowUUpLeft,
                label: tr('مرتجع'),
                onTap: onQuickReturn!,
                color: AppColors.error,
              ),
            ),

          const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildShiftCloseButton() {
    return PermissionGuard(
      permission: PermissionCodes.posShiftClose,
      allowManagerOverride: true,
      actionName: tr('إغلاق الوردية'),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error, width: 2),
          ),
          child: TextButton.icon(
            onPressed: onCashierClosing,
            icon: const Icon(
              PhosphorIconsBold.signOut,
              color: AppColors.error,
              size: 18,
            ),
            label:  Text(
              tr('إغلاق'),
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.error.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmAction(BuildContext context, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title:  Text(tr('تأكيد')),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child:  Text(tr('إلغاء')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child:  Text(tr('تأكيد')),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _openOnScreenKeyboard() {
    if (Platform.isWindows) {
      try {
        Process.run('cmd', ['/c', 'start', 'osk.exe']);
      } catch (e) {
        try {
          Process.run('cmd', [
            '/c',
            'start',
            '',
            'C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe',
          ]);
        } catch (_) {}
      }
    }
  }
}

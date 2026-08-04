import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/cart_view.dart';
import '../providers/pos_controller.dart';
import '../providers/cart_controller.dart';
import '../../../data/providers/providers.dart';
import '../../../services/cash_drawer_service.dart';

class PosCartPanel extends ConsumerWidget {
  final PosState posState;
  final VoidCallback onCheckout;
  final VoidCallback onClearCart;
  final Function(int) onEditItem;
  final VoidCallback onVReturns;
  final VoidCallback onHoldOrder;
  final VoidCallback onShowHeldOrders;
  final Future<String> Function() getDrawerPrinterName;
  final VoidCallback onSave;
  final VoidCallback onSaveQuotation;
  final VoidCallback onSaveAndPrint;

  final VoidCallback onPreviousInvoices;
  final VoidCallback onExpense;
  final VoidCallback onDeletedItems;

  const PosCartPanel({
    super.key,
    required this.posState,
    required this.onCheckout,
    required this.onClearCart,
    required this.onEditItem,
    required this.onVReturns,
    required this.onHoldOrder,
    required this.onShowHeldOrders,
    required this.getDrawerPrinterName,
    required this.onSave,
    required this.onSaveQuotation,
    required this.onSaveAndPrint,

    required this.onPreviousInvoices,
    required this.onExpense,
    required this.onDeletedItems,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      child: CartView(
        onCheckout: onCheckout,
        onClearCart: onClearCart,
        onEditItem: onEditItem,
        // ⛔ زر «استبدال» **مش موصول عن قصد** — الزر بيتعرض فقط لما
        //    `onExchange != null` (`pos_header.dart:366`). «وضع الاستبدال»
        //    كان بيخزّن كميات سالبة فيقلب اتجاه المخزون. البديل الصح تحت:
        //    «مرتجع سريع» (مستند مرتجع بكميات موجبة) ثم بيعة جديدة —
        //    وده بالظبط نفس المستندين اللي بينتجهم الحل الصحيح.
        onQuickReturn: () =>
            ref.read(cartControllerProvider.notifier).convertToQuickReturn(),
        onViewReturns: onVReturns,
        onHoldOrder: onHoldOrder,
        onShowHeldOrders: onShowHeldOrders,
        onOpenDrawer: () async {
          final printerName = await getDrawerPrinterName();
          debugPrint('[DRAWER] Opening drawer on printer: $printerName');
          final result = await CashDrawerService().openDrawer(printerName: printerName);
          debugPrint('[DRAWER] Result: $result');

          // Log via ActivityLogger for consistent audit trail
          final user = ref.read(authProvider).user;
          final logger = ref.read(activityLoggerProvider);
          await logger.logCashDrawerOpen(
            user?.id ?? 0,
            user?.displayName ?? 'مستخدم',
          );
        },
        onSave: onSave,
        onSaveQuotation: onSaveQuotation,
        onSaveAndPrint: onSaveAndPrint,

        onPreviousInvoices: onPreviousInvoices,
        onExpense: onExpense,
        onDeletedItems: onDeletedItems,
      ),
    );
  }
}

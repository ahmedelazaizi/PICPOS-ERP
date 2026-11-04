import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../../data/providers/providers.dart';
import '../../../services/printing/posted_sales_return_print.dart';
import '../../widgets/permission_guard.dart';

/// أزرارُ الطباعة في حوار تفاصيل فاتورة البيع — **مستندان لا زرٌّ واحد**.
///
/// كان في الحوار زرُّ «طباعة» وحيد، فإذا كانت الفاتورةُ مرتجَعةً (‏SINV-7 في
/// الجولة الحيّة 2026-11-04) طبع الفاتورةَ الأصليّة وظنّه المستخدمُ إيصالَ
/// المرتجع. فصار:
///
/// * «طباعة الفاتورة» — دائماً، بقالب `sales_invoice` المحسوم ([onPrintInvoice]).
/// * «طباعة المرتجع» — حين يكون للفاتورة مرتجعٌ مرحَّل ([returnedAmount] > 0):
///   إيصالُ `sales_return` ببنوده المرتجعة ومبلغه المسترد، خلف صلاحية
///   `sales_return_print` نفسِها التي تحرس زرَّ السجلّ.
class SalesInvoicePrintActions extends ConsumerWidget {
  const SalesInvoicePrintActions({
    super.key,
    required this.invoice,
    required this.returnedAmount,
    required this.onPrintInvoice,
  });

  final InvoiceEntity invoice;

  /// ما رُدَّ عن الفاتورة (‏`SalesInvoicesState.returnedAmounts`) — صفرٌ يُخفي
  /// زرَّ المرتجع.
  final double returnedAmount;
  final VoidCallback onPrintInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          key: const Key('sales_invoice_print_invoice'),
          onPressed: onPrintInvoice,
          icon: const Icon(PhosphorIconsBold.printer, size: 16),
          label: Text(tr('طباعة الفاتورة')),
        ),
        if (returnedAmount > 0)
          TextButton.icon(
            key: const Key('sales_invoice_print_return'),
            onPressed: () => _printReturn(context, ref),
            icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16),
            label: Text(tr('طباعة المرتجع')),
          ),
      ],
    );
  }

  Future<void> _printReturn(BuildContext context, WidgetRef ref) async {
    if (!await ensurePermission(ref, context, PermissionCodes.salesReturnPrint,
        actionName: tr('طباعة المرتجع'))) {
      return;
    }
    try {
      final outcome = await printPostedSalesReturn(
        db: ref.read(databaseProvider),
        returns: ref.read(returnsRepositoryProvider),
        products: ref.read(productRepositoryProvider),
        originalInvoiceId: invoice.id!,
        returnTotal: returnedAmount,
        employeeName: ref.read(authProvider).user?.displayName,
      );
      if (!context.mounted) return;
      final args = {'invoiceNumber': invoice.invoiceNumber};
      AppToast.show(
        context,
        switch (outcome) {
          PostedReturnPrintOutcome.printed =>
            tr('تم طباعة إيصال مرتجع فاتورة {invoiceNumber}', args),
          PostedReturnPrintOutcome.cancelled =>
            tr('أُلغيت طباعة إيصال مرتجع فاتورة {invoiceNumber}', args),
          PostedReturnPrintOutcome.noReturnData =>
            tr('لا مرتجعَ مرحَّلاً لهذه الفاتورة'),
        },
        type: outcome == PostedReturnPrintOutcome.printed
            ? ToastType.success
            : ToastType.warning,
      );
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
  }
}

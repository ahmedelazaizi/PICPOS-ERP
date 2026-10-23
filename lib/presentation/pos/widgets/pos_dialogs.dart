import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/scale_service.dart';
import '../../widgets/searchable_dropdown.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';

import '../../../domain/entities/product_entity.dart';

/// Collection of POS-related dialogs extracted for maintainability
///
/// Usage:
/// ```dart
/// PosDialogs.showWeightInput(context, ref, product, onConfirm: (weight) { ... });
/// ```

part 'pos_payment_dialogs.dart';
part 'pos_dialog_models.dart';
class PosDialogs {
  PosDialogs._();

  /// Show weight input dialog for products sold by weight.
  ///
  /// If the scale is connected, stable, and reports a positive weight,
  /// the weight is returned immediately without showing a dialog.
  /// Otherwise the manual weight-entry dialog is displayed.
  static Future<double?> showWeightInput(
    BuildContext context,
    WidgetRef ref,
    ProductEntity product,
  ) async {
    // Auto-add when scale weight is stable
    final scale = ScaleService.instance;
    if (scale.isConnected && scale.isStable && scale.lastWeight > 0) {
      return scale.lastWeight;
    }

    final weightController = TextEditingController();
    final pricePerUnit = product.pricePerUnit ?? product.salePrice;

    return showDialog<double>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: _WeightInputDialog(
          product: product,
          pricePerUnit: pricePerUnit,
          weightController: weightController,
        ),
      ),
    );
  }

  /// Show delivery options dialog
  static Future<DeliveryData?> showDeliveryOptions(
    BuildContext context,
    WidgetRef ref, {
    int? initialCompanyId,
    int? initialCompanyPartyId, // #Phase2
    int? initialCourierId,
    double initialFee = 0,
    String initialStatus = 'pending',
  }) async {
    return showDialog<DeliveryData>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final companies = ref.watch(allDeliveryPartiesProvider).value ?? [];
          final couriers = ref.watch(allCouriersProvider).value ?? [];

          return _DeliveryOptionsDialog(
            companies: companies,
            couriers: couriers,
            initialCompanyId: initialCompanyId,
            initialCompanyPartyId: initialCompanyPartyId, // #Phase2
            initialCourierId: initialCourierId,
            initialFee: initialFee,
            initialStatus: initialStatus,
          );
        },
      ),
    );
  }

  static Future<CartItemEditData?> showEditCartItem(
    BuildContext context,
    String productName,
    double currentPrice,
    String? currentNote,
  ) async {
    final priceController = TextEditingController(
      text: currentPrice.toStringAsFixed(AppConstants.decimalPlaces),
    );
    final noteController = TextEditingController(text: currentNote ?? '');

    return showDialog<CartItemEditData>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(
                PhosphorIconsBold.pencilSimple,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: tr('السعر'),
                  prefixIcon: const Icon(PhosphorIconsBold.money),
                  suffixText: AppConstants.currencySymbolEn,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration:  InputDecoration(
                  labelText: tr('ملاحظة'),
                  prefixIcon: const Icon(PhosphorIconsBold.notepad),
                  hintText: tr('مثال: بدون سكر، إضافي...'),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, const CartItemEditData.delete()),
              child:  Text(tr('حذف')),
            ),
            FilledButton(
              onPressed: () {
                final newPrice = double.tryParse(priceController.text);
                final note = noteController.text.isEmpty
                    ? null
                    : noteController.text;
                Navigator.pop(ctx, CartItemEditData(price: newPrice, note: note));
              },
              child:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  /// Show print confirmation dialog after sale
  static Future<bool> showPrintConfirmation(
    BuildContext context, {
    required String invoiceNumber,
    required double total,
    bool isDelivery = false, // NEW: Check for delivery
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  PhosphorIconsBold.checkCircle,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
               Text(tr('تمت العملية بنجاح!')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('رقم الفاتورة: {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('الإجمالي: {p0} {p1}', {'p0': total.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                style: const TextStyle(fontSize: 16),
              ),
              if (isDelivery)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:  Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          PhosphorIconsBold.moped,
                          size: 16,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr('طلب توصيل - يرجى طباعة نسختين'),
                          style: const TextStyle(fontSize: 12, color: AppColors.info),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
               Text(tr('هل تريد طباعة الإيصال؟')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text(tr('لا')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(PhosphorIconsBold.printer),
              label:  Text(tr('طباعة')),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  /// Show payment dialog with Split Payment support
  ///
  /// [allowedMethods] restricts which method chips are offered. Pass `null`
  /// (the default) for every method — that is what the UralCash till does, so
  /// its dialog is unchanged. The PicPos till passes the cashier's actual
  /// payment permissions, because after the PicPos payment panel lost its
  /// method buttons this dialog became the ONLY place a method is chosen, and
  /// the `PermissionGuard`s that used to wrap those buttons had to move here.
  static Future<PaymentResult?> showPaymentDialog(
    BuildContext context, {
    required double totalAmount,
    String initialMethod = 'cash',
    Set<String>? allowedMethods,
  }) async {
    return showDialog<PaymentResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: _PaymentDialog(
          totalAmount: totalAmount,
          initialMethod: initialMethod,
          allowedMethods: allowedMethods,
        ),
      ),
    );
  }

  /// Show dialog to hold (suspend) current order
  static Future<String?> showHoldOrderDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _HoldOrderDialog(),
      ),
    );
  }
}


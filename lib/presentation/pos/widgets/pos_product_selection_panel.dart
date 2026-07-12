import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/pos_barcode_input.dart';
import '../widgets/pos_scale_input.dart';
import '../widgets/product_grid.dart';
import '../widgets/product_pricing_inquiry.dart';
import '../../widgets/permission_guard.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../data/providers/providers.dart';

class PosProductSelectionPanel extends ConsumerWidget {
  final TextEditingController barcodeController;
  final FocusNode barcodeFocus;
  final Function(String) onSearchBarcode;
  final Function(ProductEntity) onProductTap;

  const PosProductSelectionPanel({
    super.key,
    required this.barcodeController,
    required this.barcodeFocus,
    required this.onSearchBarcode,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Barcode input - controlled by settings
          if (ref.watch(showBarcodeInPOSProvider).asData?.value ?? true)
            PermissionGuard(
              permission: PermissionCodes.posSearch,
              allowManagerOverride: true,
              actionName: 'البحث بالباركود',
              child: PosBarcodeInput(
                controller: barcodeController,
                focusNode: barcodeFocus,
                onSubmitted: onSearchBarcode,
              ),
            ),

          // Pricing inquiry — under barcode input
          if (ref.watch(showPricingInquiryInPOSProvider).asData?.value ?? true)
            const ProductPricingInquiry(),

          // Scale input - only shows when scale is connected
          const PosScaleInput(),

          Expanded(
            child: PermissionGuard(
              permission: PermissionCodes.posAddProduct,
              allowManagerOverride: true,
              actionName: 'إضافة صنف للسلة',
              child: ProductGrid(onProductTap: onProductTap),
            ),
          ),
        ],
      ),
    );
  }
}

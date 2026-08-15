import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/pos_layout_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/pos_barcode_input.dart';
import '../widgets/pos_product_search_field.dart';
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

  /// وجهةُ التخطيط — §٢.
  ///
  /// تُمرَّر صراحةً كي يقيسها الاختبارُ تحت النكهة الافتراضية: `Brand.isPicPos`
  /// ثابتُ ترجمة، وفرعٌ مطويٌّ خلفه لا تراه البوابة. و`null` تعني «وجهةَ
  /// العلامة المبنيّة» وهو ما يمرّره التطبيق.
  final PosLayoutPolicy? layout;

  const PosProductSelectionPanel({
    super.key,
    required this.barcodeController,
    required this.barcodeFocus,
    required this.onSearchBarcode,
    required this.onProductTap,
    this.layout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = this.layout ?? PosLayoutPolicy.current;
    final showBarcode = ref.watch(showBarcodeInPOSProvider).asData?.value ?? true;
    final showSearch = ref.watch(showSearchInPOSProvider).value ?? true;
    final besideBarcode = layout.searchBesideBarcode && showSearch;

    final barcodeInput = PermissionGuard(
      permission: PermissionCodes.posSearch,
      allowManagerOverride: true,
      actionName: 'البحث بالباركود',
      child: PosBarcodeInput(
        controller: barcodeController,
        focusNode: barcodeFocus,
        onSubmitted: onSearchBarcode,
        contentPaddingV: layout.barcodeContentPaddingV,
        rowPaddingV: layout.barcodeRowPaddingV,
      ),
    );

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Barcode input - controlled by settings
          if (showBarcode && !besideBarcode) barcodeInput,

          // §٢ — الباركودُ والبحثُ في صفٍّ واحد (‏PicPos وحدَه).
          //
          // ‏`PosBarcodeInput` يحمل إطارَه بنفسه (خلفيةٌ بيضاءُ وحدٌّ سفليٌّ
          // وحشوٌ ١٦/١٢)، فالبحثُ يُلبَس **نفسَ** الإطار بدل نزعه من الباركود:
          // يبدو النصفان شريطاً واحداً متّصلاً، ولا يُمسّ ودجتٌ مشتركٌ لأجل
          // تغييرٍ بصريٍّ في فوركٍ واحد.
          if (besideBarcode)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showBarcode)
                  Expanded(flex: layout.barcodeFlex, child: barcodeInput),
                Expanded(
                  flex: layout.searchFlex,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: layout.barcodeRowPaddingV,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                    ),
                    child: PosProductSearchField(
                      height: layout.searchFieldHeight,
                    ),
                  ),
                ),
              ],
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
              // ‏`false` هنا تمنع ظهورَ حقلَي بحثٍ يكتبان في نفس الحالة.
              child: ProductGrid(
                onProductTap: onProductTap,
                showInlineSearch: !besideBarcode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../picpos_shell/picpos_surface.dart';

/// Product pricing inquiry button — A large button below POS barcode input
/// which opens a spacious Popup Menu (Dialog) to scan and edit item prices.
class ProductPricingInquiry extends ConsumerWidget {
  const ProductPricingInquiry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      color: context.picposCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: () async {
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => const _ProductPricingDialog(),
          );
          // Return focus to main scanner if we are in POS context
          if (context.mounted) {
            FocusScope.of(context).unfocus();
            // We use a small delay to ensure the dialog is fully closed
            Future.delayed(const Duration(milliseconds: 100), () {
              // This is a generic way to find the main barcode focus in the POS screen
              // without tight coupling to the screen implementation
              FocusManager.instance.primaryFocus?.unfocus();
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: context.picposField,
          foregroundColor: AppColors.primary,
          elevation: 0,
          side: const BorderSide(color: AppColors.primary, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: const Icon(PhosphorIconsBold.scan, size: 20),
        label: const Text(
          'تسعير الأصناف (إستعلام)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ProductPricingDialog extends ConsumerStatefulWidget {
  const _ProductPricingDialog();

  @override
  ConsumerState<_ProductPricingDialog> createState() => _ProductPricingDialogState();
}

class _ProductPricingDialogState extends ConsumerState<_ProductPricingDialog> {
  /// سقفُ نتائج البحث بالاسم.
  ///
  /// كان `1` — وهو جذرُ بلاغ المالك: البحثُ بالاسم كان يجلب واحداً ويعرضه
  /// بلا أن يعلم المستخدمُ أن هناك غيرَه. والرقمُ سقفُ عرضٍ لا سقفُ مطابقة:
  /// من يبحث بكلمةٍ عامّةٍ يضيّقها، ولائحةٌ بلا حدٍّ تُبطئ الحوارَ في قاعدةٍ
  /// كبيرة.
  static const int _nameSearchLimit = 25;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  ProductEntity? _foundProduct;

  /// مطابقاتُ البحث بالاسم حين تكون أكثرَ من واحدة — تُعرض ليختار المستخدم.
  /// وتُفرَّغ فورَ الاختيار فلا تبقى القائمةُ فوق التفاصيل.
  List<ProductEntity> _candidates = const [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Auto focus the search field after dialog animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _searchFocusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _foundProduct = null;
          _candidates = const [];
          _isSearching = false;
        });
      }
      return;
    }
    setState(() => _isSearching = true);

    final productRepo = ref.read(productRepositoryProvider);

    // الباركودُ ثم الكودُ يبقيان **مطابقةً واحدةً مباشرة**: هذا مسحٌ سريعٌ
    // بقارئ، وإقحامُ قائمةٍ بينه وبين النتيجة يبطّئ الاستعمالَ الأساسيَّ
    // للحوار.
    var product = await productRepo.getProductByBarcode(query);
    product ??= await productRepo.getProductByCode(query);

    var candidates = const <ProductEntity>[];
    if (product == null) {
      final results =
          await productRepo.getProducts(query: query, limit: _nameSearchLimit);
      if (results.length == 1) {
        // اختيارٌ من عنصرٍ واحدٍ ليس اختياراً — والقائمةُ هنا خطوةٌ زائدة.
        product = results.first;
      } else {
        candidates = results;
      }
    }

    if (mounted) {
      setState(() {
        _foundProduct = product;
        _candidates = candidates;
        _isSearching = false;
      });
      // تحديدُ النصّ كلِّه ليمسحه المسحُ التالي بلا تفريغٍ يدويّ.
      //
      // ⚠️ ومشروطٌ بغياب القائمة عن قصد: لو حُدّد والقائمةُ معروضةٌ لابتلع
      // أوّلُ حرفٍ يكتبه المستخدمُ — أو أوّلُ مسحةِ قارئ — اختيارَه قبل أن
      // يختار.
      if (candidates.isEmpty) {
        _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
      }
    }
  }

  void _selectCandidate(ProductEntity product) {
    setState(() {
      _foundProduct = product;
      _candidates = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine responsive width constraints for the dialog
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 800 ? 600.0 : screenWidth * 0.9;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        titlePadding: const EdgeInsets.all(16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(PhosphorIconsBold.scan, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('استعلام تسعير المنتجات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(PhosphorIconsBold.x, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Searching Input Layer
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الباركود ثم اضغط Enter...',
                  hintStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                  prefixIcon: const Icon(PhosphorIconsBold.barcode, size: 24, color: AppColors.primary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(PhosphorIconsBold.xCircle, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _foundProduct = null;
                              _candidates = const [];
                            });
                            _searchFocusNode.requestFocus();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.picposHairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: context.picposField,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onSubmitted: _search,
                onChanged: (val) {
                  // Force rebuild to show/hide clear icon
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),

              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),

              if (_candidates.isNotEmpty && !_isSearching) _buildCandidateList(),

              if (_foundProduct == null &&
                  _candidates.isEmpty &&
                  _searchController.text.isNotEmpty &&
                  !_isSearching)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsBold.warningCircle, color: AppColors.error),
                      SizedBox(width: 8),
                      Text(
                        'لم يتم العثور على منتج يطابق عملية البحث',
                        style: TextStyle(color: AppColors.error, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

              if (_foundProduct != null && !_isSearching)
                _buildProductDetailsAndPricingPanel(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// قائمةُ المطابقات حين يرجع البحثُ بالاسم أكثرَ من صنف.
  ///
  /// محدودةُ الارتفاع لأنها داخل `Column` في `AlertDialog`: بلا حدٍّ يفيض
  /// الحوارُ عن الشاشة على قوائمَ طويلة.
  Widget _buildCandidateList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.listMagnifyingGlass,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'اختر الصنفَ المطلوب (${_candidates.length})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _candidates.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = _candidates[index];
                return ListTile(
                  dense: true,
                  onTap: () => _selectCandidate(product),
                  title: Text(
                    product.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    product.code,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                  trailing: Text(
                    '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductDetailsAndPricingPanel() {
    final product = _foundProduct!;
    final taxRate = product.taxRate;
    final originalPriceWithTax = product.salePrice * (1 + taxRate / 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Basic Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.picposCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.picposHairline),
                ),
                child: const Center(child: Icon(PhosphorIconsBold.package, color: AppColors.primary, size: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (product.barcode != null && product.barcode!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.picposCard,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: context.picposHairline),
                            ),
                            child: Row(
                              children: [
                                const Icon(PhosphorIconsBold.barcode, size: 12, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  product.barcode!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (taxRate > 0)
                          Expanded(
                            child: Text(
                              'السعر شامل الضريبة: ${originalPriceWithTax.toStringAsFixed(AppConstants.decimalPlaces)} (${taxRate.toStringAsFixed(0)}%)',
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Divider(height: 32),

          // Price Display Section (read-only)
          Row(
            children: [
              const Text(
                'سعر البيع:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 12),
              Text(
                '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

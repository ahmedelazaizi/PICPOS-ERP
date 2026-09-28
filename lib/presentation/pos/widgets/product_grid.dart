import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/config/brand.dart';
import '../../../core/config/pos_layout_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../providers/pos_controller.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/enhanced_components.dart';
import '../../../domain/entities/product_entity.dart';
import 'product_card.dart';
import 'product_card_shimmer.dart';
import '../../widgets/category_icon_picker.dart';
import '../../../core/utils/arabic_utils.dart';
import '../../picpos_shell/picpos_surface.dart';

/// زرار طيّ شبكة المنتجات (ملء الشاشة بالسلة) — مستخرج كودجت مستقل عن
/// `_ProductGridState` عشان يتعمله اختبار widget من غير الشاشة كلها.
///
/// `fallback` مش `allowManagerOverride`: نفس سبب الزرار المقابل في
/// `cart_view.dart` (`buildPosGridToggleButton`) — طيّ/فتح الشبكة عرض واجهة
/// بحت، مش كتابة بيانات.
@visibleForTesting
Widget buildPosGridToggleActionButton({required VoidCallback onToggle}) {
  return PermissionGuard(
    permission: PermissionCodes.posGridToggle,
    fallback: const SizedBox.shrink(),
    child: Tooltip(
      message: 'طي القائمة / ملء الشاشة',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2), width: 1),
          ),
          child: const Icon(PhosphorIconsBold.caretDoubleLeft,
              color: AppColors.primary, size: 20),
        ),
      ),
    ),
  );
}

/// Product grid widget for POS
///
/// Displays products in a grid with category filtering, search,
/// and drag-and-drop reordering (long-press a product card to start).
class ProductGrid extends ConsumerStatefulWidget {
  final Function(ProductEntity product) onProductTap;

  /// 4.1: Configurable grid columns (1-8), defaults to 4
  final int gridColumns;

  /// هل تُرسم خانةُ البحث داخلَ رأس الشبكة؟
  ///
  /// §٢ — حين يرفعها `PosProductSelectionPanel` إلى صفّ الباركود
  /// (‏`PosLayoutPolicy.searchBesideBarcode`) تُطفأ هنا، وإلا ظهر حقلا بحثٍ
  /// اثنان يكتبان في نفس الحالة. والافتراضيُّ `true` فلا يتغيّر شيءٌ لمن لا
  /// يمرّرها.
  final bool showInlineSearch;

  const ProductGrid({
    super.key,
    required this.onProductTap,
    this.gridColumns = 8, // عرض 8 أصناف في الصف
    this.showInlineSearch = true,
  });

  @override
  ConsumerState<ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends ConsumerState<ProductGrid> {
  bool _isReorderMode = false;
  List<ProductEntity>? _reorderableProducts;
  List<ProductEntity> _currentLoadedProducts = [];
  bool _isLoading = true;
  String? _loadError;

  // Cached category filter sets
  Set<int> _lockedCategoryIds = {};
  Set<int> _excludedCategoryIds = {};

  // Cluster 023 / Issue 9 — multi-barcode lookup for in-grid search.
  // The grid filters an in-memory product list, so a scanned barcode that
  // lives on `product_barcodes` (packaging-unit / alternate UPCs) wouldn't
  // match the primary `barcode` column. Cache the table once per state
  // lifetime so the filter predicate stays synchronous.
  Map<String, int> _barcodeToProductId = {};

  /// ── بلاغُ المالك 2026-08-15 ────────────────────────────────────────────
  /// «عند البحث عن المنتج لا يمكن حذف البحث حتى بعد اختيار المنتج.»
  ///
  /// والجذرُ مقيس: حقلُ البحث كان **بلا `TextEditingController` إطلاقاً** —
  /// `onChanged: controller.setSearchQuery` وحدَه. فالنصُّ يعيش في الودجت
  /// الداخليّ ولا يملك أحدٌ تفريغَه برمجياً: لا زرَّ مسحٍ يعمل، ولا اختيارُ
  /// منتجٍ يُنظّفه. المتحكّمُ يُصفَّر والحقلُ يبقى مكتوباً — فيبدو البحثُ
  /// «عالقاً».
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBarcodeIndex();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// يُفرغ خانةَ البحث والمتحكّمَ معاً.
  ///
  /// ⚠️ الاثنان معاً لا أحدُهما: تفريغُ المتحكّم وحدَه يترك النصَّ معروضاً
  /// (وهو العطبُ الأصليّ)، وتفريغُ الحقل وحدَه يترك الشبكةَ مرشَّحة.
  void _clearSearch() {
    _searchController.clear();
    ref.read(posControllerProvider.notifier).setSearchQuery('');
  }

  Future<void> _loadBarcodeIndex() async {
    try {
      final repo = ref.read(productRepositoryProvider);
      final pairs = await repo.getAllProductBarcodes();
      if (!mounted) return;
      setState(() {
        _barcodeToProductId = {
          for (final pair in pairs) pair.barcode.toLowerCase(): pair.productId,
        };
      });
    } catch (e) {
      // Best-effort — primary `barcode` column still works as fallback.
      debugPrint('[ProductGrid] failed to load barcode index: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Categories reactive watch (Branch-Scoped)
    final categoriesAsync = ref.watch(visibleCategoriesProvider);
    final categories = categoriesAsync.value ?? [];

    // 2. Spec 136 ISS-12 — watch the BOUNDED POS product stream (selected
    // category / search results), NOT the unbounded allProductsProvider. With
    // a 57978-row catalog the old watch took ~8s on entry and re-mapped the
    // whole catalog on every sale (blocking the post-sale readback ~7s). The
    // client-side _filterProducts below still runs (now on the small scoped
    // set) so the locked/excluded/type/warehouse rules are unchanged. Barcode
    // scan + cart use separate DB lookups and are unaffected.
    final searchQuery = ref.watch(
        posControllerProvider.select((s) => s.searchQuery));
    final selectedCategoryId = ref.watch(
        posControllerProvider.select((s) => s.selectedCategoryId));
    final productsAsync = ref.watch(posGridProductsProvider((
      search: searchQuery,
      selectedCategoryId: selectedCategoryId,
    )));
    
    // Update local cache if we have new data
    if (productsAsync.hasValue && productsAsync.value != null && productsAsync.value != _currentLoadedProducts) {
      _currentLoadedProducts = productsAsync.value!;
      _isLoading = false;
      _loadError = null;
    } else if (productsAsync.isLoading && _currentLoadedProducts.isEmpty) {
      _isLoading = true;
    } else if (productsAsync.hasError && _currentLoadedProducts.isEmpty) {
      _loadError = productsAsync.error?.toString();
      _isLoading = false;
    }

    // 3. Update filter sets when categories change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final locked = categories.where((c) => c.isLocked).map((c) => c.id).toSet();
      final excluded = categories.where((c) => c.isExcluded || !c.showInPos).map((c) => c.id).toSet();
      
      // Simple check to avoid unnecessary setStates
      if (_lockedCategoryIds.length != locked.length || _excludedCategoryIds.length != excluded.length) {
        setState(() {
          _lockedCategoryIds = locked;
          _excludedCategoryIds = excluded;
        });
      }
    });

    // 4. Default category selection (one-time upon data arrival)
    if (categories.isNotEmpty && ref.read(posControllerProvider).selectedCategoryId == null) {
      final firstValid = categories.where((c) => !c.isLocked && !c.isExcluded && c.showInPos).firstOrNull 
          ?? categories.firstOrNull;
      if (firstValid != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(posControllerProvider.notifier).setCategoryFilter(firstValid.id);
        });
      }
    }

    // Spec 136 — do NOT watch the WHOLE pos state here. _filterProducts only
    // needs searchQuery + selectedCategoryId (already watched via select above),
    // and ProductCard does not depend on the cart. Watching the full state made
    // the entire grid rebuild on every cart change (every product tap), which
    // caused a brief flicker of a card on tap. Use read() for the notifier only.
    final posController = ref.read(posControllerProvider.notifier);

    // Issue 7: Active warehouse for product filtering
    final activeWhAsync = ref.watch(activeWarehouseIdProvider);
    final activeWarehouseId = activeWhAsync.asData?.value;

    return Column(
      children: [
        // Search bar
        _buildSearchBar(searchQuery, posController),

        // Products grid
        Expanded(
          child: _isLoading && _currentLoadedProducts.isEmpty
              ? _buildShimmerGrid()
              : _loadError != null && _currentLoadedProducts.isEmpty
                  ? Center(child: Text('خطأ: $_loadError'))
                  : () {
                      if (_isReorderMode && _reorderableProducts != null) {
                        return _buildReorderableGrid();
                      }
                      final filtered = _filterProducts(
                        _currentLoadedProducts,
                        searchQuery,
                        selectedCategoryId,
                        _lockedCategoryIds,
                        _excludedCategoryIds,
                        categories,
                        activeWarehouseId,
                      );
                      return _buildGrid(filtered);
                    }(),
        ),

        // Reorder mode banner
        if (_isReorderMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.warning.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.arrowsOutCardinal,
                  color: AppColors.warning,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'اسحب المنتجات لإعادة ترتيبها في أي مكان',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.check, size: 16),
                  label: const Text(
                    'حفظ الترتيب',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _saveReorder,
                ),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => setState(() {
                    _isReorderMode = false;
                    _reorderableProducts = null;
                  }),
                ),
              ],
            ),
          ),

      // Category filter at BOTTOM - only show unlocked categories (hide in reorder mode)
        if (!_isReorderMode)
          categories.isEmpty
            ? const SizedBox(height: 48)
            : _buildCategoryFilter(
                categories
                    .where((c) => !c.isLocked && !c.isExcluded && c.showInPos)
                    .toList(),
                selectedCategoryId,
                posController,
                ref,
              ),
      ],
    );
  }

  Widget _buildSearchBar(String query, PosController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline, width: 0.5)),
      ),
      child: Row(
        children: [
          // Layout Toggle Button (Premium)
          if (ref.watch(showProductLayoutToggleInPOSProvider).value ?? true)
            buildPosGridToggleActionButton(
              onToggle: () => controller.toggleGridCollapse(),
            ),
          // §٢ — `showInlineSearch: false` يعني أن اللوحةَ رفعت الحقلَ إلى
          // صفّ الباركود. و`Spacer` بديلُ `Expanded` المفقود كي يبقى زرُّ
          // إعادة الترتيب في طرف الصفّ لا ملتصقاً بزرّ التخطيط.
          if (!widget.showInlineSearch) const Spacer(),
          if (widget.showInlineSearch &&
              (ref.watch(showSearchInPOSProvider).value ?? true)) ...[
            const SizedBox(width: 12),
            Expanded(
              child: PermissionGuard(
                permission: PermissionCodes.posSearch,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.picposField,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.picposHairline.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    // ⚠️ بلا هذا السطر كان الحقلُ **غيرَ متحكَّمٍ به**: زرُّ
                    // المسح (×) أدناه يستدعي `setSearchQuery('')` فيمسح
                    // الحالةَ ويترك النصَّ معروضاً — فيبدو الزرُّ معطوباً،
                    // وهو بلاغُ المالك 2026-08-15 بالحرف.
                    controller: _searchController,
                    onChanged: controller.setSearchQuery,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'بحث عن منتج...',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        PhosphorIconsBold.magnifyingGlass,
                        size: 22,
                        color: AppColors.primary,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      isDense: true,
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                PhosphorIconsBold.xCircle,
                                size: 20,
                              ),
                              onPressed: _clearSearch,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (ref.watch(showProductSortInPOSProvider).value ?? true) ...[
            const SizedBox(width: 12),
            _buildActionButton(
              icon: _isReorderMode
                  ? PhosphorIconsBold.check
                  : PhosphorIconsBold.arrowsOutCardinal,
              onTap: () {
                if (_isReorderMode) {
                  _saveReorder();
                } else {
                  // Use cached loaded products filtered by selected category
                  final selectedCatId = ref.read(posControllerProvider).selectedCategoryId;
                  var activeProducts = _currentLoadedProducts
                      .where((p) => p.isActive)
                      .toList();
                  // Filter by selected category if one is selected
                  if (selectedCatId != null) {
                    activeProducts = activeProducts
                        .where((p) => p.categoryId == selectedCatId)
                        .toList();
                  }
                  if (activeProducts.isEmpty) {
                    return; // Safety: don't enter reorder with no data
                  }
                  setState(() {
                    _isReorderMode = true;
                    _reorderableProducts = List.from(activeProducts);
                  });
                }
              },
              tooltip: _isReorderMode ? 'حفظ الترتيب' : 'إعادة ترتيب المنتجات',
              color: _isReorderMode ? AppColors.success : AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(
    List<Category> categories,
    int? selectedId,
    PosController controller,
    WidgetRef ref,
  ) {
    // Read category display settings
    final catIconSize = ref.watch(posCategoryIconSizeProvider).asData?.value ?? 44.0;
    final catFontSize = ref.watch(posCategoryFontSizeProvider).asData?.value ?? 9.0;
    final catSpacing = ref.watch(posCategorySpacingProvider).asData?.value ?? 12.0;
    final catRunSpacing = ref.watch(posCategoryRunSpacingProvider).asData?.value ?? 8.0;
    final catLabelWidth = ref.watch(posCategoryLabelWidthProvider).asData?.value ?? 52.0;
    final catShape = ref.watch(posCategoryShapeProvider).asData?.value ?? 'circle';
    final catMaxHeight = ref.watch(posCategoryMaxHeightProvider).asData?.value ?? 200.0;

    // Convert categories to CategoryFilterItem with auto-icons
    final categoryItems = categories.map<CategoryFilterItem>((cat) {
      final category = cat;
      // Parse color from category
      Color? catColor;
      try {
        catColor = Color(int.parse(category.color.replaceFirst('#', '0xFF')));
      } catch (_) {
        catColor = null;
      }

      return CategoryFilterItem(
        id: category.id,
        name: category.name,
        icon: CategoryIconPicker.getIconData(category.iconName),
        color: catColor,
      );
    }).toList();

    return EnhancedCategoryFilter(
      categories: categoryItems,
      selectedId: selectedId,
      onSelect: controller.setCategoryFilter,
      showAllOption: false,
      iconSize: catIconSize,
      fontSize: catFontSize,
      spacing: catSpacing,
      runSpacing: catRunSpacing,
      labelWidth: catLabelWidth,
      iconShape: catShape,
      maxHeight: catMaxHeight,
      // بلاغُ المالك 2026-08-15: «نفس الأمر على نص ايقونات اسماء التصنيفات».
      // والوزنُ من السياسة لا رقماً هنا — فالفرعُ على العلامة يبقى في موضعٍ
      // واحدٍ مقيس.
      labelWeight: PosLayoutPolicy.current.categoryLabelWeight,
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: context.picposField.withValues(alpha: 0.5),
      highlightColor: AppColors.primary.withValues(alpha: 0.1),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.gridColumns.clamp(1, 10),
          childAspectRatio: 0.75,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: 18, // Show a reasonable number of shimmer cards
        itemBuilder: (_, _) => const ProductCardShimmer(),
      ),
    );
  }

  Widget _buildGrid(List<ProductEntity> products) {
    if (products.isEmpty) {
      return const EmptyStateWidget(
        icon: PhosphorIconsBold.package,
        message: 'لا توجد منتجات',
      );
    }

    // #3: Read product images toggle setting
    final showImages = ref.watch(showProductImagesProvider).asData?.value ?? true;
    final nameFontSize = ref.watch(productNameFontSizeProvider).asData?.value ?? 12.0;
    final priceFontSize = ref.watch(productPriceFontSizeProvider).asData?.value ?? 14.0;
    // Read grid display settings
    final gridCols = ref.watch(posGridColumnsProvider).asData?.value ?? 8;
    final gridSpacing = ref.watch(posGridSpacingProvider).asData?.value ?? 8.0;
    final gridAspect = ref.watch(posGridAspectRatioProvider).asData?.value ?? 0.75;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridCols.clamp(2, 12),
        childAspectRatio: showImages ? gridAspect : 1.0,
        crossAxisSpacing: gridSpacing,
        mainAxisSpacing: gridSpacing,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          key: ValueKey(product.id),
          product: product,
          // طلبُ المالك 2026-08-15: «عند البحث والاختيار تفريغُ خانة البحث
          // ليبدأ من جديد». الاختيارُ هو نهايةُ البحثة — وإبقاءُ النصّ يجبر
          // الكاشيرَ على مسحه يدوياً قبل كلّ صنف.
          onTap: () {
            widget.onProductTap(product);
            _clearSearch();
          },
          showImages: showImages,
          nameFontSize: nameFontSize,
          priceFontSize: priceFontSize,
          // The ONE place the brand is checked for the indicator scheme —
          // `ProductCard` itself stays brand-agnostic and testable.
          saleTypeDot: Brand.isPicPos,
          dimWhenOutOfStock: Brand.isPicPos,
        );
      },
    );
  }

  /// Build a reorderable grid using Wrap with DragTarget for individual item reordering
  Widget _buildReorderableGrid() {
    final products = _reorderableProducts ?? [];
    if (products.isEmpty) {
      return const EmptyStateWidget(
        icon: PhosphorIconsBold.package,
        message: 'لا توجد منتجات',
      );
    }

    final cols = widget.gridColumns.clamp(1, 10);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate item dimensions based on available width and columns
        final availableWidth = constraints.maxWidth - 24; // Padding (12 * 2)
        const spacing = 8.0;
        final itemWidth = (availableWidth - (cols - 1) * spacing) / cols;
        // Match the normal grid's aspect ratio (0.75 = width/height)
        final itemHeight = itemWidth / 0.75;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: products.asMap().entries.map((entry) {
              final index = entry.key;
              final product = entry.value;

              return DragTarget<int>(
                onWillAcceptWithDetails: (fromIndex) =>
                    fromIndex.data != index,
                onAcceptWithDetails: (fromIndex) {
                  setState(() {
                    final movedItem = products.removeAt(fromIndex.data);
                    products.insert(index, movedItem);
                  });
                },
                builder: (context, candidateData, rejectedData) {
                  return LongPressDraggable<int>(
                    data: index,
                    feedback: SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Material(
                        color: Colors.transparent,
                        child: Opacity(
                          opacity: 0.8,
                          child: ProductCard(
                          product: product,
                          onTap: () {},
                          saleTypeDot: Brand.isPicPos,
                          dimWhenOutOfStock: Brand.isPicPos,
                        ),
                        ),
                      ),
                    ),
                    childWhenDragging: SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Opacity(
                        opacity: 0.2,
                        child: ProductCard(
                          product: product,
                          onTap: () {},
                          saleTypeDot: Brand.isPicPos,
                          dimWhenOutOfStock: Brand.isPicPos,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Stack(
                        children: [
                          ProductCard(
                            product: product,
                            onTap: () {}, // Disable tap in reorder mode
                            // Reorder mode shows the SAME cards — matching the
                            // live grid's indicators keeps the drag preview
                            // honest about what the cashier will end up with.
                            saleTypeDot: Brand.isPicPos,
                            dimWhenOutOfStock: Brand.isPicPos,
                          ),
                          // Order badge
                          PositionedDirectional(
                            top: 4,
                            end: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Reorder overlay hint
                          if (candidateData.isNotEmpty)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.success,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.success.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Persist the new product order to the database
  Future<void> _saveReorder() async {
    final products = _reorderableProducts;
    if (products == null || products.isEmpty) return;

    final productRepo = ref.read(productRepositoryProvider);
    await productRepo.updateProductSortOrders(products.map((p) => p.id).toList());

    // Log activity
    try {
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? 'مستخدم',
        action: 'product_reorder',
        entityType: 'product',
        description: 'إعادة ترتيب ${products.length} منتج',
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isReorderMode = false;
        _reorderableProducts = null;
      });
      AppToast.show(
        context,
        'تم حفظ ترتيب المنتجات بنجاح',
        type: ToastType.success,
      );
    }
  }

  /// Filter products for POS display
  /// - Only active products
  /// - Exclude products in locked categories (unless product.isLocked=true which means exempted)
  /// - Filter by selected category and search query
  List<ProductEntity> _filterProducts(
    List<ProductEntity> products,
    String searchQuery,
    int? selectedCategoryId,
    Set<int> lockedCategoryIds,
    Set<int> excludedCategoryIds,
    List<Category> allCategories, [
    int? activeWarehouseId,
  ]) {
    final isSearching = searchQuery.isNotEmpty;

    // Cluster 027 / Task 3 (refined): pre-compute every product whose
    // name / code / primary barcode / secondary barcode matches the
    // query as a SUBSTRING. These rows bypass the warehouse + category
    // + raw-material/service guards below so the operator can always
    // find the product they typed regardless of where it's filed or
    // what type it is. We use the raw (un-normalized) lowercase query
    // for code/barcode comparisons so numeric input doesn't collide
    // with Arabic-letter normalization; the name match still uses the
    // Arabic-aware normalize so name search keeps working for diacritic
    // / alif variants.
    //
    // Raw materials and services are NOT excluded from the match set
    // here — when the operator explicitly types a code/barcode/name
    // for one, they want to find it (e.g. to price-check a raw
    // material that doubles as a sellable item). The default hide for
    // raw materials/services only applies when NOT searching.
    final searchMatchIds = <int>{};
    if (isSearching) {
      final raw = searchQuery.toLowerCase().trim();
      final normalizedQuery =
          ArabicUtils.normalize(searchQuery.toLowerCase());
      for (final p in products) {
        if (!p.isActive) continue;
        final bc = p.barcode?.toLowerCase() ?? '';
        if (bc.contains(raw) ||
            p.code.toLowerCase().contains(raw) ||
            ArabicUtils.normalize(p.name.toLowerCase())
                .contains(normalizedQuery)) {
          searchMatchIds.add(p.id);
        }
      }
      // Secondary barcodes (loaded async into _barcodeToProductId).
      _barcodeToProductId.forEach((bc, pid) {
        if (bc.contains(raw)) searchMatchIds.add(pid);
      });
    }

    // Pre-calculate matching category branch (if a category is selected)
    final matchingIds = <int>{};
    var selectedIsGeneral = false;
    if (selectedCategoryId != null) {
      matchingIds.add(selectedCategoryId);
      void addChildren(int parentId) {
        final children = allCategories.where((c) => (c).parentId == parentId);
        for (final child in children) {
          if (matchingIds.add(child.id)) {
            addChildren(child.id);
          }
        }
      }
      addChildren(selectedCategoryId);
      // Spec 150 BUG-3 — «عام» also matches every duplicate «عام» row (products
      // may be filed under a stray copy); NULL-category rows are folded in by
      // the scope re-filter below.
      selectedIsGeneral = allCategories
          .any((c) => c.id == selectedCategoryId && isGeneralCategory(c));
      if (selectedIsGeneral) {
        matchingIds
            .addAll(allCategories.where(isGeneralCategory).map((c) => c.id));
      }
    }
    // Note: We no longer return [] when selectedCategoryId is null. 
    // This allows the "All" category to show products correctly (and newly added uncategorized products).

    if (kDebugMode && selectedCategoryId != null) {
      debugPrint('[Visibility] Category match check for ID: $selectedCategoryId');
      debugPrint('[Visibility] Matching IDs set: $matchingIds');
      debugPrint('[Visibility] Active Warehouse: $activeWarehouseId');
    }

    var filtered = products.where((p) {
      // 1. Must be active (already filtered by provider, but keeping for safety)
      if (!p.isActive) return false;

      // Cluster 027 / Task 3 (refined): any name/code/barcode/secondary-
      // barcode substring match wins over warehouse + category +
      // raw-material/service guards. The operator typed a query — we
      // MUST surface every product that matches it regardless of where
      // it's currently filed or what type it is, otherwise the search
      // looks "broken" while the product is right there.
      final isSearchHit = searchMatchIds.contains(p.id);

      // 2. Hide raw materials and services from the default grid view
      // (not sellable in POS by themselves — they're consumed via BOM).
      // BUT surface them when the operator searched for them by name /
      // code / barcode so they can verify pricing or run a manual sale.
      if ((p.productType == 'raw_material' || p.productType == 'service') &&
          !isSearchHit) {
        return false;
      }

      // Warehouse-based explicit locality
      final isLocalWarehouse = activeWarehouseId != null && p.warehouseId == activeWarehouseId;
      final isOtherWarehouse = activeWarehouseId != null && p.warehouseId != null && p.warehouseId != activeWarehouseId;

      // Safe-guard: If explicitly assigned to another warehouse, hide it.
      if (isOtherWarehouse && !isSearchHit) {
        if (kDebugMode && p.categoryId != null && matchingIds.contains(p.categoryId)) {
          debugPrint('[Visibility] ✗ Hidden for mismatch: ${p.name} (Warehouse: ${p.warehouseId} vs Active: $activeWarehouseId)');
        }
        return false;
      }

      // 3. Issue 9: Category-based visibility (Locked/Excluded/Branch-Restricted)
      // Only apply locks if NOT searching and NOT a direct/child match of the selected category
      final isCategoryLocked = p.categoryId != null && lockedCategoryIds.contains(p.categoryId);
      final isCategoryExcluded = p.categoryId != null && excludedCategoryIds.contains(p.categoryId);
      final isChildOfSelected = p.categoryId != null && matchingIds.contains(p.categoryId);

      // NEW: Ensure the category is actually visible to this branch!
      final isCategoryAssignedToBranch = p.categoryId == null || allCategories.any((c) => c.id == p.categoryId);

      // Hide if category isn't assigned to branch EVEN during search, unless explicitly local to warehouse
      if (!isCategoryAssignedToBranch && !isLocalWarehouse && !isSearchHit) {
         return false;
      }

      final isCategoryRestricted = (isCategoryLocked || isCategoryExcluded) && !isSearching && !isChildOfSelected;

      // EXCEPTION: If the product is explicitly assigned to this local warehouse via PO cost center,
      // it overrides category restrictions and MUST be visible!
      if (isCategoryRestricted && !isLocalWarehouse && !isSearchHit) {
        return false;
      }

      return true;
    }).toList();

    // 5. Final Category Scope Filtering
    // Cluster 024 / Issue 4 — when the operator is searching, span every
    // category. The earlier per-row guard already exempts category-locked
    // and excluded categories during search (`!isSearching` predicates),
    // but this final scope filter still hid every product outside the
    // selected category, so a name/code/barcode match in a different
    // category was invisible. Skip the scope filter while searching.
    // Cluster 027 / Task 3: also keep exact-barcode matches even when
    // not in search mode (defensive — in practice isSearching is always
    // true for that path).
    if (selectedCategoryId != null && !isSearching) {
      filtered = filtered
          .where((p) =>
              searchMatchIds.contains(p.id) ||
              (p.categoryId != null && matchingIds.contains(p.categoryId)) ||
              (selectedIsGeneral && p.categoryId == null))
          .toList();
    }

    // Filter by search query — Apply Arabic normalization for consistent Middle Eastern search
    if (searchQuery.isNotEmpty) {
      final query = ArabicUtils.normalize(searchQuery.toLowerCase());
      // Cluster 023 / Issue 9 — multi-barcode coverage. Collect productIds
      // whose alternate barcodes match the query (substring) and OR into
      // the per-product predicate so the matched product appears in the
      // grid even if the primary `barcode` column doesn't match.
      final rawQuery = searchQuery.toLowerCase();
      final extraIds = <int>{};
      _barcodeToProductId.forEach((bc, pid) {
        if (bc.contains(rawQuery)) extraIds.add(pid);
      });
      filtered = filtered.where((p) {
        // Cluster 027 / Task 3: keep every search hit (computed up-front
        // against the full unfiltered list before warehouse / category
        // guards). This is the inverse of the bypass logic above —
        // anything that survived to here AND is a hit, stays.
        if (searchMatchIds.contains(p.id)) return true;
        final normalizedName = ArabicUtils.normalize(p.name.toLowerCase());
        final normalizedCode = ArabicUtils.normalize(p.code.toLowerCase());
        final normalizedBarcode = p.barcode != null
            ? ArabicUtils.normalize(p.barcode!.toLowerCase())
            : '';
        return normalizedName.contains(query) ||
            normalizedCode.contains(query) ||
            normalizedBarcode.contains(query) ||
            extraIds.contains(p.id);
      }).toList();
    }

    return filtered;
  }
}

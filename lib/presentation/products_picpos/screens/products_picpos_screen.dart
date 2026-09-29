import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
// (نفس product_search_header.dart — excelServiceProvider نوعه dynamic في هذا الريبو،
//  فاستدعاء export/import عليه dynamic call مقصود ومكتوم في المصدر الأصلي أيضاً.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_shortcuts.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../products/providers/products_controller.dart';
import '../../screens/units_management_screen.dart';
// جدولُ الأصناف صار فوركاً في PicPos (قرارُ المالك 2026-08-22) — شاشةُ
// UralCash تبقى على `screens/products/widgets/products_table.dart` بلا مساس.
// وشريطُ الإجراءات الجماعيّة **لم يُفرَك**: لم يطلب التصميمُ تغييرَه.
import '../widgets/products_table_picpos.dart';
import '../../screens/products/widgets/products_bulk_action_bar.dart';
import '../../../domain/models/picpos_product_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../widgets/dialogs/add_product_dialog.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_toolbar.dart';
import '../widgets/picpos_category_picker.dart';

/// شاشة الأصناف بهوية PicPos. تُختار بالعلامة في app_main_screen. لا تعيد بناء أي
/// منطق: البحث/الباجينيشن عبر productsControllerProvider، والجدول والإجراءات الجماعية
/// نفس widgets UralCash، وأزرار الهيدر تنادي نفس الخدمات.
class ProductsPicposScreen extends ConsumerStatefulWidget {
  const ProductsPicposScreen({super.key});
  @override
  ConsumerState<ProductsPicposScreen> createState() => _ProductsPicposScreenState();
}

class _ProductsPicposScreenState extends ConsumerState<ProductsPicposScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _loadInFlight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // نفس شرط الباجينيشن في شاشة UralCash (products_screen.dart:92) — نداء نفس الـ notifier.
  void _onScroll() {
    if (_loadInFlight) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    _loadInFlight = true;
    Future(() async {
      try {
        await ref.read(productsControllerProvider.notifier).loadNextPage();
      } finally {
        _loadInFlight = false;
      }
    });
  }

  Future<void> _addProduct() async {
    // ⚠️ الفحصُ في **الدالّة** لا في الزرّ وحدَه: `AppShortcuts(onNew:)` أدناه
    // يستدعيها بـ**F5** فيتخطّى `PermissionGuard` الملفوفَ حول الزرّ كلياً.
    // (مقيسٌ 2026-08-13 — ونفسُ النمط في المشتريات وفواتير البيع.)
    //
    // ولا يُسأل المسؤولُ مرّتين: `ensurePermission` تستهلك موافقةَ الحارس من
    // `ManagerApprovalCache`.
    if (!await ensurePermission(ref, context, PermissionCodes.productsAdd,
        actionName: tr('إضافة صنف'))) {
      return;
    }
    if (!mounted) return;
    final result = await AddProductDialog.show(context);
    if (result != null) {
      await ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
    }
  }

  Future<void> _exportProducts() async {
    final path = await ref.read(excelServiceProvider).exportProductsTemplate();
    if (path != null && mounted) {
      AppToast.show(context, tr('تم تصدير النموذج: {path}', {'path': path}), type: ToastType.success);
    }
  }

  Future<void> _importProducts() async {
    final result = await ref.read(excelServiceProvider).importProducts();
    if (!mounted) return;
    AppToast.show(context, result.message,
        type: result.success ? ToastType.success : ToastType.error);
    if (result.success) {
      ref.invalidate(allProductsProvider);
      ref.invalidate(posGridProductsProvider);
      ref.invalidate(visibleCategoriesProvider);
      ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
    }
  }

  Future<void> _pickCategory() async {
    final cats = ref.read(visibleCategoriesProvider).value ?? const [];
    final selectedId = ref.read(productsControllerProvider).selectedCategoryId;
    final picked = await PicPosCategoryPicker.show(context,
        categories: cats, selectedId: selectedId);
    if (picked != null && mounted) {
      ref.read(productsControllerProvider.notifier).setCategoryFilter(picked.$2?.id);
    }
  }

  /// صفُّ العدّادات — `prodKpis` في التصميم.
  ///
  /// ⚠️ **على الصفحة المحمَّلة لا على الجدول كلِّه.** الشاشةُ مُصفَّحةٌ
  /// (`loadNextPage`)، فما في `state.items` شريحةٌ لا الكلّ — والتسمياتُ تقول
  /// «في الصفحة» صراحةً. عدٌّ إجماليٌّ صادقٌ يحتاج `COUNT(*)` في SQL وهو بندٌ
  /// مستقلّ، وكتابةُ «إجمالي الأصناف» فوق عدّادِ شريحةٍ كانت ستكذب.
  Widget _buildKpiRow() {
    final items = ref.watch(productsControllerProvider.select((s) => s.items));
    final kpis = PicPosProductKpis.from([
      for (final p in items)
        (
          salePrice: p.salePrice,
          costPrice: p.costPrice,
          currentStock: p.currentStock,
          minStock: p.minStock,
          trackInventory: p.trackInventory,
          isActive: p.isActive,
        ),
    ]);

    return PicPosKpiRow(
      kpis: [
        PicPosKpi(
          label: tr('أصناف في الصفحة'),
          value: '${kpis.loaded}',
          icon: PhosphorIconsBold.package,
          tint: AppColors.primary,
        ),
        PicPosKpi(
          label: tr('نشط في الصفحة'),
          value: '${kpis.active}',
          icon: PhosphorIconsBold.checkCircle,
          tint: AppColors.success,
        ),
        PicPosKpi(
          label: tr('تحت الحد الأدنى'),
          value: '${kpis.belowMinStock}',
          icon: PhosphorIconsBold.warning,
          tint: kpis.belowMinStock > 0 ? AppColors.error : AppColors.success,
        ),
        PicPosKpi(
          label: tr('بلا تكلفة مسجّلة'),
          value: '${kpis.missingCost}',
          icon: PhosphorIconsBold.currencyCircleDollar,
          tint: kpis.missingCost > 0 ? AppColors.warning : AppColors.success,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategoryId =
        ref.watch(productsControllerProvider.select((s) => s.selectedCategoryId));
    final cats = ref.watch(visibleCategoriesProvider).value ?? const [];
    String categoryName = tr('تصنيف');
    for (final c in cats) {
      if (c.id == selectedCategoryId) {
        categoryName = c.name;
        break;
      }
    }
    final categoryLabel =
        selectedCategoryId == null ? tr('كل التصنيفات') : categoryName;

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: _addProduct,
      child: PicPosScreenScaffold(
        title: tr('الأصناف'),
        subtitle: tr('إدارة المنتجات والتسعير'),
        icon: PhosphorIconsBold.package,
        headerSearch: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (v) =>
              ref.read(productsControllerProvider.notifier).setSearchQuery(v),
          decoration:  InputDecoration(
            hintText: tr('البحث عن صنف...'),
            prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          ),
        ),
        toolbar: PicPosToolbar(children: [
          OutlinedButton.icon(
            onPressed: _pickCategory,
            icon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
            label: Text(categoryLabel),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsExport,
            allowManagerOverride: true,
            actionName: tr('تصدير الأصناف'),
            child: OutlinedButton.icon(
              onPressed: _exportProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
              label:  Text(tr('تصدير')),
            ),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsImport,
            allowManagerOverride: true,
            actionName: tr('استيراد أصناف'),
            child: OutlinedButton.icon(
              onPressed: _importProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
              label:  Text(tr('استيراد')),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UnitsManagementScreen())),
            icon: const Icon(PhosphorIconsBold.ruler, size: 18),
            label:  Text(tr('وحدات القياس')),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsAdd,
            allowManagerOverride: true,
            actionName: tr('إضافة صنف جديد'),
            child: ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label:  Text(tr('إضافة صنف')),
            ),
          ),
        ]),
        body: Column(
          children: [
            _buildKpiRow(),
            const SizedBox(height: 12),
            Expanded(
              child: PicPosContentCard(
                child: ProductsTablePicpos(
                  scrollController: _scrollController,
                ),
              ),
            ),
            const ProductsBulkActionBar(),
          ],
        ),
      ),
    );
  }
}

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
import '../../../data/services/excel_service.dart';
import '../../products/providers/products_controller.dart';
import '../../screens/units_management_screen.dart';
import '../../screens/products/widgets/products_table.dart';
import '../../screens/products/widgets/products_bulk_action_bar.dart';
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
    final result = await AddProductDialog.show(context);
    if (result != null) {
      await ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
    }
  }

  Future<void> _exportProducts() async {
    final path = await ref.read(excelServiceProvider).exportProductsTemplate();
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير النموذج: $path', type: ToastType.success);
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

  @override
  Widget build(BuildContext context) {
    final selectedCategoryId =
        ref.watch(productsControllerProvider.select((s) => s.selectedCategoryId));
    final cats = ref.watch(visibleCategoriesProvider).value ?? const [];
    final categoryLabel = selectedCategoryId == null
        ? 'كل التصنيفات'
        : cats
            .where((c) => c.id == selectedCategoryId)
            .map((c) => c.name)
            .fold<String?>(null, (_, n) => n) ?? 'تصنيف';

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: _addProduct,
      child: PicPosScreenScaffold(
        title: 'الأصناف',
        subtitle: 'إدارة المنتجات والتسعير',
        icon: PhosphorIconsBold.package,
        headerSearch: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (v) =>
              ref.read(productsControllerProvider.notifier).setSearchQuery(v),
          decoration: const InputDecoration(
            hintText: 'البحث عن صنف...',
            prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
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
            actionName: 'تصدير الأصناف',
            child: OutlinedButton.icon(
              onPressed: _exportProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
              label: const Text('تصدير'),
            ),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsImport,
            allowManagerOverride: true,
            actionName: 'استيراد أصناف',
            child: OutlinedButton.icon(
              onPressed: _importProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
              label: const Text('استيراد'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UnitsManagementScreen())),
            icon: const Icon(PhosphorIconsBold.ruler, size: 18),
            label: const Text('وحدات القياس'),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsAdd,
            allowManagerOverride: true,
            actionName: 'إضافة صنف جديد',
            child: ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label: const Text('إضافة صنف'),
            ),
          ),
        ]),
        body: Column(
          children: [
            Expanded(
              child: PicPosContentCard(
                child: ProductsTable(scrollController: _scrollController),
              ),
            ),
            const ProductsBulkActionBar(),
          ],
        ),
      ),
    );
  }
}

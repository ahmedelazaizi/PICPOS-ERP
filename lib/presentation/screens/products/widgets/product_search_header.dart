// ignore_for_file: avoid_dynamic_calls
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/logging/diagnostic_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../widgets/permission_guard.dart';
import '../../../products/providers/products_controller.dart';
import '../../../widgets/dialogs/add_product_dialog.dart';
import '../../../../services/label_scale_service.dart';
import '../../../../data/providers/providers.dart';
import '../../units_management_screen.dart';

class ProductSearchHeader extends ConsumerWidget {
  final TextEditingController searchController;
  final FocusNode? searchFocusNode;

  const ProductSearchHeader({super.key, required this.searchController, this.searchFocusNode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(productsControllerProvider);
    final products = productsState.items;
    final categoriesAsync = ref.watch(visibleCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Actions Row
        Row(
          children: [
            const Text(
              'إدارة الأصناف',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            _buildScaleActions(context, ref, products),
            const SizedBox(width: 8),
            _buildExportButton(context, ref),
            const SizedBox(width: 8),
            _buildImportButton(context, ref),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UnitsManagementScreen()),
              ),
              icon: const Icon(PhosphorIconsBold.package, size: 18),
              label: const Text('وحدات القياس'),
            ),
            const SizedBox(width: 12),
            _buildAddProductButton(context, ref),
          ],
        ),
        const SizedBox(height: 24),

        // Search Field
        TextField(
          controller: searchController,
          focusNode: searchFocusNode,
          onChanged: (val) =>
              ref.read(productsControllerProvider.notifier).setSearchQuery(val),
          decoration: InputDecoration(
            hintText: 'البحث عن صنف...',
            prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
        const SizedBox(height: 12),

        // Category Filter
        //
        // ROOT-CAUSE FIX (2026-05-12) — "filter doesn't respond on SERVER"
        //
        // On SERVER mode, every client write fires `markTablesUpdated` for
        // the `categories` table (along with everything else those writes
        // touch). Each invalidation flips `visibleCategoriesProvider` from
        // `data` → `loading` → `data` again. Under the old `.when()` we
        // rendered the spinner during every `loading` transition — which
        // destroyed the InkWell mid-tap.
        //
        // The field log proved it: pointer-down events landed on the
        // InkWell, but the subsequent "categoriesAsync.loading (spinner
        // shown)" line meant the widget was replaced *before* gesture
        // recognition completed (~100ms after pointer-down). The `onTap`
        // callback therefore never fired, and the dialog never opened.
        //
        // Switch to AsyncValue.value-first rendering: once we've seen ANY
        // emit, we keep showing the InkWell with the last-known list, even
        // while a refresh is in flight. The widget identity stays stable
        // across emits, the InkWell survives the gesture window, and the
        // dialog opens reliably. Only show the spinner on the genuine
        // first-load (value == null AND state is loading).
        // ROOT-CAUSE FIX v3 (2026-05-12) — ALWAYS render the same widget
        // type at this position. Field log v120 proved that the v2 fix
        // (stable callback identity) wasn't enough: the State's
        // `_rebuildCount` counter kept resetting between taps because the
        // Builder switched between `_CategoryFilterButton` and
        // `CircularProgressIndicator` whenever `categoriesAsync.asData?.value`
        // briefly returned null during a Riverpod AsyncLoading transition.
        // Each switch disposed the InkWell's Element + gesture recognizer.
        // `valueOrNull` (unlike `asData?.value`) preserves prior data
        // through copyWithPrevious, but the safer fix is to never swap
        // widget types at this slot — always emit `_CategoryFilterButton`
        // with whatever data we have (possibly empty) so its Element
        // identity is preserved across every provider emit.
        _CategoryFilterButton(
          key: const ValueKey('category-filter-button'),
          categories: categoriesAsync.value ?? const <Category>[],
          selectedId: productsState.selectedCategoryId,
          loadingFirstTime: categoriesAsync.isLoading &&
              categoriesAsync.value == null,
          errorMessage: categoriesAsync.hasError
              ? categoriesAsync.error?.toString()
              : null,
        ),
      ],
    );
  }

  Widget _buildScaleActions(
    BuildContext context,
    WidgetRef ref,
    List<ProductEntity> products,
  ) {
    return PermissionGuard(
      permission: PermissionCodes.productsExport,
      allowManagerOverride: true,
      actionName: 'عمليات الميزان',
      child: PopupMenuButton<String>(
        tooltip: 'عمليات الميزان',
        onSelected: (value) async {
          final excelService = ref.read(excelServiceProvider);
          switch (value) {
            case 'export_scale':
              final path = await excelService.exportScaleItemsTemplate();
              if (path != null && context.mounted) {
                AppToast.show(
                  context,
                  'تم تصدير قالب أصناف الميزان: $path',
                  type: ToastType.success,
                );
              }
              break;
            case 'import_scale':
              final result = await excelService.importScaleItems();
              if (context.mounted) {
                AppToast.show(
                  context,
                  result.message,
                  type: result.success ? ToastType.success : ToastType.error,
                );
                if (result.success) {
                  ref
                      .read(productsControllerProvider.notifier)
                      .loadNextPage(isRefresh: true);
                }
              }
              break;
            case 'upload_scale':
              await _uploadToScale(context, ref, products);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'export_scale',
            child: ListTile(
              leading: Icon(
                PhosphorIconsBold.fileArrowUp,
                color: AppColors.warning,
              ),
              title: Text('تصدير قالب الميزان'),
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'import_scale',
            child: ListTile(
              leading: Icon(
                PhosphorIconsBold.fileArrowDown,
                color: AppColors.warning,
              ),
              title: Text('استيراد أصناف الميزان'),
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'upload_scale',
            child: ListTile(
              leading: Icon(PhosphorIconsBold.upload, color: AppColors.info),
              title: Text('ترحيل للميزان'),
              dense: true,
            ),
          ),
        ],
        child: IgnorePointer(
          child: OutlinedButton.icon(
            onPressed: () {},
          icon: const Icon(PhosphorIconsBold.scales),
          label: const Text('الميزان ▾'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
            side: const BorderSide(color: AppColors.warning),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton(BuildContext context, WidgetRef ref) {
    return PermissionGuard(
      permission: PermissionCodes.productsExport,
      allowManagerOverride: true,
      actionName: 'تصدير الأصناف',
      child: OutlinedButton.icon(
        onPressed: () async {
          final path = await ref
              .read(excelServiceProvider)
              .exportProductsTemplate();
          if (path != null && context.mounted) {
            AppToast.show(
              context,
              'تم تصدير النموذج بنجاح: $path',
              type: ToastType.success,
            );
          }
        },
        icon: const Icon(PhosphorIconsBold.fileArrowUp),
        label: const Text('تصدير الأصناف'),
      ),
    );
  }

  Widget _buildImportButton(BuildContext context, WidgetRef ref) {
    return PermissionGuard(
      permission: PermissionCodes.productsImport,
      allowManagerOverride: true,
      actionName: 'استيراد أصناف',
      child: OutlinedButton.icon(
        onPressed: () async {
          final result = await ref.read(excelServiceProvider).importProducts();
          if (context.mounted) {
            AppToast.show(
              context,
              result.message,
              type: result.success ? ToastType.success : ToastType.error,
            );
            if (result.success) {
              ref.invalidate(allProductsProvider);
              // Spec 150 BUG-1: also refresh the POS grid's bounded stream.
              ref.invalidate(posGridProductsProvider);
              ref.invalidate(visibleCategoriesProvider);
              ref
                  .read(productsControllerProvider.notifier)
                  .loadNextPage(isRefresh: true);
            }
          }
        },
        icon: const Icon(PhosphorIconsBold.fileArrowDown),
        label: const Text('استيراد أصناف'),
      ),
    );
  }

  Widget _buildAddProductButton(BuildContext context, WidgetRef ref) {
    return PermissionGuard(
      permission: PermissionCodes.productsAdd,
      allowManagerOverride: true,
      actionName: 'إضافة صنف جديد',
      child: ElevatedButton.icon(
        onPressed: () async {
          // Assuming AddProductDialog.show exists
          final result = await AddProductDialog.show(context);
          if (result != null) {
            await ref
                .read(productsControllerProvider.notifier)
                .loadNextPage(isRefresh: true);
            if (context.mounted) {
              AppToast.show(
                context,
                'تم إضافة ${result.productName} بنجاح',
                type: ToastType.success,
              );
            }
          }
        },
        icon: const Icon(PhosphorIconsBold.plus),
        label: const Text('إضافة صنف'),
      ),
    );
  }

  Future<void> _uploadToScale(
    BuildContext context,
    WidgetRef ref,
    List<ProductEntity> products,
  ) async {
    final weightProducts = products
        .where(
          (p) =>
              p.scaleType == 'weight' ||
              p.scaleType == 'weightByPiece' ||
              p.isSoldByWeight,
        )
        .toList();
    if (weightProducts.isEmpty) {
      if (context.mounted) {
        AppToast.show(
          context,
          'لا توجد أصناف للميزان',
          type: ToastType.warning,
        );
      }
      return;
    }

    final settings = await LabelScaleService.instance.loadSettings();
    final brand = settings['brand'] as LabelScaleBrand;
    final connection = settings['connection'] as LabelScaleConnection;

    final pluItems = weightProducts
        .map(
          (p) => ScalePLUItem(
            pluNumber: (p.scalePluNumber != null && p.scalePluNumber! > 0) ? p.scalePluNumber! : p.id,
            name: p.name,
            unitPrice: p.pricePerUnit ?? p.salePrice,
            isByWeight: scaleItemIsSoldByWeight(
              scaleType: p.scaleType,
              isSoldByWeight: p.isSoldByWeight,
            ),
            barcode: p.barcode,
            productCode: p.code,
          ),
        )
        .toList();

    if (context.mounted) {
      AppToast.show(
        context,
        'جاري ترحيل ${pluItems.length} صنف للميزان...',
        type: ToastType.info,
      );
    }

    try {
      final result = await LabelScaleService.instance.uploadPLUItems(
        brand: brand,
        connection: connection,
        items: pluItems,
        ipAddress: settings['ipAddress'] as String?,
        port: settings['port'] as int?,
        comPort: settings['comPort'] as String?,
        baudRate: settings['baudRate'] as int?,
      );

      if (context.mounted) {
        AppToast.show(
          context,
          'تم ترحيل ${result.success}/${result.total} صنف بنجاح',
          type: result.failed == 0 ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ في الترحيل: $e', type: ToastType.error);
      }
    }
  }
}

/// 2026-05-12 root-cause fix — gesture-stable wrapper around the category
/// picker InkWell. Owns the `onTap` callback as a `State` instance method so
/// its identity is stable across parent rebuilds (closure-based onTap was
/// torn down mid-gesture by `visibleCategoriesProvider` re-emits, killing
/// the tap on the SERVER device under client-write traffic).
class _CategoryFilterButton extends ConsumerStatefulWidget {
  final List<Category> categories;
  final int? selectedId;
  // Genuine first-load (no prior data ever emitted). Renders a small
  // spinner inline INSIDE the button so the button's Element is still
  // alive — losing the button on first paint is fine; what matters is
  // never disposing it once it's been rendered with data.
  final bool loadingFirstTime;
  // Latched error message; shown inline in the button label.
  final String? errorMessage;

  const _CategoryFilterButton({
    super.key,
    required this.categories,
    required this.selectedId,
    this.loadingFirstTime = false,
    this.errorMessage,
  });

  @override
  ConsumerState<_CategoryFilterButton> createState() =>
      _CategoryFilterButtonState();
}

class _CategoryFilterButtonState extends ConsumerState<_CategoryFilterButton> {
  // Diagnostic: how many times this widget rebuilt since mount. If gestures
  // are still flaky after this fix, this counter helps confirm whether the
  // State itself is being re-created (counter resets) or just rebuilt
  // (counter increments). The v2 fix slipped because a Builder above swapped
  // widget types on AsyncLoading transitions — disposing this State each
  // time. v3 keeps the State alive by always rendering this widget.
  int _rebuildCount = 0;

  void _onPointerDown(PointerDownEvent event) {
    unawaited(DiagnosticLogger.log(
      'UI',
      'CategoryFilter pointer-down at ${event.position} '
          '(localPos=${event.localPosition} kind=${event.kind.name} '
          'rebuilds=$_rebuildCount '
          'cats=${widget.categories.length} '
          'loadingFirstTime=${widget.loadingFirstTime})',
    ));
  }

  Future<void> _onTap() async {
    // Snapshot `widget.categories` and `widget.selectedId` AT THE TIME OF
    // TAP. Even if the parent re-emits during the dialog, this keeps the
    // dialog wired to consistent inputs for its lifetime.
    final categories = widget.categories;
    final selectedId = widget.selectedId;
    await DiagnosticLogger.log(
      'UI',
      'CategoryFilter onTap fired (categories=${categories.length} '
          'selectedId=$selectedId mounted=${context.mounted} '
          'rebuilds=$_rebuildCount)',
    );
    if (categories.isEmpty) {
      // No categories yet — showing the dialog with an empty list would
      // be confusing. Surface a toast and bail.
      if (mounted) {
        AppToast.show(
          context,
          widget.loadingFirstTime
              ? 'جاري تحميل التصنيفات…'
              : (widget.errorMessage != null
                  ? 'خطأ في تحميل التصنيفات: ${widget.errorMessage}'
                  : 'لا توجد تصنيفات متاحة'),
          type: ToastType.info,
        );
      }
      return;
    }
    try {
      final picked = await showDialog<_CategoryPick>(
        context: context,
        builder: (_) {
          unawaited(DiagnosticLogger.log(
            'UI',
            'CategoryFilter dialog builder running',
          ));
          return _CategorySearchDialog(
            categories: categories,
            selectedId: selectedId,
          );
        },
      );
      await DiagnosticLogger.log(
        'UI',
        'CategoryFilter dialog closed (picked=${picked?.id})',
      );
      if (picked != null && mounted) {
        ref
            .read(productsControllerProvider.notifier)
            .setCategoryFilter(picked.id);
      }
    } catch (e, st) {
      await DiagnosticLogger.log(
        'UI',
        '❌ CategoryFilter showDialog THREW: $e\nstack='
            '${st.toString().substring(0, st.toString().length.clamp(0, 800))}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _rebuildCount++;
    Category? selected;
    if (widget.selectedId != null) {
      for (final c in widget.categories) {
        if (c.id == widget.selectedId) {
          selected = c;
          break;
        }
      }
    }
    final String label;
    if (widget.errorMessage != null && widget.categories.isEmpty) {
      label = 'خطأ في التصنيفات';
    } else if (widget.loadingFirstTime) {
      label = 'جاري التحميل…';
    } else {
      label = selected?.name ?? 'كل التصنيفات';
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.errorMessage != null && widget.categories.isEmpty
                  ? AppColors.error
                  : AppColors.textMuted,
            ),
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardColor,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.loadingFirstTime)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                const Icon(PhosphorIconsBold.squaresFour,
                    size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 12),
              const Icon(PhosphorIconsBold.caretDown,
                  size: 14, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cluster 027 / Task 1 — payload returned by the searchable category
/// picker. `id == null` means "all categories" (clear the filter).
class _CategoryPick {
  final int? id;
  const _CategoryPick(this.id);
}

class _CategorySearchDialog extends StatefulWidget {
  final List<Category> categories;
  final int? selectedId;

  const _CategorySearchDialog({
    required this.categories,
    required this.selectedId,
  });

  @override
  State<_CategorySearchDialog> createState() => _CategorySearchDialogState();
}

class _CategorySearchDialogState extends State<_CategorySearchDialog> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.squaresFour,
                size: 20, color: AppColors.primary),
            SizedBox(width: 8),
            Text('اختر التصنيف'),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: SizedBox(
          width: 420,
          height: 500,
          child: Column(
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ابحث عن تصنيف...',
                  prefixIcon:
                      const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      final isSelected = widget.selectedId == null;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          PhosphorIconsBold.listBullets,
                          color:
                              isSelected ? AppColors.primary : AppColors.textMuted,
                        ),
                        title: Text(
                          'كل التصنيفات',
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(PhosphorIconsBold.check,
                                color: AppColors.success)
                            : null,
                        onTap: () =>
                            Navigator.pop(context, const _CategoryPick(null)),
                      );
                    }
                    final cat = filtered[i - 1];
                    final isSelected = cat.id == widget.selectedId;
                    return ListTile(
                      dense: true,
                      title: Text(
                        cat.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(PhosphorIconsBold.check,
                              color: AppColors.success)
                          : null,
                      onTap: () =>
                          Navigator.pop(context, _CategoryPick(cat.id)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
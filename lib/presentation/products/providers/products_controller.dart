import 'dart:async';

import 'package:drift/drift.dart' show Value, Uint8List;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../core/diagnostics/perf_trace.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/i_products_repository.dart';
import '../../../data/database/database_barrel.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/providers.dart' show databaseProvider;
import '../../../data/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../data/providers/audit_providers.dart';

/// Spec 029 / US4 — search-box debounce window. The cashier types
/// faster than the DB can serve every keystroke; without a debounce
/// the controller fires a `loadNextPage` per character. 200ms is
/// short enough to feel instant, long enough to coalesce a typing
/// burst (~5–7 keystrokes/sec).
const Duration _searchDebounce = Duration(milliseconds: 200);

/// Products state
class ProductsState {
  final List<ProductEntity> items;
  final String searchQuery;
  final int? selectedCategoryId;
  final bool isLoading;
  final String? error;
  final int offset;
  final int limit;
  final bool hasMore;
  final Set<int> selectedIds;

  const ProductsState({
    this.items = const [],
    this.searchQuery = '',
    this.selectedCategoryId,
    this.isLoading = false,
    this.error,
    this.offset = 0,
    this.limit = 20,
    this.hasMore = true,
    this.selectedIds = const {},
  });

  factory ProductsState.initial() => const ProductsState();

  ProductsState copyWith({
    List<ProductEntity>? items,
    String? searchQuery,
    int? selectedCategoryId,
    bool clearCategoryId = false,
    bool? isLoading,
    String? error,
    int? offset,
    int? limit,
    bool? hasMore,
    Set<int>? selectedIds,
  }) {
    return ProductsState(
      items: items ?? this.items,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategoryId
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      isLoading: isLoading ?? this.isLoading,
      error: error,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }

  ProductsState clearCategory() {
    return copyWith(
      clearCategoryId: true,
      items: [], // Reset items to reload
      offset: 0,
      hasMore: true,
    );
  }
}

/// Products controller - Riverpod 3.x Notifier pattern
class ProductsController extends Notifier<ProductsState> {
  late final IProductRepository _repository;

  // Spec 029 / US4 — debounce timer for search-box keystrokes.
  Timer? _searchDebounceTimer;
  // Spec 029 / US4 — counter for the perf audit recipe. Inc'd on each
  // actual DB query so the audit can sample queries-per-second during
  // a typing burst. Compiled-out in release via kPerfDebug.
  final _perfQueryCounter = PerfQueryCounter('products');

  @override
  ProductsState build() {
    _repository = ref.watch(productRepositoryProvider);
    // Cancel any pending debounce on dispose so a stale timer can't
    // fire after the controller is gone.
    ref.onDispose(() {
      _searchDebounceTimer?.cancel();
    });
    // Initial load - loadNextPage will handle the actual loading
    Future.microtask(() => loadNextPage(isRefresh: true));
    // Return with isLoading=true so loading indicator shows immediately
    return const ProductsState(isLoading: true);
  }

  Future<void> loadNextPage({bool isRefresh = false}) async {
    // Spec 118 (Bug Y) — defensive ref.mounted check.
    // الـ field log أظهر [PLATFORM_ERROR] Cannot use the Ref of
    // NotifierProvider<ProductsController> after it has been disposed
    // عند خروج سريع من شاشة المنتجات. السبب: loadNextPage تُستدعى
    // من Future.microtask (السطر 107) ومن debounce timer (155-165)،
    // فلو الـ provider يُحلَّل (autoDispose أو widget unmount) أثناء
    // الـ await، الـ state access بعدها يفشل.
    if (!ref.mounted) return;

    if (state.isLoading && state.items.isNotEmpty) return;
    if (!state.hasMore && !isRefresh) return;

    final currentOffset = isRefresh ? 0 : state.offset;
    final currentItems = isRefresh ? <ProductEntity>[] : state.items;

    state = state.copyWith(
      isLoading: true,
      error: null,
      offset: currentOffset, // Update offset tentatively if refresh
      items: isRefresh ? [] : state.items, // Clear items if refresh
    );

    try {
      _perfQueryCounter.inc(); // Spec 029 / US4 — audit instrumentation.
      final newItems = await _repository.getProducts(
        limit: state.limit,
        offset: currentOffset,
        query: state.searchQuery,
        categoryId: state.selectedCategoryId,
      );

      // Spec 118 (Bug Y) — second mounted check بعد async gap.
      if (!ref.mounted) return;

      final hasNext = newItems.length >= state.limit;
      final updatedItems = [...currentItems, ...newItems];

      state = state.copyWith(
        items: updatedItems,
        isLoading: false,
        offset: currentOffset + newItems.length,
        hasMore: hasNext,
      );
    } catch (e, stack) {
      print('[PRODUCTS_CTRL] ❌ loadNextPage FAILED: $e\n$stack');
      logger.error('Failed to load products', e, stack, 'PRODUCTS');
      // Spec 118 (Bug Y) — لا state access لو الـ provider تُحلَّل أثناء الـ catch
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, error: 'فشل تحميل المنتجات: $e');
      }
    }
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) return;
    // Update the input-binding state immediately so the text field
    // never feels laggy, but defer the DB query until the typing
    // burst settles (Spec 029 / US4 — FR-018, 200ms debounce).
    state = state.copyWith(
      searchQuery: query,
      items: [],
      offset: 0,
      hasMore: true,
    );
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      loadNextPage(isRefresh: true);
    });
  }

  void setCategoryFilter(int? categoryId) {
    if (categoryId == null) {
      if (state.selectedCategoryId == null) return;
      state = state.clearCategory();
    } else {
      if (state.selectedCategoryId == categoryId) return;
      state = state.copyWith(
        selectedCategoryId: categoryId,
        items: [],
        offset: 0,
        hasMore: true,
      );
    }
    loadNextPage(isRefresh: true);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<int?> createProduct({
    required String code,
    required String name,
    required double salePrice,
    required double costPrice,
    int? categoryId,
    double? pricePerUnit,
    double currentStock = 0,
    double minStock = 0,
    bool trackInventory = true,
    bool trackExpiry = false,
    bool isSoldByWeight = false,
    String? description,
    Uint8List? image,
    int? scalePluNumber,
    String scaleType = 'count',
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // ── Client mode: send to server FIRST, then use the server-assigned
      // ID locally. This keeps client/server IDs perfectly in sync and
      // prevents the "duplicate row after next fullSync" bug where the
      // client ends up with the local auto-increment row AND the synced
      // server-ID row for the same product.
      //
      // If the server is offline, `createProduct` queues into the outbox
      // and returns null → we fall back to a local auto-increment ID,
      // which gets reconciled on the next sync (the outbox replay inserts
      // the product on the server and the pull updates the local ID via
      // the product sync strategy).
      int? serverId;
      try {
        serverId = await ClientWriteInterceptor.createProduct(
          code: code,
          name: name,
          salePrice: salePrice,
          costPrice: costPrice,
          categoryId: categoryId,
          currentStock: currentStock,
          minStock: minStock,
          isSoldByWeight: isSoldByWeight,
          trackExpiry: trackExpiry,
          pricePerUnit: pricePerUnit,
          scaleType: scaleType,
          scalePluNumber: scalePluNumber,
        );
      } catch (e) {
        logger.info(
          'Server createProduct failed, falling back to local insert: $e',
          correlationId: 'PRODUCTS',
        );
      }

      final companion = ProductsCompanion.insert(
        id: serverId != null ? Value(serverId) : const Value<int>.absent(),
        code: code,
        name: name,
        categoryId: Value(categoryId),
        salePrice: Value(salePrice),
        costPrice: Value(costPrice),
        pricePerUnit: Value(pricePerUnit),
        currentStock: Value(currentStock),
        minStock: Value(minStock),
        trackInventory: Value(trackInventory),
        trackExpiry: Value(trackExpiry),
        isSoldByWeight: Value(isSoldByWeight),
        description: Value(description),
        imageData: Value(image),
        scalePluNumber: Value(scalePluNumber),
        scaleType: Value(scaleType),
      );

      final id = await _repository.insertProduct(companion);

      logger.info(
        'Created product: $name (#$id, serverId=$serverId)',
        correlationId: 'PRODUCTS',
      );
      loadNextPage(isRefresh: true);
      return id;
    } catch (e, stack) {
      logger.error('Failed to create product', e, stack, 'PRODUCTS');
      state = state.copyWith(isLoading: false, error: 'فشل إنشاء المنتج: $e');
      return null;
    }
  }

  Future<bool> updateProduct(ProductEntity product) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // ── Client mode: queue to server (fire-and-forget) ──
      //
      // P5 (subsequent-edit fix): Look up the product's globalId from local
      // DB and ship it. Without it the server falls back to lookup-by-code,
      // which is fragile when:
      //   • Code was changed in this same edit (the lookup returns the OLD
      //     row by old code mismatch, finds nothing, the upsert path
      //     creates a duplicate with the new code).
      //   • A duplicate with the same code already exists from an earlier
      //     race; lookup returns whichever one the SQLite engine picks.
      // Result observed by user: first edit syncs (creates the row on
      // server), but subsequent edits silently target the wrong row OR get
      // dropped because the lookup picks a stale duplicate. Sending
      // globalId makes the lookup deterministic and idempotent.
      String? productGlobalId;
      try {
        final db = ref.read(databaseProvider);
        final row = await (db.select(db.products)
              ..where((p) => p.id.equals(product.id))
              ..limit(1))
            .getSingleOrNull();
        productGlobalId = row?.globalId;
      } catch (_) {}

      final productData = {
        if (productGlobalId != null && productGlobalId.isNotEmpty)
          'globalId': productGlobalId,
        'code': product.code,
        'name': product.name,
        'description': product.description,
        'barcode': product.barcode,
        // Pricing (all four levels)
        'salePrice': product.salePrice,
        'costPrice': product.costPrice,
        'wholesalePrice': product.wholesalePrice,
        'priceTalabat': product.priceTalabat,
        'priceCareem': product.priceCareem,
        'priceAshyae': product.priceAshyae,
        'pricePerUnit': product.pricePerUnit,
        'taxRate': product.taxRate,
        // Inventory / behaviour
        'minStock': product.minStock,
        'trackInventory': product.trackInventory,
        'trackExpiry': product.trackExpiry,
        'defaultShelfDays': product.defaultShelfDays,
        'alertDaysBefore': product.alertDaysBefore,
        'isSoldByWeight': product.isSoldByWeight,
        'allowNegativeSale': product.allowNegativeSale,
        'isActive': product.isActive,
        // Scale
        'scalePluNumber': product.scalePluNumber,
        'scaleType': product.scaleType,
        // Classification + FKs
        'productType': product.productType,
        'categoryId': product.categoryId,
        'supplierId': product.supplierId,
        'warehouseId': product.warehouseId,
      };

      ClientWriteInterceptor.updateProduct(
        product.id,
        productData,
      ).catchError((e) {
        debugPrint('[ProductsController] updateProduct sync failed (queued): $e');
        return false;
      });

      // ALWAYS write locally
      await _repository.updateProductFromEntity(product);

      logger.info(
        'Updated product: ${product.name} (#${product.id})',
        correlationId: 'PRODUCTS',
      );

      // Reset isLoading BEFORE refresh so loadNextPage's guard doesn't skip it
      state = state.copyWith(isLoading: false);
      await loadNextPage(isRefresh: true);
      return true;
    } catch (e, stack) {
      logger.error(
        'Failed to update product #${product.id}',
        e,
        stack,
        'PRODUCTS',
      );
      state = state.copyWith(isLoading: false, error: 'فشل تحديث المنتج: $e');
      return false;
    }
  }

  Future<bool> deleteProduct(int id) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // ── Client mode: also queue to server (fire-and-forget) ──
      ClientWriteInterceptor.deleteProduct(id).catchError((_) {});

      // ALWAYS delete locally
      await _repository.deleteProduct(id);

      logger.info('Deleted product #$id', correlationId: 'PRODUCTS');
      // Remove locally
      final updatedItems = state.items.where((p) => p.id != id).toList();
      state = state.copyWith(items: updatedItems, isLoading: false);
      return true;
    } catch (e, stack) {
      logger.error('Failed to delete product #$id', e, stack, 'PRODUCTS');
      state = state.copyWith(isLoading: false, error: 'فشل حذف المنتج: $e');
      return false;
    }
  }

  Future<void> toggleProductLock(ProductEntity product) async {
    // Currently disabled for Domain Entity representation until update method handles DTO.
    /*
    try {
      final updatedProduct = product.copyWith(isLocked: !product.isLocked);
      await _repository.updateProduct(updatedProduct);
      
      final updatedItems = state.items.map((p) => p.id == product.id ? updatedProduct : p).toList();
      state = state.copyWith(items: updatedItems);
    } catch (e, stack) {
      logger.error('Failed to toggle product lock', e, stack, 'PRODUCTS');
    }
    */
  }

  void toggleSelection(int id) {
    final newSelectedIds = Set<int>.from(state.selectedIds);
    if (newSelectedIds.contains(id)) {
      newSelectedIds.remove(id);
    } else {
      newSelectedIds.add(id);
    }
    state = state.copyWith(selectedIds: newSelectedIds);
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: state.items.map((p) => p.id).toSet(),
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {});
  }

  Future<void> bulkDeleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    
    state = state.copyWith(isLoading: true, error: null);
    try {
      for (final id in state.selectedIds) {
        // Fire-and-forget server sync
        ClientWriteInterceptor.deleteProduct(id).catchError((_) {});
        // ALWAYS delete locally
        await _repository.deleteProduct(id);
      }
      
      final updatedItems = state.items.where((p) => !state.selectedIds.contains(p.id)).toList();
      final count = state.selectedIds.length;
      final user = ref.read(authProvider).user;
      
      state = state.copyWith(
        items: updatedItems, 
        isLoading: false, 
        selectedIds: {},
      );
      
      if (user != null) {
        await ref.read(activityLoggerProvider).logBulkAction(
          user.id,
          user.displayName,
          'product',
          'delete',
          count,
        );
      }
      
      logger.info('Bulk deleted $count products', correlationId: 'PRODUCTS');
    } catch (e, stack) {
      logger.error('Failed bulk delete', e, stack, 'PRODUCTS');
      state = state.copyWith(isLoading: false, error: 'فشل حذف المنتجات المحددة: $e');
    }
  }

  Future<void> bulkUpdateStatus(bool active) async {
    if (state.selectedIds.isEmpty) return;
    
    state = state.copyWith(isLoading: true, error: null);
    try {
      final count = state.selectedIds.length;
      for (final id in state.selectedIds) {
        final product = state.items.firstWhere((p) => p.id == id);
        final updatedProduct = product.copyWith(isActive: active);
        await updateProduct(updatedProduct);
      }
      
      final user = ref.read(authProvider).user;
      if (user != null) {
        await ref.read(activityLoggerProvider).logBulkAction(
          user.id,
          user.displayName,
          'product',
          active ? 'activate' : 'deactivate',
          count,
        );
      }
      
      state = state.copyWith(isLoading: false, selectedIds: {});
    } catch (e, stack) {
      logger.error('Failed bulk update', e, stack, 'PRODUCTS');
      state = state.copyWith(isLoading: false, error: 'فشل تحديث المنتجات: $e');
    }
  }
}

/// Provider for products controller - Riverpod 3.x NotifierProvider
final productsControllerProvider =
    NotifierProvider.autoDispose<ProductsController, ProductsState>(ProductsController.new);

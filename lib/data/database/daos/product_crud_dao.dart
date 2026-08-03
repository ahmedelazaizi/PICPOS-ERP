part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT CRUD DAO — المنتجات والأقسام والتنبيهات
// ═══════════════════════════════════════════════════════════════════════════

/// Global cache for product search results to avoid redundant FTS queries
final Map<String, List<Product>> _productSearchCache = {};

/// PERF: In-memory cache for product-by-ID lookups (barcode scan flow)
/// Key = productId, evicts LRU when exceeding 200 entries.
final Map<int, Product> _productByIdCache = {};

/// Spec 136 (field 2026-06-14): cached availability of the FTS5 shadow table
/// `products_fts`. Some DBs lack it (a mirror seeded before the FTS migration,
/// or a backend without FTS5) — product search must fall back to LIKE instead
/// of crashing with "no such table: products_fts" (the stock-transfer item
/// picker crash).
bool? _productsFtsAvailable;

/// FTS-free product search used when `products_fts` is absent. Matches the
/// normalized search_name / name / code (LIKE) plus exact barcode/code, with
/// exact hits ranked first.
const String _kLikeProductSearchSql = '''
  SELECT p.* FROM products p
  WHERE (p.search_name LIKE ? OR p.name LIKE ? OR p.code LIKE ? OR p.barcode = ? OR p.code = ?)
    AND p.is_active = 1
  ORDER BY (CASE WHEN p.barcode = ? OR p.code = ? THEN 0 ELSE 1 END), p.name ASC
''';

/// PERF: In-memory cache for category list (rarely changes)
List<Category>? _categoriesCache;
DateTime? _categoriesCacheTime;

/// Clear all product/category caches. Called by AppDatabase.forTesting()
/// to prevent cross-test contamination (top-level caches are shared per process).
void resetProductCaches() {
  _productSearchCache.clear();
  _productByIdCache.clear();
  _categoriesCache = null;
  _categoriesCacheTime = null;
}

/// Extension for core Product CRUD, Search, Category, and Alert operations
extension ProductCrudDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all active products ordered by sort order then name
  Stream<List<Product>> watchAllProducts() {
    return (select(products)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([
            (p) => OrderingTerm.asc(p.sortOrder),
            (p) => OrderingTerm.asc(p.name),
          ]))
        .watch();
  }

  /// Spec 136 ISS-9 — bounded, DB-filtered product stream for the inventory
  /// stock-balances screen. The screen previously watched the UNBOUNDED
  /// `watchAllProducts()`, which loaded + mapped every active row — a 762ms
  /// UI-isolate stall on a 57978-product catalog (build was only 0.3ms, so it
  /// was the data load, not rendering). Applying the filters in SQL means the
  /// LIMIT yields the right rows instead of fetching everything and filtering
  /// in Dart. [restrictToIds] scopes to a warehouse's product set when a
  /// warehouse filter is active. Multi-barcode (unit-row) search is not
  /// covered here — only the primary barcode column — to keep the query a
  /// single bounded statement (the inventory screen is for browsing/adjusting,
  /// not POS scanning).
  Stream<List<Product>> watchInventoryProducts({
    int limit = 1500,
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
    Iterable<int>? restrictToIds,
  }) {
    final q = select(products)..where((p) => p.isActive.equals(true));
    if (restrictToIds != null) {
      final ids = restrictToIds.toList();
      // An empty restriction set means "no products in this warehouse" → emit
      // nothing rather than (incorrectly) every product.
      if (ids.isEmpty) {
        q.where((p) => p.id.equals(-1));
      } else {
        q.where((p) => p.id.isIn(ids));
      }
    }
    if (categoryId != null) {
      q.where((p) => p.categoryId.equals(categoryId));
    }
    if (lowStockOnly) {
      q.where((p) => p.currentStock.isSmallerOrEqual(p.minStock));
    }
    final s = search?.trim() ?? '';
    if (s.isNotEmpty) {
      final like = '%$s%';
      q.where((p) =>
          p.name.like(like) | p.code.like(like) | p.barcode.like(like));
    }
    q
      ..orderBy([
        (p) => OrderingTerm.asc(p.sortOrder),
        (p) => OrderingTerm.asc(p.name),
      ])
      ..limit(limit);
    return q.watch();
  }

  /// Spec 136 ISS-12 — bounded product stream for the POS grid. The grid shows
  /// ONE category (or search results) at a time, so it never needs the whole
  /// catalog: watching the unbounded `watchAllProducts()` loaded + mapped all
  /// 57978 rows on POS entry (~8s) AND re-mapped them on every sale's stock
  /// change (blocking the post-sale readback ~7s, readbackMs=7119 in the field).
  /// This scopes the query to the selected category (+ descendants) or the
  /// search term, DB-side + LIMIT, so POS load + post-sale rebuild are
  /// independent of catalog size. Barcode scan + cart use separate DB lookups
  /// and are unaffected.
  Stream<List<Product>> watchPosProducts({
    Iterable<int>? categoryIds,
    String? search,
    int limit = 600,
    bool includeUncategorized = false,
  }) {
    final q = select(products)..where((p) => p.isActive.equals(true));
    final s = search?.trim() ?? '';
    if (s.isNotEmpty) {
      // Search overrides category — find the typed item anywhere.
      final like = '%$s%';
      q.where((p) =>
          p.name.like(like) | p.code.like(like) | p.barcode.like(like));
    } else if (categoryIds != null) {
      final ids = categoryIds.toList();
      if (ids.isNotEmpty) {
        q.where((p) => includeUncategorized
            ? p.categoryId.isIn(ids) | p.categoryId.isNull()
            : p.categoryId.isIn(ids));
      }
      // empty categoryIds + no search ⇒ the "All" view (bounded by LIMIT).
    }
    q
      ..orderBy([
        (p) => OrderingTerm.asc(p.sortOrder),
        (p) => OrderingTerm.asc(p.name),
      ])
      ..limit(limit);
    return q.watch();
  }

  /// Spec 136 ISS-9b — one page of inventory products (offset-based) for
  /// infinite scroll. Same DB-side filters as [watchInventoryProducts] but a
  /// Future with an OFFSET, so the screen can append page-by-page and browse
  /// the WHOLE catalog smoothly without ever materialising it all at once
  /// (O(n) total across the scroll, vs re-mapping a growing LIMIT each step).
  Future<List<Product>> getInventoryProductsPage({
    required int limit,
    required int offset,
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
    Iterable<int>? restrictToIds,
  }) {
    final q = select(products)..where((p) => p.isActive.equals(true));
    if (restrictToIds != null) {
      final ids = restrictToIds.toList();
      if (ids.isEmpty) {
        q.where((p) => p.id.equals(-1));
      } else {
        q.where((p) => p.id.isIn(ids));
      }
    }
    if (categoryId != null) {
      q.where((p) => p.categoryId.equals(categoryId));
    }
    if (lowStockOnly) {
      q.where((p) => p.currentStock.isSmallerOrEqual(p.minStock));
    }
    final s = search?.trim() ?? '';
    if (s.isNotEmpty) {
      final like = '%$s%';
      q.where((p) =>
          p.name.like(like) | p.code.like(like) | p.barcode.like(like));
    }
    q
      ..orderBy([
        (p) => OrderingTerm.asc(p.sortOrder),
        (p) => OrderingTerm.asc(p.name),
      ])
      ..limit(limit, offset: offset);
    return q.get();
  }

  /// Spec 136 ISS-9 — cheap aggregate for the inventory summary cards
  /// (active count, low-stock count, total stock value). Computed in SQL so
  /// the summary no longer depends on mapping every product entity. Uses
  /// Drift aggregate expressions (FILTER clause) — dialect-safe on SQLite and
  /// PostgreSQL.
  Stream<({int activeCount, int lowStockCount, double totalValue})>
      watchInventorySummary() {
    final activeF = products.isActive.equals(true);
    final trackable = activeF & products.trackInventory.equals(true);
    final activeCount = products.id.count(filter: activeF);
    final lowStockCount = products.id.count(
        filter: trackable & products.currentStock.isSmallerOrEqual(products.minStock));
    final totalValue =
        (products.currentStock * products.costPrice).sum(filter: trackable);
    final query = selectOnly(products)
      ..addColumns([activeCount, lowStockCount, totalValue]);
    return query.watchSingle().map((row) => (
          activeCount: row.read(activeCount) ?? 0,
          lowStockCount: row.read(lowStockCount) ?? 0,
          totalValue: row.read(totalValue) ?? 0.0,
        ));
  }

  /// Get all active products ordered by sort order then name.
  /// Pagination: [limit] and [offset] default to 500/0 to prevent loading
  /// unbounded datasets. Callers that need all rows can pass a large limit.
  Future<List<Product>> getAllProducts({
    int limit = 500,
    int offset = 0,
  }) {
    return (select(products)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([
            (p) => OrderingTerm.asc(p.sortOrder),
            (p) => OrderingTerm.asc(p.name),
          ])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Batch update product sort orders (for drag-and-drop reordering)
  Future<void> updateProductSortOrders(List<int> productIds) async {
    await transaction(() async {
      for (int i = 0; i < productIds.length; i++) {
        await (update(products)..where((p) => p.id.equals(productIds[i])))
            .write(ProductsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Batch update category sort orders (for drag-and-drop reordering)
  Future<void> updateCategorySortOrders(List<int> categoryIds) async {
    await transaction(() async {
      for (int i = 0; i < categoryIds.length; i++) {
        await (update(categories)..where((c) => c.id.equals(categoryIds[i])))
            .write(CategoriesCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Get a single product by ID (PERF: cached for barcode scan flow)
  Future<Product?> getProductById(int id) async {
    // Check cache first — but never inside a transaction. See
    // AppDatabase.isInTransaction for why both directions are unsafe there.
    if (!isInTransaction && _productByIdCache.containsKey(id)) {
      return _productByIdCache[id];
    }

    final product = await (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (product != null && !isInTransaction) {
      // LRU eviction at 200 entries
      if (_productByIdCache.length > 200) {
        _productByIdCache.remove(_productByIdCache.keys.first);
      }
      _productByIdCache[id] = product;
    }
    return product;
  }

  /// Batch-fetch products by IDs. Returns map for O(1) lookup.
  /// Use to eliminate N+1 queries when iterating over invoice items, BOM components, etc.
  Future<Map<int, Product>> getProductsByIds(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final unique = ids.toSet().toList();
    final productList = await (select(products)..where((p) => p.id.isIn(unique))).get();
    // Same transaction rule as getProductById. This reader is the worse
    // offender of the two: it never consults the cache, only WRITES to it, so
    // inside the purchase-invoice loop it poisoned every line of the invoice
    // at once with mid-transaction stock and cost.
    if (!isInTransaction) {
      for (final p in productList) {
        if (_productByIdCache.length > 200) {
          _productByIdCache.remove(_productByIdCache.keys.first);
        }
        _productByIdCache[p.id] = p;
      }
    }
    return {for (final p in productList) p.id: p};
  }

  /// Invalidate product cache (call after insert/update/delete)
  void invalidateProductCache([int? productId]) {
    if (productId != null) {
      _productByIdCache.remove(productId);
    } else {
      _productByIdCache.clear();
    }
    _productSearchCache.clear();
  }

  /// Get next sequential product code (8-digit format starting from 10000001)
  Future<String> getNextProductCode() async {
    const int baseCode = 10000000; // Start from 10 million
    final count =
        await (selectOnly(products)..addColumns([products.id.count()]))
            .map((row) => row.read(products.id.count()))
            .getSingle();
    final nextNumber = baseCode + (count ?? 0) + 1;
    return nextNumber.toString();
  }

  /// Returns true if the FTS5 shadow table `products_fts` exists (cached).
  Future<bool> _hasProductsFts() async {
    final cached = _productsFtsAvailable;
    if (cached != null) return cached;
    try {
      final r = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='products_fts' LIMIT 1",
      ).getSingleOrNull();
      return _productsFtsAvailable = (r != null);
    } catch (_) {
      return _productsFtsAvailable = false;
    }
  }

  /// Search products by name or code
  Stream<List<Product>> searchProducts(String query) {
    if (query.isEmpty) {
      return watchAllProducts();
    }

    final normalizedQuery = ArabicUtils.normalize(query);

    // Default to the FTS-free LIKE query until we've confirmed `products_fts`
    // exists — prevents the "no such table: products_fts" crash on DBs without
    // it (e.g. the stock-transfer item picker on a mirror seeded without FTS).
    if (_productsFtsAvailable == null) unawaited(_hasProductsFts());
    if (_productsFtsAvailable != true) {
      final like = '%$normalizedQuery%';
      return customSelect(
        _kLikeProductSearchSql,
        variables: [
          Variable.withString(like),
          Variable.withString(like),
          Variable.withString(like),
          Variable.withString(query),
          Variable.withString(query),
          Variable.withString(query),
          Variable.withString(query),
        ],
        readsFrom: {products},
      ).watch().map((rows) => rows.map((row) => products.map(row.data)).toList());
    }

    // Full Text Search (FTS5) — better Arabic tokenization + ranking.
    final processedQuery = normalizedQuery
        .split(RegExp(r'\s+'))
        .map((e) => '$e*')
        .join(' ');

    return customSelect(
      '''
      SELECT p.* FROM products p
      LEFT JOIN products_fts f ON p.id = f.rowid
      WHERE (f.searchName MATCH ? OR f.name MATCH ? OR f.code MATCH ? OR p.barcode = ? OR p.code = ?) AND p.is_active = 1
      ORDER BY (CASE WHEN p.barcode = ? OR p.code = ? THEN 0 ELSE 1 END), bm25(f) ASC
      ''',
      variables: [
        Variable.withString(processedQuery),
        Variable.withString(processedQuery),
        Variable.withString(processedQuery),
        Variable.withString(query),
        Variable.withString(query),
        Variable.withString(query),
        Variable.withString(query),
      ],
      readsFrom: {products},
    ).watch().map((rows) => rows.map((row) => products.map(row.data)).toList());
  }

  /// Search products by name or code (Async version with caching)
  Future<List<Product>> searchProductsAsync(
    String query, {
    bool useCache = true,
  }) async {
    if (query.isEmpty) {
      return getAllProducts();
    }

    final cacheKey = query.trim().toLowerCase();
    if (useCache && _productSearchCache.containsKey(cacheKey)) {
      return _productSearchCache[cacheKey]!;
    }

    final normalizedQuery = ArabicUtils.normalize(query);

    List<Product> results;
    Future<List<Product>> runLike() {
      final like = '%$normalizedQuery%';
      return customSelect(
        _kLikeProductSearchSql,
        variables: [
          Variable.withString(like),
          Variable.withString(like),
          Variable.withString(like),
          Variable.withString(query),
          Variable.withString(query),
          Variable.withString(query),
          Variable.withString(query),
        ],
        readsFrom: {products},
      ).get().then((rows) => rows.map((row) => products.map(row.data)).toList());
    }

    if (await _hasProductsFts()) {
      final processedQuery = normalizedQuery
          .split(RegExp(r'\s+'))
          .map((e) => '$e*')
          .join(' ');
      try {
        results = await customSelect(
          '''
      SELECT p.* FROM products p
      LEFT JOIN products_fts f ON p.id = f.rowid
      WHERE (f.searchName MATCH ? OR f.name MATCH ? OR f.code MATCH ? OR p.barcode = ? OR p.code = ?) AND p.is_active = 1
      ORDER BY (CASE WHEN p.barcode = ? OR p.code = ? THEN 0 ELSE 1 END), bm25(f) ASC
      ''',
          variables: [
            Variable.withString(processedQuery),
            Variable.withString(processedQuery),
            Variable.withString(processedQuery),
            Variable.withString(query),
            Variable.withString(query),
            Variable.withString(query),
            Variable.withString(query),
          ],
          readsFrom: {products},
        ).get().then((rows) => rows.map((row) => products.map(row.data)).toList());
      } catch (_) {
        // FTS table vanished/corrupt after the availability check — degrade.
        _productsFtsAvailable = false;
        results = await runLike();
      }
    } else {
      results = await runLike();
    }

    if (useCache) {
      // Limit cache size to avoid memory issues (keep last 50 unique searches)
      if (_productSearchCache.length > 50) {
        _productSearchCache.remove(_productSearchCache.keys.first);
      }
      _productSearchCache[cacheKey] = results;
    }

    return results;
  }

  /// Get products by category
  Stream<List<Product>> watchProductsByCategory(int categoryId) {
    return (select(products)
          ..where(
            (p) => p.isActive.equals(true) & p.categoryId.equals(categoryId),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Insert a new product with trial version limits
  Future<int> insertProduct(ProductsCompanion product) async {
    // Trial version limit: configurable via TrialPolicy
    if (AppConfig.isDemo) {
      // Check HMAC-verified activation status (cached at app startup)
      if (!TrialState.isActivatedCached) {
        final maxProducts = TrialState.activePolicy.maxProducts;
        if (maxProducts != null) {
          final count =
              await (selectOnly(products)..addColumns([products.id.count()]))
                  .map((row) => row.read(products.id.count()))
                  .getSingle();
          if ((count ?? 0) >= maxProducts) {
            throw Exception(
              'تم الوصول للحد الأقصى للأصناف في النسخة التجريبية ($maxProducts صنف)',
            );
          }
        }
      }
    }

    // #Phase4: Populate searchName
    // UUID-First (Phase 1): guarantee every inserted product has a global_id.
    // If the caller already supplied one (sync replay / server-originated row)
    // we respect it; otherwise we mint a fresh UUID v7 locally so the record
    // has a stable identity from the moment it hits the DB — no more NULLs
    // floating around the outbox.
    final hasGid = product.globalId.present &&
        (product.globalId.value?.isNotEmpty ?? false);
    final pWithSearch = product.copyWith(
      searchName: Value(ArabicUtils.normalize(product.name.value)),
      globalId: hasGid ? product.globalId : Value(UuidV7.generate()),
    );

    final id = await into(products).insert(pWithSearch);
    invalidateProductCache(); // Invalidate all product caches on write
    return id;
  }

  /// Update an existing product
  Future<bool> updateProduct(Product product) async {
    final pWithSearch = product.copyWith(
      searchName: Value(ArabicUtils.normalize(product.name)),
    );
    final updated = await update(products).replace(pWithSearch);
    if (updated) invalidateProductCache(product.id); // Invalidate specific product cache
    return updated;
  }

  /// Targeted update from domain entity (Prevents wiping unmapped columns like imagePath, createdAt)
  /// PIR P1-02: Logs price/cost changes to field_audit_logs for financial audit trail.
  Future<bool> updateProductFromEntity(
    ProductEntity entity, {
    int changedBy = 0,
    String changedByName = 'SYSTEM',
  }) async {
    // Read current values for audit comparison
    final existing = await (select(products)
          ..where((p) => p.id.equals(entity.id)))
        .getSingleOrNull();

    final companion = ProductsCompanion(
      code: Value(entity.code),
      barcode: Value(entity.barcode),
      name: Value(entity.name),
      searchName: Value(ArabicUtils.normalize(entity.name)),
      description: Value(entity.description),
      categoryId: Value(entity.categoryId),
      salePrice: Value(entity.salePrice),
      costPrice: Value(entity.costPrice),
      minStock: Value(entity.minStock),
      trackInventory: Value(entity.trackInventory),
      trackExpiry: Value(entity.trackExpiry),
      isSoldByWeight: Value(entity.isSoldByWeight),
      isActive: Value(entity.isActive),
      scalePluNumber: Value(entity.scalePluNumber),
      scaleType: Value(entity.scaleType ?? 'count'),
      taxRate: Value(entity.taxRate),
      allowNegativeSale: Value(entity.allowNegativeSale),
      defaultShelfDays: Value(entity.defaultShelfDays),
      alertDaysBefore: Value(entity.alertDaysBefore),
      priceTalabat: Value(entity.priceTalabat),
      priceCareem: Value(entity.priceCareem),
      priceAshyae: Value(entity.priceAshyae),
      wholesalePrice: Value(entity.wholesalePrice),
      supplierId: Value(entity.supplierId),
      pricePerUnit: Value(entity.pricePerUnit),
      imageData: Value(entity.imageData),
      warehouseId: Value(entity.warehouseId),
      productType: Value(entity.productType ?? 'general'),
    );

    final rowsAffected = await (update(
      products,
    )..where((p) => p.id.equals(entity.id))).write(companion);

    if (rowsAffected > 0) {
      invalidateProductCache(entity.id);

      // P1-02: Log price changes for financial audit trail
      if (existing != null) {
        final txId = 'product-edit-${entity.id}-${DateTime.now().millisecondsSinceEpoch}';
        if ((existing.salePrice - entity.salePrice).abs() > 0.001) {
          await logFieldChange(
            entityType: 'product',
            entityId: entity.id,
            fieldName: 'سعر البيع',
            fieldKey: 'sale_price',
            oldValue: existing.salePrice.toStringAsFixed(4),
            newValue: entity.salePrice.toStringAsFixed(4),
            changedBy: changedBy,
            changedByName: changedByName,
            transactionId: txId,
          );
        }
        if ((existing.costPrice - entity.costPrice).abs() > 0.001) {
          await logFieldChange(
            entityType: 'product',
            entityId: entity.id,
            fieldName: 'سعر التكلفة',
            fieldKey: 'cost_price',
            oldValue: existing.costPrice.toStringAsFixed(4),
            newValue: entity.costPrice.toStringAsFixed(4),
            changedBy: changedBy,
            changedByName: changedByName,
            transactionId: txId,
          );
        }
      }
    }

    return rowsAffected > 0;
  }

  /// Check if product has transaction history
  Future<bool> productHasTransactions(int productId) async {
    // Check sales invoice items
    final salesCount =
        await (selectOnly(salesInvoiceItems)
              ..addColumns([salesInvoiceItems.id.count()])
              ..where(salesInvoiceItems.productId.equals(productId)))
            .map((row) => row.read(salesInvoiceItems.id.count())!)
            .getSingle();
    if (salesCount > 0) return true;

    // Check purchase invoice items
    final purchaseCount =
        await (selectOnly(purchaseInvoiceItems)
              ..addColumns([purchaseInvoiceItems.id.count()])
              ..where(purchaseInvoiceItems.productId.equals(productId)))
            .map((row) => row.read(purchaseInvoiceItems.id.count())!)
            .getSingle();
    if (purchaseCount > 0) return true;

    // Check stock movements
    final movementCount =
        await (selectOnly(stockMovements)
              ..addColumns([stockMovements.id.count()])
              ..where(stockMovements.productId.equals(productId)))
            .map((row) => row.read(stockMovements.id.count())!)
            .getSingle();
    return movementCount > 0;
  }

  /// Delete a product (with transaction history check and soft-delete)
  Future<void> deleteProduct(int productId) async {
    final hasTransactions = await productHasTransactions(productId);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا المنتج - يوجد سجل معاملات مرتبط به. استخدم إلغاء التفعيل بدلاً من ذلك.',
      );
    }

    // Soft delete - mark as inactive instead of hard delete
    await (update(products)..where((p) => p.id.equals(productId))).write(
      const ProductsCompanion(isActive: Value(false)),
    );
    _productSearchCache.clear(); // Invalidate cache on write
  }

  /// Update product stock
  Future<void> updateProductStock(int productId, double newStock) async {
    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        currentStock: Value(newStock),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Without this the write lands on disk while every cached reader keeps
    // returning the old quantity. Its neighbour adjustProductStockGlobal has
    // always invalidated for exactly this reason — the omission here was an
    // oversight, and a costly one: this method is what
    // `reconciliation_service` calls (so the repair tool's own correction was
    // invisible to readers) and what `inventory_balance_sync_strategy` calls
    // on every client balance sync (silently undoing the "zero stock in POS"
    // fix for any product sitting in the cache).
    invalidateProductCache(productId);
  }

  /// Atomically adjust product stock (prevents race conditions)
  Future<void> adjustProductStockGlobal(int productId, double quantityDelta) async {
    await customUpdate(
      'UPDATE products SET current_stock = current_stock + ?, updated_at = CAST(strftime(\'%s\', \'now\') AS INTEGER) WHERE id = ?',
      variables: [Variable.withReal(quantityDelta), Variable.withInt(productId)],
      updates: {products},
    );
    // PERF: Invalidate cached product since currentStock changed
    invalidateProductCache(productId);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CATEGORY OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all active categories ordered by name
  Stream<List<Category>> watchAllCategories() {
    return (select(categories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.name),
          ]))
        .watch();
  }

  /// PIR R-10: Watch branch-specific categories
  Stream<List<Category>> watchCategoriesForBranch(int branchId) {
    // Join logic: Select categories that are global OR have a record in categoryBranches for this branch
    final query = select(categories).join([
      leftOuterJoin(categoryBranches,
          categoryBranches.categoryId.equalsExp(categories.id)),
    ]);

    query.where(categories.isActive.equals(true) &
        (categories.isGlobal.equals(true) |
            categoryBranches.branchId.equals(branchId)));

    // Ensure distinct categories (since one category might be linked to multiple branches, 
    // though the where clause filters for ONE branch, a category joined with other branches 
    // would still result in one row here).
    return query.watch().map((rows) {
      final List<Category> result = [];
      final Set<int> seenIds = {};
      for (final row in rows) {
        final cat = row.readTable(categories);
        if (seenIds.add(cat.id)) {
          result.add(cat);
        }
      }
      // Sort in memory (or use orderBy on the query if possible, but join + distinct + order is tricky in Drift)
      result.sort((a, b) {
        int cmp = a.sortOrder.compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
      return result;
    });
  }

  /// PIR R-10: Get branches linked to a category
  Future<List<int>> getCategoryBranchIds(int categoryId) async {
    final rows = await (select(categoryBranches)
          ..where((cb) => cb.categoryId.equals(categoryId)))
        .get();
    return rows.map((r) => r.branchId).toList();
  }

  /// PIR R-10: Update category branch links
  Future<void> setCategoryBranches(int categoryId, List<int> branchIds) async {
    await transaction(() async {
      // 1. Clear existing
      await (delete(categoryBranches)
            ..where((cb) => cb.categoryId.equals(categoryId)))
          .go();
      // 2. Insert new
      for (final bId in branchIds) {
        await into(categoryBranches).insert(
          CategoryBranchesCompanion.insert(
            categoryId: categoryId,
            branchId: bId,
          ),
        );
      }
    });
  }

  /// Get all active categories ordered by name (PERF: cached for 30 seconds)
  Future<List<Category>> getAllCategories() async {
    final now = DateTime.now();
    if (_categoriesCache != null &&
        _categoriesCacheTime != null &&
        now.difference(_categoriesCacheTime!) < const Duration(seconds: 30)) {
      return _categoriesCache!;
    }

    final result = await (select(categories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.name),
          ]))
        .get();

    _categoriesCache = result;
    _categoriesCacheTime = now;
    return result;
  }

  /// Invalidate category cache (call after insert/update/delete category)
  void invalidateCategoryCache() {
    _categoriesCache = null;
    _categoriesCacheTime = null;
  }

  /// Get category by ID
  Future<Category?> getCategoryById(int id) {
    return (select(
      categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  /// Insert a new category
  Future<int> insertCategory(CategoriesCompanion category) async {
    // UUID-First Phase 1 Slice 3: auto-mint if the caller didn't supply
    // a globalId, so every category row has stable cross-install identity.
    final hasGid = category.globalId.present &&
        (category.globalId.value?.isNotEmpty ?? false);
    final withGid = hasGid
        ? category
        : category.copyWith(globalId: Value(UuidV7.generate()));
    final id = await into(categories).insert(withGid);
    invalidateCategoryCache();
    return id;
  }

  /// Update a category
  Future<void> updateCategory({
    required int id,
    required String name,
    required String color,
  }) async {
    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(name: Value(name), color: Value(color)),
    );
    invalidateCategoryCache();
  }

  /// Count ACTIVE products currently assigned to a category. Used by the
  /// delete-category UI to pick between the empty-category confirm flow
  /// and the bulk-move-then-delete flow (Feature 045). Counts only
  /// `isActive=true` rows — soft-deactivated products don't block the
  /// category delete because they're already off the UI.
  Future<int> countActiveProductsInCategory(int categoryId) async {
    final cnt = products.id.count();
    final row = await (selectOnly(products)
          ..addColumns([cnt])
          ..where(products.categoryId.equals(categoryId) &
              products.isActive.equals(true)))
        .map((r) => r.read(cnt))
        .getSingle();
    return row ?? 0;
  }

  /// Count invoice items (sales + purchases) that reference products in
  /// the given category and were booked on the given branch.
  ///
  /// Field-report 2026-05-14: deletion is global (server propagates to
  /// every branch), but operators reported they need a heads-up if the
  /// to-be-deleted category was actively used on THEIR branch — losing
  /// it everywhere when only one branch is affected is a stronger
  /// destructive signal than the legacy "X active products" count.
  Future<int> countCategoryInvoicedItemsOnBranch(
    int categoryId,
    int branchId,
  ) async {
    // Raw SQL is the cleanest way to express "count items across two
    // unrelated parent tables filtered on the parent's branchId". Both
    // dialects (SQLite + PostgreSQL) accept this UNION ALL form.
    final result = await customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM sales_invoice_items sii
          JOIN sales_invoices si ON si.id = sii.invoice_id
          JOIN products p ON p.id = sii.product_id
          WHERE p.category_id = ? AND si.branch_id = ?) +
        (SELECT COUNT(*) FROM purchase_invoice_items pii
          JOIN purchase_invoices pi ON pi.id = pii.invoice_id
          JOIN products p ON p.id = pii.product_id
          WHERE p.category_id = ? AND pi.branch_id = ?) AS total
      ''',
      variables: [
        Variable.withInt(categoryId),
        Variable.withInt(branchId),
        Variable.withInt(categoryId),
        Variable.withInt(branchId),
      ],
    ).getSingle();
    return (result.data['total'] as int?) ?? 0;
  }

  /// Feature 045: Soft-delete a category, optionally bulk-moving its
  /// active products to a destination category first.
  ///
  /// Old behaviour (pre-v128) was a HARD DELETE preceded by a "move
  /// products to the FIRST category" step. Two real bugs flowed from that:
  ///
  ///   1. **Resurrection across users** — the UI dialog claimed
  ///      "سيتم نقل الأصناف للتصنيف الافتراضي" but `(select(categories)
  ///      ..limit(1))` returned an arbitrary row, not the actual default.
  ///      Then the DELETE made the row vanish; on the next DeltaPull from
  ///      a server that still held it, the row was re-inserted and the
  ///      "deleted" category reappeared for whoever logged in next. The
  ///      original field report: "بدخل بمستخدم تانى بلاقى التصنيفات
  ///      اللى حذفتها بتظهر للمستخدم التانى".
  ///   2. **Orphan FKs** — when the chosen "default" was the category
  ///      being deleted itself, the move was skipped and the products
  ///      ended up referencing a deleted row.
  ///
  /// Post-v128 behaviour:
  ///   - The caller explicitly picks the destination (`moveToCategoryId`
  ///     can be a real id or null — null = "بدون تصنيف" since
  ///     `Products.categoryId` is nullable).
  ///   - The whole operation runs in a single transaction.
  ///   - Category is soft-deleted (`isActive=false` + `deletedAt=NOW()`)
  ///     so the next DeltaPull's `CategorySyncStrategy` honours the
  ///     deletion via its `isActive=false` write (line 64 of that file).
  ///   - The pre-flight count check is the **caller's** responsibility
  ///     (`countActiveProductsInCategory`) — the DAO no longer guesses a
  ///     default. We still defensively move ALL active products keyed by
  ///     `categoryId` here so a race-window create between the count and
  ///     this call doesn't orphan a new product.
  /// يفعّل «السماح بالبيع بالسالب» على كل الأصناف النشطة في نقلة واحدة.
  ///
  /// ── ليه ده محتاج وجود، والإعداد العام موجود؟ ─────────────────────────
  /// إعداد `enable_negative_sales` بيتعمله OR مع علم الصنف في المسارات
  /// الحرجة (حارس `cart_controller.addItem`، كارت الصنف، `accounting_validator`)،
  /// لكن **مش في كل مكان**: `ProductEntity.isOutOfStock` جيتر خالص مبيعرفش
  /// حاجة عن الإعداد العام، و`product_list_tile` بيحسب نفاد المخزون من
  /// المخزون بس. يعني تشغيل الإعداد كان بيسمح بالبيع فعلاً لكن الواجهة في
  /// أماكن تفضل مصرّة إن الصنف «غير متوفر».
  ///
  /// تنزيل القيمة على الأصناف نفسها بيوحّد كل القُرّاء على مصدر واحد بدل
  /// الاعتماد على إن كل موضع قراءة يفتكر يعمل OR.
  ///
  /// **اتجاه واحد عن قصد:** بيفعّل ولا بيعطّل. إلغاء التفعيل الجماعي كان
  /// هيمسح كل علم اتحدّد يدوياً على صنف بعينه — قرار المستخدم ده مش بتاعنا
  /// نلغيه. اللي عايز يقفلها لصنف يقفلها من شاشة الصنف.
  ///
  /// بيرجع عدد الصفوف اللي اتغيّرت فعلاً (الأصناف اللي كانت مفعّلة أصلاً
  /// مش محسوبة)، عشان الواجهة تقول للمستخدم إيه اللي حصل بالظبط.
  Future<int> enableNegativeSaleOnAllProducts() async {
    return (update(products)
          ..where((p) =>
              p.isActive.equals(true) & p.allowNegativeSale.equals(false)))
        .write(const ProductsCompanion(allowNegativeSale: Value(true)));
  }

  Future<void> deleteCategory(
    int categoryId, {
    int? moveToCategoryId,
  }) async {
    if (moveToCategoryId != null && moveToCategoryId == categoryId) {
      throw ArgumentError(
        'moveToCategoryId must differ from the category being deleted',
      );
    }
    await transaction(() async {
      // 1. Re-target active products (idempotent: rows already on
      //    `moveToCategoryId` aren't touched). When `moveToCategoryId`
      //    is null, products land on "بدون تصنيف" (categoryId NULL) —
      //    valid because Products.categoryId is nullable.
      await (update(products)
            ..where((p) =>
                p.categoryId.equals(categoryId) & p.isActive.equals(true)))
          .write(ProductsCompanion(categoryId: Value(moveToCategoryId)));

      // 2. Soft-delete the category itself. The schema's `isActive` +
      //    `deletedAt` columns have been in place since v100 but the
      //    delete path bypassed them (HARD DELETE) — fixed here.
      await (update(categories)..where((c) => c.id.equals(categoryId)))
          .write(CategoriesCompanion(
        isActive: const Value(false),
        deletedAt: Value(DateTime.now()),
        lastModifiedAt: Value(DateTime.now()),
      ));
    });
    invalidateCategoryCache();
  }

  /// Get category by name
  Future<Category?> getCategoryByName(String name) {
    return (select(categories)
          ..where((c) => c.name.equals(name) & c.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get or create category by name
  Future<int> getOrCreateCategory(String name) async {
    final trimmed = name.trim();
    final existing = await getCategoryByName(trimmed);
    if (existing != null) return existing.id;

    return insertCategory(
      CategoriesCompanion.insert(name: trimmed, isActive: const Value(true)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LOW STOCK & ALERTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch products that are at or below minimum stock
  Stream<List<Product>> watchLowStockProducts() {
    return customSelect(
      'SELECT * FROM products WHERE is_active = 1 AND min_stock > 0 AND current_stock <= min_stock AND track_inventory = 1',
      readsFrom: {products},
    ).watch().map((rows) => rows.map((row) => products.map(row.data)).toList());
  }

  /// Get count of low stock products
  Future<int> getLowStockCount() async {
    final result = await customSelect(
      'SELECT COUNT(*) as count FROM products WHERE is_active = 1 AND current_stock <= min_stock AND track_inventory = 1',
      readsFrom: {products},
    ).getSingle();
    return result.data['count'] as int? ?? 0;
  }
}

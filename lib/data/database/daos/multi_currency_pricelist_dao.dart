part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRICE LISTS DAO — قوائم الأسعار
// ═══════════════════════════════════════════════════════════════════════════
// NOTE: Currency management is handled by MultiCurrencyDao in multi_currency_dao.dart
//       Currency seeding is handled by seedDefaultCurrencies in commercial_finance_dao (original)

extension PriceListsDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // PRICE LISTS (قوائم الأسعار)
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all price lists
  Stream<List<PriceListData>> watchPriceLists() {
    return (select(
      priceLists,
    )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  }

  /// Get active price lists
  Future<List<PriceListData>> getActivePriceLists() {
    final now = DateTime.now();
    return (select(priceLists)
          ..where((p) => p.isActive.equals(true))
          ..where(
            (p) =>
                p.startDate.isNull() |
                p.startDate.isSmallerOrEqual(Variable(now)),
          )
          ..where(
            (p) =>
                p.endDate.isNull() | p.endDate.isBiggerOrEqual(Variable(now)),
          ))
        .get();
  }

  /// Create a price list
  Future<int> createPriceList({
    required String name,
    required String code,
    bool isDefault = false,
    int? currencyId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (isDefault) {
      await (update(priceLists)).write(const PriceListsCompanion(isDefault: Value(false)));
    }
    final gid = UuidV7.generate();
    final data = {
      'globalId': gid,
      'name': name,
      'code': code,
      'isDefault': isDefault,
      'currencyId': currencyId,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createPriceList(data);
      if (serverId != null) return serverId;
    }
    return into(priceLists).insert(
      PriceListsCompanion.insert(
        name: name,
        code: code,
        isDefault: Value(isDefault),
        currencyId: Value(currencyId),
        startDate: Value(startDate),
        endDate: Value(endDate),
        globalId: Value(gid),
      ),
    );
  }

  /// Update an existing price list
  Future<int> updatePriceList(
    int id, {
    String? name,
    bool? isActive,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updatePriceList(id, {
        'name': ?name,
        'isActive': ?isActive,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      });
    }
    return (update(priceLists)..where((p) => p.id.equals(id))).write(
      PriceListsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        startDate: startDate != null ? Value(startDate) : const Value.absent(),
        endDate: endDate != null ? Value(endDate) : const Value.absent(),
      ),
    );
  }

  /// Set prices for products in a price list
  Future<void> setPriceListItem({
    required int priceListId,
    required int productId,
    required double price,
    double minQuantity = 1,
    double maxDiscount = 0,
  }) async {
    final gid = UuidV7.generate();
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.setPriceListItem({
        'globalId': gid,
        'priceListId': priceListId,
        'productId': productId,
        'price': price,
        'minQuantity': minQuantity,
        'maxDiscount': maxDiscount,
      });
    }
    // Upsert: delete existing then insert
    await (delete(priceListItems)
          ..where((i) => i.priceListId.equals(priceListId) & i.productId.equals(productId)))
        .go();
    await into(priceListItems).insert(
      PriceListItemsCompanion.insert(
        priceListId: priceListId,
        productId: productId,
        price: price,
        minQuantity: Value(minQuantity),
        maxDiscount: Value(maxDiscount),
        globalId: Value(gid),
      ),
    );
  }

  /// Bulk set prices for a price list (from a map of productId → price)
  Future<void> bulkSetPriceListItems(
    int priceListId,
    Map<int, double> prices,
  ) async {
    await transaction(() async {
      for (final entry in prices.entries) {
        await setPriceListItem(
          priceListId: priceListId,
          productId: entry.key,
          price: entry.value,
        );
      }
    });
  }

  /// Get all items in a price list
  Future<List<PriceListItemData>> getPriceListItems(int priceListId) {
    return (select(
      priceListItems,
    )..where((i) => i.priceListId.equals(priceListId))).get();
  }

  /// Get the price of a specific product from a price list
  Future<double?> getProductPriceFromList(
    int priceListId,
    int productId, {
    double quantity = 1,
  }) async {
    final item =
        await (select(priceListItems)
              ..where(
                (i) =>
                    i.priceListId.equals(priceListId) &
                    i.productId.equals(productId),
              )
              ..where((i) => i.minQuantity.isSmallerOrEqual(Variable(quantity)))
              ..orderBy([(i) => OrderingTerm.desc(i.minQuantity)])
              ..limit(1))
            .getSingleOrNull();

    return item?.price;
  }

  /// Resolve the best price for a product considering a party's price list
  Future<double> resolveProductPrice(
    int productId, {
    int? partyId,
    double quantity = 1,
  }) async {
    // 1. Try party-specific price list (if party has one assigned)
    final activeLists = await getActivePriceLists();

    for (final list in activeLists) {
      final price = await getProductPriceFromList(
        list.id,
        productId,
        quantity: quantity,
      );
      if (price != null) return price;
    }

    // 2. Fallback: product's default sale price
    final product = await (select(
      products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    return product?.salePrice ?? 0;
  }

  /// Delete a price list item
  Future<int> deletePriceListItem(int priceListId, int productId) {
    return (delete(priceListItems)..where(
          (i) =>
              i.priceListId.equals(priceListId) & i.productId.equals(productId),
        ))
        .go();
  }

  /// Seed default price lists
  Future<void> seedDefaultPriceLists() async {
    final count =
        await (selectOnly(priceLists)..addColumns([priceLists.id.count()]))
            .map((row) => row.read(priceLists.id.count()))
            .getSingle();

    if ((count ?? 0) > 0) return;

    final defaults = [
      {'name': 'سعر التجزئة', 'code': 'RETAIL', 'default': true},
      {'name': 'سعر الجملة', 'code': 'WHOLESALE', 'default': false},
      {'name': 'سعر نصف الجملة', 'code': 'SEMI_WHOLESALE', 'default': false},
      {'name': 'سعر خاص', 'code': 'SPECIAL', 'default': false},
    ];

    for (final pl in defaults) {
      await into(priceLists).insert(
        PriceListsCompanion.insert(
          name: pl['name'] as String,
          code: pl['code'] as String,
          isDefault: Value(pl['default'] as bool),
          // UUID-First Phase 1 Slice 3: seeded price lists get stable UUID.
          globalId: Value(UuidV7.generate()),
        ),
      );
    }
  }
}

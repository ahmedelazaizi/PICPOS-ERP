part of '../database.dart';


extension QuotationsDao on AppDatabase {



  Stream<List<QuotationData>> watchAllQuotations() {
    return (select(
      quotations,
    )..orderBy([(t) => OrderingTerm.desc(t.quotationDate)])).watch();
  }

  Future<QuotationData?> getQuotationById(int id) {
    return (select(
      quotations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<QuotationItem>> getQuotationItems(int quotationId) {
    return (select(quotationItems)
          ..where((t) => t.quotationId.equals(quotationId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<int> insertQuotation(
    QuotationsCompanion quotation,
    List<QuotationItemsCompanion> items,
  ) async {
    final qHasGid = quotation.globalId.present &&
        (quotation.globalId.value?.isNotEmpty ?? false);
    final quotationGid = qHasGid ? quotation.globalId.value! : UuidV7.generate();
    final quotationWithGid = qHasGid ? quotation : quotation.copyWith(globalId: Value(quotationGid));

    if (SyncInterceptor.isClientMode) {
      T? readV<T>(Value<T> v, [T? fallback]) => v.present ? v.value : fallback;
      final qData = {
        'globalId': quotationGid,
        'customerId': readV(quotation.customerId),
        'warehouseId': readV(quotation.warehouseId),
        'userId': readV(quotation.userId),
        'quotationDate': readV(quotation.quotationDate)?.toIso8601String(),
        'validityDate': readV(quotation.validityDate)?.toIso8601String(),
        'subtotal': readV(quotation.subtotal) ?? 0.0,
        'discount': readV(quotation.discount) ?? 0.0,
        'tax': readV(quotation.tax) ?? 0.0,
        'total': readV(quotation.total) ?? 0.0,
        'notes': readV(quotation.notes),
        'status': readV(quotation.status) ?? 'draft',
      };
      final itemMaps = items.map((item) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        return {
          'globalId': hasGid ? item.globalId.value : UuidV7.generate(),
          'productId': item.productId.value,
          'quantity': item.quantity.value,
          'unitPrice': item.unitPrice.value,
          'discount': item.discount.present ? item.discount.value : 0.0,
          'total': item.total.value,
        };
      }).toList();
      final serverId = await SyncInterceptor.instance?.createQuotation(qData, itemMaps);
      if (serverId != null) return serverId;
    }

    return transaction(() async {
      final quotationId = await into(quotations).insert(quotationWithGid);
      for (var item in items) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        final itemWithGid = hasGid
            ? item.copyWith(quotationId: Value(quotationId))
            : item.copyWith(quotationId: Value(quotationId), globalId: Value(UuidV7.generate()));
        await into(quotationItems).insert(itemWithGid);
      }
      return quotationId;
    });
  }

  Future<void> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  }) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updateQuotationStatus(
        id,
        status,
        convertedInvoiceId: convertedInvoiceId,
      );
    }
    await (update(quotations)..where((t) => t.id.equals(id))).write(
      QuotationsCompanion(
        status: Value(status),
        convertedToInvoiceId: convertedInvoiceId != null
            ? Value(convertedInvoiceId)
            : const Value.absent(),
      ),
    );
  }

  Future<void> deleteQuotation(int id) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteQuotation(id);
    }
    await (delete(quotations)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteQuotationAndItems(int id) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteQuotation(id);
    }
    await transaction(() async {
      await (delete(quotationItems)..where((t) => t.quotationId.equals(id))).go();
      await (delete(quotations)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<int> updateFullQuotation(
    int id,
    QuotationsCompanion quotation,
    List<QuotationItemsCompanion> items,
  ) async {
    if (SyncInterceptor.isClientMode) {
      T? readV<T>(Value<T> v, [T? fallback]) => v.present ? v.value : fallback;
      final qData = <String, dynamic>{
        if (quotation.customerId.present) 'customerId': readV(quotation.customerId),
        if (quotation.warehouseId.present) 'warehouseId': readV(quotation.warehouseId),
        if (quotation.userId.present) 'userId': readV(quotation.userId),
        if (quotation.quotationDate.present)
          'quotationDate': readV(quotation.quotationDate)?.toIso8601String(),
        if (quotation.validityDate.present)
          'validityDate': readV(quotation.validityDate)?.toIso8601String(),
        if (quotation.subtotal.present) 'subtotal': readV(quotation.subtotal),
        if (quotation.discount.present) 'discount': readV(quotation.discount),
        if (quotation.tax.present) 'tax': readV(quotation.tax),
        if (quotation.total.present) 'total': readV(quotation.total),
        if (quotation.notes.present) 'notes': readV(quotation.notes),
        if (quotation.status.present) 'status': readV(quotation.status),
      };
      final itemMaps = items.map((item) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        return {
          'globalId': hasGid ? item.globalId.value : UuidV7.generate(),
          'productId': item.productId.value,
          'quantity': item.quantity.value,
          'unitPrice': item.unitPrice.value,
          'discount': item.discount.present ? item.discount.value : 0.0,
          'total': item.total.value,
        };
      }).toList();
      await SyncInterceptor.instance?.updateQuotation(id, qData, itemMaps);
    }

    return transaction(() async {
      await (update(
        quotations,
      )..where((t) => t.id.equals(id))).write(quotation);
      await (delete(
        quotationItems,
      )..where((t) => t.quotationId.equals(id))).go();
      for (var item in items) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        final itemWithGid = hasGid
            ? item.copyWith(quotationId: Value(id))
            : item.copyWith(quotationId: Value(id), globalId: Value(UuidV7.generate()));
        await into(quotationItems).insert(itemWithGid);
      }
      return id;
    });
  }

  Future<List<QuotationDto>> getQuotationsPaginated({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    final query = select(quotations).join([
      leftOuterJoin(parties, parties.id.equalsExp(quotations.customerId)),
      leftOuterJoin(users, users.id.equalsExp(quotations.userId)),
    ]);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final searchExp = '%$searchQuery%';
      query.where(
        quotations.quotationNumber.like(searchExp) |
            parties.name.like(searchExp),
      );
    }

    if (startDate != null && endDate != null) {
      query.where(quotations.quotationDate.isBetweenValues(startDate, endDate));
    }

    if (status != null && status != 'all') {
      query.where(quotations.status.equals(status));
    }

    query.orderBy([OrderingTerm.desc(quotations.quotationDate)]);
    query.limit(limit, offset: offset);

    final result = await query.get();

    return result.map((row) {
      return QuotationDto(
        quotation: row.readTable(quotations),
        customerName: row.readTableOrNull(parties)?.name,
        userName: row.readTableOrNull(users)?.displayName ?? 'غير معروف',
      );
    }).toList();
  }

  Future<QuotationWithDetailsDto?> getQuotationWithDetails(int id) async {
    final qQuery = select(quotations).join([
      leftOuterJoin(parties, parties.id.equalsExp(quotations.customerId)),
      leftOuterJoin(users, users.id.equalsExp(quotations.userId)),
    ])..where(quotations.id.equals(id));

    final qResult = await qQuery.getSingleOrNull();
    if (qResult == null) return null;

    final qData = qResult.readTable(quotations);

    final itemsQuery = select(quotationItems).join([
      // Assuming a products table exists, but we don't have it in the @DriftAccessor yet.
      // So we'll just return the item without joining products for now, or we can add Products to the accessor.
    ])..where(quotationItems.quotationId.equals(id));

    final itemsResult = await itemsQuery.get();

    final itemsList = itemsResult.map((row) {
      return QuotationItemDto(
        item: row.readTable(quotationItems),
        productName:
            'صنف ${row.readTable(quotationItems).productId}', // Placeholder
        productCode: null,
      );
    }).toList();

    return QuotationWithDetailsDto(
      quotation: qData,
      customerName: qResult.readTableOrNull(parties)?.name,
      userName: qResult.readTableOrNull(users)?.displayName ?? 'غير معروف',
      items: itemsList,
    );
  }
}

class QuotationDto {
  final QuotationData quotation;
  final String? customerName;
  final String userName;
  QuotationDto({
    required this.quotation,
    this.customerName,
    required this.userName,
  });
}

class QuotationWithDetailsDto {
  final QuotationData quotation;
  final String? customerName;
  final String userName;
  final List<QuotationItemDto> items;
  QuotationWithDetailsDto({
    required this.quotation,
    this.customerName,
    required this.userName,
    required this.items,
  });
}

class QuotationItemDto {
  final QuotationItem item;
  final String? productName;
  final String? productCode;
  QuotationItemDto({required this.item, this.productName, this.productCode});
}

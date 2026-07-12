import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/quotation_entity.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/repositories/i_quotations_repository.dart';
import '../database/database.dart';

class DriftQuotationsRepository implements IQuotationsRepository {
  final AppDatabase _db;

  DriftQuotationsRepository(this._db);

  @override
  Future<List<QuotationEntity>> getQuotationsPaginated({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? status,
  }) async {
    final dtos = await _db.getQuotationsPaginated(
      limit: limit,
      offset: offset,
      searchQuery: searchQuery,
      startDate: dateRange?.start,
      endDate: dateRange?.end,
      status: status,
    );

    return dtos.map(_mapDtoToEntity).toList();
  }

  @override
  Future<QuotationEntity?> getQuotationWithDetails(int id) async {
    final dto = await _db.getQuotationWithDetails(id);
    if (dto == null) return null;

    return _mapWithDetailsDtoToEntity(dto);
  }

  @override
  Future<int> saveQuotation({
    required List<CartItemEntity> items,
    required int? customerId,
    int? warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
  }) async {
    final now = DateTime.now();
    final dateStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    
    // Simple counter for demonstration, better to use a sequence in DB
    final count = await (_db.selectOnly(_db.quotations)
          ..addColumns([_db.quotations.id.count()]))
        .map((row) => row.read(_db.quotations.id.count()))
        .getSingle();
        
    final quotationNumber = "Q-$dateStr-${(count ?? 0) + 1}";

    final quotation = QuotationsCompanion.insert(
      quotationNumber: quotationNumber,
      customerId: Value(customerId),
      warehouseId: warehouseId ?? 1, // Default warehouse fallback
      userId: userId,
      quotationDate: now,
      validityDate: Value(now.add(const Duration(days: 7))),
      subtotal: Value(subtotal),
      discount: Value(discount),
      tax: Value(tax),
      total: Value(total),
      notes: Value(notes),
      status: const Value('draft'),
    );

    final itemCompanions = items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return QuotationItemsCompanion.insert(
        quotationId: 0, 
        productId: item.productId,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discount: Value(item.discountPercent),
        total: item.total,
        taxRate: Value(item.taxRate),
        taxAmount: Value(item.taxAmount),
        note: Value(item.note),
        sortOrder: Value(index),
      );
    }).toList();

    return _db.insertQuotation(quotation, itemCompanions);
  }

  @override
  Future<void> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  }) {
    return _db.updateQuotationStatus(
      id,
      status,
      convertedInvoiceId: convertedInvoiceId,
    );
  }

  @override
  Future<void> deleteQuotation(int id) {
    return _db.deleteQuotation(id);
  }

  @override
  Future<void> deleteQuotationAndItems(int id) {
    return _db.deleteQuotationAndItems(id);
  }

  @override
  Future<void> updateFullQuotation({
    required int id,
    required List<CartItemEntity> items,
    required int? customerId,
    int? warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
    required String status,
  }) async {
    final quotation = QuotationsCompanion(
      id: Value(id),
      customerId: Value(customerId),
      warehouseId: Value(warehouseId ?? 1), // Default warehouse fallback
      userId: Value(userId),
      subtotal: Value(subtotal),
      discount: Value(discount),
      tax: Value(tax),
      total: Value(total),
      notes: Value(notes),
      status: Value(status),
    );

    final itemCompanions = items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return QuotationItemsCompanion.insert(
        quotationId: id,
        productId: item.productId,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discount: Value(item.discountPercent),
        total: item.total,
        taxRate: Value(item.taxRate),
        taxAmount: Value(item.taxAmount),
        note: Value(item.note),
        sortOrder: Value(index),
      );
    }).toList();

    await _db.updateFullQuotation(id, quotation, itemCompanions);
  }

  QuotationEntity _mapDtoToEntity(QuotationDto dto) {
    return QuotationEntity(
      id: dto.quotation.id,
      quotationNumber: dto.quotation.quotationNumber,
      customerId: dto.quotation.customerId,
      warehouseId: dto.quotation.warehouseId,
      userId: dto.quotation.userId,
      quotationDate: dto.quotation.quotationDate,
      validityDate:
          dto.quotation.validityDate ??
          dto.quotation.quotationDate.add(const Duration(days: 7)),
      subtotal: dto.quotation.subtotal,
      discount: dto.quotation.discount,
      tax: dto.quotation.tax,
      total: dto.quotation.total,
      notes: dto.quotation.notes,
      status: dto.quotation.status,
      customerName: dto.customerName,
      userName: dto.userName,
    );
  }

  QuotationEntity _mapWithDetailsDtoToEntity(QuotationWithDetailsDto dto) {
    return QuotationEntity(
      id: dto.quotation.id,
      quotationNumber: dto.quotation.quotationNumber,
      customerId: dto.quotation.customerId,
      warehouseId: dto.quotation.warehouseId,
      userId: dto.quotation.userId,
      quotationDate: dto.quotation.quotationDate,
      validityDate:
          dto.quotation.validityDate ??
          dto.quotation.quotationDate.add(const Duration(days: 7)),
      subtotal: dto.quotation.subtotal,
      discount: dto.quotation.discount,
      tax: dto.quotation.tax,
      total: dto.quotation.total,
      notes: dto.quotation.notes,
      status: dto.quotation.status,
      customerName: dto.customerName,
      userName: dto.userName,
      items: dto.items.map(_mapItemDtoToEntity).toList(),
    );
  }

  QuotationItemEntity _mapItemDtoToEntity(QuotationItemDto dto) {
    return QuotationItemEntity(
      id: dto.item.id,
      quotationId: dto.item.quotationId,
      productId: dto.item.productId,
      quantity: dto.item.quantity,
      unitPrice: dto.item.unitPrice,
      discount: dto.item.discount,
      total: dto.item.total,
      taxRate: dto.item.taxRate,
      taxAmount: dto.item.taxAmount,
      note: dto.item.note,
      productName: dto.productName,
      productCode: dto.productCode,
    );
  }
}

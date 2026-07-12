import 'package:flutter/material.dart';
import '../entities/quotation_entity.dart';
import '../entities/cart_item_entity.dart';

abstract class IQuotationsRepository {
  /// Fetch paginated quotations with joined data
  Future<List<QuotationEntity>> getQuotationsPaginated({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? status,
  });

  /// Fetch a single quotation with all items
  Future<QuotationEntity?> getQuotationWithDetails(int id);

  /// Save a new quotation
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
  });

  /// Update quotation status (e.g. to 'converted')
  Future<void> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  });

  /// Delete only the quotation record
  Future<void> deleteQuotation(int id);

  /// Delete quotation and all its items (Cascade delete)
  Future<void> deleteQuotationAndItems(int id);

  /// Update an existing quotation and its items
  Future<void> updateFullQuotation({
    required int id,
    required List<CartItemEntity> items,
    required int? customerId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
    required String status,
  });
}

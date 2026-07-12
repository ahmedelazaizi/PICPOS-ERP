import 'package:flutter/material.dart';
import '../../domain/entities/quotation_entity.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/repositories/i_quotations_repository.dart';

class WebQuotationsRepository implements IQuotationsRepository {
  @override
  Future<List<QuotationEntity>> getQuotationsPaginated({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? status,
  }) async {
    return [];
  }

  @override
  Future<QuotationEntity?> getQuotationWithDetails(int id) async {
    return null;
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
    return 0;
  }

  @override
  Future<void> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  }) async {}

  @override
  Future<void> deleteQuotation(int id) async {}

  @override
  Future<void> deleteQuotationAndItems(int id) async {}

  @override
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
  }) async {}
}

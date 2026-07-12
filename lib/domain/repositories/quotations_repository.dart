import '../entities/quotation_entity.dart';

abstract class IQuotationsRepository {
  /// Fetches a paginated list of quotations
  Future<List<QuotationEntity>> getQuotations({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  });

  /// Fetches a single quotation by ID with its items
  Future<QuotationEntity?> getQuotationById(int id);

  /// Marks a quotation as converted
  Future<void> markAsConverted(int id);

  /// Deletes a quotation
  Future<void> deleteQuotation(int id);
}

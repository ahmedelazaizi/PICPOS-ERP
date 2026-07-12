import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/usecases/quotations/create_quotation_usecase.dart';
import 'repository_providers.dart';

/// Provider for CreateQuotationUseCase
final createQuotationUseCaseProvider = Provider<CreateQuotationUseCase>((ref) {
  final repo = ref.watch(quotationsRepositoryProvider);
  return CreateQuotationUseCase(repo);
});

/// Provider for ConvertQuotationUseCase
final convertQuotationUseCaseProvider =
    Provider<ConvertQuotationUseCase>((ref) {
  final repo = ref.watch(quotationsRepositoryProvider);
  return ConvertQuotationUseCase(repo);
});

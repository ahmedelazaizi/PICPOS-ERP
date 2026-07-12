import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart'; // To access databaseProvider
import 'repository_providers.dart';
import '../../domain/usecases/purchases/save_purchase_usecase.dart';

/// Provider for PurchasesRepository
// purchasesRepositoryProvider moved to repository_providers.dart

/// Provider for SavePurchaseUseCase
final savePurchaseUseCaseProvider = Provider<SavePurchaseUseCase>((ref) {
  final repository = ref.watch(purchasesRepositoryProvider);
  return SavePurchaseUseCase(repository);
});

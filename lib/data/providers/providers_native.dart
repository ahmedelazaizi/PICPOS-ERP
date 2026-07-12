// Native-only providers (for desktop platforms)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../services/excel_service.dart';
import 'repository_providers.dart';

/// Native database provider (desktop only)
final nativeDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // DO NOT CALL db.close() here for the singleton instance.
  return db;
});

/// Excel service provider (desktop only)
final nativeExcelServiceProvider = Provider<ExcelService>((ref) {
  final productRepo = ref.watch(productRepositoryProvider);
  final partyRepo = ref.watch(partiesRepositoryProvider);
  final branchRepo = ref.watch(branchRepositoryProvider);
  final purchasesRepo = ref.watch(purchasesRepositoryProvider);
  final modifierRepo = ref.watch(modifierRepositoryProvider);
  final inventoryRepo = ref.watch(inventoryRepositoryProvider);
  return ExcelService(
    productRepo,
    partyRepo,
    branchRepo,
    purchasesRepo,
    modifierRepo: modifierRepo,
    inventoryRepo: inventoryRepo,
  );
});

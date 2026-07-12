import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/database.dart' as db;
import '../../../domain/repositories/landed_cost_repository.dart';
import '../../../data/providers/repository_providers.dart';

class LandedCostState {
  final List<db.LandedCostSheetData> sheets;
  final db.LandedCostSheetData? selectedSheet;
  final List<db.LandedCostItemData> costItems;
  final List<Map<String, dynamic>> allocations;
  final bool isLoading;

  /// S-COST (Spec 144 / R2): true while a landed-cost sheet is being applied —
  /// gates the apply button so a double-tap cannot post the entry twice.
  final bool isApplying;

  LandedCostState({
    this.sheets = const [],
    this.selectedSheet,
    this.costItems = const [],
    this.allocations = const [],
    this.isLoading = true,
    this.isApplying = false,
  });

  LandedCostState copyWith({
    List<db.LandedCostSheetData>? sheets,
    db.LandedCostSheetData? selectedSheet,
    List<db.LandedCostItemData>? costItems,
    List<Map<String, dynamic>>? allocations,
    bool? isLoading,
    bool? isApplying,
  }) {
    return LandedCostState(
      sheets: sheets ?? this.sheets,
      selectedSheet: selectedSheet ?? this.selectedSheet,
      costItems: costItems ?? this.costItems,
      allocations: allocations ?? this.allocations,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
    );
  }
}

class LandedCostController extends Notifier<LandedCostState> {
  @override
  LandedCostState build() {
    Future.microtask(() => _loadSheets());
    return LandedCostState();
  }

  ILandedCostRepository get _repo => ref.read(landedCostRepositoryProvider);

  Future<void> _loadSheets() async {
    try {
      final sheets = await _repo.getLandedCostSheets();

      List<db.LandedCostItemData>? items;
      List<Map<String, dynamic>>? allocs;
      if (state.selectedSheet != null) {
        items = await _repo.getLandedCostItems(state.selectedSheet!.id);
        allocs = await _repo.getAllocationsWithDetails(state.selectedSheet!.id);
      }

      state = state.copyWith(
        sheets: sheets,
        costItems: items ?? state.costItems,
        allocations: allocs ?? state.allocations,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[LandedCost] Load error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() => _loadSheets();

  /// R2 double-submission guard for the apply flow.
  void setApplying(bool value) =>
      state = state.copyWith(isApplying: value);

  Future<void> selectSheet(db.LandedCostSheetData sheet) async {
    state = state.copyWith(isLoading: true);
    try {
      final items = await _repo.getLandedCostItems(sheet.id);
      final allocs = await _repo.getAllocationsWithDetails(sheet.id);
      state = state.copyWith(
        selectedSheet: sheet,
        costItems: items,
        allocations: allocs,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[LandedCost] Select sheet error: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final landedCostControllerProvider = NotifierProvider<LandedCostController, LandedCostState>(() {
  return LandedCostController();
});

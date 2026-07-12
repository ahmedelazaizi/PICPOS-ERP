import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../domain/entities/stock_requisition_entity.dart';
import '../../../../../data/providers/providers.dart';
import '../../../../../domain/entities/stock_requisition_item_entity.dart';
import '../../../../../core/enums/requisition_status.dart';
import '../../../../../core/utils/friendly_error.dart';

// State definition
class StockRequisitionsState {
  final bool isLoading;
  final List<StockRequisitionEntity> requisitions;
  final List<StockRequisitionEntity> filteredRequisitions;
  final String searchQuery;
  final DateTimeRange? dateRange;
  final String statusFilter; // 'all', 'pending', 'approved', 'rejected', 'fulfilled'
  // Spec 148 (R2) — ids with an in-flight approve/reject, so a double-tap is a
  // no-op and the heavy approval (which creates a transfer) runs exactly once.
  final Set<int> processingIds;

  StockRequisitionsState({
    this.isLoading = true,
    this.requisitions = const [],
    this.filteredRequisitions = const [],
    this.searchQuery = '',
    this.dateRange,
    this.statusFilter = 'all',
    this.processingIds = const {},
  });

  StockRequisitionsState copyWith({
    bool? isLoading,
    List<StockRequisitionEntity>? requisitions,
    List<StockRequisitionEntity>? filteredRequisitions,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? statusFilter,
    Set<int>? processingIds,
  }) {
    return StockRequisitionsState(
      isLoading: isLoading ?? this.isLoading,
      requisitions: requisitions ?? this.requisitions,
      filteredRequisitions: filteredRequisitions ?? this.filteredRequisitions,
      searchQuery: searchQuery ?? this.searchQuery,
      dateRange: dateRange ?? this.dateRange,
      statusFilter: statusFilter ?? this.statusFilter,
      processingIds: processingIds ?? this.processingIds,
    );
  }
}

// Controller definition
class StockRequisitionsController extends Notifier<StockRequisitionsState> {
  StreamSubscription? _subscription;

  @override
  StockRequisitionsState build() {
    // Keep subscription alive across states but clean up on dispose
    ref.onDispose(() {
      _subscription?.cancel();
    });
    
    // Defer initialization to avoid modifying state during build
    Future.microtask(() => _init());
    
    return StockRequisitionsState();
  }

  void _init() {
    _subscription?.cancel();
    
    // Watch all requisitions from the repository
    _subscription = ref
        .read(inventoryRepositoryProvider)
        .watchAllStockRequisitions(startDate: state.dateRange?.start, endDate: state.dateRange?.end)
        .listen((data) {
        // Notifier doesn't have `mounted`, but ref.onDispose handles cleanup
        // We just need to check if the state is still accessible.
        // If not, it means the provider was disposed.
      state = state.copyWith(
        isLoading: false,
        requisitions: data,
      );
      _applyFilters();
    });
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
  }

  void updateDateRange(DateTimeRange? range) {
    state = state.copyWith(dateRange: range, isLoading: true);
    _init(); // Re-initialize stream with new date bounds
  }

  void updateStatusFilter(String status) {
    state = state.copyWith(statusFilter: status);
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = state.requisitions;

    // Apply status filter
    if (state.statusFilter != 'all') {
      // Spec 148 — compare canonical DB strings; the enum can never == a raw
      // string (the old defect made this filter always empty).
      filtered = filtered
          .where((req) => statusToDb(req.status) == state.statusFilter)
          .toList();
    }

    // Apply search query
    if (state.searchQuery.isNotEmpty) {
      final q = state.searchQuery.toLowerCase();
      filtered = filtered.where((req) {
        return req.requisitionNumber.toLowerCase().contains(q) ||
               (req.fromBranchName?.toLowerCase().contains(q) ?? false) ||
               (req.toBranchName?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    state = state.copyWith(filteredRequisitions: filtered);
  }

  /// Returns null on success, or a user-facing Arabic error message on failure
  /// (BUG-U18: surface the real reason instead of a generic toast).
  Future<String?> createRequisition({
    required int fromBranchId,
    required int toBranchId,
    required String notes,
    required List<StockRequisitionItemEntity> items,
  }) async {
    try {
      final authState = ref.read(authProvider);
      final user = authState.effectiveUser;
      if (user == null) {
        throw Exception('المستخدم غير مسجل الدخول');
      }
      
      // Generate a requisition number (e.g., REQ-YYYYMMDD-XXXX)
      final dateStr = DateTime.now().toIso8601String().replaceAll(RegExp(r'[-:]'), '').substring(0, 8);
      final randomStr = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
      final reqNumber = 'REQ-$dateStr-$randomStr';

      final requisition = StockRequisitionEntity(
        id: 0, // Auto-incremented
        requisitionNumber: reqNumber,
        requisitionDate: DateTime.now(),
        fromBranchId: fromBranchId,
        toBranchId: toBranchId,
        status: RequisitionStatus.pending, // Initial status (Spec 148 canonical)
        notes: notes,
        createdByUserId: user.id,
        updatedByUserId: user.id,
        createdAt: DateTime.now(),
      );

      await ref.read(inventoryRepositoryProvider).createStockRequisition(requisition, items);
      return null;
    } catch (e) {
      debugPrint('Error creating requisition: $e');
      return friendlyError(e, context: 'STOCK-REQ');
    }
  }

  /// Spec 148 — approve a pending requisition: issues a warehouse transfer and
  /// marks it fulfilled. Returns null on success, or an Arabic error string.
  /// A re-tap while the same id is in flight is a no-op (R2).
  Future<String?> approve(int id) => _runGuarded(
        id,
        () => ref.read(inventoryServiceProvider).approveRequisition(
              requisitionId: id,
              userId: ref.read(authProvider).effectiveUser?.id,
            ),
      );

  /// Spec 148 — reject a pending requisition (terminal, no effect).
  Future<String?> reject(int id) => _runGuarded(
        id,
        () => ref
            .read(inventoryServiceProvider)
            .rejectRequisition(requisitionId: id),
      );

  Future<String?> _runGuarded(int id, Future<void> Function() action) async {
    if (state.processingIds.contains(id)) return null; // in-flight → no-op
    state = state.copyWith(processingIds: {...state.processingIds, id});
    try {
      await action();
      return null;
    } catch (e) {
      debugPrint('Error processing requisition $id: $e');
      return friendlyError(e, context: 'STOCK-REQ');
    } finally {
      state = state.copyWith(
        processingIds: state.processingIds.where((x) => x != id).toSet(),
      );
    }
  }

  Future<void> deleteDraftRequisition(int id) async {
    try {
      await ref.read(inventoryRepositoryProvider).deleteStockRequisition(id);
    } catch (e) {
      debugPrint('Error deleting requisition: $e');
    }
  }
}

// Provider
final stockRequisitionsControllerProvider =
    NotifierProvider<StockRequisitionsController, StockRequisitionsState>(
  StockRequisitionsController.new,
);

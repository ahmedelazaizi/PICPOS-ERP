import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/quotation_entity.dart';
import '../../../data/providers/providers.dart';

class QuotationsState {
  final List<QuotationEntity> quotations;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;

  // Filters
  final String searchQuery;
  final DateTimeRange? dateRange;
  final String statusFilter;

  QuotationsState({
    this.quotations = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.searchQuery = '',
    this.dateRange,
    this.statusFilter = 'all',
  });

  QuotationsState copyWith({
    List<QuotationEntity>? quotations,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? statusFilter,
  }) {
    return QuotationsState(
      quotations: quotations ?? this.quotations,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      searchQuery: searchQuery ?? this.searchQuery,
      dateRange: dateRange ?? this.dateRange,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }
}

class QuotationsController extends Notifier<QuotationsState> {
  static const int pageSize = 50;

  @override
  QuotationsState build() {
    // Initial load
    Future.microtask(() => loadQuotations(refresh: true));
    return QuotationsState();
  }

  Future<void> loadQuotations({bool refresh = false}) async {
    if (state.isLoading) return;

    if (refresh) {
      state = state.copyWith(
        isLoading: true,
        currentPage: 0,
        hasMore: true,
        quotations: [],
      );
    } else if (!state.hasMore) {
      return;
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final repo = ref.read(quotationsRepositoryProvider);
      final newItems = await repo.getQuotationsPaginated(
        limit: pageSize,
        offset: state.currentPage * pageSize,
        searchQuery: state.searchQuery,
        dateRange: state.dateRange,
        status: state.statusFilter,
      );

      state = state.copyWith(
        quotations: refresh ? newItems : [...state.quotations, ...newItems],
        isLoading: false,
        currentPage: state.currentPage + 1,
        hasMore: newItems.length == pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      // Handle error
    }
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadQuotations(refresh: true);
  }

  void updateDateRange(DateTimeRange? range) {
    state = state.copyWith(dateRange: range);
    loadQuotations(refresh: true);
  }

  void updateStatusFilter(String status) {
    state = state.copyWith(statusFilter: status);
    loadQuotations(refresh: true);
  }

  Future<void> deleteQuotation(int id) async {
    try {
      await ref.read(quotationsRepositoryProvider).deleteQuotation(id);
      loadQuotations(refresh: true);
    } catch (e) {
      debugPrint('Failed to delete quotation: $e');
    }
  }
}

final quotationsControllerProvider =
    NotifierProvider<QuotationsController, QuotationsState>(
      QuotationsController.new,
    );

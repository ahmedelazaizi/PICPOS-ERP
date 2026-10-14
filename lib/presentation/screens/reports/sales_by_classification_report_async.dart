part of 'sales_by_classification_report.dart';

extension _SalesByClassificationReportAsync
    on _SalesByClassificationReportState {
  Future<void> _loadData() async {
    final requestGeneration = ++_loadRequestGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isSaleTypeLoading = true;
        _saleTypeError = null;
      });
    }
    // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE
    // the report query runs, on every call. _loadData is invoked both from
    // initState's microtask and from the filter-bar onChanged callbacks, so
    // re-resolving here (rather than relying solely on build()'s
    // ref.watch) closes the race where the FIRST load could otherwise run
    // before build() ever observes branchScopeProvider.
    final scope = await ref.read(branchScopeProvider.future);
    if (!mounted || requestGeneration != _loadRequestGeneration) return;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    // Build warehouseIds — Feature 017 added the region branch.
    List<int>? warehouseIds;
    if (_selectedWarehouseId != null) {
      warehouseIds = [_selectedWarehouseId!];
    } else if (_branchWarehouseIds != null && _branchWarehouseIds!.isNotEmpty) {
      warehouseIds = _branchWarehouseIds!.toList();
    } else if (_regionWarehouseIds != null && _regionWarehouseIds!.isNotEmpty) {
      warehouseIds = _regionWarehouseIds!.toList();
    }

    final repo = ref.read(reportingRepositoryProvider);
    final categoryFuture = repo.getSalesByCategory(
      from: _dateRange.start,
      to: _dateRange.end,
      warehouseIds: warehouseIds,
      allowedBranchIds: _allowedBranchIds,
    );
    final saleTypeFuture = repo.getSalesBySaleType(
      from: _dateRange.start,
      to: _dateRange.end,
      warehouseIds: warehouseIds,
      allowedBranchIds: _allowedBranchIds,
    );
    unawaited(_finishSaleTypeLoad(saleTypeFuture, requestGeneration));

    final rows = await categoryFuture;
    if (!mounted || requestGeneration != _loadRequestGeneration) return;
    setState(() {
      _categoryData = rows;
      _isLoading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: child!,
            ),
          ),
        );
      },
    );

    if (picked != null) {
      // H10 · `showDateRangePicker` يرجّع النهايةَ عند **منتصف ليل آخر يوم**،
      // والاستعلاماتُ تقارن `BETWEEN from AND to`. فأخذُ الناتج خاماً كان
      // يبتر اليومَ الأخيرَ كلَّه: مقيس ٢٬٠٠٠ ⇒ ١٬٤٠٠. نفسُ التطبيع الذي
      // تبدأ به الشاشةُ في السطر ٣٧ بالضبط.
      setState(
        () => _dateRange = DateRangeFilter.normalizeRange(
          picked.start,
          picked.end,
        ),
      );
      _loadData();
    }
  }

  Future<void> _finishSaleTypeLoad(
    Future<List<SalesBySaleTypeRow>> saleTypeFuture,
    int requestGeneration,
  ) async {
    try {
      final rows = await saleTypeFuture;
      if (!mounted || requestGeneration != _loadRequestGeneration) return;
      setState(() {
        _saleTypeData = rows;
        _saleTypeError = null;
        _isSaleTypeLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _loadRequestGeneration) return;
      setState(() {
        _saleTypeError = error;
        _isSaleTypeLoading = false;
      });
    }
  }
}

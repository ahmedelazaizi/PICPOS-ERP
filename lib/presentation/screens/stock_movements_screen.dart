import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/config/data_dir.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../core/widgets/app_toast.dart';
part 'stock_movements_screen_rows.dart';

/// Stock Movement Audit Screen — Inventory ledger and movement history
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  ConsumerState<StockMovementsScreen> createState() =>
      _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  String _selectedType = 'all';
  String _searchQuery = '';
  int? _selectedWarehouseId; // U-02: Warehouse filter
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final _timeFormat = DateFormat('HH:mm');

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  /// الاستعلام كان بيتبني **جوّه `build()`**، يعني `FutureBuilder` بياخد future
  /// جديد مع كل rebuild — كل حرف في خانة البحث، وكل تغيير فلتر، وكل تبديل
  /// ثيم = استعلام كامل جديد على `stock_movements`. الكاش ده مفتاحه المدى
  /// الزمني وحده لأن باقي الفلاتر بتتطبّق على النتيجة في الذاكرة.
  Future<List<StockMovementData>>? _movementsFuture;
  ({DateTime from, DateTime to})? _movementsKey;

  Future<List<StockMovementData>> _fetchMovements() async {
    final repo = ref.read(inventoryRepositoryProvider);
    // حصر المخازن: الحركات بتحمل unit_cost و balance_after — تكلفة ورصيد،
    // بيان مالي. العقد موثَّق في userAccessibleWarehousesProvider: بيرجّع كل
    // المخازن للمميّز، ومجموعة فاضية لمستخدم بلا تخصيص على عميل/مرآة (فشل
    // مقفول). تمرير المعرّفات بيغطّي الحالتين من غير فرع إضافي.
    final accessible = await ref.read(userAccessibleWarehousesProvider.future);
    return repo.getMovementsByDateRange(
      _fromDate,
      _toDate,
      warehouseIds: accessible.map((w) => w.id).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Feature 058: seed _selectedWarehouseId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002). This screen filters by
      // warehouse, not branch — we resolve the active branch's first
      // warehouse via branchWarehouseIdsProvider as a sensible default.
      if (_selectedWarehouseId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          final warehouseIds = await ref.read(
            branchWarehouseIdsProvider(activeBranchId).future,
          );
          if (!mounted) return;
          if (warehouseIds.isNotEmpty) {
            setState(() => _selectedWarehouseId = warehouseIds.first);
          }
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'),
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          });
        }
      }
    });
  }

  static Map<String, _TypeInfo> get _movementTypes => <String, _TypeInfo>{
    'all': _TypeInfo(tr('الكل'), Colors.grey, PhosphorIconsBold.list),
    'sale': _TypeInfo(
      tr('بيع'),
      const Color(0xFF059669),
      PhosphorIconsBold.shoppingCart,
    ),
    'purchase': _TypeInfo(
      tr('شراء'),
      const Color(0xFF2563EB),
      PhosphorIconsBold.package,
    ),
    'adjustment': _TypeInfo(
      tr('تعديل'),
      const Color(0xFFF59E0B),
      PhosphorIconsBold.pencilSimple,
    ),
    'transfer': _TypeInfo(
      tr('تحويل'),
      const Color(0xFF7C3AED),
      PhosphorIconsBold.arrowsLeftRight,
    ),
    'transfer_in': _TypeInfo(
      tr('وارد تحويل'),
      const Color(0xFF7C3AED),
      PhosphorIconsBold.arrowSquareIn,
    ),
    'transfer_out': _TypeInfo(
      tr('صادر تحويل'),
      const Color(0xFF9333EA),
      PhosphorIconsBold.arrowSquareOut,
    ),
    'return': _TypeInfo(
      tr('مرتجع'),
      const Color(0xFFDC2626),
      PhosphorIconsBold.arrowUUpLeft,
    ),
    'manufacturing': _TypeInfo(
      tr('تصنيع'),
      const Color(0xFF0891B2),
      PhosphorIconsBold.factory,
    ),
    'manufacturing_in': _TypeInfo(
      tr('إنتاج وارد'),
      const Color(0xFF0891B2),
      PhosphorIconsBold.factory,
    ),
    'manufacturing_out': _TypeInfo(
      tr('صرف إنتاج'),
      const Color(0xFF06B6D4),
      PhosphorIconsBold.factory,
    ),
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // يُعاد بناء الـfuture لما المدى الزمني يتغيّر بس — مش مع كل rebuild.
    final key = (from: _fromDate, to: _toDate);
    if (_movementsKey != key || _movementsFuture == null) {
      _movementsKey = key;
      _movementsFuture = _fetchMovements();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين،
      // وتثبيتُها على `AppColors.surface` الفاتحةِ هو ما كان يُبقي الشاشةَ
      // بيضاءَ في الوضع الغامق.
      child: Scaffold(
        body: Column(
          children: [
            _buildHeader(),
            _buildFilters(context),
            Expanded(
              child: FutureBuilder<List<StockMovementData>>(
                future: _movementsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var movements = snapshot.data!;

                  // Filter by type
                  if (_selectedType != 'all') {
                    movements = movements
                        .where((m) => m.movementType == _selectedType)
                        .toList();
                  }

                  // Filter by warehouse (U-02)
                  if (_selectedWarehouseId != null) {
                    movements = movements
                        .where((m) => m.warehouseId == _selectedWarehouseId)
                        .toList();
                  }

                  // Filter by search
                  if (_searchQuery.isNotEmpty) {
                    movements = movements.where((m) {
                      final notes = m.notes ?? '';
                      return notes.contains(_searchQuery) ||
                          m.productId.toString().contains(_searchQuery) ||
                          m.referenceType?.contains(_searchQuery) == true ||
                          m.productName?.toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              ) ==
                              true;
                    }).toList();
                  }

                  // Cache for export
                  _lastFilteredMovements = movements;

                  if (movements.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildMovementsList(
                    context,
                    ref.read(inventoryRepositoryProvider),
                    movements,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Currently displayed (filtered) movements for export
  List<StockMovementData> _lastFilteredMovements = [];

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          // Spec 057: back button — only when pushed onto navigator (e.g.
          // from reports launcher); hidden when reached via the sidebar.
          if (Navigator.canPop(context)) ...[
            IconButton(
              tooltip: tr('رجوع'),
              icon: const Icon(
                PhosphorIconsBold.caretRight,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              PhosphorIconsBold.arrowsDownUp,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('حركة المخزون'),
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  tr('سجل جميع الحركات المخزنية'),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          // Excel Export button
          ElevatedButton.icon(
            onPressed: _lastFilteredMovements.isEmpty ? null : _exportToExcel,
            icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, size: 18),
            label: Text(
              tr('تصدير Excel'),
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_lastFilteredMovements.isEmpty) return;
    try {
      final df = DateFormat('yyyy-MM-dd');
      final tf = DateFormat('HH:mm');
      final buf = StringBuffer();
      // BOM for Excel Arabic support
      buf.write('\uFEFF');
      buf.writeln(
        tr(
          'التاريخ,الوقت,النوع,المنتج,المستودع,الكمية,التكلفة,الرصيد بعد,المرجع,ملاحظات',
        ),
      );
      for (final m in _lastFilteredMovements) {
        final typeLabel =
            _movementTypes[m.movementType]?.label ?? m.movementType;
        final productName = (m.productName ?? '#${m.productId}').replaceAll(
          ',',
          ' ',
        );
        final warehouseName = (m.warehouseName ?? '#${m.warehouseId}')
            .replaceAll(',', ' ');
        final ref = m.referenceType != null
            ? _translateReference(m.referenceType!, m.referenceId)
            : '';
        final notes = (m.notes ?? '')
            .replaceAll(',', ' ')
            .replaceAll('\n', ' ');
        buf.writeln(
          '${df.format(m.createdAt)},${tf.format(m.createdAt)},$typeLabel,$productName,$warehouseName,${m.quantity},${m.unitCost},${m.balanceAfter},$ref,$notes',
        );
      }
      final dir = await DataDir.documents();
      final file = File(
        '${dir.path}/stock_movements_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
      );
      await file.writeAsString(buf.toString());
      if (mounted) {
        AppToast.show(context, tr('تم التصدير بنجاح: {p0}', {'p0': file.path}));
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          tr('خطأ في التصدير: {e}', {'e': e}),
          type: ToastType.error,
        );
      }
    }
  }

  Widget _buildFilters(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Column(
        children: [
          // Date range + search
          Row(
            children: [
              // From date
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fromDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _fromDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr('من'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      _dateFormat.format(_fromDate),
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // To date
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _toDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setState(() => _toDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr('إلى'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      _dateFormat.format(_toDate),
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Search
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: tr('بحث...'),
                    prefixIcon: const Icon(
                      PhosphorIconsBold.magnifyingGlass,
                      size: 16,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(PhosphorIconsBold.x, size: 14),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Warehouse filter (U-02)
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final warehousesAsync = ref.watch(
                      userAccessibleWarehousesProvider,
                    );
                    return warehousesAsync.when(
                      data: (warehouses) => DropdownButtonFormField<int?>(
                        initialValue: _selectedWarehouseId,
                        decoration: InputDecoration(
                          labelText: tr('المستودع'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        isExpanded: true,
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              tr('جميع المستودعات'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          ...warehouses.map(
                            (w) => DropdownMenuItem<int?>(
                              value: w.id,
                              child: Text(
                                trData(w.name),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedWarehouseId = v),
                      ),
                      loading: () => const SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, _) => Text(tr('خطأ')),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Movement type chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _movementTypes.entries.map((entry) {
                final isSelected = _selectedType == entry.key;
                final info = entry.value;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          info.icon,
                          size: 14,
                          color: isSelected ? Colors.white : info.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          info.label,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white
                                : context.picposText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    selectedColor: info.color,
                    backgroundColor: info.color.withValues(alpha: 0.06),
                    onSelected: (_) =>
                        setState(() => _selectedType = entry.key),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? info.color
                            : info.color.withValues(alpha: 0.2),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.package, size: 64, color: context.picposMuted),
          const SizedBox(height: 16),
          Text(
            tr('لا توجد حركات في الفترة المحددة'),
            style: GoogleFonts.cairo(fontSize: 14, color: context.picposMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsList(
    BuildContext context,
    InventoryRepository repo,
    List<StockMovementData> movements,
  ) {
    // Client-side filtering for type and search
    final filteredMovements = movements.where((m) {
      final matchesType =
          _selectedType == 'all' || m.movementType == _selectedType;
      final matchesSearch =
          _searchQuery.isEmpty ||
          (m.productName?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          m.productId.toString().contains(_searchQuery);
      return matchesType && matchesSearch;
    }).toList();

    // Summary stats
    final totalIn = filteredMovements
        .where((m) => m.quantity > 0)
        .fold(0.0, (s, m) => s + m.quantity);
    final totalOut = filteredMovements
        .where((m) => m.quantity < 0)
        .fold(0.0, (s, m) => s + m.quantity.abs());
    final totalValue = filteredMovements.fold(
      0.0,
      (s, m) => s + (m.quantity.abs() * m.unitCost),
    );

    if (filteredMovements.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: context.picposField,
          child: Row(
            children: [
              _statChip(
                tr('إجمالي الحركات'),
                '${filteredMovements.length}',
                AppColors.primary,
              ),
              const SizedBox(width: 8),
              _statChip(
                tr('الوارد'),
                totalIn.toStringAsFixed(1),
                AppColors.success,
              ),
              const SizedBox(width: 8),
              _statChip(
                tr('الصادر'),
                totalOut.toStringAsFixed(1),
                AppColors.error,
              ),
              const SizedBox(width: 8),
              _statChip(
                tr('القيمة'),
                totalValue.toStringAsFixed(AppConstants.decimalPlaces),
                AppColors.info,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.primary.withValues(alpha: 0.04),
          child: Row(
            children: [
              _headerCell(tr('التاريخ'), flex: 2),
              _headerCell(tr('النوع'), flex: 1),
              _headerCell(tr('المنتج'), flex: 2),
              _headerCell(tr('المستودع'), flex: 1),
              _headerCell(tr('الكمية'), flex: 1),
              _headerCell(tr('التكلفة'), flex: 1),
              _headerCell(tr('الرصيد بعد'), flex: 1),
              _headerCell(tr('المرجع'), flex: 2),
            ],
          ),
        ),
        const Divider(height: 1),
        // Movements list
        Expanded(
          child: ListView.separated(
            itemCount: filteredMovements.length,
            separatorBuilder: (context, i) => Divider(
              height: 1,
              color: context.picposHairline.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              final m = filteredMovements[index];
              return _buildMovementRow(context, repo, m);
            },
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.cairo(fontSize: 9, color: context.picposMuted),
            ),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TypeInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _TypeInfo(this.label, this.color, this.icon);
}

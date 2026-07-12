import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/fixed_assets_repository.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../services/printing/report_pdf_generator.dart';

part 'fixed_assets_dialogs.dart';

/// Fixed Assets Screen — الأصول الثابتة والإهلاك
/// Manage asset categories, fixed assets, and run depreciation
class FixedAssetsScreen extends ConsumerStatefulWidget {
  const FixedAssetsScreen({super.key});

  @override
  ConsumerState<FixedAssetsScreen> createState() => _FixedAssetsScreenState();
}

class _FixedAssetsScreenState extends ConsumerState<FixedAssetsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final _currencyFormat = NumberFormat('#,##0.00');
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixedAssetsRepo = ref.watch(fixedAssetsRepositoryProvider);
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(
            'الأصول الثابتة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(PhosphorIconsBold.buildings, size: 18), text: 'الأصول'),
              Tab(icon: Icon(PhosphorIconsBold.folders, size: 18), text: 'الفئات'),
              Tab(icon: Icon(PhosphorIconsBold.trendDown, size: 18), text: 'الإهلاك'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.chartPie),
              tooltip: 'ملخص',
              onPressed: () => showSummary(fixedAssetsRepo),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث عن أصل (اسم، رمز)...',
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildAssetsTab(fixedAssetsRepo, accountingRepo),
                  _buildCategoriesTab(fixedAssetsRepo, accountingRepo),
                  _buildDepreciationTab(fixedAssetsRepo),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFab(fixedAssetsRepo, accountingRepo),
      ),
    );
  }

  Widget? _buildFab(IFixedAssetsRepository repo, IAccountingRepository accountingRepo) {
    return FloatingActionButton.extended(
      onPressed: () {
        if (_tabCtrl.index == 0) {
          showCreateAssetDialog(repo, accountingRepo);
        } else if (_tabCtrl.index == 1) {
          showCreateCategoryDialog(repo, accountingRepo);
        }
      },
      backgroundColor: AppColors.primary,
      icon: const Icon(PhosphorIconsBold.plus, color: Colors.white),
      label: Text(
        _tabCtrl.index == 1 ? 'فئة جديدة' : 'أصل جديد',
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ASSETS TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAssetsTab(IFixedAssetsRepository repo, IAccountingRepository accountingRepo) {
    return StreamBuilder<List<FixedAssetData>>(
      stream: repo.watchFixedAssets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var assets = (snapshot.data ?? []).toList();
        if (_searchQuery.isNotEmpty) {
          assets = assets.where((a) =>
            a.name.toLowerCase().contains(_searchQuery) ||
            a.code.toLowerCase().contains(_searchQuery)
          ).toList();
        }
        if (assets.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIconsBold.buildings,
                    size: 64, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text('لا توجد أصول ثابتة',
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: assets.length,
          itemBuilder: (context, i) => _buildAssetCard(repo, accountingRepo, assets[i]),
        );
      },
    );
  }

  Widget _buildAssetCard(IFixedAssetsRepository repo, IAccountingRepository accountingRepo, FixedAssetData asset) {
    final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;
    final depreciationPercent = asset.purchasePrice > 0
        ? (asset.accumulatedDepreciation / asset.purchasePrice * 100)
        : 0.0;
    final statusInfo = getAssetStatusInfo(asset.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showAssetDetails(asset),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      asset.code,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      asset.name,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusInfo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusInfo.label,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusInfo.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _valueChip(
                    'تكلفة الشراء',
                    _currencyFormat.format(asset.purchasePrice),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _valueChip(
                    'القيمة الدفترية',
                    _currencyFormat.format(bookValue),
                    bookValue > 0 ? AppColors.success : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  _valueChip(
                    'الإهلاك',
                    '${depreciationPercent.toStringAsFixed(0)}%',
                    Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: depreciationPercent / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    depreciationPercent >= 100
                        ? AppColors.error
                        : depreciationPercent >= 75
                            ? Colors.orange
                            : AppColors.primary,
                  ),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(PhosphorIconsBold.calendarBlank,
                      size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'شراء: ${_dateFormat.format(asset.purchaseDate)}',
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  Icon(PhosphorIconsBold.clock,
                      size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${asset.usefulLifeYears} سنة',
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: Colors.grey.shade600),
                  ),
                  if (asset.location != null) ...[
                    const SizedBox(width: 12),
                    Icon(PhosphorIconsBold.mapPin,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      asset.location!,
                      style: GoogleFonts.cairo(
                          fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
              if (asset.status == 'active') ...[
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ActionChip(
                      avatar: const Icon(PhosphorIconsBold.pencilSimple,
                          size: 14, color: Colors.indigo),
                      label: Text('تعديل',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.indigo)),
                      backgroundColor: Colors.indigo.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: Colors.indigo.withValues(alpha: 0.2)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showEditAssetDialog(repo, accountingRepo, asset),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(PhosphorIconsBold.trendUp,
                          size: 14, color: Colors.teal),
                      label: Text('إعادة تقييم',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.teal)),
                      backgroundColor: Colors.teal.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: Colors.teal.withValues(alpha: 0.2)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showRevalueDialog(repo, asset),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(PhosphorIconsBold.clockCounterClockwise,
                          size: 14, color: Colors.blue),
                      label: Text('سجل الإهلاك',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.blue)),
                      backgroundColor: Colors.blue.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: Colors.blue.withValues(alpha: 0.2)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showDepreciationHistory(repo, asset),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(PhosphorIconsBold.trash,
                          size: 14, color: AppColors.error),
                      label: Text('استبعاد',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: AppColors.error)),
                      backgroundColor: AppColors.error.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.2)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showDisposeDialog(repo, asset),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _valueChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 9, color: Colors.grey.shade600)),
            Text(value,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // CATEGORIES TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCategoriesTab(IFixedAssetsRepository repo, IAccountingRepository accountingRepo) {
    return StreamBuilder<List<AssetCategory>>(
      stream: repo.watchAssetCategories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snapshot.data ?? [];
        if (categories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIconsBold.folders,
                    size: 64, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text('لا توجد فئات',
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final cat = categories[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: const Icon(PhosphorIconsBold.folder,
                      color: AppColors.primary, size: 18),
                ),
                title: Text(cat.name,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'العمر الافتراضي: ${cat.defaultUsefulLife > 0 ? '${cat.defaultUsefulLife} سنة' : 'غير محدد'} | '
                  '${getDepreciationMethodLabel(cat.defaultDepreciationMethod)}',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                ),
                trailing: IconButton(
                  icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                  onPressed: () => showEditCategoryDialog(repo, accountingRepo, cat),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DEPRECIATION TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDepreciationTab(IFixedAssetsRepository repo) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: () => runDepreciation(repo),
            icon: const Icon(PhosphorIconsBold.play, size: 18),
            label: Text('تنفيذ الإهلاك الشهري',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<FixedAssetData>>(
            stream: repo.watchFixedAssets(),
            builder: (context, assetSnapshot) {
              final assetNameMap = <int, String>{};
              if (assetSnapshot.hasData) {
                for (var a in assetSnapshot.data!) {
                  assetNameMap[a.id] = a.name;
                }
              }

              return StreamBuilder<List<AssetDepreciationData>>(
                stream: repo.watchAllDepreciations(),
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text('لا يوجد سجل إهلاك',
                          style: GoogleFonts.cairo(color: Colors.grey)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final assetName = assetNameMap[entry.assetId] ?? 'أصل #${entry.assetId}';
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.withValues(alpha: 0.12),
                          radius: 16,
                          child: const Icon(PhosphorIconsBold.trendDown,
                              size: 14, color: Colors.orange),
                        ),
                        title: Text(assetName,
                            style: GoogleFonts.cairo(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${_dateFormat.format(entry.periodDate)} | '
                          'ق.د: ${_currencyFormat.format(entry.bookValue)}',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.grey),
                        ),
                        trailing: Text(
                          '-${_currencyFormat.format(entry.depreciationAmount)}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssetStatusInfo {
  final String label;
  final Color color;
  _AssetStatusInfo(this.label, this.color);
}

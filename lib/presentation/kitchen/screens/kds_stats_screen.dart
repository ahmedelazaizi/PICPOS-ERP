import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// KDS Statistics Dashboard — kitchen performance analytics
class KdsStatsScreen extends ConsumerStatefulWidget {
  const KdsStatsScreen({super.key});

  @override
  ConsumerState<KdsStatsScreen> createState() => _KdsStatsScreenState();
}

class _KdsStatsScreenState extends ConsumerState<KdsStatsScreen> {
  Map<String, int> _orderStats = {};
  Map<String, int> _stationStats = {};
  Map<int, int> _hourlyStats = {};
  List<Map<String, dynamic>> _slowestItems = [];
  double _avgPrepTime = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final kitchenRepo = ref.read(kitchenRepositoryProvider);
      final results = await Future.wait([
        kitchenRepo.getTodayOrderStats(),
        kitchenRepo.getOrdersPerStation(),
        kitchenRepo.getOrdersByHour(),
        kitchenRepo.getSlowestItems(),
        kitchenRepo.getAveragePrepTime(),
      ]);
      if (!mounted) return;
      setState(() {
        _orderStats = results[0] as Map<String, int>;
        _stationStats = results[1] as Map<String, int>;
        _hourlyStats = results[2] as Map<int, int>;
        _slowestItems = results[3] as List<Map<String, dynamic>>;
        _avgPrepTime = results[4] as double;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        appBar: AppBar(
          backgroundColor: AppColors.secondary,
          title:  Text(tr('📊 إحصائيات المطبخ'),
              style: const TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _loadStats,
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              tooltip: tr('تحديث'),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight))
            : RefreshIndicator(
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary cards row
                    _buildSummaryCards(),
                    const SizedBox(height: 16),

                    // Station breakdown
                    _buildStationBreakdown(),
                    const SizedBox(height: 16),

                    // Peak hours chart
                    _buildPeakHoursCard(),
                    const SizedBox(height: 16),

                    // Slowest items
                    _buildSlowestItemsCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final total = _orderStats.values.fold<int>(0, (a, b) => a + b);
    final pending = _orderStats['pending'] ?? 0;
    final preparing = _orderStats['preparing'] ?? 0;
    final ready = _orderStats['ready'] ?? 0;
    final served = _orderStats['served'] ?? 0;

    return Row(
      children: [
        _buildStatCard(tr('إجمالي الطلبات'), '$total', PhosphorIconsBold.listChecks,
            AppColors.primary),
        const SizedBox(width: 10),
        _buildStatCard(
            tr('معلق'), '$pending', PhosphorIconsBold.hourglass, AppColors.error),
        const SizedBox(width: 10),
        _buildStatCard(tr('قيد التحضير'), '$preparing', PhosphorIconsBold.fire,
            AppColors.warning),
        const SizedBox(width: 10),
        _buildStatCard(tr('جاهز'), '$ready', PhosphorIconsBold.checkCircle,
            AppColors.success),
        const SizedBox(width: 10),
        _buildStatCard(tr('تم التقديم'), '$served', PhosphorIconsBold.forkKnife,
            AppColors.info),
        const SizedBox(width: 10),
        _buildStatCard(
            tr('متوسط التحضير'),
            tr('{p0} د', {'p0': _avgPrepTime.toStringAsFixed(1)}),
            PhosphorIconsBold.timer,
            Colors.purple),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStationBreakdown() {
    if (_stationStats.isEmpty) {
      return _buildCard(
        tr('توزيع المحطات'),
        PhosphorIconsBold.mapPinArea,
         Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('لا توجد طلبات اليوم'),
                    style: const TextStyle(color: Colors.white38)))),
      );
    }

    final total = _stationStats.values.fold<int>(0, (a, b) => a + b);
    final stationColors = [
      AppColors.primary,
      AppColors.warning,
      AppColors.success,
      AppColors.info,
      Colors.purple,
      Colors.teal,
    ];

    return _buildCard(
      tr('توزيع المحطات'),
      PhosphorIconsBold.mapPinArea,
      Column(
        children: _stationStats.entries.toList().asMap().entries.map((entry) {
          final idx = entry.key;
          final station = entry.value.key;
          final count = entry.value.value;
          final pct = total > 0 ? (count / total * 100) : 0.0;
          final color = stationColors[idx % stationColors.length];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                SizedBox(
                    width: 80,
                    child: Text(_stationLabel(station),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: Colors.white10,
                      color: color,
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$count (${pct.toStringAsFixed(0)}%)',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeakHoursCard() {
    if (_hourlyStats.isEmpty) {
      return _buildCard(
        tr('ساعات الذروة'),
        PhosphorIconsBold.chartBar,
         Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('لا توجد بيانات'),
                    style: const TextStyle(color: Colors.white38)))),
      );
    }

    final maxCount =
        _hourlyStats.values.fold<int>(0, (a, b) => a > b ? a : b);
    // Show hours from 6AM to 11PM
    final hours =
        List.generate(18, (i) => i + 6).where((h) => h <= 23).toList();

    return _buildCard(
      tr('ساعات الذروة'),
      PhosphorIconsBold.chartBar,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: hours.map((hour) {
              final count = _hourlyStats[hour] ?? 0;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;
              final isPeak = count == maxCount && count > 0;

              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (count > 0)
                      Text('$count',
                          style: TextStyle(
                              color: isPeak
                                  ? AppColors.warning
                                  : Colors.white54,
                              fontSize: 9,
                              fontWeight:
                                  isPeak ? FontWeight.bold : FontWeight.normal)),
                    const SizedBox(height: 2),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: ratio.clamp(0.05, 1.0),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: isPeak
                                ? AppColors.warning
                                : AppColors.primary.withValues(alpha: 0.7),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${hour % 12 == 0 ? 12 : hour % 12}',
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 9)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSlowestItemsCard() {
    if (_slowestItems.isEmpty) {
      return _buildCard(
        tr('أبطأ الأصناف تحضيراً'),
        PhosphorIconsBold.hourglass,
         Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('لا توجد بيانات كافية'),
                    style: const TextStyle(color: Colors.white38)))),
      );
    }

    return _buildCard(
      tr('أبطأ الأصناف تحضيراً'),
      PhosphorIconsBold.hourglass,
      Column(
        children: _slowestItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final name = item['name'] as String;
          final avgMin = (item['avgMinutes'] as num).toDouble();
          final count = item['count'] as int;

          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.error.withValues(alpha: 0.2),
              child: Text('${idx + 1}',
                  style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            title: Text(name,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(tr('{count} طلب', {'count': count}),
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(tr('{p0} د', {'p0': avgMin.toStringAsFixed(1)}),
                  style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCard(String title, IconData icon, Widget content) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          content,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _stationLabel(String code) {
    switch (code.toLowerCase()) {
      case 'kitchen':
        return tr('المطبخ');
      case 'bar':
        return tr('البار');
      case 'dessert':
        return tr('الحلويات');
      case 'grill':
        return tr('الشواية');
      default:
        return code;
    }
  }
}

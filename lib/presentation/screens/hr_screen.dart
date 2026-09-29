import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import 'hr/widgets/hr_widgets.dart';

class HRScreen extends ConsumerStatefulWidget {
  const HRScreen({super.key});

  @override
  ConsumerState<HRScreen> createState() => _HRScreenState();
}

class _HRScreenState extends ConsumerState<HRScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // لا تجاوزَ للخلفيّة: الثيمُ يعرّف `scaffoldBackgroundColor` للوضعَين.
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title:  Text(
          tr('الموارد البشرية (HR)'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs:  [
            Tab(text: tr('لوحة المعلومات'), icon: const Icon(PhosphorIconsBold.chartBar)),
            Tab(text: tr('الموظفين'), icon: const Icon(PhosphorIconsBold.users)),
            Tab(text: tr('الحضور'), icon: const Icon(PhosphorIconsBold.calendarCheck)),
            Tab(text: tr('الرواتب'), icon: const Icon(PhosphorIconsBold.wallet)),
            Tab(text: tr('الإجازات'), icon: const Icon(PhosphorIconsBold.calendar)),
            Tab(text: tr('إضافي'), icon: const Icon(PhosphorIconsBold.timer)),
            Tab(text: tr('الأداء'), icon: const Icon(PhosphorIconsBold.chartLine)),
            Tab(text: tr('العقود'), icon: const Icon(PhosphorIconsBold.fileText)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: tr('بحث في الموظفين (اسم، قسم)...'),
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
              controller: _tabController,
              children: const [
                HRDashboardTab(),
                StaffListTab(),
                AttendanceTab(),
                PayrollTab(),
                LeavesTab(),
                OvertimeTab(),
                PerformanceTab(),
                ContractsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

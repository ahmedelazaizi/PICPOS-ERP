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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'الموارد البشرية (HR)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'لوحة المعلومات', icon: Icon(PhosphorIconsBold.chartBar)),
            Tab(text: 'الموظفين', icon: Icon(PhosphorIconsBold.users)),
            Tab(text: 'الحضور', icon: Icon(PhosphorIconsBold.calendarCheck)),
            Tab(text: 'الرواتب', icon: Icon(PhosphorIconsBold.wallet)),
            Tab(text: 'الإجازات', icon: Icon(PhosphorIconsBold.calendar)),
            Tab(text: 'إضافي', icon: Icon(PhosphorIconsBold.timer)),
            Tab(text: 'الأداء', icon: Icon(PhosphorIconsBold.chartLine)),
            Tab(text: 'العقود', icon: Icon(PhosphorIconsBold.fileText)),
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
                hintText: 'بحث في الموظفين (اسم، قسم)...',
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

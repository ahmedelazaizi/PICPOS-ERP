import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value;
import '../../data/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';
import 'package:picpos_erp/presentation/widgets/field_geo_link.dart';
import 'providers/distribution_controller.dart';


part 'distribution/distribution_routes_tab.dart';
part 'distribution/distribution_visits_tab.dart';
part 'distribution/distribution_targets_tab.dart';
part 'distribution/distribution_collections_tab.dart';
/// شاشة التوزيع والمندوبين
class DistributionScreen extends ConsumerStatefulWidget {
  const DistributionScreen({super.key});
  @override
  ConsumerState<DistributionScreen> createState() => _DistributionScreenState();
}

class _DistributionScreenState extends ConsumerState<DistributionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      appBar: AppBar(
        title:  Text(tr('التوزيع والمندوبين')),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs:  [
            Tab(text: tr('المسارات'), icon: const Icon(PhosphorIconsBold.mapPin)),
            Tab(text: tr('الزيارات'), icon: const Icon(PhosphorIconsBold.path)),
            Tab(text: tr('الأهداف'), icon: const Icon(PhosphorIconsBold.target)),
            Tab(text: tr('التحصيلات'), icon: const Icon(PhosphorIconsBold.money)),
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
                hintText: tr('بحث في التوزيع (مسارات، زيارات)...'),
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
              children: [
                _RoutesTab(ref: ref, searchQuery: _searchQuery),
                _VisitsTab(ref: ref, searchQuery: _searchQuery),
                _TargetsTab(ref: ref, searchQuery: _searchQuery),
                _CollectionsTab(ref: ref, searchQuery: _searchQuery),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

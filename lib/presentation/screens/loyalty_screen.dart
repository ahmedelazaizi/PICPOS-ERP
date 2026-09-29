import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value, OrderingTerm;
import '../../data/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import '../../domain/repositories/loyalty_repository.dart';
import '../widgets/permission_guard.dart';


part 'loyalty_programs_tab.dart';
part 'loyalty_points_tab.dart';
part 'loyalty_transactions_tab.dart';
/// شاشة نقاط الولاء
class LoyaltyScreen extends ConsumerStatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  ConsumerState<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends ConsumerState<LoyaltyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title:  Text(tr('نقاط العملاء')),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs:  [
            Tab(text: tr('البرامج'), icon: const Icon(PhosphorIconsBold.star)),
            Tab(text: tr('أرصدة العملاء'), icon: const Icon(PhosphorIconsBold.users)),
            Tab(
              text: tr('سجل الحركات'),
              icon: const Icon(PhosphorIconsBold.clockCounterClockwise),
            ),
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
                hintText: tr('بحث في برامج الولاء...'),
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
                _ProgramsTab(ref: ref, searchQuery: _searchQuery),
                _CustomerPointsTab(ref: ref, searchQuery: _searchQuery),
                _TransactionsTab(ref: ref, searchQuery: _searchQuery),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


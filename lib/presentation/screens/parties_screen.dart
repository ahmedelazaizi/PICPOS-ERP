import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import 'customers_screen.dart';
import 'suppliers_screen.dart';
import 'parties/party_groups_tab.dart';

/// Unified Parties screen with tabs for Customers, Suppliers, and
/// (Phase 2) Party Groups for batching customers/suppliers into
/// administrative categories.
class PartiesScreen extends ConsumerStatefulWidget {
  final int initialTab; // 0 = customers, 1 = suppliers, 2 = groups

  const PartiesScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('إدارة الأطراف (العملاء والموردين)'),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(PhosphorIconsBold.users), text: 'العملاء'),
              Tab(icon: Icon(PhosphorIconsBold.truck), text: 'الموردين'),
              Tab(icon: Icon(PhosphorIconsBold.usersThree), text: 'المجموعات'),
            ],
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            const SizedBox(height: 16),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _CustomersTabContent(),
                  _SuppliersTabContent(),
                  PartyGroupsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrapper for CustomersScreen content
class _CustomersTabContent extends ConsumerWidget {
  const _CustomersTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Embed the existing CustomersScreen without its own header
    return const CustomersScreen();
  }
}

/// Wrapper for SuppliersScreen content
class _SuppliersTabContent extends ConsumerWidget {
  const _SuppliersTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Embed the existing SuppliersScreen without its own header
    return const SuppliersScreen();
  }
}

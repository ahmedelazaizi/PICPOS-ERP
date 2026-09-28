import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../domain/entities/product_entity.dart';
import '../widgets/permission_guard.dart';

part 'widgets/manufacturing/bom_tab.dart';
part 'widgets/manufacturing/production_orders_tab.dart';
part 'widgets/manufacturing/production_dialog_analytics.dart';

/// Manufacturing Screen — BOM Management + Production Orders
class ManufacturingScreen extends ConsumerStatefulWidget {
  const ManufacturingScreen({super.key});

  @override
  ConsumerState<ManufacturingScreen> createState() =>
      _ManufacturingScreenState();
}

class _ManufacturingScreenState extends ConsumerState<ManufacturingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        body: Column(
          children: [
            // ─── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(PhosphorIconsBold.factory,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'التصنيع',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const Spacer(),
                  // Tab Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      dividerHeight: 0,
                      tabAlignment: TabAlignment.start,
                      padding: const EdgeInsets.all(4),
                      tabs: const [
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(PhosphorIconsBold.listDashes, size: 16),
                                SizedBox(width: 8),
                                Text('قوائم المواد (BOM)'),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(PhosphorIconsBold.gearSix, size: 16),
                                SizedBox(width: 8),
                                Text('أوامر الإنتاج'),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(PhosphorIconsBold.chartBar, size: 16),
                                SizedBox(width: 8),
                                Text('تحليلات'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ─── Tab Content ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _BomTab(),
                  _ProductionOrdersTab(),
                  _MfgAnalyticsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

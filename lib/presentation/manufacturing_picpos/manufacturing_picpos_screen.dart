import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/permissions/permission_codes.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../picpos_shell/picpos_report_tabs.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/permission_guard.dart';
import 'additional_costs_tab.dart';
import 'bom_dialog.dart';
import 'bom_tab.dart';
import 'butchery_tab.dart';
import 'manufacturing_orders_tab.dart';
import 'reports_tab.dart';

class ManufacturingPicposScreen extends ConsumerStatefulWidget {
  const ManufacturingPicposScreen({super.key});

  @override
  ConsumerState<ManufacturingPicposScreen> createState() => _ManufacturingPicposScreenState();
}

class _ManufacturingPicposScreenState extends ConsumerState<ManufacturingPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boms = ref.watch(allBomsProvider).value ?? const <BillOfMaterialData>[];
    final orders = ref.watch(manufacturingOrdersProvider).value ?? const <ManufacturingOrderData>[];
    final products = ref.watch(allProductsProvider).value ?? const <ProductEntity>[];
    final warehouses = ref.watch(warehouseListProvider).value ?? const <Warehouse>[];
    return PicPosScreenScaffold(
      title: 'التصنيع',
      subtitle: 'قوائم المكوّنات والإنتاج والتشفية والتكلفة والتقارير',
      icon: PhosphorIconsBold.factory,
      headerActions: [
        PermissionGuard(
          permission: PermissionCodes.manufacturingManage,
          allowManagerOverride: true,
          actionName: 'إنشاء قائمة مكونات',
          onGranted: () => _openBomEditor(products),
          child: FilledButton.icon(
            onPressed: () => _openBomEditor(products),
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('قائمة مكوّنات جديدة'),
          ),
        ),
      ],
      subHeader: PicPosReportTabs(
        controller: _tabs,
        tabs: [
          (label: 'قوائم المكوّنات', icon: PhosphorIconsBold.listDashes, badge: '${boms.length}'),
          (label: 'أوامر الإنتاج', icon: PhosphorIconsBold.factory, badge: '${orders.length}'),
          (label: 'التشفية', icon: PhosphorIconsBold.scissors, badge: null),
          (label: 'التكاليف الإضافية', icon: PhosphorIconsBold.coins, badge: null),
          (label: 'التقارير', icon: PhosphorIconsBold.chartLine, badge: null),
        ],
      ),
      bodyPadding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
      body: TabBarView(
        controller: _tabs,
        children: [
          BomTab(boms: boms, products: products, onEdit: _openBomEditor),
          ManufacturingOrdersTab(orders: orders, boms: boms, warehouses: warehouses),
          ButcheryTab(products: products, warehouses: warehouses),
          AdditionalCostsTab(orders: orders),
          ManufacturingReportsTab(boms: boms, products: products),
        ],
      ),
    );
  }

  Future<void> _openBomEditor(List<ProductEntity> products, [int? bomId]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BomEditorDialog(products: products, bomId: bomId),
    );
    ref.invalidate(allBomsProvider);
  }
}

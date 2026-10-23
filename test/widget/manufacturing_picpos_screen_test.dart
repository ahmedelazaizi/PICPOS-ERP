import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/manufacturing_providers.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/manufacturing_picpos/manufacturing_picpos_screen.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.getDefaultWarehouse();
  });
  tearDown(() => db.close());

  testWidgets('PicPos manufacturing renders tabs and gated BOM actions', (tester) async {
    await _pumpScreen(tester, db: db);
    expect(find.text('قوائم المكوّنات'), findsWidgets);
    expect(find.text('أوامر الإنتاج'), findsWidgets);
    expect(find.text('التشفية'), findsWidgets);
    expect(find.text('التكاليف الإضافية'), findsWidgets);
    expect(find.text('التقارير'), findsWidgets);
    expect(find.byType(PermissionGuard), findsWidgets);
    expect(find.text('التكلفة تشمل المواد والتحميل وتقترح سعر البيع'), findsWidgets);
  });

  testWidgets('butchery dialog previews loss and posts an order from a template', (tester) async {
    await tester.pump();
    const warehouse = _testWarehouse;
    final carcass = await _insertProduct(db, 'W-CARCASS', cost: 100);
    final cut = await _insertProduct(db, 'W-CUT', sale: 1);
    await db.adjustStock(productId: carcass, warehouseId: warehouse.id, quantity: 1, type: 'opening', unitCost: 100);
    final template = await db.createButcheryTemplate(
      carcassProductId: carcass,
      name: 'قالب اختبار',
      valuationMethod: 'by_weight',
    );
    await db.addButcheryTemplateLine(
      templateId: template,
      outputProductId: cut,
      expectedYieldPercent: 50,
      isByProduct: false,
    );

    await _pumpScreen(
      tester,
      db: db,
      warehouses: [warehouse],
      products: [_productEntity(carcass, 'W-CARCASS'), _productEntity(cut, 'W-CUT')],
    );
    await tester.tap(find.text('التشفية').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أمر تشفية جديد'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تكلفة الوحدة'), findsOneWidget);
    expect(find.textContaining('الفاقد:'), findsOneWidget);
    await tester.tap(find.text('حفظ وترحيل'));
    await tester.pumpAndSettle();

    final posted = await db.customSelect(
      "SELECT id FROM butchery_orders WHERE status = 'posted'",
    ).get();
    expect(posted, hasLength(1));
  });

  testWidgets('production orders start then complete through row actions', (tester) async {
    await tester.pump();
    const warehouse = _testWarehouse;
    final finished = await _insertProduct(db, 'W-FINISHED');
    final raw = await _insertProduct(db, 'W-RAW', cost: 2);
    await db.adjustStock(productId: raw, warehouseId: warehouse.id, quantity: 10, type: 'opening', unitCost: 2);
    final bom = await db.createBOM(
      finishedProductId: finished,
      bomCode: 'W-BOM',
      components: [
        {'rawMaterialId': raw, 'quantity': 1.0, 'quantityInBase': 1.0},
      ],
    );
    final orderId = await db.into(db.manufacturingOrders).insert(
      ManufacturingOrdersCompanion.insert(
        orderNumber: 'MFG-00001',
        bomId: bom,
        orderedQty: 2,
        warehouseId: warehouse.id,
        startDate: DateTime.now(),
      ),
    );
    final order = await (db.select(db.manufacturingOrders)..where((row) => row.id.equals(orderId))).getSingle();
    final orderStream = StreamController<List<ManufacturingOrderData>>();
    addTearDown(orderStream.close);
    await tester.pumpWidget(_screenScope(
      db: db,
      boms: [(await db.getBOM(bom))!],
      orders: orderStream.stream,
      products: [_productEntity(finished, 'W-FINISHED'), _productEntity(raw, 'W-RAW', cost: 2)],
      warehouses: [warehouse],
    ));
    orderStream.add([order]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أوامر الإنتاج').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بدء'));
    await tester.pumpAndSettle();
    expect((await (db.select(db.manufacturingOrders)..where((row) => row.id.equals(orderId))).getSingle()).status, 'in_progress');

    final started = await (db.select(db.manufacturingOrders)..where((row) => row.id.equals(orderId))).getSingle();
    orderStream.add([started]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إكمال'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إكمال').last);
    await tester.pumpAndSettle();
    expect((await (db.select(db.manufacturingOrders)..where((row) => row.id.equals(orderId))).getSingle()).status, 'completed');
  });

  testWidgets('reports tab renders posted butchery yield rows', (tester) async {
    await tester.pump();
    const warehouse = _testWarehouse;
    final carcass = await _insertProduct(db, 'R-CARCASS', cost: 100);
    final cut = await _insertProduct(db, 'R-CUT', sale: 1);
    await db.adjustStock(productId: carcass, warehouseId: warehouse.id, quantity: 1, type: 'opening', unitCost: 100);
    final template = await db.createButcheryTemplate(carcassProductId: carcass, name: 'قالب تقرير', valuationMethod: 'by_weight');
    await db.addButcheryTemplateLine(templateId: template, outputProductId: cut, expectedYieldPercent: 50, isByProduct: false);
    final order = await db.createButcheryOrder(
      carcassProductId: carcass,
      warehouseId: warehouse.id,
      carcassQuantity: 1,
      carcassWeight: 1000,
      carcassTotalCost: 100,
      templateId: template,
      outputs: [
        {'outputProductId': cut, 'actualWeight': 500.0},
      ],
    );
    await db.customStatement(
      "UPDATE butchery_orders SET status = 'posted', posted_at = ? WHERE id = ?",
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, order],
    );

    await _pumpScreen(
      tester,
      db: db,
      warehouses: [warehouse],
      products: [_productEntity(carcass, 'R-CARCASS'), _productEntity(cut, 'R-CUT')],
    );
    await tester.ensureVisible(find.text('التقارير').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('التقارير').first);
    await tester.pumpAndSettle();
    expect(find.text('تقرير عائد التشفية'), findsOneWidget);
    expect(find.text('R-CUT'), findsOneWidget);
    expect(find.text('فعلي %'), findsOneWidget);
  });

}

Future<int> _insertProduct(AppDatabase db, String code, {double cost = 0, double sale = 0}) async {
  final id = await db.insertProduct(ProductsCompanion.insert(
        code: code,
        name: code,
        costPrice: Value(cost),
        salePrice: Value(sale),
        trackInventory: const Value(true),
      ),
    );
  return id;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AppDatabase db,
  List<Warehouse> warehouses = const [],
  List<ProductEntity> products = const [],
}) async {
  await tester.pumpWidget(_screenScope(
    db: db,
    boms: const [],
    orders: Stream.value(const <ManufacturingOrderData>[]),
    products: products,
    warehouses: warehouses,
  ));
  await tester.pumpAndSettle();
}

Widget _screenScope({
  required AppDatabase db,
  required List<BillOfMaterialData> boms,
  required Stream<List<ManufacturingOrderData>> orders,
  required List<ProductEntity> products,
  required List<Warehouse> warehouses,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      allBomsProvider.overrideWith((ref) => Stream.value(boms)),
      manufacturingOrdersProvider.overrideWith((ref) => orders),
      allMfgOrderCostsProvider.overrideWith((ref) => Stream.value(const <MfgOrderCostData>[])),
      allProductsProvider.overrideWith((ref) => Stream.value(products)),
      warehouseListProvider.overrideWith((ref) async => warehouses),
      currentUserPermissionsProvider.overrideWith((ref) async => const <String>[]),
    ],
    child: const MaterialApp(home: ManufacturingPicposScreen()),
  );
}

const _testWarehouse = Warehouse(
  id: 1,
  name: 'المخزن الرئيسي',
  type: 'main',
  isDefault: true,
  isActive: true,
  isSystemDefault: true,
  rowVersion: 0,
);

ProductEntity _productEntity(int id, String name, {double cost = 0}) => ProductEntity(
      id: id,
      code: name,
      name: name,
      salePrice: 0,
      costPrice: cost,
      currentStock: 0,
      minStock: 0,
    );

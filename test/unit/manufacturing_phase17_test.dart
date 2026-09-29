import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;
  });

  tearDown(() => db.close());

  Future<int> product(String code, double cost, {double sale = 0}) {
    return db.insertProduct(ProductsCompanion.insert(
      code: code,
      name: code,
      costPrice: Value(cost),
      salePrice: Value(sale),
      trackInventory: const Value(true),
    ));
  }

  test('BOM materials use quantityInBase and add overhead to total', () async {
    final finished = await product('P17-FIN', 0);
    final flour = await product('P17-FLOUR', 10);
    final bom = await db.createBOM(
      finishedProductId: finished,
      bomCode: 'P17-KG',
      overheadPercent: 20,
      components: [
        {
          'rawMaterialId': flour,
          'quantity': 1000.0,
          'quantityInBase': 0.001,
          'unit': 'جرام',
        },
      ],
    );

    final preview = await db.getBomCostPreview(bom);
    expect(preview.materialsCost, closeTo(10, 0.0001));
    expect(preview.overheadAmount, closeTo(2, 0.0001));
    expect(preview.totalCost, closeTo(12, 0.0001));
  });

  test('suggested price obeys both profit bases', () async {
    final finished = await product('P17-PRICE-FIN', 0);
    final raw = await product('P17-PRICE-RAW', 100);
    final components = [
      {'rawMaterialId': raw, 'quantity': 1.0, 'quantityInBase': 1.0},
    ];
    final after = await db.createBOM(
      finishedProductId: finished,
      bomCode: 'P17-AFTER',
      overheadPercent: 30,
      profitPercent: 40,
      components: components,
    );
    final materialsOnly = await db.createBOM(
      finishedProductId: finished,
      bomCode: 'P17-MATERIALS',
      overheadPercent: 30,
      profitPercent: 40,
      profitBasis: 'materials_only',
      components: components,
    );

    expect((await db.getBomCostPreview(after)).suggestedSellingPrice, closeTo(182, 0.0001));
    expect((await db.getBomCostPreview(materialsOnly)).suggestedSellingPrice, closeTo(170, 0.0001));
  });

  test('weight output excludes count units and calculates pieces with override', () async {
    final finished = await product('P17-WEIGHT-FIN', 0);
    final raw = await product('P17-WEIGHT-RAW', 1);
    final quantities = [1000, 1000, 15, 25, 150, 50, 50, 25];
    final components = [
      for (var i = 0; i < quantities.length; i++)
        {'rawMaterialId': raw, 'quantity': quantities[i].toDouble(), 'unit': 'جرام'},
      {'rawMaterialId': raw, 'quantity': 2.0, 'unit': 'حبّة'},
    ];
    final bom = await db.createBOM(
      finishedProductId: finished,
      bomCode: 'P17-WEIGHT',
      pieceWeight: 55,
      components: components,
    );

    var preview = await db.getBomCostPreview(bom);
    expect(preview.outputWeight, closeTo(2315, 0.0001));
    expect(preview.pieces, 42);

    await db.updateBOM(
      bomId: bom,
      finishedProductId: finished,
      bomCode: 'P17-WEIGHT',
      outputQuantityOverride: 2090,
      pieceWeight: 55,
      components: components,
    );
    final storedOverride = await db.customSelect(
      'SELECT output_quantity_override FROM bill_of_materials WHERE id = ?',
      variables: [Variable<int>(bom)],
    ).getSingle();
    expect((storedOverride.data['output_quantity_override'] as num).toDouble(), closeTo(2090, 0.0001));
    preview = await db.getBomCostPreview(bom);
    expect(preview.outputWeight, closeTo(2090, 0.0001));
    expect(preview.pieces, 38);
  });

  test('sales-value and by-weight butchery allocation stays balanced and reversible', () async {
    final carcass = await product('P17-CARCASS', 1000);
    final thigh = await product('P17-THIGH', 0, sale: 10);
    final shoulder = await product('P17-SHOULDER', 0, sale: 20);
    final bone = await product('P17-BONE', 0, sale: 5);
    await db.adjustStock(
      productId: carcass,
      warehouseId: warehouseId,
      quantity: 1,
      type: 'opening',
      unitCost: 1000,
    );
    final template = await db.createButcheryTemplate(
      carcassProductId: carcass,
      name: 'قالب P17',
      valuationMethod: 'sales_value',
    );
    await db.addButcheryTemplateLine(
      templateId: template,
      outputProductId: thigh,
      expectedYieldPercent: 50,
      isByProduct: false,
      valuationPrice: 1,
    );
    await db.addButcheryTemplateLine(
      templateId: template,
      outputProductId: shoulder,
      expectedYieldPercent: 30,
      isByProduct: false,
      valuationPrice: 2,
    );
    await db.addButcheryTemplateLine(
      templateId: template,
      outputProductId: bone,
      expectedYieldPercent: 20,
      isByProduct: true,
      valuationPrice: 0.5,
    );
    final order = await db.createButcheryOrder(
      carcassProductId: carcass,
      warehouseId: warehouseId,
      carcassQuantity: 1,
      carcassWeight: 1000,
      carcassTotalCost: 1000,
      templateId: template,
      outputs: [
        {'outputProductId': thigh, 'actualWeight': 500.0},
        {'outputProductId': shoulder, 'actualWeight': 300.0},
        {'outputProductId': bone, 'actualWeight': 200.0, 'isByProduct': true},
      ],
    );
    final posted = await db.postButcheryOrder(order);
    expect(posted['varianceFlag'], isFalse);
    final lines = await db.customSelect(
      'SELECT allocated_cost FROM butchery_order_lines WHERE order_id = ? ORDER BY id',
      variables: [Variable<int>(order)],
    ).get();
    expect((lines[2].data['allocated_cost'] as num).toDouble(), closeTo(100, 0.0001));
    final balance = await db.customSelect(
      '''SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c
         FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id
         WHERE e.reference_type = 'butchery_order' AND e.reference_id = ?''',
      variables: [Variable<int>(order)],
    ).getSingle();
    expect((balance.data['d'] as num).toDouble(), closeTo((balance.data['c'] as num).toDouble(), 0.0001));

    await db.reverseButcheryOrder(order);
    final state = await db.customSelect(
      'SELECT status FROM butchery_orders WHERE id = ?',
      variables: [Variable<int>(order)],
    ).getSingle();
    expect(state.data['status'], 'reversed');

    final weightTemplate = await db.createButcheryTemplate(
      carcassProductId: carcass,
      name: 'قالب وزن P17',
      valuationMethod: 'by_weight',
      varianceThresholdPercent: 2,
    );
    await db.addButcheryTemplateLine(
      templateId: weightTemplate,
      outputProductId: thigh,
      expectedYieldPercent: 50,
      isByProduct: false,
    );
    await db.addButcheryTemplateLine(
      templateId: weightTemplate,
      outputProductId: shoulder,
      expectedYieldPercent: 30,
      isByProduct: false,
    );
    final weightOrder = await db.createButcheryOrder(
      carcassProductId: carcass,
      warehouseId: warehouseId,
      carcassQuantity: 1,
      carcassWeight: 1000,
      carcassTotalCost: 1000,
      templateId: weightTemplate,
      outputs: [
        {'outputProductId': thigh, 'actualWeight': 500.0},
        {'outputProductId': shoulder, 'actualWeight': 300.0},
      ],
    );
    final weightPosted = await db.postButcheryOrder(weightOrder);
    expect(weightPosted['lossWeight'], closeTo(200, 0.0001));
    final weightLines = await db.customSelect(
      'SELECT allocated_cost FROM butchery_order_lines WHERE order_id = ? ORDER BY id',
      variables: [Variable<int>(weightOrder)],
    ).get();
    expect((weightLines[0].data['allocated_cost'] as num).toDouble(), closeTo(500, 0.0001));
    expect((weightLines[1].data['allocated_cost'] as num).toDouble(), closeTo(300, 0.0001));
  });

  test('v180 butchery tables expose every sync column', () async {
    const tableNames = [
      'butchery_templates',
      'butchery_template_lines',
      'butchery_orders',
      'butchery_order_lines',
    ];
    for (final tableName in tableNames) {
      final columns = await db.customSelect('PRAGMA table_info($tableName)').get();
      final columnNames = columns.map((row) => row.data['name']).toSet();
      expect(columnNames, containsAll(['global_id', 'last_modified_at', 'deleted_at', 'origin_client_id', 'row_version']));
    }
  });
}

part of '../database.dart';

double _mfgNumber(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// Cost figures stored for a BOM and used by both the editor and production.
class BomCostPreview {
  const BomCostPreview({
    required this.materialsCost,
    required this.overheadAmount,
    required this.totalCost,
    required this.suggestedSellingPrice,
    required this.outputWeight,
    required this.pieces,
  });

  final double materialsCost;
  final double overheadAmount;
  final double totalCost;
  final double suggestedSellingPrice;
  final double outputWeight;
  final int? pieces;
}

/// Raw-SQL manufacturing extensions kept outside Drift table classes.
extension ManufacturingV180Dao on AppDatabase {
  Future<void> ensureManufacturingV180Schema() async {
    final createStatements = _isPostgres
        ? _manufacturingV180PostgresCreateStatements
        : _manufacturingV180CreateStatements;
    final columnStatements = _isPostgres
        ? _manufacturingV180PostgresColumnStatements
        : _manufacturingV180ColumnStatements;
    for (final statement in createStatements) {
      await customStatement(statement);
    }
    for (final statement in columnStatements) {
      try {
        await customStatement(statement);
      } catch (error) {
        if (!isIdempotentMigrationError(error.toString())) rethrow;
      }
    }
    for (final statement in _manufacturingV180IndexStatements) {
      await customStatement(statement);
    }
  }

  Future<void> recalculateStoredBomCosts() async {
    await ensureManufacturingV180Schema();
    final boms = await customSelect(
      'SELECT id FROM bill_of_materials WHERE deleted_at IS NULL',
    ).get();
    for (final row in boms) {
      await _recalculateBomCost(row.data['id'] as int);
    }
  }

  Future<BomCostPreview> getBomCostPreview(int bomId) async {
    await ensureManufacturingV180Schema();
    final bom = await customSelect(
      '''SELECT expected_quantity, overhead_percent, profit_percent, profit_basis,
                piece_weight, output_quantity_override, output_unit
         FROM bill_of_materials WHERE id = ?''',
      variables: [Variable<int>(bomId)],
    ).getSingle();
    final components = await customSelect(
      '''SELECT quantity, quantity_in_base, unit, wastage_percent, raw_material_id
         FROM bom_components WHERE bom_id = ? AND deleted_at IS NULL''',
      variables: [Variable<int>(bomId)],
    ).get();
    final materials = await _calculateMaterialsCost(components);
    final overheadPercent = _number(bom.data['overhead_percent']);
    final profitPercent = _number(bom.data['profit_percent']);
    final overhead = materials * overheadPercent / 100;
    final total = materials + overhead;
    final basis = bom.data['profit_basis']?.toString() ?? 'after_overhead';
    final suggested = basis == 'materials_only'
        ? materials * (1 + (overheadPercent + profitPercent) / 100)
        : total * (1 + profitPercent / 100);
    final outputWeight = await _calculateOutputWeight(components);
    final effectiveOutputWeight =
        _numberOrNull(bom.data['output_quantity_override']) ?? outputWeight;
    final pieceWeight = _numberOrNull(bom.data['piece_weight']);
    final pieces = pieceWeight != null && pieceWeight > 0
        ? (effectiveOutputWeight / pieceWeight).floor()
        : null;
    return BomCostPreview(
      materialsCost: materials,
      overheadAmount: overhead,
      totalCost: total,
      suggestedSellingPrice: suggested,
      outputWeight: effectiveOutputWeight,
      pieces: pieces,
    );
  }

  Future<void> applyBomSuggestedSalePrice(int bomId) async {
    final preview = await getBomCostPreview(bomId);
    final bom = await customSelect(
      'SELECT finished_product_id, expected_quantity FROM bill_of_materials WHERE id = ?',
      variables: [Variable<int>(bomId)],
    ).getSingle();
    final expected = _number(bom.data['expected_quantity']);
    final price = expected > 0 ? preview.suggestedSellingPrice / expected : 0;
    await customStatement(
      'UPDATE products SET sale_price = ?, updated_at = ? WHERE id = ?',
      [price, DateTime.now().millisecondsSinceEpoch ~/ 1000, bom.data['finished_product_id']],
    );
  }

  Future<double> calculateBomOutputWeight(int bomId) async {
    final preview = await getBomCostPreview(bomId);
    return preview.outputWeight;
  }

  Future<int> createButcheryTemplate({
    required int carcassProductId,
    required String name,
    String valuationMethod = 'sales_value',
    double varianceThresholdPercent = 2,
  }) async {
    await ensureManufacturingV180Schema();
    final gid = UuidV7.generate();
    return customInsert(
      '''INSERT INTO butchery_templates
         (carcass_product_id, name, valuation_method, variance_threshold_percent, global_id)
         VALUES (?, ?, ?, ?, ?)''',
      variables: [
        Variable<int>(carcassProductId), Variable<String>(name),
        Variable<String>(valuationMethod), Variable<double>(varianceThresholdPercent),
        Variable<String>(gid),
      ],
    );
  }

  Future<int> addButcheryTemplateLine({
    required int templateId,
    required int outputProductId,
    required double expectedYieldPercent,
    required bool isByProduct,
    double valuationPrice = 0,
    String unit = 'كجم',
  }) async {
    await ensureManufacturingV180Schema();
    return customInsert(
      '''INSERT INTO butchery_template_lines
         (template_id, output_product_id, expected_yield_percent, is_by_product,
          valuation_price, unit, global_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      variables: [
        Variable<int>(templateId), Variable<int>(outputProductId),
        Variable<double>(expectedYieldPercent), Variable<bool>(isByProduct),
        Variable<double>(valuationPrice), Variable<String>(unit),
        Variable<String>(UuidV7.generate()),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getButcheryTemplates() async {
    await ensureManufacturingV180Schema();
    final rows = await customSelect(
      '''SELECT t.*, p.name AS carcass_name
         FROM butchery_templates t JOIN products p ON p.id = t.carcass_product_id
         WHERE t.deleted_at IS NULL ORDER BY t.name''',
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<List<Map<String, dynamic>>> getButcheryTemplateLines(int templateId) async {
    await ensureManufacturingV180Schema();
    final rows = await customSelect(
      '''SELECT l.*, p.name AS output_name
         FROM butchery_template_lines l JOIN products p ON p.id = l.output_product_id
         WHERE l.template_id = ? AND l.deleted_at IS NULL ORDER BY l.id''',
      variables: [Variable<int>(templateId)],
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<List<Map<String, dynamic>>> getButcheryOrders() async {
    await ensureManufacturingV180Schema();
    final rows = await customSelect(
      '''SELECT o.*, c.name AS carcass_name, t.name AS template_name
         FROM butchery_orders o
         JOIN products c ON c.id = o.carcass_product_id
         LEFT JOIN butchery_templates t ON t.id = o.template_id
         WHERE o.deleted_at IS NULL ORDER BY o.created_at DESC, o.id DESC''',
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<List<Map<String, dynamic>>> getButcheryOrderLines(int orderId) async {
    await ensureManufacturingV180Schema();
    final rows = await customSelect(
      '''SELECT l.*, p.name AS output_name
         FROM butchery_order_lines l JOIN products p ON p.id = l.output_product_id
         WHERE l.order_id = ? AND l.deleted_at IS NULL ORDER BY l.id''',
      variables: [Variable<int>(orderId)],
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<int> createButcheryOrder({
    required int carcassProductId,
    required int warehouseId,
    required double carcassQuantity,
    required double carcassWeight,
    required double carcassTotalCost,
    required List<Map<String, dynamic>> outputs,
    int? templateId,
    String weightUnit = 'g',
    String? notes,
  }) async {
    await ensureManufacturingV180Schema();
    if (carcassQuantity <= 0 || carcassWeight <= 0 || carcassTotalCost < 0) {
      throw Exception('بيانات الذبيحة غير صالحة: الكمية والوزن موجبان والتكلفة غير سالبة');
    }
    if (outputs.isEmpty) throw Exception('يجب تسجيل مخرج واحد على الأقل في أمر التشفية');
    return transaction(() async {
      final count = await customSelect(
        'SELECT COUNT(*) AS n FROM butchery_orders',
      ).getSingle();
      final number = 'BUT-${((_number(count.data['n'])).toInt() + 1).toString().padLeft(5, '0')}';
      final orderId = await customInsert(
        '''INSERT INTO butchery_orders
           (order_number, template_id, carcass_product_id, warehouse_id,
            carcass_quantity, carcass_weight, carcass_total_cost, weight_unit,
            notes, global_id)
           VALUES (?, CASE WHEN ? = 0 THEN NULL ELSE ? END, ?, ?, ?, ?, ?, ?, ?, ?)''',
        variables: [
          Variable<String>(number), Variable<int>(templateId ?? 0),
           Variable<int>(templateId ?? 0),
          Variable<int>(carcassProductId), Variable<int>(warehouseId),
          Variable<double>(carcassQuantity), Variable<double>(carcassWeight),
          Variable<double>(carcassTotalCost), Variable<String>(weightUnit),
          Variable<String>(notes ?? ''), Variable<String>(UuidV7.generate()),
        ],
      );
      for (final output in outputs) {
        final weight = _number(output['actualWeight']);
        if (weight <= 0 || output['outputProductId'] is! int) {
          throw Exception('وزن ومُنتج كل مخرج في أمر التشفية مطلوبان');
        }
        await customStatement(
          '''INSERT INTO butchery_order_lines
             (order_id, output_product_id, actual_weight, is_by_product,
              sale_price, global_id)
             VALUES (?, ?, ?, ?, ?, ?)''',
          [
            orderId, output['outputProductId'], weight,
            _isPostgres ? output['isByProduct'] == true : (output['isByProduct'] == true ? 1 : 0),
            _number(output['salePrice']), UuidV7.generate(),
          ],
        );
      }
      return orderId;
    });
  }

  Future<Map<String, dynamic>> postButcheryOrder(int orderId) async {
    await ensureManufacturingV180Schema();
    return transaction(() async {
      final order = await customSelect(
        'SELECT * FROM butchery_orders WHERE id = ?',
        variables: [Variable<int>(orderId)],
      ).getSingle();
      if (order.data['status'] != 'draft') {
        throw Exception('لا يمكن ترحيل أمر تشفية ليس مسودة');
      }
      final lines = await customSelect(
        '''SELECT l.*, p.sale_price AS current_sale_price,
                  tl.valuation_price AS template_valuation_price
           FROM butchery_order_lines l
           JOIN products p ON p.id = l.output_product_id
           LEFT JOIN butchery_template_lines tl
             ON tl.template_id = NULLIF(?, 0) AND tl.output_product_id = l.output_product_id
           WHERE l.order_id = ? ORDER BY l.id''',
        variables: [
          Variable<int>((order.data['template_id'] as int?) ?? 0),
          Variable<int>(orderId),
        ],
      ).get();
      final carcassWeight = _number(order.data['carcass_weight']);
      final unit = order.data['weight_unit']?.toString() ?? 'g';
      final outputsWeight = lines.fold<double>(
        0, (sum, row) => sum + _toGrams(_number(row.data['actual_weight']), unit),
      );
      final inputWeight = _toGrams(carcassWeight, unit);
      final lossWeight = inputWeight - outputsWeight;
      if (lossWeight < -0.000001) {
        throw Exception('أوزان المخرجات تتجاوز وزن الذبيحة — راجع البيانات قبل الترحيل');
      }
      final lossPercent = inputWeight == 0 ? 0 : lossWeight * 100 / inputWeight;
      final template = order.data['template_id'] == null
          ? null
          : await customSelect(
              'SELECT valuation_method, variance_threshold_percent FROM butchery_templates WHERE id = ?',
              variables: [Variable<int>(order.data['template_id'] as int)],
            ).getSingleOrNull();
      final valuationMethod = template?.data['valuation_method']?.toString() ?? 'sales_value';
      final threshold = _number(template?.data['variance_threshold_percent']) == 0
          ? 2
          : _number(template?.data['variance_threshold_percent']);
      final expectedYield = await _expectedYield(order.data['template_id'] as int?);
      final variance = (100 - (inputWeight == 0 ? 0 : outputsWeight * 100 / inputWeight)) - (100 - expectedYield);
      if (variance.abs() > threshold) {
        debugPrint('[Butchery] variance beyond threshold: order=$orderId variance=$variance');
      }
      final lossCost = _number(order.data['carcass_total_cost']) *
          (inputWeight == 0 ? 0 : lossWeight / inputWeight);
      final allocation = _allocateButcheryCost(
        lines, _number(order.data['carcass_total_cost']) - lossCost, valuationMethod, unit,
      );
      final warehouse = await getWarehouseById(order.data['warehouse_id'] as int);
      final branchId = warehouse?.branchId;
      final carcassUnitCost = _number(order.data['carcass_total_cost']) /
          _number(order.data['carcass_quantity']);
      await adjustStock(
        productId: order.data['carcass_product_id'] as int,
        warehouseId: order.data['warehouse_id'] as int,
        quantity: -_number(order.data['carcass_quantity']),
        type: 'butchery_out', referenceType: 'butchery_order', referenceId: orderId,
        unitCost: carcassUnitCost, branchId: branchId,
        notes: 'صرف ذبيحة لأمر التشفية ${order.data['order_number']}',
      );
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].data;
        final cost = allocation[i];
        final weight = _number(line['actual_weight']);
        await customStatement(
          'UPDATE butchery_order_lines SET allocated_cost = ?, unit_cost = ? WHERE id = ?',
          [cost, weight > 0 ? cost / weight : 0, line['id']],
        );
        await adjustStock(
          productId: line['output_product_id'] as int,
          warehouseId: order.data['warehouse_id'] as int,
          quantity: weight,
          type: 'butchery_in', referenceType: 'butchery_order', referenceId: orderId,
          unitCost: weight > 0 ? cost / weight : 0, branchId: branchId,
          notes: 'ناتج تشفية ${order.data['order_number']}',
        );
      }
      await _postButcheryJournal(
        orderId: orderId,
        order: order.data,
        lines: lines,
        allocation: allocation,
        lossCost: lossCost,
        branchId: branchId,
      );
      await customStatement(
        '''UPDATE butchery_orders SET status = 'posted', output_weight = ?,
           loss_weight = ?, loss_percent = ?, variance_percent = ?, variance_flag = ?,
           posted_at = ? WHERE id = ?''',
        [outputsWeight, lossWeight, lossPercent, variance, _isPostgres ? variance.abs() > threshold : (variance.abs() > threshold ? 1 : 0),
         DateTime.now().millisecondsSinceEpoch ~/ 1000, orderId],
      );
      return {
        'orderId': orderId,
        'outputWeight': outputsWeight,
        'lossWeight': lossWeight,
        'lossPercent': lossPercent,
        'variancePercent': variance,
        'varianceFlag': variance.abs() > threshold,
        'allocatedCost': allocation.fold<double>(0, (a, b) => a + b) + lossCost,
      };
    });
  }

  Future<void> reverseButcheryOrder(int orderId) async {
    await ensureManufacturingV180Schema();
    await transaction(() async {
      final order = await customSelect(
        'SELECT * FROM butchery_orders WHERE id = ?',
        variables: [Variable<int>(orderId)],
      ).getSingle();
      if (order.data['status'] != 'posted') {
        throw Exception('لا يمكن عكس أمر تشفية غير مُرحّل');
      }
      final lines = await customSelect(
        'SELECT * FROM butchery_order_lines WHERE order_id = ? ORDER BY id',
        variables: [Variable<int>(orderId)],
      ).get();
      final warehouse = await getWarehouseById(order.data['warehouse_id'] as int);
      for (final line in lines) {
        await adjustStock(
          productId: line.data['output_product_id'] as int,
          warehouseId: order.data['warehouse_id'] as int,
          quantity: -_number(line.data['actual_weight']),
          type: 'butchery_reverse', referenceType: 'butchery_order', referenceId: orderId,
          unitCost: _number(line.data['unit_cost']), branchId: warehouse?.branchId,
          notes: 'عكس ناتج تشفية ${order.data['order_number']}',
        );
      }
      await adjustStock(
        productId: order.data['carcass_product_id'] as int,
        warehouseId: order.data['warehouse_id'] as int,
        quantity: _number(order.data['carcass_quantity']),
        type: 'butchery_reverse', referenceType: 'butchery_order', referenceId: orderId,
        unitCost: _number(order.data['carcass_total_cost']) /
            _number(order.data['carcass_quantity']), branchId: warehouse?.branchId,
        notes: 'عكس صرف ذبيحة ${order.data['order_number']}',
      );
      await _postButcheryReversalJournal(orderId, order.data, lines, warehouse?.branchId);
      await customStatement(
        "UPDATE butchery_orders SET status = 'reversed', reversed_at = ? WHERE id = ?",
        [DateTime.now().millisecondsSinceEpoch ~/ 1000, orderId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getButcheryYieldReport({
    required DateTime from,
    required DateTime to,
  }) async {
    await ensureManufacturingV180Schema();
    final rows = await customSelect(
      '''WITH order_totals AS (
             SELECT o.id, o.carcass_weight,
                    COALESCE(SUM(l.actual_weight), 0) AS output_weight,
                    COALESCE(o.loss_weight, 0) AS stored_loss_weight
             FROM butchery_orders o
             LEFT JOIN butchery_order_lines l ON l.order_id = o.id
             WHERE o.status = 'posted' AND o.posted_at >= ? AND o.posted_at < ?
             GROUP BY o.id, o.carcass_weight, o.loss_weight
           )
           SELECT p.name AS product_name,
                  SUM(l.actual_weight) AS actual_weight,
                  SUM(l.allocated_cost) AS allocated_cost,
                  SUM(CASE WHEN l.is_by_product = 1 THEN l.actual_weight ELSE 0 END)
                    AS by_product_weight,
                  COALESCE(MAX(tl.expected_yield_percent), 0) AS expected_yield_percent,
                  CASE WHEN (SELECT SUM(carcass_weight) FROM order_totals) > 0
                    THEN SUM(l.actual_weight) * 100.0 /
                         (SELECT SUM(carcass_weight) FROM order_totals)
                    ELSE 0 END AS actual_yield_percent,
                  CASE WHEN (SELECT SUM(carcass_weight) FROM order_totals) > 0
                    THEN SUM(l.actual_weight) * 100.0 /
                         (SELECT SUM(carcass_weight) FROM order_totals) -
                         COALESCE(MAX(tl.expected_yield_percent), 0)
                    ELSE 0 END AS variance_percent,
                  (SELECT SUM(stored_loss_weight) FROM order_totals) AS total_loss_weight
           FROM butchery_order_lines l
           JOIN butchery_orders o ON o.id = l.order_id
           JOIN products p ON p.id = l.output_product_id
           LEFT JOIN butchery_template_lines tl
             ON tl.template_id = o.template_id AND tl.output_product_id = l.output_product_id
           WHERE o.status = 'posted' AND o.posted_at >= ? AND o.posted_at < ?
           GROUP BY l.output_product_id, p.name ORDER BY p.name''',
      variables: [dateVar(from), dateVar(to), dateVar(from), dateVar(to)],
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<void> _recalculateBomCost(int bomId) async {
    final rows = await customSelect(
      '''SELECT quantity, quantity_in_base, unit, wastage_percent, raw_material_id
         FROM bom_components WHERE bom_id = ? AND deleted_at IS NULL''',
      variables: [Variable<int>(bomId)],
    ).get();
    final bom = await customSelect(
      'SELECT overhead_percent FROM bill_of_materials WHERE id = ?',
      variables: [Variable<int>(bomId)],
    ).getSingleOrNull();
    if (bom == null) return;
    final materials = await _calculateMaterialsCost(rows);
    final overhead = materials * _number(bom.data['overhead_percent']) / 100;
    await customStatement(
      '''UPDATE bill_of_materials SET materials_cost = ?, overhead_amount = ?, estimated_cost = ?
         WHERE id = ?''',
      [materials, overhead, materials + overhead, bomId],
    );
  }

  Future<double> calculateBomMaterialsCostFromMaps(
    List<Map<String, dynamic>> components,
  ) async {
    final ids = components.map((component) => component['rawMaterialId'] as int).toList();
    final prices = await _getLastPurchasePricesByIds(ids);
    final productsById = await getProductsByIds(ids);
    var total = 0.0;
    for (final component in components) {
      final id = component['rawMaterialId'] as int;
      final price = _number(prices[id]) > 0
          ? _number(prices[id])
          : productsById[id]?.costPrice ?? 0;
      total += price * _number(component['quantity']) *
          _number(component['quantityInBase'] ?? 1) *
          (1 + _number(component['wastagePercent']) / 100);
    }
    return total;
  }

  Future<double> _calculateMaterialsCost(List<QueryRow> rows) async {
    final ids = rows.map((row) => row.data['raw_material_id'] as int).toList();
    final prices = await _getLastPurchasePricesByIds(ids);
    final productsById = await getProductsByIds(ids);
    var total = 0.0;
    for (final row in rows) {
      final materialId = row.data['raw_material_id'] as int;
      final price = prices[materialId] ?? productsById[materialId]?.costPrice ?? 0;
      total += price * _number(row.data['quantity']) * _number(row.data['quantity_in_base']) *
          (1 + _number(row.data['wastage_percent']) / 100);
    }
    return total;
  }

  Future<double> _calculateOutputWeight(List<QueryRow> rows) async {
    var grams = 0.0;
    for (final row in rows) {
      final unit = row.data['unit']?.toString() ?? '';
      final converted = _weightFactorToGrams(unit);
      if (converted != null) {
        grams += _number(row.data['quantity']) * _number(row.data['quantity_in_base']) * converted;
      }
    }
    return grams;
  }

  Future<double> _expectedYield(int? templateId) async {
    if (templateId == null) return 0;
    final row = await customSelect(
      'SELECT COALESCE(SUM(expected_yield_percent), 0) AS yield FROM butchery_template_lines WHERE template_id = ?',
      variables: [Variable<int>(templateId)],
    ).getSingle();
    return _number(row.data['yield']);
  }

  List<double> _allocateButcheryCost(
    List<QueryRow> lines,
    double allocatableCost,
    String valuationMethod,
    String weightUnit,
  ) {
    final main = [for (var i = 0; i < lines.length; i++) if (!_isTrue(lines[i].data['is_by_product'])) i];
    final byProducts = [for (var i = 0; i < lines.length; i++) if (_isTrue(lines[i].data['is_by_product'])) i];
    final result = List<double>.filled(lines.length, 0);
    if (valuationMethod == 'by_weight') {
      final grams = main.fold<double>(0, (sum, i) => sum + _toGrams(_number(lines[i].data['actual_weight']), weightUnit));
      if (grams <= 0) throw Exception('لا يمكن توزيع تكلفة التشفية بالوزن دون مخرجات رئيسية موزونة');
      for (final i in main) {
        result[i] = allocatableCost * _toGrams(_number(lines[i].data['actual_weight']), weightUnit) / grams;
      }
      return result;
    }
    var byProductValue = 0.0;
    for (final i in byProducts) {
      final salePrice = _lineSalePrice(lines[i].data);
      byProductValue += _number(lines[i].data['actual_weight']) * salePrice;
      result[i] = _number(lines[i].data['actual_weight']) * salePrice;
    }
    if (byProductValue > allocatableCost + 0.000001) {
      throw Exception('قيمة المنتجات الثانوية تتجاوز تكلفة الذبيحة — لا يمكن ترحيل أمر غير متزن');
    }
    final mainValue = main.fold<double>(
      0, (sum, i) => sum + _number(lines[i].data['actual_weight']) * _lineSalePrice(lines[i].data),
    );
    if (main.isNotEmpty && mainValue <= 0) {
      throw Exception('أسعار بيع القطع الرئيسية مطلوبة لتوزيع التكلفة بقيمة البيع');
    }
    final remaining = allocatableCost - byProductValue;
    for (final i in main) {
      final value = _number(lines[i].data['actual_weight']) * _lineSalePrice(lines[i].data);
      result[i] = remaining * value / mainValue;
    }
    return result;
  }

  Future<void> _postButcheryJournal({
    required int orderId,
    required Map<String, dynamic> order,
    required List<QueryRow> lines,
    required List<double> allocation,
    required double lossCost,
    required int? branchId,
  }) async {
    final inventoryCode = await accountingDao.getMappedAccountCode(
      'inventory', AccountingDao.accountPurposes['inventory']!,
    );
    final lossCode = await accountingDao.getMappedAccountCode(
      'inventory_shrinkage', AccountingDao.accountPurposes['inventory_shrinkage']!,
    );
    final inventory = await accountingDao.getAccountByCode(inventoryCode);
    final loss = await accountingDao.getAccountByCode(lossCode);
    if (inventory == null || loss == null) {
      throw Exception('حساب المخزون أو خسائر المخزون غير مُعرَّف — تعذّر ترحيل التشفية');
    }
    final journalLines = <JournalLine>[];
    for (var i = 0; i < lines.length; i++) {
      if (allocation[i] <= 0) continue;
      journalLines.add(JournalLine(accountId: inventory.id, debit: allocation[i], credit: 0, description: 'ناتج تشفية'));
    }
    if (lossCost > 0) {
      journalLines.add(JournalLine(accountId: loss.id, debit: lossCost, credit: 0, description: 'فاقد تشفية'));
    }
    journalLines.add(JournalLine(
      accountId: inventory.id,
      debit: 0,
      credit: allocation.fold<double>(0, (a, b) => a + b) + lossCost,
      description: 'صرف الذبيحة',
    ));
    await accountingDao.createJournalEntry(
      date: DateTime.now(), description: 'ترحيل أمر تشفية ${order['order_number']}',
      lines: journalLines, referenceType: 'butchery_order', referenceId: orderId,
      isAutoPosted: true, branchId: branchId,
      globalId: JournalEntryGid.compute(sourceType: 'butchery', sourceGid: 'order$orderId', verb: 'post'),
    );
  }

  Future<void> _postButcheryReversalJournal(
    int orderId, Map<String, dynamic> order, List<QueryRow> lines, int? branchId,
  ) async {
    final inventoryCode = await accountingDao.getMappedAccountCode(
      'inventory', AccountingDao.accountPurposes['inventory']!,
    );
    final lossCode = await accountingDao.getMappedAccountCode(
      'inventory_shrinkage', AccountingDao.accountPurposes['inventory_shrinkage']!,
    );
    final inventory = await accountingDao.getAccountByCode(inventoryCode);
    final loss = await accountingDao.getAccountByCode(lossCode);
    if (inventory == null || loss == null) {
      throw Exception('حساب المخزون أو خسائر المخزون غير مُعرَّف — تعذّر عكس التشفية');
    }
    var outputCost = 0.0;
    for (final line in lines) outputCost += _number(line.data['allocated_cost']);
    final lossCost = _number(order['carcass_total_cost']) - outputCost;
    final journalLines = <JournalLine>[
      JournalLine(accountId: inventory.id, debit: _number(order['carcass_total_cost']), credit: 0, description: 'استرجاع الذبيحة'),
      JournalLine(accountId: inventory.id, debit: 0, credit: outputCost, description: 'عكس نواتج التشفية'),
    ];
    if (lossCost > 0) journalLines.add(JournalLine(accountId: loss.id, debit: 0, credit: lossCost, description: 'عكس فاقد التشفية'));
    await accountingDao.createJournalEntry(
      date: DateTime.now(), description: 'عكس أمر تشفية ${order['order_number']}',
      lines: journalLines, referenceType: 'butchery_reverse', referenceId: orderId,
      isAutoPosted: true, branchId: branchId,
      globalId: JournalEntryGid.compute(sourceType: 'butchery', sourceGid: 'order$orderId', verb: 'reverse'),
    );
  }

  static bool _isTrue(Object? value) => value == true || value == 1 || value == '1';
  static double _lineSalePrice(Map<String, dynamic> line) {
    final direct = _number(line['sale_price']);
    if (direct > 0) return direct;
    final template = _number(line['template_valuation_price']);
    if (template > 0) return template;
    return _number(line['current_sale_price']);
  }
  static double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  static double? _numberOrNull(Object? value) => value == null ? null : _number(value);
  static double _toGrams(double value, String unit) => value * (_weightFactorToGrams(unit) ?? 1);
  static double? _weightFactorToGrams(String unit) {
    final normalized = unit.trim().toLowerCase();
    if (normalized == 'g' || normalized == 'جرام' || normalized == 'غرام' || normalized == 'جم') return 1;
    if (normalized == 'kg' || normalized == 'كيلو' || normalized == 'كجم') return 1000;
    return null;
  }
}

const _manufacturingV180CreateStatements = <String>[
  '''CREATE TABLE IF NOT EXISTS butchery_templates (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       carcass_product_id INTEGER NOT NULL REFERENCES products(id),
       name TEXT NOT NULL,
       valuation_method TEXT NOT NULL DEFAULT 'sales_value',
       variance_threshold_percent REAL NOT NULL DEFAULT 2,
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_template_lines (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       template_id INTEGER NOT NULL REFERENCES butchery_templates(id),
       output_product_id INTEGER NOT NULL REFERENCES products(id),
       expected_yield_percent REAL NOT NULL DEFAULT 0,
       is_by_product INTEGER NOT NULL DEFAULT 0,
       valuation_price REAL NOT NULL DEFAULT 0,
       unit TEXT NOT NULL DEFAULT 'كجم',
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_orders (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       order_number TEXT NOT NULL,
       template_id INTEGER REFERENCES butchery_templates(id),
       carcass_product_id INTEGER NOT NULL REFERENCES products(id),
       warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
       carcass_quantity REAL NOT NULL,
       carcass_weight REAL NOT NULL,
       carcass_total_cost REAL NOT NULL,
       weight_unit TEXT NOT NULL DEFAULT 'g',
       status TEXT NOT NULL DEFAULT 'draft',
       output_weight REAL NOT NULL DEFAULT 0,
       loss_weight REAL NOT NULL DEFAULT 0,
       loss_percent REAL NOT NULL DEFAULT 0,
       variance_percent REAL NOT NULL DEFAULT 0,
       variance_flag INTEGER NOT NULL DEFAULT 0,
       notes TEXT,
       posted_at INTEGER,
       reversed_at INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_order_lines (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       order_id INTEGER NOT NULL REFERENCES butchery_orders(id),
       output_product_id INTEGER NOT NULL REFERENCES products(id),
       actual_weight REAL NOT NULL,
       allocated_cost REAL NOT NULL DEFAULT 0,
       unit_cost REAL NOT NULL DEFAULT 0,
       is_by_product INTEGER NOT NULL DEFAULT 0,
       sale_price REAL NOT NULL DEFAULT 0,
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _manufacturingV180PostgresCreateStatements = <String>[
  '''CREATE TABLE IF NOT EXISTS butchery_templates (
       id SERIAL PRIMARY KEY,
       carcass_product_id INTEGER NOT NULL REFERENCES products(id),
       name TEXT NOT NULL,
       valuation_method TEXT NOT NULL DEFAULT 'sales_value',
       variance_threshold_percent DOUBLE PRECISION NOT NULL DEFAULT 2,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_template_lines (
       id SERIAL PRIMARY KEY,
       template_id INTEGER NOT NULL REFERENCES butchery_templates(id),
       output_product_id INTEGER NOT NULL REFERENCES products(id),
       expected_yield_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
       is_by_product BOOLEAN NOT NULL DEFAULT FALSE,
       valuation_price DOUBLE PRECISION NOT NULL DEFAULT 0,
       unit TEXT NOT NULL DEFAULT 'كجم',
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_orders (
       id SERIAL PRIMARY KEY,
       order_number TEXT NOT NULL,
       template_id INTEGER REFERENCES butchery_templates(id),
       carcass_product_id INTEGER NOT NULL REFERENCES products(id),
       warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
       carcass_quantity DOUBLE PRECISION NOT NULL,
       carcass_weight DOUBLE PRECISION NOT NULL,
       carcass_total_cost DOUBLE PRECISION NOT NULL,
       weight_unit TEXT NOT NULL DEFAULT 'g',
       status TEXT NOT NULL DEFAULT 'draft',
       output_weight DOUBLE PRECISION NOT NULL DEFAULT 0,
       loss_weight DOUBLE PRECISION NOT NULL DEFAULT 0,
       loss_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
       variance_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
       variance_flag BOOLEAN NOT NULL DEFAULT FALSE,
       notes TEXT,
       posted_at BIGINT,
       reversed_at BIGINT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS butchery_order_lines (
       id SERIAL PRIMARY KEY,
       order_id INTEGER NOT NULL REFERENCES butchery_orders(id),
       output_product_id INTEGER NOT NULL REFERENCES products(id),
       actual_weight DOUBLE PRECISION NOT NULL,
       allocated_cost DOUBLE PRECISION NOT NULL DEFAULT 0,
       unit_cost DOUBLE PRECISION NOT NULL DEFAULT 0,
       is_by_product BOOLEAN NOT NULL DEFAULT FALSE,
       sale_price DOUBLE PRECISION NOT NULL DEFAULT 0,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _manufacturingV180PostgresColumnStatements = <String>[
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS overhead_percent DOUBLE PRECISION NOT NULL DEFAULT 0',
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS materials_cost DOUBLE PRECISION NOT NULL DEFAULT 0',
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS overhead_amount DOUBLE PRECISION NOT NULL DEFAULT 0',
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS profit_percent DOUBLE PRECISION NOT NULL DEFAULT 0',
  "ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS profit_basis TEXT NOT NULL DEFAULT 'after_overhead'",
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS piece_weight DOUBLE PRECISION',
  'ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS output_quantity_override DOUBLE PRECISION',
  "ALTER TABLE bill_of_materials ADD COLUMN IF NOT EXISTS output_unit TEXT NOT NULL DEFAULT 'g'",
];

const _manufacturingV180ColumnStatements = <String>[
  "ALTER TABLE bill_of_materials ADD COLUMN overhead_percent REAL NOT NULL DEFAULT 0",
  "ALTER TABLE bill_of_materials ADD COLUMN materials_cost REAL NOT NULL DEFAULT 0",
  "ALTER TABLE bill_of_materials ADD COLUMN overhead_amount REAL NOT NULL DEFAULT 0",
  "ALTER TABLE bill_of_materials ADD COLUMN profit_percent REAL NOT NULL DEFAULT 0",
  "ALTER TABLE bill_of_materials ADD COLUMN profit_basis TEXT NOT NULL DEFAULT 'after_overhead'",
  "ALTER TABLE bill_of_materials ADD COLUMN piece_weight REAL",
  "ALTER TABLE bill_of_materials ADD COLUMN output_quantity_override REAL",
  "ALTER TABLE bill_of_materials ADD COLUMN output_unit TEXT NOT NULL DEFAULT 'g'",
];

const _manufacturingV180IndexStatements = <String>[
  'CREATE INDEX IF NOT EXISTS idx_butchery_templates_carcass ON butchery_templates(carcass_product_id)',
  'CREATE INDEX IF NOT EXISTS idx_butchery_template_lines_template ON butchery_template_lines(template_id)',
  'CREATE INDEX IF NOT EXISTS idx_butchery_orders_status_date ON butchery_orders(status, posted_at)',
  'CREATE INDEX IF NOT EXISTS idx_butchery_order_lines_order ON butchery_order_lines(order_id)',
];

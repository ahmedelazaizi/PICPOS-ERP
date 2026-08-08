part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REPORT BUILDER DAO — منشئ التقارير المخصصة (Phase C5)
// ═══════════════════════════════════════════════════════════════════════════

extension ReportBuilderDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // REPORT CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a custom report
  Future<int> createCustomReport({
    required String name,
    required String sourceEntity,
    required String columns,
    String? description,
    String? filters,
    String? groupBy,
    String? sortBy,
    String? aggregates,
    int? createdBy,
    bool isShared = false,
  }) {
    return into(customReports).insert(
      CustomReportsCompanion.insert(
        name: name,
        sourceEntity: sourceEntity,
        columns: columns,
        description: Value(description),
        filters: Value(filters),
        groupBy: Value(groupBy),
        sortBy: Value(sortBy),
        aggregates: Value(aggregates),
        createdBy: Value(createdBy),
        isShared: Value(isShared),
      ),
    );
  }

  /// Update a custom report
  Future<void> updateCustomReport(int reportId, CustomReportsCompanion data) async {
    await (update(customReports)..where((r) => r.id.equals(reportId)))
        .write(data.copyWith(updatedAt: Value(DateTime.now())));
  }

  /// Get all reports (user's own + shared)
  Future<List<CustomReportData>> getCustomReports({int? userId}) {
    final query = select(customReports)
      ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]);

    if (userId != null) {
      query.where((r) =>
          r.createdBy.equals(userId) | r.isShared.equals(true));
    }

    return query.get();
  }

  /// Get a single report
  Future<CustomReportData?> getCustomReport(int reportId) {
    return (select(customReports)..where((r) => r.id.equals(reportId)))
        .getSingleOrNull();
  }

  /// Delete a report
  Future<void> deleteCustomReport(int reportId) async {
    await (delete(savedReportRuns)..where((r) => r.reportId.equals(reportId))).go();
    await (delete(customReports)..where((r) => r.id.equals(reportId))).go();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPORT EXECUTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Execute a custom report and return results
  /// [allowedBranchIds] — null = وصول كامل · {ids} = الفروع دي · {} = لا شيء.
  ///
  /// الحصر دلالته **مختلفة لكل كيان مصدر**، فمعمول كخريطة لا كفلتر واحد
  /// (شوف [_scopeClauseFor]). وكيان مالوش فلتر مدعوم بيرجّع **فاضي** لمستخدم
  /// محصور بدل ما يتساب يسرّب: الحصر الجزئي أخطر من غيابه، لأن التقرير بيبان
  /// محصوراً والمستخدم بيثق فيه.
  Future<List<Map<String, dynamic>>> executeReport(
    int reportId, {
    Set<int>? allowedBranchIds,
  }) async {
    final report = await getCustomReport(reportId);
    if (report == null) return [];

    final stopwatch = Stopwatch()..start();

    // Build the query dynamically
    final query = _buildReportQuery(report, allowedBranchIds);
    if (query == null) {
      debugPrint('[ReportBuilder] رُفض: الكيان "${report.sourceEntity}" مالوش '
          'فلتر حصر مدعوم، والمستخدم محصور بفرع');
      return [];
    }
    final results = await customSelect(query).get();

    stopwatch.stop();

    // Log the execution
    await into(savedReportRuns).insert(
      SavedReportRunsCompanion.insert(
        reportId: reportId,
        rowCount: Value(results.length),
        executionMs: Value(stopwatch.elapsedMilliseconds),
      ),
    );

    return results.map((r) => r.data).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIELD REGISTRY
  // ─────────────────────────────────────────────────────────────────────────

  /// Get available fields for a source entity
  List<Map<String, String>> getAvailableFields(String sourceEntity) {
    switch (sourceEntity) {
      case 'products':
        return [
          {'key': 'name', 'label': 'اسم المنتج', 'type': 'text'},
          {'key': 'code', 'label': 'الكود', 'type': 'text'},
          {'key': 'barcode', 'label': 'الباركود', 'type': 'text'},
          {'key': 'price', 'label': 'سعر البيع', 'type': 'number'},
          {'key': 'cost', 'label': 'سعر التكلفة', 'type': 'number'},
          {'key': 'wholesale_price', 'label': 'سعر الجملة', 'type': 'number'},
          {'key': 'tax_rate', 'label': 'نسبة الضريبة', 'type': 'number'},
          {'key': 'category_name', 'label': 'التصنيف', 'type': 'text'},
          {'key': 'unit_name', 'label': 'الوحدة', 'type': 'text'},
          {'key': 'is_active', 'label': 'نشط', 'type': 'boolean'},
          {'key': 'quantity', 'label': 'الكمية المتوفرة', 'type': 'number'},
        ];
      case 'sales_invoices':
        return [
          {'key': 'invoice_number', 'label': 'رقم الفاتورة', 'type': 'text'},
          {'key': 'date', 'label': 'التاريخ', 'type': 'date'},
          {'key': 'party_name', 'label': 'العميل', 'type': 'text'},
          {'key': 'total', 'label': 'الإجمالي', 'type': 'number'},
          {'key': 'discount', 'label': 'الخصم', 'type': 'number'},
          {'key': 'tax', 'label': 'الضريبة', 'type': 'number'},
          {'key': 'net_total', 'label': 'صافي الإجمالي', 'type': 'number'},
          {'key': 'payment_status', 'label': 'حالة الدفع', 'type': 'text'},
          {'key': 'sale_type', 'label': 'نوع البيع', 'type': 'text'},
        ];
      case 'purchase_invoices':
        return [
          {'key': 'invoice_number', 'label': 'رقم الفاتورة', 'type': 'text'},
          {'key': 'date', 'label': 'التاريخ', 'type': 'date'},
          {'key': 'party_name', 'label': 'المورد', 'type': 'text'},
          {'key': 'total', 'label': 'الإجمالي', 'type': 'number'},
          {'key': 'discount', 'label': 'الخصم', 'type': 'number'},
          {'key': 'tax', 'label': 'الضريبة', 'type': 'number'},
          {'key': 'net_total', 'label': 'صافي الإجمالي', 'type': 'number'},
        ];
      case 'parties':
        return [
          {'key': 'name', 'label': 'الاسم', 'type': 'text'},
          {'key': 'phone', 'label': 'الهاتف', 'type': 'text'},
          {'key': 'address', 'label': 'العنوان', 'type': 'text'},
          {'key': 'type', 'label': 'النوع', 'type': 'text'},
          {'key': 'balance', 'label': 'الرصيد', 'type': 'number'},
          {'key': 'credit_limit', 'label': 'حد الائتمان', 'type': 'number'},
        ];
      case 'journal_entries':
        return [
          {'key': 'entry_number', 'label': 'رقم القيد', 'type': 'text'},
          {'key': 'date', 'label': 'التاريخ', 'type': 'date'},
          {'key': 'description', 'label': 'البيان', 'type': 'text'},
          {'key': 'total_debit', 'label': 'مدين', 'type': 'number'},
          {'key': 'total_credit', 'label': 'دائن', 'type': 'number'},
          {'key': 'is_auto_posted', 'label': 'آلي', 'type': 'boolean'},
        ];
      default:
        return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUERY BUILDER (internal)
  // ─────────────────────────────────────────────────────────────────────────

  /// شرط الحصر لكل كيان. `null` = **مالوش فلتر مدعوم** ⇒ ارفض التقرير.
  ///
  /// عن قصد مش فلتراً واحداً: كل مصدر بيوصل للفرع بطريق مختلف، والتعميم بيدي
  /// إما تسريباً أو صفر صفوف مضلّلاً.
  ///   • الفواتير      → `branch_id` مباشرةً (‏L3 حطّه على الصف)
  ///   • الأطراف       → `is_global OR branch_ids LIKE` (زي _watchPartiesForBranches)
  ///   • الأصناف       → بيانات أساسية على مستوى الشركة، مفيش قيم مالية عبر فروع
  ///   • قيود اليومية  → الوصول للفرع عبر مراكز التكلفة، مش عمود على الصف
  ///   • الموظفون      → `employees.branch_id` **ما بيتكتبش أصلاً** (مانع H6)،
  ///                     فحصره بيدي صفر صفوف بشكل مضلّل بدل ما يحصر
  ///   • أرصدة المخزون → الحصر بالمخزن لا الفرع (‏getWarehouseScopeForUser)
  String? _scopeClauseFor(String entity, Set<int> ids) {
    final list = ids.join(',');
    switch (entity) {
      case 'sales_invoices':
      case 'purchase_invoices':
        final t = _getTableName(entity);
        return '$t.branch_id IN ($list) OR $t.branch_id IS NULL';
      case 'parties':
        final ors = ids
            .map((id) =>
                "(',' || COALESCE(parties.branch_ids, '') || ',') LIKE '%,$id,%'")
            .join(' OR ');
        return 'parties.is_global = 1 OR $ors';
      case 'products':
        return '1 = 1';
      default:
        return null;
    }
  }

  String? _buildReportQuery(
      CustomReportData report, Set<int>? allowedBranchIds) {
    final tableName = _getTableName(report.sourceEntity);
    
    // Map friendly keys to proper SQL columns to prevent "no such column" errors
    String mappedCols = '*';
    if (report.columns.isNotEmpty) {
      mappedCols = report.columns.split(',').map((c) {
        final col = c.trim();
        switch (report.sourceEntity) {
          case 'products':
            if (col == 'category_name') return 'c.name AS category_name';
            if (col == 'unit_name') return 'u.name AS unit_name';
            if (col == 'quantity') return 'ib.quantity AS quantity';
            return 'products.$col';
          case 'sales_invoices':
            if (col == 'date') return 'sales_invoices.invoice_date AS date';
            if (col == 'party_name') return 'p.name AS party_name';
            if (col == 'net_total') return 'sales_invoices.total AS net_total';
            // كان `'مكتمل' AS payment_status` — نص ثابت باسم حقل حقيقي، فكل
            // صف بيقول «مكتمل» مهما كانت الحقيقة. و`payment_status` مش عمود
            // في الجدول أصلاً، فلازم يُشتق من paid مقابل total.
            if (col == 'payment_status') {
              return "CASE WHEN sales_invoices.paid >= sales_invoices.total "
                  "THEN 'مكتمل' "
                  "WHEN sales_invoices.paid > 0 THEN 'جزئي' "
                  "ELSE 'غير مدفوع' END AS payment_status";
            }
            // كان `'أجل' AS sale_type` — غلط مرتين: العمود موجود فعلاً، و«أجل»
            // مش من مجال قيمه (default/talabat/careem/ashyae). «أجل مقابل
            // نقدي» دلالتها payment_method = 'credit'، حقل تاني تماماً.
            if (col == 'sale_type') {
              return 'sales_invoices.sale_type AS sale_type';
            }
            return 'sales_invoices.$col';
          case 'purchase_invoices':
            if (col == 'date') return 'purchase_invoices.invoice_date AS date';
            if (col == 'party_name') return 'p.name AS party_name';
            if (col == 'net_total') return 'purchase_invoices.total AS net_total';
            return 'purchase_invoices.$col';
          case 'parties':
            return 'parties.$col';
          case 'journal_entries':
            if (col == 'date') return 'journal_entries.entry_date AS date';
            return 'journal_entries.$col';
        }
        return col;
      }).join(', ');
    }

    var query = 'SELECT $mappedCols FROM $tableName';

    // Add joins for related data
    final joins = _getJoins(report.sourceEntity);
    if (joins.isNotEmpty) {
      query += ' $joins';
    }

    // حصر الفروع + فلاتر المستخدم في نفس الـWHERE. الحصر **الأول** وبقوسين
    // حواليه، فأي فلتر مستخدم بـOR ما يقدرش يوسّع النطاق.
    final conditions = <String>[];
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        conditions.add('1 = 0'); // فشل مقفول
      } else {
        final clause =
            _scopeClauseFor(report.sourceEntity, allowedBranchIds);
        if (clause == null) return null; // كيان مالوش فلتر مدعوم ⇒ ارفض
        conditions.add('($clause)');
      }
    }
    if (report.filters != null && report.filters!.isNotEmpty) {
      conditions.add('(${_buildWhereClause(report.filters!)})');
    }
    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }

    // Add group by
    if (report.groupBy != null && report.groupBy!.isNotEmpty) {
      query += ' GROUP BY ${report.groupBy}';
    }

    // Add sort
    if (report.sortBy != null && report.sortBy!.isNotEmpty) {
      query += ' ORDER BY ${report.sortBy}';
    }

    query += ' LIMIT 10000'; // Safety limit

    return query;
  }

  String _getTableName(String entity) {
    switch (entity) {
      case 'products': return 'products';
      case 'sales_invoices': return 'sales_invoices';
      case 'purchase_invoices': return 'purchase_invoices';
      case 'parties': return 'parties';
      case 'journal_entries': return 'journal_entries';
      case 'inventory_balances': return 'inventory_balances';
      case 'employees': return 'employees';
      default: return entity;
    }
  }

  String _getJoins(String entity) {
    switch (entity) {
      case 'products':
        // الـjoin المباشر على inventory_balances كان بلا تجميع: صنف في مخزنين
        // بيطلّع **صفّين** في التقرير، فأي جمع لعمود بيتضاعف بعدد المخازن —
        // والمستخدم شايف الصنف مكرر بلا سبب ظاهر. التجميع المسبق بيدي صف واحد
        // لكل صنف و`quantity` = إجمالي المخازن، وهو المعنى اللي الحقل معروض بيه
        // («الكمية المتوفرة»).
        return '''
          LEFT JOIN categories c ON c.id = products.category_id
          LEFT JOIN units u ON u.id = products.unit_id
          LEFT JOIN (
            SELECT product_id, SUM(quantity) AS quantity
            FROM inventory_balances GROUP BY product_id
          ) ib ON ib.product_id = products.id
        ''';
      case 'sales_invoices':
        return 'LEFT JOIN parties p ON p.id = sales_invoices.customer_id';
      case 'purchase_invoices':
        return 'LEFT JOIN parties p ON p.id = purchase_invoices.supplier_id';
      default:
        return '';
    }
  }

  String _buildWhereClause(String filtersJson) {
    try {
      final filters = filtersJson;
      // Filters are stored as pre-built WHERE conditions
      return filters;
    } catch (_) {
      return '1=1';
    }
  }
}

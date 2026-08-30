part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REPORT BUILDER DAO — منشئ التقارير المخصصة (Phase C5)
// ═══════════════════════════════════════════════════════════════════════════

/// سقفُ صفوف تقريرٍ مخصَّص واحد.
///
/// كان `LIMIT 10000` رقماً مدفوناً في بناء الاستعلام بتعليق `// Safety limit`،
/// فلا المستخدمُ يعلم بوجوده ولا الكودُ يتيح تغييره. معلَنٌ هنا كي يُقاس عليه
/// الإبلاغُ ويُمرَّر في الاختبار بقيمةٍ صغيرة بدل زرعِ عشرةِ آلاف صفّ.
const int kReportBuilderRowLimit = 10000;

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
  /// [rowLimit] — سقفُ الصفوف المُرجَعة. و[onRowLimitReached] يُنادى **فقط** إذا
  /// كانت هناك صفوفٌ أكثر منه ⇒ التقريرُ مقتطع.
  ///
  /// كان السقفُ `LIMIT 10000` مدفوناً في بناء الاستعلام **بلا أن ينطق**: من
  /// يبني تقريراً على ١٥ ألف صفٍّ يرى عشرةَ آلاف ويجمع العمودَ ويقدّمه إجمالياً
  /// للفترة. والتقريرُ المقتطعُ لا يُميَّز عن الكامل — وهذا أخطرُ من فشلٍ، لأن
  /// الفشلَ يُرى.
  Future<List<Map<String, dynamic>>> executeReport(
    int reportId, {
    Set<int>? allowedBranchIds,
    int rowLimit = kReportBuilderRowLimit,
    void Function(int limit)? onRowLimitReached,
  }) async {
    final report = await getCustomReport(reportId);
    if (report == null) return [];

    final stopwatch = Stopwatch()..start();

    // Build the query dynamically
    final query = _buildReportQuery(report, allowedBranchIds, rowLimit);
    if (query == null) {
      debugPrint('[ReportBuilder] رُفض: الكيان "${report.sourceEntity}" مالوش '
          'فلتر حصر مدعوم (أو الفلتر مرفوض)، والمستخدم محصور بفرع');
      return [];
    }
    var results = await customSelect(query.sql, variables: query.vars).get();

    // الصفُّ الزائد دليلُ القصّ: يُبلَّغ عنه ثم يُطرَح فلا يُعرَض ولا يُحتسب.
    // والإبلاغُ **قبل** الطرح كي لا يبقى الاكتشافُ متوقفاً على ترتيبِ سطور.
    if (results.length > rowLimit) {
      onRowLimitReached?.call(rowLimit);
      results = results.sublist(0, rowLimit);
    }

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

  /// عواملُ الفلتر المتاحة لنوعِ حقلٍ ما — **نفسُ القائمة التي يفرضها
  /// التنفيذ** ([_kFilterOpsByFieldType])، لا نسخةٌ منها في الواجهة.
  ///
  /// لو كانت القائمتان اثنتين لأمكن أن تعرض الواجهةُ عاملاً يرفضه المحرِّك،
  /// فيخرج التقريرُ **مرفوضاً بالكامل**: صفرُ صفوفٍ بلا رسالةِ خطأ ولا حقلٍ
  /// معطَّل — أي عطلٌ لا يُرى.
  List<Map<String, String>> getFilterOperators(String fieldType) {
    const labels = {
      '=': 'يساوي',
      '!=': 'لا يساوي',
      '>': 'أكبر من',
      '>=': 'أكبر من أو يساوي',
      '<': 'أصغر من',
      '<=': 'أصغر من أو يساوي',
      'contains': 'يحتوي',
    };
    // الترتيبُ ثابتٌ لا يتبع ترتيبَ الـSet كي لا تتبدّل المنسدلةُ بين تشغيلتين.
    const order = ['=', '!=', 'contains', '>', '>=', '<', '<='];
    final allowed = _kFilterOpsByFieldType[fieldType] ?? const <String>{};
    return [
      for (final op in order)
        if (allowed.contains(op)) {'op': op, 'label': labels[op]!},
    ];
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
  ///   • الموظفون      → `branch_id` مباشرةً. كان مرفوضاً لأن العمود **ما كانش
  ///                     بيتكتب أصلاً** (مانع H6)، فحصرُه كان بيدي صفر صفوف
  ///                     مضلّلاً. اتقفل H6 (‏addEmployee بيكتبه) فبقى الحصر
  ///                     ذا معنى — وهو المصدر الوحيد اللي فيه **رواتب**
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
      case 'employees':
        // نفس دلالة الفواتير: `branch_id` على الصف، وNULL = مستوى الشركة
        // فيبقى مرئياً — مطابقةً لـ`_employeeBranchScope` في hr_extensions.
        return 'employees.branch_id IN ($list) '
            'OR employees.branch_id IS NULL';
      default:
        return null;
    }
  }

  /// تعبيرُ الحقل المعروض في SQL — **بلا `AS`**.
  ///
  /// المُعلَن في `getAvailableFields` ليس بالضرورة اسمَ العمود: `price` عمودُه
  /// `sale_price`، و`type` في الأطراف لا عمودَ له أصلاً بل يُشتقّ من صفتَين،
  /// و`total_debit` يُشتقّ باستعلامٍ فرعيّ. وكان بثُّ الاسم المعروض كما هو
  /// يعطي `no such column` **فيفشل التقريرُ كلُّه** لا العمودُ وحده.
  ///
  /// ⚠️ **مشتركٌ إجبارياً بين `SELECT` والفلتر.** لو بنى كلٌّ خريطته لفلتَر
  /// الفلترُ على عمودٍ آخر — أو على عمودٍ لا وجود له — بينما الأعمدةُ المعروضة
  /// صحيحة، فيخرج تقريرٌ **يبدو سليماً وقد صُفّي بشرطٍ غير الذي طلبه المستخدم**.
  /// والاسمُ المستعار (`AS`) لا يُرى داخل `WHERE` في SQLite، فالتعبيرُ نفسُه هو
  /// ما يتكرّر هناك.
  String _fieldSqlExpression(String entity, String col) {
    switch (entity) {
      case 'products':
        if (col == 'category_name') return 'c.name';
        if (col == 'unit_name') return 'u.name';
        if (col == 'quantity') return 'ib.quantity';
        if (col == 'price') return 'products.sale_price';
        if (col == 'cost') return 'products.cost_price';
        return 'products.$col';
      case 'sales_invoices':
        if (col == 'date') return 'sales_invoices.invoice_date';
        if (col == 'party_name') return 'p.name';
        if (col == 'net_total') return 'sales_invoices.total';
        // كان `'مكتمل' AS payment_status` — نص ثابت باسم حقل حقيقي، فكل
        // صف بيقول «مكتمل» مهما كانت الحقيقة. و`payment_status` مش عمود
        // في الجدول أصلاً، فلازم يُشتق من paid مقابل total.
        if (col == 'payment_status') {
          // وفرقُ التقريب يُضاف للمقبوض قبل المقارنة: بيعةٌ نقديّةٌ مقرَّبةٌ
          // مسدَّدةٌ بالكامل كانت تُقرأ «جزئي» لأنّ `paid` أقلُّ من `total`
          // بمقدارٍ ليس ديناً.
          return "CASE WHEN sales_invoices.paid + "
              "COALESCE(sales_invoices.rounding_adjustment, 0) "
              ">= sales_invoices.total "
              "THEN 'مكتمل' "
              "WHEN sales_invoices.paid > 0 THEN 'جزئي' "
              "ELSE 'غير مدفوع' END";
        }
        // كان `'أجل' AS sale_type` — غلط مرتين: العمود موجود فعلاً، و«أجل»
        // مش من مجال قيمه (default/talabat/careem/ashyae). «أجل مقابل
        // نقدي» دلالتها payment_method = 'credit'، حقل تاني تماماً.
        return 'sales_invoices.$col';
      case 'purchase_invoices':
        if (col == 'date') return 'purchase_invoices.invoice_date';
        if (col == 'party_name') return 'p.name';
        if (col == 'net_total') return 'purchase_invoices.total';
        return 'purchase_invoices.$col';
      case 'parties':
        // لا عمودَ `type` في الجدول — النوعُ صفتان منطقيتان
        // (`is_customer`/`is_supplier`)، وقد يكون الطرفُ الاثنين معاً.
        if (col == 'type') {
          return "CASE "
              "WHEN parties.is_customer = 1 AND parties.is_supplier = 1 "
              "THEN 'عميل ومورد' "
              "WHEN parties.is_supplier = 1 THEN 'مورد' "
              "WHEN parties.is_customer = 1 THEN 'عميل' "
              "ELSE '-' END";
        }
        return 'parties.$col';
      case 'journal_entries':
        if (col == 'date') return 'journal_entries.entry_date';
        // لا عمودَي إجمالٍ في الجدول — الإجماليُّ يُشتقّ بجمع السطور.
        //
        // استعلامٌ فرعيٌّ مترابط لا `JOIN`: الـJOIN على السطور يُنتج صفاً
        // لكل سطرٍ في القيد فيتضاعف كلُّ عمودٍ آخر — نفسُ عطلِ تضاعفِ
        // الأصناف بعدد المخازن الذي أُصلح في `_getJoins`.
        if (col == 'total_debit' || col == 'total_credit') {
          final side = col == 'total_debit' ? 'debit' : 'credit';
          return '(SELECT COALESCE(SUM(jel.$side), 0) '
              'FROM journal_entry_lines jel '
              'WHERE jel.entry_id = journal_entries.id)';
        }
        return 'journal_entries.$col';
    }
    return col;
  }

  /// نوعُ الحقل كما **يُعلنه السجلّ** — لا كما يُخمَّن من اسم العمود.
  /// `null` = الحقلُ ليس من حقول هذا الكيان ⇒ يُرفَض.
  String? _fieldType(String entity, String key) {
    for (final f in getAvailableFields(entity)) {
      if (f['key'] == key) return f['type'];
    }
    return null;
  }

  ({String sql, List<Variable> vars})? _buildReportQuery(
      CustomReportData report, Set<int>? allowedBranchIds, int rowLimit) {
    final tableName = _getTableName(report.sourceEntity);

    // Map friendly keys to proper SQL columns to prevent "no such column" errors
    String mappedCols = '*';
    if (report.columns.isNotEmpty) {
      mappedCols = report.columns.split(',').map((c) {
        final col = c.trim();
        final expr = _fieldSqlExpression(report.sourceEntity, col);
        // الاسمُ المُعلَن يُحفَظ بـ`AS` كي تبقى رؤوسُ الجدول في الواجهة هي ما
        // اختاره المستخدم لا اسمَ العمود الخام.
        return expr == col ? col : '$expr AS $col';
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
    final vars = <Variable>[];
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
    final rawFilters = report.filters?.trim() ?? '';
    if (rawFilters.isNotEmpty) {
      // التمييزُ بأوّل حرفٍ غير فراغ: `[` ⇒ الصيغةُ المهيكلة التي توثّقها
      // السكيما وتنتجها الواجهة. وما عداه نصُّ SQL خامّ من تقريرٍ قديم.
      if (rawFilters.startsWith('[')) {
        final built = _buildStructuredFilter(report.sourceEntity, rawFilters);
        if (built == null) return null; // فلتر مرفوض ⇒ ارفض التقرير كله
        if (built.sql.isNotEmpty) {
          conditions.add('(${built.sql})');
          vars.addAll(built.vars);
        }
      } else {
        final safe = _buildWhereClause(rawFilters);
        if (safe == null) return null; // فلتر مرفوض ⇒ ارفض التقرير كله
        conditions.add('($safe)');
      }
    }
    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }

    // ── التجميعُ والترتيب ─────────────────────────────────────────────
    //
    // 🔴 **يُصفَّيان على سجلّ الحقول قبل أن يلمسا SQL.** هذان العمودان
    // يُركَّبان في نصّ الاستعلام حرفيّاً (‏لا يُربَطان معاملاتٍ — لا يمكن:
    // `GROUP BY ?` ليس SQL صالحاً)، فأيُّ نصٍّ يصلهما يصل المحرّك. وحتّى
    // اليوم لم يكن ذلك مبلوغاً لأنّ `createCustomReport` على المستودع لا
    // تقبلهما أصلاً، فهما `null` دائماً. ومع فتحِ لوحتَي «تجميع حسب»
    // و«الترتيب» في واجهة PicPos صار لهما كاتبٌ — فلزم الحارس.
    //
    // و`_fieldType` سجلٌّ **مغلق**: يعيد `null` لأيّ مفتاحٍ ليس من حقول
    // الكيان. فالمقبولُ هو ما أعلنه السجلُّ وحدَه، والباقي يُرفَض التقريرُ
    // كلُّه لأجله — نفسُ سياسة الفلتر المرفوض فوق.
    if (report.groupBy != null && report.groupBy!.isNotEmpty) {
      final fields = report.groupBy!.split(',').map((f) => f.trim()).toList();
      for (final f in fields) {
        if (_fieldType(report.sourceEntity, f) == null) {
          debugPrint('[ReportBuilder] رُفض: حقلُ تجميعٍ "$f" ليس من حقول '
              '"${report.sourceEntity}"');
          return null;
        }
      }
      final exprs =
          fields.map((f) => _fieldSqlExpression(report.sourceEntity, f));
      query += ' GROUP BY ${exprs.join(', ')}';
    }

    if (report.sortBy != null && report.sortBy!.isNotEmpty) {
      final terms = <String>[];
      for (final raw in report.sortBy!.split(',')) {
        final parts = raw.trim().split(RegExp(r'\s+'));
        if (parts.isEmpty || parts.first.isEmpty) continue;
        final field = parts.first;
        if (_fieldType(report.sourceEntity, field) == null) {
          debugPrint('[ReportBuilder] رُفض: حقلُ ترتيبٍ "$field" ليس من حقول '
              '"${report.sourceEntity}"');
          return null;
        }
        // الاتّجاهُ كلمتان لا غير — و`ASC` هو الافتراض حين يُترَك.
        final dir = parts.length > 1 ? parts[1].toUpperCase() : 'ASC';
        if (dir != 'ASC' && dir != 'DESC') {
          debugPrint('[ReportBuilder] رُفض: اتّجاهُ ترتيبٍ "$dir" غيرُ معروف');
          return null;
        }
        terms.add('${_fieldSqlExpression(report.sourceEntity, field)} $dir');
      }
      if (terms.isNotEmpty) query += ' ORDER BY ${terms.join(', ')}';
    }

    // ‏`rowLimit + 1` عن قصد: `LIMIT n` وحده لا يفرّق بين «توجد n صفوفٍ
    // بالضبط» و«قُصَّت». فالصفُّ الزائدُ **دليلٌ لا بيانات** — يُقاس ثم يُطرح
    // في [executeReport].
    query += ' LIMIT ${rowLimit + 1}';

    return (sql: query, vars: vars);
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

  /// الفلتر مخزَّن كـ«شرط WHERE جاهز» ‑ وكان بيترجع كما هو بلا أي تحقّق.
  ///
  /// ده مش سطح حقن نظري: الاستعلام بقى
  /// `WHERE (حصر الفروع) AND (فلتر المستخدم)`، ففلتر زي `1=1) OR (1=1` بينتج
  /// `WHERE (branch_id IN (1)) AND (1=1) OR (1=1)` — والـOR بيلغي الشرطين
  /// اللي قبله ⇒ **حصر الفروع نفسه بيتكسر**. مقيس: التقرير رجّع فواتير
  /// الفرعين لمستخدم محصور بفرع واحد.
  ///
  /// التحصين بيرفض الأشكال اللي بتسمح بالهروب بدل ما يعيد تصميم الصيغة:
  /// أقواس غير متوازنة (الهروب من القوس الحاوي)، تعليق (قصّ باقي الشرط)،
  /// فاصلة منقوطة (جملة تانية)، واقتباس غير مغلق. الفلاتر السليمة بتفضل
  /// شغّالة زي ما هي.
  ///
  /// `null` = مرفوض ⇒ المُنادي بيرفض التقرير كله. الرفض بيسري على المستخدم
  /// بالوصول الكامل كمان — الحقن مش خطره على الحصر وحده.
  ///
  /// ⚠️ ده **المسار القديم وحده**. الواجهة بقت تنتج [_buildStructuredFilter]،
  /// والخامُّ باقٍ للنصوص المخزَّنة سلفاً: حذفُه كسرٌ لتقاريرَ قائمةٍ في منتجٍ
  /// مطروح مقابل فائدةٍ صفر، لأن التحصين بيمنع الهروب أصلاً.
  String? _buildWhereClause(String filtersJson) {
    final f = filtersJson.trim();
    if (f.isEmpty) return null;
    if (f.contains(';') ||
        f.contains('--') ||
        f.contains('/*') ||
        f.contains('*/')) {
      return null;
    }
    var depth = 0;
    var inQuote = false;
    for (final c in f.split('')) {
      if (c == "'") {
        inQuote = !inQuote;
        continue;
      }
      if (inQuote) continue;
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (depth < 0) return null; // قوس إغلاق زيادة ⇒ هروب
    }
    if (depth != 0 || inQuote) return null;
    return f;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STRUCTURED FILTER — الصيغةُ التي توثّقها السكيما
  // ─────────────────────────────────────────────────────────────────────────

  /// يبني شرطَ `WHERE` من الصيغة المهيكلة التي تعلنها السكيما:
  ///
  ///     [{"field":"price","op":">","value":100}, …]
  ///
  /// **الأمانُ من البناء لا من الفحص**: اسمُ العمود لا يأتي من المستخدم بل
  /// يُختار من [getAvailableFields] — قائمةٌ مغلقة — ثم يُترجَم بـ
  /// [_fieldSqlExpression]. والقيمةُ **تُربَط معاملاً** فلا تصل السلسلةَ
  /// النصّية للاستعلام أبداً. فالحقنُ مستحيلٌ بالبناء، لا مرفوضٌ بفحصٍ
  /// يُنسى تحديثُه كلما أُضيف شكلُ هروبٍ جديد.
  ///
  /// `null` = مرفوض ⇒ التقريرُ كلُّه مرفوض. والرفضُ **صريحٌ لا صامت**: شرطٌ
  /// لا يُفهَم لا يُسقَط بل يُبطل التقرير، وإلا رأى المستخدمُ صفوفاً أكثرَ مما
  /// طلب وظنّها مفلترة.
  ///
  /// وقائمةٌ فارغة ⇒ `sql` فارغ: لا شرطَ ولا `WHERE ()` مكسور.
  ({String sql, List<Variable> vars})? _buildStructuredFilter(
      String entity, String json) {
    final List<dynamic> decoded;
    try {
      final v = jsonDecode(json);
      if (v is! List) return null;
      decoded = v;
    } catch (_) {
      return null; // JSON فاسد ⇒ ارفض، ولا تبثّه SQL
    }

    final parts = <String>[];
    final vars = <Variable>[];
    for (final c in decoded) {
      if (c is! Map) return null;
      final field = c['field'];
      final op = c['op'];
      if (field is! String || op is! String) return null;

      final type = _fieldType(entity, field);
      if (type == null) return null; // خارج القائمة المغلقة
      if (!(_kFilterOpsByFieldType[type] ?? const <String>{}).contains(op)) {
        return null; // عاملٌ غيرُ مدعوم لهذا النوع
      }

      final cond = _filterCondition(
          _fieldSqlExpression(entity, field), type, op, c['value']);
      if (cond == null) return null;
      parts.add(cond.sql);
      vars.addAll(cond.vars);
    }
    // الشروطُ تُجمَع بـAND وحدَه — عن قصد. `OR` بين شرطَي المستخدم يحتاج
    // تعشيشاً في الصيغة والواجهة معاً، وبلا ذلك يكون بابَ توسيعٍ للنطاق.
    return (sql: parts.join(' AND '), vars: vars);
  }

  /// شرطٌ واحد: التعبيرُ جاهزٌ ومحصور، والقيمةُ تُتحقَّق **بحسب نوع الحقل**
  /// ثم تُربَط. `null` = القيمةُ لا تليق بالنوع ⇒ ارفض.
  ({String sql, List<Variable> vars})? _filterCondition(
      String expr, String type, String op, Object? value) {
    // `!=` بعاملٍ آمنٍ تجاه NULL لا بـ`<>`: مقارنةُ NULL في SQL تُنتج NULL
    // فيسقط الصفُّ من النتيجة. فصنفٌ **بلا** باركود «ليس BC-1» فعلاً،
    // وإسقاطُه صمتاً هو بالضبط نوعُ الخطأ الذي لا يُرى.
    //
    // ⚠️ والعاملُ ليس لغةً مشتركة: `x IS NOT y` صحيحٌ في SQLite، أما
    // PostgreSQL فلا تقبل بعد `IS NOT` إلا `NULL`/`TRUE`/`FALSE`/`UNKNOWN`
    // ونظيرُه هناك `IS DISTINCT FROM`. وبثُّ `IS NOT ?` على PostgreSQL
    // **خطأٌ نحويّ عند التشغيل** (`42601`) لا اختلافُ نتيجة — مقيسٌ في
    // `report_builder_structured_filter_pg_test`.
    final notEq = isPostgres ? 'IS DISTINCT FROM' : 'IS NOT';
    String eq() => op == '!=' ? '$expr $notEq ?' : '$expr = ?';

    switch (type) {
      case 'number':
        final n = value is num
            ? value
            : (value is String ? num.tryParse(value) : null);
        // قيمةٌ غيرُ رقميةٍ لحقلٍ رقميّ تُرفَض ولا تُمرَّر: مقارنةُ REAL بنصٍّ
        // في SQLite لا تطابق شيئاً، فالتقريرُ كان سيرجع **فارغاً بلا سبب ظاهر**.
        if (n == null) return null;
        if (op == '=' || op == '!=') return (sql: eq(), vars: [Variable(n)]);
        return (sql: '$expr $op ?', vars: [Variable(n)]);

      case 'boolean':
        final b = _asBool(value);
        if (b == null) return null;
        return (sql: eq(), vars: [Variable(b)]);

      case 'date':
        // دلالةُ اليوم لا اللحظة: المستخدمُ يختار يوماً من التقويم، والعمودُ
        // يحمل وقتاً. فـ`= 2026-08-10` على فاتورةِ ١٤:٣٠ كان سيرجع صفراً.
        final day = _asDay(value);
        if (day == null) return null;
        final next = DateTime(day.year, day.month, day.day + 1);
        switch (op) {
          case '=':
            return (
              sql: '($expr >= ? AND $expr < ?)',
              vars: [Variable(day), Variable(next)]
            );
          case '!=':
            return (
              sql: '($expr IS NULL OR $expr < ? OR $expr >= ?)',
              vars: [Variable(day), Variable(next)]
            );
          case '>': // بعد ذلك اليوم ⇒ من أوّل اليوم التالي
            return (sql: '$expr >= ?', vars: [Variable(next)]);
          case '>=':
            return (sql: '$expr >= ?', vars: [Variable(day)]);
          case '<':
            return (sql: '$expr < ?', vars: [Variable(day)]);
          case '<=': // حتى نهاية ذلك اليوم ⇒ قبل أوّل اليوم التالي
            return (sql: '$expr < ?', vars: [Variable(next)]);
        }
        return null;

      default: // text
        if (value == null) return null;
        final s = value.toString();
        if (op == 'contains') {
          // ‏`%` و`_` محرفا بدلٍ في نمط LIKE **مهما كان مصدرُ النمط**، فالربطُ
          // معاملاً وحدَه لا يحوّلهما نصّاً. فمن يبحث عن «خصم %50» بلا هروبٍ
          // يحصل على كلِّ ما فيه «50».
          //
          // و`ILIKE` على PostgreSQL: ‏`LIKE` في SQLite لا يفرّق بين حالتَي
          // الحرف اللاتينيّ، وفي PostgreSQL يفرّق. فبلا التسوية يعطي **نفسُ
          // التقرير نتيجتَين مختلفتين** بحسب المحرِّك تحته — والاختلافُ صامت.
          final like = isPostgres ? 'ILIKE' : 'LIKE';
          return (
            sql: "$expr $like ? ESCAPE '\\'",
            vars: [Variable('%${_escapeLikePattern(s)}%')]
          );
        }
        return (sql: eq(), vars: [Variable(s)]);
    }
  }

  bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value == 'true' || value == '1') return true;
      if (value == 'false' || value == '0') return false;
    }
    return null;
  }

  /// يُرجِع **بدايةَ اليوم** المحلّي — الجزءُ الزمنيّ يُطرح عمداً.
  DateTime? _asDay(Object? value) {
    DateTime? dt;
    if (value is DateTime) {
      dt = value;
    } else if (value is String) {
      dt = DateTime.tryParse(value);
    } else if (value is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  String _escapeLikePattern(String v) => v
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

/// العواملُ المسموحة **لكلِّ نوعِ حقل** — قائمةٌ مغلقة.
///
/// مربوطةٌ بالنوع لا بالحقل: «يحتوي» على حقلٍ رقميّ يُقارن نصّاً فيعطي
/// نتائجَ لا يتوقّعها أحد (‏`100` تحتوي `0`)، ولذلك يُرفَض بدل أن يُقبَل
/// ويُفسَّر. ونفسُ القائمة تبني منسدلةَ العامل في الواجهة، فلا يظهر للمستخدم
/// عاملٌ سيُرفض عند التنفيذ.
const Map<String, Set<String>> _kFilterOpsByFieldType = {
  'text': {'=', '!=', 'contains'},
  'number': {'=', '!=', '>', '>=', '<', '<='},
  'date': {'=', '!=', '>', '>=', '<', '<='},
  'boolean': {'=', '!='},
};

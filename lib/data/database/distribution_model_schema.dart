part of 'database.dart';

/// v185 — نموذجُ التوزيع (المرحلة و، بندا المالك ١٢ و١٨).
///
/// Raw SQL outside Drift's table model (no codegen run), following the
/// `voucher_books_schema.dart` pattern:
///
/// • `distribution_areas` — a distribution area (name, code, boundary text,
///   branch). Separate from the branch-grouping `regions` table.
/// • `sales_routes.area_id` + `visit_days` (raw columns) — the route's area
///   and its visit weekdays (CSV of ISO weekdays). `sales_rep_id` stays the
///   ONE responsible rep; the free-text `area` is legacy display only.
/// • `route_customers` — which route a customer is on, in what manual
///   order, and since when. **One open row per customer**
///   (`effective_to IS NULL`): assigning to another route closes the old
///   row, so the history stays readable.
/// • `route_rep_history` — every change of a route's rep.
/// • `rep_resources` — a rep's van warehouse and custody safe.
/// • `rep_employee_id` + `route_id` (raw columns) on `sales_invoices`
///   (sales AND returns), `safe_transactions` and `sales_rep_collections` —
///   stamped at creation time from the customer's current route. Reports
///   read the stamp, so a reassignment never rewrites history.
///
/// ⚠️ The customer's rep is **derived** from its current route — never
///    stored on the party.
///
/// Travels by the generic `SELECT *` delta pull (all four tables are in
/// `DeltaPullService.pullTables`; the stamp columns ride their tables).
extension DistributionModelSchema on AppDatabase {
  Future<void> ensureDistributionModelSchema() async {
    final creates = _isPostgres
        ? _distributionModelPostgresCreate
        : _distributionModelSqliteCreate;
    for (final statement in creates) {
      await customStatement(statement);
    }
    await _dmAddColumns('sales_routes', const [
      'area_id INTEGER',
      'visit_days TEXT',
    ]);
    for (final table in kRepStampedTables) {
      await _dmAddColumns(table, const [
        'rep_employee_id INTEGER',
        'route_id INTEGER',
      ]);
    }
    for (final statement in _distributionModelIndexes) {
      await customStatement(statement);
    }
  }

  Future<void> _dmAddColumns(String table, List<String> columns) async {
    for (final column in columns) {
      final name = column.split(' ').first;
      if (_isPostgres) {
        await customStatement(
            'ALTER TABLE $table ADD COLUMN IF NOT EXISTS $column');
        continue;
      }
      final existing = await customSelect('PRAGMA table_info($table)').get();
      if (existing.any((c) => c.data['name'] == name)) continue;
      try {
        await customStatement('ALTER TABLE $table ADD COLUMN $column');
      } catch (error) {
        if (!isIdempotentMigrationError(error.toString())) rethrow;
      }
    }
  }

  int _dmNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Inserts [values] into [table] with fresh sync columns; returns the id.
  Future<int> _dmInsert(String table, Map<String, Object?> values) async {
    // A caller-supplied `global_id` (a cloud-created row) is kept as is.
    final gid = values['global_id'] as String? ?? UuidV7.generate();
    final now = _dmNow();
    // NULLs are left to the column default: an untyped NULL parameter is
    // rejected by PostgreSQL for an INTEGER column.
    final row = {
      for (final e in values.entries)
        if (e.value != null) e.key: e.value,
      'global_id': gid,
      'last_modified_at': now,
    };
    final cols = row.keys.toList();
    await customInsert(
      'INSERT INTO $table (${cols.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      variables: [for (final c in cols) _dmVar(row[c])],
    );
    final inserted = await customSelect(
      'SELECT id FROM $table WHERE global_id = ?',
      variables: [Variable<String>(gid)],
    ).getSingle();
    return (inserted.data['id'] as num).toInt();
  }

  Variable<Object> _dmVar(Object? v) => switch (v) {
        int() => Variable<int>(v),
        double() => Variable<double>(v),
        bool() => Variable<bool>(v),
        String() => Variable<String>(v),
        _ => const Variable<String>(null),
      };

  // ═══════════════════════════════════════════════════════════════════════
  // Areas
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<DistributionArea>> listDistributionAreas(
      {bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT * FROM distribution_areas WHERE deleted_at IS NULL '
      '${activeOnly ? 'AND is_active = 1 ' : ''}ORDER BY name',
    ).get();
    return [for (final r in rows) _areaFromRow(r.data)];
  }

  /// Creates ([id] null) or updates an area. Names are unique among live
  /// areas.
  Future<int> saveDistributionArea({
    int? id,
    required String name,
    String? code,
    String? boundary,
    int? branchId,
    bool isActive = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw DistributionException('اسم المنطقة مطلوب.');
    final dup = await customSelect(
      'SELECT id FROM distribution_areas WHERE deleted_at IS NULL '
      'AND name = ? AND id <> ? LIMIT 1',
      variables: [Variable<String>(trimmed), Variable<int>(id ?? -1)],
    ).getSingleOrNull();
    if (dup != null) {
      throw DistributionException('توجد منطقةٌ بهذا الاسم.');
    }
    final values = <String, Object?>{
      'name': trimmed,
      'code': _dmBlank(code),
      'boundary': _dmBlank(boundary),
      'branch_id': branchId,
      'is_active': isActive ? 1 : 0,
    };
    if (id == null) return _dmInsert('distribution_areas', values);
    await customUpdate(
      'UPDATE distribution_areas SET name = ?, code = ?, boundary = ?, '
      'branch_id = ?, is_active = ?, last_modified_at = ? WHERE id = ?',
      variables: [
        Variable<String>(trimmed),
        Variable<String>(_dmBlank(code)),
        Variable<String>(_dmBlank(boundary)),
        Variable<int>(branchId),
        Variable<int>(isActive ? 1 : 0),
        Variable<int>(_dmNow()),
        Variable<int>(id),
      ],
      updates: {salesRoutes},
    );
    return id;
  }

  /// Soft-deletes an area. Refused while a live route still uses it.
  Future<void> deleteDistributionArea(int id) async {
    final used = await customSelect(
      'SELECT id FROM sales_routes WHERE area_id = ? AND is_active = ? '
      'AND deleted_at IS NULL LIMIT 1',
      variables: [Variable<int>(id), const Variable<bool>(true)],
    ).getSingleOrNull();
    if (used != null) {
      throw DistributionException('المنطقة مستخدمة في مسارٍ نشط.');
    }
    final now = _dmNow();
    await customUpdate(
      'UPDATE distribution_areas SET deleted_at = ?, last_modified_at = ? '
      'WHERE id = ?',
      variables: [Variable<int>(now), Variable<int>(now), Variable<int>(id)],
      updates: {salesRoutes},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Routes
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<DistributionRoute>> listDistributionRoutes(
      {bool activeOnly = true}) async {
    final rows = await customSelect(
      'SELECT r.id, r.name, r.description, r.area, r.is_active, '
      'r.sales_rep_id, r.area_id, r.visit_days, a.name AS area_name, '
      'e.name AS rep_name, (SELECT COUNT(*) FROM route_customers rc '
      'WHERE rc.route_id = r.id AND rc.effective_to IS NULL '
      'AND rc.deleted_at IS NULL) AS customer_count '
      'FROM sales_routes r '
      'LEFT JOIN distribution_areas a ON a.id = r.area_id '
      'LEFT JOIN employees e ON e.id = r.sales_rep_id '
      'WHERE r.deleted_at IS NULL '
      '${activeOnly ? 'AND r.is_active = ? ' : ''}ORDER BY r.name',
      variables: [if (activeOnly) const Variable<bool>(true)],
    ).get();
    return [
      for (final r in rows)
        DistributionRoute(
          id: (r.data['id'] as num).toInt(),
          name: r.data['name'] as String? ?? '',
          description: r.data['description'] as String?,
          legacyArea: r.data['area'] as String?,
          isActive: _dmBool(r.data['is_active']),
          repEmployeeId: _dmInt(r.data['sales_rep_id']),
          repName: r.data['rep_name'] as String?,
          areaId: _dmInt(r.data['area_id']),
          areaName: r.data['area_name'] as String?,
          visitDays: parseVisitDays(r.data['visit_days'] as String?),
          customerCount: _dmInt(r.data['customer_count']) ?? 0,
        ),
    ];
  }

  /// Creates ([id] null) or updates a route. A rep change goes through
  /// [setRouteRep] so it lands in `route_rep_history`.
  Future<int> saveDistributionRoute({
    int? id,
    required String name,
    String? description,
    int? areaId,
    int? repEmployeeId,
    List<int> visitDays = const [],
    bool isActive = true,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw DistributionException('اسم المسار مطلوب.');
    }
    return transaction(() async {
      var routeId = id;
      if (routeId == null) {
        routeId = await into(salesRoutes).insert(SalesRoutesCompanion.insert(
          name: trimmed,
          description: Value(_dmBlank(description)),
          isActive: Value(isActive),
          globalId: Value(UuidV7.generate()),
          lastModifiedAt: Value(DateTime.now()),
        ));
      } else {
        await (update(salesRoutes)..where((r) => r.id.equals(routeId!)))
            .write(SalesRoutesCompanion(
          name: Value(trimmed),
          description: Value(_dmBlank(description)),
          isActive: Value(isActive),
          lastModifiedAt: Value(DateTime.now()),
        ));
      }
      await customUpdate(
        'UPDATE sales_routes SET area_id = ?, visit_days = ? WHERE id = ?',
        variables: [
          Variable<int>(areaId),
          Variable<String>(encodeVisitDays(visitDays)),
          Variable<int>(routeId),
        ],
        updates: {salesRoutes},
      );
      await setRouteRep(routeId, repEmployeeId);
      return routeId;
    });
  }

  /// Changes the route's ONE responsible rep and records the change in
  /// `route_rep_history` (closing the previous open row). No-op when the
  /// rep is unchanged and its history row exists.
  Future<void> setRouteRep(int routeId, int? repEmployeeId, {DateTime? at}) {
    return transaction(() async {
      final route = await (select(salesRoutes)
            ..where((r) => r.id.equals(routeId)))
          .getSingleOrNull();
      if (route == null) throw DistributionException('المسار غير موجود.');
      final open = await customSelect(
        'SELECT id, rep_employee_id FROM route_rep_history '
        'WHERE route_id = ? AND effective_to IS NULL AND deleted_at IS NULL',
        variables: [Variable<int>(routeId)],
      ).get();
      final unchanged = route.salesRepId == repEmployeeId &&
          (repEmployeeId == null ||
              open.any((r) =>
                  _dmInt(r.data['rep_employee_id']) == repEmployeeId));
      if (unchanged) return;
      final now = at == null ? _dmNow() : at.millisecondsSinceEpoch ~/ 1000;
      for (final r in open) {
        await customUpdate(
          'UPDATE route_rep_history SET effective_to = ?, '
          'last_modified_at = ? WHERE id = ?',
          variables: [
            Variable<int>(now),
            Variable<int>(_dmNow()),
            Variable<int>((r.data['id'] as num).toInt()),
          ],
          updates: {salesRoutes},
        );
      }
      if (repEmployeeId != null) {
        await _dmInsert('route_rep_history', {
          'route_id': routeId,
          'rep_employee_id': repEmployeeId,
          'effective_from': now,
        });
      }
      await (update(salesRoutes)..where((r) => r.id.equals(routeId))).write(
          SalesRoutesCompanion(
              salesRepId: Value(repEmployeeId),
              lastModifiedAt: Value(DateTime.now())));
    });
  }

  Future<List<RouteRepHistoryEntry>> routeRepHistory(int routeId) async {
    final rows = await customSelect(
      'SELECT * FROM route_rep_history WHERE route_id = ? '
      'AND deleted_at IS NULL ORDER BY effective_from, id',
      variables: [Variable<int>(routeId)],
    ).get();
    return [
      for (final r in rows)
        RouteRepHistoryEntry(
          routeId: routeId,
          repEmployeeId: (r.data['rep_employee_id'] as num).toInt(),
          effectiveFrom: _dmDate(r.data['effective_from'])!,
          effectiveTo: _dmDate(r.data['effective_to']),
        ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Route customers — one open route per customer
  // ═══════════════════════════════════════════════════════════════════════

  /// Puts [customerId] on [routeId] (appended at the end of the route's
  /// order unless [sequence] is given). The customer's previous open row —
  /// on any route — is closed with `effective_to = now`, so a customer is on
  /// EXACTLY ONE route at a time and the history stays.
  Future<int> assignCustomerToRoute({
    required int customerId,
    required int routeId,
    int? sequence,
    DateTime? at,
    String? globalId,
  }) {
    return transaction(() async {
      // J3 — العميلُ النقديُّ متاحٌ على كلّ المسارات والمناطق (استثناءٌ صريحٌ
      // من قاعدة «مسارٌ واحدٌ للعميل»): لا يدخل `route_customers` أبداً.
      if (await isCashCustomer(customerId)) {
        throw DistributionException(
            'العميل النقدي متاح على كل المسارات — لا يُسنَد إلى مسار.');
      }
      final route = await (select(salesRoutes)
            ..where((r) => r.id.equals(routeId)))
          .getSingleOrNull();
      if (route == null || !route.isActive) {
        throw DistributionException('المسار غير موجود.');
      }
      final open = await _openRouteRows(customerId);
      final same = open.where((r) => _dmInt(r['route_id']) == routeId);
      if (same.isNotEmpty && open.length == 1) {
        return (same.first['id'] as num).toInt();
      }
      final now = at == null ? _dmNow() : at.millisecondsSinceEpoch ~/ 1000;
      await _closeRouteRows(open, now);
      final seq = sequence ?? (await _maxRouteSequence(routeId)) + 1;
      return _dmInsert('route_customers', {
        'route_id': routeId,
        'customer_id': customerId,
        'sequence': seq,
        'effective_from': now,
        'global_id': ?globalId,
      });
    });
  }

  /// Takes [customerId] off its route (closes the open row).
  Future<void> removeCustomerFromRoute(int customerId, {DateTime? at}) {
    return transaction(() async {
      final now = at == null ? _dmNow() : at.millisecondsSinceEpoch ~/ 1000;
      await _closeRouteRows(await _openRouteRows(customerId), now);
    });
  }

  /// Rewrites the manual visit order of [routeId] to [customerIdsInOrder].
  Future<void> reorderRouteCustomers(
      int routeId, List<int> customerIdsInOrder) {
    return transaction(() async {
      for (var i = 0; i < customerIdsInOrder.length; i++) {
        await customUpdate(
          'UPDATE route_customers SET sequence = ?, last_modified_at = ? '
          'WHERE route_id = ? AND customer_id = ? AND effective_to IS NULL '
          'AND deleted_at IS NULL',
          variables: [
            Variable<int>(i + 1),
            Variable<int>(_dmNow()),
            Variable<int>(routeId),
            Variable<int>(customerIdsInOrder[i]),
          ],
          updates: {salesRoutes},
        );
      }
    });
  }

  /// The route's current customers in visit order.
  Future<List<RouteCustomer>> listRouteCustomers(int routeId) async {
    final rows = await customSelect(
      'SELECT rc.*, p.name AS customer_name, p.phone AS phone, '
      'p.balance AS balance FROM route_customers rc '
      'JOIN parties p ON p.id = rc.customer_id '
      'WHERE rc.route_id = ? AND rc.effective_to IS NULL '
      'AND rc.deleted_at IS NULL ORDER BY rc.sequence, rc.id',
      variables: [Variable<int>(routeId)],
    ).get();
    return [for (final r in rows) _routeCustomerFromRow(r.data)];
  }

  /// Every route row [customerId] ever had, oldest first (history).
  Future<List<RouteCustomer>> customerRouteHistory(int customerId) async {
    final rows = await customSelect(
      'SELECT rc.*, p.name AS customer_name, p.phone AS phone, '
      'p.balance AS balance FROM route_customers rc '
      'JOIN parties p ON p.id = rc.customer_id WHERE rc.customer_id = ? '
      'AND rc.deleted_at IS NULL ORDER BY rc.effective_from, rc.id',
      variables: [Variable<int>(customerId)],
    ).get();
    return [for (final r in rows) _routeCustomerFromRow(r.data)];
  }

  /// Route / area / rep of [customerId] derived from its current route —
  /// `null` when the customer is on no route.
  Future<CustomerRouteInfo?> currentRouteOfCustomer(int customerId) async {
    final all = await customerRouteInfoMap(customerIds: {customerId});
    return all[customerId];
  }

  /// [CustomerRouteInfo] for every customer on a route (or only
  /// [customerIds]). Feeds the customers screen columns.
  Future<Map<int, CustomerRouteInfo>> customerRouteInfoMap(
      {Set<int>? customerIds}) async {
    final rows = await customSelect(
      'SELECT rc.customer_id, rc.route_id, r.name AS route_name, '
      'r.area_id, a.name AS area_name, r.sales_rep_id, e.name AS rep_name '
      'FROM route_customers rc JOIN sales_routes r ON r.id = rc.route_id '
      'LEFT JOIN distribution_areas a ON a.id = r.area_id '
      'LEFT JOIN employees e ON e.id = r.sales_rep_id '
      'WHERE rc.effective_to IS NULL AND rc.deleted_at IS NULL '
      'ORDER BY rc.effective_from, rc.id',
    ).get();
    final out = <int, CustomerRouteInfo>{};
    for (final r in rows) {
      final customerId = (r.data['customer_id'] as num).toInt();
      if (customerIds != null && !customerIds.contains(customerId)) continue;
      // Latest open row wins should a sync race ever leave two open.
      out[customerId] = CustomerRouteInfo(
        customerId: customerId,
        routeId: (r.data['route_id'] as num).toInt(),
        routeName: r.data['route_name'] as String? ?? '',
        areaId: _dmInt(r.data['area_id']),
        areaName: r.data['area_name'] as String?,
        repEmployeeId: _dmInt(r.data['sales_rep_id']),
        repName: r.data['rep_name'] as String?,
      );
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _openRouteRows(int customerId) async {
    final rows = await customSelect(
      'SELECT id, route_id FROM route_customers WHERE customer_id = ? '
      'AND effective_to IS NULL AND deleted_at IS NULL',
      variables: [Variable<int>(customerId)],
    ).get();
    return [for (final r in rows) r.data];
  }

  Future<void> _closeRouteRows(List<Map<String, dynamic>> rows, int at) async {
    for (final r in rows) {
      await customUpdate(
        'UPDATE route_customers SET effective_to = ?, last_modified_at = ? '
        'WHERE id = ?',
        variables: [
          Variable<int>(at),
          Variable<int>(_dmNow()),
          Variable<int>((r['id'] as num).toInt()),
        ],
        updates: {salesRoutes},
      );
    }
  }

  Future<int> _maxRouteSequence(int routeId) async {
    final row = await customSelect(
      'SELECT MAX(sequence) AS m FROM route_customers WHERE route_id = ? '
      'AND effective_to IS NULL AND deleted_at IS NULL',
      variables: [Variable<int>(routeId)],
    ).getSingle();
    return _dmInt(row.data['m']) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Stamping — rep + route at document creation
  // ═══════════════════════════════════════════════════════════════════════

  /// The rep + route [customerId]'s documents are stamped with now. `null`
  /// customer (POS walk-in) or no route ⇒ an empty stamp.
  Future<RepStamp> resolveRepStamp(int? customerId) async {
    if (customerId == null) return const RepStamp();
    final info = await currentRouteOfCustomer(customerId);
    if (info == null) return const RepStamp();
    return RepStamp(repEmployeeId: info.repEmployeeId, routeId: info.routeId);
  }

  /// Stamps row [id] of [table] (one of [kRepStampedTables]) with the rep +
  /// route resolved from [customerId] — or with [explicit] when the caller
  /// already carries a stamp (a sale pushed by a client keeps the client's
  /// stamp). Never overwrites an existing stamp, so a re-post or an edit
  /// cannot rewrite history.
  Future<void> stampDocumentRep(String table, int id, int? customerId,
      {RepStamp? explicit}) async {
    if (!kRepStampedTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a rep-stamped table');
    }
    final stamp = (explicit == null || explicit.isEmpty)
        ? await resolveRepStamp(customerId)
        : explicit;
    if (stamp.isEmpty) return;
    await customUpdate(
      'UPDATE $table SET rep_employee_id = COALESCE(rep_employee_id, ?), '
      'route_id = COALESCE(route_id, ?) WHERE id = ?',
      variables: [
        Variable<int>(stamp.repEmployeeId),
        Variable<int>(stamp.routeId),
        Variable<int>(id),
      ],
      updates: {
        if (table == 'sales_invoices') salesInvoices,
        if (table == 'safe_transactions') safeTransactions,
        if (table == 'sales_rep_collections') salesRepCollections,
      },
    );
  }

  /// Stamps every `safe_transactions` row of [voucherNumber] — a standalone
  /// sales return is written as one or more `SRET-…` rows (cash / bank /
  /// balance memo) with no `sales_invoices` row of its own.
  Future<void> stampSafeTransactionsByVoucher(
      String voucherNumber, int? customerId) async {
    final stamp = await resolveRepStamp(customerId);
    if (stamp.isEmpty) return;
    await customUpdate(
      'UPDATE safe_transactions SET '
      'rep_employee_id = COALESCE(rep_employee_id, ?), '
      'route_id = COALESCE(route_id, ?) WHERE voucher_number = ?',
      variables: [
        Variable<int>(stamp.repEmployeeId),
        Variable<int>(stamp.routeId),
        Variable<String>(voucherNumber),
      ],
      updates: {safeTransactions},
    );
  }

  /// The stamp of row [id] as sync-payload keys (unset keys omitted).
  Future<Map<String, int>> repStampJson(String table, int id) async {
    final stamp = await getDocumentRepStamp(table, id);
    return {
      'repEmployeeId': ?stamp.repEmployeeId,
      'routeId': ?stamp.routeId,
    };
  }

  /// Writes a pulled payload's stamp onto local row [id] (never overwrites
  /// an existing stamp; a payload without the keys is a no-op).
  Future<void> applyRepStampJson(
      String table, int id, Map<String, dynamic> json) async {
    final stamp = RepStamp(
      repEmployeeId: _dmInt(json['repEmployeeId']),
      routeId: _dmInt(json['routeId']),
    );
    if (stamp.isEmpty) return;
    await stampDocumentRep(table, id, null, explicit: stamp);
  }

  /// The stamp a document row carries (`null` fields = unstamped).
  Future<RepStamp> getDocumentRepStamp(String table, int id) async {
    if (!kRepStampedTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a rep-stamped table');
    }
    final row = await customSelect(
      'SELECT rep_employee_id, route_id FROM $table WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return RepStamp(
      repEmployeeId: _dmInt(row?.data['rep_employee_id']),
      routeId: _dmInt(row?.data['route_id']),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Rep resources
  // ═══════════════════════════════════════════════════════════════════════

  Future<RepResources?> getRepResources(int employeeId) async {
    final row = await customSelect(
      'SELECT * FROM rep_resources WHERE employee_id = ? '
      'AND deleted_at IS NULL ORDER BY id DESC LIMIT 1',
      variables: [Variable<int>(employeeId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return RepResources(
      employeeId: employeeId,
      vanWarehouseId: _dmInt(row.data['van_warehouse_id']),
      custodySafeId: _dmInt(row.data['custody_safe_id']),
    );
  }

  Future<List<RepResources>> listRepResources() async {
    final rows = await customSelect(
      'SELECT * FROM rep_resources WHERE deleted_at IS NULL ORDER BY id',
    ).get();
    final byEmployee = <int, RepResources>{};
    for (final r in rows) {
      final employeeId = (r.data['employee_id'] as num).toInt();
      byEmployee[employeeId] = RepResources(
        employeeId: employeeId,
        vanWarehouseId: _dmInt(r.data['van_warehouse_id']),
        custodySafeId: _dmInt(r.data['custody_safe_id']),
      );
    }
    return byEmployee.values.toList();
  }

  /// Sets the rep's van warehouse and custody safe. A warehouse / safe can
  /// belong to ONE rep only.
  Future<void> saveRepResources({
    required int employeeId,
    int? vanWarehouseId,
    int? custodySafeId,
  }) {
    return transaction(() async {
      for (final (column, value, key) in [
        ('van_warehouse_id', vanWarehouseId, 'مخزن السيارة مخصّص لمندوبٍ آخر.'),
        ('custody_safe_id', custodySafeId, 'خزنة العهدة مخصّصة لمندوبٍ آخر.'),
      ]) {
        if (value == null) continue;
        final taken = await customSelect(
          'SELECT id FROM rep_resources WHERE $column = ? '
          'AND employee_id <> ? AND deleted_at IS NULL LIMIT 1',
          variables: [Variable<int>(value), Variable<int>(employeeId)],
        ).getSingleOrNull();
        if (taken != null) throw DistributionException(key);
      }
      final existing = await customSelect(
        'SELECT id FROM rep_resources WHERE employee_id = ? '
        'AND deleted_at IS NULL ORDER BY id DESC LIMIT 1',
        variables: [Variable<int>(employeeId)],
      ).getSingleOrNull();
      if (existing == null) {
        await _dmInsert('rep_resources', {
          'employee_id': employeeId,
          'van_warehouse_id': vanWarehouseId,
          'custody_safe_id': custodySafeId,
        });
        return;
      }
      await customUpdate(
        'UPDATE rep_resources SET van_warehouse_id = ?, custody_safe_id = ?, '
        'last_modified_at = ? WHERE id = ?',
        variables: [
          Variable<int>(vanWarehouseId),
          Variable<int>(custodySafeId),
          Variable<int>(_dmNow()),
          Variable<int>((existing.data['id'] as num).toInt()),
        ],
        updates: {salesRoutes},
      );
    });
  }
}

/// Tables whose rows carry the v185 `rep_employee_id` + `route_id` stamp.
const kRepStampedTables = <String>[
  'sales_invoices',
  'safe_transactions',
  'sales_rep_collections',
];

String? _dmBlank(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

int? _dmInt(Object? v) => v is num ? v.toInt() : null;

bool _dmBool(Object? v) => v == true || (v is num && v != 0);

DateTime? _dmDate(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

DistributionArea _areaFromRow(Map<String, dynamic> d) => DistributionArea(
      id: (d['id'] as num).toInt(),
      name: d['name'] as String? ?? '',
      code: d['code'] as String?,
      boundary: d['boundary'] as String?,
      branchId: _dmInt(d['branch_id']),
      isActive: _dmBool(d['is_active']),
    );

RouteCustomer _routeCustomerFromRow(Map<String, dynamic> d) => RouteCustomer(
      rowId: (d['id'] as num).toInt(),
      routeId: (d['route_id'] as num).toInt(),
      customerId: (d['customer_id'] as num).toInt(),
      customerName: d['customer_name'] as String? ?? '',
      sequence: _dmInt(d['sequence']) ?? 0,
      effectiveFrom: _dmDate(d['effective_from'])!,
      effectiveTo: _dmDate(d['effective_to']),
      phone: d['phone'] as String?,
      balance: (d['balance'] as num?)?.toDouble() ?? 0,
    );

const _distributionModelSqliteCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS distribution_areas (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       code TEXT,
       boundary TEXT,
       branch_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS route_customers (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       route_id INTEGER NOT NULL REFERENCES sales_routes(id),
       customer_id INTEGER NOT NULL REFERENCES parties(id),
       sequence INTEGER NOT NULL DEFAULT 0,
       effective_from INTEGER NOT NULL,
       effective_to INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS route_rep_history (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       route_id INTEGER NOT NULL REFERENCES sales_routes(id),
       rep_employee_id INTEGER NOT NULL REFERENCES employees(id),
       effective_from INTEGER NOT NULL,
       effective_to INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS rep_resources (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       van_warehouse_id INTEGER REFERENCES warehouses(id),
       custody_safe_id INTEGER REFERENCES safes(id),
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _distributionModelPostgresCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS distribution_areas (
       id SERIAL PRIMARY KEY,
       name TEXT NOT NULL,
       code TEXT,
       boundary TEXT,
       branch_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS route_customers (
       id SERIAL PRIMARY KEY,
       route_id INTEGER NOT NULL REFERENCES sales_routes(id),
       customer_id INTEGER NOT NULL REFERENCES parties(id),
       sequence INTEGER NOT NULL DEFAULT 0,
       effective_from BIGINT NOT NULL,
       effective_to BIGINT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS route_rep_history (
       id SERIAL PRIMARY KEY,
       route_id INTEGER NOT NULL REFERENCES sales_routes(id),
       rep_employee_id INTEGER NOT NULL REFERENCES employees(id),
       effective_from BIGINT NOT NULL,
       effective_to BIGINT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS rep_resources (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       van_warehouse_id INTEGER REFERENCES warehouses(id),
       custody_safe_id INTEGER REFERENCES safes(id),
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _distributionModelIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_route_customers_customer_open '
      'ON route_customers(customer_id, effective_to)',
  'CREATE INDEX IF NOT EXISTS idx_route_customers_route_seq '
      'ON route_customers(route_id, sequence)',
  'CREATE INDEX IF NOT EXISTS idx_route_rep_history_route '
      'ON route_rep_history(route_id, effective_from)',
  'CREATE INDEX IF NOT EXISTS idx_rep_resources_employee '
      'ON rep_resources(employee_id)',
  'CREATE INDEX IF NOT EXISTS idx_sales_invoices_rep_stamp '
      'ON sales_invoices(rep_employee_id, route_id)',
  'CREATE INDEX IF NOT EXISTS idx_safe_transactions_rep_stamp '
      'ON safe_transactions(rep_employee_id, route_id)',
];

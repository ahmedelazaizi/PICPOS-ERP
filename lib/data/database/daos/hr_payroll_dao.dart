part of '../database.dart';

/// J4 (الجزء ٣) — إعداداتُ الرواتب وبنودُها، ومسيّرُ الشهر: الإنشاءُ
/// والاحتسابُ (‏[computePay] على ملخّص الحضور والبدلات والبنود والعمولة
/// والمكافآت والجزاءات والأقساط) والتسوياتُ اليدويّة والمراجعة. الاعتمادُ
/// والترحيلُ والصرفُ والعكسُ في `hr_payroll_posting_dao.dart`.
extension HrPayrollDao on AppDatabase {
  // ── أدوات ────────────────────────────────────────────────────────────────

  static const _hrpRealCols = {
    'amount', 'installment_amount', 'sales_rate', 'collections_rate',
    'basic_salary', 'paid_days', 'period_days', 'gross', 'deductions', 'net',
    'employer_cost', 'paid_amount', 'quantity', 'rate', 'total_gross',
    'total_deductions', 'total_net', 'total_employer', 'total_paid',
  };

  Variable<Object> _hrpVar(String col, Object? v) {
    if (v != null) return _dmVar(v);
    if (_hrpRealCols.contains(col)) return const Variable<double>(null);
    if (col.endsWith('_id') ||
        col.endsWith('_at') ||
        col.endsWith('_by') ||
        col.endsWith('_date') ||
        col.endsWith('_number') ||
        col.endsWith('_ref')) {
      return const Variable<int>(null);
    }
    return const Variable<String>(null);
  }

  Future<void> _hrpUpdate(
      String table, int id, Map<String, Object?> values) async {
    final cols = values.keys.toList();
    await customUpdate(
      'UPDATE $table SET ${cols.map((c) => '$c = ?').join(', ')}, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        for (final c in cols) _hrpVar(c, values[c]),
        Variable<int>(_dmNow()),
        Variable<int>(id),
      ],
      updates: {employees},
    );
  }

  Future<void> _hrpSoftDelete(String table, String where, List<Object> args) =>
      customUpdate(
        'UPDATE $table SET deleted_at = ?, last_modified_at = ? '
        'WHERE deleted_at IS NULL AND $where',
        variables: [
          Variable<int>(_dmNow()),
          Variable<int>(_dmNow()),
          for (final a in args) _dmVar(a),
        ],
        updates: {employees},
      );

  /// يرفض ما لا تملكه [userId] (‏null ⇒ مسارٌ داخليٌّ بلا مستخدم).
  Future<void> _hrpRequire(int? userId, String code) async {
    if (userId == null) return;
    if (!await userHasPermission(userId, code)) {
      throw HrException('ليس لديك صلاحية لهذا الإجراء.');
    }
  }

  double _hrpD(Object? v) => (v as num?)?.toDouble() ?? 0;

  // ── الإعدادات ────────────────────────────────────────────────────────────

  Future<String?> _hrpSetting(String key) async {
    final r = await customSelect(
      'SELECT setting_value FROM hr_payroll_settings '
      'WHERE setting_key = ? AND deleted_at IS NULL',
      variables: [Variable<String>(key)],
    ).getSingleOrNull();
    return r?.data['setting_value'] as String?;
  }

  Future<void> _hrpPutSetting(String key, String value) async {
    final r = await customSelect(
      'SELECT id FROM hr_payroll_settings '
      'WHERE setting_key = ? AND deleted_at IS NULL',
      variables: [Variable<String>(key)],
    ).getSingleOrNull();
    if (r != null) {
      await _hrpUpdate('hr_payroll_settings', (r.data['id'] as num).toInt(),
          {'setting_value': value});
      return;
    }
    final gid = UuidV7.deriveSeedGlobalId(
        table: 'hr_payroll_settings', seedKey: 'setting:$key');
    final taken = await customSelect(
      'SELECT id FROM hr_payroll_settings WHERE global_id = ?',
      variables: [Variable<String>(gid)],
    ).getSingleOrNull();
    if (taken != null) {
      // A soft-deleted row with the derived id is revived.
      await customUpdate(
        'UPDATE hr_payroll_settings SET deleted_at = NULL, setting_value = ?, '
        'last_modified_at = ? WHERE id = ?',
        variables: [
          Variable<String>(value),
          Variable<int>(_dmNow()),
          Variable<int>((taken.data['id'] as num).toInt()),
        ],
      );
      return;
    }
    await _dmInsert('hr_payroll_settings',
        {'setting_key': key, 'setting_value': value, 'global_id': gid});
  }

  Future<PayrollRules> payrollRules() async =>
      PayrollRules.decode(await _hrpSetting('rules'));

  Future<void> savePayrollRules(PayrollRules rules, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    if (rules.overtimeRate < 0 ||
        rules.insuranceEmployeePct < 0 ||
        rules.insuranceEmployerPct < 0 ||
        rules.defaultHoursPerDay <= 0) {
      throw HrException('قيم إعدادات الرواتب غير صالحة.');
    }
    await _hrpPutSetting('rules', rules.encode());
  }

  /// الأكوادُ الفعليّةُ لكلّ مفتاح: ما ضبطه المستخدمُ هنا، وإلّا ربطُ الحسابات
  /// القديم (‏`salary_expense` …)، وإلّا الافتراضيّ.
  Future<PayrollAccounts> payrollAccounts() async {
    final explicit = PayrollAccounts.decode(await _hrpSetting('accounts'));
    final codes = <String, String>{};
    for (final key in PayAccountKey.values) {
      final own = explicit.codes[key];
      if (own != null) {
        codes[key] = own;
        continue;
      }
      final purpose = PayAccountKey.legacyPurposes[key];
      codes[key] = purpose == null
          ? PayAccountKey.defaultCodes[key]!
          : await getMappedAccountCode(
              purpose, PayAccountKey.defaultCodes[key]!);
    }
    return PayrollAccounts(codes);
  }

  Future<void> savePayrollAccounts(Map<String, String> codes,
      {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    for (final e in codes.entries) {
      final acc = await getAccountByCode(e.value);
      if (acc == null) {
        throw HrException('الحساب {p0} غير موجود.', {'p0': e.value});
      }
      if (acc.accountNature == 'view') {
        throw HrException('الحساب {p0} حساب رئيسي — اختر حساباً تفصيلياً.',
            {'p0': e.value});
      }
    }
    await _hrpPutSetting('accounts', PayrollAccounts(codes).encode());
  }

  /// الحساباتُ التفصيليّةُ الفعّالة (لاختيار الربط).
  Future<List<PayrollAccountOption>> payrollAccountOptions() async {
    final rows = await (select(accounts)
          ..where((a) => a.accountNature.equals('detail') & a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .get();
    return [
      for (final a in rows) PayrollAccountOption(id: a.id, code: a.code, name: a.name),
    ];
  }

  Future<Account> _hrpAccount(PayrollAccounts accs, String key) async {
    final code = accs.codeFor(key);
    final acc = await getAccountByCode(code);
    if (acc == null) {
      throw HrException('الحساب {p0} غير موجود.', {'p0': code});
    }
    if (acc.accountNature == 'view') {
      final leaf = await getLeafAccountById(acc.id);
      if (leaf == null || leaf.accountNature == 'view') {
        throw HrException(
            'الحساب {p0} حساب رئيسي — اختر حساباً تفصيلياً.', {'p0': code});
      }
      return leaf;
    }
    return acc;
  }

  /// مركزُ تكلفةٍ لكلّ قسم (‏قسم ⇒ مركز).
  Future<Map<int, int>> departmentCostCenters() async {
    final raw = await _hrpSetting('dept_cost_centers');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = (jsonDecode(raw) as Map).cast<String, Object?>();
      return {
        for (final e in m.entries)
          if (int.tryParse(e.key) != null && e.value is num)
            int.parse(e.key): (e.value as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveDepartmentCostCenters(Map<int, int> map,
      {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    await _hrpPutSetting('dept_cost_centers',
        jsonEncode({for (final e in map.entries) '${e.key}': e.value}));
  }

  /// مراكزُ التكلفة الفعّالة (معرّف، اسم).
  Future<List<(int, String)>> payrollCostCenterOptions() async => [
        for (final c in await (select(costCenters)
              ..where((c) => c.isActive.equals(true))
              ..orderBy([(c) => OrderingTerm.asc(c.code)]))
            .get())
          (c.id, '${c.code} — ${c.name}'),
      ];

  /// الخزائنُ والبنوكُ الفعّالة للصرف.
  Future<List<PayrollSafe>> payrollSafes() async => [
        for (final s in await (select(safes)
              ..where((s) => s.isActive.equals(true))
              ..orderBy([(s) => OrderingTerm.asc(s.id)]))
            .get())
          PayrollSafe(
              id: s.id, name: s.name, type: s.safeType, branchId: s.branchId),
      ];

  // ── البنود ───────────────────────────────────────────────────────────────

  SalaryComponent _hrpComponentOf(Map<String, Object?> d) => SalaryComponent(
        id: (d['id'] as num).toInt(),
        name: d['name'] as String,
        nameEn: d['name_en'] as String?,
        kind: d['kind'] as String? ?? PayItemKind.earning,
        calc: d['calc'] as String? ?? ComponentCalc.fixed,
        amount: _hrpD(d['amount']),
        formula: d['formula'] as String?,
        departmentId: _dmInt(d['department_id']),
        isActive: _dmBool(d['is_active']),
        taxable: _dmBool(d['taxable']),
        insurable: _dmBool(d['insurable']),
      );

  Future<List<SalaryComponent>> listSalaryComponents(
      {bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT * FROM hr_salary_components WHERE deleted_at IS NULL '
      '${activeOnly ? 'AND is_active = 1 ' : ''}ORDER BY sort_order, id',
    ).get();
    return [for (final r in rows) _hrpComponentOf(r.data)];
  }

  Future<int> saveSalaryComponent(SalaryComponent c, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final name = c.name.trim();
    if (name.isEmpty) throw HrException('اسم البند مطلوب.');
    if (c.calc == ComponentCalc.formula &&
        !isValidPayFormula(c.formula ?? '')) {
      throw HrException('صيغة البند غير صالحة.');
    }
    final values = <String, Object?>{
      'name': name,
      'name_en': _dmBlank(c.nameEn),
      'kind': c.kind,
      'calc': c.calc,
      'amount': FinancialUtils.round(c.amount),
      'formula': c.calc == ComponentCalc.formula ? c.formula?.trim() : null,
      'department_id': c.departmentId,
      'is_active': c.isActive ? 1 : 0,
      'taxable': c.taxable ? 1 : 0,
      'insurable': c.insurable ? 1 : 0,
    };
    if (c.id == null) return _dmInsert('hr_salary_components', values);
    await _hrpUpdate('hr_salary_components', c.id!, values);
    return c.id!;
  }

  Future<void> deleteSalaryComponent(int id, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    await _hrpSoftDelete('hr_salary_components', 'id = ?', [id]);
  }

  // ── المسيّرات (قراءة) ────────────────────────────────────────────────────

  PayrollRun _hrpRunOf(Map<String, Object?> d) => PayrollRun(
        id: (d['id'] as num).toInt(),
        year: _dmInt(d['period_year'])!,
        month: _dmInt(d['period_month'])!,
        from: _dmDate(d['period_from'])!,
        to: _dmDate(d['period_to'])!,
        status: d['status'] as String,
        branchId: _dmInt(d['branch_id']),
        departmentId: _dmInt(d['department_id']),
        journalEntryId: _dmInt(d['journal_entry_id']),
        reversalJournalEntryId: _dmInt(d['reversal_journal_entry_id']),
        gross: _hrpD(d['total_gross']),
        deductions: _hrpD(d['total_deductions']),
        net: _hrpD(d['total_net']),
        employerCost: _hrpD(d['total_employer']),
        paid: _hrpD(d['total_paid']),
        employeeCount: _dmInt(d['employee_count']) ?? 0,
        legacy: _dmBool(d['is_legacy']),
        notes: d['notes'] as String?,
        createdBy: _dmInt(d['created_by']),
        approvedBy: _dmInt(d['approved_by']),
        postedAt: _dmDate(d['posted_at']),
      );

  Future<List<PayrollRun>> listPayrollRuns({int? year}) async {
    final rows = await customSelect(
      'SELECT * FROM hr_payroll_runs WHERE deleted_at IS NULL '
      '${year == null ? '' : 'AND period_year = ? '}'
      'ORDER BY period_year DESC, period_month DESC, id DESC',
      variables: [if (year != null) Variable<int>(year)],
    ).get();
    return [for (final r in rows) _hrpRunOf(r.data)];
  }

  Future<PayrollRun> getPayrollRun(int id) async {
    final r = await customSelect(
      'SELECT * FROM hr_payroll_runs WHERE id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    if (r == null) throw HrException('المسير غير موجود.');
    return _hrpRunOf(r.data);
  }

  PayrollItem _hrpItemOf(Map<String, Object?> d) => PayrollItem(
        id: (d['id'] as num).toInt(),
        lineId: _dmInt(d['line_id']),
        kind: d['kind'] as String,
        code: d['code'] as String,
        label: d['label'] as String,
        amount: _hrpD(d['amount']),
        accountKey: d['account_key'] as String,
        quantity: (d['quantity'] as num?)?.toDouble(),
        rate: (d['rate'] as num?)?.toDouble(),
        isManual: _dmBool(d['is_manual']),
        reason: d['reason'] as String?,
        refType: d['ref_type'] as String?,
        refId: _dmInt(d['ref_id']),
      );

  /// سطورُ مسيّرٍ ببنودها (أو سطورُ موظفٍ عبر المسيّرات بـ[employeeId]).
  Future<List<PayrollLine>> listPayrollLines(
      {int? runId, int? employeeId}) async {
    final where = <String>['l.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (runId != null) {
      where.add('l.run_id = ?');
      vars.add(Variable<int>(runId));
    }
    if (employeeId != null) {
      where.add('l.employee_id = ?');
      vars.add(Variable<int>(employeeId));
    }
    final rows = await customSelect(
      'SELECT l.*, e.name AS employee_name, e.employee_code AS employee_code, '
      'd.name AS department_name FROM hr_payroll_lines l '
      'JOIN employees e ON e.id = l.employee_id '
      'LEFT JOIN hr_departments d ON d.id = l.department_id '
      'WHERE ${where.join(' AND ')} ORDER BY e.name, l.id',
      variables: vars,
    ).get();
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) (r.data['id'] as num).toInt()];
    final items = <int, List<PayrollItem>>{};
    for (final r in await customSelect(
      'SELECT * FROM hr_payroll_items WHERE deleted_at IS NULL '
      'AND line_id IN (${List.filled(ids.length, '?').join(', ')}) ORDER BY id',
      variables: [for (final id in ids) Variable<int>(id)],
    ).get()) {
      final item = _hrpItemOf(r.data);
      items.putIfAbsent(item.lineId!, () => []).add(item);
    }
    return [
      for (final r in rows)
        PayrollLine(
          id: (r.data['id'] as num).toInt(),
          runId: _dmInt(r.data['run_id'])!,
          employeeId: _dmInt(r.data['employee_id'])!,
          employeeName: r.data['employee_name'] as String? ?? '',
          employeeCode: r.data['employee_code'] as String?,
          departmentId: _dmInt(r.data['department_id']),
          departmentName: r.data['department_name'] as String?,
          branchId: _dmInt(r.data['branch_id']),
          basicSalary: _hrpD(r.data['basic_salary']),
          paidDays: _hrpD(r.data['paid_days']),
          periodDays: _hrpD(r.data['period_days']),
          gross: _hrpD(r.data['gross']),
          deductions: _hrpD(r.data['deductions']),
          net: _hrpD(r.data['net']),
          employerCost: _hrpD(r.data['employer_cost']),
          paidAmount: _hrpD(r.data['paid_amount']),
          paymentStatus:
              r.data['payment_status'] as String? ?? PayLineStatus.unpaid,
          paymentMethod: r.data['payment_method'] as String?,
          safeTransactionId: _dmInt(r.data['safe_transaction_id']),
          items: items[(r.data['id'] as num).toInt()] ?? const [],
        ),
    ];
  }

  /// قسائمُ موظفٍ عبر المسيّرات غير المعكوسة، الأحدثُ أوّلاً.
  Future<List<PayslipEntry>> employeePayslips(int employeeId) async {
    final runs = {for (final r in await listPayrollRuns()) r.id: r};
    final out = [
      for (final l in await listPayrollLines(employeeId: employeeId))
        if (runs[l.runId] != null &&
            runs[l.runId]!.status != PayrollRunStatus.reversed)
          PayslipEntry(run: runs[l.runId]!, line: l),
    ];
    out.sort((a, b) => (b.run.year * 12 + b.run.month)
        .compareTo(a.run.year * 12 + a.run.month));
    return out;
  }

  Future<void> _hrpRefreshLineTotals(int lineId, {bool? paid}) async {
    final items = [
      for (final r in await customSelect(
        'SELECT * FROM hr_payroll_items WHERE line_id = ? AND deleted_at IS NULL',
        variables: [Variable<int>(lineId)],
      ).get())
        _hrpItemOf(r.data),
    ];
    final t = PayTotals.of(items);
    await _hrpUpdate('hr_payroll_lines', lineId, {
      'gross': t.gross,
      'deductions': t.deductions,
      'net': t.net,
      'employer_cost': t.employerCost,
      if (paid == true) 'paid_amount': t.net,
    });
  }

  Future<void> _hrpRefreshRunTotals(int runId) async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n, COALESCE(SUM(gross), 0) AS g, '
      'COALESCE(SUM(deductions), 0) AS d, COALESCE(SUM(net), 0) AS t, '
      'COALESCE(SUM(employer_cost), 0) AS e, COALESCE(SUM(paid_amount), 0) AS p '
      'FROM hr_payroll_lines WHERE run_id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(runId)],
    ).getSingle();
    await _hrpUpdate('hr_payroll_runs', runId, {
      'employee_count': _dmInt(r.data['n']) ?? 0,
      'total_gross': FinancialUtils.round(_hrpD(r.data['g'])),
      'total_deductions': FinancialUtils.round(_hrpD(r.data['d'])),
      'total_net': FinancialUtils.round(_hrpD(r.data['t'])),
      'total_employer': FinancialUtils.round(_hrpD(r.data['e'])),
      'total_paid': FinancialUtils.round(_hrpD(r.data['p'])),
    });
  }

  // ── الإنشاءُ والاحتساب ───────────────────────────────────────────────────

  /// ينشئ مسيّرَ شهرٍ (مسودة) ويحتسبه. يرفض مسيّراً نشطاً لنفس الشهر
  /// والنطاق نفسه؛ والموظفُ المحسوبُ في مسيّرٍ نشطٍ آخر للشهر لا يتكرّر.
  Future<int> createPayrollRun({
    required int year,
    required int month,
    int? branchId,
    int? departmentId,
    int? userId,
    DateTime? now,
  }) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    if (month < 1 || month > 12) throw HrException('الشهر غير صالح.');
    final dup = await customSelect(
      'SELECT id FROM hr_payroll_runs WHERE deleted_at IS NULL '
      "AND status <> 'reversed' AND is_legacy = 0 "
      'AND period_year = ? AND period_month = ? '
      'AND COALESCE(branch_id, 0) = ? AND COALESCE(department_id, 0) = ?',
      variables: [
        Variable<int>(year),
        Variable<int>(month),
        Variable<int>(branchId ?? 0),
        Variable<int>(departmentId ?? 0),
      ],
    ).get();
    if (dup.isNotEmpty) {
      throw HrException('يوجد مسير لهذا الشهر والنطاق بالفعل.');
    }
    return transaction(() async {
      final id = await _dmInsert('hr_payroll_runs', {
        'period_year': year,
        'period_month': month,
        'period_from': _hrEpoch(DateTime(year, month)),
        'period_to': _hrEpoch(DateTime(year, month + 1, 0)),
        'branch_id': branchId,
        'department_id': departmentId,
        'status': PayrollRunStatus.draft,
        'created_by': userId,
      });
      await _hrpCompute(id, now: now);
      return id;
    });
  }

  /// يعيد احتسابَ مسودةٍ (أو مراجَعٍ يعود مسودة) ويُبقي التسوياتِ اليدويّة.
  Future<void> recomputePayrollRun(int runId,
      {int? userId, DateTime? now}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final run = await getPayrollRun(runId);
    if (!run.editable) {
      throw HrException('لا يمكن تعديل مسير بعد اعتماده.');
    }
    await transaction(() async {
      await _hrpCompute(runId, now: now);
      if (run.status == PayrollRunStatus.reviewed) {
        await _hrpUpdate('hr_payroll_runs', runId,
            {'status': PayrollRunStatus.draft, 'reviewed_by': null});
      }
    });
  }

  Future<void> _hrpCompute(int runId, {DateTime? now}) async {
    final run = await getPayrollRun(runId);
    final rules = await payrollRules();
    final components = await listSalaryComponents(activeOnly: true);
    final from = run.from;
    final to = run.to;

    // موظفو مسيّراتٍ نشطةٍ أخرى للشهر نفسه.
    final taken = {
      for (final r in await customSelect(
        'SELECT l.employee_id FROM hr_payroll_lines l '
        'JOIN hr_payroll_runs r ON r.id = l.run_id '
        "WHERE l.deleted_at IS NULL AND r.deleted_at IS NULL AND r.status <> 'reversed' "
        'AND r.period_year = ? AND r.period_month = ? AND r.id <> ?',
        variables: [
          Variable<int>(run.year),
          Variable<int>(run.month),
          Variable<int>(runId),
        ],
      ).get())
        _dmInt(r.data['employee_id'])!,
    };

    final existingLines = <int, int>{
      for (final r in await customSelect(
        'SELECT id, employee_id FROM hr_payroll_lines '
        'WHERE run_id = ? AND deleted_at IS NULL',
        variables: [Variable<int>(runId)],
      ).get())
        _dmInt(r.data['employee_id'])!: (r.data['id'] as num).toInt(),
    };
    final manual = <int, List<PayrollItem>>{};
    for (final r in await customSelect(
      'SELECT * FROM hr_payroll_items WHERE run_id = ? AND is_manual = 1 '
      'AND deleted_at IS NULL',
      variables: [Variable<int>(runId)],
    ).get()) {
      final item = _hrpItemOf(r.data);
      manual.putIfAbsent(_dmInt(r.data['employee_id'])!, () => []).add(item);
    }

    final adjustments = await listPayrollAdjustments(
        year: run.year, month: run.month, status: AdjustmentStatus.approved);
    final advances = await listEmployeeAdvances(status: AdvanceStatus.active);
    // العمولةُ لمن له خطّةٌ (خاصّةٌ أو افتراضيّة) ومستنداتٌ مختومةٌ في الفترة.
    final plans = await listCommissionPlans(activeOnly: true);
    final stampedReps = plans.isEmpty
        ? const <int>{}
        : {
            for (final r in await repTransactionDetail(
                from: from, to: DateTime(to.year, to.month, to.day + 1)))
              if (r.repEmployeeId != null) r.repEmployeeId!,
          };

    final kept = <int>{};
    for (final p in await listEmployeeProfiles()) {
      final id = p.id!;
      if (taken.contains(id)) continue;
      if (p.status == EmployeeStatus.suspended) continue;
      if (run.branchId != null && p.branchId != run.branchId) continue;
      if (run.departmentId != null && p.departmentId != run.departmentId) {
        continue;
      }
      if (employedDaysIn(from, to,
              hireDate: p.hireDate, terminationDate: p.terminationDate) <=
          0) {
        continue;
      }
      if (p.status == EmployeeStatus.terminated && p.terminationDate == null) {
        continue;
      }
      final summary = await attendanceSummary(id, from, to, now: now);
      final allowances = [
        for (final a in await listEmployeeAllowances(id))
          (a.name, a.valueFor(p.basicSalary)),
      ];
      final ownComponents = [
        for (final c in components)
          if (c.departmentId == null || c.departmentId == p.departmentId) c,
      ];
      final commission = stampedReps.contains(id)
          ? (await commissionStatement(id, from, to)).total
          : 0.0;
      final mine = [
        for (final a in adjustments)
          if (a.employeeId == id &&
              (a.payrollRunId == null || a.payrollRunId == runId))
            a,
      ];
      final due = [
        for (final a in advances)
          if (a.employeeId == id && a.dueFor(run.year, run.month) > 0)
            (a, a.dueFor(run.year, run.month)),
      ];
      final result = computePay(PayInput(
        basicSalary: p.basicSalary,
        salaryType: p.salaryType,
        hoursPerDay: p.hoursPerDay,
        hireDate: p.hireDate,
        terminationDate: p.terminationDate,
        from: from,
        to: to,
        rules: rules,
        summary: summary,
        allowances: allowances,
        components: ownComponents,
        commission: commission,
        bonuses: [for (final a in mine) if (a.kind == AdjustmentKind.bonus) a],
        penalties: [
          for (final a in mine) if (a.kind == AdjustmentKind.penalty) a,
        ],
        advances: due,
        manual: manual[id] ?? const [],
      ));
      if (result.items.isEmpty) continue;
      final lineValues = <String, Object?>{
        'run_id': runId,
        'employee_id': id,
        'branch_id': p.branchId,
        'department_id': p.departmentId,
        'basic_salary': FinancialUtils.round(p.basicSalary),
        'paid_days': result.paidDays,
        'period_days': result.periodDays,
        'payment_method': p.paymentMethod,
      };
      var lineId = existingLines[id];
      if (lineId == null) {
        lineId = await _dmInsert('hr_payroll_lines', lineValues);
      } else {
        await _hrpUpdate('hr_payroll_lines', lineId, lineValues);
        await _hrpSoftDelete('hr_payroll_items',
            'line_id = ? AND is_manual = 0', [lineId]);
      }
      for (final item in result.items) {
        if (item.isManual) continue;
        await _hrpInsertItem(runId, lineId, id, item);
      }
      await _hrpRefreshLineTotals(lineId);
      kept.add(id);
    }
    for (final e in existingLines.entries) {
      if (kept.contains(e.key)) continue;
      await _hrpSoftDelete('hr_payroll_items', 'line_id = ?', [e.value]);
      await _hrpSoftDelete('hr_payroll_lines', 'id = ?', [e.value]);
    }
    await _hrpRefreshRunTotals(runId);
  }

  Future<int> _hrpInsertItem(
          int runId, int lineId, int employeeId, PayrollItem item,
          {int? userId}) =>
      _dmInsert('hr_payroll_items', {
        'run_id': runId,
        'line_id': lineId,
        'employee_id': employeeId,
        'kind': item.kind,
        'code': item.code,
        'label': item.label,
        'amount': FinancialUtils.round(item.amount),
        'quantity': item.quantity,
        'rate': item.rate,
        'account_key': item.accountKey,
        'is_manual': item.isManual ? 1 : 0,
        'reason': item.reason,
        'ref_type': item.refType,
        'ref_id': item.refId,
        'created_by': userId,
      });

  /// تسويةٌ يدويّةٌ على قسيمة (استحقاقٌ أو استقطاع) بسببٍ إلزاميّ — تُسجَّل
  /// في سجلّ الموظف، وتبقى بعد إعادة الاحتساب.
  Future<int> addPayrollManualItem({
    required int runId,
    required int employeeId,
    required String kind,
    required double amount,
    required String reason,
    String? label,
    int? userId,
  }) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final run = await getPayrollRun(runId);
    if (!run.editable) throw HrException('لا يمكن تعديل مسير بعد اعتماده.');
    if (reason.trim().isEmpty) throw HrException('سبب التسوية مطلوب.');
    if (amount <= 0) throw HrException('المبلغ يجب أن يكون أكبر من صفر.');
    if (kind != PayItemKind.earning && kind != PayItemKind.deduction) {
      throw HrException('نوع التسوية غير صالح.');
    }
    final line = await customSelect(
      'SELECT id FROM hr_payroll_lines WHERE run_id = ? AND employee_id = ? '
      'AND deleted_at IS NULL',
      variables: [Variable<int>(runId), Variable<int>(employeeId)],
    ).getSingleOrNull();
    if (line == null) throw HrException('الموظف ليس في هذا المسير.');
    final lineId = (line.data['id'] as num).toInt();
    return transaction(() async {
      final id = await _hrpInsertItem(
        runId,
        lineId,
        employeeId,
        PayrollItem(
          kind: kind,
          code: PayItemCode.manual,
          label: (label ?? '').trim().isEmpty
              ? (kind == PayItemKind.earning ? 'تسوية إضافة' : 'تسوية خصم')
              : label!.trim(),
          amount: amount,
          accountKey: kind == PayItemKind.earning
              ? PayAccountKey.allowancesExpense
              : PayAccountKey.salariesExpense,
          isManual: true,
          reason: reason.trim(),
        ),
        userId: userId,
      );
      // الضريبةُ والتأميناتُ والأقساطُ تتبع الإجماليَّ الجديد.
      await _hrpCompute(runId);
      await logEmployeeEvent(employeeId, HrEventType.payroll,
          to: '${kind == PayItemKind.earning ? '+' : '−'}'
              '${FinancialUtils.round(amount)} · ${run.period}',
          notes: reason.trim(),
          actorUserId: userId);
      return id;
    });
  }

  Future<void> removePayrollManualItem(int itemId, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final r = await customSelect(
      'SELECT run_id, employee_id, amount, reason FROM hr_payroll_items '
      'WHERE id = ? AND is_manual = 1 AND deleted_at IS NULL',
      variables: [Variable<int>(itemId)],
    ).getSingleOrNull();
    if (r == null) return;
    final run = await getPayrollRun(_dmInt(r.data['run_id'])!);
    if (!run.editable) throw HrException('لا يمكن تعديل مسير بعد اعتماده.');
    await transaction(() async {
      await _hrpSoftDelete('hr_payroll_items', 'id = ?', [itemId]);
      await _hrpCompute(run.id);
      await logEmployeeEvent(_dmInt(r.data['employee_id'])!, HrEventType.payroll,
          from: '${FinancialUtils.round(_hrpD(r.data['amount']))} · ${run.period}',
          notes: r.data['reason'] as String?,
          actorUserId: userId);
    });
  }

  /// مسودة ⇒ مراجَع.
  Future<void> reviewPayrollRun(int runId, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final run = await getPayrollRun(runId);
    if (run.legacy || run.status != PayrollRunStatus.draft) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    if (run.employeeCount == 0) throw HrException('المسير فارغ.');
    await _hrpUpdate('hr_payroll_runs', runId,
        {'status': PayrollRunStatus.reviewed, 'reviewed_by': userId});
  }

  /// مراجَعٌ أو معتمدٌ (قبل الترحيل) ⇒ مسودة.
  Future<void> reopenPayrollRun(int runId, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final run = await getPayrollRun(runId);
    if (run.legacy ||
        (run.status != PayrollRunStatus.reviewed &&
            run.status != PayrollRunStatus.approved)) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    if (run.status == PayrollRunStatus.approved) {
      await _hrpRequire(userId, PermissionCodes.hrPayrollApprove);
    }
    await _hrpUpdate('hr_payroll_runs', runId, {
      'status': PayrollRunStatus.draft,
      'reviewed_by': null,
      'approved_by': null,
    });
  }

  /// يحذف مسودةً (لا أثرَ ماليَّ لها بعد).
  Future<void> deletePayrollRun(int runId, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final run = await getPayrollRun(runId);
    if (run.legacy || !run.editable) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    await transaction(() async {
      await _hrpSoftDelete('hr_payroll_items', 'run_id = ?', [runId]);
      await _hrpSoftDelete('hr_payroll_lines', 'run_id = ?', [runId]);
      await _hrpSoftDelete('hr_payroll_runs', 'id = ?', [runId]);
    });
  }
}

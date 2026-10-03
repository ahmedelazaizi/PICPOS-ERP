part of 'database.dart';

/// v193 — الرواتبُ والسلفُ والجزاءاتُ وعمولاتُ المندوبين (J4 الجزء ٣).
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// `hr_attendance_schema.dart`:
///
/// • `hr_payroll_settings` — key/value JSON (rules · accounts · department
///   cost centers). A key's global id is derived from the key, so two
///   installs writing it converge on sync.
/// • `hr_salary_components` — company / department earnings & deductions.
/// • `hr_employee_advances` · `hr_advance_repayments` — advances and loans
///   paid out through a payment voucher, repaid by payroll installments or an
///   early settlement (receipt voucher). Balance = amount − repayments.
/// • `hr_payroll_adjustments` — one-off bonuses / penalties with approval.
/// • `hr_commission_plans` — rep commission plans (default or per rep).
/// • `hr_payroll_runs` · `hr_payroll_lines` · `hr_payroll_items` — the run
///   (draft → reviewed → approved → posted → paid / reversed), one line per
///   employee and its earning / deduction / employer items.
///
/// The legacy screen's `salary_payments` and `employee_transactions` stay as
/// they are; [migrateLegacyPayroll] copies them here as read-only history.
extension HrPayrollSchema on AppDatabase {
  Future<void> ensureHrPayrollSchema() async {
    final creates =
        _isPostgres ? _hrPayrollPostgresCreate : _hrPayrollSqliteCreate;
    for (final statement in creates) {
      await customStatement(statement);
    }
    for (final statement in _hrPayrollIndexes) {
      await customStatement(statement);
    }
    for (final statement in _hrPayrollUniqueIndexes) {
      try {
        await customStatement(statement);
      } catch (e) {
        debugPrint('[HR] payroll unique index skipped: $e');
      }
    }
  }

  /// One-time grant of the v193 codes: `hr_manage` ⇒ payroll view;
  /// `hr_payroll_process` (the legacy payroll right) ⇒ view / edit / approve
  /// / post / commissions; `hr_advance_record` ⇒ advances. Admin is covered
  /// by `syncAllPermissions`.
  Future<void> backfillHrPayrollPermissionsOnce() async {
    const flag = 'hr_payroll_perm_backfill_done';
    if (await getSettingValue(flag) == 'true') return;
    const pairs = <String, List<String>>{
      PermissionCodes.hrManage: [PermissionCodes.hrPayrollView],
      PermissionCodes.hrPayrollProcess: [
        PermissionCodes.hrPayrollView,
        PermissionCodes.hrPayrollEdit,
        PermissionCodes.hrPayrollApprove,
        PermissionCodes.hrPayrollPost,
        PermissionCodes.hrCommissionsManage,
      ],
      PermissionCodes.hrAdvanceRecord: [
        PermissionCodes.hrPayrollView,
        PermissionCodes.hrAdvancesManage,
      ],
    };
    for (final pair in pairs.entries) {
      final source = await (select(permissions)
            ..where((p) => p.code.equals(pair.key)))
          .getSingleOrNull();
      if (source == null) continue;
      final targets = await (select(permissions)
            ..where((p) => p.code.isIn(pair.value)))
          .get();
      final holders = await (select(rolePermissions)
            ..where((rp) => rp.permissionId.equals(source.id)))
          .get();
      for (final roleId in {for (final h in holders) h.roleId}) {
        for (final t in targets) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(roleId: roleId, permissionId: t.id),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: flag, value: const Value('true')),
    );
  }

  /// Copies the legacy screen's payroll into the v193 tables as read-only
  /// history. Idempotent (deterministic global ids, a copied row is skipped
  /// even if later deleted here):
  ///  • `salary_payments` → one legacy run per period (status `paid`), a line
  ///    per employee and an item per payment (salary / bonus = earning,
  ///    deduction / advance = deduction);
  ///  • `employee_transactions` advances → `hr_employee_advances` (no new
  ///    voucher or JE — the legacy one stands); a settled advance gets a
  ///    legacy repayment, an active one is repaid by the next payroll;
  ///  • deductions → approved penalties of their month (consumed by the
  ///    legacy run of that month when there is one).
  Future<void> migrateLegacyPayroll() async {
    String gid(String table, Object key) =>
        UuidV7.deriveSeedGlobalId(table: table, seedKey: 'legacy:$key');
    Future<Set<String>> gids(String table) async => {
          for (final r in await customSelect(
            'SELECT global_id FROM $table WHERE global_id IS NOT NULL',
          ).get())
            r.data['global_id'] as String,
        };
    final employeeRows = {for (final e in await select(employees).get()) e.id: e};

    // ── salary_payments → legacy runs ──
    final payments = await select(salaryPayments).get();
    final runGids = await gids('hr_payroll_runs');
    final lineGids = await gids('hr_payroll_lines');
    final itemGids = await gids('hr_payroll_items');
    final runIds = <String, int>{};
    for (final r in await customSelect(
      'SELECT id, global_id FROM hr_payroll_runs WHERE is_legacy = 1',
    ).get()) {
      runIds[r.data['global_id'] as String] = (r.data['id'] as num).toInt();
    }
    final touchedLines = <int>{};
    for (final p in payments) {
      if (!employeeRows.containsKey(p.employeeId)) continue;
      final itemGid = gid('hr_payroll_items', p.id);
      if (itemGids.contains(itemGid)) continue;
      final period = _legacyPeriod(p.period, p.paymentDate);
      final (year, month) = period;
      final key = '$year-${month.toString().padLeft(2, '0')}';
      final runGid = gid('hr_payroll_runs', key);
      var runId = runIds[runGid];
      if (runId == null) {
        if (runGids.contains(runGid)) continue; // deleted here on purpose
        runId = await _dmInsert('hr_payroll_runs', {
          'period_year': year,
          'period_month': month,
          'period_from': _hrEpoch(DateTime(year, month)),
          'period_to': _hrEpoch(DateTime(year, month + 1, 0)),
          'status': PayrollRunStatus.paid,
          'is_legacy': 1,
          'notes': 'مرحَّل من شاشة الحضور والرواتب',
          'global_id': runGid,
        });
        runIds[runGid] = runId;
      }
      final lineGid = gid('hr_payroll_lines', '$key:${p.employeeId}');
      final existing = await customSelect(
        'SELECT id FROM hr_payroll_lines WHERE global_id = ?',
        variables: [Variable<String>(lineGid)],
      ).getSingleOrNull();
      int lineId;
      if (existing != null) {
        lineId = (existing.data['id'] as num).toInt();
      } else {
        if (lineGids.contains(lineGid)) continue;
        final emp = employeeRows[p.employeeId]!;
        lineId = await _dmInsert('hr_payroll_lines', {
          'run_id': runId,
          'employee_id': p.employeeId,
          'branch_id': emp.branchId,
          'basic_salary': emp.salary,
          'payment_status': PayLineStatus.paid,
          'payment_method': SalaryPaymentMethod.cash,
          'global_id': lineGid,
        });
      }
      final deduction = p.type == 'deduction' || p.type == 'advance';
      await _dmInsert('hr_payroll_items', {
        'run_id': runId,
        'line_id': lineId,
        'employee_id': p.employeeId,
        'kind': deduction ? PayItemKind.deduction : PayItemKind.earning,
        'code': switch (p.type) {
          'bonus' => PayItemCode.bonus,
          'deduction' => PayItemCode.penalty,
          'advance' => PayItemCode.advance,
          _ => PayItemCode.legacy,
        },
        'label': switch (p.type) {
          'bonus' => 'مكافأة',
          'deduction' => 'خصم',
          'advance' => 'سلفة',
          _ => 'راتب مصروف',
        },
        'amount': FinancialUtils.round(p.amount),
        'account_key': p.type == 'advance'
            ? PayAccountKey.advancesReceivable
            : PayAccountKey.salariesExpense,
        'reason': p.notes,
        'ref_type': 'salary_payment',
        'ref_id': p.id,
        'global_id': itemGid,
      });
      touchedLines.add(lineId);
    }
    for (final lineId in touchedLines) {
      await _hrpRefreshLineTotals(lineId, paid: true);
    }
    for (final runId in {...runIds.values}) {
      await _hrpRefreshRunTotals(runId);
    }

    // ── employee_transactions → advances / penalties ──
    final advanceGids = await gids('hr_employee_advances');
    final adjustmentGids = await gids('hr_payroll_adjustments');
    final repaymentGids = await gids('hr_advance_repayments');
    for (final t in await select(employeeTransactions).get()) {
      if (!employeeRows.containsKey(t.employeeId)) continue;
      final d = t.transactionDate;
      if (t.transactionType == 'advance') {
        final g = gid('hr_employee_advances', t.id);
        if (advanceGids.contains(g)) continue;
        final status = switch (t.status) {
          'settled' => AdvanceStatus.settled,
          'cancelled' => AdvanceStatus.cancelled,
          _ => AdvanceStatus.active,
        };
        final id = await _dmInsert('hr_employee_advances', {
          'employee_id': t.employeeId,
          'kind': AdvanceKind.advance,
          'amount': FinancialUtils.round(t.amount),
          'issue_date': _hrEpoch(d),
          'installments': 1,
          'installment_amount': FinancialUtils.round(t.amount),
          'start_year': d.year,
          'start_month': d.month,
          'status': status,
          'safe_transaction_id': t.treasuryTransactionId,
          'notes': t.description,
          'legacy_ref': t.id,
          'global_id': g,
        });
        final rg = gid('hr_advance_repayments', t.id);
        if (status == AdvanceStatus.settled && !repaymentGids.contains(rg)) {
          await _dmInsert('hr_advance_repayments', {
            'advance_id': id,
            'employee_id': t.employeeId,
            'amount': FinancialUtils.round(t.amount),
            'repay_date': _hrEpoch(d),
            'source': RepaymentSource.legacy,
            'global_id': rg,
          });
        }
      } else if (t.transactionType == 'deduction') {
        final g = gid('hr_payroll_adjustments', t.id);
        if (adjustmentGids.contains(g)) continue;
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        final legacyRun = runIds[gid('hr_payroll_runs', key)];
        await _dmInsert('hr_payroll_adjustments', {
          'employee_id': t.employeeId,
          'kind': AdjustmentKind.penalty,
          'amount': FinancialUtils.round(t.amount),
          'period_year': d.year,
          'period_month': d.month,
          'reason': (t.description ?? '').trim().isEmpty
              ? 'خصم مرحَّل'
              : t.description,
          'status': t.status == 'cancelled'
              ? AdjustmentStatus.rejected
              : AdjustmentStatus.approved,
          'payroll_run_id': legacyRun,
          'legacy_ref': t.id,
          'global_id': g,
        });
      }
    }
  }
}

(int, int) _legacyPeriod(String? period, DateTime fallback) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(period ?? '');
  if (m != null) {
    final month = int.parse(m.group(2)!);
    if (month >= 1 && month <= 12) return (int.parse(m.group(1)!), month);
  }
  return (fallback.year, fallback.month);
}

const _kHrSync = '''
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0''';

const _kHrSyncPg = '''
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0''';

/// One `CREATE TABLE` per table for both dialects: `@ID` · `@TS` (epoch) ·
/// `@REAL` · `@NOW` · `@SYNC` (the delta columns) are substituted per dialect.
const _hrPayrollTables = <String>[
  '''CREATE TABLE IF NOT EXISTS hr_payroll_settings (
       id @ID,
       setting_key TEXT NOT NULL,
       setting_value TEXT,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_salary_components (
       id @ID,
       name TEXT NOT NULL,
       name_en TEXT,
       kind TEXT NOT NULL DEFAULT 'earning',
       calc TEXT NOT NULL DEFAULT 'fixed',
       amount @REAL NOT NULL DEFAULT 0,
       formula TEXT,
       department_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       taxable INTEGER NOT NULL DEFAULT 1,
       insurable INTEGER NOT NULL DEFAULT 0,
       sort_order INTEGER NOT NULL DEFAULT 0,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_employee_advances (
       id @ID,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       kind TEXT NOT NULL DEFAULT 'advance',
       amount @REAL NOT NULL DEFAULT 0,
       issue_date @TS NOT NULL,
       installments INTEGER NOT NULL DEFAULT 1,
       installment_amount @REAL NOT NULL DEFAULT 0,
       start_year INTEGER NOT NULL,
       start_month INTEGER NOT NULL,
       status TEXT NOT NULL DEFAULT 'active',
       safe_transaction_id INTEGER,
       journal_entry_id INTEGER,
       book_id INTEGER,
       book_number INTEGER,
       notes TEXT,
       legacy_ref INTEGER,
       created_by INTEGER,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_advance_repayments (
       id @ID,
       advance_id INTEGER NOT NULL REFERENCES hr_employee_advances(id),
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       amount @REAL NOT NULL DEFAULT 0,
       repay_date @TS NOT NULL,
       source TEXT NOT NULL DEFAULT 'payroll',
       payroll_run_id INTEGER,
       payroll_line_id INTEGER,
       safe_transaction_id INTEGER,
       notes TEXT,
       created_by INTEGER,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_payroll_adjustments (
       id @ID,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       kind TEXT NOT NULL,
       amount @REAL NOT NULL DEFAULT 0,
       period_year INTEGER NOT NULL,
       period_month INTEGER NOT NULL,
       reason TEXT NOT NULL,
       status TEXT NOT NULL DEFAULT 'pending',
       decided_by INTEGER,
       decided_at @TS,
       payroll_run_id INTEGER,
       legacy_ref INTEGER,
       created_by INTEGER,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_commission_plans (
       id @ID,
       name TEXT NOT NULL,
       employee_id INTEGER,
       sales_rate @REAL NOT NULL DEFAULT 0,
       collections_rate @REAL NOT NULL DEFAULT 0,
       tiers TEXT,
       category_rates TEXT,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_payroll_runs (
       id @ID,
       period_year INTEGER NOT NULL,
       period_month INTEGER NOT NULL,
       period_from @TS NOT NULL,
       period_to @TS NOT NULL,
       branch_id INTEGER,
       department_id INTEGER,
       status TEXT NOT NULL DEFAULT 'draft',
       journal_entry_id INTEGER,
       reversal_journal_entry_id INTEGER,
       total_gross @REAL NOT NULL DEFAULT 0,
       total_deductions @REAL NOT NULL DEFAULT 0,
       total_net @REAL NOT NULL DEFAULT 0,
       total_employer @REAL NOT NULL DEFAULT 0,
       total_paid @REAL NOT NULL DEFAULT 0,
       employee_count INTEGER NOT NULL DEFAULT 0,
       is_legacy INTEGER NOT NULL DEFAULT 0,
       notes TEXT,
       created_by INTEGER,
       reviewed_by INTEGER,
       approved_by INTEGER,
       posted_by INTEGER,
       posted_at @TS,
       reversed_by INTEGER,
       reversed_at @TS,
       reversal_reason TEXT,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_payroll_lines (
       id @ID,
       run_id INTEGER NOT NULL REFERENCES hr_payroll_runs(id),
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       branch_id INTEGER,
       department_id INTEGER,
       basic_salary @REAL NOT NULL DEFAULT 0,
       paid_days @REAL NOT NULL DEFAULT 0,
       period_days @REAL NOT NULL DEFAULT 0,
       gross @REAL NOT NULL DEFAULT 0,
       deductions @REAL NOT NULL DEFAULT 0,
       net @REAL NOT NULL DEFAULT 0,
       employer_cost @REAL NOT NULL DEFAULT 0,
       paid_amount @REAL NOT NULL DEFAULT 0,
       payment_status TEXT NOT NULL DEFAULT 'unpaid',
       payment_method TEXT,
       safe_transaction_id INTEGER,
       paid_at @TS,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_payroll_items (
       id @ID,
       run_id INTEGER NOT NULL REFERENCES hr_payroll_runs(id),
       line_id INTEGER NOT NULL REFERENCES hr_payroll_lines(id),
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       kind TEXT NOT NULL,
       code TEXT NOT NULL,
       label TEXT NOT NULL,
       amount @REAL NOT NULL DEFAULT 0,
       quantity @REAL,
       rate @REAL,
       account_key TEXT NOT NULL,
       is_manual INTEGER NOT NULL DEFAULT 0,
       reason TEXT,
       ref_type TEXT,
       ref_id INTEGER,
       created_by INTEGER,
       created_at @TS NOT NULL DEFAULT @NOW,
@SYNC
     )''',
];

List<String> _hrPayrollCreate({required bool pg}) => [
      for (final sql in _hrPayrollTables)
        sql
            .replaceAll('@SYNC', pg ? _kHrSyncPg : _kHrSync)
            .replaceAll(
                '@ID', pg ? 'SERIAL PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT')
            .replaceAll('@TS', pg ? 'BIGINT' : 'INTEGER')
            .replaceAll('@REAL', pg ? 'DOUBLE PRECISION' : 'REAL')
            .replaceAll('@NOW',
                pg ? 'EXTRACT(EPOCH FROM NOW())::bigint' : "(strftime('%s','now'))"),
    ];

final _hrPayrollSqliteCreate = _hrPayrollCreate(pg: false);
final _hrPayrollPostgresCreate = _hrPayrollCreate(pg: true);

/// Every v193 table, parents first (the sync lists use this order).
const kHrPayrollTables = <String>[
  'hr_payroll_settings',
  'hr_salary_components',
  'hr_commission_plans',
  'hr_employee_advances',
  'hr_advance_repayments',
  'hr_payroll_adjustments',
  'hr_payroll_runs',
  'hr_payroll_lines',
  'hr_payroll_items',
];

const _hrPayrollIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_hr_payroll_lines_run '
      'ON hr_payroll_lines(run_id)',
  'CREATE INDEX IF NOT EXISTS idx_hr_payroll_lines_employee '
      'ON hr_payroll_lines(employee_id)',
  'CREATE INDEX IF NOT EXISTS idx_hr_payroll_items_line '
      'ON hr_payroll_items(line_id)',
  'CREATE INDEX IF NOT EXISTS idx_hr_payroll_runs_period '
      'ON hr_payroll_runs(period_year, period_month)',
  'CREATE INDEX IF NOT EXISTS idx_hr_employee_advances_employee '
      'ON hr_employee_advances(employee_id)',
  'CREATE INDEX IF NOT EXISTS idx_hr_advance_repayments_advance '
      'ON hr_advance_repayments(advance_id)',
  'CREATE INDEX IF NOT EXISTS idx_hr_payroll_adjustments_employee '
      'ON hr_payroll_adjustments(employee_id, period_year, period_month)',
];

const _hrPayrollUniqueIndexes = <String>[
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_payroll_settings_key '
      'ON hr_payroll_settings(setting_key) WHERE deleted_at IS NULL',
  // One line per employee per run.
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_payroll_lines_unique '
      'ON hr_payroll_lines(run_id, employee_id) WHERE deleted_at IS NULL',
];

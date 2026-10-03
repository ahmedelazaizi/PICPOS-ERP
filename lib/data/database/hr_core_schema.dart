part of 'database.dart';

/// v191 — ملفُّ الموظف وربطُ الأدوار (J4 الجزء ١، قرارُ المالك).
///
/// Raw SQL outside Drift's table model (no codegen run), following the
/// `distribution_model_schema.dart` / `system_parties_schema.dart` pattern:
///
/// • `employees` gains raw columns for the personal / job / contract / pay
///   tabs ([_kHrEmployeeColumns]) plus `user_id` (the ONE login user of the
///   employee — a partial UNIQUE index keeps one user ↔ one employee) and
///   `role_tags` (CSV of [HrRoleTag]). Drift columns keep their meaning:
///   `name` = Arabic name, `salary` = basic salary, `hired_at` = hire date,
///   `is_active` mirrors `employment_status == 'active'`, `role` stays the
///   legacy UralCash role.
/// • `hr_departments` / `hr_job_titles` — the organisation.
/// • `employee_allowances` — the pay components part 3 (payroll) reads.
/// • `employee_documents` — attachment metadata with an expiry date.
/// • `employee_history` — appointment / transfer / promotion / termination…
///   recorded automatically by `saveEmployeeProfile`.
///
/// Travels by the generic `SELECT *` delta pull (the five tables are in
/// `DeltaPullService.pullTables`; the columns ride `employees`).
extension HrCoreSchema on AppDatabase {
  Future<void> ensureHrCoreSchema() async {
    final creates = _isPostgres ? _hrCorePostgresCreate : _hrCoreSqliteCreate;
    for (final statement in creates) {
      await customStatement(statement);
    }
    await _hrAddEmployeeColumns();
    for (final statement in _hrCoreIndexes) {
      await customStatement(statement);
    }
    // A UNIQUE index fails on duplicate data (a sync race, a restored
    // backup): the app-level checks still hold, so it must not block startup.
    for (final statement in _hrCoreUniqueIndexes) {
      try {
        await customStatement(statement);
      } catch (e) {
        debugPrint('[HR] unique index skipped: $e');
      }
    }
  }

  Future<void> _hrAddEmployeeColumns() async {
    final existing = _isPostgres
        ? const <String>{}
        : {
            for (final c in await customSelect('PRAGMA table_info(employees)')
                .get())
              c.data['name'] as String,
          };
    for (final (name, type) in _kHrEmployeeColumns) {
      final sqlType = switch (type) {
        'EPOCH' => _isPostgres ? 'BIGINT' : 'INTEGER',
        'REAL' => _isPostgres ? 'DOUBLE PRECISION' : 'REAL',
        _ => type,
      };
      if (_isPostgres) {
        await customStatement(
            'ALTER TABLE employees ADD COLUMN IF NOT EXISTS $name $sqlType');
        continue;
      }
      if (existing.contains(name)) continue;
      try {
        await customStatement('ALTER TABLE employees ADD COLUMN $name $sqlType');
      } catch (error) {
        if (!isIdempotentMigrationError(error.toString())) rethrow;
      }
    }
  }

  /// Fills what v191 added for employees that existed before it: a code, a
  /// job title from the legacy `role`, a status, employment type, payment
  /// method, the latest contract dates, rep/cashier tags and an
  /// «appointment» history event. Only NULLs are filled, so it is idempotent
  /// and never overrides a user's edit. Seed rows use deterministic global
  /// ids, so two installs back-filling the same employee converge on sync.
  Future<void> backfillHrCoreData() async {
    final drift = await select(employees).get();
    if (drift.isEmpty) return;
    final raw = {
      for (final r in await customSelect(
        'SELECT id, employee_code, employment_status, employment_type, '
        'payment_method, job_title_id, contract_start, role_tags, global_id '
        'FROM employees',
      ).get())
        (r.data['id'] as num).toInt(): r.data,
    };
    final repIds = {
      for (final r in await customSelect(
        'SELECT sales_rep_id AS id FROM sales_routes '
        'WHERE sales_rep_id IS NOT NULL AND deleted_at IS NULL '
        'UNION SELECT employee_id AS id FROM rep_resources '
        'WHERE deleted_at IS NULL',
      ).get())
        (r.data['id'] as num).toInt(),
    };
    final withHistory = {
      for (final r in await customSelect(
        'SELECT DISTINCT employee_id FROM employee_history',
      ).get())
        (r.data['employee_id'] as num).toInt(),
    };
    for (final e in drift) {
      final d = raw[e.id] ?? const <String, dynamic>{};
      final sets = <String, Variable<Object>>{};
      if ((d['employee_code'] as String?) == null) {
        sets['employee_code'] = Variable<String>(await _hrFreeCode(e.id));
      }
      if (d['employment_status'] == null) {
        sets['employment_status'] = Variable<String>(
            e.isActive ? EmployeeStatus.active : EmployeeStatus.suspended);
      }
      if (d['employment_type'] == null) {
        sets['employment_type'] = const Variable<String>(EmploymentType.fullTime);
      }
      if (d['payment_method'] == null) {
        sets['payment_method'] = const Variable<String>(SalaryPaymentMethod.cash);
      }
      if (d['job_title_id'] == null && e.role.trim().isNotEmpty) {
        sets['job_title_id'] = Variable<int>(await _hrLegacyJobTitle(e.role));
      }
      if (d['contract_start'] == null) {
        final contract = await (select(employeeContracts)
              ..where((c) => c.employeeId.equals(e.id))
              ..orderBy([(c) => OrderingTerm.desc(c.startDate)])
              ..limit(1))
            .getSingleOrNull();
        if (contract != null) {
          sets['contract_start'] = Variable<int>(_hrEpoch(contract.startDate));
          sets['contract_end'] = Variable<int>(_hrEpoch(contract.endDate));
        }
      }
      if (d['role_tags'] == null) {
        final tags = {
          if (repIds.contains(e.id)) HrRoleTag.rep,
          if (e.role == 'cashier') HrRoleTag.cashier,
        };
        final encoded = HrRoleTag.encode(tags);
        if (encoded != null) sets['role_tags'] = Variable<String>(encoded);
      }
      if (sets.isNotEmpty) {
        await customUpdate(
          'UPDATE employees SET ${sets.keys.map((k) => '$k = ?').join(', ')} '
          'WHERE id = ?',
          variables: [...sets.values, Variable<int>(e.id)],
          updates: {employees},
        );
      }
      if (!withHistory.contains(e.id)) {
        await _dmInsert('employee_history', {
          'employee_id': e.id,
          'event_type': HrEventType.appointment,
          'event_date': _hrEpoch(e.hiredAt),
          'global_id': UuidV7.deriveSeedGlobalId(
            table: 'employee_history',
            seedKey: 'appointment:${e.globalId ?? d['global_id'] ?? e.id}',
          ),
        });
      }
    }
  }

  /// `EMP-0007` for employee 7 — or the next free number when taken.
  Future<String> _hrFreeCode(int employeeId) async {
    var n = employeeId;
    while (true) {
      final code = 'EMP-${n.toString().padLeft(4, '0')}';
      final taken = await customSelect(
        'SELECT id FROM employees WHERE employee_code = ? LIMIT 1',
        variables: [Variable<String>(code)],
      ).getSingleOrNull();
      if (taken == null) return code;
      n += 1000;
    }
  }

  /// The job title a legacy `employees.role` maps to (created once).
  Future<int> _hrLegacyJobTitle(String role) async {
    final name = _kLegacyRoleTitles[role] ?? role.trim();
    final existing = await customSelect(
      'SELECT id FROM hr_job_titles WHERE name = ? AND deleted_at IS NULL '
      'ORDER BY id LIMIT 1',
      variables: [Variable<String>(name)],
    ).getSingleOrNull();
    if (existing != null) return (existing.data['id'] as num).toInt();
    return _dmInsert('hr_job_titles', {
      'name': name,
      'is_active': 1,
      'global_id': UuidV7.deriveSeedGlobalId(
          table: 'hr_job_titles', seedKey: 'legacy:$role'),
    });
  }
}

int? _hrEpoch(DateTime? d) =>
    d == null ? null : d.millisecondsSinceEpoch ~/ 1000;

/// Legacy `employees.role` values (UralCash dialog) → Arabic job titles.
const _kLegacyRoleTitles = <String, String>{
  'manager': 'مدير',
  'cashier': 'كاشير',
  'waiter': 'نادل',
  'chef': 'طاهٍ',
  'cleaner': 'عامل نظافة',
  'staff': 'موظف',
};

/// The v191 raw columns on `employees` — `EPOCH` = seconds since epoch
/// (BIGINT on PostgreSQL).
const _kHrEmployeeColumns = <(String, String)>[
  ('employee_code', 'TEXT'),
  ('name_en', 'TEXT'),
  ('national_id', 'TEXT'),
  ('birth_date', 'EPOCH'),
  ('gender', 'TEXT'),
  ('nationality', 'TEXT'),
  ('phone2', 'TEXT'),
  ('email', 'TEXT'),
  ('address', 'TEXT'),
  ('emergency_contact_name', 'TEXT'),
  ('emergency_contact_phone', 'TEXT'),
  ('photo_path', 'TEXT'),
  ('department_id', 'INTEGER'),
  ('job_title_id', 'INTEGER'),
  ('manager_id', 'INTEGER'),
  ('employment_type', 'TEXT'),
  ('employment_status', 'TEXT'),
  ('termination_date', 'EPOCH'),
  ('termination_reason', 'TEXT'),
  ('contract_start', 'EPOCH'),
  ('contract_end', 'EPOCH'),
  ('probation_end', 'EPOCH'),
  ('payment_method', 'TEXT'),
  ('bank_name', 'TEXT'),
  ('bank_account', 'TEXT'),
  ('iban', 'TEXT'),
  ('user_id', 'INTEGER'),
  ('role_tags', 'TEXT'),
];

const _hrCoreSqliteCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS hr_departments (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       name_en TEXT,
       code TEXT,
       parent_id INTEGER,
       manager_employee_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_job_titles (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       name_en TEXT,
       department_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_allowances (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       name TEXT NOT NULL,
       amount REAL NOT NULL DEFAULT 0,
       amount_type TEXT NOT NULL DEFAULT 'fixed',
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_documents (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       doc_type TEXT NOT NULL,
       doc_number TEXT,
       issue_date INTEGER,
       expiry_date INTEGER,
       file_path TEXT,
       notes TEXT,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_history (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       event_type TEXT NOT NULL,
       event_date INTEGER NOT NULL,
       from_value TEXT,
       to_value TEXT,
       notes TEXT,
       user_id INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _hrCorePostgresCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS hr_departments (
       id SERIAL PRIMARY KEY,
       name TEXT NOT NULL,
       name_en TEXT,
       code TEXT,
       parent_id INTEGER,
       manager_employee_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_job_titles (
       id SERIAL PRIMARY KEY,
       name TEXT NOT NULL,
       name_en TEXT,
       department_id INTEGER,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_allowances (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       name TEXT NOT NULL,
       amount DOUBLE PRECISION NOT NULL DEFAULT 0,
       amount_type TEXT NOT NULL DEFAULT 'fixed',
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_documents (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       doc_type TEXT NOT NULL,
       doc_number TEXT,
       issue_date BIGINT,
       expiry_date BIGINT,
       file_path TEXT,
       notes TEXT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS employee_history (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       event_type TEXT NOT NULL,
       event_date BIGINT NOT NULL,
       from_value TEXT,
       to_value TEXT,
       notes TEXT,
       user_id INTEGER,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _hrCoreIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_employee_allowances_employee '
      'ON employee_allowances(employee_id)',
  'CREATE INDEX IF NOT EXISTS idx_employee_documents_employee '
      'ON employee_documents(employee_id)',
  'CREATE INDEX IF NOT EXISTS idx_employee_history_employee '
      'ON employee_history(employee_id, event_date)',
  'CREATE INDEX IF NOT EXISTS idx_employees_department '
      'ON employees(department_id)',
];

const _hrCoreUniqueIndexes = <String>[
  // One login user ↔ one employee.
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_user_link '
      'ON employees(user_id) WHERE user_id IS NOT NULL AND deleted_at IS NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_code '
      'ON employees(employee_code) '
      'WHERE employee_code IS NOT NULL AND deleted_at IS NULL',
];

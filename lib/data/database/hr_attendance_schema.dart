part of 'database.dart';

/// v192 — الورديّاتُ والحضورُ والإجازات (J4 الجزء ٢، قرارُ المالك).
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// `hr_core_schema.dart`:
///
/// • `hr_shifts` — a work shift (start/end minute, break, grace, weekly days
///   off, overtime threshold). End ≤ start ⇒ crosses midnight.
/// • `hr_shift_assignments` — which shift an employee works from a date
///   (history kept: a new assignment closes the open one).
/// • `hr_attendance_days` — one row per employee per work day: the two
///   punches and what the user marked explicitly (present / absent / leave).
///   The status itself (late, day off, holiday…) is computed, never stored.
/// • `hr_public_holidays` — company-wide holidays by date.
/// • `hr_leave_types` · `hr_leave_entitlements` · `hr_leave_requests` — leave
///   types, per-year balances and the request workflow.
///
/// The legacy UralCash tables (`employee_attendance` · `employee_leaves` ·
/// `leave_balances` · `work_holidays`) stay as they are — the legacy screen
/// «الحضور والرواتب» and its payroll still read them. [migrateLegacyHrAttendance]
/// copies their rows here (idempotent, deterministic global ids), and every
/// attendance write here is mirrored back to `employee_attendance` so the
/// legacy payroll keeps deducting what the new board marks.
extension HrAttendanceSchema on AppDatabase {
  Future<void> ensureHrAttendanceSchema() async {
    final creates =
        _isPostgres ? _hrAttendancePostgresCreate : _hrAttendanceSqliteCreate;
    for (final statement in creates) {
      await customStatement(statement);
    }
    for (final statement in _hrAttendanceIndexes) {
      await customStatement(statement);
    }
    for (final statement in _hrAttendanceUniqueIndexes) {
      try {
        await customStatement(statement);
      } catch (e) {
        debugPrint('[HR] attendance unique index skipped: $e');
      }
    }
  }

  /// The four system leave types (deterministic global ids, so two installs
  /// seeding them converge on sync). Existing rows are never touched.
  Future<void> ensureDefaultLeaveTypes() async {
    final existing = {
      for (final r in await customSelect(
        'SELECT code FROM hr_leave_types WHERE deleted_at IS NULL',
      ).get())
        r.data['code'] as String?,
    };
    for (final (code, name, paid, days, accrual) in _kDefaultLeaveTypes) {
      if (existing.contains(code)) continue;
      final gid = UuidV7.deriveSeedGlobalId(
          table: 'hr_leave_types', seedKey: 'system:$code');
      final taken = await customSelect(
        'SELECT id FROM hr_leave_types WHERE global_id = ?',
        variables: [Variable<String>(gid)],
      ).getSingleOrNull();
      if (taken != null) continue;
      await _dmInsert('hr_leave_types', {
        'code': code,
        'name': name,
        'is_paid': paid ? 1 : 0,
        'yearly_days': days,
        'carry_over_max': 0.0,
        'requires_attachment': code == 'sick' ? 1 : 0,
        'accrual': accrual,
        'is_active': 1,
        'global_id': gid,
      });
    }
  }

  /// Copies the legacy attendance / leave / balance / holiday rows into the
  /// v192 tables. Idempotent: a legacy row maps to a deterministic global id
  /// and is skipped once copied (even if later deleted here), and a day that
  /// already has a row here is never overwritten. Runs on every non-client
  /// startup, so rows the legacy screen keeps writing still arrive.
  Future<void> migrateLegacyHrAttendance() async {
    await ensureDefaultLeaveTypes();
    String gid(String table, Object id) =>
        UuidV7.deriveSeedGlobalId(table: table, seedKey: 'legacy:$id');
    Future<Set<String>> gids(String table) async => {
          for (final r in await customSelect(
            'SELECT global_id FROM $table WHERE global_id IS NOT NULL',
          ).get())
            r.data['global_id'] as String,
        };
    final employeeIds = {
      for (final e in await select(employees).get()) e.id,
    };

    // Holidays: only company-wide dated rows (weekday rows stay the weekly
    // days off of employees without a shift — read live from
    // `work_holidays`; a branch-only date is not a company holiday).
    final holidayGids = await gids('hr_public_holidays');
    final holidayDays = {
      for (final r in await customSelect(
        'SELECT holiday_date FROM hr_public_holidays WHERE deleted_at IS NULL',
      ).get())
        _dmInt(r.data['holiday_date']),
    };
    for (final h in await select(workHolidays).get()) {
      final date = h.date;
      if (date == null || h.branchId != null) continue;
      final g = gid('hr_public_holidays', h.id);
      final day = _hrEpoch(hrDay(date));
      if (holidayGids.contains(g) || holidayDays.contains(day)) continue;
      await _dmInsert('hr_public_holidays', {
        'holiday_date': day,
        'name': h.name,
        'global_id': g,
      });
      holidayDays.add(day);
    }

    final typeIds = {
      for (final t in await customSelect(
        'SELECT id, code FROM hr_leave_types WHERE deleted_at IS NULL '
        'ORDER BY id',
      ).get())
        t.data['code'] as String: (t.data['id'] as num).toInt(),
    };
    int? typeOf(String legacy) => typeIds[legacy] ?? typeIds['annual'];

    final requestGids = await gids('hr_leave_requests');
    for (final l in await select(employeeLeaves).get()) {
      final g = gid('hr_leave_requests', l.id);
      final type = typeOf(l.leaveType);
      if (requestGids.contains(g) || type == null) continue;
      if (!employeeIds.contains(l.employeeId)) continue;
      await _dmInsert('hr_leave_requests', {
        'employee_id': l.employeeId,
        'leave_type_id': type,
        'start_date': _hrEpoch(hrDay(l.startDate)),
        'end_date': _hrEpoch(hrDay(l.endDate)),
        'days': l.days.toDouble(),
        'status': switch (l.status) {
          'approved' => 'approved',
          'rejected' => 'rejected',
          'cancelled' => 'cancelled',
          _ => 'submitted',
        },
        'reason': l.notes,
        'decided_by': l.approvedBy,
        'global_id': g,
      });
    }

    final balanceKeys = {
      for (final r in await customSelect(
        'SELECT employee_id, leave_type_id, year FROM hr_leave_entitlements '
        'WHERE deleted_at IS NULL',
      ).get())
        '${r.data['employee_id']}:${r.data['leave_type_id']}:${r.data['year']}',
    };
    final balanceGids = await gids('hr_leave_entitlements');
    for (final b in await select(leaveBalances).get()) {
      final type = typeOf(b.leaveType);
      final g = gid('hr_leave_entitlements', b.id);
      if (type == null || balanceGids.contains(g)) continue;
      if (!employeeIds.contains(b.employeeId)) continue;
      if (!balanceKeys.add('${b.employeeId}:$type:${b.year}')) continue;
      await _dmInsert('hr_leave_entitlements', {
        'employee_id': b.employeeId,
        'leave_type_id': type,
        'year': b.year,
        'opening_days': 0.0,
        'opening_locked': 1,
        'accrued_days': b.totalDays.toDouble(),
        'entitlement_override': b.totalDays.toDouble(),
        'used_days': b.usedDays.toDouble(),
        'global_id': g,
      });
    }

    final dayGids = await gids('hr_attendance_days');
    final dayKeys = {
      for (final r in await customSelect(
        'SELECT employee_id, work_date FROM hr_attendance_days '
        'WHERE deleted_at IS NULL',
      ).get())
        '${r.data['employee_id']}:${r.data['work_date']}',
    };
    for (final a in await select(employeeAttendance).get()) {
      final g = gid('hr_attendance_days', a.id);
      if (dayGids.contains(g) || !employeeIds.contains(a.employeeId)) continue;
      final day = _hrEpoch(hrDay(a.date))!;
      if (!dayKeys.add('${a.employeeId}:$day')) continue;
      final punched = a.checkIn != null || a.checkOut != null;
      await _dmInsert('hr_attendance_days', {
        'employee_id': a.employeeId,
        'work_date': day,
        'check_in': _hrEpoch(a.checkIn),
        'check_out': _hrEpoch(a.checkOut),
        'mark': switch (a.status) {
          'absent' => AttendanceMark.absent,
          'leave' || 'sick' => AttendanceMark.leave,
          'unpaid_leave' => AttendanceMark.unpaidLeave,
          _ => punched ? null : AttendanceMark.present,
        },
        'source': AttendanceSource.legacy,
        'notes': a.notes,
        'global_id': g,
      });
    }
  }

  /// One-time grant of the v192 codes: roles holding `hr_view` get
  /// `hr_attendance_view`; roles holding `hr_manage` (which ran attendance
  /// and approved leaves in the legacy screen) get the edit / request /
  /// approve / shifts codes. Admin is covered by `syncAllPermissions`.
  Future<void> backfillHrAttendancePermissionsOnce() async {
    const flag = 'hr_attendance_perm_backfill_done';
    if (await getSettingValue(flag) == 'true') return;
    const pairs = <String, List<String>>{
      PermissionCodes.hrView: [PermissionCodes.hrAttendanceView],
      PermissionCodes.hrManage: [
        PermissionCodes.hrAttendanceView,
        PermissionCodes.hrAttendanceEdit,
        PermissionCodes.hrLeaveRequest,
        PermissionCodes.hrLeaveApprove,
        PermissionCodes.hrShiftsManage,
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
}

/// (code, Arabic name, paid, yearly days, accrual) — the legacy defaults
/// (`initializeLeaveBalances`: 21 annual · 15 sick · 3 emergency).
const _kDefaultLeaveTypes = <(String, String, bool, double, String)>[
  ('annual', 'إجازة سنوية', true, 21.0, 'yearly'),
  ('sick', 'إجازة مرضية', true, 15.0, 'yearly'),
  ('unpaid', 'إجازة بدون أجر', false, 0.0, 'none'),
  ('emergency', 'إجازة طارئة', true, 3.0, 'yearly'),
];

const _hrAttendanceSqliteCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS hr_shifts (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       name_en TEXT,
       start_minute INTEGER NOT NULL,
       end_minute INTEGER NOT NULL,
       break_minutes INTEGER NOT NULL DEFAULT 0,
       grace_late_minutes INTEGER NOT NULL DEFAULT 0,
       days_off TEXT,
       overtime_after_minutes INTEGER NOT NULL DEFAULT 0,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_shift_assignments (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       shift_id INTEGER NOT NULL REFERENCES hr_shifts(id),
       effective_from INTEGER NOT NULL,
       effective_to INTEGER,
       notes TEXT,
       user_id INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_public_holidays (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       holiday_date INTEGER NOT NULL,
       name TEXT NOT NULL,
       name_en TEXT,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_types (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       code TEXT NOT NULL,
       name TEXT NOT NULL,
       name_en TEXT,
       is_paid INTEGER NOT NULL DEFAULT 1,
       yearly_days REAL NOT NULL DEFAULT 0,
       carry_over_max REAL NOT NULL DEFAULT 0,
       requires_attachment INTEGER NOT NULL DEFAULT 0,
       accrual TEXT NOT NULL DEFAULT 'yearly',
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_requests (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       leave_type_id INTEGER NOT NULL REFERENCES hr_leave_types(id),
       start_date INTEGER NOT NULL,
       end_date INTEGER NOT NULL,
       days REAL NOT NULL DEFAULT 0,
       status TEXT NOT NULL DEFAULT 'draft',
       reason TEXT,
       attachment_path TEXT,
       requested_by INTEGER,
       decided_by INTEGER,
       decided_at INTEGER,
       decision_note TEXT,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_entitlements (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       leave_type_id INTEGER NOT NULL REFERENCES hr_leave_types(id),
       year INTEGER NOT NULL,
       opening_days REAL NOT NULL DEFAULT 0,
       opening_locked INTEGER NOT NULL DEFAULT 0,
       accrued_days REAL NOT NULL DEFAULT 0,
       entitlement_override REAL,
       used_days REAL NOT NULL DEFAULT 0,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_attendance_days (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       work_date INTEGER NOT NULL,
       check_in INTEGER,
       check_out INTEGER,
       mark TEXT,
       source TEXT NOT NULL DEFAULT 'manual',
       leave_request_id INTEGER,
       notes TEXT,
       edit_reason TEXT,
       edited_by INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _hrAttendancePostgresCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS hr_shifts (
       id SERIAL PRIMARY KEY,
       name TEXT NOT NULL,
       name_en TEXT,
       start_minute INTEGER NOT NULL,
       end_minute INTEGER NOT NULL,
       break_minutes INTEGER NOT NULL DEFAULT 0,
       grace_late_minutes INTEGER NOT NULL DEFAULT 0,
       days_off TEXT,
       overtime_after_minutes INTEGER NOT NULL DEFAULT 0,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_shift_assignments (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       shift_id INTEGER NOT NULL REFERENCES hr_shifts(id),
       effective_from BIGINT NOT NULL,
       effective_to BIGINT,
       notes TEXT,
       user_id INTEGER,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_public_holidays (
       id SERIAL PRIMARY KEY,
       holiday_date BIGINT NOT NULL,
       name TEXT NOT NULL,
       name_en TEXT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_types (
       id SERIAL PRIMARY KEY,
       code TEXT NOT NULL,
       name TEXT NOT NULL,
       name_en TEXT,
       is_paid INTEGER NOT NULL DEFAULT 1,
       yearly_days DOUBLE PRECISION NOT NULL DEFAULT 0,
       carry_over_max DOUBLE PRECISION NOT NULL DEFAULT 0,
       requires_attachment INTEGER NOT NULL DEFAULT 0,
       accrual TEXT NOT NULL DEFAULT 'yearly',
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_requests (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       leave_type_id INTEGER NOT NULL REFERENCES hr_leave_types(id),
       start_date BIGINT NOT NULL,
       end_date BIGINT NOT NULL,
       days DOUBLE PRECISION NOT NULL DEFAULT 0,
       status TEXT NOT NULL DEFAULT 'draft',
       reason TEXT,
       attachment_path TEXT,
       requested_by INTEGER,
       decided_by INTEGER,
       decided_at BIGINT,
       decision_note TEXT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_leave_entitlements (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       leave_type_id INTEGER NOT NULL REFERENCES hr_leave_types(id),
       year INTEGER NOT NULL,
       opening_days DOUBLE PRECISION NOT NULL DEFAULT 0,
       opening_locked INTEGER NOT NULL DEFAULT 0,
       accrued_days DOUBLE PRECISION NOT NULL DEFAULT 0,
       entitlement_override DOUBLE PRECISION,
       used_days DOUBLE PRECISION NOT NULL DEFAULT 0,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS hr_attendance_days (
       id SERIAL PRIMARY KEY,
       employee_id INTEGER NOT NULL REFERENCES employees(id),
       work_date BIGINT NOT NULL,
       check_in BIGINT,
       check_out BIGINT,
       mark TEXT,
       source TEXT NOT NULL DEFAULT 'manual',
       leave_request_id INTEGER,
       notes TEXT,
       edit_reason TEXT,
       edited_by INTEGER,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _hrAttendanceIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_hr_shift_assignments_employee '
      'ON hr_shift_assignments(employee_id, effective_from)',
  'CREATE INDEX IF NOT EXISTS idx_hr_attendance_days_date '
      'ON hr_attendance_days(work_date)',
  'CREATE INDEX IF NOT EXISTS idx_hr_leave_requests_employee '
      'ON hr_leave_requests(employee_id, start_date)',
];

const _hrAttendanceUniqueIndexes = <String>[
  // One attendance row per employee per work day.
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_attendance_days_unique '
      'ON hr_attendance_days(employee_id, work_date) WHERE deleted_at IS NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_public_holidays_date '
      'ON hr_public_holidays(holiday_date) WHERE deleted_at IS NULL',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_leave_entitlements_unique '
      'ON hr_leave_entitlements(employee_id, leave_type_id, year) '
      'WHERE deleted_at IS NULL',
];

part of '../database.dart';

/// J4 — ملفُّ الموظف: القراءةُ والحفظُ وتسجيلُ الأحداث آليّاً، والأقسامُ
/// والمسمّياتُ والبدلاتُ والمستندات (جداول v191 في `hr_core_schema.dart`).
extension HrEmployeeFileDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // Departments & job titles
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<HrDepartment>> listHrDepartments({bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT d.*, (SELECT COUNT(*) FROM employees e WHERE e.department_id = d.id '
      'AND e.deleted_at IS NULL) AS employee_count FROM hr_departments d '
      'WHERE d.deleted_at IS NULL ${activeOnly ? 'AND d.is_active = 1 ' : ''}'
      'ORDER BY d.name',
      readsFrom: {employees},
    ).get();
    return [
      for (final r in rows)
        HrDepartment(
          id: (r.data['id'] as num).toInt(),
          name: r.data['name'] as String? ?? '',
          nameEn: r.data['name_en'] as String?,
          code: r.data['code'] as String?,
          parentId: _dmInt(r.data['parent_id']),
          managerEmployeeId: _dmInt(r.data['manager_employee_id']),
          isActive: _dmBool(r.data['is_active']),
          employeeCount: _dmInt(r.data['employee_count']) ?? 0,
        ),
    ];
  }

  Future<int> saveHrDepartment({
    int? id,
    required String name,
    String? nameEn,
    String? code,
    int? parentId,
    int? managerEmployeeId,
    bool isActive = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw HrException('اسم القسم مطلوب.');
    if (id != null && parentId == id) {
      throw HrException('لا يكون القسم تابعاً لنفسه.');
    }
    await _hrAssertUniqueName('hr_departments', trimmed, id,
        'يوجد قسم بنفس الاسم.');
    final values = {
      'name': trimmed,
      'name_en': _dmBlank(nameEn),
      'code': _dmBlank(code),
      'parent_id': parentId,
      'manager_employee_id': managerEmployeeId,
      'is_active': isActive ? 1 : 0,
    };
    if (id == null) return _dmInsert('hr_departments', values);
    await _hrUpdateRow('hr_departments', id, values);
    return id;
  }

  /// Soft-deletes an empty department (no employees, sub-departments or
  /// job titles).
  Future<void> deleteHrDepartment(int id) async {
    final used = await customSelect(
      'SELECT (SELECT COUNT(*) FROM employees WHERE department_id = ? '
      'AND deleted_at IS NULL) + (SELECT COUNT(*) FROM hr_departments '
      'WHERE parent_id = ? AND deleted_at IS NULL) + (SELECT COUNT(*) FROM '
      'hr_job_titles WHERE department_id = ? AND deleted_at IS NULL) AS n',
      variables: [Variable<int>(id), Variable<int>(id), Variable<int>(id)],
    ).getSingle();
    if ((_dmInt(used.data['n']) ?? 0) > 0) {
      throw HrException(
          'لا يمكن حذف القسم — عليه موظفون أو أقسام فرعية أو مسميات.');
    }
    await _hrSoftDelete('hr_departments', id);
  }

  Future<List<HrJobTitle>> listHrJobTitles({bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT t.*, (SELECT COUNT(*) FROM employees e WHERE e.job_title_id = t.id '
      'AND e.deleted_at IS NULL) AS employee_count FROM hr_job_titles t '
      'WHERE t.deleted_at IS NULL ${activeOnly ? 'AND t.is_active = 1 ' : ''}'
      'ORDER BY t.name',
      readsFrom: {employees},
    ).get();
    return [
      for (final r in rows)
        HrJobTitle(
          id: (r.data['id'] as num).toInt(),
          name: r.data['name'] as String? ?? '',
          nameEn: r.data['name_en'] as String?,
          departmentId: _dmInt(r.data['department_id']),
          isActive: _dmBool(r.data['is_active']),
          employeeCount: _dmInt(r.data['employee_count']) ?? 0,
        ),
    ];
  }

  Future<int> saveHrJobTitle({
    int? id,
    required String name,
    String? nameEn,
    int? departmentId,
    bool isActive = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw HrException('اسم المسمى الوظيفي مطلوب.');
    await _hrAssertUniqueName('hr_job_titles', trimmed, id,
        'يوجد مسمى وظيفي بنفس الاسم.');
    final values = {
      'name': trimmed,
      'name_en': _dmBlank(nameEn),
      'department_id': departmentId,
      'is_active': isActive ? 1 : 0,
    };
    if (id == null) return _dmInsert('hr_job_titles', values);
    await _hrUpdateRow('hr_job_titles', id, values);
    return id;
  }

  Future<void> deleteHrJobTitle(int id) async {
    final used = await customSelect(
      'SELECT COUNT(*) AS n FROM employees WHERE job_title_id = ? '
      'AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingle();
    if ((_dmInt(used.data['n']) ?? 0) > 0) {
      throw HrException('لا يمكن حذف المسمى — يحمله موظفون.');
    }
    await _hrSoftDelete('hr_job_titles', id);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Employee profiles
  // ═══════════════════════════════════════════════════════════════════════

  /// Every non-deleted employee as a full profile (with display names).
  Future<List<EmployeeProfile>> listEmployeeProfiles() async {
    final drift = await (select(employees)
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .get();
    return _hrProfiles(drift);
  }

  Future<EmployeeProfile?> getEmployeeProfile(int id) async {
    final e = await (select(employees)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    if (e == null) return null;
    return (await _hrProfiles([e])).single;
  }

  Future<List<EmployeeProfile>> _hrProfiles(List<Employee> drift) async {
    if (drift.isEmpty) return const [];
    final raw = {
      for (final r in await customSelect(
        'SELECT id, ${_kHrEmployeeColumns.map((c) => c.$1).join(', ')} '
        'FROM employees',
        readsFrom: {employees},
      ).get())
        (r.data['id'] as num).toInt(): r.data,
    };
    final departments = {for (final d in await listHrDepartments()) d.id: d};
    final titles = {for (final t in await listHrJobTitles()) t.id: t};
    final branchNames = {
      for (final b in await select(branches).get()) b.id: b.name,
    };
    final names = {
      for (final e in await select(employees).get()) e.id: e.name,
    };
    final usernames = {
      for (final u in await select(users).get()) u.id: u.username,
    };
    return [
      for (final e in drift)
        _hrProfileOf(e, raw[e.id] ?? const {}, departments, titles,
            branchNames, names, usernames),
    ];
  }

  EmployeeProfile _hrProfileOf(
    Employee e,
    Map<String, dynamic> d,
    Map<int, HrDepartment> departments,
    Map<int, HrJobTitle> titles,
    Map<int, String> branchNames,
    Map<int, String> names,
    Map<int, String> usernames,
  ) {
    String? s(String k) => d[k] as String?;
    final departmentId = _dmInt(d['department_id']);
    final jobTitleId = _dmInt(d['job_title_id']);
    final managerId = _dmInt(d['manager_id']);
    final userId = _dmInt(d['user_id']);
    return EmployeeProfile(
      id: e.id,
      globalId: e.globalId,
      code: s('employee_code'),
      name: e.name,
      nameEn: s('name_en'),
      nationalId: s('national_id'),
      birthDate: _dmDate(d['birth_date']),
      gender: s('gender'),
      nationality: s('nationality'),
      phone: e.phone,
      phone2: s('phone2'),
      email: s('email'),
      address: s('address'),
      emergencyContactName: s('emergency_contact_name'),
      emergencyContactPhone: s('emergency_contact_phone'),
      photoPath: s('photo_path'),
      departmentId: departmentId,
      jobTitleId: jobTitleId,
      branchId: e.branchId,
      managerId: managerId,
      hireDate: e.hiredAt,
      employmentType: s('employment_type') ?? EmploymentType.fullTime,
      status: s('employment_status') ??
          (e.isActive ? EmployeeStatus.active : EmployeeStatus.suspended),
      terminationDate: _dmDate(d['termination_date']),
      terminationReason: s('termination_reason'),
      contractStart: _dmDate(d['contract_start']),
      contractEnd: _dmDate(d['contract_end']),
      probationEnd: _dmDate(d['probation_end']),
      basicSalary: e.salary,
      salaryType: e.salaryType,
      hoursPerDay: e.hoursPerDay,
      paymentMethod: s('payment_method') ?? SalaryPaymentMethod.cash,
      bankName: s('bank_name'),
      bankAccount: s('bank_account'),
      iban: s('iban'),
      userId: userId,
      roleTags: HrRoleTag.decode(s('role_tags')),
      legacyRole: e.role,
      departmentName: departments[departmentId]?.name,
      jobTitleName: titles[jobTitleId]?.name,
      branchName: branchNames[e.branchId],
      managerName: names[managerId],
      username: usernames[userId],
    );
  }

  /// Creates ([EmployeeProfile.id] null) or updates an employee with every
  /// tab of its file, and records the change as history events
  /// (appointment / transfer / promotion / salary change / status change /
  /// termination). [allowances] null leaves the allowances untouched.
  Future<int> saveEmployeeProfile(
    EmployeeProfile p, {
    List<EmployeeAllowance>? allowances,
    int? actorUserId,
  }) {
    return transaction(() async {
      final name = p.name.trim();
      if (name.isEmpty) throw HrException('اسم الموظف مطلوب.');
      if (name.length > 100) {
        throw HrException('اسم الموظف أطول من 100 حرف.');
      }
      if (p.salaryType == 'hourly' &&
          (p.hoursPerDay == null || p.hoursPerDay! <= 0)) {
        throw HrException('ساعات العمل اليومية مطلوبة لموظف بالساعة.');
      }
      if (p.basicSalary < 0) throw HrException('الراتب الأساسي لا يكون سالباً.');
      final before = p.id == null ? null : await getEmployeeProfile(p.id!);
      if (p.id != null && before == null) {
        throw HrException('الموظف غير موجود.');
      }
      if (p.managerId != null) await _hrAssertManager(p.id, p.managerId!);
      final code = _dmBlank(p.code) ?? await _hrNextCode();
      final clash = await customSelect(
        'SELECT name FROM employees WHERE employee_code = ? AND id <> ? '
        'AND deleted_at IS NULL LIMIT 1',
        variables: [Variable<String>(code), Variable<int>(p.id ?? -1)],
      ).getSingleOrNull();
      if (clash != null) {
        throw HrException('كود الموظف مستخدم للموظف «{p0}».',
            {'p0': clash.data['name']});
      }
      final terminated = p.status == EmployeeStatus.terminated;
      final terminationDate =
          terminated ? (p.terminationDate ?? DateTime.now()) : null;
      final now = DateTime.now();
      final companion = EmployeesCompanion(
        name: Value(name),
        phone: Value(_dmBlank(p.phone)),
        role: Value(p.legacyRole),
        salary: Value(p.basicSalary),
        salaryType: Value(p.salaryType),
        branchId: Value(p.branchId),
        isActive: Value(p.status == EmployeeStatus.active),
        hiredAt: Value(p.hireDate ?? before?.hireDate ?? now),
        hoursPerDay: Value(p.hoursPerDay),
        lastModifiedAt: Value(now),
      );
      final int id;
      if (p.id == null) {
        id = await into(employees).insert(
            companion.copyWith(globalId: Value(UuidV7.generate())));
      } else {
        id = p.id!;
        await (update(employees)..where((e) => e.id.equals(id)))
            .write(companion);
      }
      await customUpdate(
        'UPDATE employees SET employee_code = ?, name_en = ?, national_id = ?, '
        'birth_date = ?, gender = ?, nationality = ?, phone2 = ?, email = ?, '
        'address = ?, emergency_contact_name = ?, emergency_contact_phone = ?, '
        'photo_path = ?, department_id = ?, job_title_id = ?, manager_id = ?, '
        'employment_type = ?, employment_status = ?, termination_date = ?, '
        'termination_reason = ?, contract_start = ?, contract_end = ?, '
        'probation_end = ?, payment_method = ?, bank_name = ?, '
        'bank_account = ?, iban = ? WHERE id = ?',
        variables: [
          Variable<String>(code),
          Variable<String>(_dmBlank(p.nameEn)),
          Variable<String>(_dmBlank(p.nationalId)),
          Variable<int>(_hrEpoch(p.birthDate)),
          Variable<String>(p.gender),
          Variable<String>(_dmBlank(p.nationality)),
          Variable<String>(_dmBlank(p.phone2)),
          Variable<String>(_dmBlank(p.email)),
          Variable<String>(_dmBlank(p.address)),
          Variable<String>(_dmBlank(p.emergencyContactName)),
          Variable<String>(_dmBlank(p.emergencyContactPhone)),
          Variable<String>(_dmBlank(p.photoPath)),
          Variable<int>(p.departmentId),
          Variable<int>(p.jobTitleId),
          Variable<int>(p.managerId),
          Variable<String>(p.employmentType),
          Variable<String>(p.status),
          Variable<int>(_hrEpoch(terminationDate)),
          Variable<String>(terminated ? _dmBlank(p.terminationReason) : null),
          Variable<int>(_hrEpoch(p.contractStart)),
          Variable<int>(_hrEpoch(p.contractEnd)),
          Variable<int>(_hrEpoch(p.probationEnd)),
          Variable<String>(p.paymentMethod),
          Variable<String>(_dmBlank(p.bankName)),
          Variable<String>(_dmBlank(p.bankAccount)),
          Variable<String>(_dmBlank(p.iban)),
          Variable<int>(id),
        ],
        updates: {employees},
      );
      if (allowances != null) await _hrReplaceAllowances(id, allowances);
      final after = (await getEmployeeProfile(id))!;
      await _hrLogChanges(before, after, actorUserId);
      return id;
    });
  }

  /// The manager must exist and must not report (directly or not) to the
  /// employee — a cycle would make the org chart a loop.
  Future<void> _hrAssertManager(int? employeeId, int managerId) async {
    if (managerId == employeeId) {
      throw HrException('لا يكون الموظف مديراً لنفسه.');
    }
    final chain = {
      for (final r in await customSelect(
              'SELECT id, manager_id FROM employees WHERE deleted_at IS NULL')
          .get())
        (r.data['id'] as num).toInt(): _dmInt(r.data['manager_id']),
    };
    if (!chain.containsKey(managerId)) {
      throw HrException('المدير المباشر غير موجود.');
    }
    final seen = <int>{};
    int? cursor = managerId;
    while (cursor != null && seen.add(cursor)) {
      if (cursor == employeeId) {
        throw HrException('المدير المختار يتبع هذا الموظف — حلقة في الهيكل.');
      }
      cursor = chain[cursor];
    }
  }

  /// Next free `EMP-####` code.
  Future<String> _hrNextCode() async {
    final rows = await customSelect(
      "SELECT employee_code FROM employees WHERE employee_code LIKE 'EMP-%'",
    ).get();
    var max = 0;
    for (final r in rows) {
      final n = int.tryParse(
          (r.data['employee_code'] as String).substring(4).split('-').first);
      if (n != null && n > max) max = n;
    }
    return 'EMP-${(max + 1).toString().padLeft(4, '0')}';
  }

  Future<void> _hrLogChanges(
      EmployeeProfile? before, EmployeeProfile after, int? actorUserId) async {
    final id = after.id!;
    Future<void> log(String type, {String? from, String? to, String? notes}) =>
        logEmployeeEvent(id, type,
            from: from, to: to, notes: notes, actorUserId: actorUserId);
    if (before == null) {
      await log(HrEventType.appointment,
          to: _hrJoin([after.jobTitleName, after.departmentName, after.branchName]),
          notes: after.code);
      return;
    }
    if (before.departmentId != after.departmentId ||
        before.branchId != after.branchId) {
      await log(HrEventType.transfer,
          from: _hrJoin([before.departmentName, before.branchName]),
          to: _hrJoin([after.departmentName, after.branchName]));
    }
    if (before.jobTitleId != after.jobTitleId) {
      await log(HrEventType.promotion,
          from: before.jobTitleName, to: after.jobTitleName);
    }
    if (before.basicSalary != after.basicSalary) {
      await log(HrEventType.salaryChange,
          from: before.basicSalary.toStringAsFixed(2),
          to: after.basicSalary.toStringAsFixed(2));
    }
    if (before.status != after.status) {
      if (after.status == EmployeeStatus.terminated) {
        await log(HrEventType.termination,
            from: before.status,
            to: after.status,
            notes: after.terminationReason);
      } else {
        await log(HrEventType.statusChange,
            from: before.status, to: after.status);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // History
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> logEmployeeEvent(
    int employeeId,
    String eventType, {
    String? from,
    String? to,
    String? notes,
    int? actorUserId,
    DateTime? at,
  }) async {
    await _dmInsert('employee_history', {
      'employee_id': employeeId,
      'event_type': eventType,
      'event_date': _hrEpoch(at ?? DateTime.now()),
      'from_value': _dmBlank(from),
      'to_value': _dmBlank(to),
      'notes': _dmBlank(notes),
      'user_id': actorUserId,
    });
  }

  Future<List<EmployeeHistoryEvent>> listEmployeeHistory(int employeeId) async {
    final rows = await customSelect(
      'SELECT * FROM employee_history WHERE employee_id = ? '
      'AND deleted_at IS NULL ORDER BY event_date DESC, id DESC',
      variables: [Variable<int>(employeeId)],
    ).get();
    return [
      for (final r in rows)
        EmployeeHistoryEvent(
          id: (r.data['id'] as num).toInt(),
          employeeId: employeeId,
          eventType: r.data['event_type'] as String? ?? '',
          eventDate: _dmDate(r.data['event_date']) ?? DateTime.now(),
          fromValue: r.data['from_value'] as String?,
          toValue: r.data['to_value'] as String?,
          notes: r.data['notes'] as String?,
          userId: _dmInt(r.data['user_id']),
        ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Allowances
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<EmployeeAllowance>> listEmployeeAllowances(int employeeId) async {
    final rows = await customSelect(
      'SELECT * FROM employee_allowances WHERE employee_id = ? '
      'AND deleted_at IS NULL AND is_active = 1 ORDER BY id',
      variables: [Variable<int>(employeeId)],
    ).get();
    return [
      for (final r in rows)
        EmployeeAllowance(
          id: (r.data['id'] as num).toInt(),
          name: r.data['name'] as String? ?? '',
          amount: (r.data['amount'] as num?)?.toDouble() ?? 0,
          type: r.data['amount_type'] as String? ?? AllowanceType.fixed,
        ),
    ];
  }

  /// Makes [allowances] the employee's allowance list: rows with an id are
  /// updated, new ones inserted, missing ones soft-deleted (history stays).
  Future<void> _hrReplaceAllowances(
      int employeeId, List<EmployeeAllowance> allowances) async {
    final keep = <int>{};
    for (final a in allowances) {
      final name = a.name.trim();
      if (name.isEmpty) continue;
      if (a.amount < 0) throw HrException('قيمة البدل لا تكون سالبة.');
      if (a.type == AllowanceType.percent && a.amount > 100) {
        throw HrException('نسبة البدل لا تتجاوز 100٪.');
      }
      final values = {
        'name': name,
        'amount': a.amount,
        'amount_type': a.type,
        'is_active': 1,
      };
      if (a.id == null) {
        keep.add(await _dmInsert(
            'employee_allowances', {'employee_id': employeeId, ...values}));
      } else {
        keep.add(a.id!);
        await _hrUpdateRow('employee_allowances', a.id!, values);
      }
    }
    for (final existing in await listEmployeeAllowances(employeeId)) {
      if (!keep.contains(existing.id)) {
        await _hrSoftDelete('employee_allowances', existing.id!);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Documents
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<EmployeeDocument>> listEmployeeDocuments(int employeeId) async {
    final rows = await customSelect(
      'SELECT * FROM employee_documents WHERE employee_id = ? '
      'AND deleted_at IS NULL ORDER BY expiry_date IS NULL, expiry_date, id',
      variables: [Variable<int>(employeeId)],
    ).get();
    return [for (final r in rows) _hrDocumentOf(r.data)];
  }

  /// Documents expiring within [EmployeeDocument.warningDays] (or expired),
  /// per employee — the list screen's warning badge.
  Future<Map<int, int>> expiringDocumentCounts({DateTime? now}) async {
    final limit = (now ?? DateTime.now())
        .add(const Duration(days: EmployeeDocument.warningDays));
    final rows = await customSelect(
      'SELECT employee_id, COUNT(*) AS n FROM employee_documents '
      'WHERE deleted_at IS NULL AND expiry_date IS NOT NULL '
      'AND expiry_date <= ? GROUP BY employee_id',
      variables: [Variable<int>(_hrEpoch(limit))],
    ).get();
    return {
      for (final r in rows)
        (r.data['employee_id'] as num).toInt(): _dmInt(r.data['n']) ?? 0,
    };
  }

  Future<int> saveEmployeeDocument(int employeeId, EmployeeDocument doc) async {
    final type = doc.docType.trim();
    if (type.isEmpty) throw HrException('نوع المستند مطلوب.');
    if (doc.issueDate != null &&
        doc.expiryDate != null &&
        doc.expiryDate!.isBefore(doc.issueDate!)) {
      throw HrException('تاريخ الانتهاء قبل تاريخ الإصدار.');
    }
    final values = {
      'doc_type': type,
      'doc_number': _dmBlank(doc.docNumber),
      'issue_date': _hrEpoch(doc.issueDate),
      'expiry_date': _hrEpoch(doc.expiryDate),
      'file_path': _dmBlank(doc.filePath),
      'notes': _dmBlank(doc.notes),
    };
    if (doc.id == null) {
      return _dmInsert(
          'employee_documents', {'employee_id': employeeId, ...values});
    }
    await _hrUpdateRow('employee_documents', doc.id!, values);
    return doc.id!;
  }

  Future<void> deleteEmployeeDocument(int id) =>
      _hrSoftDelete('employee_documents', id);

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _hrAssertUniqueName(
      String table, String name, int? id, String message) async {
    final row = await customSelect(
      'SELECT id FROM $table WHERE name = ? AND id <> ? '
      'AND deleted_at IS NULL LIMIT 1',
      variables: [Variable<String>(name), Variable<int>(id ?? -1)],
    ).getSingleOrNull();
    if (row != null) throw HrException(message);
  }

  /// UPDATE [table] SET [values] (NULLs included) + `last_modified_at`.
  Future<void> _hrUpdateRow(
      String table, int id, Map<String, Object?> values) async {
    final cols = values.keys.toList();
    await customUpdate(
      'UPDATE $table SET ${cols.map((c) => '$c = ?').join(', ')}, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        for (final c in cols) _hrTypedVar(c, values[c]),
        Variable<int>(_dmNow()),
        Variable<int>(id),
      ],
      updates: {employees},
    );
  }

  Future<void> _hrSoftDelete(String table, int id) => customUpdate(
        'UPDATE $table SET deleted_at = ?, last_modified_at = ? WHERE id = ?',
        variables: [
          Variable<int>(_dmNow()),
          Variable<int>(_dmNow()),
          Variable<int>(id),
        ],
        updates: {employees},
      );
}

/// A typed variable for [column]. A NULL must keep the column's type —
/// PostgreSQL rejects a TEXT null for an INTEGER column — and the v191
/// nullable integer columns all end in `_id` or `_date`.
Variable<Object> _hrTypedVar(String column, Object? v) => switch (v) {
      int() => Variable<int>(v),
      double() => Variable<double>(v),
      bool() => Variable<int>(v ? 1 : 0),
      String() => Variable<String>(v),
      _ when column.endsWith('_id') || column.endsWith('_date') =>
        const Variable<int>(null),
      _ => const Variable<String>(null),
    };

String? _hrJoin(List<String?> parts) {
  final kept = [
    for (final p in parts)
      if (p != null && p.trim().isNotEmpty) p.trim(),
  ];
  return kept.isEmpty ? null : kept.join(' · ');
}

EmployeeDocument _hrDocumentOf(Map<String, dynamic> d) => EmployeeDocument(
      id: (d['id'] as num).toInt(),
      docType: d['doc_type'] as String? ?? '',
      docNumber: d['doc_number'] as String?,
      issueDate: _dmDate(d['issue_date']),
      expiryDate: _dmDate(d['expiry_date']),
      filePath: d['file_path'] as String?,
      notes: d['notes'] as String?,
    );

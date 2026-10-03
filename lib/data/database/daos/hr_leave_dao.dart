part of '../database.dart';

/// J4 (الجزء ٢) — أنواعُ الإجازات وأرصدتُها السنويّة ودورةُ الطلب:
/// مسودة → مقدَّم → معتمد / مرفوض، والإلغاء. الاعتمادُ (من المدير المباشر أو
/// صاحب `hr_leave_approve`) يعلّم أيّامَ العمل «إجازة» ويستهلك الرصيد.
extension HrLeaveDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // Leave types
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<LeaveType>> listLeaveTypes({bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT * FROM hr_leave_types WHERE deleted_at IS NULL '
      '${activeOnly ? 'AND is_active = 1 ' : ''}ORDER BY id',
    ).get();
    return [for (final r in rows) _hrLeaveTypeOf(r.data)];
  }

  Future<int> saveLeaveType(LeaveType t) async {
    final name = t.name.trim();
    if (name.isEmpty) throw HrException('اسم نوع الإجازة مطلوب.');
    if (t.yearlyDays < 0 || t.carryOverMax < 0) {
      throw HrException('الأيام لا تكون سالبة.');
    }
    if (t.yearlyDays > 366) throw HrException('الاستحقاق السنوي أكبر من سنة.');
    if (!LeaveAccrual.values.contains(t.accrual)) {
      throw HrException('طريقة الاستحقاق غير معروفة.');
    }
    await _hrAssertUniqueName(
        'hr_leave_types', name, t.id, 'يوجد نوع إجازة بنفس الاسم.');
    final values = <String, Object?>{
      'name': name,
      'name_en': _dmBlank(t.nameEn),
      'is_paid': t.isPaid ? 1 : 0,
      'yearly_days': t.yearlyDays,
      'carry_over_max': t.carryOverMax,
      'requires_attachment': t.requiresAttachment ? 1 : 0,
      'accrual': t.accrual,
      'is_active': t.isActive ? 1 : 0,
    };
    if (t.id == null) {
      return _dmInsert('hr_leave_types', {
        'code': LeaveTypeCode.system.contains(t.code) ? t.code : LeaveTypeCode.custom,
        ...values,
      });
    }
    await _hraUpdate('hr_leave_types', t.id!, values);
    return t.id!;
  }

  Future<void> deleteLeaveType(int id) async {
    final type = await _hrLeaveType(id);
    if (type.isSystem) {
      throw HrException('الأنواع الأساسية لا تُحذف — أوقفها بدلاً من ذلك.');
    }
    final used = await customSelect(
      'SELECT COUNT(*) AS n FROM hr_leave_requests WHERE leave_type_id = ? '
      'AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingle();
    if ((_dmInt(used.data['n']) ?? 0) > 0) {
      throw HrException('لا يمكن حذف نوع عليه طلبات — أوقفه بدلاً من ذلك.');
    }
    await _hrSoftDelete('hr_leave_types', id);
  }

  Future<LeaveType> _hrLeaveType(int id) async {
    final r = await customSelect(
      'SELECT * FROM hr_leave_types WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    if (r == null) throw HrException('نوع الإجازة غير موجود.');
    return _hrLeaveTypeOf(r.data);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Balances
  // ═══════════════════════════════════════════════════════════════════════

  /// أرصدةُ الموظف في [year] بعد إعادة حسابها حتى [asOf].
  Future<List<LeaveEntitlement>> employeeLeaveBalances(int employeeId, int year,
      {DateTime? asOf}) async {
    await refreshLeaveBalances(year, employeeId: employeeId, asOf: asOf);
    final types = {for (final t in await listLeaveTypes()) t.id!: t};
    final rows = await customSelect(
      'SELECT * FROM hr_leave_entitlements WHERE employee_id = ? AND year = ? '
      'AND deleted_at IS NULL ORDER BY leave_type_id',
      variables: [Variable<int>(employeeId), Variable<int>(year)],
    ).get();
    return [
      for (final r in rows)
        if (types[_dmInt(r.data['leave_type_id'])] case final t?)
          _hrEntitlementOf(r.data, t),
    ];
  }

  /// يعيد حسابَ أرصدة [year] (لموظفٍ أو للكلّ): الافتتاحيُّ = المتبقّي من
  /// السنة السابقة مقيَّداً بحدّ الترحيل (ما لم يُدخَل يدويّاً)، والمستحَقُّ
  /// بطريقة النوع حتى [asOf]، والمستهلَكُ = أيّامُ الطلبات المعتمدة.
  Future<void> refreshLeaveBalances(int year,
      {int? employeeId, DateTime? asOf}) async {
    final when = asOf ?? DateTime.now();
    final types = [
      for (final t in await listLeaveTypes()) if (t.hasEntitlement) t,
    ];
    if (types.isEmpty) return;
    final profiles = [
      for (final p in await listEmployeeProfiles())
        if (employeeId == null
            ? p.status != EmployeeStatus.terminated
            : p.id == employeeId)
          p,
    ];
    for (final p in profiles) {
      for (final t in types) {
        final prev = await _hrEntitlementRow(p.id!, t.id!, year - 1);
        double opening = 0;
        if (prev != null) {
          final prevBalance = await _hrRefreshOne(
              p, t, year - 1, DateTime(year - 1, 12, 31), prev,
              opening: _hrNum(prev['opening_days']));
          final carry = prevBalance.remaining;
          opening = carry <= 0 ? 0 : (carry < t.carryOverMax ? carry : t.carryOverMax);
        }
        final row = await _hrEntitlementRow(p.id!, t.id!, year);
        if (row != null && _dmBool(row['opening_locked'])) {
          opening = _hrNum(row['opening_days']);
        }
        await _hrRefreshOne(p, t, year, when, row, opening: opening);
      }
    }
  }

  Future<LeaveEntitlement> _hrRefreshOne(EmployeeProfile p, LeaveType t,
      int year, DateTime asOf, Map<String, dynamic>? row,
      {required double opening}) async {
    final override = row?['entitlement_override'];
    final accrued = override is num
        ? override.toDouble()
        : accruedLeaveDays(t, year, asOf, p.hireDate);
    final used = await _hrUsedLeaveDays(p.id!, t.id!, year);
    final values = <String, Object?>{
      'opening_days': opening,
      'accrued_days': accrued,
      'used_days': used,
    };
    if (row == null) {
      await _dmInsert('hr_leave_entitlements', {
        'employee_id': p.id,
        'leave_type_id': t.id,
        'year': year,
        ...values,
      });
    } else {
      await _hraUpdate(
          'hr_leave_entitlements', (row['id'] as num).toInt(), values);
    }
    return LeaveEntitlement(
      employeeId: p.id!,
      leaveTypeId: t.id!,
      year: year,
      openingDays: opening,
      accruedDays: accrued,
      usedDays: used,
      type: t,
    );
  }

  /// افتتاحيٌّ يدويٌّ (رصيدٌ مرحَّلٌ من خارج النظام) لا يُعاد حسابُه.
  Future<void> setLeaveOpeningBalance({
    required int employeeId,
    required int leaveTypeId,
    required int year,
    required double days,
  }) async {
    if (days < 0) throw HrException('الأيام لا تكون سالبة.');
    final row = await _hrEntitlementRow(employeeId, leaveTypeId, year);
    if (row == null) {
      await _dmInsert('hr_leave_entitlements', {
        'employee_id': employeeId,
        'leave_type_id': leaveTypeId,
        'year': year,
        'opening_days': days,
        'opening_locked': 1,
      });
    } else {
      await _hraUpdate('hr_leave_entitlements', (row['id'] as num).toInt(),
          {'opening_days': days, 'opening_locked': 1});
    }
    await refreshLeaveBalances(year, employeeId: employeeId);
  }

  Future<Map<String, dynamic>?> _hrEntitlementRow(
      int employeeId, int typeId, int year) async {
    final r = await customSelect(
      'SELECT * FROM hr_leave_entitlements WHERE employee_id = ? '
      'AND leave_type_id = ? AND year = ? AND deleted_at IS NULL',
      variables: [
        Variable<int>(employeeId),
        Variable<int>(typeId),
        Variable<int>(year),
      ],
    ).getSingleOrNull();
    return r?.data;
  }

  Future<double> _hrUsedLeaveDays(int employeeId, int typeId, int year) async {
    final r = await customSelect(
      'SELECT COALESCE(SUM(days), 0) AS n FROM hr_leave_requests '
      "WHERE employee_id = ? AND leave_type_id = ? AND status = 'approved' "
      'AND deleted_at IS NULL AND start_date >= ? AND start_date < ?',
      variables: [
        Variable<int>(employeeId),
        Variable<int>(typeId),
        Variable<int>(_hrEpoch(DateTime(year))),
        Variable<int>(_hrEpoch(DateTime(year + 1))),
      ],
    ).getSingle();
    return _hrNum(r.data['n']);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Requests
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<LeaveRequest>> listLeaveRequests({
    int? employeeId,
    String? status,
    int? year,
  }) async {
    final where = <String>['r.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (employeeId != null) {
      where.add('r.employee_id = ?');
      vars.add(Variable<int>(employeeId));
    }
    if (status != null) {
      where.add('r.status = ?');
      vars.add(Variable<String>(status));
    }
    if (year != null) {
      where.add('r.start_date >= ? AND r.start_date < ?');
      vars
        ..add(Variable<int>(_hrEpoch(DateTime(year))))
        ..add(Variable<int>(_hrEpoch(DateTime(year + 1))));
    }
    final types = {for (final t in await listLeaveTypes()) t.id!: t};
    final rows = await customSelect(
      'SELECT r.*, e.name AS employee_name FROM hr_leave_requests r '
      'JOIN employees e ON e.id = r.employee_id WHERE ${where.join(' AND ')} '
      'ORDER BY r.start_date DESC, r.id DESC',
      variables: vars,
      readsFrom: {employees},
    ).get();
    return [
      for (final r in rows)
        _hrRequestOf(r.data, types[_dmInt(r.data['leave_type_id'])]),
    ];
  }

  Future<LeaveRequest> getLeaveRequest(int id) async {
    final types = {for (final t in await listLeaveTypes()) t.id!: t};
    final r = await customSelect(
      'SELECT r.*, e.name AS employee_name FROM hr_leave_requests r '
      'JOIN employees e ON e.id = r.employee_id WHERE r.id = ?',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    if (r == null) throw HrException('طلب الإجازة غير موجود.');
    return _hrRequestOf(r.data, types[_dmInt(r.data['leave_type_id'])]);
  }

  /// ينشئ ([LeaveRequest.id] null) أو يعدّل طلباً في حالة المسودة. الأيّامُ
  /// تُحسَب: أيّامُ العمل في الفترة. [submit] يقدّمه فوراً.
  Future<int> saveLeaveRequest(LeaveRequest r,
      {int? actorUserId, bool submit = false}) async {
    final id = await transaction(() async {
      final from = hrDay(r.startDate);
      final to = hrDay(r.endDate);
      if (to.isBefore(from)) {
        throw HrException('تاريخ النهاية قبل تاريخ البداية.');
      }
      if (to.difference(from).inDays > 365) {
        throw HrException('فترة الإجازة أطول من سنة.');
      }
      final type = await _hrLeaveType(r.leaveTypeId);
      if (!type.isActive) throw HrException('نوع الإجازة موقوف.');
      if (r.id != null) {
        final current = await getLeaveRequest(r.id!);
        if (current.status != LeaveRequestStatus.draft) {
          throw HrException('لا يُعدَّل إلا طلب في حالة المسودة.');
        }
      }
      final days =
          (await employeeWorkingDays(r.employeeId, from, to)).length.toDouble();
      if (days <= 0) throw HrException('لا أيام عمل في الفترة المختارة.');
      await _hrAssertNoOverlap(r.employeeId, from, to, r.id);
      final values = <String, Object?>{
        'leave_type_id': r.leaveTypeId,
        'start_date': _hrEpoch(from),
        'end_date': _hrEpoch(to),
        'days': days,
        'reason': _dmBlank(r.reason),
        'attachment_path': _dmBlank(r.attachmentPath),
      };
      final int id;
      if (r.id == null) {
        id = await _dmInsert('hr_leave_requests', {
          'employee_id': r.employeeId,
          'status': LeaveRequestStatus.draft,
          'requested_by': actorUserId,
          ...values,
        });
      } else {
        id = r.id!;
        await _hraUpdate('hr_leave_requests', id, values);
      }
      return id;
    });
    // Outside the save transaction: a refused submit keeps the draft.
    if (submit) await submitLeaveRequest(id, actorUserId: actorUserId);
    return id;
  }

  Future<void> submitLeaveRequest(int id, {int? actorUserId}) {
    return transaction(() async {
      final r = await getLeaveRequest(id);
      if (r.status != LeaveRequestStatus.draft) {
        throw HrException('لا يُقدَّم إلا طلب في حالة المسودة.');
      }
      final type = r.type ?? await _hrLeaveType(r.leaveTypeId);
      if (type.requiresAttachment && (r.attachmentPath ?? '').trim().isEmpty) {
        throw HrException('هذا النوع من الإجازات يتطلب مرفقاً.');
      }
      await _hrAssertNoOverlap(r.employeeId, r.startDate, r.endDate, r.id);
      await _hrAssertBalance(r, type);
      await _hrSetRequestStatus(id, LeaveRequestStatus.submitted);
      await _hrLogLeave(r, LeaveRequestStatus.submitted, actorUserId);
    });
  }

  /// هل [userId] هو مستخدمُ المدير المباشر لـ[employeeId]؟
  Future<bool> isDirectManagerUser(int? userId, int employeeId) async {
    if (userId == null) return false;
    final r = await customSelect(
      'SELECT m.user_id FROM employees e JOIN employees m ON m.id = e.manager_id '
      'WHERE e.id = ?',
      variables: [Variable<int>(employeeId)],
    ).getSingleOrNull();
    return r != null && _dmInt(r.data['user_id']) == userId;
  }

  /// يعتمد طلباً مقدَّماً: المديرُ المباشر أو صاحبُ `hr_leave_approve`
  /// ([canApproveAll]). يعلّم أيّامَ العمل إجازةً ويستهلك الرصيد.
  Future<void> approveLeaveRequest(
    int id, {
    int? actorUserId,
    bool canApproveAll = false,
    String? note,
  }) {
    return transaction(() async {
      final r = await getLeaveRequest(id);
      await _hrAssertDecider(r, actorUserId, canApproveAll);
      final type = r.type ?? await _hrLeaveType(r.leaveTypeId);
      await _hrAssertNoOverlap(r.employeeId, r.startDate, r.endDate, r.id);
      await _hrAssertBalance(r, type);
      await _hrSetRequestStatus(id, LeaveRequestStatus.approved,
          decidedBy: actorUserId, note: note);
      final mark = type.isPaid ? AttendanceMark.leave : AttendanceMark.unpaidLeave;
      for (final day
          in await employeeWorkingDays(r.employeeId, r.startDate, r.endDate)) {
        final existing = await attendanceRecordFor(r.employeeId, day);
        await _hraUpsert(r.employeeId, day,
            checkIn: existing?.checkIn,
            checkOut: existing?.checkOut,
            mark: mark,
            source: existing?.source ?? AttendanceSource.leave,
            leaveRequestId: id,
            notes: existing?.notes,
            editReason: existing?.editReason,
            editedBy: actorUserId);
      }
      await refreshLeaveBalances(r.startDate.year, employeeId: r.employeeId);
      await _hrLogLeave(r, LeaveRequestStatus.approved, actorUserId, note: note);
    });
  }

  Future<void> rejectLeaveRequest(
    int id, {
    int? actorUserId,
    bool canApproveAll = false,
    String? note,
  }) {
    return transaction(() async {
      final r = await getLeaveRequest(id);
      await _hrAssertDecider(r, actorUserId, canApproveAll);
      await _hrSetRequestStatus(id, LeaveRequestStatus.rejected,
          decidedBy: actorUserId, note: note);
      await _hrLogLeave(r, LeaveRequestStatus.rejected, actorUserId, note: note);
    });
  }

  /// يلغي طلباً مفتوحاً. المعتمدُ تُرفع علاماتُه من الحضور (البصماتُ تبقى)
  /// ويعود رصيدُه.
  Future<void> cancelLeaveRequest(int id, {int? actorUserId, String? note}) {
    return transaction(() async {
      final r = await getLeaveRequest(id);
      if (!LeaveRequestStatus.blocking.contains(r.status)) {
        throw HrException('لا يُلغى طلب مرفوض أو ملغى.');
      }
      final wasApproved = r.status == LeaveRequestStatus.approved;
      await _hrSetRequestStatus(id, LeaveRequestStatus.cancelled,
          decidedBy: actorUserId, note: note);
      if (wasApproved) {
        final rows = await customSelect(
          'SELECT * FROM hr_attendance_days WHERE leave_request_id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable<int>(id)],
        ).get();
        for (final row in rows) {
          final rec = _hrRecordOf(row.data);
          await _hraUpsert(rec.employeeId, rec.workDate,
              checkIn: rec.checkIn,
              checkOut: rec.checkOut,
              source: rec.source,
              notes: rec.notes,
              editReason: rec.editReason,
              editedBy: actorUserId);
        }
        await refreshLeaveBalances(r.startDate.year, employeeId: r.employeeId);
      }
      await _hrLogLeave(r, LeaveRequestStatus.cancelled, actorUserId,
          note: note);
    });
  }

  Future<void> _hrAssertDecider(
      LeaveRequest r, int? actorUserId, bool canApproveAll) async {
    if (r.status != LeaveRequestStatus.submitted) {
      throw HrException('لا يُبتّ إلا في طلب مقدَّم.');
    }
    if (canApproveAll) return;
    if (!await isDirectManagerUser(actorUserId, r.employeeId)) {
      throw HrException(
          'الاعتماد للمدير المباشر أو لمن يملك صلاحية اعتماد الإجازات.');
    }
  }

  Future<void> _hrAssertNoOverlap(
      int employeeId, DateTime from, DateTime to, int? exceptId) async {
    final r = await customSelect(
      'SELECT start_date, end_date FROM hr_leave_requests WHERE employee_id = ? '
      "AND id <> ? AND deleted_at IS NULL AND status IN ('draft', 'submitted', "
      "'approved') AND start_date <= ? AND end_date >= ? LIMIT 1",
      variables: [
        Variable<int>(employeeId),
        Variable<int>(exceptId ?? -1),
        Variable<int>(_hrEpoch(hrDay(to))),
        Variable<int>(_hrEpoch(hrDay(from))),
      ],
    ).getSingleOrNull();
    if (r != null) {
      throw HrException('الطلب يتداخل مع طلب إجازة آخر ({p0} → {p1}).', {
        'p0': hrDateKey(_dmDate(r.data['start_date'])!),
        'p1': hrDateKey(_dmDate(r.data['end_date'])!),
      });
    }
  }

  Future<void> _hrAssertBalance(LeaveRequest r, LeaveType type) async {
    if (!type.hasEntitlement) return;
    final year = r.startDate.year;
    final now = DateTime.now();
    final asOf = r.startDate.isAfter(now) ? r.startDate : now;
    await refreshLeaveBalances(year, employeeId: r.employeeId, asOf: asOf);
    final row = await _hrEntitlementRow(r.employeeId, type.id!, year);
    final remaining = row == null
        ? 0.0
        : _hrNum(row['opening_days']) +
            _hrNum(row['accrued_days']) -
            _hrNum(row['used_days']);
    if (r.days > remaining + 1e-9) {
      throw HrException('رصيد الإجازة غير كافٍ (المتبقي {p0} يوم).',
          {'p0': _hrFmt(remaining)});
    }
  }

  Future<void> _hrSetRequestStatus(int id, String status,
      {int? decidedBy, String? note}) async {
    await _hraUpdate('hr_leave_requests', id, {
      'status': status,
      if (status != LeaveRequestStatus.submitted) ...{
        'decided_by': decidedBy,
        'decided_at': _dmNow(),
        'decision_note': _dmBlank(note),
      },
    });
  }

  Future<void> _hrLogLeave(LeaveRequest r, String status, int? actorUserId,
      {String? note}) =>
      logEmployeeEvent(r.employeeId, HrEventType.leave,
          from: r.type?.name,
          to: status,
          notes: [
            '${hrDateKey(r.startDate)} → ${hrDateKey(r.endDate)} '
                '(${_hrFmt(r.days)})',
            if (_dmBlank(note) != null) note!.trim(),
          ].join(' — '),
          actorUserId: actorUserId);
}

double _hrNum(Object? v) => v is num ? v.toDouble() : 0.0;

String _hrFmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

LeaveType _hrLeaveTypeOf(Map<String, dynamic> d) => LeaveType(
      id: (d['id'] as num).toInt(),
      code: d['code'] as String? ?? LeaveTypeCode.custom,
      name: d['name'] as String? ?? '',
      nameEn: d['name_en'] as String?,
      isPaid: _dmBool(d['is_paid']),
      yearlyDays: _hrNum(d['yearly_days']),
      carryOverMax: _hrNum(d['carry_over_max']),
      requiresAttachment: _dmBool(d['requires_attachment']),
      accrual: d['accrual'] as String? ?? LeaveAccrual.yearly,
      isActive: _dmBool(d['is_active']),
    );

LeaveEntitlement _hrEntitlementOf(Map<String, dynamic> d, LeaveType t) =>
    LeaveEntitlement(
      id: (d['id'] as num).toInt(),
      employeeId: (d['employee_id'] as num).toInt(),
      leaveTypeId: t.id!,
      year: _dmInt(d['year']) ?? 0,
      openingDays: _hrNum(d['opening_days']),
      accruedDays: _hrNum(d['accrued_days']),
      usedDays: _hrNum(d['used_days']),
      openingLocked: _dmBool(d['opening_locked']),
      entitlementOverride: (d['entitlement_override'] as num?)?.toDouble(),
      type: t,
    );

LeaveRequest _hrRequestOf(Map<String, dynamic> d, LeaveType? t) => LeaveRequest(
      id: (d['id'] as num).toInt(),
      employeeId: (d['employee_id'] as num).toInt(),
      leaveTypeId: (d['leave_type_id'] as num).toInt(),
      startDate: _dmDate(d['start_date'])!,
      endDate: _dmDate(d['end_date'])!,
      days: _hrNum(d['days']),
      status: d['status'] as String? ?? LeaveRequestStatus.draft,
      reason: d['reason'] as String?,
      attachmentPath: d['attachment_path'] as String?,
      requestedBy: _dmInt(d['requested_by']),
      decidedBy: _dmInt(d['decided_by']),
      decidedAt: _dmDate(d['decided_at']),
      decisionNote: d['decision_note'] as String?,
      employeeName: d['employee_name'] as String?,
      type: t,
    );

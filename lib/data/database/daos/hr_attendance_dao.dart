part of '../database.dart';

/// J4 (الجزء ٢) — الورديّاتُ وإسنادُها، والعطلاتُ الرسميّة، والحضورُ اليوميّ
/// (لوحةٌ وكشفٌ شهريٌّ وتصحيحٌ يدويٌّ واستيرادٌ من جهاز البصمة)، وملخّصُ
/// الفترة الذي يقرأه الجزءُ ٣. الجداولُ في `hr_attendance_schema.dart`.
extension HrAttendanceDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // Shifts
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<WorkShift>> listWorkShifts({bool activeOnly = false}) async {
    final today = _hrEpoch(hrDay(DateTime.now()));
    final rows = await customSelect(
      'SELECT s.*, (SELECT COUNT(DISTINCT a.employee_id) FROM '
      'hr_shift_assignments a WHERE a.shift_id = s.id AND a.deleted_at IS NULL '
      'AND a.effective_from <= ? AND (a.effective_to IS NULL OR '
      'a.effective_to >= ?)) AS employee_count FROM hr_shifts s '
      'WHERE s.deleted_at IS NULL ${activeOnly ? 'AND s.is_active = 1 ' : ''}'
      'ORDER BY s.start_minute, s.name',
      variables: [Variable<int>(today), Variable<int>(today)],
    ).get();
    return [for (final r in rows) _hrShiftOf(r.data)];
  }

  Future<int> saveWorkShift(WorkShift s) async {
    final name = s.name.trim();
    if (name.isEmpty) throw HrException('اسم الوردية مطلوب.');
    bool inDay(int m) => m >= 0 && m < 1440;
    if (!inDay(s.startMinute) || !inDay(s.endMinute)) {
      throw HrException('وقت بداية أو نهاية الوردية غير صحيح.');
    }
    if (s.startMinute == s.endMinute) {
      throw HrException('بداية الوردية ونهايتها متطابقتان.');
    }
    if (s.breakMinutes < 0 ||
        s.graceLateMinutes < 0 ||
        s.overtimeAfterMinutes < 0) {
      throw HrException('الدقائق لا تكون سالبة.');
    }
    final span = s.crossesMidnight
        ? s.endMinute + 1440 - s.startMinute
        : s.endMinute - s.startMinute;
    if (s.breakMinutes >= span) {
      throw HrException('الاستراحة أطول من الوردية.');
    }
    if (s.daysOff.length >= 7) {
      throw HrException('لا تكون كل أيام الأسبوع راحة.');
    }
    await _hrAssertUniqueName('hr_shifts', name, s.id, 'توجد وردية بنفس الاسم.');
    final values = <String, Object?>{
      'name': name,
      'name_en': _dmBlank(s.nameEn),
      'start_minute': s.startMinute,
      'end_minute': s.endMinute,
      'break_minutes': s.breakMinutes,
      'grace_late_minutes': s.graceLateMinutes,
      'days_off': WorkShift.encodeDays(s.daysOff),
      'overtime_after_minutes': s.overtimeAfterMinutes,
      'is_active': s.isActive ? 1 : 0,
    };
    if (s.id == null) return _dmInsert('hr_shifts', values);
    await _hraUpdate('hr_shifts', s.id!, values);
    return s.id!;
  }

  /// يحذف ورديّةً لم تُسنَد لأحدٍ قطّ؛ وغيرُها يُوقَف ولا يُحذَف (سجلُّها).
  Future<void> deleteWorkShift(int id) async {
    final used = await customSelect(
      'SELECT COUNT(*) AS n FROM hr_shift_assignments WHERE shift_id = ? '
      'AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingle();
    if ((_dmInt(used.data['n']) ?? 0) > 0) {
      throw HrException('لا يمكن حذف وردية لها إسنادات — أوقفها بدلاً من ذلك.');
    }
    await _hrSoftDelete('hr_shifts', id);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Assignments
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<ShiftAssignment>> listShiftAssignments({int? employeeId}) async {
    final rows = await customSelect(
      'SELECT a.*, s.name AS shift_name FROM hr_shift_assignments a '
      'JOIN hr_shifts s ON s.id = a.shift_id WHERE a.deleted_at IS NULL '
      '${employeeId == null ? '' : 'AND a.employee_id = ? '}'
      'ORDER BY a.employee_id, a.effective_from DESC',
      variables: [if (employeeId != null) Variable<int>(employeeId)],
    ).get();
    return [for (final r in rows) _hrAssignmentOf(r.data)];
  }

  /// الورديّةُ السارية لكلّ موظفٍ في [day] (‏`employeeId → shiftId`).
  Future<Map<int, int>> currentShiftIds({DateTime? day}) async {
    final d = hrDay(day ?? DateTime.now());
    return {
      for (final a in await listShiftAssignments())
        if (a.covers(d)) a.employeeId: a.shiftId,
    };
  }

  /// يُسند [shiftId] للموظف من [from]. السجلُّ يبقى: الإسنادُ المفتوحُ قبله
  /// يُغلَق في اليوم السابق لـ[from]، وما يبدأ من [from] فصاعداً يُستبدَل.
  Future<int> assignShift({
    required int employeeId,
    required int shiftId,
    required DateTime from,
    DateTime? to,
    String? notes,
    int? actorUserId,
  }) {
    return transaction(() async {
      final start = hrDay(from);
      if (to != null && hrDay(to).isBefore(start)) {
        throw HrException('تاريخ النهاية قبل تاريخ البداية.');
      }
      final shift = await customSelect(
        'SELECT name FROM hr_shifts WHERE id = ? AND deleted_at IS NULL',
        variables: [Variable<int>(shiftId)],
      ).getSingleOrNull();
      if (shift == null) throw HrException('الوردية غير موجودة.');
      final dayBefore = DateTime(start.year, start.month, start.day - 1);
      for (final a in await listShiftAssignments(employeeId: employeeId)) {
        if (!a.effectiveFrom.isBefore(start)) {
          await _hrSoftDelete('hr_shift_assignments', a.id);
        } else if (a.effectiveTo == null || !a.effectiveTo!.isBefore(start)) {
          await _hraUpdate('hr_shift_assignments', a.id,
              {'effective_to': _hrEpoch(dayBefore)});
        }
      }
      final id = await _dmInsert('hr_shift_assignments', {
        'employee_id': employeeId,
        'shift_id': shiftId,
        'effective_from': _hrEpoch(start),
        'effective_to': _hrEpoch(to == null ? null : hrDay(to)),
        'notes': _dmBlank(notes),
        'user_id': actorUserId,
      });
      await logEmployeeEvent(employeeId, HrEventType.shiftChange,
          to: shift.data['name'] as String?,
          notes: hrDateKey(start),
          actorUserId: actorUserId);
      return id;
    });
  }

  /// يُسند الورديّةَ لكلّ موظفٍ نشطٍ في [departmentId] و/أو [branchId].
  Future<int> assignShiftBulk({
    required int shiftId,
    required DateTime from,
    int? departmentId,
    int? branchId,
    int? actorUserId,
  }) async {
    var n = 0;
    for (final p in await listEmployeeProfiles()) {
      if (!p.isActive) continue;
      if (departmentId != null && p.departmentId != departmentId) continue;
      if (branchId != null && p.branchId != branchId) continue;
      await assignShift(
          employeeId: p.id!,
          shiftId: shiftId,
          from: from,
          actorUserId: actorUserId);
      n++;
    }
    return n;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Public holidays
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<PublicHoliday>> listPublicHolidays({int? year}) async {
    final rows = await customSelect(
      'SELECT * FROM hr_public_holidays WHERE deleted_at IS NULL '
      '${year == null ? '' : 'AND holiday_date >= ? AND holiday_date < ? '}'
      'ORDER BY holiday_date',
      variables: [
        if (year != null) Variable<int>(_hrEpoch(DateTime(year))),
        if (year != null) Variable<int>(_hrEpoch(DateTime(year + 1))),
      ],
    ).get();
    return [
      for (final r in rows)
        PublicHoliday(
          id: (r.data['id'] as num).toInt(),
          date: _dmDate(r.data['holiday_date'])!,
          name: r.data['name'] as String? ?? '',
          nameEn: r.data['name_en'] as String?,
        ),
    ];
  }

  Future<int> savePublicHoliday(PublicHoliday h) async {
    final name = h.name.trim();
    if (name.isEmpty) throw HrException('اسم العطلة مطلوب.');
    final day = _hrEpoch(hrDay(h.date));
    final clash = await customSelect(
      'SELECT name FROM hr_public_holidays WHERE holiday_date = ? AND id <> ? '
      'AND deleted_at IS NULL LIMIT 1',
      variables: [Variable<int>(day), Variable<int>(h.id ?? -1)],
    ).getSingleOrNull();
    if (clash != null) {
      throw HrException(
          'يوجد عطلة في هذا التاريخ «{p0}».', {'p0': clash.data['name']});
    }
    final values = {
      'holiday_date': day,
      'name': name,
      'name_en': _dmBlank(h.nameEn),
    };
    if (h.id == null) return _dmInsert('hr_public_holidays', values);
    await _hraUpdate('hr_public_holidays', h.id!, values);
    return h.id!;
  }

  Future<void> deletePublicHoliday(int id) =>
      _hrSoftDelete('hr_public_holidays', id);

  // ═══════════════════════════════════════════════════════════════════════
  // Computed attendance
  // ═══════════════════════════════════════════════════════════════════════

  /// لوحةُ يومٍ: كلُّ موظفٍ في الخدمة ذلك اليوم بورديّته وحالته المحسوبة.
  Future<List<AttendanceBoardRow>> attendanceBoard(
    DateTime day, {
    int? branchId,
    int? departmentId,
    DateTime? now,
  }) async {
    final d = hrDay(day);
    final data = await _hraLoad(d, d);
    final out = <AttendanceBoardRow>[];
    for (final p in data.employees.values) {
      if (branchId != null && p.branchId != branchId) continue;
      if (departmentId != null && p.departmentId != departmentId) continue;
      if (p.status == EmployeeStatus.suspended) continue;
      final a = _hraDay(data, p.id!, d, now ?? DateTime.now());
      if (a.status == AttendanceStatus.notEmployed) continue;
      out.add(AttendanceBoardRow(
        employeeId: p.id!,
        name: p.name,
        code: p.code,
        departmentName: p.departmentName,
        branchName: p.branchName,
        attendance: a,
      ));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// أيّامُ [from]..[to] شاملةً لموظفٍ واحد — الكشفُ الشهريّ.
  Future<List<DayAttendance>> employeeAttendanceDays(
    int employeeId,
    DateTime from,
    DateTime to, {
    DateTime? now,
  }) async {
    final f = hrDay(from);
    final t = hrDay(to);
    if (t.isBefore(f)) return const [];
    final data = await _hraLoad(f, t);
    if (!data.employees.containsKey(employeeId)) return const [];
    return [
      for (var d = f; !d.isAfter(t); d = DateTime(d.year, d.month, d.day + 1))
        _hraDay(data, employeeId, d, now ?? DateTime.now()),
    ];
  }

  /// ملخّصُ الفترة لموظف — **ما يقرأه مسيّرُ الرواتب (الجزء ٣)**: أيّامُ
  /// العمل والغياب ودقائقُ التأخير والانصراف المبكّر والإضافيّ وأيّامُ
  /// الإجازة المدفوعة وغير المدفوعة والعطلاتُ والراحة.
  Future<AttendanceSummary> attendanceSummary(
    int employeeId,
    DateTime from,
    DateTime to, {
    DateTime? now,
  }) async {
    final days = await employeeAttendanceDays(employeeId, from, to, now: now);
    return AttendanceSummary.of(employeeId, from, to,
        [for (final d in days) if (d.status != AttendanceStatus.notEmployed) d]);
  }

  /// أيّامُ العمل لموظفٍ في الفترة (بلا الراحة الأسبوعيّة والعطلات).
  Future<List<DateTime>> employeeWorkingDays(
      int employeeId, DateTime from, DateTime to) async {
    final f = hrDay(from);
    final t = hrDay(to);
    final data = await _hraLoad(f, t);
    return [
      for (var d = f; !d.isAfter(t); d = DateTime(d.year, d.month, d.day + 1))
        if (_hraIsWorkingDay(data, employeeId, d)) d,
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Writes
  // ═══════════════════════════════════════════════════════════════════════

  Future<AttendanceRecord?> attendanceRecordFor(
      int employeeId, DateTime day) async {
    final r = await customSelect(
      'SELECT * FROM hr_attendance_days WHERE employee_id = ? AND work_date = ? '
      'AND deleted_at IS NULL',
      variables: [
        Variable<int>(employeeId),
        Variable<int>(_hrEpoch(hrDay(day))),
      ],
    ).getSingleOrNull();
    return r == null ? null : _hrRecordOf(r.data);
  }

  /// إدخالٌ أو تصحيحٌ يدويٌّ لحضور يومٍ، **بسببٍ إلزاميّ** يُسجَّل في سجلّ
  /// الموظف (القيمةُ قبل وبعد). كلُّ الحقول فارغةٌ ⇒ يُحذَف صفُّ اليوم.
  Future<void> saveAttendanceEntry({
    required int employeeId,
    required DateTime day,
    DateTime? checkIn,
    DateTime? checkOut,
    String? mark,
    required String reason,
    int? actorUserId,
  }) {
    return transaction(() async {
      final why = reason.trim();
      if (why.isEmpty) throw HrException('سبب التعديل مطلوب.');
      final d = hrDay(day);
      if (checkIn != null && checkOut != null && !checkOut.isAfter(checkIn)) {
        throw HrException('الانصراف يجب أن يكون بعد الحضور.');
      }
      for (final t in [checkIn, checkOut]) {
        if (t == null) continue;
        if (t.isBefore(d) || !t.isBefore(DateTime(d.year, d.month, d.day + 2))) {
          throw HrException('وقت البصمة خارج يوم العمل.');
        }
      }
      final before = await attendanceRecordFor(employeeId, d);
      await _hraUpsert(employeeId, d,
          checkIn: checkIn,
          checkOut: checkOut,
          mark: mark,
          source: AttendanceSource.manual,
          leaveRequestId: before?.leaveRequestId,
          editReason: why,
          editedBy: actorUserId);
      await logEmployeeEvent(employeeId, HrEventType.attendanceEdit,
          from: before == null ? null : _hraDescribe(before),
          to: _hraDescribe(AttendanceRecord(
              employeeId: employeeId,
              workDate: d,
              checkIn: checkIn,
              checkOut: checkOut,
              mark: mark)),
          notes: '${hrDateKey(d)} — $why',
          actorUserId: actorUserId);
    });
  }

  /// «تحضير الكلّ»: كلُّ موظفٍ يومُه يومُ عملٍ بلا بصمةٍ ولا إجازة يُسجَّل
  /// حاضراً بأوقات ورديّته (أو حاضراً بلا أوقات إن لم تكن له ورديّة).
  Future<int> markAllPresent(
    DateTime day, {
    Set<int>? employeeIds,
    int? actorUserId,
    DateTime? now,
  }) async {
    final rows = await attendanceBoard(day, now: now);
    var n = 0;
    await transaction(() async {
      for (final row in rows) {
        if (employeeIds != null && !employeeIds.contains(row.employeeId)) {
          continue;
        }
        final a = row.attendance;
        if (a.status != AttendanceStatus.absent &&
            a.status != AttendanceStatus.pending) {
          continue;
        }
        if (a.record?.mark == AttendanceMark.absent) continue;
        final shift = a.shift;
        await _hraUpsert(row.employeeId, a.day,
            checkIn: shift?.startOn(a.day),
            checkOut: shift?.endOn(a.day),
            mark: shift == null ? AttendanceMark.present : null,
            source: AttendanceSource.bulk,
            editedBy: actorUserId);
        n++;
      }
    });
    return n;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Device CSV import
  // ═══════════════════════════════════════════════════════════════════════

  /// يحلّل الملفّ ويطابق الأكوادَ بالموظفين (‏`employee_code` أو معرّف
  /// جهاز البصمة) ويضع كلَّ بصمةٍ في يوم عملها — ورديّةٌ تعبر منتصفَ الليل
  /// تُنسب بصمتُها الفجريّةُ لليوم السابق. لا يكتب شيئاً.
  Future<AttendanceImportPreview> previewAttendanceImport(
      String text, AttendanceCsvMapping mapping) async {
    final parsed = parseAttendanceCsv(text, mapping);
    final byCode = <String, EmployeeProfile>{};
    final devices = {
      for (final e in await select(employees).get())
        if ((e.deviceUserId ?? '').trim().isNotEmpty) e.deviceUserId!.trim(): e.id,
    };
    final profiles = await listEmployeeProfiles();
    final byId = {for (final p in profiles) p.id!: p};
    for (final p in profiles) {
      if (p.code != null) byCode[p.code!.trim().toLowerCase()] = p;
    }
    final valid = [for (final p in parsed) if (p.isValid) p];
    DateTime? first, last;
    for (final p in valid) {
      if (first == null || p.at!.isBefore(first)) first = p.at;
      if (last == null || p.at!.isAfter(last)) last = p.at;
    }
    final data = first == null
        ? null
        : await _hraLoad(hrDay(first).subtract(const Duration(days: 1)),
            hrDay(last!));
    final rows = <AttendancePunch>[];
    for (final p in parsed) {
      if (!p.isValid) {
        rows.add(p);
        continue;
      }
      final profile = byCode[p.code.toLowerCase()] ?? byId[devices[p.code]];
      if (profile == null) {
        rows.add(p.resolved(error: 'كود الموظف غير موجود'));
        continue;
      }
      rows.add(p.resolved(
        employeeId: profile.id,
        employeeName: profile.name,
        workDate: _hraWorkDateOf(data!, profile.id!, p.at!),
      ));
    }
    final grouped = <String, List<AttendancePunch>>{};
    for (final r in rows) {
      if (r.error != null || r.employeeId == null) continue;
      grouped.putIfAbsent('${r.employeeId}:${hrDateKey(r.workDate!)}', () => [])
          .add(r);
    }
    final days = <ImportedAttendanceDay>[];
    for (final punches in grouped.values) {
      punches.sort((a, b) => a.at!.compareTo(b.at!));
      final ins = [
        for (final p in punches)
          if (p.direction == PunchDirection.checkIn) p.at!,
      ];
      final outs = [
        for (final p in punches)
          if (p.direction == PunchDirection.checkOut) p.at!,
      ];
      final unknown = [
        for (final p in punches)
          if (p.direction == PunchDirection.unknown) p.at!,
      ];
      DateTime? checkIn = ins.isEmpty ? null : ins.first;
      DateTime? checkOut = outs.isEmpty ? null : outs.last;
      if (unknown.isNotEmpty) {
        checkIn ??= unknown.first;
        if (checkOut == null && unknown.length > 1) checkOut = unknown.last;
      }
      if (checkIn != null && checkOut != null && !checkOut.isAfter(checkIn)) {
        checkOut = null;
      }
      days.add(ImportedAttendanceDay(
        employeeId: punches.first.employeeId!,
        employeeName: punches.first.employeeName ?? '',
        workDate: punches.first.workDate!,
        checkIn: checkIn,
        checkOut: checkOut,
        punches: punches.length,
      ));
    }
    days.sort((a, b) {
      final c = a.workDate.compareTo(b.workDate);
      return c != 0 ? c : a.employeeName.compareTo(b.employeeName);
    });
    return AttendanceImportPreview(rows: rows, days: days);
  }

  /// يكتب أيّامَ المعاينة: البصمةُ الأبكرُ حضوراً والأحدثُ انصرافاً مع ما
  /// كان مسجَّلاً، و«غائب» المعلَّمُ يُرفَع لأنّ الجهازَ يُثبت الحضور.
  Future<int> applyAttendanceImport(AttendanceImportPreview preview,
      {int? actorUserId}) {
    return transaction(() async {
      var n = 0;
      for (final d in preview.days) {
        final existing = await attendanceRecordFor(d.employeeId, d.workDate);
        DateTime? earliest(DateTime? a, DateTime? b) =>
            a == null ? b : (b == null || a.isBefore(b) ? a : b);
        DateTime? latest(DateTime? a, DateTime? b) =>
            a == null ? b : (b == null || a.isAfter(b) ? a : b);
        final checkIn = earliest(existing?.checkIn, d.checkIn);
        var checkOut = latest(existing?.checkOut, d.checkOut);
        if (checkIn != null && checkOut != null && !checkOut.isAfter(checkIn)) {
          checkOut = null;
        }
        final mark = existing?.mark == AttendanceMark.absent ||
                existing?.mark == AttendanceMark.present
            ? null
            : existing?.mark;
        await _hraUpsert(d.employeeId, d.workDate,
            checkIn: checkIn,
            checkOut: checkOut,
            mark: mark,
            source: AttendanceSource.device,
            leaveRequestId: existing?.leaveRequestId,
            notes: existing?.notes,
            editReason: existing?.editReason,
            editedBy: actorUserId);
        n++;
      }
      return n;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Internals
  // ═══════════════════════════════════════════════════════════════════════

  /// يكتب صفَّ اليوم (إدراجاً أو تحديثاً)، أو يحذفه إن لم يبقَ فيه شيء،
  /// ويعكسه على `employee_attendance` القديم كي يبقى مسيّرُ «الحضور
  /// والرواتب» يخصم ما تعلّمه اللوحة.
  Future<void> _hraUpsert(
    int employeeId,
    DateTime day, {
    DateTime? checkIn,
    DateTime? checkOut,
    String? mark,
    required String source,
    int? leaveRequestId,
    String? notes,
    String? editReason,
    int? editedBy,
  }) async {
    final d = hrDay(day);
    final existing = await attendanceRecordFor(employeeId, d);
    final empty = checkIn == null &&
        checkOut == null &&
        mark == null &&
        leaveRequestId == null;
    if (empty) {
      if (existing != null) {
        await _hrSoftDelete('hr_attendance_days', existing.id!);
      }
    } else {
      final values = <String, Object?>{
        'check_in': _hrEpoch(checkIn),
        'check_out': _hrEpoch(checkOut),
        'mark': mark,
        'source': source,
        'leave_request_id': leaveRequestId,
        'notes': _dmBlank(notes),
        'edit_reason': _dmBlank(editReason),
        'edited_by': editedBy,
      };
      if (existing == null) {
        await _dmInsert('hr_attendance_days', {
          'employee_id': employeeId,
          'work_date': _hrEpoch(d),
          ...values,
        });
      } else {
        await _hraUpdate('hr_attendance_days', existing.id!, values);
      }
    }
    await _hraMirrorLegacy(employeeId, d,
        checkIn: checkIn, checkOut: checkOut, mark: mark, clear: empty);
  }

  Future<void> _hraMirrorLegacy(
    int employeeId,
    DateTime day, {
    DateTime? checkIn,
    DateTime? checkOut,
    String? mark,
    bool clear = false,
  }) async {
    final legacy = await (select(employeeAttendance)
          ..where((a) => a.employeeId.equals(employeeId))
          ..where((a) => a.date.equals(day)))
        .get();
    if (clear) {
      for (final l in legacy) {
        await (delete(employeeAttendance)..where((a) => a.id.equals(l.id)))
            .go();
      }
      return;
    }
    final status = switch (mark) {
      AttendanceMark.absent => 'absent',
      AttendanceMark.leave => 'leave',
      AttendanceMark.unpaidLeave => 'unpaid_leave',
      _ => 'present',
    };
    final companion = EmployeeAttendanceCompanion(
      checkIn: Value(checkIn),
      checkOut: Value(checkOut),
      status: Value(status),
    );
    if (legacy.isEmpty) {
      await into(employeeAttendance).insert(companion.copyWith(
          employeeId: Value(employeeId), date: Value(day)));
    } else {
      await (update(employeeAttendance)
            ..where((a) => a.id.equals(legacy.first.id)))
          .write(companion);
    }
  }

  Future<void> _hraUpdate(
      String table, int id, Map<String, Object?> values) async {
    final cols = values.keys.toList();
    await customUpdate(
      'UPDATE $table SET ${cols.map((c) => '$c = ?').join(', ')}, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        for (final c in cols) _hraVar(c, values[c]),
        Variable<int>(_dmNow()),
        Variable<int>(id),
      ],
      updates: {employees},
    );
  }

  Future<_HrAttendanceData> _hraLoad(DateTime from, DateTime to) async {
    final profiles = await listEmployeeProfiles();
    final shifts = {
      for (final r in await customSelect('SELECT * FROM hr_shifts').get())
        (r.data['id'] as num).toInt(): _hrShiftOf(r.data),
    };
    final assignments = <int, List<ShiftAssignment>>{};
    for (final a in await listShiftAssignments()) {
      assignments.putIfAbsent(a.employeeId, () => []).add(a);
    }
    final lo = _hrEpoch(from.subtract(const Duration(days: 1)))!;
    final hi = _hrEpoch(DateTime(to.year, to.month, to.day + 2))!;
    final holidays = {
      for (final r in await customSelect(
        'SELECT holiday_date, name FROM hr_public_holidays '
        'WHERE deleted_at IS NULL AND holiday_date >= ? AND holiday_date <= ?',
        variables: [Variable<int>(lo), Variable<int>(hi)],
      ).get())
        hrDateKey(_dmDate(r.data['holiday_date'])!): r.data['name'] as String,
    };
    final records = {
      for (final r in await customSelect(
        'SELECT * FROM hr_attendance_days WHERE deleted_at IS NULL '
        'AND work_date >= ? AND work_date <= ?',
        variables: [Variable<int>(lo), Variable<int>(hi)],
      ).get())
        '${r.data['employee_id']}:${hrDateKey(_dmDate(r.data['work_date'])!)}':
            _hrRecordOf(r.data),
    };
    final leaves = <int, List<(DateTime, DateTime, LeaveDayMark)>>{};
    for (final r in await customSelect(
      'SELECT r.id, r.employee_id, r.start_date, r.end_date, t.is_paid, '
      't.name FROM hr_leave_requests r JOIN hr_leave_types t '
      'ON t.id = r.leave_type_id WHERE r.deleted_at IS NULL '
      "AND r.status = 'approved' AND r.start_date <= ? AND r.end_date >= ?",
      variables: [Variable<int>(hi), Variable<int>(lo)],
    ).get()) {
      leaves.putIfAbsent((r.data['employee_id'] as num).toInt(), () => []).add((
        _dmDate(r.data['start_date'])!,
        _dmDate(r.data['end_date'])!,
        LeaveDayMark(
          paid: _dmBool(r.data['is_paid']),
          requestId: (r.data['id'] as num).toInt(),
          typeName: r.data['name'] as String?,
        ),
      ));
    }
    final weeklyOff = <int?, Set<int>>{};
    for (final h in await (select(workHolidays)
          ..where((h) => h.weekday.isNotNull()))
        .get()) {
      weeklyOff.putIfAbsent(h.branchId, () => {}).add(h.weekday!);
    }
    return _HrAttendanceData(
      employees: {for (final p in profiles) p.id!: p},
      shifts: shifts,
      assignments: assignments,
      holidays: holidays,
      records: records,
      leaves: leaves,
      weeklyOff: weeklyOff,
    );
  }

  WorkShift? _hraShift(_HrAttendanceData data, int employeeId, DateTime day) {
    for (final a in data.assignments[employeeId] ?? const <ShiftAssignment>[]) {
      if (a.covers(day)) return data.shifts[a.shiftId];
    }
    return null;
  }

  bool _hraWeeklyOff(_HrAttendanceData data, int employeeId, DateTime day) {
    final branch = data.employees[employeeId]?.branchId;
    return (data.weeklyOff[null]?.contains(day.weekday) ?? false) ||
        (branch != null &&
            (data.weeklyOff[branch]?.contains(day.weekday) ?? false));
  }

  bool _hraIsWorkingDay(_HrAttendanceData data, int employeeId, DateTime day) {
    if (data.holidays.containsKey(hrDateKey(day))) return false;
    final shift = _hraShift(data, employeeId, day);
    return !(shift?.isDayOff(day) ?? _hraWeeklyOff(data, employeeId, day));
  }

  DayAttendance _hraDay(
      _HrAttendanceData data, int employeeId, DateTime day, DateTime now) {
    final p = data.employees[employeeId];
    final hire = p?.hireDate == null ? null : hrDay(p!.hireDate!);
    final end = p?.status == EmployeeStatus.terminated
        ? (p?.terminationDate == null ? null : hrDay(p!.terminationDate!))
        : null;
    final employed = p != null &&
        (hire == null || !day.isBefore(hire)) &&
        !(p.status == EmployeeStatus.terminated &&
            (end == null || day.isAfter(end)));
    LeaveDayMark? leave;
    if (_hraIsWorkingDay(data, employeeId, day)) {
      for (final (from, to, mark) in data.leaves[employeeId] ??
          const <(DateTime, DateTime, LeaveDayMark)>[]) {
        if (!day.isBefore(hrDay(from)) && !day.isAfter(hrDay(to))) {
          leave = mark;
          break;
        }
      }
    }
    return computeDayAttendance(DayContext(
      day: day,
      now: now,
      shift: _hraShift(data, employeeId, day),
      record: data.records['$employeeId:${hrDateKey(day)}'],
      holidayName: data.holidays[hrDateKey(day)],
      leave: leave,
      weeklyOff: _hraWeeklyOff(data, employeeId, day),
      employed: employed,
    ));
  }

  /// يومُ العمل الذي تنتمي إليه بصمةٌ في [at]: ورديّةُ الأمس العابرةُ لمنتصف
  /// الليل تأخذ البصمةَ إن وقعت قبل منتصف المسافة بين نهايتها وبدايتها.
  DateTime _hraWorkDateOf(_HrAttendanceData data, int employeeId, DateTime at) {
    final day = hrDay(at);
    final yesterday = DateTime(day.year, day.month, day.day - 1);
    final prev = _hraShift(data, employeeId, yesterday);
    if (prev != null && prev.crossesMidnight) {
      final minute = at.hour * 60 + at.minute;
      final cut = (prev.endMinute + prev.startMinute) ~/ 2;
      if (minute < cut) return yesterday;
    }
    return day;
  }

  String _hraDescribe(AttendanceRecord r) {
    String t(DateTime? d) => d == null
        ? '—'
        : '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
    return [
      '${t(r.checkIn)} → ${t(r.checkOut)}',
      if (r.mark != null) r.mark!,
    ].join(' · ');
  }
}

/// `yyyy-MM-dd` — مفتاحُ يومٍ ثابتٌ في الخرائط والسجلّ.
String hrDateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A typed variable — v192 NULL integer columns must stay INTEGER on
/// PostgreSQL (an untyped NULL is rejected).
Variable<Object> _hraVar(String column, Object? v) => switch (v) {
      int() => Variable<int>(v),
      double() => Variable<double>(v),
      bool() => Variable<int>(v ? 1 : 0),
      String() => Variable<String>(v),
      _ when _kHraIntColumns.contains(column) || column.endsWith('_id') =>
        const Variable<int>(null),
      _ when _kHraRealColumns.contains(column) => const Variable<double>(null),
      _ => const Variable<String>(null),
    };

const _kHraIntColumns = {
  'check_in',
  'check_out',
  'effective_to',
  'edited_by',
  'decided_by',
  'decided_at',
  'requested_by',
};

const _kHraRealColumns = {'entitlement_override'};

class _HrAttendanceData {
  const _HrAttendanceData({
    required this.employees,
    required this.shifts,
    required this.assignments,
    required this.holidays,
    required this.records,
    required this.leaves,
    required this.weeklyOff,
  });
  final Map<int, EmployeeProfile> employees;
  final Map<int, WorkShift> shifts;
  final Map<int, List<ShiftAssignment>> assignments;
  final Map<String, String> holidays;
  final Map<String, AttendanceRecord> records;
  final Map<int, List<(DateTime, DateTime, LeaveDayMark)>> leaves;
  final Map<int?, Set<int>> weeklyOff;
}

/// يومٌ مجمَّعٌ من بصمات الملفّ.
class ImportedAttendanceDay {
  const ImportedAttendanceDay({
    required this.employeeId,
    required this.employeeName,
    required this.workDate,
    this.checkIn,
    this.checkOut,
    this.punches = 0,
  });
  final int employeeId;
  final String employeeName;
  final DateTime workDate;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int punches;
}

/// معاينةُ الاستيراد: كلُّ سطرٍ بنتيجته، والأيّامُ التي ستُكتَب.
class AttendanceImportPreview {
  const AttendanceImportPreview({required this.rows, required this.days});
  final List<AttendancePunch> rows;
  final List<ImportedAttendanceDay> days;
  List<AttendancePunch> get errors => [for (final r in rows) if (r.error != null) r];
}

WorkShift _hrShiftOf(Map<String, dynamic> d) => WorkShift(
      id: (d['id'] as num).toInt(),
      name: d['name'] as String? ?? '',
      nameEn: d['name_en'] as String?,
      startMinute: _dmInt(d['start_minute']) ?? 0,
      endMinute: _dmInt(d['end_minute']) ?? 0,
      breakMinutes: _dmInt(d['break_minutes']) ?? 0,
      graceLateMinutes: _dmInt(d['grace_late_minutes']) ?? 0,
      daysOff: WorkShift.decodeDays(d['days_off'] as String?),
      overtimeAfterMinutes: _dmInt(d['overtime_after_minutes']) ?? 0,
      isActive: _dmBool(d['is_active']),
      employeeCount: _dmInt(d['employee_count']) ?? 0,
    );

ShiftAssignment _hrAssignmentOf(Map<String, dynamic> d) => ShiftAssignment(
      id: (d['id'] as num).toInt(),
      employeeId: (d['employee_id'] as num).toInt(),
      shiftId: (d['shift_id'] as num).toInt(),
      effectiveFrom: _dmDate(d['effective_from'])!,
      effectiveTo: _dmDate(d['effective_to']),
      notes: d['notes'] as String?,
      shiftName: d['shift_name'] as String?,
    );

AttendanceRecord _hrRecordOf(Map<String, dynamic> d) => AttendanceRecord(
      id: (d['id'] as num).toInt(),
      employeeId: (d['employee_id'] as num).toInt(),
      workDate: _dmDate(d['work_date'])!,
      checkIn: _dmDate(d['check_in']),
      checkOut: _dmDate(d['check_out']),
      mark: d['mark'] as String?,
      source: d['source'] as String? ?? AttendanceSource.manual,
      leaveRequestId: _dmInt(d['leave_request_id']),
      notes: d['notes'] as String?,
      editReason: d['edit_reason'] as String?,
      editedBy: _dmInt(d['edited_by']),
    );

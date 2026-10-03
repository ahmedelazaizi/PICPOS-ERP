part of '../database.dart';

/// J4 (الجزء ٣) — السلفُ والقروض (تُصرف بسند صرفٍ من دفتر السندات وقيدِ
/// مدين سلف الموظفين / دائن الخزنة، وتُستقطع أقساطُها في المسيّر، وتُسدَّد
/// مبكّراً بسند قبض)، والمكافآتُ والجزاءاتُ لمرّةٍ واحدة باعتماد.
extension HrAdvancesDao on AppDatabase {
  Future<List<EmployeeAdvance>> listEmployeeAdvances(
      {int? employeeId, String? status}) async {
    final where = <String>['a.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (employeeId != null) {
      where.add('a.employee_id = ?');
      vars.add(Variable<int>(employeeId));
    }
    if (status != null) {
      where.add('a.status = ?');
      vars.add(Variable<String>(status));
    }
    final rows = await customSelect(
      'SELECT a.*, e.name AS employee_name, st.voucher_number AS voucher_number, '
      '(SELECT COALESCE(SUM(r.amount), 0) FROM hr_advance_repayments r '
      ' WHERE r.advance_id = a.id AND r.deleted_at IS NULL) AS repaid '
      'FROM hr_employee_advances a JOIN employees e ON e.id = a.employee_id '
      'LEFT JOIN safe_transactions st ON st.id = a.safe_transaction_id '
      'WHERE ${where.join(' AND ')} ORDER BY a.issue_date DESC, a.id DESC',
      variables: vars,
    ).get();
    return [
      for (final r in rows)
        EmployeeAdvance(
          id: (r.data['id'] as num).toInt(),
          employeeId: _dmInt(r.data['employee_id'])!,
          employeeName: r.data['employee_name'] as String?,
          kind: r.data['kind'] as String? ?? AdvanceKind.advance,
          amount: _hrpD(r.data['amount']),
          issueDate: _dmDate(r.data['issue_date'])!,
          installments: _dmInt(r.data['installments']) ?? 1,
          installmentAmount: _hrpD(r.data['installment_amount']),
          startYear: _dmInt(r.data['start_year'])!,
          startMonth: _dmInt(r.data['start_month'])!,
          status: r.data['status'] as String? ?? AdvanceStatus.active,
          repaid: FinancialUtils.round(_hrpD(r.data['repaid'])),
          safeTransactionId: _dmInt(r.data['safe_transaction_id']),
          journalEntryId: _dmInt(r.data['journal_entry_id']),
          voucherNumber: r.data['voucher_number'] as String?,
          bookNumber: _dmInt(r.data['book_number']),
          notes: r.data['notes'] as String?,
          legacy: _dmInt(r.data['legacy_ref']) != null,
        ),
    ];
  }

  Future<List<AdvanceRepayment>> listAdvanceRepayments(int advanceId) async => [
        for (final r in await customSelect(
          'SELECT * FROM hr_advance_repayments WHERE advance_id = ? '
          'AND deleted_at IS NULL ORDER BY repay_date, id',
          variables: [Variable<int>(advanceId)],
        ).get())
          AdvanceRepayment(
            id: (r.data['id'] as num).toInt(),
            advanceId: advanceId,
            amount: _hrpD(r.data['amount']),
            date: _dmDate(r.data['repay_date'])!,
            source: r.data['source'] as String,
            payrollRunId: _dmInt(r.data['payroll_run_id']),
          ),
      ];

  /// رصيدُ سلف الموظف المفتوحة.
  Future<double> employeeAdvanceBalance(int employeeId) async =>
      FinancialUtils.round((await listEmployeeAdvances(
              employeeId: employeeId, status: AdvanceStatus.active))
          .fold<double>(0, (a, x) => a + x.balance));

  Future<void> _hrpSettleIfRepaid(int advanceId) async {
    final r = await customSelect(
      'SELECT a.amount, a.status, (SELECT COALESCE(SUM(r.amount), 0) '
      'FROM hr_advance_repayments r WHERE r.advance_id = a.id '
      'AND r.deleted_at IS NULL) AS repaid FROM hr_employee_advances a '
      'WHERE a.id = ?',
      variables: [Variable<int>(advanceId)],
    ).getSingleOrNull();
    if (r == null) return;
    final left = _hrpD(r.data['amount']) - _hrpD(r.data['repaid']);
    final status = left <= 0.005 ? AdvanceStatus.settled : AdvanceStatus.active;
    if (r.data['status'] != status &&
        r.data['status'] != AdvanceStatus.cancelled) {
      await _hrpUpdate('hr_employee_advances', advanceId, {'status': status});
    }
  }

  /// يصرف سلفةً أو قرضاً بسند صرفٍ من [safeId] (ورقةٌ من دفتر السندات
  /// [bookId] إن مُرِّر): مدين سلف الموظفين / دائن الخزنة.
  Future<int> createEmployeeAdvance({
    required int employeeId,
    required double amount,
    required int safeId,
    String kind = AdvanceKind.advance,
    DateTime? date,
    int installments = 1,
    double? installmentAmount,
    int? startYear,
    int? startMonth,
    int? bookId,
    int? bookNumber,
    String? notes,
    int? userId,
  }) async {
    await _hrpRequire(userId, PermissionCodes.hrAdvancesManage);
    if (amount <= 0) throw HrException('المبلغ يجب أن يكون أكبر من صفر.');
    if (installments < 1) throw HrException('عدد الأقساط غير صالح.');
    final issue = date ?? DateTime.now();
    final per = installmentAmount != null && installmentAmount > 0
        ? installmentAmount
        : amount / installments;
    final first = DateTime(issue.year, issue.month + 1);
    int? leaf = bookNumber;
    if (bookId != null) {
      leaf ??= await suggestNextVoucherBookNumber(bookId);
      if (leaf == null) throw HrException('الدفتر ممتلئ.');
      try {
        await validateVoucherBookLeaf(bookId, leaf);
      } on VoucherBookException catch (e) {
        throw HrException(e.key, e.params);
      }
    }
    final account = await _hrpAccount(
        await payrollAccounts(), PayAccountKey.advancesReceivable);
    final emp = await (select(employees)..where((e) => e.id.equals(employeeId)))
        .getSingleOrNull();
    if (emp == null) throw HrException('الموظف غير موجود.');
    return transaction(() async {
      final txn = await createPaymentVoucher(
        amount: FinancialUtils.round(amount),
        category: 'employee_advance',
        description:
            '${kind == AdvanceKind.loan ? 'قرض' : 'سلفة'} موظف — ${emp.name}',
        safeId: safeId,
        userId: userId,
        linkedAccountId: account.id,
      );
      await customUpdate(
        'UPDATE safe_transactions SET employee_id = ? WHERE id = ?',
        variables: [Variable<int>(employeeId), Variable<int>(txn)],
        updates: {safeTransactions},
      );
      if (bookId != null) {
        await assignVoucherBookLeaf(txnId: txn, bookId: bookId, number: leaf!);
      }
      final je = await customSelect(
        "SELECT id FROM journal_entries WHERE reference_type = 'payment_voucher' "
        'AND reference_id = ? ORDER BY id DESC LIMIT 1',
        variables: [Variable<int>(txn)],
      ).getSingleOrNull();
      final id = await _dmInsert('hr_employee_advances', {
        'employee_id': employeeId,
        'kind': kind,
        'amount': FinancialUtils.round(amount),
        'issue_date': _hrEpoch(issue),
        'installments': installments,
        'installment_amount': FinancialUtils.round(per),
        'start_year': startYear ?? first.year,
        'start_month': startMonth ?? first.month,
        'status': AdvanceStatus.active,
        'safe_transaction_id': txn,
        'journal_entry_id': je == null ? null : (je.data['id'] as num).toInt(),
        'book_id': bookId,
        'book_number': bookId == null ? null : leaf,
        'notes': _dmBlank(notes),
        'created_by': userId,
      });
      await logEmployeeEvent(employeeId, HrEventType.advance,
          to: '${FinancialUtils.round(amount)} · $installments',
          notes: _dmBlank(notes),
          actorUserId: userId);
      return id;
    });
  }

  /// تسديدٌ مبكّرٌ نقداً بسند قبضٍ في [safeId] (الرصيدُ كلُّه افتراضيّاً).
  Future<int> settleEmployeeAdvance(int advanceId,
      {required int safeId, double? amount, int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrAdvancesManage);
    final adv = (await listEmployeeAdvances())
        .where((a) => a.id == advanceId)
        .firstOrNull;
    if (adv == null || adv.status != AdvanceStatus.active) {
      throw HrException('السلفة غير مفتوحة.');
    }
    final value = FinancialUtils.round(amount ?? adv.balance);
    if (value <= 0 || value > adv.balance + 0.005) {
      throw HrException('مبلغ السداد يتجاوز الرصيد.');
    }
    final account = await _hrpAccount(
        await payrollAccounts(), PayAccountKey.advancesReceivable);
    return transaction(() async {
      final txn = await createReceiptVoucher(
        amount: value,
        category: 'employee_advance',
        description: 'تسديد سلفة — ${adv.employeeName ?? ''}',
        safeId: safeId,
        userId: userId,
        linkedAccountId: account.id,
      );
      await customUpdate(
        'UPDATE safe_transactions SET employee_id = ? WHERE id = ?',
        variables: [Variable<int>(adv.employeeId), Variable<int>(txn)],
        updates: {safeTransactions},
      );
      final id = await _dmInsert('hr_advance_repayments', {
        'advance_id': advanceId,
        'employee_id': adv.employeeId,
        'amount': value,
        'repay_date': _hrEpoch(DateTime.now()),
        'source': RepaymentSource.earlySettlement,
        'safe_transaction_id': txn,
        'created_by': userId,
      });
      await _hrpSettleIfRepaid(advanceId);
      return id;
    });
  }

  // ── المكافآتُ والجزاءات ──────────────────────────────────────────────────

  Future<List<PayrollAdjustment>> listPayrollAdjustments(
      {int? employeeId, int? year, int? month, String? status}) async {
    final where = <String>['a.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    void add(String sql, Object? v) {
      if (v == null) return;
      where.add(sql);
      vars.add(_dmVar(v));
    }

    add('a.employee_id = ?', employeeId);
    add('a.period_year = ?', year);
    add('a.period_month = ?', month);
    add('a.status = ?', status);
    final rows = await customSelect(
      'SELECT a.*, e.name AS employee_name FROM hr_payroll_adjustments a '
      'JOIN employees e ON e.id = a.employee_id WHERE ${where.join(' AND ')} '
      'ORDER BY a.period_year DESC, a.period_month DESC, a.id DESC',
      variables: vars,
    ).get();
    return [
      for (final r in rows)
        PayrollAdjustment(
          id: (r.data['id'] as num).toInt(),
          employeeId: _dmInt(r.data['employee_id'])!,
          employeeName: r.data['employee_name'] as String?,
          kind: r.data['kind'] as String,
          amount: _hrpD(r.data['amount']),
          year: _dmInt(r.data['period_year'])!,
          month: _dmInt(r.data['period_month'])!,
          reason: r.data['reason'] as String? ?? '',
          status: r.data['status'] as String? ?? AdjustmentStatus.pending,
          payrollRunId: _dmInt(r.data['payroll_run_id']),
          decidedBy: _dmInt(r.data['decided_by']),
        ),
    ];
  }

  Future<int> createPayrollAdjustment(PayrollAdjustment a,
      {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    if (a.amount <= 0) throw HrException('المبلغ يجب أن يكون أكبر من صفر.');
    if (a.reason.trim().isEmpty) throw HrException('السبب مطلوب.');
    if (!AdjustmentKind.values.contains(a.kind)) {
      throw HrException('نوع التسوية غير صالح.');
    }
    return _dmInsert('hr_payroll_adjustments', {
      'employee_id': a.employeeId,
      'kind': a.kind,
      'amount': FinancialUtils.round(a.amount),
      'period_year': a.year,
      'period_month': a.month,
      'reason': a.reason.trim(),
      'status': AdjustmentStatus.pending,
      'created_by': userId,
    });
  }

  /// اعتمادٌ أو رفض (‏`hr_payroll_approve`)؛ المستهلَكُ في مسيّرٍ لا يتغيّر.
  Future<void> decidePayrollAdjustment(int id,
      {required bool approve, int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollApprove);
    final a = (await listPayrollAdjustments()).where((x) => x.id == id).firstOrNull;
    if (a == null) throw HrException('السجل غير موجود.');
    if (a.payrollRunId != null) {
      throw HrException('مستهلكة في مسير ولا تتغير.');
    }
    await _hrpUpdate('hr_payroll_adjustments', id, {
      'status': approve ? AdjustmentStatus.approved : AdjustmentStatus.rejected,
      'decided_by': userId,
      'decided_at': _hrEpoch(DateTime.now()),
    });
    await logEmployeeEvent(a.employeeId, HrEventType.payroll,
        to: '${a.kind == AdjustmentKind.bonus ? '+' : '−'}${a.amount} · '
            '${a.year}-${a.month.toString().padLeft(2, '0')}',
        notes: a.reason,
        actorUserId: userId);
  }

  Future<void> deletePayrollAdjustment(int id, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollEdit);
    final a = (await listPayrollAdjustments()).where((x) => x.id == id).firstOrNull;
    if (a == null) return;
    if (a.payrollRunId != null) {
      throw HrException('مستهلكة في مسير ولا تتغير.');
    }
    await _hrpSoftDelete('hr_payroll_adjustments', 'id = ?', [id]);
  }
}

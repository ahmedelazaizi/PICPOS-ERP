part of '../database.dart';

/// J4 (الجزء ٣) — اعتمادُ المسيّر وترحيلُه بقيدٍ واحدٍ متوازن، وصرفُه بسندات
/// صرفٍ (لكلّ موظفٍ أو سندٍ واحدٍ للتحويل البنكيّ)، وعكسُه بقيدٍ عاكس.
///
/// القيد: مدينٌ — مصروفُ الرواتب (الأساسيُّ ناقصاً خصوماتِ الحضور والجزاءات)
/// والبدلاتُ والإضافيُّ والعمولاتُ وحصّةُ المنشأة في التأمينات، بمركز تكلفة
/// القسم إن ضُبط؛ دائنٌ — الرواتبُ المستحقّة (الصافي) والتأميناتُ المستحقّة
/// (الحصّتان) والضريبةُ المستحقّة وسلفُ الموظفين (الأقساط).
extension HrPayrollPostingDao on AppDatabase {
  /// مراجَع ⇒ معتمد (‏`hr_payroll_approve`).
  Future<void> approvePayrollRun(int runId, {int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollApprove);
    final run = await getPayrollRun(runId);
    if (run.legacy || run.status != PayrollRunStatus.reviewed) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    await _hrpUpdate('hr_payroll_runs', runId,
        {'status': PayrollRunStatus.approved, 'approved_by': userId});
  }

  /// سطورُ القيد المتوقَّعة لمسيّر (للمعاينة وللترحيل).
  Future<List<JournalLine>> payrollJournalLines(int runId) async {
    final run = await getPayrollRun(runId);
    final accs = await payrollAccounts();
    final costCenters = await departmentCostCenters();
    final ids = <String, int>{};
    Future<int> acc(String key) async =>
        ids[key] ??= (await _hrpAccount(accs, key)).id;
    final expense = <(int, int?), double>{};
    final credit = <int, double>{};
    for (final line in await listPayrollLines(runId: run.id)) {
      final cc = line.departmentId == null ? null : costCenters[line.departmentId];
      for (final i in line.items) {
        switch (i.kind) {
          case PayItemKind.earning:
            final k = (await acc(i.accountKey), cc);
            expense[k] = (expense[k] ?? 0) + i.amount;
          case PayItemKind.employer:
            final k = (await acc(PayAccountKey.employerInsuranceExpense), cc);
            expense[k] = (expense[k] ?? 0) + i.amount;
            final c = await acc(PayAccountKey.insurancePayable);
            credit[c] = (credit[c] ?? 0) + i.amount;
          default:
            if (i.accountKey == PayAccountKey.salariesExpense ||
                i.accountKey == PayAccountKey.allowancesExpense) {
              final k = (await acc(i.accountKey), cc);
              expense[k] = (expense[k] ?? 0) - i.amount;
            } else {
              final c = await acc(i.accountKey);
              credit[c] = (credit[c] ?? 0) + i.amount;
            }
        }
      }
      final payable = await acc(PayAccountKey.salariesPayable);
      credit[payable] = (credit[payable] ?? 0) + line.net;
    }
    const round = FinancialUtils.round;
    final desc = 'مسير رواتب ${run.period}';
    return [
      for (final e in expense.entries)
        if (round(e.value).abs() >= 0.001)
          JournalLine(
            accountId: e.key.$1,
            debit: e.value > 0 ? round(e.value) : 0,
            credit: e.value < 0 ? round(-e.value) : 0,
            costCenterId: e.key.$2,
            description: desc,
          ),
      for (final e in credit.entries)
        if (round(e.value).abs() >= 0.001)
          JournalLine(
            accountId: e.key,
            debit: e.value < 0 ? round(-e.value) : 0,
            credit: e.value > 0 ? round(e.value) : 0,
            description: desc,
          ),
    ];
  }

  /// معتمد ⇒ مرحَّل: قيدٌ واحدٌ متوازن، ويستهلك الأقساطَ والمكافآتِ والجزاءات.
  Future<int> postPayrollRun(int runId, {int? userId, DateTime? date}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollPost);
    final run = await getPayrollRun(runId);
    if (run.legacy || run.status != PayrollRunStatus.approved) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    return transaction(() async {
      final lines = await payrollJournalLines(runId);
      if (lines.isEmpty) throw HrException('المسير فارغ.');
      final gid = await customSelect(
        'SELECT global_id FROM hr_payroll_runs WHERE id = ?',
        variables: [Variable<int>(runId)],
      ).getSingle();
      final entryId = await createJournalEntry(
        description: 'مسير رواتب ${run.period}',
        date: date ?? run.to,
        lines: lines,
        referenceType: 'payroll_run',
        referenceId: runId,
        isAutoPosted: true,
        branchId: run.branchId,
        globalId: 'je-payroll-${gid.data['global_id']}',
        createdBy: userId,
      );
      final postedAt = date ?? DateTime.now();
      for (final line in await listPayrollLines(runId: runId)) {
        for (final i in line.items) {
          if (i.refType == 'advance' && i.refId != null) {
            await _dmInsert('hr_advance_repayments', {
              'advance_id': i.refId,
              'employee_id': line.employeeId,
              'amount': i.amount,
              'repay_date': _hrEpoch(run.to),
              'source': RepaymentSource.payroll,
              'payroll_run_id': runId,
              'payroll_line_id': line.id,
              'created_by': userId,
            });
            await _hrpSettleIfRepaid(i.refId!);
          } else if (i.refType == 'adjustment' && i.refId != null) {
            await _hrpUpdate('hr_payroll_adjustments', i.refId!,
                {'payroll_run_id': runId});
          }
        }
      }
      await _hrpUpdate('hr_payroll_runs', runId, {
        'status': PayrollRunStatus.posted,
        'journal_entry_id': entryId,
        'posted_by': userId,
        'posted_at': _hrEpoch(postedAt),
      });
      return entryId;
    });
  }

  /// يصرف سطورَ مسيّرٍ مرحَّل من [safeId]: سندُ صرفٍ لكلّ موظف، أو سندٌ واحدٌ
  /// بالإجمالي ([bulk] — تحويلٌ بنكيٌّ جماعيّ). الطرفُ المدين «الرواتب
  /// المستحقّة»، والدائنُ حسابُ الخزنة أو البنك. يعيد معرّفاتِ السندات.
  Future<List<int>> payPayrollRun(
    int runId, {
    required int safeId,
    bool bulk = false,
    List<int>? lineIds,
    int? bookId,
    int? bookNumber,
    int? userId,
  }) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollPost);
    final run = await getPayrollRun(runId);
    if (run.legacy || run.status != PayrollRunStatus.posted) {
      throw HrException('حالة المسير لا تسمح بهذا الإجراء.');
    }
    final lines = [
      for (final l in await listPayrollLines(runId: runId))
        if (!l.isPaid && l.net > 0 && (lineIds == null || lineIds.contains(l.id)))
          l,
    ];
    if (lines.isEmpty) throw HrException('لا سطور غير مصروفة.');
    if (bookId != null) {
      final needed = bulk ? 1 : lines.length;
      final first = bookNumber ?? await suggestNextVoucherBookNumber(bookId);
      if (first == null) throw HrException('الدفتر ممتلئ.');
      for (var n = first; n < first + needed; n++) {
        try {
          await validateVoucherBookLeaf(bookId, n);
        } on VoucherBookException catch (e) {
          throw HrException(e.key, e.params);
        }
      }
      bookNumber = first;
    }
    final payable = await _hrpAccount(
        await payrollAccounts(), PayAccountKey.salariesPayable);
    return transaction(() async {
      final vouchers = <int>[];
      Future<int> voucher(double amount, String description, int? employeeId,
          int leaf) async {
        final txn = await createPaymentVoucher(
          amount: FinancialUtils.round(amount),
          category: 'salaries',
          description: description,
          safeId: safeId,
          userId: userId,
          linkedAccountId: payable.id,
          operatingBranchId: run.branchId,
        );
        if (employeeId != null) {
          await customUpdate(
            'UPDATE safe_transactions SET employee_id = ? WHERE id = ?',
            variables: [Variable<int>(employeeId), Variable<int>(txn)],
            updates: {safeTransactions},
          );
        }
        if (bookId != null) {
          await assignVoucherBookLeaf(txnId: txn, bookId: bookId, number: leaf);
        }
        vouchers.add(txn);
        return txn;
      }

      final now = _hrEpoch(DateTime.now());
      if (bulk) {
        final total = lines.fold<double>(0, (a, l) => a + l.net);
        final txn = await voucher(
            total, 'صرف رواتب ${run.period} — تحويل جماعي', null, bookNumber ?? 0);
        for (final l in lines) {
          await _hrpUpdate('hr_payroll_lines', l.id, {
            'paid_amount': l.net,
            'payment_status': PayLineStatus.paid,
            'safe_transaction_id': txn,
            'paid_at': now,
          });
        }
      } else {
        var leaf = bookNumber ?? 0;
        for (final l in lines) {
          final txn = await voucher(l.net,
              'راتب ${l.employeeName} — ${run.period}', l.employeeId, leaf++);
          await _hrpUpdate('hr_payroll_lines', l.id, {
            'paid_amount': l.net,
            'payment_status': PayLineStatus.paid,
            'safe_transaction_id': txn,
            'paid_at': now,
          });
        }
      }
      await _hrpRefreshRunTotals(runId);
      final unpaid = await customSelect(
        'SELECT COUNT(*) AS n FROM hr_payroll_lines WHERE run_id = ? '
        "AND deleted_at IS NULL AND payment_status <> 'paid' AND net > 0",
        variables: [Variable<int>(runId)],
      ).getSingle();
      if ((_dmInt(unpaid.data['n']) ?? 0) == 0) {
        await _hrpUpdate(
            'hr_payroll_runs', runId, {'status': PayrollRunStatus.paid});
      }
      return vouchers;
    });
  }

  /// يعكس مسيّراً مرحَّلاً لم يُصرف منه شيء: قيدٌ عاكس، وتعود الأقساطُ رصيداً
  /// والمكافآتُ والجزاءاتُ معلّقةً للمسيّر التالي.
  Future<int> reversePayrollRun(int runId,
      {required String reason, int? userId}) async {
    await _hrpRequire(userId, PermissionCodes.hrPayrollPost);
    final run = await getPayrollRun(runId);
    if (run.legacy || run.status != PayrollRunStatus.posted) {
      throw HrException('لا يُعكس إلا مسير مرحّل لم يُصرف.');
    }
    if (reason.trim().isEmpty) throw HrException('سبب العكس مطلوب.');
    if (run.paid > 0) {
      throw HrException('لا يُعكس إلا مسير مرحّل لم يُصرف.');
    }
    return transaction(() async {
      final reversal = run.journalEntryId == null
          ? 0
          : await reverseJournalEntryById(
              entryId: run.journalEntryId!, descriptionPrefix: 'عكس');
      final advanceIds = {
        for (final r in await customSelect(
          'SELECT advance_id FROM hr_advance_repayments '
          'WHERE payroll_run_id = ? AND deleted_at IS NULL',
          variables: [Variable<int>(runId)],
        ).get())
          _dmInt(r.data['advance_id'])!,
      };
      await _hrpSoftDelete('hr_advance_repayments', 'payroll_run_id = ?', [runId]);
      for (final id in advanceIds) {
        await _hrpUpdate('hr_employee_advances', id,
            {'status': AdvanceStatus.active});
        await _hrpSettleIfRepaid(id);
      }
      await customUpdate(
        'UPDATE hr_payroll_adjustments SET payroll_run_id = NULL, '
        'last_modified_at = ? WHERE payroll_run_id = ?',
        variables: [Variable<int>(_dmNow()), Variable<int>(runId)],
      );
      await _hrpUpdate('hr_payroll_runs', runId, {
        'status': PayrollRunStatus.reversed,
        'reversal_journal_entry_id': reversal == 0 ? null : reversal,
        'reversed_by': userId,
        'reversed_at': _hrEpoch(DateTime.now()),
        'reversal_reason': reason.trim(),
      });
      return reversal;
    });
  }

  /// سجلُّ المسيّر (للتصدير): صفُّ رأسٍ ثمّ صفٌّ لكلّ موظف.
  Future<(List<String>, List<List<Object?>>)> payrollRegister(
      int runId) async {
    final lines = await listPayrollLines(runId: runId);
    double sum(PayrollLine l, bool Function(PayrollItem) f) =>
        FinancialUtils.round(
            l.items.where(f).fold<double>(0, (a, i) => a + i.amount));
    final headers = <String>[
      'الكود', 'الموظف', 'القسم', 'الأساسي', 'البدلات', 'الإضافي', 'العمولة',
      'المكافآت', 'الإجمالي', 'الغياب والتأخير', 'السلف', 'التأمينات',
      'الضريبة', 'خصومات أخرى', 'إجمالي الخصومات', 'الصافي', 'حصة المنشأة',
      'الحالة',
    ];
    const attendance = {
      PayItemCode.absence, PayItemCode.lateness, PayItemCode.unpaidLeave,
    };
    final rows = <List<Object?>>[
      for (final l in lines)
        [
          l.employeeCode ?? '',
          l.employeeName,
          l.departmentName ?? '',
          sum(l, (i) => i.code == PayItemCode.basic || i.code == PayItemCode.legacy),
          sum(l, (i) =>
              i.kind == PayItemKind.earning &&
              (i.code == PayItemCode.allowance ||
                  i.code == PayItemCode.component ||
                  i.code == PayItemCode.manual)),
          sum(l, (i) => i.code == PayItemCode.overtime),
          sum(l, (i) => i.code == PayItemCode.commission),
          sum(l, (i) => i.code == PayItemCode.bonus),
          l.gross,
          sum(l, (i) => attendance.contains(i.code)),
          sum(l, (i) => i.code == PayItemCode.advance),
          sum(l, (i) => i.code == PayItemCode.insuranceEmployee),
          sum(l, (i) => i.code == PayItemCode.tax),
          sum(l, (i) =>
              i.kind == PayItemKind.deduction &&
              !attendance.contains(i.code) &&
              i.code != PayItemCode.advance &&
              i.code != PayItemCode.insuranceEmployee &&
              i.code != PayItemCode.tax),
          l.deductions,
          l.net,
          l.employerCost,
          l.isPaid ? 'مصروف' : 'غير مصروف',
        ],
    ];
    return (headers, rows);
  }
}

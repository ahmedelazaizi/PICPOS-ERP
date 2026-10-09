import 'package:picpos_api_client/picpos_api_client.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/database.dart';
import '../../domain/models/return_draft.dart';

/// Signed projections of the same desktop reporting DAOs, never cloud math.
class AdminSnapshotBuilder {
  AdminSnapshotBuilder(this.db, this.signer);
  final AppDatabase db;
  final PayloadSigner signer;

  String _amount(num amount) => amount.toStringAsFixed(AppConstants.decimalPlaces);
  Future<Map<String, Object?>> _signed(String kind, String scope,
          DateTime at, Map<String, Object?> body) =>
      buildSignedSnapshot(signer, kind: kind, scope: scope, asOf: at, data: body);

  Future<List<Map<String, Object?>>> buildKpis(DateTime at) async {
    final local = at.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final month = DateTime(local.year, local.month);
    final end = DateTime(local.year, local.month, local.day, 23, 59, 59);
    final branches = await db.select(db.branches).get();
    final snapshots = <Map<String, Object?>>[];
    for (final branch in <int?>[null, ...branches.map((b) => b.id)]) {
      final scope = branch == null ? 'all' : SnapshotKinds.branchScope(branch);
      for (final period in [
        (SnapshotKinds.kpiToday, SnapshotKinds.profitToday, day),
        (SnapshotKinds.kpiMonth, SnapshotKinds.profitMonth, month),
      ]) {
        final income = await db.getIncomeStatement(period.$3, end, branchId: branch);
        final sales = await db.getSalesAnalytics(period.$3, end,
            allowedBranchIds: branch == null ? null : {branch});
        String figure(String field) => _amount(income[field] as num);
        snapshots.add(await _signed(period.$1, scope, at, {
          'netSales': figure('totalRevenue'),
          'invoiceCount': sales.invoiceCount,
          'returns': figure('salesReturns'),
          'grossProfit': figure('grossProfit'),
        }));
        snapshots.add(await _signed(period.$2, scope, at,
            {'netProfit': figure('netProfit')}));
      }
    }
    return snapshots;
  }

  /// A safe's GL account balance, not the independently cached safe balance.
  Future<Map<String, Object?>> cash(DateTime at, {int? branchId}) async {
    final scope = branchId == null ? 'all' : SnapshotKinds.branchScope(branchId);
    final balances = await db.getTrialBalance(DateTime(2000), at.toLocal(), branchId: branchId);
    final byAccount = {
      for (final row in balances)
        if (row['id'] is int)
          row['id'] as int: ((row['closingDebit'] as num) - (row['closingCredit'] as num)),
    };
    final safes = await db.select(db.safes).get();
    return _signed(SnapshotKinds.cash, scope, at, {
      'accounts': [
        for (final safe in safes)
          if (safe.isActive && safe.linkedAccountId != null &&
              (branchId == null || safe.branchId == branchId))
            {'name': safe.name, 'type': safe.safeType,
              'balance': _amount(byAccount[safe.linkedAccountId] ?? 0)},
      ],
    });
  }

  Future<Map<String, Object?>> parties(DateTime at, {int? branchId}) async {
    final scope = branchId == null ? 'all' : SnapshotKinds.branchScope(branchId);
    final branches = branchId == null ? null : {branchId};
    final ar = await db.getArAgingReport(asOfDate: at, allowedBranchIds: branches);
    final ap = await db.getArAgingReport(
        asOfDate: at, customersOnly: false, allowedBranchIds: branches);
    Map<String, Object?> summary(List<ArAgingRow> rows) => {
      'total': _amount(rows.fold<double>(0, (sum, row) => sum + row.totalBalance)),
      'aging': [
        _amount(rows.fold<double>(0, (sum, row) => sum + row.bucket0_30)),
        _amount(rows.fold<double>(0, (sum, row) => sum + row.bucket31_60)),
        _amount(rows.fold<double>(0, (sum, row) => sum + row.bucket61_90)),
        _amount(rows.fold<double>(0, (sum, row) => sum + row.bucket90Plus)),
      ],
      'top': [
        for (final row in (rows.toList()
          ..sort((a, b) => b.totalBalance.compareTo(a.totalBalance))).take(20))
          {'name': row.partyName, 'balance': _amount(row.totalBalance)},
      ],
    };
    return _signed(SnapshotKinds.parties, scope, at,
        {'receivables': summary(ar), 'payables': summary(ap)});
  }

  Future<Map<String, Object?>> branches(DateTime at) async {
    final from = DateTime(at.toLocal().year, at.toLocal().month);
    final branches = await db.select(db.branches).get();
    final rows = <Map<String, Object?>>[];
    for (final branch in branches) {
      final report = await db.getBranchSalesSummary(branch.id, from: from, to: at.toLocal());
      rows.add({'branchId': branch.id, 'name': branch.name,
        'sales': _amount(report.totalSales), 'invoiceCount': report.invoiceCount});
    }
    return _signed(SnapshotKinds.branches, 'all', at, {'rows': rows});
  }

  Future<Map<String, Object?>> reps(DateTime at) async {
    final local = at.toLocal();
    final rows = await db.repSalesSummary(from: DateTime(local.year, local.month), to: local);
    return _signed(SnapshotKinds.reps, 'all', at, {'rows': [
      for (final rep in rows)
        {'name': rep.repName, 'invoiceCount': rep.invoiceCount,
          'sales': _amount(rep.netSales), 'returns': _amount(rep.returns),
          'collections': _amount(rep.collections)},
    ]});
  }

  Future<List<Map<String, Object?>>> approvals(DateTime at) async {
    final sales = await db.listReturnDraftRecords(kind: ReturnDraftKind.sales);
    final purchases = await db.listReturnDraftRecords(kind: ReturnDraftKind.purchase);
    final leave = await db.listLeaveRequests(status: 'submitted');
    final payroll = await db.listPayrollRuns();
    final categories = <String, List<Map<String, Object?>>>{
      SnapshotKinds.approvalsSalesReturns: [
        for (final row in sales) {'ref': row.key, 'summary': row.number, 'amount': _amount(row.total)},
      ],
      SnapshotKinds.approvalsPurchaseReturns: [
        for (final row in purchases) {'ref': row.key, 'summary': row.number, 'amount': _amount(row.total)},
      ],
      SnapshotKinds.approvalsLeave: [
        for (final row in leave)
          {'ref': '${row.id}', 'summary': row.employeeName ?? '', 'amount': _amount(row.days)},
      ],
      SnapshotKinds.approvalsPayroll: [
        for (final row in payroll)
          if (row.status == 'reviewed' || row.status == 'approved')
            {'ref': '${row.id}', 'summary': '${row.year}-${row.month}', 'amount': _amount(row.net)},
      ],
      SnapshotKinds.approvalsJournals: const [],
    };
    return [
      for (final entry in categories.entries)
        await _signed(entry.key, 'all', at,
            {'count': entry.value.length, 'items': entry.value}),
    ];
  }

  Future<List<Map<String, Object?>>> buildAll(DateTime at) async {
    final snapshots = await buildKpis(at);
    final branches = await db.select(db.branches).get();
    for (final branch in <int?>[null, ...branches.map((b) => b.id)]) {
      snapshots.add(await cash(at, branchId: branch));
      snapshots.add(await parties(at, branchId: branch));
    }
    snapshots.add(await this.branches(at));
    snapshots.add(await reps(at));
    snapshots.addAll(await approvals(at));
    return snapshots;
  }
}

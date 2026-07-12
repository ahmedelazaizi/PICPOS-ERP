// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/uuid_v7.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/client_write_interceptor.dart';
import '../database/database.dart';
import '../database/sync_interceptor.dart';

class DriftAccountingRepository implements IAccountingRepository {
  final AppDatabase _db;

  DriftAccountingRepository(this._db);

  // --- Accounts (COA) ---
  @override
  Future<List<Account>> getAllAccounts() => _db.getAllAccounts();

  @override
  Stream<List<Account>> watchAllAccounts() => _db.watchAllAccounts();

  @override
  Future<Account?> getAccountById(int id) => _db.getAccountById(id);

  @override
  Future<Account?> getAccountByCode(String code) => _db.getAccountByCode(code);

  @override
  Future<int> createAccount({required String code, required String name, required String accountType, int? parentId}) async {
    if (SyncInterceptor.isClientMode) {
      final id = await ClientWriteInterceptor.createAccount(
        code: code,
        name: name,
        accountType: accountType,
        parentId: parentId,
      );
      return id ?? 0;
    }
    return _db.createAccount(code: code, name: name, accountType: accountType, parentId: parentId);
  }

  @override
  Future<int> updateAccount(int id, {String? name, String? code, bool? isActive, bool? isHiddenFromEntries}) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateAccount(id, {
        'name': ?name,
        'code': ?code,
        'isActive': ?isActive,
        'isHiddenFromEntries': ?isHiddenFromEntries,
      });
      // Drift's updateAccount returns the affected row count; the
      // interceptor doesn't have that figure, so fall back to 1 on
      // success (the next DeltaPull will reconcile).
      return 1;
    }
    return _db.updateAccount(id, name: name, code: code, isActive: isActive, isHiddenFromEntries: isHiddenFromEntries);
  }

  @override
  Future<void> deleteAccount(int id) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.deleteAccount(id);
      return;
    }
    await _db.deleteAccount(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getAccountLedger(int accountId, DateTime from, DateTime to, {int? costCenterId, int? branchId, Set<int>? allowedBranchIds}) =>
      _db.getAccountLedger(accountId, from, to, costCenterId: costCenterId, branchId: branchId, allowedBranchIds: allowedBranchIds);

  // --- Journal Entries ---
  @override
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
  }) async {
    // Feature 010 / Cluster B (Issue 2) — resolve the originating branch
    // when the caller did not supply one. The manual-JE dialog
    // (journal_entry_create_dialog.saveManualEntry) does NOT pass branchId,
    // so without this resolution the call cascades into the DAO which
    // falls back to `branchId ?? 1` (main branch). On a client device
    // bound to e.g. branch 3, the entry then appears on the server as
    // having been created by the main branch (the user's complaint:
    // "بيظهر ان العميل فرع كذا هو اللى عمله"). The threaded value also
    // flows into SyncInterceptor.submitJournalEntry's payload at
    // accounting_dao_writes.dart:336, so the server-side handler stores
    // the correct branch attribution too.
    int? resolvedBranchId = branchId;
    if (resolvedBranchId == null && SyncInterceptor.isClientMode) {
      resolvedBranchId = await _resolveClientBranchId();
    }
    return _db.createJournalEntry(
      description: description,
      date: date,
      lines: lines,
      referenceType: referenceType,
      referenceId: referenceId,
      isAutoPosted: isAutoPosted,
      costCenterId: costCenterId,
      branchId: resolvedBranchId,
    );
  }

  /// Read the branch this client/mirror is bound to, written by the setup
  /// wizard at `client_branch_id`. Returns null if missing (fresh install
  /// or not yet configured) so the DAO's `branchId ?? 1` fallback still
  /// applies — never throws, never blocks the JE write.
  Future<int?> _resolveClientBranchId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('client_branch_id');
    } catch (e) {
      debugPrint('[DriftAccountingRepository] '
          'client_branch_id lookup failed (non-fatal): $e');
      return null;
    }
  }

  @override
  Future<List<JournalEntryData>> getJournalEntries({DateTime? from, DateTime? to}) =>
      _db.getJournalEntries(from: from, to: to);

  @override
  Stream<List<JournalEntryData>> watchJournalEntries({DateTime? from, DateTime? to}) =>
      _db.watchJournalEntries(from: from, to: to);

  @override
  Stream<List<JournalEntryData>> watchJournalEntriesPaged({
    required int limit,
    required int offset,
    DateTime? from,
    DateTime? to,
  }) =>
      _db.watchJournalEntriesPaged(
        limit: limit,
        offset: offset,
        from: from,
        to: to,
      );

  @override
  Future<List<JournalEntryData>> getJournalEntriesByReference(String referenceType, int referenceId) =>
      ((_db.select(_db.journalEntries)
        ..where((e) => e.referenceType.equals(referenceType) & e.referenceId.equalsNullable(referenceId))
        ..orderBy([(e) => OrderingTerm.desc(e.entryDate)])
      ).get());

  @override
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(int entryId) =>
      _db.getJournalEntryLinesWithAccounts(entryId);

  // --- Fiscal Years ---
  @override
  Future<List<FiscalYearData>> getFiscalYears() => _db.getFiscalYears();

  @override
  Future<FiscalYearData?> getCurrentFiscalYear() async {
    final now = DateTime.now();
    // `.limit(1)` guards against overlapping / duplicate fiscal-year rows
    // (seen in the field when the seeder re-ran). Without it,
    // `getSingleOrNull` throws "Bad state: Too many elements" which then
    // propagates through every accounting validator call (payment voucher,
    // receipt voucher, expense, sale, ...) and blocks the operation.
    return (_db.select(_db.fiscalYears)
          ..where((y) => y.startDate.isSmallerOrEqualValue(now) & y.endDate.isBiggerOrEqualValue(now))
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date) async {
    return (_db.select(_db.fiscalYears)
          ..where((y) => y.startDate.isSmallerOrEqualValue(date) & y.endDate.isBiggerOrEqualValue(date))
          ..limit(1))
        .getSingleOrNull();
  }

  // --- Cost Centers & Activity Profiles ---
  @override
  Future<List<CostCenter>> getCostCenters() => _db.getCostCenters();

  @override
  Stream<List<CostCenter>> watchCostCenters() => _db.watchCostCenters();

  @override
  Future<int> createCostCenter({required String code, required String name, int? parentId}) async {
    if (SyncInterceptor.isClientMode) {
      final id = await ClientWriteInterceptor.createCostCenter(
        code: code,
        name: name,
        parentId: parentId,
      );
      return id ?? 0;
    }
    return _db.createCostCenter(code: code, name: name, parentId: parentId);
  }

  @override
  Future<void> updateCostCenter(int id, {String? code, String? name, int? parentId, bool? isActive}) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateCostCenter(id, {
        'code': ?code,
        'name': ?name,
        'parentId': ?parentId,
        'isActive': ?isActive,
      });
      return;
    }
    await _db.updateCostCenter(id, code: code, name: name, parentId: parentId, isActive: isActive);
  }

  @override
  Future<void> deactivateCostCenter(int id) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.deleteCostCenter(id);
      return;
    }
    await _db.deactivateCostCenter(id);
  }

  @override
  Future<Map<String, double>> getCostCenterBalance(int costCenterId) =>
      _db.getCostCenterBalance(costCenterId);

  @override
  Future<List<Map<String, dynamic>>> getCostCenterLedger(int costCenterId, DateTime from, DateTime to) =>
      _db.getCostCenterLedger(costCenterId, from, to);

  @override
  Future<List<ActivityProfile>> getActivityProfiles() => _db.getActivityProfiles();

  // --- Account Mapping ---
  @override
  Future<String> getMappedAccountCode(String purpose, String defaultCode, {int? costCenterId}) =>
      _db.getMappedAccountCode(purpose, defaultCode, costCenterId: costCenterId);

  @override
  Future<Account?> getAccountByPurpose(String purpose, {int? costCenterId}) =>
      _db.getAccountByPurpose(purpose, costCenterId: costCenterId);

  @override
  Future<Account?> getLeafAccountByPurpose(String purpose, {int? costCenterId}) =>
      _db.getLeafAccountByPurpose(purpose, costCenterId: costCenterId);

  @override
  Future<Account?> getLeafAccountById(int id) => _db.getLeafAccountById(id);

  @override
  Future<void> setAccountMapping(String purpose, int accountId, {int? costCenterId}) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.setAccountMapping(
        purpose: purpose,
        accountId: accountId,
        costCenterId: costCenterId,
      );
      return;
    }
    await _db.setAccountMapping(purpose, accountId, costCenterId: costCenterId);
  }

  @override
  Future<void> deleteAccountMapping(String purpose, {int? costCenterId}) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.deleteAccountMapping(
        purpose: purpose,
        costCenterId: costCenterId,
      );
      return;
    }
    if (costCenterId != null) {
      await (_db.delete(_db.accountMappings)
        ..where((m) => m.purpose.equals(purpose) & m.costCenterId.equals(costCenterId))).go();
      return;
    }
    await (_db.delete(_db.accountMappings)
      ..where((m) => m.purpose.equals(purpose) & m.costCenterId.isNull())).go();
  }

  @override
  Future<void> saveAccountMappings(Map<String, int?> selectedAccounts, {int? costCenterId}) async {
    await _db.transaction(() async {
      for (var entry in selectedAccounts.entries) {
        if (entry.value != null) {
          await _db.setAccountMapping(entry.key, entry.value!, costCenterId: costCenterId);
        } else {
          await deleteAccountMapping(entry.key, costCenterId: costCenterId);
        }
      }
    });
  }

  @override
  Future<List<AccountMapping>> getAccountMappings({int? costCenterId}) {
    if (costCenterId != null) {
      return (_db.select(_db.accountMappings)
        ..where((m) => m.costCenterId.equals(costCenterId))).get();
    }
    return (_db.select(_db.accountMappings)
      ..where((m) => m.costCenterId.isNull())).get();
  }

  @override
  Future<List<AccountMapping>> getAllAccountMappings() =>
      _db.select(_db.accountMappings).get();

  @override
  Future<void> deleteAccountMappingById(int mappingId) =>
      (_db.delete(_db.accountMappings)..where((m) => m.id.equals(mappingId))).go();

  @override
  Future<void> syncDefaultAccounts() => _db.syncDefaultAccounts();

  @override
  Future<void> syncAccountMappings() => _db.syncAccountMappings();

  @override
  Future<void> resetToDefaultMappings() => _db.resetToDefaultMappings();

  // --- Auto-Posting ---
  @override
  Future<int?> autoPostCashSale(SalesInvoiceData sale) => _db.autoPostCashSale(sale);

  @override
  Future<int?> autoPostCreditSale(SalesInvoiceData sale) => _db.autoPostCreditSale(sale);

  @override
  Future<int?> autoPostPurchase(PurchaseInvoiceData purchase) => _db.autoPostPurchase(purchase);

  @override
  Future<int?> autoPostReceipt(SafeTransactionData txn) => _db.autoPostReceipt(txn);

  @override
  Future<int?> autoPostPayment(SafeTransactionData txn) => _db.autoPostPayment(txn);

  @override
  Future<int?> autoPostSalesReturn({
    required SalesInvoiceData originalInvoice,
    required double returnAmount,
    required double cogsAmount,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    double vatAmount = 0,
    int? costCenterId,
  }) {
    return _db.autoPostSalesReturn(
      originalInvoice: originalInvoice,
      returnAmount: returnAmount,
      cogsAmount: cogsAmount,
      cashRefund: cashRefund,
      bankRefund: bankRefund,
      arRefund: arRefund,
      vatAmount: vatAmount,
      costCenterId: costCenterId,
    );
  }

  @override
  Future<int?> autoPostOperationalExpense({
    required int expenseId,
    required double amount,
    required String description,
    required String expenseAccountCode,
    int? costCenterId,
    int? branchId, // Added for branch isolation
    DateTime? date,
    String? paymentMethod, // F-12
  }) {
    return _db.autoPostOperationalExpense(
      expenseId: expenseId,
      amount: amount,
      description: description,
      expenseAccountCode: expenseAccountCode,
      costCenterId: costCenterId,
      branchId: branchId,
      date: date,
      paymentMethod: paymentMethod,
    );
  }

  @override
  Future<int> recordAndPostOperationalExpense({
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required String description,
    required String expenseAccountCode,
    String period = 'monthly',
    int? manufacturingOrderId,
    String? reference,
    String? notes,
    required int userId,
    int? branchId,
    int? costCenterId,
    String? paymentMethod,
    int? safeId,
  }) {
    return _db.recordAndPostOperationalExpense(
      categoryId: categoryId,
      amount: amount,
      expenseDate: expenseDate,
      description: description,
      expenseAccountCode: expenseAccountCode,
      period: period,
      manufacturingOrderId: manufacturingOrderId,
      reference: reference,
      notes: notes,
      userId: userId,
      branchId: branchId,
      costCenterId: costCenterId,
      paymentMethod: paymentMethod,
      safeId: safeId,
    );
  }

  @override
  Future<bool> hasAutoPostEntry(String referenceType, int referenceId) =>
      _db.hasAutoPostEntry(referenceType, referenceId);

  // --- Financial Reports ---
  @override
  Future<List<Map<String, dynamic>>> getTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId}) async {
    int? resolvedBranchId = branchId;
    if (regionId != null && branchId == null) {
      final regionBranches = await _db.getBranchesByRegion(regionId);
      final branchIds = regionBranches.map((b) => b.id).toList();
      if (branchIds.isEmpty) return [];
      if (branchIds.length == 1) {
        resolvedBranchId = branchIds.first;
      } else {
        final results = await Future.wait(
          branchIds.map((bid) => _db.getTrialBalance(from, to, costCenterId: costCenterId, branchId: bid)),
        );
        // Merge trial balances across branches
        final merged = <String, Map<String, dynamic>>{};
        for (final branchData in results) {
          for (final row in branchData) {
            final code = row['code'] as String? ?? '';
            if (merged.containsKey(code)) {
              final m = merged[code]!;
              m['openingDebit'] = (m['openingDebit'] as double) + (row['openingDebit'] as double? ?? 0.0);
              m['openingCredit'] = (m['openingCredit'] as double) + (row['openingCredit'] as double? ?? 0.0);
              m['movementDebit'] = (m['movementDebit'] as double) + (row['movementDebit'] as double? ?? 0.0);
              m['movementCredit'] = (m['movementCredit'] as double) + (row['movementCredit'] as double? ?? 0.0);
              m['closingDebit'] = (m['closingDebit'] as double) + (row['closingDebit'] as double? ?? 0.0);
              m['closingCredit'] = (m['closingCredit'] as double) + (row['closingCredit'] as double? ?? 0.0);
            } else {
              merged[code] = Map<String, dynamic>.from(row);
            }
          }
        }
        return merged.values.toList();
      }
    }
    return _db.getTrialBalance(from, to, costCenterId: costCenterId, branchId: resolvedBranchId);
  }

  @override
  Future<Map<String, dynamic>> getIncomeStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId}) async {
    int? resolvedBranchId = branchId;
    if (regionId != null && branchId == null) {
      final regionBranches = await _db.getBranchesByRegion(regionId);
      final branchIds = regionBranches.map((b) => b.id).toList();
      if (branchIds.isEmpty) return {'totalRevenue': 0.0, 'totalExpenses': 0.0, 'netProfit': 0.0, 'totalCOGS': 0.0, 'grossProfit': 0.0, 'operatingProfit': 0.0, 'totalDepreciation': 0.0, 'revenueDetails': <Map<String, dynamic>>[], 'expenseDetails': <Map<String, dynamic>>[], 'cogsDetails': <Map<String, dynamic>>[], 'depreciationDetails': <Map<String, dynamic>>[]};
      if (branchIds.length == 1) resolvedBranchId = branchIds.first;
      else {
        final results = await Future.wait(
          branchIds.map((bid) => _db.getIncomeStatement(from, to, costCenterId: costCenterId, branchId: bid)),
        );
        // Merge income statements across branches
        double totalRevenue = 0, totalExpenses = 0, totalCOGS = 0, grossProfit = 0, operatingProfit = 0, totalDepreciation = 0, netProfit = 0;
        final revenueMap = <String, Map<String, dynamic>>{};
        final expenseMap = <String, Map<String, dynamic>>{};
        final cogsMap = <String, Map<String, dynamic>>{};
        final depreciationMap = <String, Map<String, dynamic>>{};
        for (final data in results) {
          totalRevenue += (data['totalRevenue'] as double? ?? 0);
          totalExpenses += (data['totalExpenses'] as double? ?? 0);
          totalCOGS += (data['totalCOGS'] as double? ?? 0);
          grossProfit += (data['grossProfit'] as double? ?? 0);
          operatingProfit += (data['operatingProfit'] as double? ?? 0);
          totalDepreciation += (data['totalDepreciation'] as double? ?? 0);
          netProfit += (data['netProfit'] as double? ?? 0);
          for (final list in [['revenueDetails', revenueMap], ['expenseDetails', expenseMap], ['cogsDetails', cogsMap], ['depreciationDetails', depreciationMap]]) {
            final key = list[0] as String;
            final map = list[1] as Map<String, Map<String, dynamic>>;
            final details = data[key] as List?;
            if (details == null) continue;
            for (final d in details) {
              final name = d['name'] as String? ?? '';
              if (map.containsKey(name)) {
                map[name]!['amount'] = (map[name]!['amount'] as double) + (d['amount'] as double? ?? 0.0);
              } else {
                map[name] = Map<String, dynamic>.from(d as Map);
              }
            }
          }
        }
        return {
          'totalRevenue': totalRevenue, 'totalExpenses': totalExpenses, 'totalCOGS': totalCOGS,
          'grossProfit': grossProfit, 'operatingProfit': operatingProfit, 'totalDepreciation': totalDepreciation, 'netProfit': netProfit,
          'revenueDetails': revenueMap.values.toList(), 'expenseDetails': expenseMap.values.toList(),
          'cogsDetails': cogsMap.values.toList(), 'depreciationDetails': depreciationMap.values.toList(),
        };
      }
    }
    return _db.getIncomeStatement(from, to, costCenterId: costCenterId, branchId: resolvedBranchId);
  }

  @override
  Future<Map<String, dynamic>> getBalanceSheet(DateTime atDate, {int? costCenterId, int? branchId, int? regionId}) async {
    int? resolvedBranchId = branchId;
    if (regionId != null && branchId == null) {
      final regionBranches = await _db.getBranchesByRegion(regionId);
      final branchIds = regionBranches.map((b) => b.id).toList();
      if (branchIds.isEmpty) return {'totalAssets': 0.0, 'totalLiabilities': 0.0, 'totalEquity': 0.0, 'isBalanced': true, 'assetDetails': <Map<String, dynamic>>[], 'liabilityDetails': <Map<String, dynamic>>[], 'equityDetails': <Map<String, dynamic>>[]};
      if (branchIds.length == 1) resolvedBranchId = branchIds.first;
      else {
        final results = await Future.wait(
          branchIds.map((bid) => _db.getBalanceSheet(atDate, costCenterId: costCenterId, branchId: bid)),
        );
        double totalAssets = 0, totalLiabilities = 0, totalEquity = 0;
        final assetMap = <String, Map<String, dynamic>>{};
        final liabilityMap = <String, Map<String, dynamic>>{};
        final equityMap = <String, Map<String, dynamic>>{};
        for (final data in results) {
          totalAssets += (data['totalAssets'] as double? ?? 0);
          totalLiabilities += (data['totalLiabilities'] as double? ?? 0);
          totalEquity += (data['totalEquity'] as double? ?? 0);
          for (final list in [['assetDetails', assetMap], ['liabilityDetails', liabilityMap], ['equityDetails', equityMap]]) {
            final key = list[0] as String;
            final map = list[1] as Map<String, Map<String, dynamic>>;
            final details = data[key] as List?;
            if (details == null) continue;
            for (final d in details) {
              final name = d['name'] as String? ?? '';
              if (map.containsKey(name)) {
                map[name]!['balance'] = (map[name]!['balance'] as double) + (d['balance'] as double? ?? 0.0);
              } else {
                map[name] = Map<String, dynamic>.from(d as Map);
              }
            }
          }
        }
        return {
          'totalAssets': totalAssets, 'totalLiabilities': totalLiabilities, 'totalEquity': totalEquity,
          'isBalanced': (totalAssets - (totalLiabilities + totalEquity)).abs() < 0.01,
          'assetDetails': assetMap.values.toList(), 'liabilityDetails': liabilityMap.values.toList(), 'equityDetails': equityMap.values.toList(),
        };
      }
    }
    return _db.getBalanceSheet(atDate, costCenterId: costCenterId, branchId: resolvedBranchId);
  }

  @override
  Future<Map<String, dynamic>> getCashFlowStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    int? resolvedBranchId = branchId;
    List<int>? resolvedBranchIds;
    if (regionId != null && branchId == null) {
      final regionBranches = await _db.getBranchesByRegion(regionId);
      final branchIds = regionBranches.map((b) => b.id).toList();
      if (branchIds.isEmpty) return {'openingBalance': 0.0, 'netChange': 0.0, 'closingBalance': 0.0, 'operating': {'salesCash': 0.0, 'receiptsFromCustomers': 0.0, 'purchasesCash': 0.0, 'paymentsToSuppliers': 0.0, 'salaries': 0.0, 'expenses': 0.0, 'net': 0.0}, 'investing': {'assetPurchases': 0.0, 'assetDisposals': 0.0, 'net': 0.0}, 'financing': {'checksCollected': 0.0, 'checksIssued': 0.0, 'net': 0.0}};
      if (branchIds.length == 1) {
        resolvedBranchId = branchIds.first;
      } else {
        // D-03: do NOT loop `getCashFlowStatement(branchId: bid)` per branch and
        // sum — every per-branch call re-includes the `branch_id IS NULL`
        // (global/head-office) rows, so an N-branch region counted each global
        // cash line N times. Issue ONE scoped query over the whole branch set
        // (branch_id IN (..) OR branch_id IS NULL) so NULL rows are counted once
        // — matching the trial/income/balance path in reporting_repository_impl.
        resolvedBranchIds = branchIds;
      }
    }
    return _db.getCashFlowStatement(from, to, costCenterId: costCenterId, branchId: resolvedBranchId, branchIds: resolvedBranchIds, allowedBranchIds: allowedBranchIds);
  }

  @override
  Future<Map<String, dynamic>> getHierarchicalTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, Set<int>? allowedBranchIds}) =>
      _db.getHierarchicalTrialBalance(from, to, costCenterId: costCenterId, branchId: branchId, allowedBranchIds: allowedBranchIds);

  @override
  Future<List<Map<String, dynamic>>> getAgedPayables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) =>
      _db.getAgedPayables(asOfDate, costCenterId: costCenterId, branchId: branchId, regionId: regionId, allowedBranchIds: allowedBranchIds);

  @override
  Future<List<Map<String, dynamic>>> getAgedReceivables(DateTime asOfDate, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) =>
      _db.getAgedReceivables(asOfDate, costCenterId: costCenterId, branchId: branchId, regionId: regionId, allowedBranchIds: allowedBranchIds);

  @override
  Future<Map<String, dynamic>> getTaxReport(DateTime from, DateTime to, {Set<int>? allowedBranchIds}) =>
      _db.getTaxReport(from, to, allowedBranchIds: allowedBranchIds);

  @override
  Future<List<Map<String, dynamic>>> getPostingReconciliation(DateTime from, DateTime to, {int? branchId, Set<int>? allowedBranchIds}) =>
      _db.getPostingReconciliation(from, to, branchId: branchId, allowedBranchIds: allowedBranchIds);

  @override
  Future<void> approveJournalEntry(int entryId, int approverId) =>
      _db.approveJournalEntry(entryId, approverId);

  @override
  Future<void> reverseReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
  }) =>
      _db.reverseReturnAccountingEntry(
        invoiceId: invoiceId,
        invNumber: invNumber,
      );

  @override
  Future<void> reverseTransaction({
    required String referenceType,
    required int referenceId,
    required String descriptionPrefix,
    required String newReferenceType,
  }) =>
      _db.reverseTransaction(
        referenceType: referenceType,
        referenceId: referenceId,
        descriptionPrefix: descriptionPrefix,
        newReferenceType: newReferenceType,
      );

  @override
  Future<int> reverseJournalEntryById({
    required int entryId,
    String? descriptionPrefix,
  }) =>
      _db.reverseJournalEntryById(
        entryId: entryId,
        descriptionPrefix: descriptionPrefix,
      );

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => _db.transaction(action);

  @override
  Future<void> updateEntityStatus(String table, int id, String status, {String column = 'status'}) async {
    final query = 'UPDATE $table SET $column = ? WHERE id = ?';
    await _db.customStatement(query, [status, id]);
  }

  @override
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates() {
    return _db.watchActiveTemplates();
  }

  @override
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int templateId) {
    return _db.getTemplateLinesWithAccounts(templateId);
  }

  // --- Deferred Schedules ---
  @override
  Future<int> processDueRecognitions() => _db.processDueRecognitions();

  @override
  Future<List<dynamic>> getActiveSchedules() => _db.getActiveSchedules();

  // --- Exchange Rates ---
  @override
  Future<List<dynamic>> getActiveCurrencies() => _db.getActiveCurrencies();

  @override
  Future<void> recordExchangeRate({required int currencyId, required double rate}) =>
      _db.recordExchangeRate(currencyId: currencyId, rate: rate);

  // --- Fiscal Years (Batch 3) ---
  @override
  Stream<List<FiscalYearData>> watchFiscalYears() =>
      _db.select(_db.fiscalYears).watch();

  @override
  Future<int> createFiscalYear({required String name, required DateTime startDate, required DateTime endDate}) async {
    return _db.into(_db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: name,
        startDate: startDate,
        endDate: endDate,
        // Spec 136 ISS-2 — deterministic gid from the natural key so server +
        // client converge on the sync Tier-1 globalId match.
        globalId: Value(UuidV7.deriveFiscalYearGlobalId(
            name: name, startDate: startDate, endDate: endDate)),
      ),
    );
  }

  @override
  Future<void> closeFiscalYear(int yearId, int userId) async {
    await _db.closeFiscalYear(yearId, userId);
  }

  @override
  Future<Map<String, double>> getYearSummary(int yearId) => _db.getYearSummary(yearId);

  @override
  Stream<List<AccountingPeriodData>> watchAccountingPeriods(int yearId) =>
      (_db.select(_db.accountingPeriods)..where((p) => p.fiscalYearId.equals(yearId))).watch();

  @override
  Future<void> generatePeriodsForYear(int yearId, DateTime startDate, DateTime endDate) =>
      _db.generatePeriodsForYear(yearId, startDate, endDate);

  @override
  Future<void> closeAccountingPeriod(int periodId, int userId) =>
      _db.closeAccountingPeriod(periodId, userId);

  @override
  Future<void> reopenAccountingPeriod(int periodId) => _db.reopenAccountingPeriod(periodId);

  // --- Cost Centers (active filter) ---
  @override
  Future<List<CostCenter>> getActiveCostCenters() =>
      _db.getActiveCostCenters();

  // --- Journal Templates (full CRUD) ---
  @override
  Stream<List<JournalEntryTemplateData>> watchAllTemplates() =>
      _db.watchAllTemplates();

  @override
  Future<void> deleteJournalTemplate(int templateId) =>
      _db.deleteJournalEntryTemplate(templateId);

  @override
  Future<int> createJournalTemplate({required String name, String? description, required List<Map<String, dynamic>> lines}) {
    // Convert Map lines to JournalEntryTemplateLine objects
    final templateLines = lines.map((l) => JournalEntryTemplateLine(
      id: 0, templateId: 0,
      accountId: l['accountId'] as int,
      debit: (l['debit'] as num?)?.toDouble() ?? 0,
      credit: (l['credit'] as num?)?.toDouble() ?? 0,
      description: l['description'] as String?,
      costCenterId: l['costCenterId'] as int?,
    )).toList();
    return _db.createTemplateWithLines(name: name, description: description, lines: templateLines);
  }

  @override
  Future<void> updateJournalTemplate(int id, {required String name, String? description, required List<Map<String, dynamic>> lines}) {
    final templateLines = lines.map((l) => JournalEntryTemplateLine(
      id: 0, templateId: id,
      accountId: l['accountId'] as int,
      debit: (l['debit'] as num?)?.toDouble() ?? 0,
      credit: (l['credit'] as num?)?.toDouble() ?? 0,
      description: l['description'] as String?,
      costCenterId: l['costCenterId'] as int?,
    )).toList();
    return _db.updateTemplateWithLines(templateId: id, name: name, description: description, lines: templateLines);
  }

  @override
  Future<double> getCalculatedAccountBalance(int accountId) async {
    final result = await _db.customSelect(
      'SELECT COALESCE(SUM(debit - credit), 0) as calculated_balance '
      'FROM journal_entry_lines l '
      'JOIN journal_entries e ON l.entry_id = e.id '
      'WHERE l.account_id = ? AND e.is_posted = 1',
      variables: [Variable(accountId)],
      readsFrom: {_db.journalEntryLines, _db.journalEntries},
    ).getSingle();

    return (result.data['calculated_balance'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<void> updateAccountBalance(int accountId, double balance) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(balance: Value(balance)),
    );
  }

  @override
  Future<List<BankReconciliationData>> getReconciliationSessions() {
    return (_db.select(_db.bankReconciliations)
          ..orderBy([
            (r) => OrderingTerm.desc(r.createdAt),
          ]))
        .get();
  }

  @override
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) =>
      _db.createReconciliation(
        bankAccountId: bankAccountId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        statementBalance: statementBalance,
        userId: userId,
      );

  @override
  Future<void> completeReconciliation(int reconciliationId) =>
      _db.completeReconciliation(reconciliationId);

  @override
  Future<List<Map<String, dynamic>>> runComplianceAudit() =>
      _db.runComplianceAudit();

  @override
  Future<List<dynamic>> getActiveWorkflows() => _db.getActiveWorkflows();

  @override
  Future<void> seedDefaultSodConflicts() => _db.seedDefaultSodConflicts();

  @override
  Future<List<SodConflictData>> getActiveSodConflicts() =>
      _db.getActiveSodConflicts();

  @override
  Future<List<SodViolationData>> getSodViolationReport({DateTime? from, DateTime? to}) =>
      _db.getSodViolationReport(from: from, to: to);

  @override
  Future<List<Account>> getActiveAccounts() =>
      (_db.select(_db.accounts)..where((a) => a.isActive.equals(true))).get();

  @override
  Future<int> remediateHistoricalCostCenters() => _db.remediateHistoricalCostCenters();
}
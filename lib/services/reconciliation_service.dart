// ═══════════════════════════════════════════════════════════════════════════
// RECONCILIATION SERVICE — Balance Integrity Verification
// ═══════════════════════════════════════════════════════════════════════════
//
// This service compares cached balances (stored directly on entity tables)
// against the calculated truth (sum of movements/entries).
//
// PIR Report Items: F1, F2, F3, I1
// - Accounts.balance vs SUM(JournalEntryLines)
// - Parties.balance vs invoice/payment movements
// - Safes.balance vs SUM(SafeTransactions)
// - Product.currentStock vs SUM(StockMovements)

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../data/database/database_barrel.dart';
import '../domain/repositories/accounting_repository.dart';
import '../domain/repositories/parties_repository.dart';
import '../domain/repositories/i_products_repository.dart';
import '../core/logging/diagnostic_logger.dart';

/// Represents a discrepancy between cached and calculated balance
class BalanceDiscrepancy {
  final int entityId;
  final String entityName;
  final String entityType; // 'account', 'party', 'safe', 'product'
  final double cachedValue;
  final double calculatedValue;
  final double difference;

  const BalanceDiscrepancy({
    required this.entityId,
    required this.entityName,
    required this.entityType,
    required this.cachedValue,
    required this.calculatedValue,
    required this.difference,
  });

  bool get hasDiscrepancy => difference.abs() > 0.01;

  @override
  String toString() =>
      '$entityType[$entityId] "$entityName": cached=$cachedValue, calculated=$calculatedValue, diff=$difference';
}

/// Summary of a reconciliation run
class ReconciliationReport {
  final String entityType;
  final int totalChecked;
  final int discrepanciesFound;
  final int fixed;
  final List<BalanceDiscrepancy> discrepancies;
  final DateTime timestamp;

  ReconciliationReport({
    required this.entityType,
    required this.totalChecked,
    required this.discrepanciesFound,
    required this.fixed,
    required this.discrepancies,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Service for verifying and correcting cached balance integrity
class ReconciliationService {
  final IAccountingRepository _accountingRepo;
  final IPartiesRepository _partiesRepo;
  final ITreasuryRepository _treasuryRepo;
  final IProductRepository _productRepo;
  final AppDatabase _db;

  ReconciliationService({
    required IAccountingRepository accountingRepo,
    required IPartiesRepository partiesRepo,
    required ITreasuryRepository treasuryRepo,
    required IProductRepository productRepo,
    required AppDatabase db,
  })  : _accountingRepo = accountingRepo,
        _partiesRepo = partiesRepo,
        _treasuryRepo = treasuryRepo,
        _productRepo = productRepo,
        _db = db;

  // ═══════════════════════════════════════════════════════════════════════
  // 1. ACCOUNT BALANCE RECONCILIATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Compare Accounts.balance vs SUM(debit - credit) from JournalEntryLines
  Future<List<BalanceDiscrepancy>> reconcileAccounts() async {
    final discrepancies = <BalanceDiscrepancy>[];

    final allAccounts = await _accountingRepo.getAllAccounts();

    for (final account in allAccounts) {
      final calculatedBalance =
          await _accountingRepo.getCalculatedAccountBalance(account.id);
      final difference = account.balance - calculatedBalance;

      if (difference.abs() > 0.01) {
        discrepancies.add(BalanceDiscrepancy(
          entityId: account.id,
          entityName: account.name,
          entityType: 'account',
          cachedValue: account.balance,
          calculatedValue: calculatedBalance,
          difference: difference,
        ));
      }
    }

    return discrepancies;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. PARTY BALANCE RECONCILIATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Compare Parties.balance vs calculated from invoices and payments
  Future<List<BalanceDiscrepancy>> reconcileParties() async {
    final discrepancies = <BalanceDiscrepancy>[];

    final allParties = await _partiesRepo.getAllPartiesList();

    for (final party in allParties) {
      final calculatedBalance =
          await _partiesRepo.getCalculatedPartyBalance(party.id);
      final difference = party.balance - calculatedBalance;

      if (difference.abs() > 0.01) {
        discrepancies.add(BalanceDiscrepancy(
          entityId: party.id,
          entityName: party.name,
          entityType: 'party',
          cachedValue: party.balance,
          calculatedValue: calculatedBalance,
          difference: difference,
        ));
      }
    }

    return discrepancies;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. SAFE BALANCE RECONCILIATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Compare Safes.balance vs SUM of SafeTransactions
  Future<List<BalanceDiscrepancy>> reconcileSafes() async {
    final discrepancies = <BalanceDiscrepancy>[];

    final allSafes = await _treasuryRepo.getSafesList();

    for (final safe in allSafes) {
      final calculatedBalance =
          await _treasuryRepo.getCalculatedSafeBalance(safe.id);
      final difference = safe.balance - calculatedBalance;

      if (difference.abs() > 0.01) {
        discrepancies.add(BalanceDiscrepancy(
          entityId: safe.id,
          entityName: safe.name,
          entityType: 'safe',
          cachedValue: safe.balance,
          calculatedValue: calculatedBalance,
          difference: difference,
        ));
      }
    }

    return discrepancies;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. STOCK BALANCE RECONCILIATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Compare Product.currentStock vs SUM(quantity) from StockMovements
  Future<List<BalanceDiscrepancy>> reconcileStock() async {
    final discrepancies = <BalanceDiscrepancy>[];

    final products = await _productRepo.getInventoryProducts();

    for (final product in products) {
      final calculatedStock = await _productRepo.getCalculatedStock(product.id);
      final difference = product.currentStock - calculatedStock;

      if (difference.abs() > 0.01) {
        discrepancies.add(BalanceDiscrepancy(
          entityId: product.id,
          entityName: product.name,
          entityType: 'product',
          cachedValue: product.currentStock,
          calculatedValue: calculatedStock,
          difference: difference,
        ));
      }
    }

    return discrepancies;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. FIX DISCREPANCIES
  // ═══════════════════════════════════════════════════════════════════════

  /// Fix discrepancies by recalculating cached values from source-of-truth
  /// Returns the number of fixes applied.
  Future<int> fixDiscrepancies(List<BalanceDiscrepancy> discrepancies) async {
    int fixCount = 0;

    await _accountingRepo.runInTransaction(() async {
      for (final d in discrepancies) {
        if (!d.hasDiscrepancy) continue;

        switch (d.entityType) {
          case 'account':
            await _accountingRepo.updateAccountBalance(d.entityId, d.calculatedValue);
            fixCount++;
            break;

          // ── الأطراف: تُبلَّغ ولا تُصلَّح تلقائياً ──────────────────────────
          //
          // كان هنا `updatePartyBalance(d.entityId, d.calculatedValue)` —
          // **كتابةٌ مطلقةٌ بلا قيدٍ ولا أثرٍ تدقيقيّ**، ومصدرُها صيغةٌ تطرح
          // المقبوضَ مرّتين:
          //
          //   getCalculatedPartyBalance = (receivable − receipts) − (payable − payments)
          //
          // و`receivable` هي `SUM(total − paid)` — أي أنّ المقبوضَ **مطروحٌ
          // سلفاً** — ثمّ تطرحه `receipts` ثانيةً، لأنّ `_recordSalesReceipt`
          // يكتب صفَّ `safe_transactions` بـ`partyId = customerId` لنفس المبلغ.
          //
          // مقيس: عميلٌ مسمّى وبيعةٌ نقديّةٌ كاملةٌ ١٠٠٠ ⇒ الرصيدُ الصحيح صفر،
          // والصيغةُ تعطي **−١٠٠٠**، فضغطةُ الزرّ تكتب أنّنا **ندين** له بألف.
          // على متجرٍ بألفِ فاتورةٍ بمتوسّط ٤٠٠ تفتح ضغطةٌ واحدةٌ فجوةً قدرُها
          // ٤٠٠٬٠٠٠ في مطابقة الذمم — بلا سجلٍّ ولا رجعة.
          //
          // ونفسُ حجّة الخزائن أدناه حرفاً بحرف: رصيدُ طرفٍ ليس بياناتٍ تالفةً
          // تُعاد اشتقاقُها، بل نتيجةُ قيودٍ مرحَّلة. والكاشفُ الصحيحُ الموجودُ
          // سلفاً هو `PartyDao.getPartyBalanceMismatches()` الذي يقارن بالأستاذ
          // لا بصيغةٍ موازية — وهو ما يجب أن يحلّ محلَّ `reconcileParties`.
          case 'party':
            debugPrint(
                '[Reconcile] فرقُ طرف #${d.entityId}: مخزَّن=${d.cachedValue} '
                'محسوب=${d.calculatedValue} — يُبلَّغ ولا يُصلَّح تلقائياً '
                '(الصيغةُ تطرح المقبوضَ مرّتين — استعمل getPartyBalanceMismatches).');
            break;

          // ── الخزائن: تُبلَّغ ولا تُصلَّح تلقائياً ────────────────────────────
          //
          // كان هنا `updateSafeBalance(d.entityId, d.calculatedValue)`، وهو
          // **يخلق نقديةً من العدم**. سببان مستقلّان، وكلٌّ منهما وحدَه كافٍ:
          //
          // ١. الصيغةُ كانت تُسقط `withdrawal` — أي كلَّ سحبِ إقفالِ ورديةٍ
          //    وكلَّ إقفالٍ يوميّ. فدرجٌ صُفِّي بعد الإقفال يُقرأ «ناقصاً
          //    المبلغَ كلَّه»، والزرُّ يكتبه فيه. (‏الصيغةُ صُحِّحت في
          //    `TreasuryRepositoryImpl.getCalculatedSafeBalance`.)
          //
          // ٢. وحتى بالصيغة الصحيحة يبقى الإصلاحُ خاطئاً: **الرصيدُ
          //    الافتتاحيّ لا صفَّ حركةٍ له**. خزنةٌ زُرعت أو فُتحت برصيدٍ
          //    ≠ صفر تفترق عن مجموع حركاتها **شرعياً**، فالكتابةُ فوقها
          //    تمحو الافتتاحيّ.
          //
          // والفرقُ في خزنةٍ ليس بياناتٍ تالفةً تُعاد اشتقاقُها كرصيد حسابٍ
          // أو مخزونِ صنف — هو **إمّا** حركةٌ ناقصةٌ **وإمّا** عجزٌ نقديٌّ
          // حقيقيّ. كلاهما يُسوَّى بسندٍ يوقّعه إنسان، لا بضغطة زرّ.
          case 'safe':
            debugPrint(
                '[Reconcile] فرقُ خزنة #${d.entityId}: مخزَّن=${d.cachedValue} '
                'محسوب=${d.calculatedValue} — يُبلَّغ ولا يُصلَّح تلقائياً '
                '(سوِّه بسندِ إيداعٍ أو صرفٍ موثَّق).');
            break;

          case 'product':
            await _productRepo.updateProductStock(d.entityId, d.calculatedValue);
            fixCount++;
            break;
        }
      }
    });

    return fixCount;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. FULL RECONCILIATION REPORT
  // ═══════════════════════════════════════════════════════════════════════

  /// Run full reconciliation across all entity types
  Future<List<ReconciliationReport>> runFullReconciliation({
    bool autoFix = false,
  }) async {
    final reports = <ReconciliationReport>[];

    // 1. Accounts
    final accountDiscrepancies = await reconcileAccounts();
    int accountFixes = 0;
    if (autoFix && accountDiscrepancies.isNotEmpty) {
      accountFixes = await fixDiscrepancies(accountDiscrepancies);
    }
    reports.add(ReconciliationReport(
      entityType: 'الحسابات',
      totalChecked: (await _accountingRepo.getAllAccounts()).length,
      discrepanciesFound: accountDiscrepancies.length,
      fixed: accountFixes,
      discrepancies: accountDiscrepancies,
    ));

    // 2. Parties
    final partyDiscrepancies = await reconcileParties();
    int partyFixes = 0;
    if (autoFix && partyDiscrepancies.isNotEmpty) {
      partyFixes = await fixDiscrepancies(partyDiscrepancies);
    }
    reports.add(ReconciliationReport(
      entityType: 'الأطراف',
      totalChecked: (await _partiesRepo.getAllPartiesList()).length,
      discrepanciesFound: partyDiscrepancies.length,
      fixed: partyFixes,
      discrepancies: partyDiscrepancies,
    ));

    // 3. Safes
    final safeDiscrepancies = await reconcileSafes();
    int safeFixes = 0;
    if (autoFix && safeDiscrepancies.isNotEmpty) {
      safeFixes = await fixDiscrepancies(safeDiscrepancies);
    }
    reports.add(ReconciliationReport(
      entityType: 'الخزائن',
      totalChecked: (await _treasuryRepo.getSafesList()).length,
      discrepanciesFound: safeDiscrepancies.length,
      fixed: safeFixes,
      discrepancies: safeDiscrepancies,
    ));

    // 4. Stock
    final stockDiscrepancies = await reconcileStock();
    int stockFixes = 0;
    if (autoFix && stockDiscrepancies.isNotEmpty) {
      stockFixes = await fixDiscrepancies(stockDiscrepancies);
    }
    reports.add(ReconciliationReport(
      entityType: 'المخزون',
      totalChecked: (await _productRepo.getInventoryProducts()).length,
      discrepanciesFound: stockDiscrepancies.length,
      fixed: stockFixes,
      discrepancies: stockDiscrepancies,
    ));

    return reports;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. NEGATIVE BALANCE DETECTION (PIR I2)
  // ═══════════════════════════════════════════════════════════════════════

  /// Detect inventory balances that have gone negative.
  /// Returns list of products with negative stock per warehouse.
  Future<List<BalanceDiscrepancy>> detectNegativeBalances() async {
    final results = await _db.customSelect(
      'SELECT ib.product_id, ib.warehouse_id, ib.quantity, '
      'p.name as product_name, w.name as warehouse_name '
      'FROM inventory_balances ib '
      'JOIN products p ON ib.product_id = p.id '
      'JOIN warehouses w ON ib.warehouse_id = w.id '
      'WHERE ib.quantity < 0',
      readsFrom: {_db.inventoryBalances, _db.products, _db.warehouses},
    ).get();

    return results.map((r) {
      final productId = r.data['product_id'] as int;
      final productName = r.data['product_name'] as String? ?? '';
      final warehouseName = r.data['warehouse_name'] as String? ?? '';
      final qty = (r.data['quantity'] as num?)?.toDouble() ?? 0;

      return BalanceDiscrepancy(
        entityId: productId,
        entityName: '$productName @ $warehouseName',
        entityType: 'product',
        cachedValue: qty,
        calculatedValue: 0,
        difference: qty, // negative value
      );
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. AR RECONCILIATION SCHEDULED CHECK (PIR P2-02)
  // ═══════════════════════════════════════════════════════════════════════

  /// Runs the AR reconciliation check:
  ///   - SUM(parties.balance WHERE is_customer=1) vs GL Account 1121
  ///   - If diff > 0.01, logs an alert row to field_audit_logs
  ///
  /// Designed to be called on app startup or via a periodic trigger.
  /// Returns the [ArReconciliation] result (null when receivables account
  /// is not yet configured), and the diff alert message when applicable.
  Future<ArReconciliationCheckResult> scheduleArReconciliationCheck() async {
    final reconciliation = await _db.getArReconciliation();

    if (reconciliation == null) {
      return const ArReconciliationCheckResult(
        reconciliation: null,
        alertLogged: false,
        message: 'AR reconciliation skipped: receivables account not configured.',
      );
    }

    final bool hasDiff = !reconciliation.isBalanced; // diff.abs() >= 0.01

    if (hasDiff) {
      final diffStr = reconciliation.difference.toStringAsFixed(4);
      final cardStr = reconciliation.totalCardBalance.toStringAsFixed(4);
      final glStr = reconciliation.totalGlBalance.toStringAsFixed(4);
      final alertMessage =
          'AR RECONCILIATION ALERT: parties.balance=$cardStr vs '
          'GL ${reconciliation.receivablesAccountCode}=$glStr, diff=$diffStr';

      try {
        await _db.logFieldChange(
          entityType: 'ar_reconciliation',
          entityId: 0, // aggregate — no single entity ID
          fieldName: 'فرق تسوية الذمم',
          fieldKey: 'ar_reconciliation_diff',
          oldValue: glStr,
          newValue: cardStr,
          changedBy: 0, // system process
          changedByName: 'system:ar_reconciliation_check',
          changeReason: alertMessage,
          transactionId:
              'ar-recon-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (e) {
        debugPrint('[ArRecon] Failed to log alert to field_audit_logs: $e');
      }

      debugPrint('[ArRecon] $alertMessage');

      return ArReconciliationCheckResult(
        reconciliation: reconciliation,
        alertLogged: true,
        message: alertMessage,
      );
    }

    debugPrint('[ArRecon] AR reconciliation OK — diff=${reconciliation.difference.toStringAsFixed(4)}');

    return ArReconciliationCheckResult(
      reconciliation: reconciliation,
      alertLogged: false,
      message: 'AR reconciliation OK.',
    );
  }

  /// Spec 153 (م-2) — inventory perpetual value vs GL account 1136 check.
  /// READ-ONLY: posts nothing, changes no WAC semantics. Emits a diagnostic-log
  /// alert when |delta| >= 0.01 (isBalanced). Call on startup or via a manual
  /// trigger; the decision itself lives in the pure
  /// [InventoryGlReconciliationCheckResult.evaluate] factory.
  Future<InventoryGlReconciliationCheckResult>
      scheduleInventoryGlReconciliationCheck() async {
    final reconciliation = await _db.getInventoryGlReconciliation();
    final result =
        InventoryGlReconciliationCheckResult.evaluate(reconciliation);
    if (result.alertLogged) {
      try {
        await DiagnosticLogger.log('INVENTORY-GL-RECON', result.message);
      } catch (e) {
        debugPrint('[InvGlRecon] Failed to write alert to diagnostic log: $e');
      }
    }
    debugPrint('[InvGlRecon] ${result.message}');
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. STOCK TRANSFER SOURCE VALIDATION (PIR I3)
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate that source warehouse has sufficient stock for transfer.
  /// Returns null if OK, error message if insufficient.
  Future<String?> validateStockTransfer({
    required int productId,
    required int sourceWarehouseId,
    required double transferQty,
  }) async {
    final result = await _db.customSelect(
      'SELECT COALESCE(quantity, 0) as current_qty '
      'FROM inventory_balances '
      'WHERE product_id = ? AND warehouse_id = ?',
      variables: [Variable(productId), Variable(sourceWarehouseId)],
      readsFrom: {_db.inventoryBalances},
    ).getSingleOrNull();

    final currentQty =
        (result?.data['current_qty'] as num?)?.toDouble() ?? 0;

    if (currentQty < transferQty) {
      // Get product name for error message
      final product = await (_db.select(_db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      final productName = product?.name ?? 'صنف #$productId';

      return 'لا يوجد رصيد كافٍ لتحويل "$productName": '
          'المتاح ${currentQty.toStringAsFixed(AppConstants.decimalPlaces)}، '
          'المطلوب ${transferQty.toStringAsFixed(AppConstants.decimalPlaces)}';
    }

    return null; // OK
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AR RECONCILIATION CHECK RESULT (PIR P2-02)
// ═══════════════════════════════════════════════════════════════════════════

/// Result returned by [ReconciliationService.scheduleArReconciliationCheck].
class ArReconciliationCheckResult {
  /// The raw reconciliation data, or null when the receivables account
  /// is not yet configured in accounting mappings.
  final ArReconciliation? reconciliation;

  /// Whether an alert row was written to field_audit_logs.
  /// True only when diff.abs() >= 0.01.
  final bool alertLogged;

  /// Human-readable summary of the check outcome.
  final String message;

  const ArReconciliationCheckResult({
    required this.reconciliation,
    required this.alertLogged,
    required this.message,
  });

  /// Convenience getter: true when the AR sub-ledger is in balance with the GL.
  bool get isBalanced => reconciliation?.isBalanced ?? true;
}

// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY-vs-GL RECONCILIATION CHECK RESULT (Spec 153 م-2)
// ═══════════════════════════════════════════════════════════════════════════

/// Result of [ReconciliationService.scheduleInventoryGlReconciliationCheck].
class InventoryGlReconciliationCheckResult {
  /// Raw reconciliation data, or null when the inventory account is unmapped.
  final InventoryGlReconciliation? reconciliation;

  /// True when |delta| >= 0.01 — an alert was emitted to the diagnostic log.
  final bool alertLogged;

  /// Human-readable summary of the check outcome.
  final String message;

  const InventoryGlReconciliationCheckResult({
    required this.reconciliation,
    required this.alertLogged,
    required this.message,
  });

  /// True when the perpetual inventory value ties out to GL 1136.
  bool get isBalanced => reconciliation?.isBalanced ?? true;

  /// Pure decision: null → skipped; balanced → OK (no alert); drift → alert.
  /// Side-effect-free so it is unit-testable; the service does the actual
  /// diagnostic-log write for alert results.
  factory InventoryGlReconciliationCheckResult.evaluate(
      InventoryGlReconciliation? r) {
    if (r == null) {
      return const InventoryGlReconciliationCheckResult(
        reconciliation: null,
        alertLogged: false,
        message:
            'Inventory reconciliation skipped: inventory account not configured.',
      );
    }
    if (r.isBalanced) {
      return InventoryGlReconciliationCheckResult(
        reconciliation: r,
        alertLogged: false,
        message:
            'Inventory reconciliation OK — delta=${r.delta.toStringAsFixed(4)}.',
      );
    }
    return InventoryGlReconciliationCheckResult(
      reconciliation: r,
      alertLogged: true,
      message: 'INVENTORY-GL RECONCILIATION ALERT: '
          'perpetual=${r.reportValue.toStringAsFixed(4)} vs '
          'GL ${r.inventoryAccountCode}=${r.glBalance.toStringAsFixed(4)}, '
          'delta=${r.delta.toStringAsFixed(4)} '
          '(costBasis=${r.costBasisDivergence.toStringAsFixed(2)}, '
          'stockVsLedger=${r.stockVsLedgerDivergence.toStringAsFixed(2)}, '
          'zeroCost=${r.zeroCostItemCount})',
    );
  }
}

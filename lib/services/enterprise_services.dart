// ═══════════════════════════════════════════════════════════════════════════
// Batch: Remaining Phase 2 & Phase 3 Service Stubs
// F-05, F-06, F-07, F-09, I-02, B-02, B-03, B-04, U-02, U-05
// + Phase 3: E-01 through E-12, I-06, I-07, U-17, U-18, C-04
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/theme/app_colors.dart';

// ─── F-05: Depreciation Schedule Service ────────────────────────────────

/// Depreciation method
enum DepreciationMethod {
  straightLine,
  decliningBalance,
  sumOfYearsDigits;

  String get labelAr => switch (this) {
    DepreciationMethod.straightLine => 'القسط الثابت',
    DepreciationMethod.decliningBalance => 'القسط المتناقص',
    DepreciationMethod.sumOfYearsDigits => 'مجموع أرقام السنوات',
  };
}

class DepreciationEntry {
  final int year;
  final double openingValue;
  final double depreciationAmount;
  final double closingValue;
  final double accumulatedDepreciation;

  const DepreciationEntry({
    required this.year,
    required this.openingValue,
    required this.depreciationAmount,
    required this.closingValue,
    required this.accumulatedDepreciation,
  });
}

class DepreciationScheduleService {
  /// Generate depreciation schedule for an asset
  static List<DepreciationEntry> calculate({
    required double cost,
    required double salvageValue,
    required int usefulLifeYears,
    DepreciationMethod method = DepreciationMethod.straightLine,
  }) {
    final entries = <DepreciationEntry>[];
    final depreciableBase = cost - salvageValue;
    double accumulated = 0;
    double bookValue = cost;

    for (int y = 1; y <= usefulLifeYears; y++) {
      double depreciation;

      switch (method) {
        case DepreciationMethod.straightLine:
          depreciation = depreciableBase / usefulLifeYears;
        case DepreciationMethod.decliningBalance:
          final rate = 2.0 / usefulLifeYears;
          depreciation = bookValue * rate;
          if (bookValue - depreciation < salvageValue) {
            depreciation = bookValue - salvageValue;
          }
        case DepreciationMethod.sumOfYearsDigits:
          final sumDigits = usefulLifeYears * (usefulLifeYears + 1) / 2;
          depreciation = depreciableBase * (usefulLifeYears - y + 1) / sumDigits;
      }

      accumulated += depreciation;
      final closing = cost - accumulated;

      entries.add(DepreciationEntry(
        year: y,
        openingValue: bookValue,
        depreciationAmount: depreciation,
        closingValue: closing,
        accumulatedDepreciation: accumulated,
      ));

      bookValue = closing;
    }

    return entries;
  }
}

// ─── F-06: AR/AP Sub-Ledger Reconciliation ──────────────────────────────

class ReconciliationItem {
  final String accountCode;
  final String accountName;
  final double subledgerBalance;
  final double generalLedgerBalance;
  final double variance;

  const ReconciliationItem({
    required this.accountCode,
    required this.accountName,
    required this.subledgerBalance,
    required this.generalLedgerBalance,
    required this.variance,
  });

  bool get isReconciled => variance.abs() < 0.01;
}

class SubledgerReconciliationService {
  /// Compare sub-ledger (AR/AP individual customer/supplier totals)
  /// with the general ledger control account
  static List<ReconciliationItem> reconcile({
    required Map<String, double> subledgerBalances,
    required Map<String, double> glBalances,
    required Map<String, String> accountNames,
  }) {
    final all = {...subledgerBalances.keys, ...glBalances.keys};
    return all.map((code) {
      final sub = subledgerBalances[code] ?? 0;
      final gl = glBalances[code] ?? 0;
      return ReconciliationItem(
        accountCode: code,
        accountName: accountNames[code] ?? code,
        subledgerBalance: sub,
        generalLedgerBalance: gl,
        variance: sub - gl,
      );
    }).toList();
  }
}

// ─── F-07: Multi-Currency Support Types ─────────────────────────────────

class CurrencyRate {
  final String currencyCode;
  final String currencyName;
  final double rate; // to base currency
  final DateTime effectiveDate;

  const CurrencyRate({
    required this.currencyCode,
    required this.currencyName,
    required this.rate,
    required this.effectiveDate,
  });

  double convert(double amount) => amount * rate;
  double convertBack(double amount) => rate > 0 ? amount / rate : 0;
}

// ─── F-09: VAT Return Report ────────────────────────────────────────────

class VATReturnLine {
  final String description;
  final double taxableAmount;
  final double vatAmount;

  const VATReturnLine({
    required this.description,
    required this.taxableAmount,
    required this.vatAmount,
  });
}

class VATReturnReport {
  final DateTime fromDate;
  final DateTime toDate;
  final List<VATReturnLine> outputVAT; // VAT collected (sales)
  final List<VATReturnLine> inputVAT;  // VAT paid (purchases)

  const VATReturnReport({
    required this.fromDate,
    required this.toDate,
    required this.outputVAT,
    required this.inputVAT,
  });

  double get totalOutputVAT => outputVAT.fold(0, (s, l) => s + l.vatAmount);
  double get totalInputVAT => inputVAT.fold(0, (s, l) => s + l.vatAmount);
  double get netVATPayable => totalOutputVAT - totalInputVAT;
  bool get isRefundDue => netVATPayable < 0;
}

// ─── I-02: Stock Transfer Approval Integration ──────────────────────────

class StockTransferApprovalConfig {
  final double autoApproveThreshold;
  final bool requireApprovalForInterBranch;
  final List<String> approverRoles;

  const StockTransferApprovalConfig({
    this.autoApproveThreshold = 0,
    this.requireApprovalForInterBranch = true,
    this.approverRoles = const ['admin', 'manager'],
  });

  bool needsApproval(double transferValue, bool isInterBranch) {
    if (isInterBranch && requireApprovalForInterBranch) return true;
    if (autoApproveThreshold > 0 && transferValue > autoApproveThreshold) return true;
    return false;
  }
}

// ─── B-02: Inter-Branch Settlement Report ───────────────────────────────

class InterBranchSettlement {
  final int fromBranchId;
  final String fromBranchName;
  final int toBranchId;
  final String toBranchName;
  final double amountDue;
  final int invoiceCount;

  const InterBranchSettlement({
    required this.fromBranchId,
    required this.fromBranchName,
    required this.toBranchId,
    required this.toBranchName,
    required this.amountDue,
    required this.invoiceCount,
  });
}

// ─── B-03: Cost Center Allocation Rules ─────────────────────────────────

enum AllocationBasis {
  revenue,
  headcount,
  squareMeters,
  fixed,
  custom;

  String get labelAr => switch (this) {
    AllocationBasis.revenue => 'الإيرادات',
    AllocationBasis.headcount => 'عدد الموظفين',
    AllocationBasis.squareMeters => 'المساحة',
    AllocationBasis.fixed => 'نسبة ثابتة',
    AllocationBasis.custom => 'مخصص',
  };
}

class AllocationRule {
  final int sourceCostCenterId;
  final int targetCostCenterId;
  final AllocationBasis basis;
  final double percentage;

  const AllocationRule({
    required this.sourceCostCenterId,
    required this.targetCostCenterId,
    required this.basis,
    required this.percentage,
  });
}

// ─── B-04: Branch Performance Trend ────────────────────────────────────

class BranchKPI {
  final int branchId;
  final String branchName;
  final DateTime period;
  final double revenue;
  final double expenses;
  final double profit;
  final int invoiceCount;
  final double avgTicket;

  const BranchKPI({
    required this.branchId,
    required this.branchName,
    required this.period,
    required this.revenue,
    required this.expenses,
    required this.profit,
    required this.invoiceCount,
    required this.avgTicket,
  });

  double get profitMargin => revenue > 0 ? (profit / revenue * 100) : 0;
}

// ─── U-02: Bulk Action Toolbar ─────────────────────────────────────────

class BulkActionToolbar extends StatelessWidget {
  final int selectedCount;
  final List<BulkAction> actions;
  final VoidCallback onClearSelection;

  const BulkActionToolbar({
    super.key,
    required this.selectedCount,
    required this.actions,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.x, size: 18),
            onPressed: onClearSelection,
            tooltip: 'إلغاء التحديد',
          ),
          Text(
            '$selectedCount محدد',
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
          const Spacer(),
          ...actions.map((a) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              onPressed: a.onPressed,
              icon: Icon(a.icon, size: 16),
              label: Text(a.label, style: GoogleFonts.cairo(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: a.isDestructive ? Colors.red : AppColors.primary,
              ),
            ),
          )),
        ],
      ),
    );
  }
}

class BulkAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDestructive;

  const BulkAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isDestructive = false,
  });
}

// ─── U-05: Quick-Create "+" Button ─────────────────────────────────────

class QuickCreateButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  const QuickCreateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = PhosphorIconsBold.plus,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 3 Enterprise Models
// ═══════════════════════════════════════════════════════════════════════════

// ─── E-01: Bank Reconciliation ──────────────────────────────────────────

class BankReconciliationEntry {
  final DateTime date;
  final String reference;
  final double amount;
  final bool isMatched;
  final int? matchedTransactionId;

  const BankReconciliationEntry({
    required this.date,
    required this.reference,
    required this.amount,
    this.isMatched = false,
    this.matchedTransactionId,
  });
}

class BankReconciliationResult {
  final List<BankReconciliationEntry> bankEntries;
  final List<BankReconciliationEntry> systemEntries;
  final int matchedCount;
  final int unmatchedBankCount;
  final int unmatchedSystemCount;
  final double bankBalance;
  final double systemBalance;
  final double difference;

  const BankReconciliationResult({
    required this.bankEntries,
    required this.systemEntries,
    required this.matchedCount,
    required this.unmatchedBankCount,
    required this.unmatchedSystemCount,
    required this.bankBalance,
    required this.systemBalance,
    required this.difference,
  });
}

// ─── E-02: Budget vs Actual ─────────────────────────────────────────────

class BudgetLine {
  final String accountCode;
  final String accountName;
  final double budgetAmount;
  final double actualAmount;

  const BudgetLine({
    required this.accountCode,
    required this.accountName,
    required this.budgetAmount,
    required this.actualAmount,
  });

  double get variance => actualAmount - budgetAmount;
  double get variancePercent => budgetAmount != 0 ? (variance / budgetAmount * 100) : 0;
  bool get isOverBudget => actualAmount > budgetAmount;
}

// ─── E-07: KPI Definitions ─────────────────────────────────────────────

enum KPIType {
  dso,     // Days Sales Outstanding
  dpo,     // Days Payables Outstanding
  inventoryTurnover,
  grossMargin,
  currentRatio,
  quickRatio;

  String get labelAr => switch (this) {
    KPIType.dso => 'أيام تحصيل المبيعات (DSO)',
    KPIType.dpo => 'أيام سداد المشتريات (DPO)',
    KPIType.inventoryTurnover => 'معدل دوران المخزون',
    KPIType.grossMargin => 'هامش الربح الإجمالي',
    KPIType.currentRatio => 'نسبة التداول',
    KPIType.quickRatio => 'نسبة السيولة السريعة',
  };

  String get formula => switch (this) {
    KPIType.dso => '(الذمم المدينة / المبيعات) × 365',
    KPIType.dpo => '(الذمم الدائنة / المشتريات) × 365',
    KPIType.inventoryTurnover => 'تكلفة البضاعة المباعة / متوسط المخزون',
    KPIType.grossMargin => '(المبيعات - التكلفة) / المبيعات × 100',
    KPIType.currentRatio => 'الأصول المتداولة / الالتزامات المتداولة',
    KPIType.quickRatio => '(الأصول المتداولة - المخزون) / الالتزامات المتداولة',
  };
}

class KPIValue {
  final KPIType type;
  final double current;
  final double? previous;
  final double? target;

  const KPIValue({
    required this.type,
    required this.current,
    this.previous,
    this.target,
  });

  double? get changePercent =>
      previous != null && previous != 0 ? ((current - previous!) / previous! * 100) : null;

  bool get isOnTarget => target != null && current >= target!;
}

// ─── E-09: Risk Monitoring ──────────────────────────────────────────────

enum RiskLevel { low, medium, high, critical }

class RiskIndicator {
  final String name;
  final String description;
  final RiskLevel level;
  final double score; // 0-100
  final String recommendation;

  const RiskIndicator({
    required this.name,
    required this.description,
    required this.level,
    required this.score,
    required this.recommendation,
  });
}

// ─── I-06: Serial Number Tracking ───────────────────────────────────────

class SerialNumberEntry {
  final String serialNumber;
  final int productId;
  final String? batchNumber;
  final DateTime? receivedDate;
  final DateTime? soldDate;
  final int? invoiceId;
  final String status; // 'available', 'sold', 'returned', 'defective'

  const SerialNumberEntry({
    required this.serialNumber,
    required this.productId,
    this.batchNumber,
    this.receivedDate,
    this.soldDate,
    this.invoiceId,
    this.status = 'available',
  });
}

// ─── I-07: Warehouse Zone/Location ──────────────────────────────────────

class WarehouseZone {
  final int id;
  final String name;
  final String code;
  final int warehouseId;
  final String? description;
  final String? locationType; // 'bulk', 'picking', 'staging', 'cold'

  const WarehouseZone({
    required this.id,
    required this.name,
    required this.code,
    required this.warehouseId,
    this.description,
    this.locationType,
  });
}

class WarehouseLocation {
  final int id;
  final int zoneId;
  final String aisle;
  final String rack;
  final String shelf;
  final String bin;

  const WarehouseLocation({
    required this.id,
    required this.zoneId,
    required this.aisle,
    required this.rack,
    required this.shelf,
    required this.bin,
  });

  String get fullCode => '$aisle-$rack-$shelf-$bin';
}

// ─── C-04: IP/Device Whitelist ──────────────────────────────────────────

class DeviceWhitelistEntry {
  final String deviceId;
  final String deviceName;
  final String? ipAddress;
  final DateTime addedAt;
  final int addedByUserId;
  final bool isActive;

  const DeviceWhitelistEntry({
    required this.deviceId,
    required this.deviceName,
    this.ipAddress,
    required this.addedAt,
    required this.addedByUserId,
    this.isActive = true,
  });
}

class DeviceWhitelistService {
  /// Check if a device is authorized
  static bool isAuthorized({
    required String deviceId,
    required List<DeviceWhitelistEntry> whitelist,
    required bool whitelistEnabled,
  }) {
    if (!whitelistEnabled) return true;
    return whitelist.any((e) => e.deviceId == deviceId && e.isActive);
  }
}

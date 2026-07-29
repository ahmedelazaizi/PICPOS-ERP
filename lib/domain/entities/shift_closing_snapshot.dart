import 'dart:convert';

/// The exact set of figures a shift-closing report was printed from.
///
/// Persisted as JSON on `shifts.closing_snapshot` at close time so the paper
/// can be reproduced byte-for-byte later. Recomputation alone cannot do this:
/// the `actual*` amounts are what the cashier physically counted and typed,
/// and before this only `actualCash` had a column — the bank and click counts
/// were buried inside the free-text `notes` string.
///
/// Deliberately a plain map round-trip rather than a codegen'd model: it is
/// written once and read by one screen, and it must tolerate being read back
/// by a build whose field list has since grown (see [fromJson]'s defaults).
class ShiftClosingSnapshot {
  final int invoiceCount;
  final double totalSales;

  final double systemCash;
  final double systemCard;
  final double systemClick;

  final double actualCash;
  final double actualCard;
  final double actualClick;

  final double cashVariance;
  final double cardVariance;
  final double clickVariance;
  final double totalVariance;

  final double totalExpenses;
  final double cashRefunds;
  final double cashIncome;
  final double creditSales;
  final int creditSalesCount;
  final double openingBalance;

  final String? employeeName;
  final String? companyName;

  /// When the close actually happened. Used as the report date on a reprint —
  /// stamping it with "now" would date last week's shift to today.
  final DateTime? closedAt;

  const ShiftClosingSnapshot({
    required this.invoiceCount,
    required this.totalSales,
    required this.systemCash,
    required this.systemCard,
    required this.systemClick,
    required this.actualCash,
    required this.actualCard,
    required this.actualClick,
    required this.cashVariance,
    required this.cardVariance,
    required this.clickVariance,
    required this.totalVariance,
    required this.totalExpenses,
    required this.cashRefunds,
    required this.cashIncome,
    required this.creditSales,
    required this.creditSalesCount,
    required this.openingBalance,
    this.employeeName,
    this.companyName,
    this.closedAt,
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'invoiceCount': invoiceCount,
        'totalSales': totalSales,
        'systemCash': systemCash,
        'systemCard': systemCard,
        'systemClick': systemClick,
        'actualCash': actualCash,
        'actualCard': actualCard,
        'actualClick': actualClick,
        'cashVariance': cashVariance,
        'cardVariance': cardVariance,
        'clickVariance': clickVariance,
        'totalVariance': totalVariance,
        'totalExpenses': totalExpenses,
        'cashRefunds': cashRefunds,
        'cashIncome': cashIncome,
        'creditSales': creditSales,
        'creditSalesCount': creditSalesCount,
        'openingBalance': openingBalance,
        'employeeName': employeeName,
        'companyName': companyName,
        'closedAt': closedAt?.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  factory ShiftClosingSnapshot.fromJson(Map<String, dynamic> json) =>
      ShiftClosingSnapshot(
        invoiceCount: _i(json['invoiceCount']),
        totalSales: _d(json['totalSales']),
        systemCash: _d(json['systemCash']),
        systemCard: _d(json['systemCard']),
        systemClick: _d(json['systemClick']),
        actualCash: _d(json['actualCash']),
        actualCard: _d(json['actualCard']),
        actualClick: _d(json['actualClick']),
        cashVariance: _d(json['cashVariance']),
        cardVariance: _d(json['cardVariance']),
        clickVariance: _d(json['clickVariance']),
        totalVariance: _d(json['totalVariance']),
        totalExpenses: _d(json['totalExpenses']),
        cashRefunds: _d(json['cashRefunds']),
        cashIncome: _d(json['cashIncome']),
        creditSales: _d(json['creditSales']),
        creditSalesCount: _i(json['creditSalesCount']),
        openingBalance: _d(json['openingBalance']),
        employeeName: json['employeeName'] as String?,
        companyName: json['companyName'] as String?,
        closedAt: DateTime.tryParse((json['closedAt'] as String?) ?? ''),
      );

  /// Decodes a stored snapshot, returning null for absent or unreadable data.
  ///
  /// Never throws: a corrupt snapshot must degrade to "recompute and label it"
  /// rather than break the shift screen for every other shift on it.
  static ShiftClosingSnapshot? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ShiftClosingSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

import 'dart:math' as math;
import 'package:picpos_erp/core/constants/app_constants.dart';

/// Utility class for precise financial calculations.
/// Avoids floating-point rounding errors by using standard fixed-point strategies
/// and centralizes all core accounting formulas (discounts, taxes, totals).
class FinancialUtils {
  FinancialUtils._();

  /// Defines the precision for financial storage and calculation.
  ///
  /// ⚠️ **getters عن قصدٍ لا `static final`** (‏قرارُ المالك 2026-08-23).
  /// كانا:
  ///
  /// ```dart
  /// static const int _precision = AppConstants.decimalPlaces;
  /// static final double _multiplier = math.pow(10, _precision).toDouble();
  /// ```
  ///
  /// و`static final` في دارت **كسولٌ يُحسب عند أوّل وصولٍ ثمّ يثبت للأبد**.
  /// و`setCurrency` تقع **بعد** إقلاعٍ كامل (‏`init()` تقرأ القاعدة)، فأيُّ
  /// لمسٍ لـ`FinancialUtils` قبلها كان يجمّد المضاعفَ على ١٠٠٠ — فتبقى
  /// الحساباتُ كلُّها بثلاث خاناتٍ رغم اختيار الجنيه، **صامتةً وبلا أثرٍ في
  /// أيّ سجلّ**. وهي أخطرُ من الخطأ الظاهر لأنها تصيب المالَ لا العرض.
  ///
  /// والقراءةُ الديناميّةُ كلفتُها `math.pow` لكلّ نداء — ولا تُحوَّل إلى
  /// كاشٍ إلّا بمُبطِلٍ يُستدعى من `setCurrency`، وإلّا عاد العطبُ نفسُه.
  static int get _precision => AppConstants.decimalPlaces;
  static double get _multiplier => math.pow(10, _precision).toDouble();

  // ── Spec 139: single source of truth for the journal-entry balance cap ──
  // The ONE allowed debit-vs-credit tolerance. A residual within this cap is a
  // legitimate rounding remainder (booked to the «فروق تقريب» account by the JE
  // writer); anything beyond it is a real error and is hard-failed. This value
  // (0.01) restores the pre-Cluster-025 honest tolerance — the ×10 bump to 0.10
  // and the divergent 0.001/0.01 thresholds are eliminated. Referenced by the
  // JE writer, the JE factory pre-validation, and [assertBalanced].
  static const double balanceTolerance = 0.01;

  /// The balance cap expressed in integer minor units (= 10 at decimalPlaces=3).
  /// The JE writer compares residuals in minor units to avoid float drift.
  static int get balanceToleranceMinorUnits =>
      (balanceTolerance * _multiplier).round();

  /// Convert a currency amount to integer minor units (half-up), e.g.
  /// 12.345 → 12345 at decimalPlaces=3. Used to compute JE balance exactly.
  static int toMinorUnits(double value) => (value * _multiplier).round();

  /// Inverse of [toMinorUnits]: 12345 → 12.345.
  static double fromMinorUnits(int minor) => minor / _multiplier;

  /// Round using the currency's minor units, half away from zero.
  ///
  /// FA-04 decision: money columns remain `RealColumn` for schema compatibility
  /// with existing SQLite and PostgreSQL databases. Every persistence boundary
  /// must therefore call this method first; comparisons use [toMinorUnits].
  /// Normalizing to ten decimal places before scaling removes binary-fraction
  /// artefacts (for example 2.675 and 1.005) while preserving the configured
  /// [AppConstants.decimalPlaces].
  static double round(double value) {
    if (!value.isFinite) return value;
    final normalized = double.parse(value.toStringAsFixed(10));
    return (normalized * _multiplier).roundToDouble() / _multiplier;
  }

  /// Phase 2: Defensive precision guard for DB-write boundaries.
  /// Rounds + clamps to non-negative (unless [allowNegative] is true).
  /// Use before every INSERT/UPDATE of a financial amount.
  static double guardAmount(double value, {bool allowNegative = false}) {
    final rounded = round(value);
    if (!allowNegative && rounded < 0) return 0.0;
    return rounded;
  }

  /// Phase 2: Assert that journal entry debit/credit totals are balanced.
  /// Throws if the absolute difference exceeds [balanceTolerance] (the single
  /// balance-tolerance source of truth — half-penny tolerance).
  static void assertBalanced(
    double totalDebit,
    double totalCredit, {
    String? context,
  }) {
    final diff = (round(totalDebit) - round(totalCredit)).abs();
    if (diff > balanceTolerance) {
      throw UnbalancedJournalException(
        debit: totalDebit,
        credit: totalCredit,
        context: context ?? 'Unknown',
      );
    }
  }

  /// Calculate the total of a single line item.
  /// Formula: (Quantity * Unit Price)
  static double calculateLineSubtotal(double quantity, double unitPrice) {
    return round(quantity * unitPrice);
  }

  /// Calculate tax amount for a specific amount.
  /// Formula: Amount * (TaxRate / 100)
  static double calculateTaxAmount(double amount, double taxRatePercent) {
    if (taxRatePercent <= 0) return 0.0;
    return round(amount * (taxRatePercent / 100.0));
  }

  /// Calculate discount amount from a percentage.
  /// Formula: Amount * (DiscountPercent / 100)
  static double calculateDiscountFromPercent(
    double amount,
    double discountPercent,
  ) {
    if (discountPercent <= 0) return 0.0;
    return round(amount * (discountPercent / 100.0));
  }

  /// Calculate the net total for a line item after item-level tax and discount (if any).
  static double calculateLineNetTotal({
    required double quantity,
    required double unitPrice,
    double taxRatePercent = 0.0,
    double discountAmount = 0.0,
  }) {
    final subtotal = calculateLineSubtotal(quantity, unitPrice);
    final afterDiscount = subtotal - discountAmount;
    final tax = calculateTaxAmount(afterDiscount, taxRatePercent);
    return round(afterDiscount + tax);
  }

  /// Centralized invoice totals engine.
  ///
  /// Line bases are rounded individually. The invoice-discount remainder is
  /// assigned to the largest line, guaranteeing that the sum of persisted line
  /// nets equals the rounded header net. Tax is then calculated on each rounded
  /// net. With [pricesIncludeTax], each discounted gross line is split into net
  /// and tax before the same rounding rule is applied.
  static ({
    double subtotal,
    double totalDiscount,
    double totalTax,
    double grandTotal,
    List<double> lineNets,
    List<double> lineTaxes,
  })
  calculateInvoiceTotals({
    required List<({double quantity, double unitPrice, double taxRatePercent})>
    items,
    double globalDiscountAmount = 0.0,
    double deliveryFee = 0.0,
    bool pricesIncludeTax = false,
    List<double>? lineDiscountAmounts,
  }) {
    final lineGrosses = items
        .map((item) => calculateLineSubtotal(item.quantity, item.unitPrice))
        .toList();
    final subtotal = round(
      lineGrosses.fold<double>(0, (sum, value) => sum + value),
    );
    final lineDiscounts = List<double>.generate(
      items.length,
      (i) => round(
        (lineDiscountAmounts != null && i < lineDiscountAmounts.length)
            ? lineDiscountAmounts[i].clamp(0, lineGrosses[i]).toDouble()
            : 0.0,
      ),
    );
    final afterLineDiscount = round(
      lineGrosses.fold<double>(0, (sum, value) => sum + value) -
          lineDiscounts.fold<double>(0, (sum, value) => sum + value),
    );
    final requestedDiscount = round(
      globalDiscountAmount.clamp(0, afterLineDiscount).toDouble(),
    );
    final headerNet = round(afterLineDiscount - requestedDiscount);
    final grossBase = lineGrosses.asMap().entries.fold<double>(
      0,
      (sum, entry) => sum + entry.value - lineDiscounts[entry.key],
    );
    final ratio = grossBase > 0 ? headerNet / grossBase : 0.0;
    final lineNets = <double>[];
    for (var i = 0; i < lineGrosses.length; i++) {
      final discountedGross = round(
        (lineGrosses[i] - lineDiscounts[i]) * ratio,
      );
      lineNets.add(discountedGross);
    }
    if (lineNets.isNotEmpty) {
      final largest = lineGrosses.indexOf(lineGrosses.reduce(math.max));
      final remainder = round(
        headerNet - lineNets.fold<double>(0, (sum, value) => sum + value),
      );
      lineNets[largest] = round(lineNets[largest] + remainder);
    }

    final lineTaxes = <double>[];
    for (var i = 0; i < items.length; i++) {
      final rate = items[i].taxRatePercent;
      if (rate <= 0) {
        lineTaxes.add(0.0);
      } else if (pricesIncludeTax) {
        final net = round(lineNets[i] / (1 + rate / 100));
        lineTaxes.add(round(lineNets[i] - net));
        lineNets[i] = net;
      } else {
        lineTaxes.add(calculateTaxAmount(lineNets[i], rate));
      }
    }
    final totalTax = round(
      lineTaxes.fold<double>(0, (sum, value) => sum + value),
    );
    final taxableBase = pricesIncludeTax
        ? lineNets.fold<double>(0, (sum, value) => sum + value) + totalTax
        : headerNet + totalTax;
    final grandTotal = round(taxableBase + deliveryFee);
    return (
      subtotal: subtotal,
      totalDiscount: round(
        requestedDiscount +
            lineDiscounts.fold<double>(0, (sum, value) => sum + value),
      ),
      totalTax: totalTax,
      grandTotal: grandTotal,
      lineNets: lineNets,
      lineTaxes: lineTaxes,
    );
  }
}

/// Exception for journal entry imbalance
class UnbalancedJournalException implements Exception {
  final double debit;
  final double credit;
  final String context;

  UnbalancedJournalException({
    required this.debit,
    required this.credit,
    required this.context,
  });

  @override
  String toString() =>
      'قيد غير متزن ($context): مدين=${debit.toStringAsFixed(AppConstants.decimalPlaces)}, '
      'دائن=${credit.toStringAsFixed(AppConstants.decimalPlaces)}, '
      'فرق=${(debit - credit).abs().toStringAsFixed(AppConstants.decimalPlaces)}';
}

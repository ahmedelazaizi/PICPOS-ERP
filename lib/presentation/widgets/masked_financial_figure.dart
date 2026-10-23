import '../../core/permissions/financial_figures_access.dart';

/// Returns a stable placeholder when a financial figure is not visible.
String maskFinancialFigure(bool canSee, String value) =>
    canSee ? value : maskedFinancialFigure;

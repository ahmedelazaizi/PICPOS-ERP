class DashboardProfitMarginDisplay {
  const DashboardProfitMarginDisplay({
    required this.rawMargin,
    required this.value,
    required this.valueLabel,
    required this.isDefined,
  });

  final double rawMargin;
  final double value;
  final String valueLabel;
  final bool isDefined;
}

DashboardProfitMarginDisplay dashboardProfitMargin({
  required double revenue,
  required double netProfit,
}) {
  if (revenue <= 0) {
    return const DashboardProfitMarginDisplay(
      rawMargin: 0,
      value: 0,
      valueLabel: '—',
      isDefined: false,
    );
  }
  final margin = netProfit / revenue;
  return DashboardProfitMarginDisplay(
    rawMargin: margin,
    value: margin.clamp(0.0, 1.0),
    valueLabel: '${(margin * 100).toStringAsFixed(1)}%',
    isDefined: true,
  );
}

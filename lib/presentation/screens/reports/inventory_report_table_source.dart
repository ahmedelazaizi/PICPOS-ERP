import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/data/database/database.dart';

class InventoryReportTableSource extends DataTableSource {
  InventoryReportTableSource({
    required this.products,
    required this.categoryNames,
    required this.unitNames,
    required this.stockMap,
    required this.stockScoped,
    required this.currencyFormat,
    required this.secondaryTextColor,
  });

  final List<Product> products;
  final Map<int, String> categoryNames;
  final Map<int, String> unitNames;
  final Map<int, double> stockMap;
  final bool stockScoped;
  final NumberFormat currencyFormat;
  final Color secondaryTextColor;

  @override
  DataRow? getRow(int index) {
    if (index >= products.length) return null;
    final product = products[index];
    final stock = stockScoped
        ? (stockMap[product.id] ?? 0.0)
        : product.currentStock;
    final totalCost = product.costPrice * stock;
    final totalSale = product.salePrice * stock;
    final isLow = stock <= product.minStock;
    return DataRow(
      cells: [
        DataCell(Text(product.code)),
        DataCell(Text(product.name)),
        DataCell(
          Text(
            categoryNames[product.categoryId] ?? tr('غير مصنف'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            unitNames[product.id] ?? tr('قطعة'),
            style: TextStyle(fontSize: 12, color: secondaryTextColor),
          ),
        ),
        DataCell(
          Text(
            stock.toString(),
            style: TextStyle(
              color: isLow ? AppColors.error : null,
              fontWeight: isLow ? FontWeight.bold : null,
            ),
          ),
        ),
        DataCell(Text(currencyFormat.format(product.costPrice))),
        DataCell(Text(currencyFormat.format(totalCost))),
        DataCell(Text(currencyFormat.format(product.salePrice))),
        DataCell(Text(currencyFormat.format(totalSale))),
      ],
    );
  }

  @override
  int get rowCount => products.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}

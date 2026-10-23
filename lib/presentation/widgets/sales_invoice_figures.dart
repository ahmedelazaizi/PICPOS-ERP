import 'package:flutter/material.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/number_utils.dart';
import '../../domain/entities/invoice_entity.dart';
import 'any_permission_masked_text.dart';
import 'permission_guard.dart';

/// من يرى هامشَ الربح في تفاصيل الفاتورة (AUTHZ-007): من يرى أرقامَ المبيعات
/// **و** يملك كودَ التكلفة أو الربح. فالهامشُ يكشف التكلفةَ.
const List<String> kInvoiceMarginCodes = [
  PermissionCodes.productsCostView,
  PermissionCodes.dashboardProfit,
];

/// بوّابةُ هامش الربح: أرقامُ المبيعات (كلا الكودَين) + أحدُ [kInvoiceMarginCodes].
class SalesInvoiceMarginGate extends StatelessWidget {
  const SalesInvoiceMarginGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PermissionGuard.allOf(
        allOf: kSalesFiguresCodes,
        child: PermissionGuard.anyOf(anyOf: kInvoiceMarginCodes, child: child),
      );
}

/// جدولُ أصناف الفاتورة: الكميّاتُ ظاهرة، والأسعارُ والإجماليّاتُ خلف بوّابةِ
/// أرقام المبيعات (AUTHZ-002).
/// صفّ بنود الفاتورة للعرض (بلا اعتماد على طبقة قاعدة البيانات).
class InvoiceItemRow {
  const InvoiceItemRow({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final String name;
  final String? unit;
  final double quantity;
  final double unitPrice;
  final double total;
}

class SalesInvoiceItemsTable extends StatelessWidget {
  const SalesInvoiceItemsTable({super.key, required this.items});

  final List<InvoiceItemRow> items;

  String _fmt(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

  Widget _money(double v) =>
      AllPermissionsMaskedText(allOf: kSalesFiguresCodes, text: _fmt(v));

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columnSpacing: 20,
      columns: [
        DataColumn(label: Text(tr('الصنف'))),
        DataColumn(label: Text(tr('الوحدة'))),
        DataColumn(label: Text(tr('الكمية'))),
        DataColumn(label: Text(tr('السعر'))),
        DataColumn(label: Text(tr('الإجمالي'))),
      ],
      rows: [
        for (final item in items)
          DataRow(cells: [
            DataCell(Text(item.name)),
            DataCell(Text(item.unit ?? tr('قطعة'))),
            DataCell(Text(_fmt(item.quantity))),
            DataCell(_money(item.unitPrice)),
            DataCell(_money(item.total)),
          ]),
      ],
    );
  }
}

/// كتلةُ المجاميع (فرعي/خصم/ضريبة/إجمالي/مدفوع/متبقٍّ) — تختفي كاملةً بلا
/// أرقام المبيعات (AUTHZ-002).
class SalesInvoiceTotalsBlock extends StatelessWidget {
  const SalesInvoiceTotalsBlock({super.key, required this.invoice});

  final InvoiceEntity invoice;

  Widget _row(String label, double value,
      {Color? color, bool emphasize = false}) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(NumberUtils.formatCurrency(value), style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = invoice.total - invoice.paid;
    return PermissionGuard.allOf(
      allOf: kSalesFiguresCodes,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              _row(tr('المجموع الفرعي'), invoice.subtotal),
              if (invoice.discountAmount != 0)
                _row(tr('الخصم'), invoice.discountAmount,
                    color: AppColors.warning),
              if (invoice.taxAmount != 0)
                _row(tr('الضريبة'), invoice.taxAmount),
              const Divider(height: 18),
              _row(tr('الإجمالي'), invoice.total, emphasize: true),
              _row(tr('المدفوع'), invoice.paid, color: AppColors.success),
              _row(
                tr('المتبقي'),
                remaining,
                color: remaining > 0.001 ? AppColors.error : AppColors.success,
                emphasize: remaining > 0.001,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/database/database_barrel.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../../domain/models/table_status.dart';

/// Callback types for table card actions
typedef OnTableTap = void Function(RestaurantTable table);
typedef OnTableEdit = void Function(RestaurantTable table);
typedef OnTableDelete = void Function(RestaurantTable table);
typedef OnTableTransfer = void Function(RestaurantTable table);
typedef OnTableSplit = void Function(RestaurantTable table);
typedef GetOpenOrder = Future<TableOrder?> Function(int tableId);

/// Premium table card with status glow, dynamic shape, and order total
class TableCardWidget extends StatelessWidget {
  final RestaurantTable table;
  final OnTableTap onTap;
  final OnTableEdit onEdit;
  final OnTableDelete onDelete;
  final OnTableTransfer? onTransfer;
  final OnTableSplit? onSplit;
  final GetOpenOrder getOpenOrder;

  const TableCardWidget({
    super.key,
    required this.table,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onTransfer,
    this.onSplit,
    required this.getOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = ['occupied', 'seated', 'ordered', 'eating', 'billing']
        .contains(table.status);
    final statusColor = _getStatusColor();
    final statusIcon = _getStatusIcon();

    // Calculate elapsed time
    final elapsed = DateTime.now().difference(table.lastStatusAt);
    final elapsedStr = elapsed.inMinutes > 0
        ? '${elapsed.inHours > 0 ? '${elapsed.inHours}س ' : ''}${elapsed.inMinutes % 60}د'
        : '${elapsed.inSeconds}ث';

    // Table shape based on capacity
    final isRound = table.capacity <= 4;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(table),
        borderRadius: BorderRadius.circular(isRound ? 80 : 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                statusColor.withValues(alpha: 0.1),
                statusColor.withValues(alpha: 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(isRound ? 80 : 16),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.15),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Main content ──
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Status glow dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Table name
                    Text(
                      table.name,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),

                    // Capacity + timer row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsBold.users,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.25)),
                        const SizedBox(width: 3),
                        Text(
                          '${table.capacity}',
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.25),
                              fontWeight: FontWeight.w600),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(PhosphorIconsBold.clock,
                              size: 10, color: statusColor),
                          const SizedBox(width: 2),
                          Text(
                            elapsedStr,
                            style: GoogleFonts.cairo(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Status badge or order total
                    if (isActive)
                      FutureBuilder<TableOrder?>(
                        future: getOpenOrder(table.id),
                        builder: (ctx, snap) {
                          final order = snap.data;
                          // «دُفع X من Y» — دفعةٌ جزئيةٌ فقط تبقي الطاولة
                          // 🔵 (المدفوعةُ بالكامل تصير 🟠 من تلقائها)، فهذا
                          // العرضُ محصورٌ بحالة `occupied` كي لا يظهر على
                          // طاولةٍ فارغة.
                          final showsPaidProgress =
                              table.status == TableStatus.occupied &&
                                  order != null &&
                                  order.paidAmount > 0;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    statusColor.withValues(alpha: 0.2),
                                    statusColor.withValues(alpha: 0.08),
                                  ]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: statusColor
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon,
                                        size: 10, color: statusColor),
                                    const SizedBox(width: 4),
                                    if (order != null && order.total > 0)
                                      Text(
                                        '${order.total.toStringAsFixed(0)} ${AppConstants.currencySymbolEn}',
                                        style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10,
                                            color: statusColor),
                                      )
                                    else
                                      Text(
                                        _getStatusLabel(),
                                        style: GoogleFonts.cairo(
                                            fontSize: 9,
                                            color: statusColor,
                                            fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              ),
                              if (showsPaidProgress) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'دُفع ${order.paidAmount.toStringAsFixed(0)} من ${_effectiveTotal(order).toStringAsFixed(0)}',
                                  style: GoogleFonts.cairo(
                                      fontSize: 8,
                                      color: const Color(0xFFF97316),
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ],
                          );
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            statusColor.withValues(alpha: 0.15),
                            statusColor.withValues(alpha: 0.05),
                          ]),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  statusColor.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon,
                                size: 10, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              _getStatusLabel(),
                              style: GoogleFonts.cairo(
                                  fontSize: 9,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ── Menu button ──
              Positioned(
                top: 6,
                left: 6,
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit(table);
                    } else if (value == 'delete') {
                      onDelete(table);
                    } else if (value == 'transfer' && onTransfer != null) {
                      onTransfer!(table);
                    } else if (value == 'split' && onSplit != null) {
                      onSplit!(table);
                    }
                  },
                  icon: Icon(
                    PhosphorIconsBold.dotsThreeVertical,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  itemBuilder: (ctx) => [
                    if (isActive && onTransfer != null)
                      PopupMenuItem(
                        value: 'transfer',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.arrowsLeftRight,
                                size: 16,
                                color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 8),
                            Text('نقل الطلب',
                                style: GoogleFonts.cairo(
                                    color: Colors.white
                                        .withValues(alpha: 0.8),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    if (isActive && onSplit != null)
                      PopupMenuItem(
                        value: 'split',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.columns,
                                size: 16,
                                color: Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Text('تقسيم الطلب',
                                style: GoogleFonts.cairo(
                                    color: Colors.white
                                        .withValues(alpha: 0.8),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.pencil,
                              size: 16,
                              color: Color(0xFF3B82F6)),
                          const SizedBox(width: 8),
                          Text('تعديل',
                              style: GoogleFonts.cairo(
                                  color: Colors.white
                                      .withValues(alpha: 0.8),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.trash,
                              size: 16, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text('حذف',
                              style: GoogleFonts.cairo(
                                  color: const Color(0xFFEF4444),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (table.status) {
      case 'available':
        return const Color(0xFF10B981);
      case 'reserved':
        return const Color(0xFFF59E0B);
      case 'occupied':
        return const Color(0xFF3B82F6);
      case TableStatus.paid: // 🟠
        return const Color(0xFFF97316);
      case TableStatus.outOfService: // ⚪
        return const Color(0xFFCBD5E1);
      case 'seated':
        return const Color(0xFF06B6D4);
      case 'ordered':
        return const Color(0xFF8B5CF6);
      case 'eating':
        return const Color(0xFFEC4899);
      case 'billing':
        return const Color(0xFFF97316);
      case 'cleaning':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getStatusIcon() {
    switch (table.status) {
      case 'available':
        return PhosphorIconsBold.checkCircle;
      case 'reserved':
        return PhosphorIconsBold.calendarCheck;
      case 'occupied':
      case 'seated':
        return PhosphorIconsBold.armchair;
      case TableStatus.paid:
        return PhosphorIconsBold.currencyCircleDollar;
      case TableStatus.outOfService:
        return PhosphorIconsBold.prohibit;
      case 'ordered':
        return PhosphorIconsBold.notepad;
      case 'eating':
        return PhosphorIconsBold.forkKnife;
      case 'billing':
        return PhosphorIconsBold.receipt;
      case 'cleaning':
        return PhosphorIconsBold.broom;
      default:
        return PhosphorIconsBold.circlesThree;
    }
  }

  String _getStatusLabel() {
    switch (table.status) {
      case 'available':
        return 'متاحة';
      case 'reserved':
        return 'محجوزة';
      case 'occupied':
      case 'seated':
        return 'جالسين';
      case TableStatus.paid:
        return 'مدفوعة';
      case TableStatus.outOfService:
        return 'خارج الخدمة';
      case 'ordered':
        return 'تم الطلب';
      case 'eating':
        return 'يأكلون';
      case 'billing':
        return 'بانتظار الدفع';
      case 'cleaning':
        return 'تنظيف';
      default:
        return 'متاحة';
    }
  }
}

/// الإجماليُّ بعد الخصم — مرآةٌ خفيفةٌ لـ`TableSessionService.effectiveTotal`
/// لعرضٍ فوريٍّ من الطلب المحمَّل أصلاً، لا استعلامٍ آخر لقاعدة البيانات.
double _effectiveTotal(TableOrder order) {
  if (order.discountType == null || order.discountValue <= 0) {
    return order.total;
  }
  final discount = order.discountType == 'percent'
      ? order.total * order.discountValue / 100
      : order.discountValue;
  final net = order.total - discount;
  return net < 0 ? 0 : net;
}

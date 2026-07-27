import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../domain/entities/cart_item_entity.dart';
import '../../../../core/constants/app_constants.dart';

class TablePosCartItem extends StatelessWidget {
  final CartItemEntity item;
  final int index;
  final Function(int, double) onUpdateQuantity;
  final Function(int) onRemove;
  final VoidCallback onAddNote;

  const TablePosCartItem({
    super.key,
    required this.item,
    required this.index,
    required this.onUpdateQuantity,
    required this.onRemove,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Product name + price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName,
                        style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        '${item.effectivePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.3))),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Decrement (or delete if qty=1)
                    _qtyBtn(
                      icon: item.quantity <= 1
                          ? PhosphorIconsBold.trash
                          : PhosphorIconsBold.minus,
                      color: item.quantity <= 1
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: 0.5),
                      onTap: () {
                        if (item.quantity <= 1) {
                          onRemove(index);
                        } else {
                          onUpdateQuantity(index, item.quantity - 1);
                        }
                      },
                    ),
                    // Quantity label
                    Container(
                      width: 32,
                      alignment: Alignment.center,
                      child: Text(
                        item.quantity.toStringAsFixed(
                            item.isSoldByWeight ? 2 : 0),
                        style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                    // Increment
                    _qtyBtn(
                      icon: PhosphorIconsBold.plus,
                      color: const Color(0xFF10B981),
                      onTap: () {
                        onUpdateQuantity(index, item.quantity + 1);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Item total
              SizedBox(
                width: 60,
                child: Text(
                  // صافي الصف مش شامل الضريبة — نفس سبب `cart_item_tile`:
                  // حساب الفاتورة بيتجاهل ضريبة الصف ويعيد حسابها مشروطة
                  // بـ `taxEnabled`، فعرض الصف شاملها بيخلّيه رقم مالوش
                  // علاقة بالإجماليات لما الضريبة تكون مقفولة.
                  item.totalBeforeTax
                      .toStringAsFixed(AppConstants.decimalPlaces),
                  style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.7)),
                  textAlign: TextAlign.end,
                ),
              ),

              const SizedBox(width: 4),

              // Note button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAddNote,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      item.note != null && item.note!.isNotEmpty
                          ? PhosphorIconsFill.notepad
                          : PhosphorIconsBold.notepad,
                      size: 16,
                      color: item.note != null && item.note!.isNotEmpty
                          ? const Color(0xFFF59E0B)
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Show note if exists
          if (item.note != null && item.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.pencilLine,
                      size: 10, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(item.note!,
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _qtyBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

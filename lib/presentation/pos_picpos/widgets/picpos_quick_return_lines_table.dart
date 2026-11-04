import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/returnable_line.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../state/pos_return_mode.dart';
import 'picpos_pos_text.dart';

/// لوحةُ «سلّة المرتجع» في عمود الفاتورة أثناء «مرتجع سريع».
///
/// ── لماذا وُجدت (2026-11-04) ─────────────────────────────────────────────
/// بعد تأكيد محرِّر الأسطر كان العمودُ يعرض `PicPosItemsTable` — وهو جدولُ
/// **سلّة البيع** (‏`cartControllerProvider`) التي لا يكتب عليها وضعُ المرتجع
/// عمداً — فيرى الكاشيرُ الترويسةَ الحمراء فوق سلّةٍ فارغة ولا طريقَ لرؤية
/// ما اختاره أو تعديله (بلاغُ التحقّق الحيّ final3، `SINV-7`). هذه اللوحةُ
/// تعرض [mode] نفسَه بدلها، فلا مصدرَ حقيقةٍ ثانٍ.
///
/// عديمةُ الحالة وخالصة: لا Riverpod ولا `data/database`. كلُّ تعديلٍ يذهب
/// للمستدعي (‏الشاشة) الذي يمرّ بـ`PosReturnMode.setQty`/`clearQty` وبحرّاس
/// الصلاحيّة نفسِها التي في المحرِّر.
class PicPosQuickReturnLinesTable extends StatelessWidget {
  final PosReturnMode mode;
  final ValueChanged<ReturnableLine> onIncrement;
  final ValueChanged<ReturnableLine> onDecrement;
  final ValueChanged<ReturnableLine> onEditQty;
  final ValueChanged<ReturnableLine> onRemove;

  const PicPosQuickReturnLinesTable({
    super.key,
    required this.mode,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditQty,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lines = mode.linesByItemId.values.toList();
    final refundInk = PicPosText.readableOn(context, AppColors.error);
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              tr('امسح باركود صنفٍ من الفاتورة أو اضغط بطاقته لزيادة كميّة إرجاعه'),
              style: PicPosText.l(context, 11, color: context.picposMuted),
            ),
          ),
          Divider(height: 1, color: context.picposHairline),
          Expanded(
            child: ListView.separated(
              itemCount: lines.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.picposHairline),
              itemBuilder: (context, i) => _row(context, lines[i]),
            ),
          ),
          Divider(height: 1, color: context.picposHairline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Text(tr('مبلغُ الاسترداد'), style: PicPosText.l(context, 13)),
                const Spacer(),
                Text(
                  mode.refundTotal.toStringAsFixed(2),
                  key: const ValueKey('picpos_quick_return_refund_total'),
                  style: PicPosText.v(context, 16, color: refundInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ReturnableLine line) {
    final qty = mode.requestedQty[line.invoiceItemId] ?? 0;
    final atMax = qty >= line.availableQty - 0.0005;
    final qtyText = qty == qty.truncateToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(3);
    return Padding(
      key: ValueKey('picpos_quick_return_line_${line.invoiceItemId}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName,
                    overflow: TextOverflow.ellipsis,
                    style: PicPosText.v(context, 13)),
                Text(
                  tr('مباع {p0} · مرتجعٌ سابقاً {p1} · متاح {p2} · السعر {p3}', {
                    'p0': line.soldQty.toStringAsFixed(2),
                    'p1': line.alreadyReturnedQty.toStringAsFixed(2),
                    'p2': line.availableQty.toStringAsFixed(2),
                    'p3': mode.unitPriceOf(line.invoiceItemId).toStringAsFixed(2),
                  }),
                  style: PicPosText.l(context, 10, color: context.picposMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIconsBold.minusCircle,
                size: 20, color: context.picposText),
            onPressed: qty > 0 ? () => onDecrement(line) : null,
          ),
          InkWell(
            onTap: line.availableQty > 0 ? () => onEditQty(line) : null,
            child: Container(
              width: 52,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                qtyText,
                key: ValueKey('picpos_quick_return_qty_${line.invoiceItemId}'),
                style: PicPosText.v(context, 13),
              ),
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIconsBold.plusCircle,
                size: 20, color: context.picposText),
            onPressed: atMax ? null : () => onIncrement(line),
          ),
          SizedBox(
            width: 36,
            child: qty > 0
                ? IconButton(
                    icon: Icon(PhosphorIconsBold.x,
                        size: 16,
                        color: PicPosText.readableOn(context, AppColors.error)),
                    tooltip: tr('استبعادُ الصنف من المرتجع'),
                    onPressed: () => onRemove(line),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

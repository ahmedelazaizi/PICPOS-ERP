import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'picpos_pos_text.dart';

/// ترويسةٌ تحذيريةٌ تظهر أعلى عمود الفاتورة في شاشة نقطة بيع PicPos أثناء
/// «وضع المرتجع» — سلةٌ تبدو كسلّة بيعٍ وتفعل عكسَها هي وصفةُ خطأٍ يوميّ
/// (مهمّةُ الواجهة ٧، مواصفةُ §٥).
///
/// عديمةُ الحالة وخالصةٌ عمداً: لا Riverpod ولا `data/database` — حارسُ
/// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
/// القاعدة، وهذا ملفٌّ جديد. القراءةُ من `posReturnModeProvider` تحدث عند
/// المستدعي (‏شاشةُ البيع السريع)، وهذه فقط تعرض ما تُعطاه — `invoiceNumber`
/// نصٌّ، لا `SalesInvoiceData`.
class PicPosReturnModeBanner extends StatelessWidget {
  final String invoiceNumber;

  /// يُستدعى عند الضغط على «إلغاء المرتجع». المستدعي مسؤول عن التأكيد
  /// وتصفير الحالة. `null` = لا يظهر الزر.
  final VoidCallback? onCancel;

  const PicPosReturnModeBanner(
      {super.key, required this.invoiceNumber, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.error.withValues(alpha: 0.12);
    // الحبر يُقاس على الخلفية المصبوغة فعلاً لا على الكرت العادي.
    final ink = PicPosText.readableOn(context, AppColors.error,
        on: Color.alphaBlend(tint, context.picposCard));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.arrowUUpLeft, size: 16, color: ink),
          const SizedBox(width: 8),
          Text(tr('وضع المرتجع'), style: PicPosText.v(context, 13, color: ink)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              invoiceNumber,
              overflow: TextOverflow.ellipsis,
              style: PicPosText.v(context, 13, color: ink),
            ),
          ),
          if (onCancel != null)
            TextButton.icon(
              key: const ValueKey('picpos_return_cancel_button'),
              onPressed: onCancel,
              icon: const Icon(PhosphorIconsBold.x, size: 14),
              label: Text(tr('إلغاء المرتجع'),
                  style: PicPosText.v(context, 12, color: ink)),
              style: TextButton.styleFrom(
                foregroundColor: ink,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
            ),
        ],
      ),
    );
  }
}

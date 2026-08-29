import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
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

  const PicPosReturnModeBanner({super.key, required this.invoiceNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.arrowUUpLeft,
              size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Text('وضع المرتجع',
              style: PicPosText.v(context, 13, color: AppColors.error)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              invoiceNumber,
              overflow: TextOverflow.ellipsis,
              style: PicPosText.v(context, 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

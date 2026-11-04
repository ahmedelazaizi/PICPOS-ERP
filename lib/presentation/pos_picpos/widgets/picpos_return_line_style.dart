import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'picpos_pos_text.dart';

/// مظهرُ سطرِ **المرتجع بلا فاتورة** في جدول السلّة (بند ٤).
///
/// في ملفٍّ مستقلّ حفاظاً على سقف حجم `picpos_items_table.dart`. السطرُ العاديُّ
/// يعود بنفس ما كان يرسمه الجدولُ حرفاً بحرف.
bool isReturnLine(CartItemEntity item) =>
    item.itemType == CartItemType.returned;

/// لونُ خلفيّة الصفّ: أحمرُ خفيفٌ للمرتجع، وإلا تلوينُ الصفوف المعتاد.
Color picposRowColor(
  BuildContext context,
  CartItemEntity item, {
  required bool isSelected,
  required int index,
}) {
  if (isSelected) return AppColors.primary.withValues(alpha: 0.10);
  if (isReturnLine(item)) return AppColors.error.withValues(alpha: 0.09);
  return index.isEven ? context.picposCard : context.picposField;
}

/// اسمُ الصنف، ومعه وسمُ «مرتجع» الأحمر حين يكون السطرُ مرتجعاً.
class PicPosLineName extends StatelessWidget {
  final CartItemEntity item;
  final String suffix;
  final double fontSize;

  const PicPosLineName({
    super.key,
    required this.item,
    required this.suffix,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final name = Text(
      '${item.productName}$suffix',
      overflow: TextOverflow.ellipsis,
      style: PicPosText.v(context, fontSize,
          color: isReturnLine(item)
              ? PicPosText.readableOn(context, AppColors.error)
              : null),
    );
    if (!isReturnLine(item)) return name;
    return Row(
      children: [
        Container(
          key: const ValueKey('return-line-tag'),
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            // أحمر أغمق من `AppColors.error` ليبلغ نصُّه الأبيض ٤٫٥:١ (كان ٣٫٧٦).
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(tr('مرتجع'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
        Expanded(child: name),
      ],
    );
  }
}

/// مجموعُ السطر كما يُعرض: المرتجعُ بإشارة ناقص (هو مال يخرج لا يدخل).
String picposLineTotalText(CartItemEntity item) {
  final text = NumberUtils.formatCurrency(item.totalBeforeTax);
  return isReturnLine(item) ? '-$text' : text;
}

/// حالةُ الجدول الفارغ — منقولةٌ كما هي من `picpos_items_table.dart`.
class PicPosItemsEmptyState extends StatelessWidget {
  const PicPosItemsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.barcode,
              size: 44, color: context.picposMuted),
          const SizedBox(height: 10),
          Text(
            tr('امسح باركود أو اكتب كود الصنف للبدء'),
            style: PicPosText.l(context, 14),
          ),
        ],
      ),
    );
  }
}

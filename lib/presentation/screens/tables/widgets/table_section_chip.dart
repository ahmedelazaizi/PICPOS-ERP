import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// شريحةُ اسم القسم على بطاقة الطاولة — صغيرةٌ، بلونٍ محايدٍ من الثيم (لا لونَ
/// حالةٍ فتختلط بدلالة الحالة)، وتُقصّ بنقاطٍ عند الضيق. مستقلّةٌ ليعيد
/// استعمالَها تصميمُ اللوحة (P5).
class TableSectionChip extends StatelessWidget {
  const TableSectionChip({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr('القسم: {p0}', {'p0': name}),
      child: Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        constraints: const BoxConstraints(maxWidth: 110),
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.mapPin, size: 9, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

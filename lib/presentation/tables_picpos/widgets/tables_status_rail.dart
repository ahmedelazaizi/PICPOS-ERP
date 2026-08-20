import 'package:flutter/material.dart';

import '../../../core/design_system/spacing.dart';
import '../../../domain/models/table_status.dart';
import '../../picpos_shell/picpos_stat_tile.dart';
import '../../screens/tables/widgets/table_status_info.dart';

/// عدُّ الطاولات لكلِّ حالة — **بمدخلٍ لكلِّ حالةٍ ولو كان صفراً**.
///
/// إخفاءُ الصفر يجعل العمودَ يقفز طولاً كلّما تبدّلت الطاولات، ويخفي معلومةً
/// حقيقيّة: «لا طاولةَ خارجَ الخدمة» خبرٌ لا فراغ.
Map<String, int> countByStatus(List<String> statuses) {
  final counts = {for (final s in TableStatus.all) s: 0};
  for (final s in statuses) {
    if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
  }
  return counts;
}

class TablesStatusRail extends StatelessWidget {
  const TablesStatusRail({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;

  /// الحالةُ المرشَّحُ بها — `null` تعني «الكلّ».
  final String? selected;

  final ValueChanged<String?> onSelect;

  /// مفتاحُ بطاقةِ حالةٍ بعينها — لاختبارِ حالةِ الاختيار بلا فتح شاشة.
  static ValueKey<String> tileKey(String status) =>
      ValueKey<String>('tablesStatusTile_$status');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in TableStatus.all)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _StatusTile(
              key: tileKey(status),
              status: status,
              count: counts[status] ?? 0,
              isSelected: selected == status,
              onTap: () => onSelect(selected == status ? null : status),
            ),
          ),
      ],
    );
  }
}

/// بطاقةُ حالةٍ واحدة — **ترسم اختيارَها**.
///
/// كان العمودُ يستقبل `selected` ولا يستعمله في الرسم إطلاقاً: فالمستخدمُ
/// ينقر «متاحة» فيُرشَّح المحتوى ولا يرى أثراً في العمود، ثم ينقر أخرى فلا
/// يدري أيَّهما فعّالة. حلقةُ التغذية الراجعة هي نصفُ المرشِّح.
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    super.key,
    required this.status,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String status;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = tableStatusColor(status);
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // الإطارُ شفّافٌ لا غائب: لولا ذلك لتغيّر مقاسُ البطاقة عند
            // الاختيار فيقفز العمودُ كلّه.
            border: Border.all(
              color: isSelected ? accent : Colors.transparent,
              width: 2,
            ),
            color: isSelected ? accent.withValues(alpha: 0.10) : null,
          ),
          child: PicPosStatTile(
            label: tableStatusLabel(status),
            value: '$count',
            accent: accent,
          ),
        ),
      ),
    );
  }
}

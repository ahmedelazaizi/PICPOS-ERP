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

  /// مفتاحُ بطاقةِ «عرض الكل» — نفسُ نمط [tileKey] بمعرِّفٍ لا يتقاطع مع أيّ
  /// حالةٍ حقيقيّة في [TableStatus.all].
  static const String allKey = 'all';

  /// لونُ بطاقة «عرض الكل» — رماديٌّ محايدٌ لا يُشبه لونَ أيّ حالةٍ حقيقيّة،
  /// نفسُ الرمادي المستعمَل لمدخل «الكل» في `tables_filter_bar.dart`
  /// (الشاشةُ القديمة) فلا يُخترَع لونٌ ثالث لنفس المعنى.
  static const Color _allAccent = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    // مجموعُ الطاولات — لا `TableStatus.all.length` ولا عددُ الطاولات
    // الكليّ من مصدرٍ آخر، بل مجموعُ ما تعرضه البطاقاتُ فعلاً، فلا يتباعد
    // الرقمان أبداً.
    final total = counts.values.fold<int>(0, (sum, c) => sum + c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in TableStatus.all)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _StatusTile(
              key: tileKey(status),
              label: tableStatusLabel(status),
              accent: tableStatusColor(status),
              count: counts[status] ?? 0,
              isSelected: selected == status,
              onTap: () => onSelect(selected == status ? null : status),
            ),
          ),
        // آخرُ بطاقةٍ في العمود — بعد الحالات الخمس كما في نصّ المالك.
        // `selected == null` تعني «الكلّ» (راجع تعليقَ [selected])، والنقرُ
        // عليها يُعيد المرشِّحَ إلى الكلّ بلا تبديلٍ — فهي مخرجٌ لا حالة.
        _StatusTile(
          key: tileKey(allKey),
          label: 'عرض الكل',
          accent: _allAccent,
          count: total,
          isSelected: selected == null,
          onTap: () => onSelect(null),
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
    required this.label,
    required this.accent,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            label: label,
            value: '$count',
            accent: accent,
          ),
        ),
      ),
    );
  }
}

// شريطُ مرشِّحات الشاشة: الفترة + الفرع + تحديث. نفسُ اتّفاقيّات شاشة القوائم
// المالية (مزوّدُ `branchListProvider` وحجبُ الفروع خارج نطاق المستخدم) على
// لبنة `PicPosFilterStrip` وبرموز الثيم.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/i18n/tr.dart';
import '../../data/providers/manufacturing_providers.dart' show branchListProvider;
import '../../data/providers/providers.dart';
import '../picpos_shell/picpos_filter_strip.dart';
import '../picpos_shell/picpos_surface.dart';

class FinancialFilterBar extends ConsumerWidget {
  const FinancialFilterBar({
    super.key,
    required this.from,
    required this.to,
    required this.branchId,
    required this.onPickRange,
    required this.onBranchChanged,
    required this.onRefresh,
  });

  final DateTime from;
  final DateTime to;
  final int? branchId;
  final VoidCallback onPickRange;
  final ValueChanged<int?> onBranchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('yyyy-MM-dd', 'en');
    // نطاقٌ لم يُحسَم (تحميل/خطأ) ⇒ لا أسماءَ فروع. النطاقُ المحسوم بصلاحيةٍ
    // كاملة (`hasFullAccess`) وحدَه يعني «كل الفروع»؛ وغيرُه يُرشَّح بـ`isAllowed`.
    final scope = ref.watch(branchScopeProvider).asData?.value;
    final branches = ref.watch(branchListProvider).asData?.value ?? const [];
    final visible = [
      if (scope != null)
        for (final b in branches)
          if (scope.isAllowed(b.id)) b,
    ];

    return PicPosFilterStrip(
      children: [
        PicPosFilterPill(
          icon: Icons.date_range,
          label: '${fmt.format(from)}  →  ${fmt.format(to)}',
          tabular: true,
          onTap: onPickRange,
        ),
        if (visible.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: context.picposHairline),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: visible.any((b) => b.id == branchId) ? branchId : null,
                hint: Text(tr('الفرع')),
                icon: Icon(Icons.expand_more, color: context.picposMuted),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(tr('كل الفروع')),
                  ),
                  for (final b in visible)
                    DropdownMenuItem<int?>(
                      value: b.id,
                      child: Text(trData(b.name)),
                    ),
                ],
                onChanged: onBranchChanged,
              ),
            ),
          ),
        IconButton(
          icon: Icon(Icons.refresh, color: context.picposBrandInk),
          tooltip: tr('تحديث البيانات'),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

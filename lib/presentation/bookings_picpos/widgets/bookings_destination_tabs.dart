import 'package:ural_erp/core/i18n/tr.dart';
// شريطُ وجهاتِ الحجوزات — ثمانٍ، وبحثٌ سريعٌ بجوارها.
//
// ⚠️ **قابلٌ للتمرير أفقيّاً عن قصد**: ثمانِ حبّاتٍ بنصوصٍ عربيّةٍ تتجاوز
// عرضَ البطاقة على شاشةٍ ١٢٨٠، والصفُّ الثابتُ كان سيفيض شريطاً أصفرَ —
// وهو نفسُ صنفِ الفيض الذي أمسكه اختبارُ التركيب في عمود الوقت.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_booking_view.dart';

class BookingsDestinationTabs extends ConsumerWidget {
  const BookingsDestinationTabs({super.key});

  static const _icons = <BookingsDestination, IconData>{
    BookingsDestination.board: PhosphorIconsBold.calendarDots,
    BookingsDestination.waitlist: PhosphorIconsBold.hourglassMedium,
    BookingsDestination.resources: PhosphorIconsBold.users,
    BookingsDestination.services: PhosphorIconsBold.scissors,
    BookingsDestination.customers: PhosphorIconsBold.addressBook,
    BookingsDestination.reminders: PhosphorIconsBold.bellRinging,
    BookingsDestination.reports: PhosphorIconsBold.chartBar,
    BookingsDestination.settings: PhosphorIconsBold.gear,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(bookingsDestinationProvider);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in BookingsDestination.values) ...[
                    _Tab(
                      label: d.label,
                      icon: _icons[d]!,
                      selected: d == current,
                      onTap: () =>
                          ref.read(bookingsDestinationProvider.notifier).set(d),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 300,
            height: 36,
            child: TextField(
              onChanged: (v) => ref.read(bookingsQueryProvider.notifier).set(v),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.white10
                    : const Color(0xFFF4F7FC),
                hintText: tr('بحث سريع (اسم، هاتف، خدمة...)'),
                hintStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass,
                    size: 15, color: AppColors.textMuted),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 34),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.primary : theme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                tr(label),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

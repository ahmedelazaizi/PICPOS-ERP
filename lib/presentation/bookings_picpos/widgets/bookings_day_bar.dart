import 'package:picpos_erp/core/i18n/tr.dart';
// شريطُ اليوم — سهمان واسمُ اليوم و«اليوم» للعودة.
//
// ⚠️ **والسهمان مقلوبان عن الحدس في RTL**: «التالي» يقع يساراً و«السابق»
// يميناً، والأيقونةُ تتبع الاتّجاهَ لا الاسم. وسهمٌ يشير عكسَ ما يفعل
// أسوأُ من غياب السهم.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../screens/bookings_picpos_screen.dart'
    show bookingDayLabel, bookingTabularFigures;

class BookingsDayBar extends StatelessWidget {
  const BookingsDayBar({
    super.key,
    required this.day,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = bookingDayLabel(day) == 'اليوم';

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _arrow(context, PhosphorIconsBold.caretRight, onNext, tr('اليوم التالي')),
          const SizedBox(width: 12),
          const Icon(PhosphorIconsBold.calendarBlank,
              size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            bookingDayLabel(day),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              fontFeatures: bookingTabularFigures,
            ),
          ),
          const SizedBox(width: 12),
          _arrow(context, PhosphorIconsBold.caretLeft, onPrev, tr('اليوم السابق')),
          if (!isToday) ...[
            const SizedBox(width: 14),
            TextButton.icon(
              onPressed: onToday,
              icon: const Icon(PhosphorIconsBold.arrowCounterClockwise,
                  size: 14),
              label:  Text(tr('اليوم')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _arrow(
    BuildContext context,
    IconData icon,
    VoidCallback onTap,
    String tooltip,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 13, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

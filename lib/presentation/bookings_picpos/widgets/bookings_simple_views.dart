// ثلاثُ وجهاتٍ تقرأ ما هو مبنيٌّ فعلاً: الانتظارُ والمواردُ والخدمات.
//
// ⚠️ **ولا حقلَ يُخترَع**: التصميمُ يعرض لقائمة الانتظار «الوقتَ المرغوب»
// و«منذ متى»، ولا عمودَ للأوّل في `Bookings`. فيُعرَض ما يوجد (الملاحظةُ
// ووقتُ الإنشاء) ويُترك ما لا يوجد — وحقلٌ مُختلَقٌ من فراغٍ يبدو بياناً
// وهو ليس كذلك.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../screens/bookings_picpos_screen.dart';

// ═════════════════════════ قائمة الانتظار ═════════════════════════

/// حجزُ اليومِ **بلا موردٍ مُسنَد** — هذا هو نموذجُ «قائمة الانتظار» في
/// المحرِّك (لا جدولَ مستقلّ). فمن لم يُسنَد بعدُ ينتظر إسناداً.
class BookingsWaitlistView extends StatelessWidget {
  const BookingsWaitlistView({super.key, required this.rows});

  final List<BookingBoardRow> rows;

  @override
  Widget build(BuildContext context) {
    final waiting =
        rows.where((r) => r.resourceId == null && r.occupiesTime).toList();

    if (waiting.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.hourglassMedium,
        title: 'لا أحدَ في قائمة الانتظار',
        hint: 'كلُّ حجوزات اليوم مُسنَدةٌ إلى موظَّفٍ أو مورد.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: waiting.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _WaitCard(row: waiting[i]),
    );
  }
}

class _WaitCard extends StatelessWidget {
  const _WaitCard({required this.row});

  final BookingBoardRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = bookingColorOf(row.serviceColorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      // ⚠️ لا حافّةَ ملوّنةٌ من جهةٍ واحدةٍ مع `borderRadius`: فلاتر ترمي
      // «a borderRadius can only be given on borders with uniform colors».
      // فالشريطُ المميِّزُ عنصرٌ مستقلٌّ داخلَ الصفّ — نفسُ حلّ عمود الخدمة
      // في اللوحة.
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsetsDirectional.only(end: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    row.customerPhone ?? '—',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      fontFeatures: bookingTabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: _labelled('الخدمة المطلوبة', row.serviceName, color),
          ),
          SizedBox(
            width: 150,
            child: _labelled('الموعد', bookingTimeLabel(row.startsAt), null),
          ),
          SizedBox(
            width: 200,
            // ⚠️ لا «الوقتُ المرغوب» ولا «منذ متى»: لا عمودَ لهما في
            // `Bookings`. فتُعرَض الملاحظةُ الموجودةُ ولا يُختلَق حقل.
            child: _labelled('ملاحظة', row.notes?.trim().isNotEmpty == true
                ? row.notes!
                : '—', null),
          ),
        ],
      ),
    );
  }

  Widget _labelled(String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════ الموارد ═════════════════════════

class BookingsResourcesView extends ConsumerWidget {
  const BookingsResourcesView({super.key, required this.rows});

  final List<BookingBoardRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingResourcesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => PicPosEmptyState(
        icon: PhosphorIconsBold.warningCircle,
        title: 'تعذّر تحميل الموارد',
        hint: '$e',
      ),
      data: (list) {
        if (list.isEmpty) {
          return const PicPosEmptyState(
            icon: PhosphorIconsBold.users,
            title: 'لا موارد معرَّفة',
            hint: 'أضف موظَّفاً أو جهازاً ليمكن إسنادُ الحجوزات إليه.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 340,
            mainAxisExtent: 132,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final r = list[i];
            return _ResourceCard(
              name: r.name,
              role: r.role,
              kind: r.kind,
              colorHex: r.colorHex,
              load: resourceDayLoad(
                resourceId: r.id,
                rows: rows,
                shiftStartMinutes: r.shiftStartMinutes,
                shiftEndMinutes: r.shiftEndMinutes,
              ),
              shiftLabel: _shiftLabel(r.shiftStartMinutes, r.shiftEndMinutes),
            );
          },
        );
      },
    );
  }

  /// «10:00 ص — 08:00 م» أو «بلا ورديّة محدّدة».
  static String _shiftLabel(int? start, int? end) {
    if (start == null || end == null) return 'بلا ورديّة محدّدة';
    return '${_hhmm(start)} — ${_hhmm(end)}';
  }

  static String _hhmm(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 < 12 ? 'ص' : 'م';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '${h12.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')} $period';
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.name,
    required this.role,
    required this.kind,
    required this.colorHex,
    required this.load,
    required this.shiftLabel,
  });

  final String name;
  final String? role;
  final String kind;
  final String colorHex;
  final ResourceDayLoad load;
  final String shiftLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = bookingColorOf(colorHex);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  border: Border.all(color: color, width: 1.5),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initialsFor(name),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      role ?? (kind == 'device' ? 'مورد — جهاز' : 'موظَّف'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            shiftLabel,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              fontFeatures: bookingTabularFigures,
            ),
          ),
          const Spacer(),
          // ⚠️ ‏`Flexible` على كلّ عمود: العناوينُ العربيّةُ («حجوزات اليوم»
          // و«إيراد متوقع») مع مبلغٍ بثلاث خاناتٍ ورمزِ عملةٍ تتجاوز عرضَ
          // البطاقة — قِيس فيضاً ٣٧ بكسل قبل هذا الحزام.
          Row(
            children: [
              Flexible(
                child:
                    _mini('حجوزات اليوم', '${load.bookings}', AppColors.primary),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _mini(
                  'إيراد متوقع',
                  load.revenue.toStringAsFixed(AppConstants.decimalPlaces),
                  color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${load.loadPct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: bookingTabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: load.loadPct / 100,
              minHeight: 5,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: bookingTabularFigures,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════ الخدمات ═════════════════════════

class BookingsServicesView extends ConsumerWidget {
  const BookingsServicesView({super.key, required this.rows});

  final List<BookingBoardRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingServicesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => PicPosEmptyState(
        icon: PhosphorIconsBold.warningCircle,
        title: 'تعذّر تحميل الخدمات',
        hint: '$e',
      ),
      data: (list) {
        if (list.isEmpty) {
          return const PicPosEmptyState(
            icon: PhosphorIconsBold.scissors,
            title: 'لا خدمات معرَّفة',
            hint: 'أضف خدمةً بمدّتها وسعرها ليمكن الحجزُ عليها.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 124,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final s = list[i];
            final count =
                rows.where((r) => r.serviceId == s.id && r.occupiesTime).length;
            return _ServiceCard(
              name: s.name,
              durationMinutes: s.durationMinutes,
              bufferMinutes: s.bufferMinutes,
              price: s.price,
              colorHex: s.colorHex,
              todayCount: count,
              // ⚠️ خدمةٌ بلا صنفٍ مربوطٍ **لا تُفوتَر** — والحارسُ في المحرّك
              // يرفضها. فيُقال ذلك هنا قبل أن يصطدم به المستخدمُ عند التحويل.
              linked: s.productId != null,
            );
          },
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.name,
    required this.durationMinutes,
    required this.bufferMinutes,
    required this.price,
    required this.colorHex,
    required this.todayCount,
    required this.linked,
  });

  final String name;
  final int durationMinutes;
  final int bufferMinutes;
  final double price;
  final String colorHex;
  final int todayCount;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = bookingColorOf(colorHex);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (!linked)
                const Tooltip(
                  message: 'غير مربوطة بصنف — لا يمكن تفويترُ حجوزها',
                  child: Icon(PhosphorIconsBold.linkBreak,
                      size: 15, color: AppColors.warning),
                ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Flexible(child: _stat('المدة', '$durationMinutes د')),
              const SizedBox(width: 10),
              Flexible(child: _stat('فاصل', '$bufferMinutes د')),
              const SizedBox(width: 10),
              // السعرُ يأخذ الباقيَ: رمزُ العملةِ ودقّتُها يتبدّلان بالتنصيبة
              // (ق-١)، فعرضٌ ثابتٌ هنا يفيض عند عملةٍ أطولَ رمزاً.
              Expanded(
                flex: 2,
                child: _stat(
                  'السعر',
                  '${price.toStringAsFixed(AppConstants.decimalPlaces)} '
                      '${AppConstants.currencySymbol}',
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'حجوزات اليوم: $todayCount',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              fontFeatures: bookingTabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: bookingTabularFigures,
          ),
        ),
      ],
    );
  }
}

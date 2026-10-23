import 'package:ural_erp/core/i18n/tr.dart';
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
import '../../../core/permissions/permission_codes.dart';
import 'booking_catalog_editors.dart';
import 'booking_permission_gates.dart';

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
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.hourglassMedium,
        title: tr('لا أحدَ في قائمة الانتظار'),
        hint: tr('كلُّ حجوزات اليوم مُسنَدةٌ إلى موظَّفٍ أو مورد.'),
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
            child: _labelled(tr('الخدمة المطلوبة'), row.serviceName, color),
          ),
          SizedBox(
            width: 150,
            child: _labelled(tr('الموعد'), bookingTimeLabel(row.startsAt), null),
          ),
          SizedBox(
            width: 200,
            // ⚠️ لا «الوقتُ المرغوب» ولا «منذ متى»: لا عمودَ لهما في
            // `Bookings`. فتُعرَض الملاحظةُ الموجودةُ ولا يُختلَق حقل.
            child: _labelled(tr('ملاحظة'), row.notes?.trim().isNotEmpty == true
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

/// بطاقةُ «أضف» في ذيل الشبكة — أقربُ ما تكون إلى موضع التفكير بالإضافة.
class _AddCard extends StatelessWidget {
  const _AddCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: DottedBorderBox(
        color: theme.dividerColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// إطارٌ خافتٌ يميّز «أضف» عن البطاقات الحقيقيّة بلا رسمِ خطٍّ متقطّعٍ يدويّاً.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(13),
          color: AppColors.primary.withValues(alpha: .04),
        ),
        child: child,
      );
}

// فتحُ محرّري الكتالوج يمرّ ببوّابة `bookings_resources_manage` /
// `bookings_services_manage` (فتحُ الشاشة لا يمنح التعديل).
Future<void> _editResource(WidgetRef ref, BuildContext context,
        {BookingResource? existing}) =>
    runBookingAction(
        ref,
        context,
        PermissionCodes.bookingsResourcesManage,
        tr('إدارة الموارد'),
        () => showResourceEditor(context, existing: existing));

Future<void> _editService(WidgetRef ref, BuildContext context,
        {BookingService? existing}) =>
    runBookingAction(
        ref,
        context,
        PermissionCodes.bookingsServicesManage,
        tr('إدارة الخدمات'),
        () => showServiceEditor(context, existing: existing));

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
        title: tr('تعذّر تحميل الموارد'),
        hint: '$e',
      ),
      data: (list) {
        if (list.isEmpty) {
          return PicPosEmptyState(
            icon: PhosphorIconsBold.users,
            title: tr('لا موارد معرَّفة'),
            hint: tr('أضف موظَّفاً أو جهازاً ليمكن إسنادُ الحجوزات إليه.'),
            action: FilledButton.icon(
              onPressed: () => _editResource(ref, context),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label:  Text(tr('مورد جديد')),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 340,
            mainAxisExtent: 148,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            // البطاقةُ الأخيرةُ زرُّ إضافة — أقربُ ما يكون إلى المكان الذي
            // يفكّر فيه المستخدمُ بالإضافة.
            if (i == list.length) {
              return _AddCard(
                label: tr('مورد جديد'),
                icon: PhosphorIconsBold.userPlus,
                onTap: () => _editResource(ref, context),
              );
            }
            final r = list[i];
            return _ResourceCard(
              onEdit: () => _editResource(ref, context, existing: r),
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
    if (start == null || end == null) return tr('بلا ورديّة محدّدة');
    return '${_hhmm(start)} — ${_hhmm(end)}';
  }

  static String _hhmm(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 < 12 ? tr('ص') : tr('م');
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
    required this.onEdit,
  });

  final VoidCallback onEdit;
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
                      role ?? (kind == 'device' ? tr('مورد — جهاز') : tr('موظَّف')),
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
              IconButton(
                onPressed: onEdit,
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 15),
                tooltip: tr('تعديل'),
                visualDensity: VisualDensity.compact,
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
                    _mini(tr('حجوزات اليوم'), '${load.bookings}', AppColors.primary),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _mini(
                  tr('إيراد متوقع'),
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
        title: tr('تعذّر تحميل الخدمات'),
        hint: '$e',
      ),
      data: (list) {
        if (list.isEmpty) {
          return PicPosEmptyState(
            icon: PhosphorIconsBold.scissors,
            title: tr('لا خدمات معرَّفة'),
            hint: tr('أضف خدمةً بمدّتها وسعرها ليمكن الحجزُ عليها.'),
            action: FilledButton.icon(
              onPressed: () => _editService(ref, context),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label:  Text(tr('خدمة جديدة')),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 140,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == list.length) {
              return _AddCard(
                label: tr('خدمة جديدة'),
                icon: PhosphorIconsBold.plus,
                onTap: () => _editService(ref, context),
              );
            }
            final s = list[i];
            final count =
                rows.where((r) => r.serviceId == s.id && r.occupiesTime).length;
            return _ServiceCard(
              onEdit: () => _editService(ref, context, existing: s),
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
    required this.onEdit,
    required this.name,
    required this.durationMinutes,
    required this.bufferMinutes,
    required this.price,
    required this.colorHex,
    required this.todayCount,
    required this.linked,
  });

  final VoidCallback onEdit;
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
                 Tooltip(
                  message: tr('غير مربوطة بصنف — لا يمكن تفويترُ حجوزها'),
                  child: const Icon(PhosphorIconsBold.linkBreak,
                      size: 15, color: AppColors.warning),
                ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 15),
                tooltip: tr('تعديل / ربط بصنف'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Flexible(child: _stat(tr('المدة'), tr('{durationMinutes} د', {'durationMinutes': durationMinutes}))),
              const SizedBox(width: 10),
              Flexible(child: _stat(tr('فاصل'), tr('{bufferMinutes} د', {'bufferMinutes': bufferMinutes}))),
              const SizedBox(width: 10),
              // السعرُ يأخذ الباقيَ: رمزُ العملةِ ودقّتُها يتبدّلان بالتنصيبة
              // (ق-١)، فعرضٌ ثابتٌ هنا يفيض عند عملةٍ أطولَ رمزاً.
              Expanded(
                flex: 2,
                child: _stat(
                  tr('السعر'),
                  '${price.toStringAsFixed(AppConstants.decimalPlaces)} '
                      '${AppConstants.currencySymbol}',
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('حجوزات اليوم: {todayCount}', {'todayCount': todayCount}),
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

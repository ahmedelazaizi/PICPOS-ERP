import 'package:picpos_erp/core/i18n/tr.dart';
// الوجهاتُ الأربعُ الباقية: العملاءُ والتذكيراتُ والتقاريرُ والإعدادات.
import '../../../data/providers/feature_settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../screens/bookings_picpos_screen.dart';

String _money(double v) =>
    '${v.toStringAsFixed(AppConstants.decimalPlaces)} '
    '${AppConstants.currencySymbol}';

// ═════════════════════════ العملاء ═════════════════════════

class BookingsCustomersView extends ConsumerWidget {
  const BookingsCustomersView({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(bookingCustomersProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PicPosEmptyState(
            icon: PhosphorIconsBold.warningCircle,
            title: tr('تعذّر تحميل العملاء'),
            hint: '$e',
          ),
          data: (all) {
            final q = query.trim().toLowerCase();
            final list = q.isEmpty
                ? all
                : all
                    .where((c) =>
                        c.name.toLowerCase().contains(q) ||
                        (c.phone ?? '').toLowerCase().contains(q))
                    .toList();

            if (list.isEmpty) {
              return  PicPosEmptyState(
                icon: PhosphorIconsBold.addressBook,
                title: tr('لا عملاءَ بعد'),
                hint: tr('يظهر هنا كلُّ من انعقد له حجزٌ — والملغى ليس زيارة.'),
              );
            }

            return Column(
              children: [
                Container(
                  height: 34,
                  color: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child:  Row(
                    children: [
                      Expanded(flex: 3, child: _Head(tr('العميل'))),
                      Expanded(flex: 2, child: _Head(tr('الهاتف'))),
                      SizedBox(width: 92, child: _Head(tr('الزيارات'))),
                      SizedBox(width: 130, child: _Head(tr('إجمالي الإنفاق'))),
                      Expanded(flex: 2, child: _Head(tr('الخدمة المفضلة'))),
                      SizedBox(width: 110, child: _Head(tr('آخر زيارة'))),
                      SizedBox(width: 92, child: _Head(tr('الفئة'))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemExtent: 48,
                    itemBuilder: (_, i) =>
                        _CustomerRow(row: list[i], divider: theme.dividerColor),
                  ),
                ),
              ],
            );
          },
        );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.row, required this.divider});

  final BookingCustomerRow row;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final tier = row.tier;
    final color = switch (tier) {
      BookingCustomerTier.platinum => AppColors.booking,
      BookingCustomerTier.gold => AppColors.warning,
      BookingCustomerTier.silver => AppColors.info,
      BookingCustomerTier.bronze => AppColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                row.phone ?? '—',
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: bookingTabularFigures,
                ),
              ),
            ),
          ),
          SizedBox(width: 92, child: _num('${row.visits}')),
          SizedBox(width: 130, child: _num(_money(row.spend))),
          Expanded(
            flex: 2,
            child: Text(
              row.favouriteService ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              row.lastVisit == null
                  ? '—'
                  : bookingDayLabel(row.lastVisit!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFeatures: bookingTabularFigures,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  border: Border.all(color: color.withValues(alpha: .35)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tr(tier.label),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(String v) => Text(
        v,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          fontFeatures: bookingTabularFigures,
        ),
      );
}

// ═════════════════════════ التذكيرات ═════════════════════════

class BookingsRemindersView extends ConsumerWidget {
  const BookingsRemindersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(bookingRemindersProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PicPosEmptyState(
            icon: PhosphorIconsBold.warningCircle,
            title: tr('تعذّر تحميل التذكيرات'),
            hint: '$e',
          ),
          data: (list) => list.isEmpty
              ?  PicPosEmptyState(
                  icon: PhosphorIconsBold.bellRinging,
                  title: tr('لا تذكيرات مجدولة'),
                  hint: tr('يُجدوَل التذكيرُ مع الحجز، ويُفتَح رابطُه من هنا.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ReminderCard(row: list[i]),
                ),
        );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard({required this.row});

  final BookingReminderRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = row.isDue(DateTime.now());
    final color = due ? AppColors.warning : AppColors.textMuted;

    final message = bookingReminderMessage(
      customerName: row.customerName,
      serviceName: row.serviceName,
      timeLabel: bookingTimeLabel(row.bookingStartsAt),
    );
    // رمزُ الدولة من الإعداد المشترك — نفسُ ما يستعمله إرسالُ الفواتير
    // وكشوفِ الحساب. وغيابُه يعني «لا رابط»، وهو أصدقُ من رابطٍ يفتح
    // صفحةَ «الرقمُ غيرُ صالح».
    final countryCode =
        ref.watch(whatsAppCountryCodeProvider).asData?.value ?? '';
    final link = whatsappReminderLink(
      phone: row.customerPhone,
      message: message,
      defaultCountryCode: countryCode,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            due ? PhosphorIconsBold.bellRinging : PhosphorIconsBold.bell,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    row.customerPhone ?? tr('بلا رقم'),
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
            width: 150,
            child: _kv(tr('موعد الحجز'), bookingTimeLabel(row.bookingStartsAt)),
          ),
          SizedBox(
            width: 170,
            child: _kv(
              tr('القناة والتوقيت'),
              tr('{p0} · قبل {p1} دقيقة', {'p0': bookingReminderChannelLabel(row.channel), 'p1': row.offsetMinutes}),
            ),
          ),
          SizedBox(
            width: 130,
            child: _kv(tr('الحالة'), bookingReminderStateLabel(row.state)),
          ),
          // ⚠️ زرٌّ معطَّلٌ حين لا رابطَ ممكن (‏لا رقمَ أو رقمٌ بلا أرقام) —
          // رابطٌ يفتح محادثةً فارغةً يُوهم الموظَّفَ أنه أرسل ولم يُرسِل.
          FilledButton.icon(
            onPressed: link == null
                ? null
                : () async {
                    await launchUrl(Uri.parse(link),
                        mode: LaunchMode.externalApplication);
                    // ⚠️ الختمُ بعد الفتح وإلّا بقي الصفُّ `scheduled` أبداً:
                    // تتراكم القائمةُ بما عُولج فعلاً ولا يميّز المضيفُ ما
                    // أرسله ممّا لم يُرسله.
                    final auth = ref.read(authProvider);
                    await ref
                        .read(databaseProvider)
                        .markBookingReminderOpened(row.id,
                            userId: auth.user?.id);
                  },
            icon: const Icon(PhosphorIconsBold.paperPlaneTilt, size: 14),
            label:  Text(tr('فتح الرابط')),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              textStyle:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            k,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      );
}

// ═════════════════════════ التقارير ═════════════════════════

/// تقاريرُ اليوم — **مشتقّةٌ من صفوف اللوحة نفسِها**.
///
/// ⚠️ ولا استعلامَ ثانٍ: تقريرٌ يخالف الجدولَ الذي فوقه يُفقد الثقةَ في
/// الاثنين معاً. ومداه يومٌ واحدٌ صراحةً — عنوانُه يقوله فلا يُظَنّ شهريّاً.
class BookingsReportsView extends StatelessWidget {
  const BookingsReportsView({super.key, required this.rows, required this.day});

  final List<BookingBoardRow> rows;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final held = rows.where((r) => r.occupiesTime).toList();
    if (held.isEmpty) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.chartBar,
        title: tr('لا بياناتٍ لهذا اليوم'),
        hint: tr('التقاريرُ تُشتقّ من حجوزات اليوم المعروض.'),
      );
    }

    final byService = <String, ({int count, double revenue, String color})>{};
    for (final r in held) {
      final cur = byService[r.serviceName];
      byService[r.serviceName] = (
        count: (cur?.count ?? 0) + 1,
        revenue: (cur?.revenue ?? 0) + r.servicePrice,
        color: r.serviceColorHex,
      );
    }
    final entries = byService.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    final maxRevenue = entries.first.value.revenue;
    final total = held.fold<double>(0, (s, r) => s + r.servicePrice);
    final deposits = rows.fold<double>(0, (s, r) => s + r.depositAmount);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          tr('تقرير {p0}', {'p0': bookingDayLabel(day)}),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _repCard(tr('حجوزات منعقدة'), '${held.length}',
                    AppColors.primary)),
            const SizedBox(width: 10),
            Expanded(
                child: _repCard(tr('إيراد متوقع'), _money(total),
                    AppColors.success)),
            const SizedBox(width: 10),
            Expanded(
                child: _repCard(tr('عرابين مقبوضة'), _money(deposits),
                    AppColors.info)),
          ],
        ),
        const SizedBox(height: 14),
         Text(tr('الخدماتُ الأعلى إيراداً'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _bar(
              context,
              name: e.key,
              count: e.value.count,
              revenue: e.value.revenue,
              pct: maxRevenue <= 0 ? 0 : e.value.revenue / maxRevenue,
              color: bookingColorOf(e.value.color),
            ),
          ),
      ],
    );
  }

  Widget _repCard(String label, String value, Color color) => Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    )),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: bookingTabularFigures,
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _bar(
    BuildContext context, {
    required String name,
    required int count,
    required double revenue,
    required double pct,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$count · ${_money(revenue)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: bookingTabularFigures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct.clamp(0, 1),
            minHeight: 6,
            backgroundColor: theme.dividerColor,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// شاشةُ الحجوزات بهويّة PicPos — تصميمُ 2026-08-22.
//
// ═══ المرحلةُ الأولى: اللوحة ═══
//
// التصميمُ صفحةٌ واحدةٌ بثمانِ وجهاتٍ (`board` · `wait` · `res` · `svc` ·
// `cust` · `rem` · `rep` · `set`). وهذا الملفُّ يبني **اللوحةَ** — الوجهةَ
// الأولى والوحيدةَ التي تعرض حجوزاً فعليّةً — ويترك البقيّةَ لمراحلَ تالية.
// والوجهاتُ ليست شاشاتٍ منفصلةً بل تبديلُ محتوىً داخلَ نفس الإطار، فبناؤها
// تباعاً لا يُعيد كتابة شيء.
//
// ⚠️ **ولا استيرادَ لـ`data/database` هنا**: حارسُ
// `presentation_db_import_guard` يمنعه على أيّ ملفِّ عرضٍ جديد والقائمةُ
// البيضاء مقفولة. فالصفوفُ تصل نموذجاً خالصاً (`BookingBoardRow`) والوصلُ
// وقع في طبقة البيانات.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/bookings_board_table.dart';
import '../widgets/bookings_day_bar.dart';
import '../widgets/bookings_data_views.dart';
import '../widgets/bookings_destination_tabs.dart';
import '../widgets/bookings_settings_view.dart';
import '../widgets/bookings_simple_views.dart';

class BookingsPicPosScreen extends ConsumerWidget {
  const BookingsPicPosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(bookingBoardDayProvider);
    final rowsAsync = ref.watch(bookingsBoardProvider);
    final destination = ref.watch(bookingsDestinationProvider);
    final query = ref.watch(bookingsQueryProvider);
    final rows = rowsAsync.value ?? const <BookingBoardRow>[];

    return PicPosScreenScaffold(
      title: 'الحجوزات',
      subtitle: bookingDayLabel(day),
      icon: PhosphorIconsBold.calendarCheck,
      headerActions: [
        FilledButton.icon(
          onPressed: () => _notYet(context),
          icon: const Icon(PhosphorIconsBold.calendarPlus, size: 17),
          label: const Text('حجز جديد'),
        ),
      ],
      subHeader: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: PicPosKpiRow(kpis: _kpisFor(rows)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريطُ اليوم يخصّ اللوحةَ وحدَها: بقيّةُ الوجهات لا تتغيّر
          // بتبديل اليوم، وشريطٌ لا أثرَ له يُوهم بأنّ له أثراً.
          if (destination == BookingsDestination.board) ...[
            BookingsDayBar(
              day: day,
              onPrev: () =>
                  ref.read(bookingBoardDayProvider.notifier).shift(-1),
              onNext: () => ref.read(bookingBoardDayProvider.notifier).shift(1),
              onToday: () => ref.read(bookingBoardDayProvider.notifier).today(),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(13),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const BookingsDestinationTabs(),
                  Expanded(
                    child: rowsAsync.when(
                      // خطأُ الاستعلام يُقال ولا يُبتلَع: شاشةٌ فارغةٌ عند
                      // عطلٍ تُقرأ «لا حجوزات» — وهي كذبة.
                      error: (e, _) => PicPosEmptyState(
                        icon: PhosphorIconsBold.warningCircle,
                        title: 'تعذّر تحميل الحجوزات',
                        hint: '$e',
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      data: (list) => _destinationBody(
                        context,
                        destination,
                        _filter(list, query),
                        day,
                        query: query,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// البحثُ السريعُ يمسّ الصفوفَ وحدَها — الاسمُ والهاتفُ والخدمةُ والمورد.
  ///
  /// ⚠️ ويُطبَّق على **كلّ** وجهةٍ تقرأ الصفوف، فلا يبقى مربعُ بحثٍ ظاهراً
  /// بلا أثرٍ في وجهةٍ ما — وحقلٌ لا يفعل شيئاً أسوأُ من غيابه.
  List<BookingBoardRow> _filter(List<BookingBoardRow> rows, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((r) {
      return r.customerName.toLowerCase().contains(q) ||
          (r.customerPhone ?? '').toLowerCase().contains(q) ||
          r.serviceName.toLowerCase().contains(q) ||
          (r.resourceName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _destinationBody(
    BuildContext context,
    BookingsDestination destination,
    List<BookingBoardRow> rows,
    DateTime day, {
    String query = '',
  }) {
    switch (destination) {
      case BookingsDestination.board:
        return rows.isEmpty
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.calendarX,
                title: 'لا حجوزات في ${bookingDayLabel(day)}',
                hint: 'اختر يوماً آخر أو أضف حجزاً جديداً.',
              )
            : BookingsBoardTable(rows: rows);
      case BookingsDestination.waitlist:
        return BookingsWaitlistView(rows: rows);
      case BookingsDestination.resources:
        return BookingsResourcesView(rows: rows);
      case BookingsDestination.services:
        return BookingsServicesView(rows: rows);
      case BookingsDestination.customers:
        return BookingsCustomersView(query: query);
      case BookingsDestination.reminders:
        return const BookingsRemindersView();
      case BookingsDestination.reports:
        return BookingsReportsView(rows: rows, day: day);
      case BookingsDestination.settings:
        return const BookingsSettingsView();
    }
  }

  void _notYet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لوحُ «حجز جديد» يأتي في المرحلة التالية')),
    );
  }

  /// العدّاداتُ الستّةُ كما في التصميم — **محسوبةٌ من الصفوف المعروضة**.
  ///
  /// ⚠️ ولا تُحسب من استعلامٍ ثانٍ: رقمٌ يخالف الجدولَ تحته أسوأُ من غياب
  /// الرقم، وقد وقع ذلك في شاشاتٍ أخرى حين قرأ العدّادُ مصدراً غيرَ مصدرِ
  /// القائمة.
  List<PicPosKpi> _kpisFor(List<BookingBoardRow> rows) {
    var seated = 0, pending = 0, noShow = 0, deposits = 0.0, expected = 0.0;
    for (final r in rows) {
      if (r.status == 'seated' || r.status == 'in_service') seated++;
      if (r.status == 'pending') pending++;
      if (r.status == 'no_show') noShow++;
      deposits += r.depositAmount;
      if (r.occupiesTime) expected += r.servicePrice;
    }
    final money = AppConstants.currencySymbol;
    String fmt(double v) =>
        '${v.toStringAsFixed(AppConstants.decimalPlaces)} $money';

    return [
      PicPosKpi(
        label: 'حجوزات اليوم',
        value: '${rows.length}',
        icon: PhosphorIconsBold.calendarDots,
        tint: AppColors.primary,
      ),
      PicPosKpi(
        label: 'تم الحضور',
        value: '$seated',
        icon: PhosphorIconsBold.userCheck,
        tint: AppColors.success,
      ),
      PicPosKpi(
        label: 'بانتظار التأكيد',
        value: '$pending',
        icon: PhosphorIconsBold.hourglass,
        tint: AppColors.warning,
      ),
      PicPosKpi(
        label: 'لم يحضر',
        value: '$noShow',
        icon: PhosphorIconsBold.userMinus,
        tint: AppColors.error,
      ),
      PicPosKpi(
        label: 'العرابين المقبوضة',
        value: fmt(deposits),
        icon: PhosphorIconsBold.wallet,
        tint: AppColors.info,
      ),
      PicPosKpi(
        label: 'إيراد متوقع',
        value: fmt(expected),
        icon: PhosphorIconsBold.trendUp,
        tint: AppColors.booking,
      ),
    ];
  }
}

/// «اليوم» و«أمس» و«غداً» بالاسم، وما عداها بالتاريخ.
///
/// ⚠️ ويُقارَن **بالأيام لا بالفارق الزمنيّ**: `difference().inDays` بين
/// الحادية عشرة مساءً والواحدة صباحاً يعطي صفراً فيسمّي الغدَ «اليوم».
String bookingDayLabel(DateTime day, {DateTime? now}) {
  final today = _midnight(now ?? DateTime.now());
  final d = _midnight(day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == -1) return 'أمس';
  if (diff == 1) return 'غداً';
  return '${d.year}/${_two(d.month)}/${_two(d.day)}';
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);
String _two(int v) => v.toString().padLeft(2, '0');

/// تنسيقُ الوقت ١٢ ساعةً بالعربيّة — «10:00 ص».
String bookingTimeLabel(DateTime at) {
  final h24 = at.hour;
  final period = h24 < 12 ? 'ص' : 'م';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '${_two(h12)}:${_two(at.minute)} $period';
}

/// لونٌ من `#RRGGBB` — ولونٌ احتياطيٌّ حين يكون النصُّ تالفاً.
///
/// ⚠️ ‏`int.parse` ترمي على نصٍّ غيرِ سداسيّ، ولونُ خدمةٍ يكتبه المستخدمُ
/// يدويّاً يُسقط الشاشةَ كلَّها. فيُقرأ بـ`tryParse`.
Color bookingColorOf(String? hex, {Color fallback = AppColors.primary}) {
  if (hex == null) return fallback;
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return fallback;
  final v = int.tryParse(cleaned, radix: 16);
  if (v == null) return fallback;
  return Color(0xFF000000 | v);
}

/// نغمةُ الحالة ⇒ لونُ الثيمة.
Color bookingToneColor(BookingStatusTone tone) => switch (tone) {
      BookingStatusTone.success => AppColors.success,
      BookingStatusTone.info => AppColors.info,
      BookingStatusTone.warning => AppColors.warning,
      BookingStatusTone.danger => AppColors.error,
      BookingStatusTone.neutral => AppColors.textMuted,
    };

/// أرقامٌ جدوليّةٌ — تمنع رقصَ الأعمدة الرقميّة بين الصفوف.
const bookingTabularFigures = <ui.FontFeature>[ui.FontFeature.tabularFigures()];

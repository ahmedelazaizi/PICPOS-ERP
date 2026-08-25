// تقريرُ تقادم الذمم — نسخةُ PicPos.
//
// ═══ لماذا نسخةٌ لا فرعٌ في الشاشة المشتركة ═══
//
// أمرُ المالك 2026-08-25: لا يُربَط شيءٌ من PicPos بمسار UralCash، وما كان
// مشتركاً ولا نريد تعديلَه **يُنسَخ** إلى PicPos ويُثبَّت عليه التصميمُ الجديد.
//
// والشاشةُ الأصليّةُ (`screens/reports/ar_aging_report_screen.dart`) لم تكن
// قابلةً للتفريع أصلاً بلا تبديلٍ فيها: أرضيّتُها `Color(0xFFF1F5F9)`
// و`AppBar` بلون `AppColors.surface` — **ثابتان فاتحان لا يتبعان الثيم**،
// وصفوفُ جدولها بألوانٍ مكتوبةٍ بأرقامها. إصلاحُ ذلك في مكانه تعديلٌ في
// UralCash، وتركُه يعني شاشةً بيضاءَ فاقعةً في الوضع الغامق.
//
// ═══ وما تغيّر عن الأصل ═══
//
// ‏١) **المرشِّحُ نزل من الترويسة إلى الشريط.** «بتاريخ …» كان زرّاً داخل
//    `AppBar`، ومكانُه في التصميم شريطُ المرشِّحات تحت التبويبات.
// ‏٢) الترويسةُ `PicPosScreenScaffold` والتبويباتُ `PicPosReportTabs`.
// ‏٣) كلُّ لونٍ ثابتٍ صار تابعاً للثيم — عدا ألوانِ **شرائح الأعمار** فهي
//    دلالةٌ (أخضر/أصفر/أحمر/بنفسجي) لا سطحٌ، وتُقرأ في الوضعين.
//
// ⚠️ **والحسابُ لم يُمَسّ**: نفسُ `arAgingReportProvider` ونفسُ الجمع — الفرقُ
// عرضٌ لا أرقام.
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/report_providers.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';

/// صفُّ التقادم كما **تعرضه** الشاشة.
///
/// ⚠️ **سببُ وجوده حارسٌ لا ذوق.** `presentation_db_import_guard` يمنع أيَّ
/// ملفِّ عرضٍ **جديد** من استيراد `data/database` مباشرةً، وقائمتُه البيضاء
/// مجمَّدةٌ ونصُّها: «إضافةُ مخالفين جدد ممنوعة». والشاشةُ الأصليّةُ مُدرجةٌ في
/// تلك القائمة لأنّها سابقةٌ للحارس، أمّا هذه النسخةُ فجديدةٌ فلا تُدرَج.
///
/// و`ArAgingRow` معرَّفٌ في `daos/party_dao.dart`. فبدل استيراده تُشتقّ الشاشةُ
/// ما تعرضه من الصفِّ الذي يعطيه المزوِّد **بلا أن تسمّي نوعَه** — فتبقى طبقةُ
/// العرض على المزوِّد لا على القاعدة، وهو عينُ ما يطلبه الحارس.
class _AgingView {
  const _AgingView({
    required this.party,
    required this.b0,
    required this.b31,
    required this.b61,
    required this.b90,
    required this.total,
  });

  final String party;
  final double b0;
  final double b31;
  final double b61;
  final double b90;
  final double total;
}

/// ألوانُ شرائح الأعمار — دلالةٌ لا سطح، فتبقى كما هي في الوضعين.
const _kBucketFresh = Color(0xFF059669);
const _kBucketWarn = Color(0xFFF59E0B);
const _kBucketLate = Color(0xFFEF4444);
const _kBucketWorst = Color(0xFF7C3AED);

class ArAgingReportPicposScreen extends ConsumerStatefulWidget {
  const ArAgingReportPicposScreen({super.key});

  @override
  ConsumerState<ArAgingReportPicposScreen> createState() =>
      _ArAgingReportPicposScreenState();
}

class _ArAgingReportPicposScreenState
    extends ConsumerState<ArAgingReportPicposScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _asOfDate = DateTime.now();

  final _currencyFmt = NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );
  final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOfDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _asOfDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final arParams = (asOfDate: _asOfDate, customersOnly: true);
    final apParams = (asOfDate: _asOfDate, customersOnly: false);
    final arAsync = ref.watch(arAgingReportProvider(arParams));
    final apAsync = ref.watch(arAgingReportProvider(apParams));
    final currentAsync = _tabController.index == 0 ? arAsync : apAsync;

    return PicPosScreenScaffold(
      title: 'تقرير تقادم الذمم',
      subtitle: 'الذممُ المتأخّرةُ بشرائح الأيام حتى تاريخٍ محدَّد',
      icon: PhosphorIconsBold.hourglassHigh,
      headerActions: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.arrowClockwise),
          color: AppColors.primary,
          tooltip: 'تحديث',
          onPressed: () {
            ref.invalidate(arAgingReportProvider(arParams));
            ref.invalidate(arAgingReportProvider(apParams));
          },
        ),
      ],
      subHeader: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosReportTabs(
            controller: _tabController,
            tabs: const [
              (
                label: 'ذمم العملاء (AR)',
                icon: PhosphorIconsBold.usersThree,
                badge: null
              ),
              (
                label: 'ذمم الموردين (AP)',
                icon: PhosphorIconsBold.truck,
                badge: null
              ),
            ],
          ),
          // ⚠️ المرشِّحُ هنا لا في الترويسة — أمرُ المالك ونصُّ التصميم.
          PicPosFilterStrip(
            children: [
              PicPosFilterPill(
                icon: PhosphorIconsBold.calendarBlank,
                label: 'بتاريخ ${_dateFmt.format(_asOfDate)}',
                tabular: true,
                onTap: _pickDate,
              ),
            ],
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: currentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'خطأ في تحميل بيانات التقادم: $e',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
        // نوعُ `rows` مستنتَجٌ من المزوِّد ولا يُسمّى هنا — انظر [_AgingView].
        data: (rows) {
          if (rows.isEmpty) return _buildEmpty();
          return _buildTable([
            for (final r in rows)
              _AgingView(
                party: r.partyName,
                b0: r.bucket0_30,
                b31: r.bucket31_60,
                b61: r.bucket61_90,
                b90: r.bucket90Plus,
                total: r.outstandingTotal,
              ),
          ]);
        },
      ),
    );
  }

  Widget _buildEmpty() {
    final label = _tabController.index == 0 ? 'العملاء' : 'الموردين';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.checkCircle,
              size: 56, color: AppColors.success),
          const SizedBox(height: 12),
          Text(
            'لا توجد ذمم متأخرة لـ$label',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.picposText,
            ),
          ),
          Text(
            'بتاريخ ${_dateFmt.format(_asOfDate)}',
            style: TextStyle(color: context.picposMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<_AgingView> rows) {
    double t0_30 = 0, t31_60 = 0, t61_90 = 0, t90p = 0, tBal = 0;
    for (final r in rows) {
      t0_30 += r.b0;
      t31_60 += r.b31;
      t61_90 += r.b61;
      t90p += r.b90;
      tBal += r.total;
    }

    final headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: context.picposMuted,
    );
    final totalStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: context.picposText,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 10),
          child: Row(
            children: [
              _chip('0-30 يوم', t0_30, _kBucketFresh),
              const SizedBox(width: 10),
              _chip('31-60 يوم', t31_60, _kBucketWarn),
              const SizedBox(width: 10),
              _chip('61-90 يوم', t61_90, _kBucketLate),
              const SizedBox(width: 10),
              _chip('+90 يوم', t90p, _kBucketWorst),
            ],
          ),
        ),
        Container(
          color: context.picposField,
          child: Row(
            children: [
              _headerCell('اسم الطرف', flex: 3, style: headerStyle),
              _headerCell('0-30', flex: 1, style: headerStyle),
              _headerCell('31-60', flex: 1, style: headerStyle),
              _headerCell('61-90', flex: 1, style: headerStyle),
              _headerCell('+90', flex: 1, style: headerStyle),
              _headerCell('الإجمالي', flex: 1, style: headerStyle),
            ],
          ),
        ),
        Divider(height: 1, color: context.picposHairline),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: context.picposHairline),
            itemBuilder: (context, i) {
              final row = rows[i];
              final hasOverdue90 = row.b90 > 0;
              return Container(
                // ⚠️ الصفُّ المتأخّرُ يُميَّز بغسلٍ من لون الخطر لا بلونٍ
                //    ثابتٍ (`0xFFFFEBEB`) يصير بقعةً بيضاءَ في الغامق.
                color: hasOverdue90
                    ? _kBucketLate.withValues(alpha: 0.10)
                    : (i.isOdd ? context.picposField : context.picposCard),
                child: Row(
                  children: [
                    _dataCell(row.party, flex: 3, bold: true),
                    _dataCell(_fmt(row.b0), flex: 1),
                    _dataCell(_fmt(row.b31),
                        flex: 1, color: row.b31 > 0 ? _kBucketWarn : null),
                    _dataCell(_fmt(row.b61),
                        flex: 1, color: row.b61 > 0 ? _kBucketLate : null),
                    _dataCell(_fmt(row.b90),
                        flex: 1,
                        color: row.b90 > 0 ? _kBucketWorst : null,
                        bold: row.b90 > 0),
                    _dataCell(_fmt(row.total), flex: 1, bold: true),
                  ],
                ),
              );
            },
          ),
        ),
        Divider(height: 1, thickness: 2, color: context.picposHairline),
        Container(
          color: context.picposField,
          child: Row(
            children: [
              _dataCell('الإجمالي (${rows.length} طرف)', flex: 3, bold: true),
              _dataCell(_fmt(t0_30), flex: 1, style: totalStyle),
              _dataCell(_fmt(t31_60), flex: 1, style: totalStyle),
              _dataCell(_fmt(t61_90), flex: 1, style: totalStyle),
              _dataCell(_fmt(t90p), flex: 1, style: totalStyle),
              _dataCell(_fmt(tBal), flex: 1, style: totalStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_fmt(value),
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                )),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, {required int flex, TextStyle? style}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(text, style: style, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _dataCell(String text,
      {required int flex, bool bold = false, Color? color, TextStyle? style}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(
          text,
          style: style ??
              TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: color ?? context.picposText,
              ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _fmt(double v) => v == 0 ? '-' : _currencyFmt.format(v);
}

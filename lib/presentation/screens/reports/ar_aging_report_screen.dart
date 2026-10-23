import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/report_providers.dart';

/// AR/AP Aging Report screen.
/// PIR P1-01: Refactored to use arAgingReportProvider — no direct DB access.
class ArAgingReportScreen extends ConsumerStatefulWidget {
  const ArAgingReportScreen({super.key});

  @override
  ConsumerState<ArAgingReportScreen> createState() =>
      _ArAgingReportScreenState();
}

class _ArAgingReportScreenState extends ConsumerState<ArAgingReportScreen>
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
    final currentAsync =
        _tabController.index == 0 ? arAsync : apAsync;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title:  Text(
            tr('تقرير تقادم الذمم'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs:  [
              Tab(text: tr('ذمم العملاء (AR)')),
              Tab(text: tr('ذمم الموردين (AP)')),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(PhosphorIconsBold.calendar,
                  size: 18, color: AppColors.primary),
              label: Text(
                _dateFmt.format(_asOfDate),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise,
                  color: AppColors.primary),
              tooltip: tr('تحديث'),
              onPressed: () {
                ref.invalidate(arAgingReportProvider(arParams));
                ref.invalidate(arAgingReportProvider(apParams));
              },
            ),
          ],
        ),
        body: currentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('خطأ في تحميل بيانات التقادم: {e}', {'e': e}),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? _buildEmpty()
              : _buildTable(rows),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final label = _tabController.index == 0 ? tr('العملاء') : tr('الموردين');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.checkCircle,
              size: 56, color: AppColors.success),
          const SizedBox(height: 12),
          Text(
            tr('لا توجد ذمم متأخرة لـ{label}', {'label': label}),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            tr('بتاريخ {p0}', {'p0': _dateFmt.format(_asOfDate)}),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<ArAgingRow> rows) {
    double t0_30 = 0, t31_60 = 0, t61_90 = 0, t90p = 0, tBal = 0;
    for (final r in rows) {
      t0_30 += r.bucket0_30;
      t31_60 += r.bucket31_60;
      t61_90 += r.bucket61_90;
      t90p += r.bucket90Plus;
      tBal += r.outstandingTotal;
    }

    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    const totalStyle =
        TextStyle(fontWeight: FontWeight.bold, fontSize: 12);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _chip(tr('0-30 يوم'), t0_30, const Color(0xFF059669)),
              const SizedBox(width: 6),
              _chip(tr('31-60 يوم'), t31_60, const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              _chip(tr('61-90 يوم'), t61_90, const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              _chip(tr('+90 يوم'), t90p, const Color(0xFF7C3AED)),
            ],
          ),
        ),
        Container(
          color: AppColors.surface,
          child: Row(
            children: [
              _headerCell(tr('اسم الطرف'), flex: 3, style: headerStyle),
              _headerCell('0-30', flex: 1, style: headerStyle),
              _headerCell('31-60', flex: 1, style: headerStyle),
              _headerCell('61-90', flex: 1, style: headerStyle),
              _headerCell('+90', flex: 1, style: headerStyle),
              _headerCell(tr('الإجمالي'), flex: 1, style: headerStyle),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              final hasOverdue90 = row.bucket90Plus > 0;
              return Container(
                color: hasOverdue90
                    ? const Color(0xFFFFEBEB)
                    : (i.isOdd
                        ? const Color(0xFFF0F4F8)
                        : AppColors.surface),
                child: Row(
                  children: [
                    _dataCell(row.partyName, flex: 3, bold: true),
                    _dataCell(_fmt(row.bucket0_30), flex: 1),
                    _dataCell(_fmt(row.bucket31_60), flex: 1,
                        color: row.bucket31_60 > 0
                            ? const Color(0xFFF59E0B)
                            : null),
                    _dataCell(_fmt(row.bucket61_90), flex: 1,
                        color: row.bucket61_90 > 0
                            ? const Color(0xFFEF4444)
                            : null),
                    _dataCell(_fmt(row.bucket90Plus), flex: 1,
                        color: row.bucket90Plus > 0
                            ? const Color(0xFF7C3AED)
                            : null,
                        bold: row.bucket90Plus > 0),
                    _dataCell(_fmt(row.outstandingTotal),
                        flex: 1, bold: true),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, thickness: 2),
        Container(
          color: AppColors.surface,
          child: Row(
            children: [
              _dataCell(tr('الإجمالي ({p0} طرف)', {'p0': rows.length}),
                  flex: 3, bold: true),
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold)),
            Text(_fmt(value),
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text,
      {required int flex, TextStyle? style}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(text,
            style: style, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _dataCell(String text,
      {required int flex,
      bool bold = false,
      Color? color,
      TextStyle? style}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          text,
          style: style ??
              TextStyle(
                fontWeight:
                    bold ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: color,
              ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _fmt(double v) => v == 0 ? '-' : _currencyFmt.format(v);
}

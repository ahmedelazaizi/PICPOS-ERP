import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/database/database.dart';
import '../../../data/providers/report_providers.dart';
import '../../widgets/permission_guard.dart';

/// GAP-P2-FIX-11: VAT Reconciliation — compares invoice-level tax totals
/// with GL journal entry lines on output_vat / input_vat accounts.
/// PIR P1-01: Refactored to use vatReconciliationProvider — no direct DB access.
class VatReconciliationScreen extends ConsumerStatefulWidget {
  const VatReconciliationScreen({super.key});

  @override
  ConsumerState<VatReconciliationScreen> createState() =>
      _VatReconciliationScreenState();
}

class _VatReconciliationScreenState
    extends ConsumerState<VatReconciliationScreen> {
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  final _currFmt = NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );

  @override
  Widget build(BuildContext context) {
    final params = (year: _year, month: _month);
    final asyncData = ref.watch(vatReconciliationProvider(params));

    // ── ليه حراسة بصلاحية لا حصر بفرع ────────────────────────────────────
    // التقرير ده بيقارن **طرفين**: إجماليات الضريبة من الفواتير (فيها
    // branch_id وتتحصر بسهولة) مقابل **أرصدة حسابات GL** (‏2121 و1141 — على
    // مستوى الشركة بطبيعتها، وإسنادها لفرع بيعدّي على مراكز التكلفة).
    //
    // لو حصرنا طرفاً وسبنا التاني، التقرير هيعرض **فرقاً دايماً** والتسوية —
    // اللي هي كل وظيفته — تفقد معناها. يعني الفلتر الميكانيكي هنا مش إصلاح،
    // ده كسر للتقرير.
    //
    // فالصح إن الوصول نفسه يتحرس: ده تقرير محاسبي على مستوى الشركة، ومن
    // يملك reports_taxes يراه كاملاً، ومن لا يملكها لا يراه إطلاقاً. الشاشة
    // كانت **بلا أي فحص صلاحية** قبل كده.
    return PermissionGuard(
      permission: PermissionCodes.reportsTaxes,
      fallback: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'تسوية ضريبة القيمة المضافة تقرير على مستوى الشركة — '
            'لا تملك صلاحية عرضه.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      child: Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text('تسوية ضريبة القيمة المضافة',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise,
                  color: AppColors.primary),
              onPressed: () =>
                  ref.invalidate(vatReconciliationProvider(params)),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildMonthPicker(),
            Expanded(
              child: asyncData.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'خطأ في تحميل بيانات الضريبة: $e',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
                data: (d) => _buildContent(d),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMonthPicker() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _month,
            items: List.generate(
              12,
              (i) => DropdownMenuItem(
                value: i + 1,
                child:
                    Text(DateFormat.MMMM('ar').format(DateTime(2024, i + 1))),
              ),
            ),
            onChanged: (v) {
              if (v != null) setState(() => _month = v);
            },
          ),
          const SizedBox(width: 16),
          const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _year,
            items: List.generate(5, (i) {
              final y = DateTime.now().year - 2 + i;
              return DropdownMenuItem(value: y, child: Text(y.toString()));
            }),
            onChanged: (v) {
              if (v != null) setState(() => _year = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(VatReconciliationResult d) {
    final netInvoice = d.invoiceOutputVat - d.invoiceInputVat;
    final netGl = d.glOutputVat - d.glInputVat;
    final diffOutput = d.invoiceOutputVat - d.glOutputVat;
    final diffInput = d.invoiceInputVat - d.glInputVat;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              'ضريبة المخرجات (Output VAT)  — حساب ${d.outputVatAccCode}',
              const Color(0xFFDC2626)),
          _buildCard([
            _row('إجمالي ضريبة الفواتير (مبيعات)', d.invoiceOutputVat,
                bold: true),
            _row('رصيد الأستاذ العام', d.glOutputVat),
            _divider(),
            _row('الفرق', diffOutput,
                color:
                    diffOutput.abs() > 0.01 ? Colors.orange : Colors.green,
                bold: true),
          ]),
          const SizedBox(height: 16),
          _sectionHeader(
              'ضريبة المدخلات (Input VAT)  — حساب ${d.inputVatAccCode}',
              const Color(0xFF059669)),
          _buildCard([
            _row('إجمالي ضريبة الفواتير (مشتريات)', d.invoiceInputVat,
                bold: true),
            _row('رصيد الأستاذ العام', d.glInputVat),
            _divider(),
            _row('الفرق', diffInput,
                color:
                    diffInput.abs() > 0.01 ? Colors.orange : Colors.green,
                bold: true),
          ]),
          const SizedBox(height: 16),
          _sectionHeader('صافي الضريبة المستحقة', const Color(0xFF7C3AED)),
          _buildCard([
            _row('صافي (فواتير): مخرجات − مدخلات', netInvoice, bold: true),
            _row('صافي (أستاذ عام)', netGl),
            _divider(),
            _row('الضريبة المستحقة للدفع', netInvoice,
                color: netInvoice > 0 ? AppColors.error : Colors.green,
                bold: true),
          ]),
          if (diffOutput.abs() > 0.01 || diffInput.abs() > 0.01)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يوجد فرق بين ضريبة الفواتير والأستاذ العام. '
                    'راجع القيود المحاسبية أو تأكد من الترحيل التلقائي.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: children),
      ),
    );
  }

  Widget _row(String label, double value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal)),
          Text(_currFmt.format(value),
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color,
              )),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, thickness: 1);
}

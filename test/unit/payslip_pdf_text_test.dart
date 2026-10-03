// J4 (الجزء ٣) — قسيمةُ الراتب PDF: ما يصل الورقةَ فعلاً (‏`probePdf`) —
// هويّةُ المنشأة، الموظفُ والفترة، الاستحقاقاتُ والاستقطاعاتُ بمبالغها،
// والصافي — بالعربيّة وبالإنجليزيّة، وصفحةٌ لكلّ موظف.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/domain/models/hr_payroll.dart';
import 'package:ural_erp/presentation/hr_picpos/hr_payroll_labels.dart';
import 'package:ural_erp/presentation/hr_picpos/payslip_pdf.dart';
import 'package:ural_erp/services/printing/printing_models.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

String _flat(PdfProbe p) {
  final lines = <int, List<PdfTextRun>>{};
  for (final t in p.allTexts) {
    lines.putIfAbsent(t.page * 10000 - t.y.round() ~/ 3, () => []).add(t);
  }
  final keys = lines.keys.toList()..sort();
  final out = StringBuffer();
  for (final k in keys) {
    final runs = lines[k]!..sort((a, b) => a.x.compareTo(b.x));
    out.write('${runs.map((r) => r.text).join(' ')} ');
  }
  return deshapeArabic(out.toString());
}

final _run = PayrollRun(
  id: 1,
  year: 2025,
  month: 6,
  from: DateTime(2025, 6),
  to: DateTime(2025, 6, 30),
  status: PayrollRunStatus.posted,
);

PayrollLine _line(int id, String name, double net) => PayrollLine(
      id: id,
      runId: 1,
      employeeId: id,
      employeeName: name,
      employeeCode: 'EMP-$id',
      basicSalary: 3000,
      paidDays: 30,
      periodDays: 30,
      gross: 3200,
      deductions: 3200 - net,
      net: net,
      employerCost: 427.5,
      items: [
        const PayrollItem(
            kind: PayItemKind.earning,
            code: PayItemCode.basic,
            label: 'الراتب الأساسي',
            amount: 3000,
            accountKey: PayAccountKey.salariesExpense),
        const PayrollItem(
            kind: PayItemKind.earning,
            code: PayItemCode.overtime,
            label: 'العمل الإضافي',
            amount: 200,
            accountKey: PayAccountKey.overtimeExpense),
        PayrollItem(
            kind: PayItemKind.deduction,
            code: PayItemCode.advance,
            label: 'قسط سلفة',
            amount: 3200 - net,
            accountKey: PayAccountKey.advancesReceivable),
      ],
    );

const _company = DocumentCompanyHeader(
  name: 'النور',
  nameEn: 'Al-Nour Trading',
  taxId: '310-123',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('القسيمةُ العربيّة: الهويّةُ والموظفُ والبنودُ والصافي، صفحةٌ لكلّ موظف',
      () async {
    final doc = await buildPayslipDocument(
      run: _run,
      lines: [_line(1, 'أحمد', 2800), _line(2, 'سالم', 3000)],
      company: _company,
      english: false,
    );
    final probe = probePdf(await doc.save());
    expect(probe.pageCount, 2);
    final text = _flat(probe);
    for (final word in [
      'النور',
      'قسيمة',
      'أحمد',
      'سالم',
      'الاستحقاقات',
      'الاستقطاعات',
      'الأساسي',
      'الإضافي',
      'سلفة',
      'صافي',
    ]) {
      expect(text, contains(deshapeArabic(word)), reason: word);
    }
    expect(text, contains('2025-06'));
    expect(text, contains(hrMoney(2800)));
    expect(text, contains(hrMoney(400)));
    // An RTL line reorders the dashed number's parts; both reach the paper.
    expect(text, contains('310'));
    expect(text, contains(deshapeArabic('الضريبي')));
  });

  test('القسيمةُ الإنجليزيّة: تسمياتٌ إنجليزيّةٌ واسمُ المنشأة الإنجليزيّ',
      () async {
    I18nCatalog.setCatalog(Map<String, String>.from(
        jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
    I18nCatalog.setLocale(const Locale('en'));
    addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
    final doc = await buildPayslipDocument(
      run: _run,
      lines: [_line(1, 'Ahmad', 2800)],
      company: _company,
      english: true,
    );
    final text = _flat(probePdf(await doc.save()));
    for (final s in [
      'Al-Nour Trading',
      'Payslip',
      'Earnings',
      'Deductions',
      'Net salary',
      tr('الراتب الأساسي'),
      'Overtime',
      'Advance installment',
      'Ahmad',
      'Tax number: 310-123',
    ]) {
      expect(text, contains(s), reason: s);
    }
    expect(text, contains(hrMoney(2800)));
  });
}

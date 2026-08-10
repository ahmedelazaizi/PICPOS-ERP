// حارسٌ بنيويّ — تقريرُ المبيعات يطرح المرتجعاتِ كما تفعل شاشةُ الفواتير.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// شاشتان تقرآن **نفسَ القاعدة** وتجيبان جوابين مختلفين، لأن واحدةً تطرح
// المرتجعَ والأخرى لا تنديه أصلاً.
//
// `getSalesAnalytics` موثَّقٌ عقدُه نصّاً: «الشاشة تستلم المبيعاتِ الاعتيادية
// خاماً **وتطرح المرتجعَ بنفسها**» — لأن الاستعلامَ يستثني مستنداتِ
// `sale_type='return'` كي لا تُطرح مرّتين. الاستثناءُ يغطّي المرتجعَ
// **الكامل** وحدَه (حالتُه `returned`)، أمّا المرتجَعةُ **جزئياً**
// (‏`partial_return`) فتدخل المجملَ بقيمتها الكاملة وتنتظر من يحسم منها.
//
// `sales_invoices_controller` ينفّذ العقدَ: ينده `getReturnedAmountsForInvoices`
// ويطرح. و`sales_report_screen` لم يكن ينده المرتجعاتِ **ولا مرّةً واحدة**،
// فبقيت فاتورةُ ١٨ بمرتجعِ ٤ تقول ١٨ في التقرير و١٤ في شاشة الفواتير.
//
// حارسٌ بنيويٌّ لا سلوكيّ: المقيسُ هنا **الوصلُ** لا صحّةُ الحساب — الحسابُ
// مقيسٌ في `test/unit/sales_report_net_of_returns_test.dart` وعلى قاعدةٍ
// حقيقية في `test/integration/sales_report_net_of_returns_e2e_test.dart`.
//
// ⚠️ قبل تعديل هذا الحارس: العطبُ الذي يمنعه هو «شاشةٌ تنسى الطرح»، وهو
// عطبٌ صامتٌ تماماً — لا استثناءَ ولا سطرَ سجلّ، رقمٌ خاطئٌ فحسب.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _reportPath = 'lib/presentation/screens/reports/sales_report_screen.dart';
const _invoicesPath = 'lib/presentation/screens/sales_invoices_controller.dart';

/// سطرُ نداءٍ فعليّ لا ذكرٌ في تعليق.
bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains('$name(');
}

bool _calls(File f, String name) =>
    f.readAsLinesSync().any((l) => _isCall(l, name));

void main() {
  final report = File(_reportPath);
  final invoices = File(_invoicesPath);

  test('تقريرُ المبيعات ينده `getReturnedAmountsForInvoices`', () {
    expect(report.existsSync(), isTrue, reason: 'مسارُ شاشة التقرير تغيّر');

    expect(
      _calls(report, 'getReturnedAmountsForInvoices'),
      isTrue,
      reason: 'الاستعلامُ يسلّم المجملَ خاماً بعقدٍ موثَّق، والمرتجَعةُ '
          'جزئياً تدخله بقيمتها الكاملة. بلا هذا النداء تقول البطاقةُ ١٨ '
          'بينما شاشةُ الفواتير تقول ١٤ عن نفس الفاتورة.',
    );
  });

  test('ويطرحه بالقصِّ لكلّ فاتورةٍ معروضة', () {
    // `clampedReturnedTotal` هو ما يمنع الازدواجَ **بالبناء**: يقصر الحسمَ
    // على الفواتير المعروضة (فالمرتجَعةُ كلياً ليست فيها أصلاً) ويقصّ كلَّ
    // ردٍّ عند قيمة فاتورته (فلا سطرَ سالبٌ يقاصّ فواتيرَ أخرى).
    expect(
      _calls(report, 'clampedReturnedTotal'),
      isTrue,
      reason: 'طرحُ إجماليِّ مرتجعات الفترة جزافاً يشيل المرتجعَ الكاملَ '
          'مرّتين — مرّةً بالاستثناء ومرّةً بالطرح.',
    );
    expect(
      _calls(report, 'netOfReturns'),
      isTrue,
      reason: 'البطاقاتُ والطباعةُ والتصديرُ تقرأ `_analytics` كلُّها، '
          'فالصافي يُبنى مرّةً واحدةً في مكانٍ واحد وإلا انحرف أحدُها.',
    );
  });

  test('ضابط: شاشةُ الفواتير لسه تنده نفسَ الدالّة', () {
    // مصدرُ الاتّفاق هو أن الشاشتين تنديان **نفسَ** الدالّة. لو انفكّت
    // شاشةُ الفواتير عنها لعادت الفجوةُ من الطرف الآخر، والحارسُ فوق وحدَه
    // كان سيمرّ صامتاً.
    expect(invoices.existsSync(), isTrue,
        reason: 'مسارُ شاشة الفواتير تغيّر');
    expect(
      _calls(invoices, 'getReturnedAmountsForInvoices'),
      isTrue,
      reason: 'الشاشتان تتّفقان لأنهما تنديان نفسَ الدالّة — لا بالمصادفة.',
    );
  });
}

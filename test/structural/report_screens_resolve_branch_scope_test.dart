// حارس بنيوي — كل شاشة تقرير مالي لازم تحلّ حصر الفروع الآمر.
//
// ── ليه بنيوي مش سلوكي ──────────────────────────────────────────────────────
// فئة العطل هي «شاشة تقرير **جديدة** نسيت تمرّر الحصر». الاختبار السلوكي
// بيغطّي الشاشات اللي حد فتكر يكتبلها اختبار؛ ده بيوقع لحظة ما أي حد يضيف
// ملفاً في `lib/presentation/screens/reports/` من غير ما يحلّ النطاق.
//
// ── الخلفية ─────────────────────────────────────────────────────────────────
// تقرير المصروفات كان ٩١١ سطر بلا **ولا ذكر واحد** لـ`branchScopeProvider`.
// وبدل الحصر كان بيبذر `_selectedBranchId` من `activeBranchIdProvider` —
// اللي بيرجّع `null` لمستخدم بلا تخصيص فرع، وهو **نفس** المستخدم اللي
// `branchScopeProvider` بيدّيه `{}` («ما يشوفش حاجة»). فانقلب fail-closed
// لـfail-open: المستخدم ده كان بيقرا إجمالي مصروفات الشركة كلها بفئاتها
// وطرق دفعها وملاحظاتها.
//
// وجود `branchScopeProvider` في الملف مش إثبات إن الحصر **مُنفَّذ** — هو شرط
// لازم مش كافٍ. الإنفاذ الفعلي بيتحرس سلوكياً (شوف
// test/unit/expenses_report_branch_scope_test.dart و
// test/unit/treasury_report_branch_scope_d01_test.dart). الحارس ده بيمسك
// النسيان الكامل، وهو فئة العطل اللي وقعت فعلاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// شاشات تقارير خارج مجلد `reports/` بتقرا بيانات مالية عبر الفروع.
const _extraReportScreens = <String>[
  'lib/presentation/screens/report_builder_screen.dart',
  'lib/presentation/screens/party_statement_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
];

/// مش شاشة — زرار تصدير مشترك بين ١٣ شاشة، بيحرس صلاحية `reports_export`
/// ومش بيبني استعلاماً.
const _notAScreen = <String>{
  'lib/presentation/screens/reports/report_export_guard.dart',
};

/// خط أساس موثَّق — **مش نمطاً مقبولاً**، دي تسريبات مقيسة لسه مفتوحة.
///
/// كل واحدة فيهم بتعرض قيم مالية عبر الفروع لمستخدم محصور:
///   • ar_aging_report_screen    — أرصدة كل العملاء والموردين على مستوى الشركة
///   • vat_reconciliation_screen — إجماليات ضريبة المخرجات/المدخلات + أرصدة GL
///   • report_builder_screen     — تقارير مخصّصة على كل الجداول بلا أي حصر
///   • party_statement_screen    — بينده watchAllParties() مع إن
///                                 watchAllPartiesForBranches(allowedBranchIds)
///                                 موجودة فعلاً
///   • stock_movements_screen    — كل الحركات بـunitCost/balanceAfter، بلا LIMIT
///
/// لإزالة سطر: حُلّ `branchScopeProvider` في الشاشة، مرّر `allowedBranchIds`
/// للاستعلام، اكتب اختباراً سلوكياً يثبت إن `{}` بتفشل مقفولة، وشيل السطر.
const _baseline = <String>{
  'lib/presentation/screens/reports/ar_aging_report_screen.dart',
  'lib/presentation/screens/reports/vat_reconciliation_screen.dart',
  'lib/presentation/screens/report_builder_screen.dart',
  'lib/presentation/screens/party_statement_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
};

void main() {
  test('كل شاشة تقرير بتحلّ branchScopeProvider (عدا خط الأساس الموثَّق)', () {
    final files = <String>[
      ...Directory('lib/presentation/screens/reports')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.dart')),
      ..._extraReportScreens,
    ]..sort();

    final offenders = <String>[];
    for (final path in files) {
      if (_notAScreen.contains(path)) continue;
      final file = File(path);
      if (!file.existsSync()) {
        fail('مسار في قائمة الحارس مش موجود — حدّث القائمة: $path');
      }
      if (!file.readAsStringSync().contains('branchScopeProvider')) {
        offenders.add(path);
      }
    }

    final unexpected = offenders.where((p) => !_baseline.contains(p)).toList();
    expect(unexpected, isEmpty,
        reason: 'شاشة تقرير جديدة بلا حصر فروع — مرّر allowedBranchIds '
            'للاستعلام زي expenses_report_screen.dart');

    // خط الأساس لازم يضيق مع الوقت: لو اتصلحت شاشة، شيلها من `_baseline`
    // عشان ما ترجعش تتسرّب تاني من غير ما حد ياخد باله.
    final fixed = _baseline.where((p) => !offenders.contains(p)).toList();
    expect(fixed, isEmpty,
        reason: 'الشاشات دي بقت بتحلّ النطاق — شيلها من _baseline عشان '
            'الحارس يقفل عليها');
  });
}

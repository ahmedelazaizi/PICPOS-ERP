// اختبارُ سطحٍ لفئات التقارير في الشريط — بلاغُ المالك 2026-09-12:
// «شاشة التقارير موجود اختيارها ولكن ليس تحتها باقى الشاشات الداخليه».
//
// ⚠️ **ولم يكن لهذا البلاغ حارسٌ ممكن.** الودجتُ كانت صنفاً خاصّاً في
// `part` من `app_shell.dart`، والحارسُ الموجودُ بنيويٌّ يقرأ النصَّ — فيرى
// `setState` و`if (isOpen)` ويطمئنّ، ولا يرى نقرةً لا تصل ولا طفلاً لا
// يُرسَم. فالسؤالُ الوحيدُ المُجدي: **أنقر رأساً فهل يظهر تقريرٌ تحته؟**

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/e_invoicing_providers.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/reports_picpos_screen.dart';
import 'package:ural_erp/presentation/shell/report_category_nav.dart';

/// الشريطُ الجانبيّ أرضيّتُه داكنةٌ وألوانُ الودجت بيضاءُ الشفافية، فتُوضَع
/// في حاضنٍ داكنٍ كما في الشلّ — وإلّا صار الفحصُ يقرأ نصّاً غيرَ مرئيّ.
Future<void> _pump(
  WidgetTester tester,
  void Function(String, String?) onOpen,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeEInvoicePlatformProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: const Color(0xFF0F1629),
            body: SizedBox(
              width: 240,
              child: SingleChildScrollView(
                child: ReportCategoryNav(onOpen: onOpen),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<PicposReportCategory> _cats() => buildPicposReportCatalog(
      actions: PicposReportActions.inert,
      eInvoicePlatform: null,
    );

void main() {
  testWidgets('مرساةٌ — رؤوسُ الفئات تُرسَم كلُّها', (tester) async {
    await _pump(tester, (_, _) {});
    final cats = _cats();
    expect(cats.length, greaterThanOrEqualTo(10),
        reason: 'الكتالوجُ قُرئ فارغاً — الفحوصُ تحته تقرأ لا شيء');
    for (final c in cats) {
      expect(find.text(c.title), findsOneWidget, reason: c.title);
    }
  });

  testWidgets('ولا تقريرَ مرئيٌّ قبل النقر', (tester) async {
    await _pump(tester, (_, _) {});
    final cat = _cats().first;
    for (final r in cat.mainReports) {
      expect(find.text(r.title), findsNothing, reason: r.title);
    }
  });

  testWidgets('ونقرُ الرأس يُظهر تقاريرَه — عينُ ما بلّغ عنه المالك',
      (tester) async {
    await _pump(tester, (_, _) {});
    final cat = _cats().first;
    expect(cat.mainReports, isNotEmpty, reason: 'فئةٌ بلا تقارير');

    await tester.tap(find.text(cat.title));
    await tester.pumpAndSettle();

    for (final r in cat.mainReports) {
      expect(find.text(r.title), findsOneWidget,
          reason: 'نُقر «${cat.title}» ولم يظهر «${r.title}»');
    }
  });

  testWidgets('ونقرُ تقريرٍ يُبلِّغ الفئةَ والتقرير', (tester) async {
    final opened = <String>[];
    await _pump(tester, (c, r) => opened.add('$c/$r'));
    final cat = _cats().first;
    await tester.tap(find.text(cat.title));
    await tester.pumpAndSettle();

    final r = cat.mainReports.first;
    await tester.tap(find.text(r.title));
    await tester.pumpAndSettle();

    expect(opened, ['${cat.id}/${r.id}']);
  });

  testWidgets('ونقرُ رأسٍ ثانٍ يطوي الأوّل — رأسٌ واحدٌ مفتوحٌ في الحين',
      (tester) async {
    await _pump(tester, (_, _) {});
    final cats = _cats();
    final a = cats[0];
    final b = cats[1];

    await tester.tap(find.text(a.title));
    await tester.pumpAndSettle();
    expect(find.text(a.mainReports.first.title), findsOneWidget);

    await tester.tap(find.text(b.title));
    await tester.pumpAndSettle();
    expect(find.text(a.mainReports.first.title), findsNothing,
        reason: 'الأوّلُ بقي مفتوحاً فتراكمت الرؤوسُ في شريطٍ ضيّق');
    expect(find.text(b.mainReports.first.title), findsOneWidget);
  });

  testWidgets('وإعادةُ النقر على الرأس المفتوح تطويه', (tester) async {
    await _pump(tester, (_, _) {});
    final cat = _cats().first;
    await tester.tap(find.text(cat.title));
    await tester.pumpAndSettle();
    expect(find.text(cat.mainReports.first.title), findsOneWidget);

    await tester.tap(find.text(cat.title));
    await tester.pumpAndSettle();
    expect(find.text(cat.mainReports.first.title), findsNothing);
  });
}

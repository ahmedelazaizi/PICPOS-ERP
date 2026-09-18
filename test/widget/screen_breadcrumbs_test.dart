// مسارُ التنقّل: يُشتقُّ صواباً، ولا يفيض، **ولا يُسقط القشرةَ حين لا مسار.**
//
// ═══ الفئةُ الخطِرةُ هنا ليست التخطيط ═══
//
// شريطٌ يفيض يُشوِّه سطراً. لكنّ مُشتقّاً يرمي `StateError` **يُسقط شجرةَ
// القشرة كلَّها** — الشريطُ الجانبيُّ والتاباتُ والشاشةُ تحتها — لأنّه يُبنى
// في `Column` القشرة لا داخلَ الشاشة. وشاشتان مشحونتان بلا مدخلٍ جانبيٍّ
// أصلاً تسلكان هذا المسارَ بالضبط.
//
// ولذلك يُقاس هنا **الغيابُ** كما يُقاس الحضور: فحصٌ يمرّ على كلّ قيمة
// `AppScreen` لا على قيمةٍ اخترتُها.
//
// ⚠️ **وقياسُ عرضَين لا عرضٍ واحد** — عرفُ هذه الجلسة: ترويسةُ المستند فاضت
// عند ٤٢٠px وكانت خضراءَ تماماً عند ١٤٠٠. و`RenderFlex overflowed` **لا
// يرمي** في الإصدار، فـ`exception == null` وحدَه يمرّ على شاشةٍ مشوّهة —
// ولهذا يُلتقَط `FlutterError.onError` صراحةً.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/presentation/shell/screen_breadcrumbs.dart';

const _wide = 1400.0;
const _narrow = 420.0;

/// يرسم الشريطَ بعرضٍ محدَّدٍ ويعيد ارتفاعَه، ويجمع كلَّ خطأِ تخطيطٍ وقع.
Future<({double height, List<String> layoutErrors})> _measure(
  WidgetTester tester,
  int screenIndex,
  double width,
) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ScreenBreadcrumbs(screenIndex: screenIndex),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    FlutterError.onError = previous;
  }
  return (
    height: tester.getSize(find.byType(ScreenBreadcrumbs)).height,
    layoutErrors: errors,
  );
}

/// فهرسُ مدخلٍ جانبيٍّ قائمٍ بتسميتَيه — يُلتقَط من الجدول لا يُكتَب هنا،
/// فإعادةُ تسميةٍ تُسقط المرساةَ بدل أن تمرّ عليها.
({int index, String label, String group}) _anchorWithGroup() {
  for (final item in kAllNavItemDefs) {
    for (final g in kNavGroupDefs) {
      if (g.key == item.group && g.label != item.label) {
        return (index: item.index, label: item.label, group: g.label);
      }
    }
  }
  fail('لا مدخلَ جانبيٌّ واحدٌ له مجموعةٌ باسمٍ مختلف — الجدولُ تغيّر جذرياً');
}

void main() {
  test('مرساةٌ — يُشتقُّ مسارٌ كاملٌ لمدخلٍ قائم', () {
    final a = _anchorWithGroup();
    final path = resolveScreenPath(a.index);
    expect(path, isNotNull, reason: 'مدخلٌ موجودٌ في الجدول ولا مسارَ له');
    expect(path!.label, a.label);
    expect(path.groupLabel, a.group);
    expect(path.groupIcon, isNotNull,
        reason: 'أيقونةُ المجموعة سقطت — فالسطرُ يبدأ بفراغ');
  });

  test('والمجموعةُ لا تُكرَّر حين تُطابق اسمَ شاشتها', () {
    // «العملاء والموردين ‹ العملاء والموردين» و«Dashboard ‹ Dashboard»
    // حالتان **قائمتان** في الجدول لا فرضٌ نظريّ.
    final dupes = [
      for (final item in kAllNavItemDefs)
        for (final g in kNavGroupDefs)
          if (g.key == item.group && g.label == item.label) item.index,
    ];
    expect(dupes, isNotEmpty,
        reason: 'لا حالةَ تطابقٍ في الجدول — الفحصُ تحته لا يقيس شيئاً');
    for (final index in dupes) {
      final path = resolveScreenPath(index);
      expect(path, isNotNull);
      expect(path!.groupLabel, isNull,
          reason: 'الاسمُ مكرّرٌ في المسار عند الفهرس $index');
      expect(path.groupIcon, isNull);
    }
  });

  test('وشاشةٌ بلا مدخلٍ جانبيٍّ تُعيد null — لا StateError', () {
    // ⚠️ الفحصُ على **كلّ** قيمةِ `AppScreen` لا على قيمةٍ اخترتُها: مدخلٌ
    // جانبيٌّ يُضاف أو يُحذَف غداً، والحارسُ يجب أن يتبعه من نفسه.
    final withoutNav = [
      for (final s in AppScreen.values)
        if (!kAllNavItemDefs.any((i) => i.index == s.value)) s,
    ];
    for (final s in withoutNav) {
      expect(resolveScreenPath(s.value), isNull,
          reason: '${s.name} (${s.value}) بلا مدخلٍ جانبيٍّ ومع ذلك أعاد مساراً');
    }
    // وفهرسٌ لا وجودَ له إطلاقاً — يبقى صحيحاً مهما امتلأ الجدول.
    expect(resolveScreenPath(-1), isNull);
  });

  testWidgets('ولا يُسقط الشجرةَ عند شاشةٍ بلا مسار', (tester) async {
    final orphan = [
      for (final s in AppScreen.values)
        if (!kAllNavItemDefs.any((i) => i.index == s.value)) s.value,
    ];
    for (final index in [...orphan, -1]) {
      final m = await _measure(tester, index, _wide);
      expect(m.layoutErrors, isEmpty, reason: 'خطأُ بناءٍ عند الفهرس $index');
      expect(m.height, 0.0,
          reason: 'شريطٌ فارغٌ يأخذ ارتفاعاً — فراغٌ تحت التابات بلا سبب');
    }
  });

  testWidgets('والمسارُ يلتفّ على الضيّق ولا يفيض', (tester) async {
    // أطولُ مسارٍ في الجدول — لا واحدٌ اخترتُه بعينه.
    var index = _anchorWithGroup().index;
    var longest = 0;
    for (final item in kAllNavItemDefs) {
      final p = resolveScreenPath(item.index);
      if (p?.groupLabel == null) continue;
      final len = p!.label.length + p.groupLabel!.length;
      if (len > longest) {
        longest = len;
        index = item.index;
      }
    }

    final wide = await _measure(tester, index, _wide);
    expect(wide.layoutErrors, isEmpty, reason: 'فاض على العرض الواسع');

    final narrow = await _measure(tester, index, _narrow);
    expect(narrow.layoutErrors, isEmpty,
        reason: 'فاض على العرض الضيّق — `Wrap` لم يلتفّ');

    expect(narrow.height, greaterThan(wide.height),
        reason: 'الارتفاعُ لم يزد على الضيّق ⇒ لم يقع التفافٌ، فالمحتوى '
            'خرج من الحدّ صامتاً');
  });

  testWidgets('ويُسمّي شاشةً مطويّةً عن الشريط الجانبيّ', (tester) async {
    // مداخلُ حاوية «الحسابات» الستّةُ مخفيّةٌ عن القائمة في PicPos وشاشاتُها
    // تُبلَغ من تبويباتها. واشتقاقُ المسار من **المسموح به** بدل الجدول
    // الكامل يترك المسارَ فارغاً في عين الموضع الذي يحتاجه.
    expect(kPicPosFoldedIntoAccountingHub, isNotEmpty);
    for (final index in kPicPosFoldedIntoAccountingHub) {
      final path = resolveScreenPath(index);
      expect(path, isNotNull,
          reason: 'شاشةٌ مطويّةٌ ($index) بلا مسارٍ — المستخدمُ داخلَ حاويةٍ '
              'لا يدلُّ عنوانُها على موضعه');
      expect(path!.groupLabel, isNotNull);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ScreenBreadcrumbs(
              screenIndex: kPicPosFoldedIntoAccountingHub.first,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final expected = resolveScreenPath(kPicPosFoldedIntoAccountingHub.first)!;
    expect(find.text(expected.label), findsOneWidget);
    expect(find.text(expected.groupLabel!), findsOneWidget);
  });
}

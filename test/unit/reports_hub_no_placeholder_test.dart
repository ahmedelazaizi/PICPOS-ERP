// مركزُ تقارير PicPos — لا وجهةَ نائبةً بعد اليوم.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// بلاغاتُ المالك الستّةُ من التشغيل (2026-08-25) سببُها **واحد**: ثلاثةَ
// عشرَ مدخلاً في المركز موصولٌ بشاشةٍ عامّةٍ نائبةٍ بدل وجهته. والمركزُ
// كان يُبحر إلى شاشاتٍ قائمة، وهذه الثلاثةَ عشرَ لا شاشةَ لها فوُصلت
// بأقربِ عامّةٍ موجودة.
//
// وهذا العطبُ من النوع الذي **لا يحمرّ فيه شيء**: الشاشةُ تُفتَح فعلاً،
// والتحليلُ نظيف، والاختباراتُ خضراء — والمستخدمُ وحدَه يرى أنّ «هامش
// الربح» و«تقسيم العملاء» و«سجل الإلغاءات» تفتح جميعاً نفسَ اللوحة.
// فالحارسُ هنا نصّيّ: يقرأ مصدرَ المركز ويشترط ألّا يعود أيُّ مدخلٍ إلى
// الوجهات الثلاث.
//
// ⚠️ ولا يكفي عدُّ صفرٍ: لو تبدّل اسمُ الملفّ أو نمطُ التوصيل لقرأ الفحصُ
// صفراً ومرّ كاذباً. فلكلّ عدٍّ **مرساةٌ** تثبت أنّ القراءةَ نفسَها تعمل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

const _hub =
    'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart';

int _count(String src, String needle) => src.split(needle).length - 1;

void main() {
  late String src;

  setUpAll(() {
    final f = File(_hub);
    expect(f.existsSync(), isTrue, reason: 'مسارُ المركز تبدّل: $_hub');
    src = readLibrarySource(_hub);
  });

  test('مرساةُ القراءة — المركزُ مقروءٌ وفيه مداخلُ فعلاً', () {
    // بلا هذه المرساة، كلُّ فحصٍ أدناه يقرأ صفراً ويمرّ وهو أعمى.
    //
    // ⚠️ **وقد وقع فعلاً 2026-09-12**: رُفع الكتالوجُ إلى مستوى الملفّ
    //    ليقرأه الشريطُ الجانبيّ، فصار `_ReportEntry` ← `PicposReportEntry`
    //    و`nav(` ← `actions.open(`. والنمطان القديمان ماتا معاً، فلو لم
    //    تكن هذه المرساةُ هنا لقرأ فحصُ «الشاشات النائبة» أدناه صفراً
    //    **وهو أعمى** ومرّ أخضرَ إلى الأبد.
    expect(src.length, greaterThan(20000));
    expect(_count(src, 'PicposReportEntry('), greaterThan(30),
        reason: 'نمطُ المدخلات تبدّل — الفحوصُ أدناه تقرأ صفراً كاذباً');
    expect(_count(src, 'action: () => actions.open('), greaterThan(30),
        reason: 'نمطُ التوصيل تبدّل');
  });

  test('لا مدخلَ يعود إلى الشاشات النائبة الثلاث', () {
    // الثلاثُ التي كانت تبتلع الثلاثةَ عشرَ.
    for (final placeholder in const [
      'AnalyticsDashboardScreen',
      'ActivityLogScreen(',
      'ReportBuilderScreen()',
    ]) {
      expect(_count(src, 'actions.open(() => const $placeholder'), 0,
          reason: '«$placeholder» عادت وجهةً نائبةً لمدخلٍ في المركز');
    }
  });

  test('المداخلُ السبعةُ تفتح عارضَ التقرير بتعريفها', () {
    // كلُّ تعريفٍ يُنادى مرّةً واحدةً بالضبط — مرّتان تعني مدخلَين
    // مختلفَين يفتحان التقريرَ نفسَه، وهو عينُ ما شكا منه المالك.
    for (final def in const [
      'profitMarginReport()',
      'partyBehaviorReport(suppliers: false)',
      'partyBehaviorReport(suppliers: true)',
      'userActivityReport()',
      'salesTrendReport()',
      'customerSegmentsReport()',
      'inventoryTurnoverReport()',
    ]) {
      expect(_count(src, 'ReportViewPicposScreen(definition: $def)'), 1,
          reason: '«$def» ليست موصولةً بمدخلٍ واحدٍ بالضبط');
    }
  });

  test('تقاريرُ السجلّ الخمسةُ تفتح الشاشةَ المرشَّحة', () {
    expect(_count(src, 'ActivityLogPicposScreen('), 5,
        reason: 'عددُ تقارير السجلّ الموصولةِ بترشيحٍ مسبقٍ تبدّل');
    // ولكلٍّ عنوانُه — خمسةُ مداخلَ بعنوانٍ واحدٍ = خمسُ شاشاتٍ متطابقة.
    final titles = RegExp(
      r"presetTitle:\s*(?:tr\(\s*)?'([^']+)'(?:\s*\))?",
    ).allMatches(src).map((m) => m.group(1)!).toSet();
    expect(titles.length, 5, reason: 'عنوانان متطابقان في تقريرَي سجلّ');
  });

  test('أوامرُ الشراء تفتح شاشتَها القائمة', () {
    expect(_count(src, 'const PurchaseOrdersScreen()'), 1);
  });
}

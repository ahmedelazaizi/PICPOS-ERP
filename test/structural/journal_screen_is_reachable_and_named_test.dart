// حارسُ العقد: «اليومية العامة» — **اسمٌ واحدٌ وشاشةٌ واحدةٌ من كلّ باب**.
//
// ═══ 🔴 ما كان ═══
//
// ‏١ — **المدخلُ الجانبيُّ يفتح الشاشةَ القديمة.** الشاشةُ المُعاد تصميمُها
//     (`JournalEntriesPicPosScreen`) لم تكن تُفتَح إلّا من تبويب `je` في
//     حاوية الحسابات، بينما الفهرسُ ٣٢ — وهو المدخلُ الظاهرُ في القائمة —
//     بلا فرعِ علامةٍ إطلاقاً. فكلُّ ما يُعاد تصميمُه لا يراه من يدخل من
//     الباب المعتاد.
//
// ‏٢ — **والبحثُ الشاملُ يفتح شاشةً أخرى.** صفُّ «دفتر اليومية» فيه كان يحمل
//     `screenIndex: 31`، وهو فهرسُ **«ربط الحسابات»**. فمن يبحث عن اليومية
//     يُفتَح له ربطُ الحسابات.
//
// ‏٣ — **والاسمُ مكتوبٌ في أربعة مواضع.** قرارُ المالك 2026-09-18 يغيّره إلى
//     «اليومية العامة»، وتغييرُ واحدٍ يترك الثلاثةَ تقول غيرَه.
//
// ═══ والعقدُ المحروس ═══
//
// اسمٌ واحدٌ ([journalEntriesScreenLabel])، وفهرسٌ يُقرأ من `ScreenId` لا
// يُكتَب رقماً، وفرعُ علامةٍ على المدخل الجانبيّ.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
  for (final line in readLibrarySource(path).split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

const _mainPath = 'lib/app_main_screen.dart';
const _navPath = 'lib/data/providers/auth_providers.dart';
const _omniPath = 'lib/presentation/widgets/omnibox/global_search_omnibox.dart';
const _screenPath =
    'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart';

void main() {
  test('الاسمُ ثابتٌ واحدٌ وقيمتُه «اليومية العامة»', () {
    expect(
      journalEntriesScreenLabel,
      'اليومية العامة',
      reason: 'قرارُ المالك 2026-09-18 على تسمية الشاشة',
    );
  });

  test('والمواضعُ الثلاثةُ تقرؤه لا تكتبه', () {
    for (final path in [_mainPath, _navPath, _omniPath]) {
      expect(
        _code(path).contains('journalEntriesScreenLabel'),
        isTrue,
        reason: '$path يكتب الاسمَ بيده — فيتفرّق الاسمُ على الأبواب',
      );
      expect(
        _code(path).contains("'دفتر اليومية'"),
        isFalse,
        reason: '$path ما زال يحمل الاسمَ القديم مكتوباً',
      );
    }
  });

  test('🔴 وأربعةٌ أخرى: العنوانُ والتبويبُ والورقةُ وملفُّ Excel', () {
    // 🔴 المواضعُ الأربعةُ أعلاه أبوابٌ **تؤدّي** إلى الشاشة. وقياسُ
    //    2026-09-19 وجد **أربعةً غيرَها** يقرؤها المستخدمُ بعد أن يصل،
    //    وكلُّها تكتب «قيود اليومية» بيدها: عنوانُ الشاشة · تبويبُ `je` في
    //    حاوية الحسابات · ترويسةُ الـPDF المطبوع · وعنوانُ ملفّ Excel.
    //
    // ✅ **والتبويبُ سقط من العدّ 2026-09-20**: حُذفت حاويةُ
    //    «الحسابات» وصارت اليوميةُ مدخلاً تحت رأسِها.
    //    فالقارئون **ثلاثة**، والأبوابُ **ثلاثة**.
    //
    // ⚠️ **والورقةُ والملفُّ يخرجان من البرنامج**: اسمٌ قديمٌ عليهما يبقى
    //    عند المحاسب بعد أن تتغيّر الشاشةُ كلُّها.
    for (final path in [_screenPath]) {
      expect(
        _code(path).contains("'قيود اليومية'"),
        isFalse,
        reason: '$path ما زال يكتب الاسمَ القديم',
      );
    }
    final code = _code(_screenPath);
    expect(
      code.contains('title: journalEntriesScreenLabel'),
      isTrue,
      reason: 'عنوانُ الشاشة لا يقرأ الثابتَ المشترك',
    );
    expect(
      code.contains('accountName: journalEntriesScreenLabel'),
      isTrue,
      reason: 'ترويسةُ الورقة المطبوعة لا تقرؤه',
    );
  });

  test('🔴 والمدخلُ الجانبيُّ يفتح الشاشةَ المُعاد تصميمُها', () {
    final code = _code(_mainPath);
    final at = code.indexOf('appScreen: AppScreen.journalEntries');
    expect(at, greaterThan(0), reason: 'لم أجد تهيئةَ شاشة اليومية');
    final block = code.substring(at, code.indexOf('ScreenConfig(', at));
    expect(
      block.contains('Brand.isPicPos'),
      isTrue,
      reason:
          'بلا فرعِ علامة — المدخلُ الجانبيُّ يفتح القديمةَ دائماً، '
          'فلا يُرى شيءٌ ممّا أُعيد تصميمُه',
    );
    expect(
      block.contains('JournalEntriesPicPosScreen()'),
      isTrue,
      reason: 'الفرعُ لا يذكر الشاشةَ الجديدة',
    );
    expect(
      block.contains('JournalEntriesScreen()'),
      isTrue,
      reason: 'الفرعُ الآخرُ سقط — والشاشةُ الأصليّةُ تخدم UralCash',
    );
  });

  test('🔴 والبحثُ الشاملُ يقرأ الفهرسَ من `ScreenId` لا يكتبه رقماً', () {
    final code = _code(_omniPath);
    final at = code.indexOf('journalEntriesScreenLabel');
    expect(at, greaterThan(0), reason: 'صفُّ اليومية اختفى من البحث الشامل');
    final row = code.substring(at, code.indexOf('},', at));
    expect(
      row.contains('ScreenId.journalEntries.navigationIndex'),
      isTrue,
      reason:
          'الفهرسُ مكتوبٌ رقماً — وكان ٣١ (ربط الحسابات)، فيُفتَح '
          'للباحث عن اليومية شاشةٌ أخرى',
    );
  });

  test('ومرساةٌ — الفهرسُ المقصودُ ليس ٣١', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه لو صار `navigationIndex` نفسُه ٣١.
    expect(ScreenId.journalEntries.navigationIndex, 32);
    expect(ScreenId.accountMapping.navigationIndex, 31);
  });
}

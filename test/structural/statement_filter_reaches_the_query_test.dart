// حارسُ العقد: **ما يُرشَّح على الشاشة يُرشَّح في الاستعلام — وعلى الورق.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// قرارُ المالك على الصورة `(7)`: **مرشِّحُ فرعٍ ظاهر** · **«تخصيص الأعمدة»
// بتفضيلٍ يُحفَظ لكلّ مستخدم** · **«عرض المستند» بنفس آليّة «المستند المصدر»**
// · و**«عرض المعتمد فقط» يُسقَط**.
//
// والأعطابُ التي يمسكها هذا الملفّ كلُّها من صنفٍ واحد: **شيءٌ يُرشَّح في
// موضعٍ ولا يُرشَّح في نظيره**، فيبدو كلُّ شيءٍ عاملاً والرقمان مختلفان:
//
// ‏١) 🔴 **الطباعةُ والتصديرُ يُعيدان الاستعلام بأنفسهما** (`_fetchEntries`)،
//    فنسيانُ `branchId` فيهما يُخرج ورقةً من **كلّ** الفروع بينما الشاشةُ
//    تعرض واحداً. والورقةُ هي ما يُوقَّع ويُرسَل.
//
// ‏٢) 🔴 **الافتتاحيُّ يُرشَّح بـSQL مكتوبةٍ بيدها** والنافذةُ بـdrift. وكلُّ
//    شرطٍ على الفرع في الافتتاحيّ لا بدّ أن يقبل `IS NULL` كما تقبله
//    النافذة — وإلّا خرج مخزنٌ أو خزنةٌ بلا فرعٍ من رصيد البداية ودخل
//    الحركةَ. والعدُّ هو الفحص: شرطٌ رابعٌ يُضاف بلا `IS NULL` يسقط هنا.
//
// ‏٣) **ومرشِّحُ الفرع على تبويبته وحدَها**: `getPartyStatement` هو الاستعلامُ
//    الوحيدُ الذي يقبل فرعاً، فزرٌّ ثابتٌ فوق التبويبات الخمس يَعِد بترشيحٍ
//    لا يقع في أربعٍ منها.
//
// ‏٤) **و«عرض المستند» يُعاد على الخريطة المغلقة نفسِها** لا على خريطةٍ ثانيةٍ
//    تفترق بأوّل نوعٍ يُضاف — وعلى **قناة** التنقّل لا ببناء شاشةٍ مباشرةً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dao_source.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
///
/// ⚠️ **والتعليقُ يُسقَط قبل العدّ**: هذا الملفّ يعدّ مقاطعَ SQL، وشرحُ العطب
/// فوقَ الإصلاح يذكر الصيغةَ المعطوبةَ حرفيّاً — فعدُّها كان سيقرأ مخالفةً
/// في تعليقٍ يشرح إصلاحَها.
String _code(String path) => [
      for (final line in readDaoSourceMerged(path).split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

const _dao = 'lib/data/database/daos/party_dao.dart';
const _screen =
    'lib/presentation/party_statement_picpos/screens/party_statement_picpos_screen.dart';
const _tabs =
    'lib/presentation/party_statement_picpos/screens/party_statement_tabs_picpos.dart';
const _export =
    'lib/presentation/party_statement_picpos/screens/party_statement_export_picpos.dart';

void main() {
  test('🔴 الفرعُ يصل الاستعلامَ من الشاشة **ومن الورق**', () {
    expect(_code(_tabs).contains('branchId: branchId'), isTrue,
        reason: 'تبويبةُ «الحركة والرصيد» لا تمرّر الفرعَ — فالمرشِّحُ زينة');
    expect(_code(_export).contains('branchId: branchId'), isTrue,
        reason: '🔴 الطباعةُ والتصديرُ يُعيدان الاستعلامَ بأنفسهما، فبلا '
            'الفرعِ تخرج ورقةٌ من كلّ الفروع تحت عنوانِ فرعٍ واحد');
  });

  test('🔴 وكلُّ شرطِ فرعٍ في الافتتاحيّ يقبل `IS NULL`', () {
    final dao = _code(_dao);
    final conditions = _count(dao, 'branch_id = ?');
    final nullable = _count(dao, 'OR branch_id IS NULL') +
        _count(dao, 'OR s.branch_id IS NULL');
    expect(conditions, greaterThan(0),
        reason: 'لم يعد ثمّة شرطُ فرعٍ أصلاً — النمطُ تغيّر فالفحصُ بلا معنى');
    expect(nullable, conditions,
        reason: '🔴 شرطٌ على الفرع بلا `IS NULL` يُخرج المخزنَ أو الخزنةَ '
            'العامّةَ من رصيد البداية ويُبقيها في الحركة — فيبدأ الكشفُ من '
            'رقمٍ لا يقابل ما تحته');
  });

  test('🔴 والافتتاحيُّ شقّان مستقلّان كما هي النافذة', () {
    final dao = _code(_dao);
    expect(dao.contains('double customerSide = 0;'), isTrue);
    expect(dao.contains('double supplierSide = 0;'), isTrue);
    expect(
        dao.contains('openingBalance = customerSide + supplierSide + '
            'chequeOpeningBalance;'),
        isTrue,
        reason: 'عودةُ `if (isCustomer) … else …` تُسقط مشترياتِ طرفٍ '
            'بالصفتين من رصيد البداية وتُبقيها في الحركة');
  });

  test('🔴 والمبيعاتُ في الافتتاحيّ موقَّعةٌ بنوعها', () {
    expect(
        _code(_dao)
            .contains("CASE WHEN sale_type = 'return' THEN -total ELSE total"),
        isTrue,
        reason: 'مرتجعُ نقطةِ بيعٍ سابقٌ للفترة يُضاف بدل أن يُطرَح — '
            'انحرافٌ ضعفُ قيمته');
  });

  test('ومرشِّحُ الفرع على تبويبته وحدَها', () {
    final screen = _code(_screen);
    expect(screen.contains('_BranchPickerButton('), isTrue,
        reason: 'المرشِّحُ لا يُبنى أصلاً');
    expect(screen.contains('_tabs.index == 0'), isTrue,
        reason: 'مرشِّحٌ ثابتٌ فوق الخمس يَعِد بترشيحٍ لا يقع في أربعٍ منها — '
            'وأربعٌ لا تقول إنّها لم تُرشَّح');
  });

  test('🔴 و«عرض المستند» على الخريطة المغلقة نفسِها لا على ثانية', () {
    final tabs = _code(_tabs);
    expect(tabs.contains('resolveJournalSourceTarget('), isTrue,
        reason: 'الوجهةُ تُشتقّ هنا بقاعدةٍ ثانيةٍ تفترق بأوّل نوعٍ يُضاف');
    expect(tabs.contains('kJournalSourceTargets'), isFalse,
        reason: 'الخريطةُ تُقرأ عبر دالّتها لا تُنسَخ');
    expect(tabs.contains('screenNavigationProvider'), isTrue,
        reason: 'الفتحُ عبر القناة لا مباشرةً — مالكُ التابات وحدَه يعرف '
            'الصلاحيّاتِ وسقفَ التابات');
  });

  test('وتفضيلُ الأعمدة يحمل معرِّفَ المستخدم ويُقرأ من المستودع', () {
    final tabs = _code(_tabs);
    expect(tabs.contains("'statement.ledger.columns.u\$userId'"), isTrue,
        reason: 'مفتاحٌ بلا معرِّفٍ يجعل تفضيلَ آخرِ من فتح الشاشةَ يحكم '
            'الجميعَ على نفس الجهاز');
    final screen = _code(_screen);
    expect(screen.contains('settingsRepositoryProvider'), isTrue);
    expect(screen.contains('cachedSettings'), isFalse,
        reason: 'الكاشُ يُرجع `null` عند إخفاقه كما عند غياب المفتاح، '
            'فمفتاحٌ خارجَ `preloadKeys` يُقرأ فارغاً دوماً');
    expect(screen.contains('parseStatementColumnPreference('), isTrue,
        reason: 'المقاطعةُ مع الكتالوج تُكتَب بيدها هنا بدل الوحدة المختبَرة');
  });

  test('🔴 و«عرض المعتمد فقط» غيرُ مبنيّ', () {
    // فواتيرُ الكشف وحركاتُه `status`ها **حالةُ سدادٍ** لا اعتماد
    // (‏pending/partial/paid · pending/completed/returned/booked)، فلا شيءَ
    // ليُرشَّح — ومربّعٌ لا يُغيّر صفّاً واحداً يُقرأ عطباً.
    for (final f in [_screen, _tabs]) {
      expect(_code(f).contains('المعتمد'), isFalse,
          reason: 'مربّعُ اعتمادٍ بُني في $f بلا حالةِ اعتمادٍ خلفه');
    }
  });

  test('والطباعةُ والتصديرُ في التبويبة التي يصدّرانها', () {
    // كلاهما يُعيد استعلامَ **الكشف** أيّاً كانت التبويبةُ المفتوحة، فزرٌّ في
    // ترويسةٍ فوق «الأوراق» كان يَعِد بتصدير ما يُرى ويُخرج شيئاً آخر.
    expect(_code(_screen).contains("label: const Text('تصدير الكشف')"), isFalse,
        reason: 'زرُّ الترويسة عاد — وهو يصدّر الكشفَ فوق أيّ تبويبة');
    expect(_code(_tabs).contains('_StatementActionBar('), isTrue,
        reason: 'الشريطُ السفليُّ لا يُبنى');
  });
}

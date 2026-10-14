// حارسُ العقد: زرُّ «المستند المصدر» **يصل مُوجِّهَ التابات**.
//
// ═══ فئةُ العطب ═══
//
// قرارُ المالك 2026-09-18: **يُبنى زرُّ القفز** إلى المستند المصدر.
//
// و`_activateScreen` في `app_main_screen` هي المعبرُ الوحيد لفتح تاب، وهي
// حالةٌ خاصّةٌ في تلك الودجت — فالشاشاتُ المتداخلةُ لا تصلها. فبلا قناةٍ
// مشتركة، يُرسَم الزرُّ ولا يقع شيءٌ عند نقره.
//
// 🔴 **وزرٌّ يُعرَض ولا يقفز أسوأُ من غيابه**: المستخدمُ يظنّ الشاشةَ
// معطَّلةً أو المستندَ محذوفاً — وكلاهما كذب.
//
// والسلسلةُ **أربعُ حلقات**: خريطةٌ مغلقةٌ ← شرطُ العرض ← القناة ← مستمعٌ في
// مالك التابات. وكسرُ أيِّها يُنتج زرّاً ميّتاً.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
  for (final line in readLibrarySource(path).split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

const _mapPath = 'lib/domain/models/journal_source_document.dart';
const _channelPath = 'lib/data/providers/screen_navigation_provider.dart';
const _screenPath =
    'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart';
const _shellPath = 'lib/app_main_screen.dart';

String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('‏١ — الخريطةُ مغلقةٌ وتشترط الشروطَ الثلاثة', () {
    final fn = _body(
      _code(_mapPath),
      'JournalSourceTarget? resolveJournalSourceTarget(',
      // ⚠️ المرساةُ آخرُ سطرٍ في الجسم لا `}` في أوّل العمود: توقيعُ الدالّة
      // نفسُه ينتهي بـ`}) {`، فتقع الشريحةُ على التوقيع وحدَه ويسقط الفحصُ
      // على جسمٍ لم يُقرأ.
      'return target;',
    );
    expect(
      fn.contains('kJournalSourceTargets[referenceType]'),
      isTrue,
      reason:
          'الوجهةُ تُشتقّ اشتقاقاً بدل خريطةٍ مغلقة — فتُخترَع '
          'وجهاتٌ لأنواعٍ لا شاشةَ لها',
    );
    expect(
      fn.contains('referenceId == null'),
      isTrue,
      reason: 'قيدٌ بلا رقمِ مستندٍ يفتح شاشةً بلا هدف',
    );
    expect(
      fn.contains('allowedScreenIds.contains'),
      isTrue,
      reason: 'زرٌّ يقود إلى شاشةٍ خارجَ نطاق التجهيزة',
    );
  });

  test('‏٢ — والزرُّ لا يُرسَم إلّا بوجهةٍ محقّقة', () {
    final footer = _body(
      _code(_screenPath),
      'class _EntryFooter extends StatelessWidget {',
      '\nclass _Badge',
    );
    expect(
      footer.contains('resolveJournalSourceTarget('),
      isTrue,
      reason: 'الشرطُ يُكتَب بيده بدل الصيغة المشتركة',
    );
    expect(
      footer.contains('if (target != null)'),
      isTrue,
      reason: 'الزرُّ يُرسَم بلا وجهة — نقرةٌ لا يتبعها شيء',
    );
    expect(
      footer.contains('AppConfig.allowedScreenIds'),
      isTrue,
      reason: 'النطاقُ لا يُمرَّر — فتُعرَض وجهاتٌ محجوبة',
    );
  });

  test('‏٣ — والقناةُ تحمل رقماً متزايداً لا الفهرسَ وحدَه', () {
    // 🔴 قيمتان متساويتان تُبتلعان بالمساواة: الزرُّ يعمل مرّةً ثمّ يموت.
    final code = _code(_channelPath);
    expect(
      code.contains('final int seq'),
      isTrue,
      reason: 'بلا رقمٍ متزايد يُبتلَع الطلبُ الثاني لنفس الشاشة',
    );
    expect(
      code.contains('seq: ++_seq'),
      isTrue,
      reason: 'الرقمُ لا يتزايد — فالقيمتان تتساويان',
    );
    expect(
      code.contains('void consume()'),
      isTrue,
      reason: 'بلا استهلاكٍ يُعاد تنفيذُ الطلب مع أوّل إعادةِ بناء',
    );
  });

  test('‏٤ — والشاشةُ تطلب عبر القناة لا تفتح بنفسها', () {
    final code = _code(_screenPath);
    expect(
      code.contains('screenNavigationProvider.notifier'),
      isTrue,
      reason: 'الشاشةُ لا تصل القناةَ — فالزرُّ ميّت',
    );
    expect(
      code.contains('.open(target.screenId.navigationIndex)'),
      isTrue,
      reason: 'الفهرسُ يُكتَب رقماً بدل أن يُقرأ من `ScreenId`',
    );
  });

  test('‏٥ — ومالكُ التابات يستمع ويستهلك', () {
    final code = _code(_shellPath);
    expect(
      code.contains('ref.listen(screenNavigationProvider'),
      isTrue,
      reason: 'لا مستمعَ — كلُّ طلبٍ يذهب إلى لا شيء',
    );
    expect(
      code.contains('_navigateToScreen(next.screenIndex)'),
      isTrue,
      reason: 'المستمعُ لا يفتح الشاشةَ',
    );
    expect(
      code.contains('.consume()'),
      isTrue,
      reason: 'الطلبُ لا يُستهلَك — فتقفز الشاشةُ بلا أن ينقر أحد',
    );
  });

  test('ومرساةٌ — الفتحُ يمرّ بالمعبر الوحيد لا بكتابة `_currentIndex`', () {
    // ‏`_navigateToScreen` تفحص الصلاحيّةَ ثمّ تنادي `_activateScreen`، وهي
    // التي تسجّل تاريخَ الرجوع وتحترم سقفَ التابات.
    final fn = _body(
      _code(_shellPath),
      'void _navigateToScreenImpl(int screenIndex) {',
      '\n  }',
    );
    expect(
      fn.contains('allowedIndices.contains(screenIndex)'),
      isTrue,
      reason: 'القفزُ صار يتخطّى فحصَ الصلاحيّة',
    );
    expect(
      fn.contains('_activateScreen(screenIndex)'),
      isTrue,
      reason: 'القفزُ صار يكتب الفهرسَ مباشرةً — فيضيع تاريخُ الرجوع',
    );
  });
}

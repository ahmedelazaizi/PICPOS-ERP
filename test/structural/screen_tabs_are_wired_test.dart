// حارسُ العقد: تاباتُ الشاشات موصولةٌ فعلاً — بلاغُ المالك 2026-09-12.
//
// ═══ فئاتُ العطب ═══
//
// **١ — شريطٌ يُرسَم ولا يُنقَر.** وهذا ليس فرضاً: هو ما كان. `AppBreadcrumbs`
// يرسم مدخلَين ويُمرِّر `onTap: isLast ? null : item.onTap`، و`AppShell`
// يبني المدخلَ الأخيرَ وحدَه بـ`onTap` — فالوحيدُ الذي يحمل ردَّ فعلٍ هو
// عينُ الوحيدِ الذي يُلغى ردُّ فعله. صفرُ مداخلَ قابلةٍ للنقر، دائماً.
// ولا اختبارٌ في المستودع كلِّه لاحظ ذلك، لأنّ الشريطَ **كان يُرسَم**.
//
// **٢ — شريطٌ لا يتجاوز مدخلَين.** `setBreadcrumbs` يستبدل القائمةَ لا
// يُضيف إليها، والمنادي يمرّر مدخلاً أو اثنَين — فثالثٌ مستحيلٌ بنيويّاً.
// وهو نصُّ البلاغ: «ولا يفتح اكثر من تابين».
//
// **٣ — كومةٌ بلا مفاتيح.** `IndexedStack` يطابق أطفالَه **بالموضع**؛
// فإغلاقُ تابٍ في الوسط يُزحزح ما بعده، وتُسلَّم حالةُ شاشةٍ إلى أخرى.
// وهذا لا يُرى في لقطةٍ: يظهر سلّةً في شاشة المخزون بعد إغلاق تابٍ.
//
// **٤ — جرسٌ يسقط مع الشريط المستبدَل.** كان ساكناً في `AppBreadcrumbs`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _shellPath = 'lib/presentation/shell/app_shell.dart';
const _barPath = 'lib/presentation/shell/screen_tabs_bar.dart';
const _mainPath = 'lib/app_main_screen.dart';
const _modelPath = 'lib/domain/models/screen_tabs.dart';
const _deadBarPath = 'lib/presentation/shared_widgets/app_breadcrumbs.dart';
const _deadProviderPath = 'lib/presentation/providers/breadcrumb_provider.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'ملفٌّ غائب: $path');
  return f.readAsStringSync();
}

/// النصُّ بلا أسطرِ التعليق.
///
/// ⚠️ **وهذا ليس تجميلاً — بلا هذا يمسك الحارسُ شرحَه.** الأنماطُ أدناه
/// تصف العطبَ بنصّه (`onTap: isLast ? null`) والتعليقاتُ التي تفسّره تكتبه
/// حرفياً. فأوّلُ تشغيلٍ أبلغ عن ثلاث مخالفاتٍ كلُّها في تعليقاتي أنا —
/// ولو صدّقتُها لأزلتُ الشرحَ وأبقيتُ العطبَ ممكناً.
///
/// وتُحذَف الأسطرُ الكاملةُ وحدَها: قصُّ ما بعد `//` في وسط سطرٍ يبتر
/// `'https://…'` داخلَ نصٍّ فيُفسد ما يُقاس.
String _code(String src) => [
      for (final line in src.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  test('الشريطُ الخاملُ لم يبقَ له أثرٌ يُرسَم', () {
    expect(File(_deadBarPath).existsSync(), isFalse,
        reason: 'الشريطُ الخاملُ ما زال موجوداً — ويُغري بإعادة وصله');
    expect(File(_deadProviderPath).existsSync(), isFalse,
        reason: 'مزوّدٌ يُكتَب فيه ولا قارئَ له — حالةٌ ميّتةٌ صامتة');
    expect(_code(_read(_shellPath)).contains('AppBreadcrumbs'), isFalse,
        reason: 'الشلُّ ما زال يرسم الشريطَ الخامل');
  });

  test('ولا نمطَ «الوحيدُ القابلُ للنقر يُلغى نقرُه» في العرض كلِّه', () {
    // ⚠️ **والفحصُ على النمط لا على الملفّ.** الملفُّ حُذف، والنمطُ يتكرّر:
    // أيُّ شريطِ مسارٍ يُرسَم بـ`isLast ? null : …` يعيد العطبَ نفسَه.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = _code(f.readAsStringSync());
      if (RegExp(r'onTap:\s*isLast\s*\?\s*null').hasMatch(src)) {
        offenders.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(offenders, isEmpty, reason: 'شريطٌ خاملٌ من جديد: $offenders');
  });

  test('والشلُّ يرسم شريطَ التابات ويمرّر كلَّ ما يحتاجه', () {
    final shell = _read(_shellPath);
    expect(shell.contains('ScreenTabsBar('), isTrue,
        reason: 'لا شريطَ تاباتٍ مرسومٌ أصلاً');
    for (final wire in const [
      'tabs: widget.tabs',
      'active: widget.currentIndex',
      'onSelect: widget.onSelectTab',
      'onClose: widget.onCloseTab',
    ]) {
      expect(shell.contains(wire), isTrue, reason: 'توصيلٌ ناقص: $wire');
    }
  });

  test('والنقرُ في الشريط يُبلِّغ بلا شرطٍ يُبطله', () {
    final bar = _code(_read(_barPath));
    expect(bar.contains('onTap: widget.onSelect'), isTrue,
        reason: 'التابُ لا يُبلِّغ نقرَه — وهو عينُ عطبِ فتات الخبز');
    expect(RegExp(r'onTap:\s*\w+\s*\?\s*null').hasMatch(bar), isFalse,
        reason: 'نقرٌ مشروطٌ بشرطٍ قد يُبطله دائماً');
  });

  test('وجرسُ التنبيهات انتقل مع الشريط', () {
    expect(_read(_barPath).contains('NotificationBell()'), isTrue,
        reason: 'الجرسُ كان في `AppBreadcrumbs` وسقط مع استبداله');
  });

  test('والشاشاتُ المفتوحةُ كلُّها تُبنى — بمفاتيحَ لا بمواضع', () {
    final main = _read(_mainPath);
    expect(main.contains('IndexedStack('), isTrue,
        reason: 'شاشةٌ واحدةٌ تُبنى — فالتابُ إشارةٌ لا تابٌ يحفظ حالته');
    expect(main.contains('KeyedSubtree('), isTrue);
    expect(main.contains('ValueKey<int>(e.index)'), isTrue,
        reason: 'مطابقةٌ بالموضع — إغلاقُ تابٍ يُسلِّم حالةَ شاشةٍ لأخرى');
    expect(main.contains('for (final i in _tabs.order)'), isTrue,
        reason: 'الكومةُ لا تُبنى من التابات المفتوحة');
  });

  test('والتنقّلُ كلُّه يمرّ بمعبرٍ واحد', () {
    final main = _read(_mainPath);
    // ⚠️ لا كتابةَ مباشرةً على حالة التابات خارجَ الدالّات الثلاث.
    final direct = RegExp(r'_tabs\s*=\s*').allMatches(main).length;
    expect(direct, lessThanOrEqualTo(6),
        reason: 'كتاباتٌ مباشرةٌ كثيرةٌ على حالة التابات — $direct موضعاً');
    expect(main.contains('void _activateScreen(int screenIndex)'), isTrue);
    expect(main.contains('onSelectTab: _activateScreen'), isTrue);
    expect(main.contains('onCloseTab: _closeTab'), isTrue);
  });

  test('وتنشيطُ تابٍ يُظهره فعلاً — لا يبقى مستورٌ فوقَه', () {
    // ⚠️ الشاشاتُ تدفع مساراتٍ فرعيّةً على مُوجِّه الشلّ (تقريرٌ مفتوحٌ مثلاً)
    // فوقَ الكومة كلِّها. وتبديلُ التاب تحته لا يُرى — فالنقرةُ تبدو ميّتةً
    // وهي عاملة، وهو **عينُ** ما بلّغ عنه المالك في الشريط السابق.
    // ⚠️ **والفحصُ في جسم الدالّة لا في الملفّ.** أوّلُ صياغةٍ بحثت عن
    // `popUntil(` في `app_main_screen.dart` كلِّه — ونجت منها طفرةُ حذفِ
    // السطر، لأنّ `onWindowClose` يحمل `popUntil` لغرضٍ آخرَ تماماً. فحصُ
    // وجودِ رمزٍ في ملفٍّ يكذب متى ظهر الرمزُ مرّتَين.
    final main = _read(_mainPath);
    final at = main.indexOf('void _activateScreen(int screenIndex) {');
    expect(at, greaterThan(0), reason: 'لا معبرَ تنشيطٍ أصلاً');
    final body = main.substring(at, main.indexOf('\n  }', at));
    expect(body.contains('appShellNestedNavigatorKey'), isTrue,
        reason: 'تنشيطُ تابٍ لا يلمس مُوجِّهَ الشلّ');
    expect(body.contains('popUntil('), isTrue,
        reason: 'تنشيطُ تابٍ لا يُزيل المسارَ الفرعيَّ فوقَه — فالنقرةُ '
            'تبدو ميّتةً وهي عاملة');
  });

  test('ونقطةُ البيع محصَّنةٌ من الإخلاء التلقائيّ', () {
    final model = _read(_modelPath);
    expect(model.contains('kUnevictableScreenTabs'), isTrue);
    expect(RegExp(r'kUnevictableScreenTabs\s*=\s*<int>\{1\}').hasMatch(model),
        isTrue,
        reason: 'إخلاءُ تابِ البيع يمسح سلّةً غيرَ مُفوتَرةٍ بلا سؤال');
  });

  test('وإغلاقُ تابِ البيع يسأل عن السلّة', () {
    final main = _read(_mainPath);
    final at = main.indexOf('Future<void> _closeTab(');
    expect(at, greaterThan(0), reason: 'لا مُغلِقَ للتابات');
    final body = main.substring(at, at + 2000);
    expect(body.contains('AppScreen.pos.value'), isTrue);
    expect(body.contains('cartControllerProvider'), isTrue,
        reason: 'الإغلاقُ يهدم شجرةَ البيع ويمسح السلّةَ بلا سؤال');
  });
}

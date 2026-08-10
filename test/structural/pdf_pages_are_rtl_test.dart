// حارسٌ بنيويّ — كلُّ صفحة PDF تحمل اتجاهَ RTL صراحةً.
//
// ── الآلية ────────────────────────────────────────────────────────────────
// حزمةُ `pdf` **لا تُشكّل العربيةَ ولا تعيد ترتيبها إلا على الفرع RTL**:
// `text.dart` ينادي `arabic.convert(...)`/`bidi.logicalToVisual(...)` حين
// يكون الاتجاهُ المستقَرُّ RTL وحدَه. و`pw.Page` بلا `textDirection` تؤول
// إلى **LTR**، فيُرسَل النصُّ المنطقيُّ خاماً: حروفٌ بصيغها المنفصلة وبترتيبٍ
// بصريٍّ مقلوب.
//
// مقيسٌ بالرسم في هذه الجلسة: «العميل: صبري» بلا اتجاهٍ خرجت
// «يربص :ليمعلا» — كلُّ حرفٍ منفصلٌ والسطرُ مقلوب. وبالاتجاه خرجت سليمة.
//
// ── لماذا حارسٌ لا مراجعة ─────────────────────────────────────────────────
// العطبُ يعيش في **صفحةٍ واحدةٍ منسيّة**، لا في مولّدٍ كامل. مقيس: مسحٌ خامٌّ
// يعدّ `pw.Page(` مقابل عدد ذكر `rtl` في الملفّ **يمرّ زوراً** — ملفٌّ فيه
// صفحتان وثمانيةُ ذكرٍ للاتجاه في مواضعَ أخرى يبدو سليماً وفيه صفحةٌ عارية.
// فالفحصُ هنا **لكلّ منشئِ صفحةٍ على حدة** داخل نافذةٍ من أسطره.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// منشئُ صفحة — `pw.Page(` أو `pw.MultiPage(`.
final _pageCtor = RegExp(r'\bpw\.(Page|MultiPage)\(');

/// **وجودُ الوسيط** لا قيمتُه الحرفية.
///
/// الاشتراطُ على `pw.TextDirection.rtl` نصّاً كان يعطي ثلاثةَ إيجاباتٍ
/// كاذبة: مطبوعاتٌ تحترم لغةَ الطباعة تمرّر متغيّراً أو شرطاً
/// (`locale == 'en' ? ltr : rtl`) وهو **الصحيح** لا المخالف. العطبُ
/// المقيسُ هو غيابُ الوسيط أصلاً، فيؤول للـLTR ولا تُشكَّل العربية.
final _hasDir = RegExp(r'textDirection:');

/// نافذةُ الأسطر التي يُبحث فيها عن الوسيط. وسائطُ المنشئ تسبق `build:`
/// عادةً بأسطرٍ قليلة، و`dart format` قد يلفّ التعبيرَ فتتباعد.
const _window = 14;

bool _isComment(String l) {
  final t = l.trimLeft();
  return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
}

void main() {
  test('كلُّ صفحة PDF فيها textDirection: rtl', () {
    final offenders = <String>[];

    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.replaceAll(r'\', '/');
      final lines = e.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        if (_isComment(lines[i]) || !_pageCtor.hasMatch(lines[i])) continue;
        final end = (i + _window < lines.length) ? i + _window : lines.length;
        final chunk = lines.sublist(i, end).join(' ');
        if (!_hasDir.hasMatch(chunk)) offenders.add('$rel:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'صفحةٌ بلا اتجاهٍ صريح تُرسم LTR، فلا تُشكَّل العربيةُ ولا '
          'يُعاد ترتيبُها: «صبري» ⇒ «يربص». أضف '
          '`textDirection: pw.TextDirection.rtl` لمنشئ الصفحة. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('ضابط: الحارسُ يرى منشئاتِ صفحاتٍ فعلاً', () {
    // بلا هذا، خطأٌ في التعبير النمطيّ يجعل الحارسَ يمرّ على صفرِ صفحاتٍ
    // ويُقرأ خُضرةً على مشروعٍ كلُّه مكسور.
    var pages = 0;
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      for (final l in e.readAsLinesSync()) {
        if (!_isComment(l) && _pageCtor.hasMatch(l)) pages++;
      }
    }
    expect(pages, greaterThan(20),
        reason: 'عددُ الصفحات المرصودة أقلُّ من المتوقَّع — التعبيرُ غلط');
  });
}

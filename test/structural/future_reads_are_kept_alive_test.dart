// كلُّ مزوّدٍ يُقرأ بـ`.future` يُبقى حيّاً — بلاغٌ ميدانيٌّ 2026-09-22.
//
// ═══ ما بُلِّغ ═══
//
// فتحُ فاتورة مشترياتٍ يخرج برسالة:
//
//     Bad state: The provider StreamProvider<List<Branche>>#418ce was
//     disposed during loading state, yet no value could be emitted
//
// فلا تُفتَح النافذةُ إطلاقاً.
//
// ═══ والآليّةُ مشروحةٌ في الشيفرة نفسِها ═══
//
// `allBranchesProvider` مزوّدُ **بثٍّ `autoDispose`**. و`ref.read(p.future)`
// عليه **لا يُبقيه حيّاً**: إن لم يكن أحدٌ يراقبه في تلك اللحظة تُرمى
// نسختُه فورَ القراءة، فلا يكتمل المستقبَلُ — وRiverpod يرمي `Bad state`
// بدل أن يتعلّق.
//
// وقد عولج هذا مرّةً بقائمة `keepAlive` تحمل `ref.listenManual` لكلّ
// مزوّدٍ يُقرأ. ثمّ **أُضيف رابعٌ** (أسماءُ الفروع، لحقل «الفرع») ولم
// يُضَف إلى القائمة — فعاد العطبُ في مسارٍ مختلف.
//
// ═══ 🔴 ولهذا حارسٌ عامٌّ لا سطرٌ مُصلَح ═══
//
// المصيدةُ بنيويّةٌ ومتكرّرة: القراءةُ والإبقاءُ **موضعان منفصلان**، وأيُّ
// قراءةٍ جديدةٍ تُكتَب بلا نظيرها تعمل في التطوير (شيءٌ آخرُ يراقب المزوّدَ
// صدفةً) وتسقط عند المستخدم. فالحارسُ يقرن الاثنين في كلّ دالّةٍ تستعملهما.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ملفّاتٌ تستعمل نمطَ `keepAlive` — تُكتشَف لا تُكتَب بيد، فملفٌّ جديدٌ
/// يتبنّى النمطَ يدخل الحراسةَ من نفسه.
List<File> _filesWithKeepAlive() {
  final out = <File>[];
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    if (src.contains('ref.listenManual(') && src.contains('.future)')) {
      out.add(f);
    }
  }
  return out;
}

String _stripComments(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

/// أسماءُ المزوّدات المقروءةِ بـ`.future` في نصٍّ ما.
Set<String> _futureReads(String code) => {
      for (final m in RegExp(r'read\(\s*([A-Za-z_][A-Za-z0-9_]*)\.future\)')
          .allMatches(code))
        m.group(1)!,
    };

/// وأسماءُ المُبقاةِ حيّةً بـ`listenManual`.
Set<String> _keptAlive(String code) => {
      for (final m in RegExp(r'listenManual\(\s*([A-Za-z_][A-Za-z0-9_]*)')
          .allMatches(code))
        m.group(1)!,
    };

void main() {
  group('حراسةُ الحارس', () {
    test('يجد ملفّاتٍ تستعمل النمطَ فعلاً', () {
      expect(_filesWithKeepAlive(), isNotEmpty,
          reason: 'لا ملفَّ يستعمل `listenManual` مع `.future` ⇒ الكشفُ '
              'انكسر والحارسُ يقيس فراغاً');
    });

    test('ويقرأ الاسمَين من نصٍّ مضبوط — على البلاغ نفسِه', () {
      const sample = 'ref.listenManual(allWarehousesProvider, (_, _) {}),\n'
          'await ref.read(allBranchesProvider.future);';
      expect(_futureReads(sample), {'allBranchesProvider'});
      expect(_keptAlive(sample), {'allWarehousesProvider'});
      // وهذا عينُ شكل العطب: قراءةٌ بلا إبقاء.
      expect(_futureReads(sample).difference(_keptAlive(sample)),
          {'allBranchesProvider'},
          reason: 'الفرقُ لا يُحسَب ⇒ لن يُبلَّغ عن فجوةٍ أبداً');
    });

    test('وذكرٌ في تعليقٍ ليس قراءةً', () {
      const sample = '// ref.read(allBranchesProvider.future) مذكورٌ شرحاً\n'
          'const x = 1;';
      expect(_futureReads(_stripComments(sample)), isEmpty,
          reason: 'شرحٌ يُعَدُّ قراءةً ⇒ بلاغاتٌ وهميّة');
    });
  });

  test('🔴 كلُّ مزوّدٍ يُقرأ بـ`.future` له نظيرٌ في `listenManual`', () {
    final gaps = <String>[];
    for (final f in _filesWithKeepAlive()) {
      final code = _stripComments(f.readAsStringSync());
      final missing = _futureReads(code).difference(_keptAlive(code));
      for (final p in missing) {
        gaps.add('${f.path.replaceAll(r'\', '/')} ← $p');
      }
    }
    expect(gaps, isEmpty,
        reason: '🔴 مزوّدٌ يُقرأ بـ`.future` ولا يُبقيه أحدٌ حيّاً. وهو '
            '`autoDispose` غالباً، فتُرمى نسختُه أثناء التحميل ويخرج '
            '«Bad state: … disposed during loading state» — فلا تُفتَح '
            'النافذةُ إطلاقاً:\n  ${gaps.join('\n  ')}');
  });
}

// حارسُ ترقيمِ الترقيات — يمنع دمجاً صامتاً يقتل الإقلاع.
//
// **العطبُ الذي وُلد منه، مقيسٌ لا مفترض:** فرعان تفرّعا من نفس النقطة، كلٌّ
// أضاف ترقيتَه. `git merge-tree` بينهما أعطى تعارضاً **واحداً** في سطر
// `schemaVersion`، بينما `epoch_3.dart` كُتب عنه `Auto-merging` — بلا تعارض.
// والملفُّ الناتجُ حمل نفسَ الترقية مرّتين تحت رقمين (`v156` و`v157`)،
// وإحداهما بتسويةِ بياناتٍ **قديمة**: تُسوّي `tax_rate <= 0` ثم تنادي
// `m.alterTable` — وهي تبني تعريفَ الجدول **الحاليَّ** (`>= 0.01`) لا تعريفَه
// يومَ كُتبت. فصفٌّ عند `0.005` ينجو من التسوية ثم يُفشل إعادةَ البناء:
//
//   CHECK constraint failed: NOT tax_enabled OR tax_rate >= 0.01
//
// ⇒ الإقلاعُ يموت على كلِّ قاعدةٍ دون ١٥٦، ولا سطرَ تعارضٍ واحدٍ يُنبّه.
//
// **ولماذا ليست القاعدةُ «لا أرقامَ مكرَّرة»:** التكرارُ المتعمَّدُ **نمطٌ
// مشروع** — رفعُ حرّاسٍ إلى رقمٍ واحدٍ يجعل كلَّ قاعدةٍ تحته تمرّ بها جميعاً،
// والمكرَّرُ يسقط في `isIdempotentMigrationError`. وفوقَ ذلك `from < 29`
// مكرَّرٌ في `epoch_1.dart` منذ القِدَم. فحارسٌ يرفض التكرارَ يكذب على نمطٍ
// صحيحٍ ويسقط على تاريخٍ قائم.
//
// فالسؤالُ الصحيحُ ليس «هل تكرّر رقمٌ؟» بل **«هل تكرّرت ترقيةٌ؟»** — ووسمُ
// `_safeMigrate` بعد نزع بادئة `vNNN` هو هُويّتُها. مقيس: صفرُ تكرارٍ على
// الشجرة الحاليّة، وسطرٌ واحدٌ (`table_orders tax CHECK constraint`) على شجرة
// الدمج المعطوبة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _migrationFiles = <String>[
  'lib/data/database/migrations/epoch_1.dart',
  'lib/data/database/migrations/epoch_2.dart',
  'lib/data/database/migrations/epoch_3.dart',
];

const String _databaseFile = 'lib/data/database/database.dart';

/// وسمُ الترقية. `\s*` يبتلع سطراً جديداً، فيمسك الملفوفَ على سطرٍ تالٍ —
/// وهي أربعُ حالاتٍ قائمةٍ في `epoch_3.dart` (‏v103 · v132 · v146 · v147).
final RegExp _migrationLabel =
    RegExp(r"_safeMigrate\(\s*'v(\d+) ([^']+)'");

/// كلُّ نداءٍ لـ`_safeMigrate` — يُعَدّ كي لا يمرَّ وسمٌ بصيغةٍ أخرى **صامتاً**
/// من تحت [_migrationLabel]. حارسٌ يتخطّى ما لا يفهمه لا يحرس.
final RegExp _migrationCall = RegExp(r'_safeMigrate\(');

/// حارسُ الكتلة. تُسقَط أسطرُ التعليق قبل المطابقة، ففي `epoch_1.dart` كتلتان
/// معطَّلتان بالتعليق (`// if (from < 51) { ... }`) وليستا ترقيتين.
final RegExp _versionGuard = RegExp(r'if\s*\(\s*from\s*<\s*(\d+)\s*\)');

final RegExp _schemaVersion =
    RegExp(r'int\s+get\s+schemaVersion\s*=>\s*(\d+)');

String _stripLineComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'لا بدّ أن يعمل هذا الاختبارُ من جذر المستودع — لم أجد $path');
  return file.readAsStringSync();
}

void main() {
  test('ترقيمُ الترقيات — لا ترقيةَ مكرَّرةٌ تحت رقمين', () {
    final seen = <String, String>{}; // الجذر → أوّلُ موضعٍ حمله
    final duplicates = <String>[];

    for (final path in _migrationFiles) {
      final source = _read(path);

      // الحارسُ لا يتخطّى ما لا يفهم: كلُّ نداءٍ لا بدّ أن يُقرأ وسمُه.
      final calls = _migrationCall.allMatches(source).length;
      final labels = _migrationLabel.allMatches(source).length;
      expect(
        labels,
        calls,
        reason: '[migration_numbering] في $path عددُ نداءات _safeMigrate '
            '($calls) لا يساوي عددَ الأوسمة المقروءة ($labels) — أيْ أن وسماً '
            "بصيغةٍ لا يفهمها الحارسُ يمرّ من تحته. الصيغةُ المطلوبة: "
            "_safeMigrate('vNNN وصفُ الترقية', ...)",
      );

      for (final match in _migrationLabel.allMatches(source)) {
        final version = match.group(1)!;
        final stem = match.group(2)!.trim();
        final previous = seen[stem];
        if (previous != null) {
          duplicates.add('  «$stem»\n      $previous\n      $path (v$version)');
        } else {
          seen[stem] = '$path (v$version)';
        }
      }
    }

    expect(
      duplicates,
      isEmpty,
      reason: '[migration_numbering] نفسُ الترقيةِ موجودةٌ مرّتين تحت رقمين '
          'مختلفين. هذه بصمةُ دمجٍ تلقائيٍّ خلط سلسلتَي ترقيةٍ متفرّعتين — '
          'اقرأ رأسَ هذا الملفّ.\n'
          'والعلاجُ ليس تغييرَ الوسم: احذف النسخةَ الزائدةَ وأبقِ سلسلةً واحدةً '
          'مرقَّمةً تصاعديّاً، وأعطِ الترقيةَ الجديدةَ رقماً **فوق** '
          'schemaVersion الحاليّ.\n'
          'المكرَّر:\n${duplicates.join('\n')}',
    );
  });

  test('ترقيمُ الترقيات — schemaVersion يساوي أكبرَ رقمِ كتلة', () {
    var maxGuard = 0;
    String? maxGuardFile;

    for (final path in _migrationFiles) {
      final source = _stripLineComments(_read(path));
      for (final match in _versionGuard.allMatches(source)) {
        final version = int.parse(match.group(1)!);
        if (version > maxGuard) {
          maxGuard = version;
          maxGuardFile = path;
        }
      }
    }

    expect(maxGuard, greaterThan(0),
        reason: '[migration_numbering] لم أجد كتلةَ ترقيةٍ واحدة — '
            'تغيّر شكلُ الحارس؟');

    final declared = _schemaVersion.firstMatch(_read(_databaseFile));
    expect(declared, isNotNull,
        reason: '[migration_numbering] لم أجد schemaVersion في $_databaseFile');

    expect(
      int.parse(declared!.group(1)!),
      maxGuard,
      reason: '[migration_numbering] schemaVersion لا يساوي أكبرَ رقمِ كتلة '
          '($maxGuard في $maxGuardFile).\n'
          'أكبرُ من الكتل ⇒ رقمٌ لا ترقيةَ له. وأصغرُ منها ⇒ الكتلةُ الأعلى '
          '**لا تعمل أبداً**: `onUpgrade` لا تُستدعى إلّا حتى schemaVersion، '
          'فتمرّ الترقيةُ صامتةً بلا خطأ.',
    );
  });
}

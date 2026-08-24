// حارسٌ بنيويّ: كلُّ نداءِ تصفيرٍ يمرُّ بحاجزِ كلمةٍ تُكتَب.
//
// ═══ العقدُ ═══
//
// `DataWipeService` تمحو بيانات **بلا رجعة**: فواتيرَ وقيوداً وأرصدة.
// وزرُّ «موافق» يُضغَط بالغلط، أمّا كتابةُ كلمةٍ بعينها ففعلٌ واعٍ لا يقع
// سهواً. فكلُّ مدخلٍ إلى هذه الخدمة يجب أن يمرَّ بـ`showPicPosDangerConfirm`
// ومعه `typedWord` غيرُ فارغ.
//
// ═══ لماذا حارسٌ لا مراجعة ═══
//
// لأنّ الإضافةَ رخيصة: سطرٌ واحدٌ يستدعي `wipeXxx()` جديدةً يمرّ في مراجعةٍ
// عابرةٍ بلا أن يلفت النظرَ إلى غيابِ الحاجز. والعطبُ هنا لا يظهر إلّا حين
// يُصفَّر تركيبُ عميلٍ بالخطأ — ولا رجعةَ بعدها إلّا من نسخةٍ احتياطيّة.
//
// ⚠️ والحارسُ يفحص **الملفّاتِ** لا الأسطر: يكفي أن يحمل الملفُّ الذي
// يستدعي التصفيرَ حاجزاً واحداً على الأقلّ مع كلمة. ولو تعدّدت المداخلُ في
// ملفٍّ واحدٍ فالمراجعةُ بالعين تكمّل الحارس — وهذا حدُّه المعلوم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نداءُ تصفيرٍ فعليّ — لا تعريفُ الدالّة في الخدمة نفسِها.
final _wipeCall = RegExp(r'\.wipe[A-Z]\w*\(');

void main() {
  test('كلُّ ملفٍّ يستدعي التصفيرَ يحمل حاجزَ كلمةٍ تُكتَب', () {
    final root = Directory('lib/presentation');
    expect(root.existsSync(), isTrue, reason: 'يُشغَّل من جذر المستودع');

    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (!_wipeCall.hasMatch(src)) continue;

      final rel = entity.path.replaceAll(r'\', '/');
      final hasGate = src.contains('showPicPosDangerConfirm');
      // `typedWord:` بقيمةٍ غيرِ `null` — الحاجزُ بلا كلمةٍ ليس حاجزاً.
      final hasWord = RegExp(r'typedWord:\s*(?!null)\S').hasMatch(src);

      if (!hasGate || !hasWord) {
        offenders.add(
          '$rel — ${hasGate ? "بلا كلمةِ تأكيد" : "بلا حوارِ خطرٍ أصلاً"}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'ملفٌّ يستدعي `DataWipeService.wipeXxx()` بلا حاجزِ كلمة.\n'
          'المحوُ بلا رجعة، وضغطةٌ واحدةٌ لا تكفي لتفويضه.\n'
          'الوصفة: `showPicPosDangerConfirm(... typedWord: "كلمة", '
          'willDelete: [...], willRemain: [...])`.\n'
          'المواضع:\n  ${offenders.join('\n  ')}',
    );
  });
}

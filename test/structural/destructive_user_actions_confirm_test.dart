// حارسٌ بنيويٌّ: قفلُ المستخدم لا يُنفَّذ بنقرةٍ واحدةٍ بلا تأكيد.
//
// ═══ العطبُ الذي وقع فعلاً ═══
//
// `_toggleUserLock` **لا تؤكّد داخلها** — التأكيدُ كان في المستدعي (زرُّ
// القفل داخل `ExpansionTile`). وحين نُقل الإجراءُ إلى قائمة النقاط الثلاث
// في إعادةِ تصميم 2026-08-22، رُبط بالدالّة مباشرةً فسقط التأكيد: نقرةٌ
// واحدةٌ تمنع مستخدماً من الدخول بلا سؤال.
//
// ولم يمسكه شيء: `flutter analyze` نظيف، والاختباراتُ الثلاثةَ عشرَ القائمةُ
// خضراء — لأن لا واحدَ منها يركّب الشاشة (تركيبُها يجرّ `AppDatabase`
// حقيقيّة). فالحراسةُ بنيويّةٌ: تُقرأ من النصّ لا من شجرة الودجت.
//
// ═══ ما يقيسه ═══
//
// في `users_management_picpos_screen.dart`: أيُّ فرعٍ في `_onUserMenu`
// يستدعي `_toggleUserLock` مباشرةً = فشل. المسارُ الوحيدُ المسموح هو غلافٌ
// يؤكّد أوّلاً (`_confirmToggleLock`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'lib/presentation/users_picpos/screens/users_management_picpos_screen.dart';

  late String src;

  setUpAll(() {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'الملفُّ انتقل؟ حدِّث المسار: $path');
    src = f.readAsStringSync();
  });

  test('قائمةُ النقاط لا تستدعي _toggleUserLock مباشرةً', () {
    // الفرعُ في `switch` يبدو: `case 'lock':` ثمّ سطرُ الاستدعاء.
    final lockBranch = RegExp(
      r"case 'lock':\s*\n\s*([A-Za-z_]+)\(",
      multiLine: true,
    ).firstMatch(src);

    expect(lockBranch, isNotNull,
        reason: 'لم يُعثر على فرع القفل في `_onUserMenu` — أعِد قراءة الحارس');
    expect(
      lockBranch!.group(1),
      isNot('_toggleUserLock'),
      reason: 'القفلُ يجب أن يمرّ بغلافٍ يؤكّد أوّلاً، لا بالدالّة مباشرةً',
    );
  });

  test('الغلافُ المؤكِّد يستدعي AppConfirmDialog قبل القفل', () {
    final wrapper = RegExp(
      r'Future<void> _confirmToggleLock\(User user\) async \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(src);

    expect(wrapper, isNotNull, reason: 'غلافُ التأكيد مفقود');
    final body = wrapper!.group(1)!;
    expect(body, contains('AppConfirmDialog.show'),
        reason: 'الغلافُ لا يؤكّد شيئاً');
    // التأكيدُ يجب أن **يحكم** الاستدعاء لا أن يسبقه ويُهمَل.
    expect(body, contains('if (confirmed)'),
        reason: 'نتيجةُ التأكيد تُقرأ ولا تُهمَل');
    expect(body, contains('_toggleUserLock(user)'));
  });

  test('الحذفُ يؤكّد داخل دالّته — فلا يحتاج غلافاً', () {
    final del = RegExp(
      r'Future<void> _deleteUser\(User user\) async \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(del, isNotNull);
    final body = del!.group(1)!;

    // ⚠️ **يُقاس المعنى لا اسمُ الدالّة.** اشترطت الصياغةُ الأولى
    //    `AppConfirmDialog.show` بالحرف، فاحمرَّ الحارسُ حين نُقل التأكيدُ
    //    إلى `showPicPosDangerConfirm` — وهو **أقوى**: يعرض قائمتَي الأثر
    //    ويُرجع `bool` غيرَ لاغٍ افتراضُه الرفض. وحارسٌ يمنع التحسينَ
    //    ليس حارساً.
    expect(
      body,
      anyOf(
        contains('AppConfirmDialog.show'),
        contains('showPicPosDangerConfirm'),
        contains('showPicPosConfirm'),
      ),
      reason: 'الحذفُ ينفَّذ بلا تأكيدٍ إطلاقاً — نقرةٌ واحدةٌ تُقفل حساباً',
    );

    // والتأكيدُ يجب أن **يحكم** التنفيذَ لا أن يسبقه ويُهمَل — وهذا شرطٌ
    // لم يكن هنا، وهو الأهمُّ: حوارٌ يُعرَض ثمّ تُهمَل نتيجتُه أسوأُ من
    // لا حوار، لأنه يوهم بالحماية.
    expect(
      body,
      anyOf(contains('if (!confirmed)'), contains('if (confirmed)')),
      reason: 'نتيجةُ التأكيد تُقرأ ولا تُهمَل',
    );
  });
}

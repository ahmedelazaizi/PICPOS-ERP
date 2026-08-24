// حارسٌ بنيويٌّ: لا `AlertDialog` عارياً في فورك الإعدادات.
//
// ═══ لماذا ═══
//
// فورك `settings_picpos` رُسم على تصميم PicPos، و`AlertDialog` القياسيُّ
// شكلٌ آخرُ تماماً: رأسٌ بلا أيقونةٍ ملوّنة، وتذييلٌ بأزرارٍ نصّيّة، وعرضٌ
// يتبع الشاشة. فحوارٌ واحدٌ عارٍ داخلَ شاشةٍ منقولةٍ إلى الهويّة يكسرها
// أظهرَ ما يكون — لأنّ الحوارَ هو ما يراه المستخدمُ في اللحظة.
//
// و[PicPosDialog] يعطي الشكلَ نفسَه بجسدٍ حرّ، و`showPicPosConfirm` يختصر
// حوارَ «عنوانٌ ورسالةٌ وزرّان» إلى سطرَين.
//
// ═══ ⚠️ وفرقٌ يخصُّ الأمان لا الشكل ═══
//
// `showDialog<bool>` يُرجع `null` حين يُغلَق الحوارُ بالمفتاح أو بالنقر
// خارجَه. فـ`if (result != false)` أو `result!` تقرأ الإغلاقَ العرَضيَّ
// **موافقةً** — وأخطرُها حوارُ حذف. و`showPicPosConfirm` يُرجع `bool` غيرَ
// لاغٍ افتراضُه **الرفض**، فلا يبقى القرارُ رهنَ طريقةِ فحصِ كلِّ مستدعٍ.
// فلا يُستبدَل حوارُ تأكيدٍ بفحصٍ أضعفَ عند النقل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('لا AlertDialog في فورك إعدادات PicPos', () {
    final root = Directory('lib/presentation/settings_picpos');
    expect(root.existsSync(), isTrue, reason: 'يُشغَّل من جذر المستودع');

    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('AlertDialog')) continue;
        // التعليقاتُ التي تشرح القاعدةَ ليست مخالفةً لها.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        offenders.add('$rel:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'حوارٌ قياسيٌّ داخلَ شاشةٍ منقولةٍ إلى هويّة PicPos يكسرها في '
          'أظهرِ لحظة.\n'
          'الوصفة: `PicPosDialog` للحوارِ ذي الجسد، و`showPicPosConfirm` '
          'للتأكيد.\n'
          '⚠️ ولا تستبدل تأكيداً بفحصٍ أضعف: `showPicPosConfirm` يُرجع '
          '`bool` غيرَ لاغٍ افتراضُه الرفض.\n'
          'المواضع (${offenders.length}):\n  ${offenders.join('\n  ')}',
    );
  });
}

// حارسٌ بنيويٌّ: لا `AlertDialog` عارياً في فورك الحسابات.
//
// ═══ لماذا ═══
//
// بلاغُ المالك 2026-08-27 عن «تصميم شاشة الحسابات … من أنماطٍ وحواراتٍ
// ونوافذَ وديالوجات». والقياسُ صدّقه: شاشاتُ `accounting_picpos` تستورد
// `picpos_shell` فعلاً — فالهويّةُ مطبَّقةٌ على الشاشة — لكنّ **أربعةَ
// حواراتٍ** بقيت `AlertDialog` قياسيّاً. والحوارُ هو ما يراه المستخدمُ في
// اللحظة، فحوارٌ عارٍ فوق شاشةٍ منقولةٍ يكسر الهويّةَ أظهرَ ما يكون.
//
// والمرجعُ المقيس: فورك `settings_picpos` فيه **٢٦** ظهوراً لـ`PicPosDialog`
// و**صفرُ** `AlertDialog`. وفورك الحسابات كان **٦** مقابلَ **٤** عارية.
//
// ═══ ⚠️ وفرقٌ يخصُّ الأمان لا الشكل ═══
//
// `showDialog<bool>` يُرجع `null` حين يُغلَق الحوارُ بالمفتاح أو بالنقر
// خارجَه. فـ`if (result != false)` أو `result!` تقرأ الإغلاقَ العرَضيَّ
// **موافقةً**. و`showPicPosConfirm` يُرجع `bool` غيرَ لاغٍ افتراضُه
// **الرفض**، فلا يبقى القرارُ رهنَ طريقةِ فحصِ كلِّ مستدعٍ. فلا يُستبدَل
// حوارُ تأكيدٍ بفحصٍ أضعفَ عند النقل.
//
// ⚠️ ويُقاس الفورك كلُّه لا الملفّاتُ الأربعةُ المعروفة: الحارسُ يمنع
// **العودةَ** كما يمنع الباقي، وحصرُه في قائمةٍ يجعله يتقادم مع المشروع.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('لا AlertDialog في فورك حسابات PicPos', () {
    final root = Directory('lib/presentation/accounting_picpos');
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

  test('وفورك الحسابات يستعمل PicPosDialog فعلاً', () {
    // ⚠️ «صفرُ AlertDialog» وحدَه يمرّ على فوركٍ بلا حواراتٍ أصلاً. فيُقاس
    //    الوجودُ الموجَبُ أيضاً — وإلّا صار الحارسُ يبارك الحذف.
    final root = Directory('lib/presentation/accounting_picpos');
    var uses = 0;

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        uses += 'PicPosDialog'.allMatches(line).length;
      }
    }

    expect(uses, greaterThanOrEqualTo(6),
        reason: 'خطُّ الأساس المقيسُ 2026-08-27 كان ٦ ظهوراً قبل النقل، '
            'ويزيد بعده. نقصانُه يعني حذفَ حوارٍ لا تنسيقَه.');
  });
}

// حارسٌ بنيويّ: كلُّ قسمٍ يُعرَض في «حماية الأقسام» له بوّابةٌ فعليّة.
//
// ═══ العطبُ الذي يمنعه ═══
//
// شاشةُ الحماية تعرض مفتاحاً لكلِّ قسم. والمفتاحُ وعدٌ: «هذا القسمُ يُقفَل».
// فإن لم يكن للقسم `SecurityScreenGate` في الشجرة، كان المفتاحُ **يكذب**:
// المستخدمُ يشغّله ويضع كلمةً ويطمئنّ، والشاشةُ تُفتَح بلا سؤال.
//
// وهذا خطرٌ محدَّدٌ لا نظريّ: تصميمُ الإعدادات 2026-08-24 يعرض خمسةَ أقسامٍ
// منها **ثلاثةٌ لا بوّابةَ لها في التطبيق** — «شاشة المطبخ» و«المرتجعات»
// و«الخصم اليدوي». فلو نُقل التصميمُ حرفيّاً لظهرت ثلاثةُ أقفالٍ وهميّة.
//
// ⚠️ والقاعدة: **ما يعرضه التصميمُ ولا تحمله الشجرةُ لا يُعرَض**. وحين
// تُضاف بوّابةٌ حقيقيّةٌ لقسمٍ جديد، يُضاف مفتاحُه إلى السجلّ فيمرّ الحارس.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/settings_picpos/guarded_sections.dart';

/// ملفُّ السجلِّ نفسُه — **يُستثنى من المسح**.
///
/// ⚠️ وهذا ليس تفصيلاً: `PicPosGuardedSection` تحمل حقلاً اسمُه
/// `settingKey` أيضاً، فمسحُ السجلِّ يجعل كلَّ قسمٍ فيه «مربوطاً بنفسه»
/// ويمرُّ الحارسُ أخضرَ على قفلٍ وهميّ. أُمسك هذا في اختبار العضّ: أُضيف
/// «شاشة المطبخ» — بلا بوّابةٍ إطلاقاً — فبقي الحارسُ أخضر.
const _registryPath = 'lib/presentation/settings_picpos/guarded_sections.dart';

/// مفاتيحُ البوّابات المربوطةِ فعلاً في الشجرة.
Set<String> _wiredGateKeys(Directory lib) {
  final wired = <String>{};
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.replaceAll(r'\', '/').endsWith(_registryPath)) continue;
    final src = entity.readAsStringSync();
    for (final m in RegExp(r"settingKey:\s*'([a-z_]+)'").allMatches(src)) {
      wired.add(m.group(1)!);
    }
  }
  return wired;
}

void main() {
  test('كلُّ مفتاحٍ في سجلّ الحماية له SecurityScreenGate في الشجرة', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'يُشغَّل من جذر المستودع');

    final wired = _wiredGateKeys(lib);
    expect(wired, isNotEmpty,
        reason: 'لم يُعثر على أيّ بوّابة — تبدّل اسمُ المعامل؟');

    final phantom = <String>[];
    for (final section in kPicPosGuardedSections) {
      if (!wired.contains(section.settingKey)) {
        phantom.add('${section.title} (${section.settingKey})');
      }
    }

    expect(
      phantom,
      isEmpty,
      reason: 'قسمٌ في سجلّ الحماية بلا `SecurityScreenGate` في الشجرة.\n'
          'المفتاحُ المعروضُ له وعدٌ كاذب: يُشغَّل وتُوضَع كلمةٌ ثمّ تُفتَح '
          'الشاشةُ بلا سؤال.\n'
          'إمّا أن تُربَط البوّابةُ فعلاً، وإمّا أن يُحذَف القسمُ من السجلّ.\n'
          'الأقسام:\n  ${phantom.join('\n  ')}',
    );
  });

  test('وعددُ الشاشات المحميّةِ مقيسٌ لا مكتوبٌ بيد', () {
    // ⚠️ `accounting_access_password` يحمي **ستَّ** شاشاتٍ لا واحدة. والعددُ
    //    يُقاس من الشجرة، فلا يبطُل حين تُربَط شاشةٌ سابعة.
    final lib = Directory('lib');
    final counts = <String, int>{};
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // نفسُ الاستثناء — وإلّا عُدَّ السجلُّ نفسُه شاشةً محميّة.
      if (entity.path.replaceAll(r'\', '/').endsWith(_registryPath)) continue;
      final src = entity.readAsStringSync();
      for (final m in RegExp(r"settingKey:\s*'([a-z_]+)'").allMatches(src)) {
        counts.update(m.group(1)!, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    for (final section in kPicPosGuardedSections) {
      expect(
        countGuardedScreens(counts, section.settingKey),
        greaterThan(0),
        reason: '${section.title} — لا شاشةَ محميّةً فعلاً',
      );
    }
  });
}

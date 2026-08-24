// حارسٌ بنيويٌّ: أقسامُ إعدادات PicPos بلوكاتُ التصميم لا بطاقاتُ `ListTile`.
//
// ═══ العقدُ ═══
//
// تصميمُ الإعدادات (‏`PicPos-Settings-remote-2026-08-24.dc.html`) يرسم كلَّ
// قسمٍ **شبكةَ بلوكاتٍ باثني عشرَ عموداً**: لكلِّ بلوكٍ نوعٌ
// (`choice` · `values` · `switches` · `tiles`) و`span`. و`_buildSettingsCard`
// شكلٌ آخرُ تماماً: بطاقةٌ واحدةٌ بعمودٍ من `ListTile` متساوية.
//
// فبقاءُ بطاقةٍ واحدةٍ داخلَ شاشةٍ منقولةٍ إلى التصميم يُظهر واجهتَين
// مختلفتَين في شاشةٍ واحدة — وهو أظهرُ ما يكون حين ينتقل المستخدمُ بين
// قسمَين متجاورَين في العمود نفسِه.
//
// ═══ الأدواتُ جاهزة ═══
//
// `settings_picpos/widgets/settings_blocks.dart`:
// `SettingsBlockGrid` + `SettingsBlockSpan` · `SettingsBlock` ·
// `SettingsChoiceBlock` · `SettingsValueRow` + `SettingsRowsBody` ·
// `SettingsSwitchRow` · `SettingsTilesBlock` · `SettingsDangerRow`.
//
// ═══ ⚠️ وما لا يُختلَق ═══
//
// التصميمُ يعرض في مربّعاته أسطرَ حالةٍ برقمٍ («٤ طابعات معرّفة» ·
// «متصلة · 1.2 جيجا» · «٥ أيام عمل · ١١ عطلة»). تلك بياناتُ عرضٍ في ملفّ
// التصميم، وليست شيئاً تحمله القاعدةُ اليوم. فسطرُ الحالة يُكتب **وصفاً**
// لا عدّاداً، أو يُقرأ من مزوّدٍ حقيقيّ — ورقمٌ يكذب أسوأُ من لا رقم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('لا بطاقةَ ListTile في أقسام إعدادات PicPos', () {
    final file = File(
      'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart',
    );
    expect(file.existsSync(), isTrue, reason: 'يُشغَّل من جذر المستودع');

    final lines = file.readAsLinesSync();
    final offenders = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//')) continue;
      // النداءُ وحدَه مخالفةٌ — لا تعريفُ الدالّة، فهي تُحذَف بآخرِ نداء.
      if (!trimmed.contains('_buildSettingsCard(')) continue;
      if (trimmed.startsWith('Widget _buildSettingsCard(')) continue;
      offenders.add('${i + 1}');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'كلُّ موضعٍ هنا بطاقةُ `ListTile` داخلَ شاشةٍ رُسمت على '
          'بلوكات التصميم، فتظهر الشاشةُ بواجهتَين.\n'
          'حوِّلها إلى `SettingsBlockGrid` بأنواعِ التصميم وأبعادِه، '
          'واقرأ تخطيطَ القسم من `SECTIONS` في ملفّ التصميم قبل التحويل.\n'
          '⚠️ وسطرُ الحالةِ في المربّعات وصفٌ لا عدّادٌ مخترَع.\n'
          'الأسطر (${offenders.length}): ${offenders.join(' · ')}',
    );
  });
}

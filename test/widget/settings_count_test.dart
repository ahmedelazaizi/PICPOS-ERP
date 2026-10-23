// test/widget/settings_count_test.dart
//
// عدّادُ إعدادات القسم — يقيس أنّ الرقمَ مأخوذٌ من الشجرة لا مكتوبٌ بيد.
//
// ⚠️ **ولماذا اختبارٌ لا حارسٌ نصّيّ**: العطبُ هنا ليس سطراً يرتدّ بل **رقمٌ
// يكذب**. وحدَه العدُّ على شجرةٍ مبنيّةٍ يثبت أنّ الرقمَ يتبع الواقع: تُضاف
// صفوفٌ فيرتفع، ويُلَفّ البلوكُ بحاويةٍ فلا يتبدّل.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/settings_blocks.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/settings_count.dart';

SettingsValueRow _value(String t) =>
    SettingsValueRow(icon: PhosphorIconsBold.gear, title: t, value: '—');

SettingsSwitchRow _switch(String t) => SettingsSwitchRow(
      icon: PhosphorIconsBold.toggleRight,
      title: t,
      value: true,
      onChanged: (_) {},
    );

void main() {
  group('countVisibleSettings — يعدّ ما يُعرَض', () {
    test('الصفُّ الظاهرُ واحدٌ مهما كان نوعُه', () {
      expect(countVisibleSettings([_value('أ')]), 1);
      expect(countVisibleSettings([_switch('ب')]), 1);
      expect(countVisibleSettings([_value('أ'), _switch('ب')]), 2);
    });

    test('ويمشي داخلَ الشبكة والبلوك والجسم', () {
      final grid = SettingsBlockGrid(
        blocks: [
          SettingsBlockSpan(
            span: 7,
            child: SettingsBlock(
              title: 'كتلة',
              child: SettingsRowsBody(
                children: [_value('أ'), _value('ب'), _switch('ج')],
              ),
            ),
          ),
          SettingsBlockSpan(
            span: 5,
            child: SettingsBlock(
              title: 'أخرى',
              child: SettingsRowsBody(children: [_switch('د')]),
            ),
          ),
        ],
      );
      expect(countVisibleSettings([grid]), 4);
    });

    test('وكلُّ مربّعٍ في كتلة المربّعات واحد', () {
      final tiles = SettingsTilesBlock(
        tiles: [
          SettingsTile(
            icon: PhosphorIconsBold.database,
            title: 'قاعدة البيانات',
            sub: '—',
            meta: '—',
            tint: const Color(0xFF0250D3),
            onTap: () {},
          ),
          SettingsTile(
            icon: PhosphorIconsBold.network,
            title: 'الربط',
            sub: '—',
            meta: '—',
            tint: const Color(0xFF0250D3),
            onTap: () {},
          ),
        ],
      );
      expect(countVisibleSettings([tiles]), 2);
    });

    test('وبلوكٌ لا يُرى داخلَه شيءٌ معروف يُعَدُّ واحداً لا صفراً', () {
      // ⚠️ هذا البندُ هو الفرقُ بين رقمٍ صادقٍ وصفرٍ كاذب. قسمُ «البيع
      //    السريع» كلُّ بلوكاته بطاقاتٌ خاصّةٌ تفتح حوارات — فبغير هذا البند
      //    كان يقرأ صفراً وهو أكثفُ أقسام الإعدادات.
      const opaque = SettingsBlock(
        title: 'إعدادات البيع السريع',
        child: SizedBox(width: 10, height: 10),
      );
      expect(countVisibleSettings([opaque]), 1);
    });

    test('والاختيارُ إعدادٌ واحدٌ لا بعددِ خياراته', () {
      final choice = SettingsChoiceBlock<String>(
        selected: 'dark',
        onSelect: (_) {},
        options: const [
          SettingsChoiceOption(value: 'light', label: 'فاتح', sub: '—'),
          SettingsChoiceOption(value: 'dark', label: 'غامق', sub: '—'),
          SettingsChoiceOption(value: 'auto', label: 'تلقائي', sub: '—'),
        ],
      );
      expect(countVisibleSettings([choice]), 1,
          reason: 'الاختيارُ بثلاثةِ خياراتٍ عُدَّ أكثرَ من إعدادٍ واحد — '
              'فالرقمُ يتضخّم بعددِ الخيارات لا بعددِ ما يُغيَّر.');
    });

    test('والصفرُ يعود `null` فلا تُرسَم شارةُ «٠»', () {
      // قسمُ «عن البرنامج» يبني بطاقاتٍ خاصّةً لا يعرفها العدّاد، فيعود
      // بصفر. و«٠ إعداد» بجانب قسمٍ فيه أربعُ بطاقاتٍ كذبٌ كالرقم المخترَع.
      expect(countVisibleSettingsOrNull([const SizedBox.shrink()]), isNull);
      expect(countVisibleSettingsOrNull([_value('أ')]), 1);
    });

    test('ولفُّ البلوك بحاويةٍ لا يبدّل الرقم', () {
      // الأقسامُ تركّب `Column`/`Padding` حولَ بلوكاتها أحياناً — ورقمٌ
      // يتبدّل بالتغليف رقمٌ لا يُعتمد عليه.
      final rows = SettingsRowsBody(children: [_value('أ'), _switch('ب')]);
      final bare = SettingsBlock(title: 'ك', child: rows);
      expect(
        countVisibleSettings([
          Padding(padding: EdgeInsets.zero, child: Column(children: [bare])),
        ]),
        countVisibleSettings([bare]),
      );
    });
  });

  group('شريحةُ «آخر تعديل» — أُلغيت بقرار', () {
    test('لا ذكرَ لها في عمود الأقسام', () {
      // قرارُ المالك 2026-08-25: «الغية مش نحتاجه». وجدولُ `Settings` عمودان
      // (`key`/`value`) بلا `updatedAt`، فعرضُها كان يقتضي هجرةَ قاعدةٍ
      // وختمَ وقتٍ في كلّ كتابة — كلفةٌ لشريحةٍ لا تُطلَب.
      //
      // ويبقى هذا الحارسُ ليمنع إحياءَها من ملفّ التصميم بلا قرارٍ جديد.
      const rail = 'lib/presentation/settings_picpos/widgets/'
          'settings_nav_rail.dart';
      final src = (rail.isEmpty ? '' : _read(rail))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(src.contains('آخر تعديل'), isFalse,
          reason: 'عادت شريحةُ «آخر تعديل» إلى عمود الأقسام. جدولُ '
              '`Settings` بلا `updatedAt` — فالنصُّ سيعرض وقتاً لا مصدرَ له. '
              'إحياؤها يحتاج هجرةَ قاعدةٍ وقراراً من المالك.');
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

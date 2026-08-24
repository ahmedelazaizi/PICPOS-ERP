import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يُسقط أسطرَ التعليق قبل الفحص — حارسُ نصٍّ يقرأ التعليقاتِ يقيس كلاماً لا
/// واجهة. (وقع ذلك فعلاً في `settings_unified_header_test`.)
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// حرّاسُ لوحات الإعدادات (`PANELS` و`BENCH` في ملفّ التصميم) والفوركات
/// الستّة.
///
/// ═══ لماذا حارسٌ بنيويّ ═══
///
/// العطبُ هنا **سطرُ فتحٍ**: يكفي أن يعود `showXDialog(context)` بلا
/// `picpos: true` ليعود الحوارُ إلى `AlertDialog` بلا أن ينهار شيء. واختبارُ
/// الودجت يفتح الحوارَ المقصودَ فيمرّ وهو لا يرى سطرَ الفتح.
void main() {
  final hub = _code(File(
    'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart',
  ).readAsStringSync());

  group('الحواراتُ تُفتَح بغلاف PicPos', () {
    const openers = {
      'showCompanyInfoDialog': 'معلومات الشركة',
      'showHardwareSettingsDialog': 'إعدادات الأجهزة',
      'showPosSettingsDialog': 'إعدادات البيع السريع',
      'showPermissionsManagementDialog': 'إدارة الصلاحيات',
      'showActivationDialog': 'تفعيل الترخيص',
    };

    for (final e in openers.entries) {
      test('${e.key} تُنادى بـ`picpos: true`', () {
        expect(hub.contains('${e.key}(context)'), isFalse,
            reason: 'مركزُ إعدادات PicPos ينادي `${e.key}` بلا '
                '`picpos: true` — فحوارُ «${e.value}» يعود إلى '
                '`AlertDialog` بهويّة UralCash.');
        expect(hub.contains('${e.key}(context, picpos: true)'), isTrue,
            reason: 'لا نداءَ لـ`${e.key}` بـ`picpos: true` في المركز.');
      });
    }
  });

  group('AppFormDialog — الرافعةُ المشتركة', () {
    final base = _code(
      File('lib/presentation/widgets/dialogs/app_form_dialog.dart')
          .readAsStringSync(),
    );

    test('تتفرّع إلى PicPosDialog بـ`Brand.isPicPos`', () {
      // ثلاثةَ عشرَ حواراً ترث هذه القاعدة، ومنها خمسٌ من لوحات التصميم.
      // فارتدادُ هذا السطرِ وحدَه يُسقط الهويّةَ عنها كلِّها دفعةً.
      expect(
        RegExp(r'Brand\.isPicPos\s*\)?\s*\)?\s*return\s+_buildPicposDialog')
            .hasMatch(base),
        isTrue,
        reason: '`AppFormDialog` لا تتفرّع إلى `PicPosDialog` عند '
            '`Brand.isPicPos` — فخمسُ لوحاتٍ من التصميم تعود إلى '
            '`AlertDialog` دفعةً واحدة.',
      );
    });

    test('و`Form` باقٍ حولَ المحتوى في الفرعَين', () {
      // `formKey.currentState?.validate()` يقرأ من هذا الـ`Form`. إسقاطُه في
      // فرعِ PicPos يجعل كلَّ تحقّقٍ من الحقول يمرّ صامتاً — وهو عطبٌ لا
      // يُرى: الحوارُ يحفظ، والقيمةُ الخاطئةُ تدخل.
      // ⚠️ النمطُ يتسامح مع سطرَين: فرعُ UralCash يكتب `Form(` ثمّ
      //    `key: formKey,` على السطر التالي. نمطٌ يشترط التجاورَ أعطى ١ لا ٢
      //    وأحمرَّ على كودٍ سليم — وهو عينُ فخِّ القياس الضيّق.
      expect(RegExp(r'Form\(\s*key:\s*formKey').allMatches(base).length,
          greaterThanOrEqualTo(2),
          reason: 'أحدُ فرعَي `AppFormDialog` بلا `Form(key: formKey)` — '
              'فالتحقّقُ من الحقول يمرّ صامتاً فيه.');
    });
  });

  group('لوحاتُ التصميم تحمل اسمَ زرِّ الحفظ الذي يعطيه', () {
    const labels = {
      'set_pin_dialog': 'حفظ الـ PIN',
      'reset_password_dialog': 'حفظ كلمة المرور',
      'branch_access_dialog': 'حفظ النطاق',
      'warehouse_access_dialog': 'حفظ النطاق',
      'add_role_dialog': 'إنشاء الدور',
      'add_user_dialog': 'حفظ المستخدم',
    };

    for (final e in labels.entries) {
      test('${e.key} → «${e.value}»', () {
        final src = _code(
          File('lib/presentation/screens/settings/widgets/${e.key}.dart')
              .readAsStringSync(),
        );
        expect(src.contains("dialogSaveLabel => '${e.value}'"), isTrue,
            reason: '${e.key} بلا `dialogSaveLabel` = «${e.value}» — '
                'فزرُّ الحفظ يقول «حفظ» عامّاً بدل ما يسمّيه التصميم.');
      });
    }
  });

  group('لا يُرسَم ما لا يعمل', () {
    test('لوحةُ التفعيل لا تعرض «تفعيل بملف ترخيص» مفتاحاً', () {
      // التفعيلُ بملفٍّ موجودٌ فعلاً لكنّه **كشفٌ تلقائيّ** في كلّ إقلاع
      // (`LicenseService.isActivated()` يفحص license.txt وأخواتِها)، لا وضعٌ
      // يُبدَّل. فمفتاحٌ يوهم بالاختيار كذبٌ على المستخدم.
      final src = _code(
        File('lib/presentation/widgets/settings/activation_dialog.dart')
            .readAsStringSync(),
      );
      final hasFileToggle = RegExp(
        r'SettingsSwitchRow\([\s\S]{0,200}?ملف ترخيص|'
        r'Switch\([\s\S]{0,200}?ملف ترخيص',
      ).hasMatch(src);
      expect(hasFileToggle, isFalse,
          reason: 'أُضيف مفتاحُ «تفعيل بملف ترخيص» إلى لوحة التفعيل. '
              'التفعيلُ بملفٍّ تلقائيٌّ لا يُبدَّل — والمفتاحُ يوهم بخيارٍ '
              'لا وجودَ له. اجعلْه بياناً يشرح أين يوضع الملفّ.');
    });

    test('ولا تَعِد بفكِّ تفعيلٍ غيرِ موجود', () {
      // `deactivate` ميزةٌ غيرُ مبنيّةٍ في التطبيق (مقيسٌ 2026-08-24).
      final src = _code(
        File('lib/presentation/widgets/settings/activation_dialog.dart')
            .readAsStringSync(),
      );
      expect(src.contains('فك التفعيل'), isFalse,
          reason: 'نصُّ لوحة التفعيل يذكر «فك التفعيل» — وهي ميزةٌ غيرُ '
              'موجودةٍ في البرنامج. النقلُ لجهازٍ آخر يحتاج مفتاحاً جديداً.');
    });
  });

  group('الجسمُ لا يحمل زرَّ حفظٍ ثانياً في غلاف PicPos', () {
    const bodies = {
      'pos_settings_widget': 'حفظ الإعدادات',
      'hardware_settings_widget': 'حفظ الإعدادات',
    };

    for (final e in bodies.entries) {
      test('${e.key} يعيد الأقسامَ وحدَها عند `picposChrome`', () {
        // زرّان للحفظ في حوارٍ واحدٍ يجعل المستخدمَ لا يعرف أيُّهما يحفظ.
        final src = _code(
          File('lib/presentation/widgets/settings/${e.key}.dart')
              .readAsStringSync(),
        );
        expect(
          RegExp(r'if\s*\(widget\.picposChrome\)\s*return\s+sections;')
              .hasMatch(src),
          isTrue,
          reason: '${e.key} لا يقصّر جسمَه عند `picposChrome` — '
              'فيظهر زرُّ «${e.value}» داخلَ الجسم وزرٌّ آخرُ في تذييل '
              '`PicPosDialog`.',
        );
      });
    }
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/library_source.dart';
import 'package:picpos_erp/presentation/widgets/settings/company_info_widget.dart';

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
  final hub = _code(readLibrarySource(
    'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart',
  ));

  group('الحواراتُ تُفتَح بغلاف PicPos', () {
    const openers = {
      'showCompanyInfoDialog': 'معلومات الشركة',
      'showHardwareSettingsDialog': 'إعدادات الأجهزة',
      'showPosSettingsDialog': 'إعدادات البيع السريع',
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

  group('مصفوفةُ الصلاحيات — نسخةُ PicPos', () {
    // ⚠️ **حلّ محلَّ حارسٍ أقدم.** كان يشترط أن ينادي المركزُ
    // `showPermissionsManagementDialog(context, picpos: true)` — أي الشاشةَ
    // المشتركةَ بغلاف PicPos. وبلّغ المالكُ 2026-08-25 أنّ ذلك **ليس
    // التصميمَ المطلوب**: `BENCH.perms` مصفوفةٌ لا دورٌ واحدٌ في كلّ مرّة.
    //
    // فالعقدُ الآن أضيقُ لا أوسع: المركزُ يفتح **نسخةَ PicPos**، والشاشةُ
    // المشتركةُ تبقى لمسار UralCash وحدَه ولا يمسّها المركز.
    test('المركزُ يفتح `showPermissionsMatrixPicpos` لا الشاشةَ المشتركة', () {
      expect(hub.contains('showPermissionsMatrixPicpos(context)'), isTrue,
          reason: 'مركزُ إعدادات PicPos لا يفتح مصفوفةَ الأدوار — '
              'رجع إلى شاشةٍ بدورٍ واحدٍ في كلّ مرّة.');
      expect(hub.contains('showPermissionsManagementDialog'), isFalse,
          reason: 'المركزُ ما زال ينادي الشاشةَ المشتركة — والنسخةُ تصير '
              'ملفّاً ميّتاً لا يراه المالك.');
    });

    test('والشاشةُ المشتركةُ باقيةٌ ومركزُ UralCash يفتحها', () {
      // النسخُ لا يعني الحذف: مسارُ UralCash يجب أن يبقى عاملاً.
      expect(
        File('lib/presentation/widgets/settings/permissions_management_widget.dart')
            .existsSync(),
        isTrue,
        reason: 'حُذفت الشاشةُ المشتركةُ — ومسارُ UralCash يفقد إدارةَ '
            'الصلاحيات كلَّها.',
      );
      final ural = _code(
        File('lib/presentation/screens/settings_screen.dart').readAsStringSync(),
      );
      expect(ural.contains('showPermissionsManagementDialog'), isTrue,
          reason: 'مركزُ إعدادات UralCash لم يعد يفتح شاشةَ الصلاحيات.');
    });
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
        final saveLabel = RegExp(
          r"dialogSaveLabel\s*=>\s*(?:tr\(\s*)?'"
          '${RegExp.escape(e.value)}'
          r"'(?:\s*\))?",
        );
        expect(saveLabel.hasMatch(src), isTrue,
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
      test('${e.key} يخرج قبل زرِّ الحفظ عند `picposChrome`', () {
        // زرّان للحفظ في حوارٍ واحدٍ يجعل المستخدمَ لا يعرف أيُّهما يحفظ.
        //
        // ⚠️ **يُقاس الترتيبُ لا التهجئة.** كانت الصياغةُ تشترط
        // `return sections;` حرفاً بحرف، فسقطت حين صار جسمُ «البيع السريع»
        // يعيد `_buildDesignLayout()` (‏§٣ — تخطيطُ التصميم) وهو **يحقّق
        // الشرطَ نفسَه**: خروجٌ مبكّرٌ قبل الزرّ. أي أنّ الحارسَ كان يحرس
        // اسمَ متغيّرٍ لا الخاصّيّةَ التي يدّعيها.
        //
        // والخاصّيّةُ الحقيقيّةُ شرطان: خروجٌ مبكّرٌ على `picposChrome`،
        // وزرُّ الحفظِ **بعده** في المصدر فلا يبلغه ذلك المسار.
        final src = _code(
          File('lib/presentation/widgets/settings/${e.key}.dart')
              .readAsStringSync(),
        );

        final early = RegExp(
          r'if\s*\(widget\.picposChrome\)\s*return\s+[^;]+;',
        ).firstMatch(src);

        expect(early, isNotNull,
            reason: '${e.key} لا يقصّر جسمَه عند `picposChrome` — '
                'فيظهر زرُّ «${e.value}» داخلَ الجسم وزرٌّ آخرُ في تذييل '
                '`PicPosDialog`.');

        final button = RegExp(
          r'ElevatedButton\s*\(\s*onPressed:\s*_saveSettings',
        ).firstMatch(src)?.start ?? -1;
        expect(button, greaterThan(-1),
            reason: 'زرُّ الحفظِ لم يُعثر عليه في ${e.key} — تغيّرت صياغتُه '
                'فصار الحارسُ يقيس عدماً.');
        expect(button, greaterThan(early!.start),
            reason: 'زرُّ «${e.value}» يقع **قبل** الخروجِ المبكّر في '
                '${e.key}، فيراه غلافُ PicPos ويصير في الحوار زرّا حفظ.');
      });
    }
  });

  group('لا حواراتِ Material الافتراضيّة في واجهة PicPos', () {
    /// ═══ البلاغُ ═══
    ///
    /// أرسل المالكُ صوراً 2026-08-25 لمنتقي «اختر نوع النشاط» بشكل
    /// `SimpleDialog` العاري، وقال إنّ «حوارات ونوافذ التصميم القديم لا زالت
    /// موجودة، وهذا غير مطابق للتصميم الجديد المميّز الذي يجعل النظام فريداً
    /// لذاته وليس مشابهاً لشكل UralCash مع فرق الألوان».
    ///
    /// ومقيسٌ أنّها كانت **خمسةً** في فورك الإعدادات: نوعُ النشاط · عملةُ
    /// النظام · سياسةُ نقص الخامات · مهلةُ الجلسة · مظهرُ التطبيق. وكلُّها
    /// صارت `showPicPosOptionPicker`.
    ///
    /// ⚠️ ولا يُقاس `AlertDialog` هنا: بعضُ حوارات التأكيد الصغيرة تستعملها
    /// مشروعةً عبر `AppConfirmDialog` وغيرِه. المقيسُ `SimpleDialog` وحدَها —
    /// وهي **منتقي خيارٍ** بالتعريف، وله بديلٌ واحدٌ على الهويّة.
    const forkFiles = [
      'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart',
      'lib/presentation/settings_picpos/screens/general_settings_widgets_picpos.dart',
      'lib/presentation/settings_picpos/screens/admin_home_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/cfd_settings_card_picpos.dart',
      'lib/presentation/settings_picpos/screens/network_mode_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/payment_methods_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/scale_barcode_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/touch_input_settings_picpos.dart',
    ];

    for (final path in forkFiles) {
      test('${path.split('/').last} بلا SimpleDialog', () {
        final f = File(path);
        if (!f.existsSync()) return;
        // `_code` يُسقط أسطرَ التعليق — فالتعليقُ الذي يشرح التحويلَ لا
        // يُحسَب حواراً عائداً. (وقع ذلك فعلاً في حارسٍ سابق.)
        final src = _code(f.readAsStringSync());
        expect(src.contains('SimpleDialog'), isFalse,
            reason: 'عاد `SimpleDialog` إلى ${path.split('/').last}. '
                'منتقي الخيار في واجهة PicPos هو '
                '`showPicPosOptionPicker` — يأخذ رأسَ `PicPosDialog` '
                'وتذييلَه، ولا يُطبِّق الاختيارَ باللمس بل بزرِّ «تطبيق».');
      });
    }
  });

  // ═══════════ عمودُ أرقام المجموعات (`panel.index`) ═══════════
  //
  // اختبارُ الودجت يقيس أنّ العمودَ يوافق المجموعاتِ **في الشجرة**. وما لا
  // يراه هو المصدر: قائمةٌ حرفيّةٌ تُكتب بجانب الجسم، ثمّ تُضاف مجموعةٌ ولا
  // تُضاف معها — فيمرّ اختبارُ الودجت على لوحةٍ يبنيها هو، ويكذب العمودُ في
  // اللوحة الحقيقيّة. هذا الحارسُ يقفل ذلك البابَ في `lib/` كلِّه.
  group('عمودُ الأرقام مشتقٌّ من المجموعات لا مكتوبٌ بيد', () {
    test('لا موضعَ في lib يكتب `indexLabels` قائمةً حرفيّة', () {
      final offenders = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (RegExp(r'indexLabels:\s*(const\s+)?\[')
            .hasMatch(_code(e.readAsStringSync()))) {
          offenders.add(e.path.replaceAll(r'\', '/'));
        }
      }
      expect(offenders, isEmpty,
          reason: 'قائمةٌ حرفيّةٌ في `indexLabels` — اشتقّها من المجموعات '
              'بـ`picposPanelLabels(groups)`، أو من ثابتٍ واحدٍ تبني منه '
              'المجموعاتُ عناوينَها. الرقمُ الذي يكذب أسوأُ من لا رقم.');
    });

    test('لوحةُ الشركة: كلُّ مجموعةٍ عنوانُها من `picposGroupLabels`', () {
      final src = _code(
        File('lib/presentation/widgets/settings/company_info_widget_io.dart')
            .readAsStringSync(),
      );
      final groups = RegExp(r'PicPosPanelGroup\(').allMatches(src).length;
      final fromConst =
          RegExp(r'picposGroupLabels\[\d+\]').allMatches(src).length;
      expect(groups, greaterThan(0));
      expect(fromConst, groups,
          reason: 'مجموعةٌ في لوحة الشركة عنوانُها مكتوبٌ حرفيّاً لا مأخوذٌ '
              'من `CompanyInfoWidget.picposGroupLabels` — فالعمودُ يُرسم من '
              'الثابت والجسمُ من مكانٍ آخر، وهما ينحرفان.');
      expect(CompanyInfoWidget.picposGroupLabels.length, groups,
          reason: 'طولُ `picposGroupLabels` يخالف عددَ المجموعات المبنيّة — '
              'فالعمودُ يعِد برقمٍ لا مجموعةَ تحته.');
      expect(src.contains('indexLabels: CompanyInfoWidget.picposGroupLabels'),
          isTrue,
          reason: 'حوارُ الشركة لا يمرّر `indexLabels` — فاللوحةُ بلا عمود.');
    });

    test('ورافعةُ `AppFormDialog` تشتقُّه من `buildPicposGroups`', () {
      final base = _code(
        File('lib/presentation/widgets/dialogs/app_form_dialog.dart')
            .readAsStringSync(),
      );
      expect(base.contains('indexLabels: picposPanelLabels(groups)'), isTrue,
          reason: 'رافعةُ اللوحات لا تمرّر عمودَ الأرقام.');
      expect(base.contains('picposPanelBody(groups)'), isTrue,
          reason: 'رافعةُ اللوحات لا تبني الجسمَ من المجموعات.');
    });

    test('ولوحةُ التفعيل تشتقُّها بـ`picposPanelLabels`', () {
      final src = _code(
        File('lib/presentation/widgets/settings/activation_dialog.dart')
            .readAsStringSync(),
      );
      expect(src.contains('indexLabels: picposPanelLabels(groups)'), isTrue,
          reason: 'لوحةُ التفعيل لا تشتقُّ عمودَها من مجموعاتها.');
    });
  });

  // ═══════════ بنيةُ اللوحة تُضاف ولا تحلّ محلَّ جسم UralCash ═══════════
  //
  // الحواراتُ الأربعةُ هنا **مشتركة**: فرعُ UralCash يقرأ `buildFormContent`
  // وفرعُ PicPos يقرأ `buildPicposGroups`. والشرطُ الذي يجعل النقلَ مشروعاً
  // أنّ الأوّلَ لا يتبدّل فيه بايت — فهذا الحارسُ يمسك «التنظيفَ» الذي يحذف
  // الجسمَ القديمَ بعد أن صار له بديلٌ يبدو أجمل.
  //
  // ⚠️ ولا يُقاس بالعينِ ولا بـ`git`: أثرُ الحذف علامتُه سطرٌ يختفي، وهذا
  //    ما يُفحَص — وجودُ العلامة التي لا يعرفها إلّا جسمُ UralCash.
  group('لوحاتُ AppFormDialog — جسمان لا جسمٌ واحد', () {
    const panels = {
      'branch_access_dialog': 'CheckboxListTile',
      'warehouse_access_dialog': 'CheckboxListTile',
      'set_pin_dialog': 'تنبيه: يُستخدم رمز PIN',
      'add_role_dialog': 'buildFormContent',
      'reset_password_dialog': 'CheckboxListTile',
      'add_user_dialog': 'RadioListTile',
    };

    for (final e in panels.entries) {
      test('${e.key}: بنيةُ PicPos مضافةٌ وجسمُ UralCash باقٍ', () {
        final src = _code(
          File('lib/presentation/screens/settings/widgets/${e.key}.dart')
              .readAsStringSync(),
        );
        expect(src.contains('List<PicPosPanelGroup> buildPicposGroups'), isTrue,
            reason: '${e.key} لم تعد لوحةً بمجموعاتٍ في غلاف PicPos.');
        expect(src.contains(e.value), isTrue,
            reason: 'جسمُ UralCash في ${e.key} تبدّل أو حُذف — والنقلُ إلى '
                'هويّة PicPos مشروطٌ بأنّ الفرعَ الآخرَ لا يتبدّل فيه بايت.');
      });
    }

    test('ولوحةُ إعادة التعيين تقرأ القواعدَ من `SecurityService`', () {
      // ⚠️ البديلُ السهلُ أن ترسم اللوحةُ قواعدَها بنفس التعابير النمطيّة —
      //    فتصير سياسةُ كلمة المرور في مكانين ينحرفان صامتَين.
      for (final f in ['reset_password_dialog', 'add_user_dialog']) {
        final src = _code(
          File('lib/presentation/screens/settings/widgets/$f.dart')
              .readAsStringSync(),
        );
        expect(src.contains('SecurityService.passwordRules'), isTrue,
            reason: '$f: شبكةُ القواعد لا تُقرأ من `SecurityService`.');
        expect(RegExp(r"RegExp\(r?'\[A-Z\]").hasMatch(src), isFalse,
            reason: '$f: أعادت اللوحةُ كتابةَ قاعدةٍ من قواعد السياسة — '
                'وهي في `SecurityService` وحدَه.');
      }
    });

    test('وتحذيرُ «كل الفروع» انتقل بشرطه إلى لوحة PicPos', () {
      final src = _code(
        File('lib/presentation/screens/settings/widgets/add_user_dialog.dart')
            .readAsStringSync(),
      );
      // ⚠️ **لا يُفحَص الملفُّ كلُّه.** الرمزُ فيه ثلاثَ مرّات: فرعُ PicPos،
      //    وفرعُ UralCash، و`onSave`. فـ`contains` على الملفّ يمرّ ولو سقط
      //    الشرطُ من فرعٍ كامل — ومرّت عليه طفرةٌ فعلاً قبل أن يُحصَر
      //    الفحصُ في جسم `buildPicposGroups` وحدَه.
      final from = src.indexOf('List<PicPosPanelGroup> buildPicposGroups');
      final to = src.indexOf('Widget buildFormContent');
      expect(from, greaterThan(0), reason: 'لوحةُ PicPos غائبةٌ عن الحوار.');
      expect(to, greaterThan(from),
          reason: 'ترتيبُ الملفّ تبدّل — أصلح حدودَ الفحص لا تتجاوزه.');
      final picpos = src.substring(from, to);

      expect(picpos.contains('fullBranchAccessRoleNames'), isTrue,
          reason: 'لوحةُ PicPos لا تحسب شرطَ «كل الفروع» — فالتحذيرُ إمّا '
              'دائمٌ أو غائب.');
      expect(picpos.contains('لن يرى'), isTrue,
          reason: 'نصُّ التحذير سقط من لوحة PicPos: «كل الفروع» بلا إسنادٍ '
              'يُخرج المستخدمَ بلا فرعٍ فلا يرى فاتورةً أصدرها بنفسه.');
    });

    test('ولوحتا النطاق تستعملان الشرائحَ لا مربّعاتِ الاختيار', () {
      for (final f in ['branch_access_dialog', 'warehouse_access_dialog']) {
        final src = _code(
          File('lib/presentation/screens/settings/widgets/$f.dart')
              .readAsStringSync(),
        );
        expect(src.contains('PicPosPanelChip('), isTrue,
            reason: '$f: التصميمُ يرسم النطاقَ `kind:\'chips\'`، والمبنيُّ '
                'صفوفُ `CheckboxListTile`.');
        expect(src.contains('tooltip:'), isTrue,
            reason: '$f: الشريحةُ عنوانٌ وحدَه — والسطرُ الثاني الذي كان '
                'يعرضه الصفُّ لا بدّ أن يبقى مقروءاً في التلميح، وإلّا كان '
                'النقلُ حذفَ بيان.');
      }
    });
  });

  // ═══════════ اللوحتان اللتان كانتا `AlertDialog` خاماً ═══════════
  //
  // «طابعة جديدة» و«عطلة جديدة» لوحتان في التصميم، وكانتا حوارَي Material
  // عاريَين داخلَ شاشتَين **مشتركتَين** — فخرجتا من حارس `settings_picpos`
  // الذي يمسح مجلَّدَ الفورك وحدَه.
  //
  // ⚠️ والخطرُ هنا ليس الشكلَ بل **الحقلَ الذي يسقط في الطريق**: فرعٌ جديدٌ
  //    يستدعي نفسَ دالّة الحفظ بمعاملاتٍ أقلَّ يحفظ طابعةً بلا منفذٍ أو عطلةً
  //    بلا فرعٍ — بلا خطأٍ ولا إنذار.
  group('لوحتا الطابعة والعطلة — فرعٌ لـPicPos وحفظٌ بلا نقصان', () {
    String read(String p) => _code(File(p).readAsStringSync());

    const printers = 'lib/presentation/screens/printers_screen.dart';
    const holidays =
        'lib/presentation/screens/settings/work_holidays_screen.dart';

    for (final e in {'الطابعة': printers, 'العطلة': holidays}.entries) {
      test('لوحةُ ${e.key}: غلافُ PicPos مضافٌ وحوارُ UralCash باقٍ', () {
        final src = read(e.value);
        expect(src.contains('Brand.isPicPos'), isTrue,
            reason: '${e.value}: لا فرعَ لهويّة PicPos — فاللوحةُ تظهر '
                'حوارَ Material خاماً في أظهرِ لحظة.');
        expect(src.contains('PicPosDialog('), isTrue);
        expect(src.contains('AlertDialog('), isTrue,
            reason: '${e.value}: حوارُ UralCash حُذف — والنقلُ مشروطٌ بأنّ '
                'الفرعَ الآخرَ لا يتبدّل فيه بايت.');
      });
    }

    test('وحفظُ الطابعة يمرّر كلَّ حقولها في الفرعَين', () {
      final src = read(printers);
      // ⚠️ لا يُفحَص اسمُ المعامل وحدَه: `printerType: printerType` مكرّرٌ
      //    داخلَ `_savePrinter` نفسِها، فعدُّه يمرّ ولو سقط من نداءٍ كامل.
      //    فالمفحوصُ الصيغُ التي لا تظهر إلّا في موضعَي النداء.
      const args = [
        'name: nameController.text',
        'port: portController.text',
        'ipAddress: ipController.text',
        'portNumber: int.tryParse(portNumberController.text)',
        'description: descriptionController.text',
        'purpose: printerPurpose',
      ];
      for (final a in args) {
        expect(RegExp(RegExp.escape(a)).allMatches(src).length, 2,
            reason: 'المعاملُ «$a» ليس في موضعَي النداء كلَيهما — فأحدُ '
                'الفرعَين يحفظ طابعةً ناقصةَ حقلٍ بلا خطأ.');
      }
    });

    test('وحفظُ العطلة يمرّر كلَّ حقولها في الفرعَين', () {
      final src = read(holidays);
      const args = [
        'name: nameCtrl.text',
        'weekday: isWeekday ? weekday : null',
        'date: isWeekday ? null : date',
        'branchId: branchId',
      ];
      for (final a in args) {
        expect(RegExp(RegExp.escape(a)).allMatches(src).length, 2,
            reason: 'المعاملُ «$a» ليس في موضعَي النداء كلَيهما — فأحدُ '
                'الفرعَين يحفظ عطلةً ناقصةَ حقل.');
      }
    });
  });
}

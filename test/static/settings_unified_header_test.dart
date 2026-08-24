import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// يُسقط أسطرَ التعليق (`//` و`///`) قبل الفحص.
///
/// ⚠️ ضروريّةٌ لا تجميليّة: أوّلُ صياغةٍ لحارسِ «نقطة بيع جديدة» احمرّت على
/// **التعليقِ الذي يشرح سببَ حذفِ الزرّ** لا على زرٍّ عائد. حارسٌ يقرأ
/// التعليقاتِ يقيس كلاماً لا واجهة، ويعلّم المطوّرَ أن يسكت عن الشرح.
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// حرّاسُ الترويسة الموحّدة لشاشات الإعدادات الفرعيّة (`HEADS` في ملفّ
/// التصميم `PicPos Settings.dc.html`).
///
/// التصميمُ يعطي كلَّ شاشةٍ فرعيّةٍ ترويسةً واحدة: أيقونةٌ + عنوانٌ + مسارٌ
/// («الإعدادات ← …»). ومركزُ إعدادات PicPos يدفع سبعَ شاشاتٍ من `HEADS`؛
/// كلُّها لا بدّ أن تُفتَح بقشرةِ PicPos لا بالقشرة المشتركة.
///
/// ولمَ حارسٌ بنيويٌّ لا اختبارُ ودجت: العطبُ هنا **سطرُ دفعٍ** — يكفي أن
/// يعود `Navigator.push` إلى الشاشة المشتركة لتضيع الترويسةُ بلا أن ينهار
/// شيء. واختبارُ الودجت يفتح الشاشةَ المقصودةَ فيمرّ وهو لا يرى سطرَ الدفع.
void main() {
  final hub = File(
    'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart',
  ).readAsStringSync();

  group('الترويسةُ الموحّدة — سطرُ الدفع', () {
    /// المفتاحُ في `HEADS` ← الصنفُ الذي **يجب** أن يدفعه المركز.
    const expected = {
      'printers': 'PrintersPicposScreen',
      'terminals': 'PosTerminalsPicposScreen',
      'holidays': 'WorkHolidaysPicposScreen',
      'delivery': 'DeliveryManagementPicposScreen',
      'devtools': 'DeveloperToolsPicposScreen',
      'accmap': 'AccountMappingPicPosScreen',
    };

    for (final e in expected.entries) {
      test('مركزُ الإعدادات يدفع ${e.value} (HEADS.${e.key})', () {
        expect(
          RegExp(r'const\s+' '${e.value}' r'\(\)').hasMatch(hub),
          isTrue,
          reason: 'مركزُ إعدادات PicPos لا يدفع `${e.value}`. '
              'شاشةُ «${e.key}» في التصميم لها ترويسةٌ موحّدة، '
              'ودفعُ القشرة المشتركة بدلاً منها يُسقط الترويسةَ صامتاً.',
        );
      });
    }

    test('مصمّمُ الفواتير يُفتَح بـ`picposChrome: true`', () {
      // ليس صنفاً مستقلّاً بل رايةٌ على الشاشة المشتركة — بنيتُه mixins في
      // ملفّات `part` فلا يُستخرَج جسمُه كبقيّة الشاشات.
      expect(
        RegExp(r'InvoiceDesignerScreen\(\s*picposChrome:\s*true\s*,?\s*\)')
            .hasMatch(hub),
        isTrue,
        reason: 'مركزُ إعدادات PicPos يفتح مصمّمَ الفواتير بلا '
            '`picposChrome: true` — فيأخذ `AppBar` المشتركة لا ترويسةَ PicPos.',
      );
    });

    test('ولا يدفع أيّاً من القشور المشتركة', () {
      const shared = [
        'PrintersScreen',
        'PosTerminalsScreen',
        'WorkHolidaysScreen',
        'DeliveryManagementScreen',
        'DeveloperToolsScreen',
        'AccountMappingSettingsScreen',
      ];
      for (final s in shared) {
        // `const X()` وحدَه — فلا يطابق `const XPicposScreen()`.
        expect(
          RegExp(r'const\s+' '$s' r'\(\s*\)').hasMatch(hub),
          isFalse,
          reason: 'مركزُ إعدادات PicPos ما زال يدفع `$s` المشتركةَ '
              '(‏قشرةُ UralCash) بدل قشرة PicPos.',
        );
      }
    });
  });

  group('استخراجُ الجسم — لا نسخةَ ثانية', () {
    /// ملفُّ القشرة ← الجسمُ الذي **يجب** أن يستورده بدل نسخِ المنطق.
    ///
    /// هذا هو شرطُ القرار كلِّه: القشرةُ تستورد الجسمَ من الملفّ المشترك.
    /// فلو نسخ أحدٌ المنطقَ إلى ملفّ القشرة لصار في المستودع نسختان تتخلّف
    /// إحداهما عن الأخرى — وهو عينُ ما جاء الاستخراجُ ليمنعه.
    const shells = {
      'printers_picpos_screen.dart': ('PrintersBody', 'screens/printers_screen.dart'),
      'pos_terminals_picpos_screen.dart':
          ('PosTerminalsBody', 'screens/pos_terminals_screen.dart'),
      'work_holidays_picpos_screen.dart':
          ('WorkHolidaysBody', 'screens/settings/work_holidays_screen.dart'),
      'delivery_management_picpos_screen.dart':
          ('DeliveryManagementBody', 'screens/delivery_management_screen.dart'),
      'developer_tools_picpos_screen.dart':
          ('DeveloperToolsPanels', 'screens/developer_tools_screen.dart'),
    };

    for (final e in shells.entries) {
      test('${e.key} قشرةٌ تستورد ${e.value.$1}', () {
        final f =
            File('lib/presentation/settings_picpos/screens/${e.key}');
        expect(f.existsSync(), isTrue,
            reason: 'ملفُّ القشرة ${e.key} غيرُ موجود');
        final src = f.readAsStringSync();

        expect(src.contains(e.value.$1), isTrue,
            reason: '${e.key} لا يبني `${e.value.$1}` — '
                'فإمّا نسخ المنطقَ وإمّا فقده.');
        expect(src.contains(e.value.$2), isTrue,
            reason: '${e.key} لا يستورد `${e.value.$2}` — '
                'الجسمُ لا بدّ أن يأتي من الملفّ المشترك لا من نسخةٍ محلّيّة.');

        // قشرةٌ ورقيقة: لو تضخّمت فالمرجّح أنّ منطقاً تسرّب إليها.
        expect(src.split('\n').length, lessThan(140),
            reason: '${e.key} تجاوز ١٤٠ سطراً — القشرةُ ترويسةٌ وبحثٌ وزرٌّ '
                'لا أكثر. راجعْ هل تسرّب منطقُ الجسم إليها.');
      });
    }

    test('أدواتُ المطوّر لا تُركَّب بلا بوّابةِ كلمةِ المرور', () {
      // أخطرُ ما في هذه الشاشة: تبديلُ نمطِ التشغيل وتصفيرُ البيانات. لوحاتٌ
      // بلا بوّابةٍ تفتحهما بلا تحقّق.
      final src = File(
        'lib/presentation/settings_picpos/screens/'
        'developer_tools_picpos_screen.dart',
      ).readAsStringSync();
      final gated = RegExp(
        r'DeveloperPasswordGate\s*\([\s\S]{0,200}?DeveloperToolsPanels',
      );
      expect(gated.hasMatch(src), isTrue,
          reason: 'قشرةُ أدوات المطوّر تركّب `DeveloperToolsPanels` بلا أن '
              'تلفّها `DeveloperPasswordGate` — فتبديلُ نمطِ التشغيل وتصفيرُ '
              'البيانات مفتوحان بلا كلمةِ مرور.');
    });

    test('زرُّ «سائق جديد» يحمل حارسَ الصلاحيّة كما كان الـFAB', () {
      final src = File(
        'lib/presentation/settings_picpos/screens/'
        'delivery_management_picpos_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'PermissionGuard\s*\([\s\S]{0,300}?deliveryCourierManage')
            .hasMatch(src),
        isTrue,
        reason: 'زرُّ «سائق جديد» في ترويسة PicPos بلا '
            '`PermissionGuard(deliveryCourierManage)` — والـ`FAB` الذي حلّ '
            'محلَّه كان محروساً به. نقلُ الزرِّ لا يُسقط حارسَه.',
      );
    });
  });

  group('لا زرَّ بلا وظيفة', () {
    test('«نقطة بيع جديدة» غيرُ موجودةٍ في قشرة نقاط البيع', () {
      // مقيسٌ 2026-08-24: صفُّ `pos_terminals` مفتاحُه `deviceId` يولّده
      // الجهازُ نفسُه عبر `registerIfNeeded`، فلا معنى لإنشائه يدويّاً من
      // جهازٍ آخر — والشاشةُ نفسُها تقول ذلك في حالتها الفارغة. حُذف الزرُّ
      // بقرار المالك، وهذا الحارسُ يمنع عودتَه من ملفّ التصميم.
      final src = _code(File(
        'lib/presentation/settings_picpos/screens/'
        'pos_terminals_picpos_screen.dart',
      ).readAsStringSync());
      expect(src.contains('نقطة بيع جديدة'), isFalse,
          reason: 'عاد زرُّ «نقطة بيع جديدة» إلى قشرة نقاط البيع. '
              'لا وظيفةَ له: التسجيلُ تلقائيٌّ بـ`deviceId` من الجهاز نفسِه. '
              'إمّا أن تُبنى وظيفةُ تسجيلٍ يدويٍّ حقيقيّةٌ أوّلاً، وإمّا يبقى '
              'الزرُّ محذوفاً — وزرٌّ لا يعمل أسوأُ من غيابه.');
    });

    test('ولا حقلَ بحثٍ في مصمّم الفواتير قبل أن يُبنى الترشيح', () {
      // `HEADS.designer` يعطي `hint: 'بحث في العناصر...'`، لكنّ العناصرَ
      // تعيش في `InvoiceSectionEditor` ولا يرشّحها شيء. حقلٌ لا يرشّح كزرٍّ
      // لا يعمل. احذفْ هذا الحارسَ يومَ يُبنى الترشيحُ في المحرّر.
      final src = _code(File(
        'lib/presentation/screens/invoice_designer/invoice_designer_ui.dart',
      ).readAsStringSync());
      final hasHeaderSearch =
          RegExp(r'headerSearch\s*:').hasMatch(src);
      final hasFilter = RegExp(r'searchQuery|_filterElements').hasMatch(src);
      expect(hasHeaderSearch && !hasFilter, isFalse,
          reason: 'أُضيف `headerSearch` إلى ترويسة مصمّم الفواتير بلا ترشيحٍ '
              'فعليٍّ للعناصر — حقلُ بحثٍ لا يبحث.');
    });
  });
}

// محتوى لوحات الإعدادات مقابلَ ملفّ التصميم — لا بنيتُها وحدَها.
//
// ═══ لماذا حارسٌ ثانٍ إلى جانب `settings_panels_test` ═══
//
// ذاك يقيس **الغلاف**: أنّ الحوارَ يُفتَح بهويّة PicPos وأنّ الرافعةَ تتفرّع.
// وبلّغ المالكُ 2026-08-25 عطباً من نوعٍ آخر: «العديد من الديالوجات والحوارات
// ليست كما المحتوى المطلوب في ملفّ التصميم» — أي أنّ الغلافَ صحيحٌ والنصَّ
// داخله ناقص. فمرَّ الحارسُ الأوّلُ أخضرَ والعطبُ قائم.
//
// ═══ ما يُقاس هنا ═══
//
// بنودُ محتوىً من `PANELS` في «PicPos Settings.dc.html» **مسنودةٌ بالنموذج**:
// لكلٍّ منها عمودٌ أو واجهةٌ في البرنامج، فغيابُها نقصٌ لا اختيار.
//
// ⚠️ **ولا يُدرَج هنا ما لا يفعله البرنامج.** «الهاتف» و«البريد» في لوحة
// المستخدم، و«الأولوية» في لوحة الدور، و«إلزام تغيير الـPIN كلّ ٣٠ يوماً»،
// و«إنهاء الجلسات» و«إبلاغ واتساب» — كلُّها بلا عمودٍ ولا واجهة. واشتراطُها
// هنا يدفع إلى رسم حقولٍ لا يقرأها الحفظ، وهو أسوأُ من غيابها. مواضعُها
// موثَّقةٌ في رؤوس الملفّات، وقرارُ بنائها للمالك.
//
// ⚠️ **والفحصُ على النصّ لا على الودجت** — فهذه لوحاتٌ تُبنى داخلَ حالاتٍ
// خاصّةٍ يحتاج فتحُها قاعدةً حيّة. والنصُّ يمسك الارتداد: من يحذف السطرَ
// يحمرُّ عنده الحارس.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/login_rate_limiter.dart';

/// ⚠️ **يرمي ولا يستعمل `expect`**: هذه الدالّةُ تُنادى في جسم `group` أي
/// **خارجَ** أيّ اختبار، و`expect` هناك ترمي `OutsideTestException` فيسقط
/// تحميلُ الملفّ كلِّه بدل أن يفشل فحصٌ واحدٌ برسالةٍ مفهومة.
String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    throw StateError('الملفُّ غيرُ موجود: $path');
  }
  return f.readAsStringSync();
}

bool _hasUiProperty(String source, String property, String value) {
  final pattern = RegExp(
    "${RegExp.escape(property)}\\s*:\\s*(?:tr\\(\\s*)?'"
    "${RegExp.escape(value)}"
    r"'(?:\s*\))?",
  );
  return pattern.hasMatch(source);
}

void main() {
  group('لوحةُ المستخدم — `PANELS.user`', () {
    final src =
        _read('lib/presentation/screens/settings/widgets/add_user_dialog.dart');

    test('«الحساب نشط» مرسومٌ ومربوطٌ بـ`toggleUserActive`', () {
      // `Users.isActive` عمودٌ قائمٌ و`toggleUserActive` واجهةٌ قائمة —
      // فالمفتاحُ مسنودٌ بالكامل، وغيابُه كان نقصاً لا قياساً.
      expect(_hasUiProperty(src, 'title', 'الحساب نشط'), isTrue,
          reason: 'سقط مفتاحُ «الحساب نشط» من لوحة المستخدم.');
      expect(src.contains('toggleUserActive'), isTrue,
          reason: 'المفتاحُ مرسومٌ ولا يصل إلى الحفظ — مفتاحٌ لا يفعل شيئاً.');
    });

    test('«تأكيد كلمة المرور» مرسومٌ ويمنع الحفظَ عند الاختلاف', () {
      expect(_hasUiProperty(src, 'labelText', 'تأكيد كلمة المرور *'), isTrue,
          reason: 'سقط حقلُ تأكيد كلمة المرور.');
      expect(src.contains('confirmController.text != password'), isTrue,
          reason: 'الحقلُ مرسومٌ بلا تحقّقٍ في `onSave` — زينةٌ لا حماية.');
    });

    test('«اسم الدخول» بنصِّ التصميم لا «اسم المستخدم»', () {
      expect(_hasUiProperty(src, 'labelText', 'اسم الدخول *'), isTrue);
    });
  });

  group('لوحةُ الدور — `PANELS.role`', () {
    final src =
        _read('lib/presentation/screens/settings/widgets/add_role_dialog.dart');

    test('«الوصف» مرسومٌ ويصل إلى `insertRole`', () {
      expect(_hasUiProperty(src, 'labelText', 'الوصف'), isTrue);
      expect(RegExp(r'insertRole\(\s*\n?\s*name:.*\n?\s*description:')
              .hasMatch(src),
          isTrue,
          reason: 'حقلُ الوصف لا يصل إلى الحفظ رغم أنّ `Roles.description` '
              'عمودٌ قائمٌ يقبله `insertRole`.');
    });

    test('«نسخ الصلاحيات من» مرسومٌ وينسخ فعلاً', () {
      expect(_hasUiProperty(src, 'label', 'نسخ الصلاحيات من'), isTrue);
      expect(src.contains('getPermissionsForRole'), isTrue);
      expect(src.contains('setRolePermissions'), isTrue);
    });

    test('⚠️ وفشلُ النسخ لا يُبتلَع صامتاً', () {
      // الدورُ أُنشئ قبل النسخ؛ فسكوتٌ عن فشل النسخ يُخرج المشغّلَ بدورٍ
      // فارغِ الصلاحيات وهو يظنّه نسخةً من المصدر.
      final i = src.indexOf('getPermissionsForRole');
      expect(i, greaterThan(-1));
      final tail = src.substring(i);
      expect(tail.contains('catch'), isTrue);
      expect(tail.contains('تعذّر نسخُ الصلاحيات'), isTrue,
          reason: 'فشلُ النسخ لا يُبلَّغ — والدورُ يبقى فارغاً بلا أن يدري '
              'المشغّل.');
    });

    test('«تنبيه» التصميم مرسوم', () {
      expect(_hasUiProperty(src, 'label', 'تنبيه'), isTrue);
      expect(src.contains('يسري فوراً على كلّ مستخدميه'), isTrue);
    });
  });

  group('لوحةُ الـPIN — `PANELS.pin`', () {
    final src =
        _read('lib/presentation/screens/settings/widgets/set_pin_dialog.dart');

    test('صفُّ سياسة القفل مرسومٌ **معطَّلاً** لا قابلاً للتبديل', () {
      // ⚠️ **يُبحَث عن الصيغة الكوديّة لا عن العبارة**: العبارةُ نفسُها ترد
      //    في التعليق الشارح فوقَ الصفّ، فـ`indexOf` كان يمسك التعليقَ
      //    ويقيس النافذةَ منه — وسقط الفحصُ على كودٍ سليم.
      // بعد i18n صار العنوانُ `tr('قفل الحساب بعد {p0} …')`.
      const titleLine = "title: tr('قفل الحساب بعد ";
      expect(src.contains(titleLine), isTrue,
          reason: 'سقط صفُّ سياسة القفل — والحمايةُ قائمةٌ ولا تظهر.');
      // والجوهرُ هنا: `onChanged: null`. مفتاحٌ يعمل يَعِد بتحكّمٍ لكلّ
      // مستخدمٍ لا وجودَ له — السياسةُ عامّةٌ في `LoginRateLimiter`.
      final i = src.indexOf(titleLine);
      expect(src.substring(i, i + 400).contains('onChanged: null'), isTrue,
          reason: 'صفُّ السياسة قابلٌ للتبديل — وهو يَعِد بما لا ينفّذه '
              '`LoginRateLimiter`.');
    });

    test('والعددان مقروءان من `LoginRateLimiter` لا مكتوبان', () {
      expect(src.contains('LoginRateLimiter.maxAttempts'), isTrue);
      expect(src.contains('LoginRateLimiter.lockoutDuration'), isTrue);
      // وفرضيّةُ نصِّ التصميم («٥ محاولات») مقيسةٌ لا مفترَضة.
      expect(LoginRateLimiter.maxAttempts, 5,
          reason: 'تغيّر عددُ المحاولات — راجعْ أنّ الصفَّ ما زال يطابق '
              'التصميم، فالنصُّ مشتقٌّ لا مكتوب.');
    });

    test('والسطرُ الخافتُ يقول المدى الذي يقبله الحفظ', () {
      // كان يقول «أربعةُ أرقام» بينما `onSave` يقبل من ٤ إلى ٦.
      expect(src.contains('من ٤ إلى ٦ أرقامٍ للدخول السريع'), isTrue);
    });
  });

  group('لوحةُ إعادة التعيين — `PANELS.resetpw`', () {
    final src = _read(
        'lib/presentation/screens/settings/widgets/reset_password_dialog.dart');

    test('«تنبيه» الفصلِ بين كلمة المرور والـPIN مرسوم', () {
      expect(_hasUiProperty(src, 'label', 'تنبيه'), isTrue);
      expect(src.contains('غيرُ الـPIN المستخدَم على'), isTrue);
    });
  });
}

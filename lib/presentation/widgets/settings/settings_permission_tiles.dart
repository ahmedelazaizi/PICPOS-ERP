// تايلات الإعدادات المحروسة بصلاحيات — دفعة ١٠.
//
// ── ليه ملف مشترك ─────────────────────────────────────────────────────────
// الستة أكواد دي (`settings_company`، `settings_currency`،
// `settings_pos_edit`، `settings_tax`، `system_database`، `system_license`)
// كل واحد فيهم ليه **موقعين متطابقين**: `screens/settings_screen.dart`
// (UralCash) و`settings_picpos/screens/settings_picpos_screen.dart`. محتوى
// التايل نفسه واحد بالحرف في الاتنين، فالحارس اتلمّ هنا مرة واحدة بدل ما
// يتكرر — مصدر واحد يمنع انحراف فورك عن التاني، وبيسهّل النقل بـpatch.
//
// مفيش `Brand.isPicPos` هنا ولا أي فرق سلوك بين البراندين: الفعل نفسه
// (`onOpen`) بيتمرَّر من الشاشة المستدعية.
//
// ── ليه دوال top-level ────────────────────────────────────────────────────
// عشان الاختبار يبنيها لوحدها. تركيب شاشة الإعدادات كاملة بيجرّ عشرات
// الـproviders وقاعدة بيانات حقيقية (درس دفعة ٦أ: ١٩ اختبار / ١٣ فشل /
// ساعتين).
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../permission_guard.dart';

/// «عطلات العمل» — `hr_manage`.
///
/// مدخلُ إعداداتٍ لا شاشةُ تشغيل: عليه يقوم مقامُ `workingDaysInMonth` الذي
/// يُشتقّ منه أجرُ الساعة والإضافيُّ المحسوب. الحارسُ `hrManage` لا
/// `settingsBackup` — إعدادُ موظفين لا إعدادُ محاسبة.
///
/// ── ليه هنا مش جوّه الشاشتين ──────────────────────────────────────────────
/// اتكتب أول مرة **مكرَّراً بالحرف** في `settings_screen.dart` و
/// `settings_picpos_screen.dart`, وده بالظبط اللي رأس الملف ده بيحذّر منه.
///
/// وأخطر من التكرار: كان الحارس ملفوف حوالين **الكارت** كله
/// (`Card` جوّاه `Column`), و`extractChildAction` مابتعرفش تطلّع فعل من
/// `Card` ولا بتنزل جوّه `Column` متعدد الأبناء ⇒ بترجّع `null`. يعني مستخدم
/// من غير `hr_manage` كان يضغط، المدير يكتب كلمة السر، الديالوج يقفل، وما
/// يحصلش حاجة — نفس الباج الموثَّق في `permission_guard.dart:291`. الحراسة
/// على `ListTile` مع `onGranted` صريح بتقفل الاتنين.
Widget buildWorkHolidaysTileGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.hrManage,
    allowManagerOverride: true,
    actionName: 'عطلات العمل',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(PhosphorIconsBold.calendarCheck,
          color: AppColors.primary),
      title: const Text('عطلات العمل'),
      subtitle: const Text(
          'العطل الأسبوعية والأعياد — أساسُ حساب أيام العمل وأجر الساعة والإضافي'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// «معلومات الشركة» — `settings_company`.
///
/// كان التايل الوحيد المكشوف وسط تايلات مبوّبة (الطابعات/المستخدمين/الأدوار)
/// في نفس الشاشة. `onGranted` صريح رغم إن الحارس بيعرف يسحب `onTap` من
/// `ListTile` — التصريح ما بيعتمدش على التخمين (درس f8d3fa9).
Widget buildCompanyInfoTileGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.settingsCompany,
    allowManagerOverride: true,
    actionName: 'معلومات الشركة',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(PhosphorIconsBold.buildings),
      title: const Text('معلومات الشركة'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// «عملة النظام» — `settings_currency`.
///
/// معالج التنصيب (`setup_wizard_screen.dart`) بيكتب العملة برضه، ومقصود إنه
/// يفضل مكشوف: فعل تركيب أول مرة قبل ما يبقى فيه مستخدمين وأدوار أصلاً.
/// و[locked] يعني أنّ حركةً ماليّةً وقعت، فالعملةُ لم تعد قابلةً للتبديل
/// (‏م-٢، قرارُ المالك 2026-08-23): دقّتُها العشريّةُ جزءٌ من كلّ مبلغٍ
/// محفوظٍ وكلّ قيدٍ مرحَّل. والمنعُ يُشرَح هنا، ويُنفَّذ في
/// `SystemCurrencyNotifier.setCurrency` — الواجهةُ وحدَها تُلتَفّ.
Widget buildCurrencyTileGuarded({
  required String subtitle,
  required VoidCallback onOpen,
  bool locked = false,
}) {
  if (locked) {
    return ListTile(
      enabled: false,
      leading: const Icon(
        PhosphorIconsBold.lockSimple,
        color: AppColors.textMuted,
      ),
      title: const Text('عملة النظام'),
      subtitle: Text(
        '$subtitle — مقفولة بعد تسجيل حركات مالية.\n'
        'الدقة العشرية للعملة جزءٌ من كل مبلغ محفوظ، فتبديلها الآن يعيد '
        'تقريب المبالغ القائمة وقد يُخلّ قيوداً متّزنة.',
        style: const TextStyle(fontSize: 11.5),
      ),
      isThreeLine: true,
      trailing: const Icon(PhosphorIconsBold.lockSimple, size: 16),
    );
  }

  return PermissionGuard(
    permission: PermissionCodes.settingsCurrency,
    allowManagerOverride: true,
    actionName: 'تغيير عملة النظام',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(
        PhosphorIconsBold.currencyCircleDollar,
        color: AppColors.success,
      ),
      title: const Text('عملة النظام'),
      subtitle: Text(subtitle),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// «قاعدة البيانات» — `system_database`.
///
/// الديالوج بيبدّل محرك قاعدة البيانات وبيحفظ بيانات اتصال PostgreSQL (كلمة
/// سر بنص صريح). كان مفتوح لأي حد يقدر يفتح الإعدادات.
Widget buildDatabaseSettingsTileGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.systemDatabase,
    allowManagerOverride: true,
    actionName: 'إعدادات قاعدة البيانات',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(
        PhosphorIconsBold.database,
        color: AppColors.warning,
      ),
      title: const Text('قاعدة البيانات'),
      subtitle: const Text('اختيار نوع قاعدة البيانات (SQLite/PostgreSQL)'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// «إعدادات البيع السريع الرئيسية» — `settings_pos_edit`.
///
/// بوابة الدخول للديالوج كله (أزرار/شبكة/سلة/إيصال/تنبيه مخزون/بيع بالسالب/
/// مخزن افتراضي). تبويب المدخل أبسط وأشمل من تبويب كل مفتاح جوه.
Widget buildPosSettingsTileGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.settingsPosEdit,
    allowManagerOverride: true,
    actionName: 'إعدادات البيع السريع',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(
        PhosphorIconsBold.shoppingCart,
        color: AppColors.primary,
      ),
      title: const Text('إعدادات البيع السريع الرئيسية'),
      subtitle: const Text('الأزرار، التصنيفات، شبكة المنتجات، السلة، الإيصال'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// بلاطةُ «سياسة البيع السريع» — §٤.
///
/// ⚠️ **نفسُ صلاحيةِ [buildPosSettingsTileGuarded] عمداً** (`settingsPosEdit`):
/// الشاشتان تضبطان نفسَ نقطةِ البيع، إحداهما **ما يُعرَض** والأخرى **ما
/// يحدث**. وصلاحيةٌ ثالثةٌ لواحدةٍ منهما كانت ستعني أنّ من يملك تغييرَ حدودِ
/// الخصم قد لا يملك تغييرَ مقاسِ الأيقونة — تفرقةٌ بلا معنىً تشغيليّ.
Widget buildQuickSalePolicyTileGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.settingsPosEdit,
    allowManagerOverride: true,
    actionName: 'سياسة البيع السريع',
    onGranted: onOpen,
    child: ListTile(
      leading: const Icon(
        PhosphorIconsBold.slidersHorizontal,
        color: AppColors.primary,
      ),
      title: const Text('سياسة البيع السريع'),
      subtitle: const Text(
          'المسح، السلة، الدفع، الطباعة، الوردية — ما يحدث لا ما يُعرَض'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: onOpen,
    ),
  );
}

/// زرار «تفعيل الآن» — `system_license`.
///
/// زرار التفعيل التاني في `core/trial/trial_guard.dart` (شاشة انتهاء
/// التجربة) مقصود إنه يفضل مكشوف: ده المخرج الوحيد لما التجربة تخلص،
/// وتبويبه ممكن يقفل البرنامج على المستخدم نهائياً.
Widget buildLicenseActivateButtonGuarded({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.systemLicense,
    allowManagerOverride: true,
    actionName: 'تفعيل الترخيص',
    onGranted: onOpen,
    child: ElevatedButton(
      onPressed: onOpen,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(100, 36),
      ),
      child: const Text('تفعيل الآن'),
    ),
  );
}

/// حقل «نسبة الضريبة الافتراضية» — `settings_tax`.
///
/// كود مستقل جوه ديالوج مبوّب بـ`settings_pos_edit`؛ الاتنين مطلوبين: دخول
/// الديالوج شيء، وتغيير نسبة ضريبة بتتطبّق على كل فاتورة جاية شيء تاني.
///
/// **من غير `onGranted` عن قصد**: الحقل نص حر مالوش «فعل واحد» يتشغّل بعد
/// الموافقة — الحارس بيفكّ القفل والمدير يكتب النسبة بنفسه (نفس قرار
/// `pos_note_add` في دفعة ٧). والإخفاء مكانش صح: القيمة بتتحمّل من الإعدادات
/// وبتترحّل مع الحفظ، فالإخفاء كان هيمنع أي تعديل نهائياً بدل ما يطلب موافقة.
Widget buildDefaultTaxRateTileGuarded({required Widget field}) {
  return PermissionGuard(
    permission: PermissionCodes.settingsTax,
    allowManagerOverride: true,
    actionName: 'تغيير نسبة الضريبة الافتراضية',
    child: ListTile(
      title: const Text('نسبة الضريبة الافتراضية'),
      subtitle:
          const Text('النسبة المئوية للضريبة التي يتم تطبيقها تلقائياً'),
      contentPadding: EdgeInsets.zero,
      trailing: SizedBox(width: 100, child: field),
    ),
  );
}

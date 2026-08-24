// سجلُّ الأقسام المحميّة بكلمةِ مرورٍ بديلة — مصدرٌ واحدٌ للحقيقة.
//
// ═══ لماذا سجلٌّ لا قائمةٌ في الشاشة ═══
//
// لأنّ الشاشةَ تعرض **وعداً**: مفتاحٌ مفتوحٌ يعني «هذا القسمُ يُقفَل». وهذا
// الوعدُ لا تفي به الشاشةُ بل `SecurityScreenGate` المربوطةُ في
// `app_main_screen.dart`. فحين يعيش الطرفان في ملفَّين بلا رابط، يسهل أن
// يُعرَض مفتاحٌ لقسمٍ بلا بوّابة — ويطمئنَّ المستخدمُ إلى قفلٍ لا وجود له.
//
// فهذا السجلُّ هو الرابط، ويقيسه
// `test/structural/guarded_sections_have_real_gates_test.dart`: كلُّ
// `settingKey` هنا يجب أن يقابل `settingKey:` في الشجرة.
//
// ═══ ⚠️ وما لم يُدرَج عمداً ═══
//
// تصميمُ الإعدادات 2026-08-24 يعرض خمسةَ أقسام، **ثلاثةٌ منها لا بوّابةَ
// لها في التطبيق**: «شاشة المطبخ» و«المرتجعات» و«الخصم اليدوي». فأُسقطت من
// السجلّ حتى تُربَط بوّاباتُها — قفلٌ وهميٌّ أسوأُ من لا قفل، لأنّ صاحبَه
// يبني عليه.
//
// ═══ والكلمةُ نصٌّ لا PIN ═══
//
// التصميمُ يسمّيها «PIN منفصل لكل قسم»، والمقصودُ **الانفصالُ** لا الرقميّة.
// وقد بقيت نصّاً: أربعةُ أرقامٍ أضعفُ من كلمةٍ حرّة، والتحويلُ إليها تخفيفُ
// حمايةٍ بلا مقابل.
library;

import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// قسمٌ يُقفَل بكلمةِ مرورٍ بديلةٍ مستقلّةٍ عن صلاحيات المستخدم.
class PicPosGuardedSection {
  const PicPosGuardedSection({
    required this.settingKey,
    required this.title,
    required this.sub,
    required this.icon,
  });

  /// مفتاحُ الإعداد. **كلمةٌ فارغةٌ أو غائبةٌ ⇒ القسمُ مفتوح** — وهو ما
  /// يجعل «مفتاحَ التشغيل» في الواجهة انعكاساً لحالةٍ قائمةٍ لا حقلاً
  /// جديداً في القاعدة.
  final String settingKey;

  final String title;
  final String sub;
  final IconData icon;
}

/// الأقسامُ التي **لها بوّابةٌ فعليّةٌ** في الشجرة اليوم.
const kPicPosGuardedSections = <PicPosGuardedSection>[
  PicPosGuardedSection(
    settingKey: 'inventory_access_password',
    title: 'المخازن والمخزون',
    sub: 'الأرصدة وحركات المخزون',
    icon: PhosphorIconsBold.archive,
  ),
  PicPosGuardedSection(
    settingKey: 'accounting_access_password',
    title: 'الحسابات والمالية',
    sub: 'الخزينة والقيود والتقارير المالية',
    icon: PhosphorIconsBold.bank,
  ),
  PicPosGuardedSection(
    settingKey: 'purchases_access_password',
    title: 'المشتريات',
    sub: 'فواتير الموردين والتكاليف',
    icon: PhosphorIconsBold.shoppingBagOpen,
  ),
  PicPosGuardedSection(
    settingKey: 'reports_access_password',
    title: 'التقارير',
    sub: 'الأرباح وحركة المبيعات',
    icon: PhosphorIconsBold.chartPieSlice,
  ),
  PicPosGuardedSection(
    settingKey: 'hr_access_password',
    title: 'شؤون الموظفين',
    sub: 'الرواتب والحضور',
    icon: PhosphorIconsBold.users,
  ),
];

/// عددُ الشاشات التي يحميها مفتاحٌ واحد.
///
/// ⚠️ **يُقاس ولا يُكتَب بيد**: `accounting_access_password` يحمي ستَّ شاشاتٍ
/// اليومَ (الخزينة · مركزُ الحسابات · القيود · …)، ورقمٌ مكتوبٌ يبطُل عند
/// ربطِ الشاشة السابعة. والعدُّ من نفس الخريطة التي يبنيها الحارس.
int countGuardedScreens(Map<String, int> gateCounts, String settingKey) =>
    gateCounts[settingKey] ?? 0;

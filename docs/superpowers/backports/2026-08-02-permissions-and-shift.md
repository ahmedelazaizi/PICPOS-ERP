# نقل إنفاذ الصلاحيات + وردية لكل كاشير إلى UralCash

**المصدر:** `D:\PICPOS-ERP` · فرع `feat/lite-profile-and-pos-ui`
**المدى:** `546e3924~1..HEAD` — ٣٦ كوميت (إنفاذ الصلاحيات ١-١٢ + إصلاح محرك
الحارس + خطة الوردية ١-٣ + وثائق)
**الحالة عند التوليد:** `flutter analyze lib test` صفر أخطاء · `flutter test`
**٣٦٠٧ ناجح / ١٢ متخطّى / صفر فاشل**

> **ممنوع لمس `D:\URAL-ERP` من هنا.** الملف ده بيوصف patches بس؛ التطبيق
> بيتم هناك بإيد صاحب المشروع.

---

## ١. متطلّب سابق — لازم يتأكد قبل أي حاجة

السلسلة كلها مبنية على `f8d3fa99` («تجاوز المدير كان بينجح ومايشغّلش الفعل»)
اللي **ضاف `onGranted` لـ`PermissionGuard`**. هو **مش** في المدى ده (بيبدأ
بعده)، ومعظم كوميتات الإنفاذ بتمرّر `onGranted:`، وإصلاح المحرك `d01fdfdc`
بيعدّل نفس الودجت.

للتأكد في UralCash:

```bash
grep -n "onGranted" lib/presentation/widgets/permission_guard.dart
```

مفيش نتيجة ⇒ طبّق `f8d3fa99` الأول، وإلا كل الـpatches هتفشل.

---

## ٢. توليد الـpatches (بترشيح ملفات PicPos تلقائياً)

```bash
git format-patch 546e3924~1..HEAD --output-directory /tmp/bp-2026-08-02 -- ':!*_picpos*' ':!*picpos_*'
```

الـpathspec ده **بيشيل هَنكات ملفات PicPos من جوّه كل كوميت** بدل ما تفشل
وقت التطبيق. ولا كوميت بيطلع فاضي بعد الترشيح — يعني كل كوميت فيه شغل مشترك
حقيقي.

التطبيق هناك:

```bash
git am --3way /tmp/bp-2026-08-02/*.patch
```

---

## ٣. الملفات اللي اتشالت من النقل ولماذا

كلها فوركات PicPos. **النصف التاني من كل زوج (نسخة UralCash) جوّه الـpatch**،
فالإصلاح بيوصل كامل — الفورك المتشال هو نسخة PicPos من نفس الشاشة.

| الكوميت | الملفات المتشالة | النصف المقابل في الـpatch |
|---|---|---|
| `4a4816ca` | `shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart` | `pos/widgets/pos_cashier_closing_dialog.dart` |
| `68bb0fd7` · `560a436b` | `settings_picpos/screens/settings_picpos_screen.dart` · `general_settings_widgets_picpos.dart` | `screens/settings_screen.dart` · `screens/settings/general_settings_widgets.dart` |
| `dda93b6b` · `df703f27` · `f017270b` | `pos_picpos/screens/picpos_pos_operations.dart` | `pos/screens/pos_main_operations.dart` |
| `78951dc9` | ٧ ملفات: `sales_invoices_picpos/*` (٣) · `sales_returns_picpos/*` (٢) · `purchases_picpos/*` · `purchase_returns_picpos/*` | `screens/widgets/sales_invoices/*` · `screens/sales_returns/return_logic.dart` · `screens/purchase_invoices_screen.dart` · `screens/purchase_returns/return_logic.dart` |
| `3c454234` | `dashboard_picpos/screens/dashboard_picpos_screen.dart` | `screens/dashboard_screen.dart` |
| `d86dbcc9` | `reports_picpos/screens/reports_picpos_screen.dart` | `screens/reports_screen.dart` (وشاشات التقارير نفسها مشتركة أصلاً) |
| `f017270b` · `6f4ac9b5` | `pos_picpos/widgets/picpos_switch_user_dialog.dart` | **مالوش مقابل** — شوف ٤.٢ |

---

## ٤. إجراءات لازمة **بعد** التطبيق

### ٤.١ `dashboard_chart` هيبقى بلا إنفاذ في UralCash ⚠️

الكود ده اتشال من `PermissionEnforcementRegistry.knownUnenforced` (ملف مشترك،
جوّه الـpatch) لأن PicPos بوّبه على **قوس هامش الربح ودونات تركيبة الإيراد**
— والرسمين دول موجودين في فورك PicPos بس؛ **لوحة UralCash مالهاش رسوم أصلاً**.

النتيجة بعد النقل: `permission_enforcement_coverage_test` هيفشل عند UralCash
بـ«كود بلا إنفاذ ومش مسجّل».

**الحل المقترح** (الأدق للمنتج): انقله لـ`PermissionCodes.nonToggleable`
بسبب صريح بدل ما ترجّعه للسجل:

```dart
'dashboard_chart': 'مفيش رسوم بيانية في لوحة UralCash — السطح نفسه مش موجود',
```

وساعتها عدّاد `nonToggleable` عندهم بيبقى ٣٥ بدل ٣٤.

فحص مشابه اتعمل على كل الأكواد: **ده الوحيد** اللي إنفاذه حصري في PicPos من
شغل الدفعات دي. (`pos_edit_invoice` برضه بلا إنفاذ مشترك، بس ده وضع قديم
موروث مش من الشغل ده.)

### ٤.٢ مسار «تحويل المستخدم» مالوش مقابل في UralCash

`picpos_switch_user_dialog.dart` ميزة خاصة بـPicPos. الشغل في `6f4ac9b5`
بيضيف نداء `enforceShiftForUser(...)` **بعد** `switchUser()` — والدالة نفسها
(في `app_main_screen.dart`، ملف مشترك) **جوّه الـpatch**.

يعني UralCash بياخد الدالة العليا وبياخد نداء `initState` عادي. **لو ضاف
مسار تبديل مستخدم بعدين، لازم ينادي `enforceShiftForUser` بعد `switchUser`
مباشرةً** — من غير النداء ده الكاشير الجاي بيبيع بلا وردية مفتوحة وفواتيره
ما تتنسبش لأي وردية. الاختبار `test/widget/switch_user_shift_test.dart`
(جوّه الـpatch) بيغطّي الدالة نفسها.

### ٤.٣ عدّادات ممكن تختلف مشروعاً

`test/unit/permission_nontoggleable_registry_test.dart` فيه تأكيدَين رقميَّين:

- `knownUnenforced` **فاضي**
- `nonToggleable.length == 34`

كتالوج UralCash فيه كود زيادة (`pos_edit_invoice`) وبعد ٤.١ هيبقى فيه
`dashboard_chart` كمان في `nonToggleable`. **دول أول مكان يظهر فيه اختلاف
مشروع** — يتعدّلوا بالأرقام الصح عندهم، مش يتشالوا.

### ٤.٤ وثائق مش لازم تتنقل

- `RELEASE_NOTES_2026-08-02.md` — ملاحظات إصدار PicPos. المحتوى ينفع أساس
  لملاحظات UralCash، بس التطبيق الحرفي مش مطلوب.
- `docs/superpowers/plans/*` و`docs/superpowers/handoff/*` — وثائق تنفيذ.
- `.superpowers/sdd/**` — **مش في الـpatch أصلاً** (مسار متجاهَل في git).

---

## ٥. التحقق بعد التطبيق

```bash
flutter analyze lib test
flutter test --concurrency=1
```

نقاط انتباه:

1. **الاختبارات اللي بتثبّت السلوك القديم للوردية** هتفشل لو UralCash عنده
   نسخة من `open_shift_gate_test.dart` بالسلوك القديم — الـpatch بيستبدلها،
   بس لو عندهم اختبارات تانية بتتوقّع منع الخروج على وردية مفتوحة، دي **مش
   انحدار**: البوابة اتلغت بقرار صريح من صاحب المنتج.
2. **`flutter test` على ويندوز بينهار لو اتشغّل مرتين متوازيين**
   (`PathExistsException ... sqlite3.dll`). الحل: `rm -rf build/native_assets`
   وأعد. مش فشل اختبارات.
3. الأدوار: `grantMissingDefaults()` بيشتغل تلقائياً أول إقلاع في وضع الخادم
   ويطبّق المنح الجديدة. أجهزة العملاء بتسحبها من الخادم.

---

## ٦. تنبيه سلوكي للمشغّل (مش تقني)

إصلاح المحرك `d01fdfdc` بيخلّي `treasury_balance_view` و`dashboard_profit`
**يخبّوا فعلاً** بعد ما كانوا بيتعرضوا للكل. مفيش دور تشغيلي واخد الكودين
دول، فبعد الترقية كل الأدوار هتشوف `---` مكان رصيد الخزنة وصافي الربح (مع
إمكانية الكشف بموافقة مدير). ده **السلوك المقصود** من الكودين — التفاصيل
الكاملة في `RELEASE_NOTES_2026-08-02.md` قسم ١.

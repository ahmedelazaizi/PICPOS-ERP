# إعادة تصميم باقي شاشات lite بهوية PicPos — مستند التصميم

> **الحالة:** معتمد للتخطيط · **التاريخ:** ٢٠٢٦-٠٧-٢٨ · **الفرع:** `feat/lite-profile-and-pos-ui`
> **المرجع:** `HANDOFF.md` (§٤ قائمة lite، §٥.٨ نمط العيّنة، §٥.٩ آخر جلسة) +
> `docs/superpowers/specs/2026-07-27-picpos-screens-redesign-design.md` (سبيك العيّنة).
> **يكمّل:** البند ٢ في برومت بدء الجلسة (باقي شاشات lite).

---

## ١. الهدف

عيّنة الـ٣ شاشات (الأصناف/المخزون/المشتريات) خلصت واتحقّق منها (§٥.٨). المطلوب هنا:
تعميم **نفس النمط** على **باقي شاشات lite** — شاشات PicPos منفصلة يختارها `Brand.isPicPos`،
مبنية فوق طقم `picpos_shell` الموجود، **تعيد استخدام نفس الـ controllers والخدمات والجداول
والحوارات** — الجديد **التخطيط والهوية فقط، دون المساس بأي منطق**، ودون لمس UralCash.

بالإضافة لقرارين من مراجعة صاحب المشروع (٢٧–٢٨ يوليو):
1. **الداشبورد** يُعاد بناؤه بـ**منطق UralCash كامل** (فلتر + KPI بصلاحيات + صناديق متعددة +
   تنبيه مخزون + إجراءات سريعة) **مع** طبقة مؤشرات دائرية حية مربوطة بنفس الـ providers.
2. **شاشة ميزان PLU** — مستبعدة حالياً من lite — تُضاف لـ PicPos **فقط** كفورك منفصل كامل،
   دون التدخل مع UralCash.

## ٢. القواعد المطلقة (من HANDOFF)

1. **ممنوع لمس أي ملف في `D:\URAL-ERP`**، ولا إضافة git remote أو الرفع.
2. **ممنوع تغيير الملاح التشفيرية الأربعة** (§٣.٢).
3. **كل قيمة في `Brand` و`AppColors` تفضل `const`** (§٣.١) — لا getters للألوان.
4. **ممنوع إضافة قيمة `AppFlavor` جديدة** (§٣.٥).
5. **أي إصلاح باج منطقي في ملف محرك/خدمة مشتركة** = كوميت منفصل + patch لـ UralCash (§٥.٦).
   تغييرات التخطيط/الهوية **لا تنتقل**. الكود المنسوخ في fork ليس مشتركاً؛ لكن أي إصلاح منطقي
   فيه يتصلّح في مصدر UralCash أولاً ثم ينتقل patch (مصيدة النسخ — [[engine-fixes-backport-to-uralcash]]).

## ٣. القرار المعماري (مثبَّت من §٥.٨)

**شاشات PicPos منفصلة يختارها `Brand.isPicPos`** — نفس سابقة الـ POS والعيّنة، وليس مكوّنات
مشتركة تتفرّع داخل ملفات UralCash. الشاشة المنفصلة **تستورد وتنادي** نفس الـ controllers
والخدمات والجداول، فـ«المنطق واحد» حرفياً. `Brand.isPicPos` ثابت وقت الترجمة، فبناء UralCash
يأخذ فرع `else` حرف بحرف والـ tree-shaker يسقط فرع PicPos.

**التعديل الوحيد على ملفات مشتركة** = أسطر اختيار بالعلامة (`Brand.isPicPos ? PicPos : Ural`)
في `app_main_screen.dart`، وفرع `Brand.isPicPos` واحد في `screen_registry.dart` (للميزان — §٧).
فرع `else` = سلوك UralCash الحالي حرف بحرف.

### طقم `picpos_shell/` (موجود، PicPos-only)
`picpos_screen_scaffold.dart` · `picpos_page_header.dart` (هيدر فاتح + خط لوني سفلي 2.5px) ·
`picpos_content_card.dart` (كارت مسطّح بحد شعري) · `picpos_toolbar.dart`. كل شاشة جديدة تُبنى فوقه.

## ٤. النطاق — ١٦ شاشة في ٨ باتشات

قائمة lite = ١٩ شاشة (§٤) + ميزان PLU (يُضاف لـ PicPos) = **٢٠**. المنفَّذ ٤ (pos §٥.٥ +
products/inventory/purchases §٥.٨). **المتبقّي = ١٦ شاشة**، مرتّبة **بالقرابة للفورك المنفَّذ**،
**بمراجعة لكل باتش**:

| # | الباتش | الشاشات | القريب المنفَّذ | ملاحظة |
|---|---|---|---|---|
| أ | فواتير/مرتجعات | `salesInvoices` · `salesReturns` · `purchaseReturns` | المشتريات | فورك قائمة+نموذج |
| ب | تصنيفات | `categories` | الأصناف | أرخص |
| ج | عائلة المخزون | `inventoryBonds` · `stockTransfer` · `fieldAudit` | المخزون | فورك |
| د | ميزان PLU | `scalePlu` (فورك منفصل + ضمّه لـ lite بفرع العلامة) | — | §٧ |
| هـ | صناديق | `treasury` · `shiftClose` | — | فورك |
| و | تقارير | `reports` · `activityLog` | — | فورك |
| ز | تشغيل | `parties` · `users` | جدول عادي | أرخص |
| ح | خاصة الطابع | `dashboard` · `settings` | — | تخطيط مخصّص (§٦) |

## ٥. وصفة الفورك (باتشات أ، ب، ج، هـ، و، ز)

لكل شاشة: مجلد `lib/presentation/<screen>_picpos/`، شاشة PicPos تبني `PicPosScreenScaffold`
+ `PicPosPageHeader` (عنوان/وصف/بحث/أزرار) + `PicPosContentCard` حاوي الجدول/القائمة الأصلية.
الأزرار **توصيل** لنفس الـ controllers/services/dialogs — مش نسخ منطق. الاختيار في
`app_main_screen.dart` بـ `Brand.isPicPos ? XPicpos : X`.

**تكلفة النسخ:** لو fork فيه منطق تنظيم واجهة `part of` خاص (زي inventory/purchases في §٥.٨)،
يُنسخ حرفياً في الـ fork، **مع** ملاحظة مصيدة النسخ: أي إصلاح منطقي لاحق يتصلّح في مصدر
UralCash أولاً ثم ينتقل patch.

## ٦. الشاشتان الخاصتان (باتش ح) — تخطيط مخصّص

### ٦.١ الداشبورد — `DashboardPicposScreen`

**يعيد استخدام منطق `dashboard_screen.dart` كاملاً** (لا منطق جديد)، بتخطيط PicPos:

**عناصر UralCash المنقولة كما هي (ربط لا نسخ منطق):**
- **فلتر** (`_DashboardFilterBar` → `dashboardFilterProvider`): الفرع + مركز التكلفة + الفترة،
  ومؤشر الفترة أسفله.
- **٤ كروت KPI** من نفس المزوّدات:
  - **صافي الإيراد** = `kpi.revenue` (بدون ضريبة، بعد المردودات — دفتر الأستاذ)، مع نفس
    tooltip المعادلة (`revenue` + `outputVatNet` = `netRevenueInclVat`، والمردودات).
  - **عدد الفواتير** = `kpi.invoiceCount`.
  - **أرصدة الصناديق** = `dashboardCashBalanceProvider` (**يجمع صناديق الفرع المتعددة**، مفلتر
    بالفرع — وليس `totalCashBalanceProvider`)، والعنوان يتبدّل «كل الصناديق»/«صناديق الفرع» حسب
    `dashFilter.branchId`، محوَّط بـ `PermissionGuard(treasuryBalanceView)`.
  - **صافي الربح** = `kpi.netProfit`، محوَّط بـ `PermissionGuard(dashboardProfit)`.
- **تنبيه المخزون المنخفض** (`lowStockProductsProvider`) — بانر شرطي + تنقّل للمخزون.
- **شبكة إجراءات سريعة** (`_QuickActionCard` مُعاد استخدامه) — الإجراءات المتاحة في lite فقط.
- **Getting Started Checklist** كما هي.
- **يُحذف** قسم «آخر المبيعات» (قرار صاحب المشروع).

**طبقة PicPos المضافة — مؤشرات دائرية حية (عرض فقط، فوق نفس الداتا):**
مكوّنات PicPos-only (CustomPainter قوس + AnimationController للحركة + تفاعل hover)، تقرأ قيم
الـ providers بـ `ref.watch` فتتحدّث لحظياً. **تُرسم من أرقام موجودة، صفر منطق أعمال جديد.**

| المؤشر | المصدر | الحالة |
|---|---|---|
| **هامش الربح** = `netProfit ÷ revenue` | `dashboardKpiProvider` (الاتنين موجودان) | ✅ حقيقي مضمون اليوم |
| **نسبة التحصيل** = محصّل ÷ إجمالي | يُتحقّق من مزوّد فترة موجود؛ إن لم يوجد → تجميع صفوف مجلوبة أصلاً، أو إضافة مزوّد صغيرة **patch** | ⚠️ يُربط أو يُؤجَّل |
| **توزيع المدفوعات** نقدي/آجل/بطاقة | يُتحقّق من تفصيل طرق الدفع؛ إن لم يوجد → **patch** محرك صغير، أو يُقصَر على نقدي/آجل القابلة للاشتقاق | ⚠️ يُربط أو يُقلَّص |
| **تحقيق الهدف** = مبيعات ÷ هدف | يحتاج مصدر هدف؛ إن لم يوجد إعداد هدف → يُستبدل بمقياس حقيقي (مثل متوسط قيمة الفاتورة) | ⚠️ يُؤكَّد المصدر |

**التزام صريح:** لا يُعرض أي رقم بلا مصدر حقيقي. أي مقياس يحتاج حساباً غير موجود في الـ
providers يُنفَّذ كإضافة محرك منفصلة بـ patch (تنتقل لـ UralCash)، **لا يُخترع في الواجهة**.

### ٦.٢ الإعدادات — `SettingsPicposScreen`
`PicPosScreenScaffold` + هيدر موحّد + تقسيم الأقسام في `PicPosContentCard`ات، بنفس عناصر
التحكم والمنطق والمفاتيح. تأطير فقط.

## ٧. ميزان PLU — فورك منفصل كامل (باتش د)

**القرار (صاحب المشروع):** استنساخ الشاشة بكل ما تحتاجه من UralCash **كفورك PicPos منفصل**،
يبقى جزءاً كاملاً من PicPos، **دون التدخل مع UralCash إطلاقاً**.

- **الفورك:** `lib/presentation/scale_plu_picpos/` ينسخ ما يلزم من `scale_plu/scale_panels.dart`
  و`scale_logic.dart` (إن كانت `part of`، تُنسخ كما في فوركات §٥.٨)، ويعيد استخدام الخدمات
  المشتركة كما هي: `label_scale_service.dart`، `plu_manager/*` mixins، بروتوكولات الميزان.
  الشكل من طقم `picpos_shell`.
- **الاختيار:** `Brand.isPicPos ? ScalePluPicposScreen : ScalePluScreen` في `app_main_screen.dart`.
- **الضمّ لـ lite دون لمس UralCash:** في `screen_registry.dart`، تُضاف `ScreenId.scalePlu` لقائمة
  lite **بفرع `Brand.isPicPos` وقت الترجمة فقط** — فـ lite بتاعة PicPos تعرضها، وlite بتاعة
  UralCash تفضل حرف بحرف (٢٠ مقابل ١٩). (تغيير config مشترك بفرع علامة — نفس نمط §٣.)
- **مصيدة باج ٩:** الميزان يمسّ بادئة الباركود/الوزن (`weightByPiece` + بادئة السعر مقابل الوزن).
  عند النسخ يُراجَع الإصلاح موجوداً، وأي إصلاح منطقي في المنسوخ ينتقل patch.
- **UralCash's `scale_plu/` لا يُلمس.**

## ٨. الاختيار (wiring)

في `app_main_screen.dart` — سطر إضافي لكل شاشة، نفس سابقة §٥.٨:
```dart
child: Brand.isPicPos ? const SalesInvoicesPicposScreen() : const SalesInvoicesScreen(),
// ... وهكذا لكل شاشة، وفرع else = سلوك UralCash الحالي حرف بحرف
```
وفي `screen_registry.dart` (للميزان فقط):
```dart
case BusinessProfile.lite:
  return Brand.isPicPos ? _litePicpos : lite; // _litePicpos = lite + ScreenId.scalePlu
```

## ٩. الاختبارات والتحقق

**لكل باتش:**
- `flutter analyze lib` (صفر مشاكل).
- **widget tests للمكوّنات المعزولة الجديدة** (طقم/شاشة الجيوجات/PicPos widgets) — **ليس** render
  شاشة كاملة (يهنّج تحت flutter_test — مصيدة §٥.٨).
- **اختبار الاختيار:** `Brand.isPicPos == false` لسه يعطي شاشة UralCash الأصلية.
- **الجولة الكاملة `--concurrency=1`** على العلامتين (التوازي بيفلك — §٥.٨).

**في النهاية:**
- `build_picpos.bat` (flutter على `$env:PATH` — §٥.٩) = SUCCESS.
- **فحص binary بالترميزين** (§٣.٤ + §٥.٥): ٤ ملاح · UTF-16=٠ · صفر لـ
  `monexia`/`cashier_market`/`avalon`/`uraljo`.

## ١٠. خارج النطاق

- أي منطق أعمال/محاسبة/مخزون/مزامنة (المحرك مشترك، يفضل زي ما هو).
- إعادة تصميم الجداول/النماذج/الحوارات نفسها (تأخذ شكلها من الثيم) — نغيّر **التأطير** فقط.
- شاشة `analytics` (خارج lite أصلاً).
- توصيل لوحة العرض الجانبية (`picpos_side_panel.dart`) — بند HANDOFF منفصل.
- أي تغيير في `Brand`/`AppColors`/الملاح/`AppFlavor`.

## ١١. مصادر الداتا الحقيقية (مرجع للتنفيذ)

| المزوّد | يعطي |
|---|---|
| `dashboardKpiProvider` | `revenue` (بدون ضريبة، بعد المردودات) · `invoiceCount` · `netProfit` · `outputVatNet` · `netRevenueInclVat` · `salesReturns` — من قائمة الدخل GL، مفلتر |
| `dashboardFilterProvider` | الفرع · مركز التكلفة · الفترة (from/to) |
| `dashboardCashBalanceProvider` | مجموع صناديق الفرع (مفلتر) — **لا** `totalCashBalanceProvider` |
| `todaySalesProvider` | فيد فواتير اليوم |
| `lowStockProductsProvider` | الأصناف تحت الحد |
| `PermissionCodes` | `treasuryBalanceView` · `dashboardProfit` |

## ١٢. أسئلة مفتوحة / مخاطر

1. **مقاييس الجيوجات** (التحصيل/التوزيع/الهدف): يُتحقّق وقت التنفيذ أي منها له مزوّد موجود؛
   الناقص = إضافة محرك patch أو يُقلَّص. «هامش الربح» مضمون اليوم.
2. **بوابة ميزة `scalePlu`**: يُتأكّد أن lite (بميزاته: `barcodeEnabled`) تسمح بعرض الشاشة، وإلا
   يلزم تفعيل الميزة المناسبة لـ PicPos-lite (قرار صاحب المشروع لو ظهر تعارض).
3. **مصدر «هدف المبيعات»**: إعداد قابل للضبط أم يُستبدل المؤشر بمقياس حقيقي آخر.

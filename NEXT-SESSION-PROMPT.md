# ابدأ من هنا — تحقّقٌ لا استكشاف

الشغلُ كلُّه على:

    D:\PICPOS-ERP\.claude\worktrees\picpos-settings-design-c25f5b
    الفرع: claude/picpos-settings-design-c25f5b

**أوّلُ أمرٍ تشغّله:**

```bash
cd "D:/PICPOS-ERP/.claude/worktrees/picpos-settings-design-c25f5b" && pwd && git rev-parse --short HEAD && git status --porcelain
```

المتوقَّع: المسارُ أعلاه، `85160567`، وشجرةٌ نظيفة.

⚠️ **ولو فُتحت الجلسةُ في worktree آخر** (حدث في أربع جلسات متتالية): لا تنتقل
يدويّاً. تحقّق أوّلاً أنّ فرعَك بلا شغلٍ خاصّ ثمّ قدّمه:

```bash
git rev-list --count HEAD ^claude/picpos-settings-design-c25f5b   # لازم 0
git merge --ff-only claude/picpos-settings-design-c25f5b
```

صفرٌ يعني لا شيءَ يضيع. غيرُ الصفر ⇒ **قف واسأل المالك**.

⚠️ **والشِّلُّ يرتدّ إلى جذر المستودع في منتصف الجلسة** — استعمل المسارات
الكاملة، وتحقّق بـ`pwd` قبل أيّ قياسٍ تبني عليه قراراً.

⚠️ **وأعِد قياسَ كلّ رقمٍ هنا بنفسك.** أرقامُ التسليم تبطُل.

⚠️ **والمالك يريد الشرحَ بالعربيّة** في كلّ ما يقرأه. الرموزُ وأسماءُ الملفّات
والأوامرُ تبقى بالإنجليزيّة.

---

## الحالة المقيسة (2026-08-25، آخرُ بوّابةٍ خضراء)

| السويّة | العدد |
|---|---|
| analyze | **٦ info بالضبط** (كلُّها في `test/`) |
| unit + data + structural + services | **4301** |
| widget + core + domain + presentation + security + static | **1094** |
| integration | **735** |

⚠️ الأعدادُ ارتفعت في هذه الجلسة بـ**٦٦ حارساً جديداً** — فلا تظنّها انحرافاً.

**البناءُ المنشور**: `app.so = ca61ae37d26a812917a893ccaf4e5dbb` — بُني من
`cc46054b`، أي أنّ **آخر ٤ كوميتات ليست فيه** (مركزُ التقارير الجديد ·
المؤشّرات · التبويبات · أوّلُ نسخة). نسخةٌ احتياطيّة:
`FlavorBuilds/PicPos.bak-2026-08-25-1545`.
أعِد القياس: `md5sum "D:/PICPOS-ERP/FlavorBuilds/PicPos/data/app.so"`.

---

## ما أُنجز في الجلسة السابقة — لا تُعِد فتحه

| البند | الحال |
|---|---|
| عمودُ أرقام المجموعات في اللوحات (`panel.index`) | ✅ |
| **لوحاتُ الإعدادات التسع** على الهويّة | ✅ تسعٌ من تسع |
| رافعةُ `AppFormDialog.buildPicposGroups` | ✅ خمسُ لوحاتٍ بمُتجاوَزٍ واحد |
| شريطُ مرشِّحات التقارير (`ReportFilterBar` → PicPos) | ✅ يخدم ١٣ شاشة |
| إطارُ `reportScaffold` | ✅ **٧ من ١٨** شاشةَ تقرير |
| **مركزُ التقارير** على تخطيط التصميم | ✅ شريطٌ مجمَّعٌ + لوحةُ تفصيل + مؤشّرات |
| تبويباتُ `PicPosReportTabs` | ✅ + أوّلُ شاشةٍ تركبها |
| أوّلُ نسخةِ PicPos مستقلّة (تقادم الذمم) | ✅ بعقدٍ محروس |

---

## 🔴 البندُ الأوّل — مراجعةُ المالك لتصميم الإعدادات

قال المالكُ 2026-08-25: **«خيار إدارة الصلاحيات ليس كما هو مطلوب تصميمه،
والعديد من الديالوجات والحوارات ليست كما المحتوى المطلوب في ملف التصميم»**.

### ١) مصفوفةُ الأدوار والصلاحيات

التصميمُ (`BENCH.perms`) يرسم **الأدوارَ أعمدةً والصلاحياتِ صفوفاً وتبديلاً في
مكانه**، مع «٣ تعديلات معلّقة» تُحفَظ دفعةً. والمبنيُّ اليومَ **دورٌ واحدٌ في
كلّ مرّة**، وقد أخذ غلافَ `PicPosDialog` وحدَه.

⚠️ **وهذا بناءٌ لا تنسيق**: حالةٌ معلّقةٌ لستّة أدوارٍ × ١٤٢ صلاحيةً معاً،
ويمسّ أخطرَ ما في النظام. اقرأ `BENCH.perms` و`MX_ROLES`/`MX_GROUPS`/
`MX_CHANGES` في التصميم الحيّ قبل أن تقدّر.

### ٢) محتوى الحوارات مقابل ملفّ التصميم

راجعْ حواراً حواراً مقابلَ `PicPos Settings.dc.html`. والجلسةُ السابقةُ نقلت
**البنية** (مجموعاتٌ وشرائحُ وعمودُ أرقام) ولم تراجع **نصوصَ المحتوى** بندَاً
بنداً.

⚠️ **وثمانيةُ مواضعَ لم تُنقَل عمداً لأنّ البرنامج لا يفعلها** — لا تُعِدها
بلا قياس:

- «تفعيل بملف ترخيص» مفتاحاً — الميزةُ **كشفٌ تلقائيّ** لا وضعٌ يُبدَّل.
- «فك التفعيل» — `deactivate` غيرُ موجودةٍ أصلاً.
- «الاسم القانوني» و«السجل التجاري» — لا عمودَ لهما في `CompanySettings`.
- لوحةُ مفاتيح الـPIN من أربع خانات — والحفظُ يقبل ٤–٦.
- «نسخ الصلاحيات من» و«مجموعات الصلاحيات» في لوحة الدور — الحوارُ يكتب الاسمَ فقط.
- «إنهاء الجلسات المفتوحة» و«إبلاغ واتساب» في إعادة التعيين — لا مقابلَ في الحفظ.
- «عرض الورق» و«الربط بنقاط البيع» في لوحة الطابعة — لا عمودَ لهما.
- «يُغلق البيعُ في مدّة العطلة» — العطلُ تدخل **حسابَ الرواتب** وحدَه (مقيس).

فإن أمر المالكُ بأيٍّ منها فهي **ميزةٌ تُبنى** لا نصٌّ يُكتَب.

### كيف تقرأ التصميمَ الحيّ (الوصفةُ التي نجحت)

```
projectId = 2c7b6006-4708-4883-95b7-59612cd6b517
```

1. `DesignSync` بـ`method: get_file` و`path: 'PicPos Settings.dc.html'`.
2. المخرَجُ أكبرُ من الحدّ فيحفظه الـharness في ملفٍّ ويعطيك مساره — **لا
   تحاول قراءتَه في السياق**.
3. فُكَّ ترميزَه بالسكربت الجاهز:
   ```bash
   perl <scratchpad>/decode.pl <tool-results-file> <out.dc.html>
   ```
   (‏يقرأ بـ`<:encoding(UTF-8)`، يطابق `"content":"(.*)","contentType"`،
   ويفكّ `\uXXXX` ثمّ `\n` ثمّ `\"`.)

⚠️ **ولا تقرأ النسخةَ المحلّيّة** في
`D:/PICPOS-ERP/تصميم شاشات فواتير PicPos-handoff/` — هي **أقدم** (١٨٨٤ سطراً
مقابل ٣٠٩٩ في الحيّ)، و`PANELS` فيها ستٌّ بينما الحيُّ تسع.

---

## 🔴 البندُ الثاني — سبعُ شاشاتٍ بتصميمٍ جديد

**قِستُ السبعَ كلَّها: جميعُها موجودةٌ في التطبيق. المطلوبُ إعادةُ تصميمٍ لا
بناءٌ من صفر.**

| # | الشاشة | المقابلُ في التطبيق | الحجم | فوركُ PicPos |
|---|---|---|---|---|
| ١ | الفروع | `screens/branch_management_screen.dart` | ٤٠٩ | ✗ |
| ٢ | المناطق | `screens/region_management_screen.dart` | ٢٧٧ | ✗ |
| ٣ | التحليلات | `screens/analytics_dashboard_screen.dart` | ١٥٠٠ | ✗ |
| ٤ | الموظفون | `screens/hr_screen.dart` + `screens/hr/widgets/` (‏١٠ تبويبات) | ١٠٠+٢٥٠٠ | ✗ |
| ٥ | الشيكات | `screens/commercial_papers_screen.dart` + `commercial_papers_dialogs.dart` | ٦٤٩ | ✗ |
| ٦ | الأصول الثابتة | `screens/fixed_assets_screen.dart` | ٦٥٥ | ✗ |
| ٧ | نقاط الولاء | `screens/loyalty_screen.dart` + ٣ تبويبات `part` | ١٠٥١ | ✗ |

⚠️⚠️ **حذّرْ نفسَك من هذا قبل أيّ قياس**: بحثتُ عن
`class Cheques extends Table` فوجدتُ **صفراً** وكدتُ أكتب «الشيكات ميزةٌ غيرُ
موجودةٍ تحتاج بناءَ جداولَ ومستودعٍ وشاشة». والحقيقةُ أنّ الجدولَ اسمُه
`CommercialPapers` (‏الأوراق التجارية) وأنّ الشاشةَ والحوارات والمستودعَ
والـusecase **كلَّها موجودة**. ونفسُ الشيء وقع مع الولاء: `class Loyalty`
صفرٌ، والجداولُ ثلاثةٌ بأسماءٍ أخرى (`LoyaltyPrograms` ·
`CustomerLoyaltyPoints` · `LoyaltyTransactions`).

**صفرُ المطابقات نمطٌ غلطٌ قبل أن يكون غياباً — والخطأُ هنا يكلّف جلسةً كاملةً
في بناء ما هو مبنيّ.**

### روابطُ الاستيراد كما أعطاها المالك

<details>
<summary>١ — شاشة الفروع</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Branches.dc.html

Focus on these files (the whole project is readable):
- `PicPos Branches.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Branches.dc.html`
```
</details>

<details>
<summary>٢ — شاشة المناطق</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Distribution.dc.html

Focus on these files (the whole project is readable):
- `PicPos Distribution.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Distribution.dc.html`
```
</details>

<details>
<summary>٣ — شاشة التحليلات</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Analytics.dc.html

Focus on these files (the whole project is readable):
- `PicPos Analytics.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Analytics.dc.html`
```
</details>

<details>
<summary>٤ — شاشة الموظفين</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Employees.dc.html

Focus on these files (the whole project is readable):
- `PicPos Employees.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Employees.dc.html`
```
</details>

<details>
<summary>٥ — الشيكات (الأوراق التجارية)</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Cheques.dc.html

Focus on these files (the whole project is readable):
- `PicPos Cheques.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Cheques.dc.html`
```
</details>

<details>
<summary>٦ — الأصول الثابتة والإهلاك</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Fixed+Assets.dc.html

Focus on these files (the whole project is readable):
- `PicPos Fixed Assets.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Fixed Assets.dc.html`
```
</details>

<details>
<summary>٧ — نقاط الولاء</summary>

```
Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/2c7b6006-4708-4883-95b7-59612cd6b517?file=PicPos+Loyalty.dc.html

Focus on these files (the whole project is readable):
- `PicPos Loyalty.dc.html`

Also read these files the selection imports:
- `assets/picpos-logo.png`
- `support.js`

Implement: `PicPos Loyalty.dc.html`
```
</details>

### وثامنٌ في المشروع لم يطلبه المالك

`PicPos Operating Expenses.dc.html` موجودٌ في مشروع التصميم، وله في التطبيق
`screens/operational_expenses_screen.dart`. **لا تبدأه بلا أمر.**

### ما يطلبه المالك في التنفيذ

> «يكون تنفيذك للتصميمات نفسَ التصميم المطلوب تنفيذه، مع **توثيق المطالب**
> ومراجعتي في المطلوب لنمط المحتوى التنفيذيّ.»

أي: نفّذ التصميمَ كما هو، ووثّق **لكلّ شاشة** ما نُقل وما لم يُنقَل ولماذا،
واعرض على المالك ما تحتاج مراجعتَه قبل أن تفترض.

---

## 🟡 البندُ الثالث — بقيّةُ شاشات التقارير

**١١ شاشةً ما زالت ترسم `AppBar` بيدها** (‏عدّادُ التقدّم في
`test/widget/picpos_report_bar_test.dart` يمنع أن **يزيد** العددُ عن ١١):

```
ar_aging_report_screen 318      category_profit_report_screen 487
consumption_report_screen 438   delivery_report_screen 660
expenses_report_screen 944      financial_statements_screen 1602
purchase_returns_report_screen 383  sales_returns_report_screen 378
tax_report_screen 876           top_products_report_screen 385
vat_reconciliation_screen 260
```

⚠️ `ar_aging_report_screen` باقٍ لأنّ **UralCash تفتحه** — نسخةُ PicPos منه
جاهزةٌ ومربوطةٌ بمركز PicPos.

**والأثقلُ فيها ما مرشِّحاتُه داخلَ الترويسة**: `financial_statements`
(‏منتقيا منطقةٍ وفرعٍ بأرضيّةِ `Colors.white/.15` مصمَّمةٍ لشريطٍ أزرق) و
`tax_report_screen` (‏منتقي مركز تكلفةٍ + زرُّ رجوعٍ صريح Spec 057). وأمرُ
المالك: **تنزل إلى شريط المرشِّحات كما في التصميم**.

---

## الأنماطُ المعتمَدة — اتبعها ولا تخترع غيرَها

### ١) 🔴 «نسخةٌ مستقلّةٌ لا تفريع» — أمرُ المالك 2026-08-25

> «لا تربط أيَّ أمورٍ من UralCash. إذا كان هناك أمرٌ مشتركٌ ولا نريد أن نعدّل
> على UralCash فقم بنسخه إلى PicPos بشكلٍ منفصلٍ وثبّت التصميمَ الجديدَ الخاصَّ
> بـPicPos.»

النموذجُ المنفَّذ: `reports_picpos/screens/ar_aging_report_picpos_screen.dart`.
وعقدُه محروسٌ في `test/static/reports_picpos_forks_test.dart` — **أضف كلَّ
نسخةٍ جديدةٍ إلى `_forks` هناك**، فالحارسُ يمسك أربعَ طرقٍ للانحراف:

- الأصلُ باقٍ ومركزُ UralCash يفتحه.
- ومركزُ PicPos يفتح **النسخةَ** لا الأصل (وإلّا كان الفوركُ ملفّاً ميّتاً).
- والمرشِّحاتُ في الشريط لا في الترويسة.
- **ولا لونَ سطحٍ ثابتٍ في النسخة** — وهو سببُ النسخ أصلاً.

⚠️⚠️ **والنسخُ يورّث المخالفاتِ كما يورّث الشكل.** أوّلُ نسخةٍ احمرَّت في
`presentation_db_import_guard` لأنّها ورّثت `import 'data/database'`: الأصلُ
ناجٍ بالتقادم (قائمةٌ بيضاءُ **مجمَّدةٌ** نصُّها «إضافةُ مخالفين جدد ممنوعة»)،
والنسخةُ جديدةٌ فلا تنجو. **الإصلاحُ في النسخة لا في الحارس**: اشتقّ ما تعرضه
من المزوِّد بلا أن تسمّي نوعَ القاعدة. وستّةُ ملفّاتٍ في تلك القائمة تخصّ
`commercial_papers` وحدَه — فاحسبها قبل أن تنسخ.

⚠️ **وأضف كلَّ نسخةٍ إلى** `test/structural/report_screens_resolve_branch_scope_test.dart`
إن كانت شاشةَ تقرير: هي **خارج** مجلّد `reports/` فما كانت لتُمسَح، وتسقط من
حارس حصر الفروع صامتةً.

### ٢) لبناتُ PicPos الجاهزة — لا تبنِ بديلاً

| اللبنة | الملفّ |
|---|---|
| إطارُ الشاشة (ترويسة + بحث + إجراءات + `subHeader`) | `picpos_shell/picpos_screen_scaffold.dart` |
| شريطُ المرشِّحات (مدىً + فتراتٌ جاهزة) | `picpos_shell/picpos_report_bar.dart` |
| **غلافُ شريط المرشِّحات العامّ + المرشِّحُ الواحد** | `picpos_shell/picpos_filter_strip.dart` |
| تبويباتُ التقرير | `picpos_shell/picpos_report_tabs.dart` |
| مجموعاتُ اللوحة + عمودُ الأرقام + الشرائح + صندوقُ القوّة | `picpos_shell/picpos_panel_groups.dart` |
| غلافُ الحوار + اللافتة + الصفّ + الملخّص | `picpos_shell/picpos_dialog.dart` |
| ألوانُ الأسطح تابعةً للثيم | `picpos_shell/picpos_surface.dart` |
| إطارُ شاشة التقرير (للمشتركة) | `screens/reports/report_scaffold.dart` |

### ٣) الأرقامُ تُقاس من الشجرة لا تُكتَب

عمودُ الأرقام يأخذ **العناوين** لا العدد؛ وعدّادُ الفئات يُشتقّ من
`mainReports.length`؛ وعنوانُ مركز التقارير الفرعيُّ يُشتقّ من `_allItems`.
**رقمٌ يكذب أسوأُ من لا رقم.**

### ٤) لا تنقل من التصميم ما لا يفعله البرنامج

قِسْ قبل أن تنقل. وإن كان التصميمُ يَعِد بما ليس موجوداً فاكتبْه في التسليم
بندَ سؤالٍ للمالك — لا تنفّذه ولا تحذفه صامتاً.

---

## دروسٌ كلّفت عطباً — اقرأها قبل أوّل سطرِ كود

**١) صفرُ المطابقات نمطٌ غلطٌ غالباً — والمطابقةُ الناجحةُ كذلك.**
- `class Cheques extends Table` صفرٌ والميزةُ كاملةٌ باسم `CommercialPapers`.
- `contains('branchScopeProvider')` طابق `branchScopeProviderXX` **كسابقة**،
  فبدا حارسُ تسريبٍ ماليٍّ معطَّلاً وهو سليم. **اكسر السلسلةَ في وسطها** حين
  تطفّر رمزاً لتختبر حارساً.
- `contains('fullBranchAccessRoleNames')` مرّ على إسقاط الشرط من فرعٍ كاملٍ
  لأنّ الرمزَ في الملفّ **ثلاثَ مرّات**. **عُدّ مرّاتِ ظهور الرمز قبل أن تثق
  بفحصِ وجوده**، واحصر الفحصَ في جسم الدالّة (`indexOf` بين اسمَي دالّتَين).

**٢) أثبت أنّ الطفرةَ دخلت الملفَّ قبل أن تصدّق «أخضر».** مرّتان في هذه الجلسة
لم تدخل طفرةٌ (اختلافُ إزاحة) — والسكربتُ الذي يموت عند صفر مطابقاتٍ هو ما
أمسكها. استعمل `scratchpad/mut.pl`.

**٣) استعِد بالنسخة الاحتياطيّة لا بـ`git checkout`** — و`diff -q` بعدها.

**٤) الحارسُ قد يكون هو المخطئ.** `toUpperCase()` حوّل `0x` إلى `0X` فأبلغ عن
ألوانٍ مسموحةٍ كمخالفات. ولو صدّقتُه لغيّرتُ كوداً سليماً.

**٥) `flutter analyze` يعدّ **كلَّ** ملفٍّ في مجلّد الحارس شاشةً.** ملفُّ
`report_scaffold.dart` أُبلغ عنه «شاشةُ تقريرٍ بلا حصر فروع» وهو دالّةُ غلاف.
الاستثناءُ يُكتب في `_notAScreen` بوسمٍ يفرّق: **ملفٌّ ليس شاشةً، لا شاشةٌ
مستثناةٌ من الحصر**.

**٦) `dart format` ممنوع** — والتحويلُ من `Scaffold` إلى نداء دالّةٍ ينقص
مستوى تعشيشٍ واحداً؛ **لا تُعِد إزاحةَ الجسم**، فالفرقُ يصير غيرَ قابلٍ
للمراجعة. اترك الجسمَ حيث هو.

---

## قيودُ المستودع

- ممنوع `dart format` · ممنوع تحرير `database.g.dart` · `build_runner` ~٤٥ د.
- ممنوع `git checkout` للتراجع — استعِد بـ`git show HEAD:` أو بنسخةِ ملفّ.
- **البوّابة** `bash scripts/gate.sh` ‏~١٢ دقيقة، `run_in_background: true`،
  وتحلّل **`lib test`**.
- ولا تحكم بكود الخروج عبر أنبوب — اقرأ `✓ البوابة كلها خضراء`، **واشترط
  عددَ ناجحين > صفر** في كلِّ سويّة، وافحص `errno = 183` و`Failed host lookup`
  = صفر. ولا تعدّ `✗` في السجلّ فشلاً: بعضُها سجلُّ تطبيقٍ من اختباراتٍ تختبر
  مساراتِ الفشل عمداً.
- **ولا تعدّل ملفاً والبوّابةُ تعمل.**
- البناء: `build_picpos.bat` **من الـworktree** عبر PowerShell بالمسار الكامل
  (‏~٤ دقائق). والسكربتُ ينسخ إلى `FlavorBuilds` **الـworktree** لا الجذر —
  فالنشرُ خطوةٌ بيدك: انقل الجذرَ إلى `PicPos.bak-<stamp>` ثمّ انسخ وتحقّق
  بـ`md5sum` على **`app.so`** (‏`PicPos.exe` حجمُه ثابتٌ دوماً فلا يدلّ).
- **والتشغيلُ بعين المالك يمسك ما لا يمسكه اختبار** — بلاغُ «مركز التقارير مش
  زي التصميم» جاء بصورةٍ منه، ولم يمسكه حارسٌ واحد.

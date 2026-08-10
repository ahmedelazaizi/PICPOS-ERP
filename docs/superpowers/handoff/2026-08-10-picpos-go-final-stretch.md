# جلسةُ الإغلاق النهائي — تسعُ شاشاتٍ وH15 والتشغيلةُ اليدوية، ثم حكمُ Go

انسخ هذا المستند كاملاً كأوّل رسالةٍ في الجلسة الجديدة.

---

## ٠. قبل أيّ شغل — فخاخٌ **مقيسةٌ** لا منقولة

### ٠-١ الـworktree الصحيح
```bash
git worktree list
cd D:/PICPOS-ERP/.claude/worktrees/client-branch-isolation-phase1-042024
git log --oneline -1     # لازم يكون d5faecd8 أو أحدث
```
لو `HEAD` أقدم فأنت في المكان الغلط. المستودعُ **بلا remote** ⇒ لا PR.

### ٠-٢ نظّف `build/native_assets` قبل أيّ `flutter test`
وإلا انهار المشغّل بـ`errno 183` على `sqlite3.dll`.
```bash
rm -rf build/native_assets
```

### ٠-٣ البوابةُ في الخلفية، والحكمُ من داخل السجلّ
تستغرق ~٢٠ دقيقة وسقفُ الأداة ١٠. **إشعارُ الخلفية يخصّ المُطلِق لا البوابة** —
لا تصدّقه. الحكمُ من `GATE_EXIT=` **و**نصِّ `✓ البوابة كلها خضراء` معاً.
```bash
rm -rf build/native_assets
nohup bash -c 'bash scripts/gate.sh --pg > /tmp/gate.log 2>&1; echo "GATE_EXIT=$?" >> /tmp/gate.log' >/dev/null 2>&1 &
# ثم: until grep -qa "GATE_EXIT=" /tmp/gate.log; do sleep 20; done
```

### ٠-٤ ⚠️ لا تشغّل البوابةَ على شجرةٍ تتحرّك
حصل في الجلسة السابقة: عدّلتُ ملفاتٍ أثناء التشغيل فصرّحت البوابةُ حمراءَ
لسببٍ زائف، وضاعت ~٢٠ دقيقة. **ثبّت أولاً، ثم شغّل، ثم لا تلمس شيئاً.**

### ٠-٥ `perl -0777 -pi -e` تفشل **صامتةً** على CRLF
تحقّق دائماً بـ`grep` بعدها. استعمل أداةَ التحرير بدلاً منها.

### ٠-٦ بناءُ PicPos ولقطُ الشاشة
```powershell
Start-Process cmd.exe -ArgumentList '/c','call .\build_picpos.bat > build_picpos.log 2>&1' -WorkingDirectory "D:\PICPOS-ERP\.claude\worktrees\client-branch-isolation-phase1-042024" -WindowStyle Hidden
```
مقيس: ~٤ دقائق، والناتج `FlavorBuilds\PicPos\PicPos.exe`. لا تبنِ بـ
`flutter build windows` عارياً — `Brand.id` افتراضُه `uralcash`.
والسكربتُ يستبدل `windows/runner/resources/app_icon.ico` (متتبَّع) — افحص
`git status` بعده.
عند التشغيل: `Start-Process` ثم `AppActivate` ثم `CopyFromScreen`.
**لا تستعمل `ShowWindow(h,3)`** وتحقّق أن `GetForegroundWindow` يطابق الـpid
قبل تصديق اللقطة.

---

## ١. الحالة — مقيسةٌ 2026-08-10

| البند | القيمة |
|---|---|
| الفرع | `claude/section-5-structured-format-ural-b97659` |
| آخر كوميت | `d5faecd8` |
| الشجرة | نظيفة |
| البوابة | **خضراء بالحكمَين** عند `4b42c9ee` |
| خطُّ الأساس | analyze **٦ info** · unit **٢٩٦٨** · widget **٦٥١** · integration **٦٦٧** · pg **٤٥** |

⚠️ **الحدودُ في `gate.sh` أقدمُ من الشجرة الآن**: أُضيفت ١٠ اختباراتٍ
تكامليةٍ بعد آخر تشغيلةٍ كاملة (H8 ×٣ · H11 ×٢ · H14 ×٤ ... إلخ في
`picpos_report_consistency_test.dart`). **أوّلُ شيءٍ تفعله: شغّل البوابة
كاملةً، اقرأ الأرقام، وارفع الحدود** — لا تخمّنها.

**النطاق:** PicPos = `BusinessProfile.lite`. الموارد البشرية والأجور **خارج
النطاق** (`hrEnabled: false`) — الكودُ يبقى مسيَّجاً ولا يُحذف ولا يُفعَّل.

---

## ٢. ما أُغلق — لا تُعده ولا تراجعه

عشرون بنداً، كلُّها بأحمرَ مقيسٍ ثم أخضر. التفصيلُ الكاملُ بالأرقام في
`docs/superpowers/audits/2026-08-10-picpos-go-blockers.md` — **اقرأه أولاً**.

B1 · B2 · B3 · B4 · إلغاءُ مرتجع المبيعات · تكلفةُ الصنف المركّب ·
H1 · H2 · H3 · H4 · H5 · H6 · H7 · H8 · H9 · H10 · H11 · H12 ·
H13 (‏الخزينة وحدَها) · H14 · H16 (الخط) · سندُ الإضافة · CE-1 · SC-1.

---

## ٣. المطلوب — بالترتيب

### أ) H13 — تسعُ شاشاتٍ باقية (‏الأكبر، والأكثرُ ميكانيكية)

**العطب:** `initState` يبذر `_selectedBranchId` من `activeBranchIdProvider`
ثم ينادي `_loadData` مباشرةً، بينما حلَّ الفرعِ إلى نطاقِ الاستعلام
(`_branchSafeIds` / `_branchWarehouseIds`) يعيش داخل `onBranchChanged` وحدَه.
فعلى أوّل تحميل: **القائمةُ تُظهر اسمَ الفرع والأرقامُ لكلّ الفروع**، ولا شيءَ
على الشاشة يكشف الفرق.

و`allowedBranchIds` لا يُنقذ — سقفُ **صلاحية** لا فلترُ عرض، وصاحبُ الوصول
الكامل يأخذ `null`.

**الوصفة** (‏طُبِّقت على `treasury_report_screen.dart` — اقرأها كنموذج،
كوميت `d5faecd8`): استخرج جسمَ `onBranchChanged` إلى دالّةٍ خاصّة ونادِها
**بعد** البذر و**قبل** أوّل `_loadData`.

**التسع:**
`category_profit_report_screen` · `delivery_report_screen` ·
`purchase_returns_report_screen` · `purchases_report_screen` ·
`sales_by_classification_report` · `sales_report_screen` ·
`sales_returns_report_screen` · `tax_report_screen` ·
`top_products_report_screen`

**تحقّقٌ آليّ من التغطية** (‏يجب أن يطبع `initStateResolves=1` للعشرة):
```bash
for f in lib/presentation/screens/reports/*.dart; do
  grep -q "activeBranchIdProvider" "$f" && grep -qE "_branchSafeIds|_branchWarehouseIds" "$f" || continue
  echo "$(basename $f) initStateResolves=$(awk '/void initState/,/^  }/' "$f" | grep -cE '_resolveBranch|_branchSafeIds|_branchWarehouseIds')"
done
```

**واكتب حارساً بنيوياً** يفرضها — على نمط
`test/structural/report_screens_resolve_branch_scope_test.dart` الموجود
(الذي يفرض *وجودَ* `branchScopeProvider`). الجديدُ يفرض أن كلَّ شاشةٍ تبذر
فرعاً **تحلّه** في `initState`. بدونه تعود الفئةُ مع أوّل شاشةٍ جديدة.

### ب) H15 — `adjustSafeBalance` مُخالَفٌ في ٤ مسارات كاش
**مقروءٌ لا مقيس** في الحصر — `treasury_dao.dart` و`sales_mutations_dao.dart`.
سباقُ «قراءة ثم كتابة» تحت PostgreSQL. **قِسه قبل أن تُصلحه**: `createSafeTransaction`
يستعمل `UPDATE safes SET balance = balance ± ?` الذرّيّ فعلاً (قرأتُه)، فالبنودُ
الأربعةُ قد تكون مسارات `updateSafeBalance` المباشرة. عُدّها بنفسك.

### ج) المتوسطة السبع (‏من الحصر)
الورديات: فلترُ مخزنٍ لا يُطبَّق وسقفُ ١٠٠ صفٍّ صامت · المصروفات: الفرعُ غيرُ
متماثلٍ بين شقّي الاتحاد وعمودا تاريخٍ مختلفان · تصديرُ Excel لا يتبع خانات
العشرية · كلُّ خزنةٍ تسقط على ١١١١ (`linkedAccountId` فارغ) · `balanceAfter`
إسقاطٌ لا يُعاد حسابُه · `repairAllMissingInvoiceJEs` غيرُ منادى عند الإقلاع.

### د) §٧-٣ — التشغيلةُ اليدوية (‏معيارُ Go الوحيدُ غيرُ البرمجيّ)
ابنِ (§٠-٦) ثم شغّل وأدِر بالفعل:
بيعةٌ كاملة ← إقفالُ وردية ← إقفالٌ يوميّ ← تقرير ← **طباعةُ إيصالٍ فيه اسمٌ
آخرُه ي بعد حرفٍ غيرِ موصول** («صبري») والتأكّدُ أن الحرفَ ظهر.
لقطةُ شاشةٍ **مُتحقَّقٌ** أنها نافذةُ التطبيق.

الأدلّةُ البرمجيةُ على الخط خضراءُ كلُّها (‏`pdf_arabic_glyph_coverage_test` ·
`pdf_document_font_fallback_wiring_test` · `no_bare_pdf_document_test`) —
الناقصُ التأكيدُ البصريّ وحدَه.

---

## ٤. معيارُ Go — لا تُصدِر الحكمَ قبل استيفائه

1. البوابةُ كاملةً بـ`--pg` خضراء، بالحكمَين معاً، **على شجرةٍ ثابتة**.
2. **صفرُ بلوكراتٍ مفتوحة** من §٣.
3. التشغيلةُ اليدويةُ في §٣-د، بلقطةٍ متحقَّقة.
4. لكلّ بندٍ أُصلح: اختبارٌ **شوهد أحمرَ أوّلاً** ثم أخضر.
5. حدودُ `gate.sh` مضبوطةٌ على المقيس في نفس الكوميت.

وإن بقي بندٌ مفتوح: **صرّح NO-GO واذكر البند**. وحدِّد نطاقَ حكمك: PicPos lite
وحدَه، ولا تحكم على UralCash (‏`D:/URAL-ERP` لم يُلمس).

---

## ٥. درسان منهجيّان من الجلسة السابقة — اقرأهما قبل أن تبدأ

**١. اقتراحُ الإصلاح في مستند التسليم قد يكون خاطئاً حتى لو كان تشخيصُ العطب
صحيحاً.** H16 مثالُه: العطبُ حقيقيّ (الياءُ تُحذف)، والوصفةُ المقترَحة
(`fontFallback` عبر الثيم) **لا يمكن أن تعمل** — حزمةُ `pdf` تختار الخطَّ
الاحتياطيَّ على النصّ **المنطقيّ** قبل التحويل لأشكال العرض. تنفيذُ الوصفة
حرفياً كان سيعطي كوميتاً يبدو صحيحاً ولا يُصلح شيئاً.
⇒ **اكتب اختبارَ الأحمر من السلوك المرصود لا من الوصفة.** لو بقي أحمرَ بعد
تطبيقها فالوصفةُ خطأٌ لا تنفيذُك.

**٢. الضابطُ الأخضرُ ليس ترفاً.** ثلاثَ مرّاتٍ في الجلسة السابقة سقط الضابطُ
أولاً فكشف **تجهيزةً ناقصة** لا عطباً في المنتج: BOM غيرُ فعّالة ·
`into(parties).insert` لا ينشئ حساباً فرعياً (بخلاف `insertParty`) ·
`pw.Text` بلا `textDirection` لا يُشكّل أصلاً. بلا الضابط كنتُ سأطارد أعطالاً
وهمية.

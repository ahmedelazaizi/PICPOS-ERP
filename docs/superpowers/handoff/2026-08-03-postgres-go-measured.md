# وضع PostgreSQL — أول قياس على سيرفر حي

المشروع: `D:\PICPOS-ERP` · الفرع `claude/postgres-go-handoff-b8bbe4`
(آخر كوميت `8579b3f4`). الشجرة نضيفة.

يكمّل — ويصحّح — `docs/superpowers/handoff/2026-08-03-postgres-go.md`.

---

## ٠. اقرا ده الأول

**الفرع.** الجلسة دي فتحت على فرع **متأخر ١٧٦ كوميت** (كان على `main`
بينما الشغل كله على `claude/architectural-five-handoff-d7eb45`). نفس الفخ
اللي الـhandoff السابق حذّر منه بالظبط، وحصل تاني. اتحل بـ`merge --ff-only`.
**قبل أي شغل:**

```bash
git rev-list --left-right --count HEAD...claude/architectural-five-handoff-d7eb45
```

**PostgreSQL حيّة موجودة.** الشرط اللي الـhandoff السابق قال إنه بيفرق بين
GO و`v132` تانية — **اتحقق**. PG 18.4 على `127.0.0.1:5432`، قاعدة `picpos`
مخصّصة للاختبار (المالك عملها). الرِج شغّال بـ`PG_TEST_DSN` من غير docker
(‏`scripts/run_pg_tests.dart` بيطلب docker وهو مش متنصّب — تجاوزه بتصدير
المتغير مباشرة).

> ⚠️ `bootPgTestSchema()` بيعمل `DROP SCHEMA public CASCADE`. **متوجّههوش
> على `uralcash` ولا `Avalon`** — الاتنين على نفس السيرفر وفيهم بيانات.

---

## ١. الخلاصة — القياس غيّر الصورة جذرياً

الـhandoff السابق قال **NO-GO** بناءً على ٥ بنود «متحقَّق منها نصّياً».
القياس على سيرفر حي أثبت إن **٣ من الـ٥ مش مشكلة على تنصيبة جديدة**،
وكشف بنود تانية أخطر ماحدش كان شايفها.

### التركيبة على تنصيبة PG جديدة — **سليمة**، مش مكسورة

| القياس | العدد |
|---|---|
| جداول | ١٥٥ |
| `PRIMARY KEY` | **١٥٤** (الوحيد بلا مفتاح هو `__schema` بتاع drift — طبيعي) |
| `UNIQUE` | **٥٣** |
| `FOREIGN KEY` | **٢٦٩** |
| `CHECK` | ١٢٠ |

**الجداول التمانية بتاعة البند ٢-٣ كلها ليها مفاتيحها المركّبة فعلاً:**

```
category_branches      PRIMARY KEY (category_id, branch_id)
document_sequences     PRIMARY KEY (prefix)
processed_messages     PRIMARY KEY (idempotency_key)
role_permissions       PRIMARY KEY (role_id, permission_id)
settings               PRIMARY KEY (key)
user_branch_access     PRIMARY KEY (user_id, branch_id)
user_region_access     PRIMARY KEY (user_id, region_id)
user_warehouse_access  PRIMARY KEY (user_id, warehouse_id)
```

و`sales_invoices.global_id UNIQUE` — مثال البند ٢-٢ الرئيسي — **موجود**.
وكذلك `sale_bom_consumptions.global_id` و`pos_terminals.device_id`.

و`processed_messages` مطابق لـdrift بالظبط:
`text / text / text nullable / bigint`.

**ليه؟** `_createAllForPostgres` **مرحلة ١** بتنادي `m.create(entity)` بتاعة
drift نفسها، وDDL بتاع drift **واعي بالديالكت** وبيطلّع كل القيود صح على PG.
البنّاءات المكتوبة بالإيد (اللي بتسقّط القيود) مسار **احتياطي** بيشتغل بس لما
المرحلة ١ تفشل — وهي مافشلتش.

⇒ **البنود ٢-٢ و٢-٣ ما بتنطبقش على تنصيبة جديدة.** بتنطبق بس على سيرفر
قديم اتبنى بإصدار أقدم أو من `supabase_migration_v118.sql`. يعني شغل
**سكربت تسوية**، مش بند مانع للإصدار.

---

## ٢. اللي اتصلّح في الجلسة دي

### ٢-١ ⛔ تمريرة الإصلاح كانت بتبهدل الإقلاع نهائياً — `a2a85d91`

**البند الوحيد من الخمسة اللي اتأكد إنه مانع فعلاً.** ومُقاس، مش مقروء:

إسقاط `processed_messages.response_payload` وسيبان صف واحد ⇒

```
23502: column "response_payload" of relation "processed_messages"
       contains null values
⇒ PgSchemaParityException ⇒ database_startup rethrow ⇒ شاشة Fatal
```

وزرار «إعادة المحاولة» بينفّذ `SELECT 1` اللي بيعيد `beforeOpen` ⇒ نفس
الـALTER ⇒ نفس الاستثناء. **تبهدل دائم**، مالوش مخرج غير `--use-sqlite`.

المدى: **٤٣٤ عمود** non-nullable بلا default عبر ١٤٨ جدول. والسيناريو مش
افتراضي — `onUpgrade` متخطّى بالكامل على PG، فالتمريرة دي هي الآلية
**الوحيدة** اللي بتضيف عمود لجدول PG قايم.

الإصلاح: العمود بينزل `nullable` بدل ما الإقلاع يقع، مع بصمة
`nullability=degraded_to_nullable ... followup=needs_backfill_then_set_not_null`.
`CREATE TABLE` ما اتغيّرش. اختبار: `pg_heal_not_null_column_pg_test.dart`
(اتشاف أحمر على PG حيّة بالاستثناء الحرفي فوق).

### ٢-٢ ⛔ `getSingleOrNull` بلا `limit(1)` — ٤ مواضع — `2f4a1e80`

`roles.name` **مالهاش أي قيد وحدانية** (مقيس: القيود هي `PK(id)` و
`UNIQUE(global_id)` وبس)، و`seedRolesAndPermissions` بتولّد `globalId` جديد
كل نداء فـ`insertOrIgnore` مالهاش قيد تتعارض معاه ⇒ صفوف مكرّرة **حالة
مسموح بيها فعلاً على الديالكتين**.

و`getSingleOrNull` في drift هي `list.single` — **بترمي** على أكتر من صف، مش
بترجّع الأول. والأربع مواضع كلها بتبلع الاستثناء في `catch`:

| # | الموضع | الأثر |
|---|---|---|
| ١ | `permissions_dao:408` | أي كود صلاحية جديد **عمره ما يوصل لمدير النظام** — صامت تماماً |
| ٢ | `database_startup:481` | إصلاح `roleId` للأدمن ما بيشتغلش |
| ٣ | `database_startup:851` | مسار الأدمن الاحتياطي الأخير ⇒ تنصيبة بلا أدمن |
| ٤ | `api_handler_base:81` | **الأخطر** — صف مكرر ⇒ كل طلب لاحق بنفس المفتاح بيرمي ⇒ ٥٠٠ دائم ⇒ الـoutbox بيعيد المحاولة للأبد وكل محاولة بيعة جديدة |

اختبار: `test/unit/duplicate_role_name_lookup_test.dart` — أحمر أولاً بـ
`Bad state: Too many elements`.

### ٢-٣ عطل fixture كان مغطّي على باج حقيقي — `8579b3f4`

تلات اختبارات في `users_endpoint_pg_test` كانت بتفشل بـ`23503` لأن فرع ٢
عمره ما اتعمل — PG بتنفّذ الـFK اللي SQLite ماكانتش بتفحصه. بعد الإصلاح
واحد بقى أخضر **والاتنين الباقيين بقوا بيفشلوا لسبب حقيقي** (بند ٤-١ تحت).

---

## ٣. تصحيحات على الـhandoff السابق — لازم تتقري

| الادعاء | الحقيقة |
|---|---|
| «`col.defaultConstraints` مش بيتقري ⇒ صلّحه» | **الوصفة دي مكانتش هتتكمبايل.** في drift 2.32.1 ده **حقل خاص بلا getter عام** (`column_impl.dart:19`). مافيش حاجة «تتقري». |
| «‏`insertOrIgnore` في ٣ مواضع» | **٥٤ موضع** في `lib/`. والآلية مؤكَّدة: drift بيحوّلها لـ`INSERT` عادي على PG (`insert.dart:466-476`) و`DO NOTHING` بتتكتب بس لما يتبعت `onConflict` كمان. |
| «رتّب ٢-٢ (UNIQUE) قبل ٢-٤ (insertOrIgnore)» | **معكوس.** الترتيب ده بيحوّل «تكرار صامت» لـ`23505` في ٤ مواضع بلا `catch` جوه ترانزاكشنات. ابدأ بـ٢-٤ **بشكل محايد للقيود**، بعدين ٢-٢. |
| «‏`إعدادات الخزينة {key}`» | اسم الجدول `settings` (مفتاح/قيمة عام)، والاسم اتاخد من اسم الملف بالغلط. |
| «‏`category_branch_*`» | الاسم الفعلي `category_branches`. |
| «‏`role_permissions` و`settings` محتاجين سكربت» | **اتصلّحوا خلاص** في `_ensureDatabaseIntegrity` (`database_startup.dart:189-327`). الفجوة الفعلية ٦ جداول مش ٨ — ووسّع الميثود دي بدل ما تكتب سكربت جديد. |

**فروق البند ٢-٥ أكتر من تلاتة — خمسة.** الاتنين الزيادة:
`created_at` (drift `BIGINT` epoch مقابل `timestamptz`) و`branch_id` (موجود
في الـSQL ومش موجود في drift). و`created_at` هو الأخطر لأن كل قراءة drift
هتاخد `DateTime` مكان `int`.

---

## ٤. البنود المفتوحة — مرتّبة بالمخاطرة

### ٤-١ ⛔ الإصلاح الذاتي للأدمن **مش شغال على PostgreSQL** — جديد ومقيس

بعد إصلاح الـfixture، اختباران بيفشلوا لسبب منتج حقيقي:

| الاختبار | متوقَّع | فعلي |
|---|---|---|
| استرجاع صف `admin` متمسوح فعلياً | `true` | `false` |
| استرجاع `__dup_1_admin` لـ`username=admin` | `'admin'` | `'__dup_1_admin'` |

سيرفر PG فقد صف الأدمن **ما بيرجّعهوش**. محتاج تشخيص لوحده.

### ٤-٢ ⛔ سباق أرقام الفواتير على PG — جديد

`getNextDocumentNumber` بيعمل `SELECT → احسب → UPDATE` على
`document_sequences` **بلا `SELECT ... FOR UPDATE`**. قفل الكتابة العام في
SQLite بيخبّي ده؛ PG على `READ COMMITTED` لأ ⇒ طلبين متزامنين بياخدوا **نفس
الرقم**.

والتعليق في `database.dart:1906-1910` بيقول: «الوحدانية مضمونة بـ… الـUNIQUE
index على `invoice_number`». **مقيس: مافيش أي فهرس أو قيد كده على أي
باكيند.** `sales_purchase_tables.dart:91,179` أعمدة `text()` عادية.

فيه اختبار اسمه `client_issue_m4_duplicate_invoice_no_test.dart` — ابدأ منه.

### ٤-٣ ⚠️ `insertOrIgnore` — ٥٤ موضع

**اعملها محايدة للقيود** (فحص وجود صريح، أو `ON CONFLICT DO NOTHING` خام
اللي بيبقى no-op قانوني لو مافيش قيد) عشان تبقى صح تحت الحالتين.
الأخطر: `api_data_handler.dart:3337/3456/3585/3696` — جوه ترانزاكشنات بلا
`catch`، فـ`23505` بيسمّم الترانزاكشن (‏`25P02`) وبيضيّع الطلب كله.

### ٤-٤ ⚠️ سكربت تسوية للسيرفرات القايمة (٢-٣ + ٢-٥ مع بعض)

مش في مسار الإقلاع. فحص تكرارات → تقرير للمالك → dedup بقرار →
`ADD CONSTRAINT`. **شغّل استعلامات اليتامى الأول** — `ADD CONSTRAINT` على
بيانات فيها يتامى بيفشل، والفشل في الإقلاع = `v132` تاني:

```sql
SELECT count(*) FROM child c LEFT JOIN parent p ON p.id = c.<fk>
WHERE c.<fk> IS NOT NULL AND p.id IS NULL;
```

### ٤-٥ ℹ️ الفهارس — **مش بند مانع** (تصحيح لاستنتاج بدري في الجلسة دي)

القياس بيدي **٢٠٨ `create_index_failed`** على PG. السبب: `build.yaml` مافيهوش
خيار `dialects:` فـdrift بيسجّل SQL الفهرس تحت `SqlDialect.sqlite` بس، و
`pickForDialect` بيعمل `assert`.

**بس `assert` متعطّل في بناء الإصدار**، و`pickForDialect` بيرجع
`sql.values.first` كـfallback — والجملة نفسها (`CREATE INDEX x ON t (c)`)
**صالحة في PostgreSQL**. يعني الإصدار الحقيقي بياخد فهارسه.

الأثر الفعلي: **سويت `integration_pg` بتشتغل على تركيبة بلا فهارس**، فما
تقدرش تتحقق من أي سلوك معتمد على فهرس. الحل الجذري إضافة
`dialects: [sqlite, postgres]` لـ`build.yaml` — **محتاج `build_runner`
والمالك هو اللي يشغّله** (متجمّد في جلسات الوكيل).

### ٤-٦ ℹ️ `idx_je_autopost_dedup` مش موجود على PG — فجوة **معروفة ومقصودة**

`database.dart:288-290` بيقولها صراحة. السبب `WHERE is_auto_posted = 1` وهو
`BOOLEAN` على PG. الأثر محدود: PG بيفقد طبقة دفاع عميق ضد تكرار القيود
التلقائية؛ الحارس البرمجي لسه شغال. الشكل الصالح على PG:
`WHERE is_auto_posted`.

---

## ٥. البوابة

| السويت | النتيجة |
|---|---|
| `test/integration_pg` (PG حيّة) | **١٠ ناجح · ٤ فاشل** (كان ٨/٥ قبل الجلسة) |
| الفاشلين الـ٤ | ٢ إصلاح الأدمن (٤-١، منتج) · ٢ تأكيدات تمريرة التطابق |
| `pg_schema_parity_static` + idempotency | ٢٠ ناجح |
| `flutter analyze lib test` | ٦ `info` — خط الأساس بالظبط |

**ما اتشغّلتش:** `test/unit` الكاملة (~١١ دقيقة) و`test/integration`.
شغّلهم قبل أي تصديق إصدار.

### تشغيل سويت PG

```bash
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" \
  flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1
```

---

## ٦. مصايد بيئة — إضافات على قايمة الـhandoff السابق

- **`scripts/run_pg_tests.dart` بيطلب docker** وهو مش متنصّب. الرِج نفسه
  محتاج `PG_TEST_DSN` وبس — صدّره مباشرةً.
- **`psql` مش على الـPATH**؛ موجود في `C:\Program Files\PostgreSQL\18\bin`.
  والمصادقة `scram-sha-256`، فـ`psql` من غير كلمة سر **بيعلّق** على السؤال
  التفاعلي لحد الـtimeout. استعمل `PGPASSWORD` و`-w`.
- **٣ قواعد على نفس السيرفر** (`picpos`, `uralcash`, `Avalon`). الرِج بيمسح
  الـschema — `picpos` بس.
- **`assert` في drift بيكذب عليك في الاختبارات** — سلوك `flutter test`
  (assertions شغّالة) مش سلوك الإصدار. شوف ٤-٥؛ ده حوّل «٢٠٨ فهرس مفقود
  في الإنتاج» لـ«مسألة أمانة اختبارات». **اتحقق من مسار الـrelease قبل ما
  تسمّي حاجة بند مانع.**

---

## ٧. تعريف «خلصت» (لسه مفتوح)

`release-certification` بيدّي **GO لوضع PostgreSQL**. فاضل: ٤-١ و٤-٢ (اتنين
منتج مقيسين) و٤-٣، وسكربت التسوية ٤-٤ موثّق في `RELEASE_NOTES` تحت «يحتاج
إجراءً منك».

**الوضع الحالي: لسه NO-GO — بس لأسباب مختلفة تماماً عن اللي الـhandoff
السابق حدّدها، وأقل عدداً.**

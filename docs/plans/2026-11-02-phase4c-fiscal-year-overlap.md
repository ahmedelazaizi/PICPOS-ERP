# المرحلة 4C — إصلاح تداخل السنوات المالية

## قائمة التحقق النهائية (6/6)
1. ✔ **تحليل الأسباب بالأرقام:** `id=1` أُنشئ `1793319389`، و`id=2` بعد 16 ثانية عند `1793319405`. مسار PostgreSQL `_seedCurrentFiscalYearIfMissing` في `database_seeder_postgres.dart` (ونظيره في `database_startup.dart`) ينشئ id=1 باسم «السنة المالية 2026» بنهاية `23:59:59`؛ `ServerSetupWriter._fiscalYear` يطابق الاسم الحرفي `2026` فقط، فيعتبر الاسم مختلفاً وينشئ id=2 بنهاية `DateTime(year, 12, 31)` (منتصف الليل). `SetupFinishRunner` كان يحمل الإنشاء ذاته بنهاية منتصف الليل لمسار الإعداد المحلي. لا يوجد رمز `createDefaultFiscalYear`؛ مواضع الإنشاء التلقائي المكتشفة: seeder وstartup وserver writer وsetup runner. بعد إنشاء 12 فترة لـid=1، منع القيد الفريد `(month,year)` إسناد الفترات للمكرر.
2. ✔ **جرد الارتباطات:** قيود FK إلى `fiscal_years.id` هي `accounting_periods.fiscal_year_id`, `budgets.fiscal_year_id`, و`restatements.fiscal_year_id`; counts id=1/id=2 هي 12/0 و0/0 و0/0 على الترتيب. `journal_entries.fiscal_year_id` عمود موجود بلا FK ويحتوي 3/0. لم يظهر جدول مستقل للإقفال أو للأرصدة الافتتاحية يحمل FK/`fiscal_year_id`. إجمالي القيود 3، الحسابات 185، المدين والدائن 314.55 لكل منهما. عمود `deleted_at` متاح للإخفاء.
3. ✔ **ترحيل وسكربت مستقلان:** معاملات، جرد FK وكل عمود `fiscal_year_id`، رفض عند وجود مراجع، تحديث soft-delete idempotent، تحقق قيود/أرصدة قبل وبعد، و`-WhatIf` افتراضي مع `-Apply` ونسخة `pg_dump` مسبقة.
4. ✔ **حارس التداخل:** اليدوي يرفض برسالة عربية؛ مسارات الإعداد والإقلاع تعيد السنة الموجودة؛ نهاية اليوم موحدة إلى `23:59:59.999`؛ السنوات المحذوفة منطقياً لا تظهر ولا تدخل في الاختيار/التغطية/التقارير.
5. ✔ **تطبيق على نسخة المالك داخل الحاوية فقط:** 12 فترة و3 قيود قبل/بعد، الأرصدة لم تتغير، سنة مرئية واحدة، وإعادة التشغيل بلا تغيير؛ تقريرا الدخل والمركز المالي نجحا عبر PG بعد الإصلاح.
6. ✔ **الحزم النهائية:** اختبارات phase4 والفترة/الإقفال/السنة وsetup والهيكلية نجحت؛ آخر `flutter analyze` شمل 10 ملفات وانتهى `No issues found!`.

## نقاط التفتيش
### Checkpoint 1 — اختبار فاشل قبل الإصلاح
شُغّل `Invoke-FlutterTest test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` قبل الحارس؛ فشل لأن السنة المتداخلة أُنشئت.

### Checkpoint 2 — الحارس واختباراته
أضيف فحص تداخل على مستوى أيام التقويم إلى `createFiscalYear`، وطريقة `ensureFiscalYear` للمسارات التلقائية تعيد السنة القائمة، مع استبعاد `deleted_at` من استعلامات السنوات النشطة/الظاهرة. أصبحت نهاية السنة `23:59:59.999`. اختبارات `test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` أظهرت `00:09 +4: All tests passed!` وتشمل التداخل اليدوي، إعادة مسار الإنشاء التلقائي، ترحيل id=2، عدم تغيير الفترات/القيود/الأرصدة، إعادة التشغيل، التوقف عند مرجع، وعمل تقريري الدخل والمركز المالي. حدث تعثر DLL سابقاً، ثم نجحت الإعادة بعد تأكيد وجود `build/native_assets/windows/sqlite3.dll`.

اختبار المرحلة 2 كشف حالة كانت تنشئ FY 2026 ثانية رغم وجود السنة الافتراضية، برسالة `لا يمكن إنشاء السنة المالية: تتداخل مع السنة المفعّلة "السنة المالية 2026"`. حُدّث fixture ليعيد استعمال السنة القائمة، دون تغيير هدف الاختبار؛ بعدها خرج `00:16 +6: All tests passed!`.

### Checkpoint 3 — تطبيق PG على نسخة خاصة
أعيدت النسخة `backups/postgres/picpos_20261101_212419.dump` إلى حاوية خاصة `picpos-fy-overlap-qa` على `127.0.0.1:58120` فقط. الأمر `scripts/fiscal_year_overlap_repair.ps1 -Apply -Port 58120` أنشأ نسخة `pg_dump` عبر `scripts/backup_postgres.ps1` ثم نفّذ الترحيل. الخرج قبل/بعد:

`years=2; visible=2` → `years=2; visible=1`
`journal_entries=3` قبل وبعد
`periods=12` بعد
`disabled id 2: 1 row(s) changed`
`verified invariants: journal_entries 3 -> 3, per-account balances unchanged`

حالة id=1 بقيت مرئية ونشطة، وid=2 أصبح له `deleted_at=1793577710` و`is_current=false`. لم يُتصل بقاعدة المالك أو المنفذ 5432. أُعيد تشغيل `-Apply` على النسخة بعد نجاح العملية للتحقق من إعادة التشغيل؛ لم تتغير البيانات (`disabled id 2: 0 row(s) changed`).

### Checkpoint 4 — تقارير PG والحزم النهائية
بعد تطبيق الترحيل وإعادة تشغيله بنجاح على النسخة فقط، شغّل اختبار اتصال قراءة/تقارير PostgreSQL دون reset للـschema، ونجح: `Invoke-FlutterTest test/phase4/fiscal_overlap/fiscal_overlap_pg_reports_test.dart -PgDsn "postgres://picpos:picpos-local-only@127.0.0.1:58120/picpos"` — `00:15 +1: All tests passed!`. بعده بقيت البيانات: 3 قيود، 12 فترة على id=1، مدين=دائن=314.55، سنة مرئية واحدة، وid=2 soft-deleted. حاوية الاختبار خاصة ولا تتصل بالمالك؛ أزيلت في النهاية بـ`docker rm -f picpos-fy-overlap-qa`، ولم تظهر في قائمة `docker ps` النهائية.

## أوامر التحقق ونتائجها
كل اختبار Flutter شُغّل منفرداً عبر `. D:\qa\luna_tools.ps1; Invoke-FlutterTest <file>`؛ نتائج الملفات:
- `test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` — `00:09 +4: All tests passed!`
- `test/phase2/fiscal_statements_phase2_test.dart` — `00:16 +6: All tests passed!`
- `test/scenarios/sc_j_fiscal_period_test.dart` — `00:12 +5: All tests passed!`
- `test/scenarios/sc_k_trial_balance_test.dart` — `00:22 +10: All tests passed!`
- `test/audit_repro/financial_statements/fs_02_fiscal_close_test.dart -RunSkipped` — `00:16 +6: All tests passed!`; السطر التشخيصي `X3 orphan4121=200.0 bsBalanced=true A=730.0 L=0.0 E=730.0`.
- `test/integration/fiscal_close_no_double_balance_test.dart` — `00:10 +5: All tests passed!`
- `test/integration/fiscal_year_close_e2e_test.dart` — `00:05 +2: All tests passed!`
- `test/integration/pir_fiscal_period_blocking_test.dart` — `00:10 +4: All tests passed!`
- `test/phase2/fiscal_period_reopen_audit_test.dart` — `00:02 +1: All tests passed!`
- `test/unit/spec_136_fiscal_year_null_gid_guard_test.dart` — `00:06 +2: All tests passed!`
- `test/unit/task_6a_fiscal_year_reopen_permission_test.dart` — `00:00 +3: All tests passed!`
- `test/unit/setup_finish_runner_parity_test.dart` — `00:00 +7: All tests passed!`؛ حدّثت القيمة المتوقعة لنهاية اليوم من منتصف الليل إلى `23:59:59.999`، وهو السلوك المعتمد منذ المرحلة 2.
- `test/unit/setup/server_setup_writer_test.dart` — `00:20 +5: All tests passed!`
- `test/unit/setup/server_setup_writer_record_test.dart` — `00:16 +7: All tests passed!`
- `test/structural/file_size_ratchet_test.dart` — `00:00 +1: All tests passed!`
- `test/structural/dark_mode_guard_test.dart` — `00:00 +3: All tests passed!`
- `test/structural/i18n_coverage_test.dart` — `00:10 +1: All tests passed!`
- `test/structural/i18n_runtime_safety_test.dart` — `00:08 +1: All tests passed!`
- `test/phase4/fiscal_overlap/fiscal_overlap_pg_reports_test.dart -PgDsn ...` — `00:15 +1: All tests passed!`.
- `flutter analyze` على ملفات DAO/startup/seeder/adapter/writer/migration والاختبارات الثلاثة — `Analyzing 10 items... No issues found! (ran in 66.5s)`.
- `scripts/fiscal_year_overlap_repair.ps1 -WhatIf` — عرض خطة القراءة/التعطيل دون اتصال أو تعديل.
- `scripts/fiscal_year_overlap_repair.ps1 -Apply -Port 58120` — `disabled id 2: 1 row(s) changed`; ثم إعادة التشغيل `disabled id 2: 0 row(s) changed`; كلاهما تحقّق من `journal_entries 3 -> 3` و`per-account balances unchanged`.

بحث الأسماء: لا يوجد اختبار باسم `period_close` مستقل؛ كل ملفات `fiscal`, `fiscal_year`, و`fiscal_period` المكتشفة في `test/` شُغّلت منفردة أعلاه. لم أرفع `file_size_baseline`، ولم أستخدم `dart format`، ولم أضف مفتاح ترجمة جديداً.

خرج `-WhatIf` الحرفي:
`WhatIf: سوف يفحص FK للسنة 2 على 127.0.0.1:58120/picpos، ثم يعطّل deleted_at فقط إذا لم توجد مراجع؛ لن تتغير القيود أو الأرصدة.`
`للتنفيذ الصريح أعد التشغيل مع -Apply. لم يُجر أي اتصال أو تعديل.`

## الملفات المعدلة وفروقها
- `lib/data/database/daos/accounting_fiscal_dao.dart`: فحص تداخل يومي، رفض عربي يسبق أي تغيير، `ensureFiscalYear` للإنشاء التلقائي، وتصفية soft-deleted من الظهور/الحالية/التغطية. استُخدم `Diff-AgainstBackup phase4c` لمقارنة أسطري فقط مع نسخة المهمة؛ تعديلات المرحلة 2 السابقة محفوظة.
- `lib/data/database/database_startup.dart` و`lib/data/database/database_seeder_postgres.dart`: استخدام `ensureFiscalYear` بدل الإنشاء الصريح.
- `lib/presentation/screens/setup_wizard/setup_persistence_riverpod.dart`: ربط منفذ معالج الإعداد بطريقة ensure.
- `lib/services/setup/server_setup_writer.dart`: إزالة الاكتفاء بمطابقة الاسم والاعتماد على فحص المدى.
- `lib/data/database/migrations/fiscal_year_overlap_repair.dart`: ملف جديد بمعاملة وجرد روابط وsnapshot محاسبي قبل/بعد.
- `scripts/fiscal_year_overlap_repair.ps1`: وضع WhatIf افتراضي وApply محلي فقط، بنطاق منافذ 1–65535؛ `-Apply` على 5432 يتطلب `-ConfirmOwnerDb 'YES-I-APPROVE'` قبل الاتصال. يحفظ نسخة `pg_dump` لكل تشغيل في مجلد مستقل حتى لا يحذف retention نسخاً سابقة.
- `test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` و`fiscal_overlap_pg_reports_test.dart`: اختبارات SQLite/PG.
- `test/phase2/fiscal_statements_phase2_test.dart`: fixture يستخدم سنة 2026 التي أنشأها startup بدلاً من إنشاء سنة متداخلة أخرى؛ الاختبار ظل يحقق الأرباح السابقة غير المقفلة.
- `test/unit/setup_finish_runner_parity_test.dart`: عكس نهاية اليوم المطبقة مسبقاً في `SetupFinishRunner`.
- هذا التقرير.

## تغييرات متزامنة أخرى تُركت كما هي
أظهر `git status --short` النهائي تعديلات أخرى غير داخلة في المهمة وتركتها دون لمس، منها `lib/data/database/daos/sales_actions_dao.dart` و`test/integration/no_invoice_return_persist_test.dart` و`test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart` ووثيقتا `docs/plans/2026-11-02-phase4a-no-invoice-return-cap.md` و`docs/plans/2026-11-02-phase4b-credit-void-after-collection.md`، إضافة إلى الملفات المتزامنة الأخرى الظاهرة في الحالة. لم أجرِ commit أو push أو reset أو stash؛ واستعدت فقط dump الاختبار الخاص بعد الإذن الصريح في هذا التصحيح، ولم ألمس أي قاعدة أو حاوية للمالك.

## تصحيح مراجعة منفذ المالك — 2026-11-02 (قائمة هذا التصحيح: 2/2)
1. ✔ غُيّر `$Port` إلى `[ValidateRange(1, 65535)][int]$Port = 5432`. قيد الاتصال المحلي `127.0.0.1`/`localhost` باقٍ. الوضع الافتراضي يخرج قبل أي اتصال أو تعديل. عند `-Apply -Port 5432` يرفض السكربت قبل `pg_dump` أو الاتصال ما لم يُمرر `-ConfirmOwnerDb 'YES-I-APPROVE'` حرفياً.
2. ✔ بعد الإذن الصريح، أنشأت حاوية `postgres:18-alpine` خاصة على `127.0.0.1:58120`، بكلمة مرور عشوائية للحاوية لم تُكتب في ملف أو تقرير. استعدت dump الاختبار المحدد، ونجح `-Apply` ثم الإعادة idempotently. أزلت الحاوية في النهاية دون حذف الـvolume.

### أوامر وفحوص هذا التصحيح
- `Test-NetConnection 127.0.0.1 -Port 58120 -InformationLevel Quiet` قبل إنشاء الحاوية — `WARNING: TCP connect to (127.0.0.1 : 58120) failed`, `False`.
- فحص الأرشيف `pg_restore --list backups/postgres/picpos_20261101_212419.dump` أكد `Format: CUSTOM`, `Dumped from database version: 18.4`, `TOC Entries: 2304`. محاولة العرض باستخدام `Select-Object -First 18` انتهت `[exit code: 1]`؛ أُعيد الفحص بتجميع المخرجات كاملة: `pg_restore-list exit=0`.
- أُنشئت الحاوية الخاصة من `postgres:18-alpine` على 58120؛ خرج الإنشاء معرّف الحاوية، ثم `private PostgreSQL 18 ready on 127.0.0.1:58120`.
- الأمر: `pg_restore.exe --exit-on-error --no-owner --no-privileges --host 127.0.0.1 --port 58120 --username picpos --dbname picpos backups/postgres/picpos_20261101_212419.dump` — `private test dump restored successfully`.
- قبل التطبيق: `years=2; visible=2`, `journal_entries=3`, `periods=12`, `periods_id1=12`, `accounts=185`, `debits_credits=314.55/314.55`, `balance_fingerprint=8589fcbfaf32c8c367c223f43898f3b9`, وid=2 `deleted_at=NULL`.
- `. D:\qa\luna_tools.ps1; & .\scripts\fiscal_year_overlap_repair.ps1 -WhatIf -Port 5432` — `WhatIf: سوف يفحص FK للسنة 2 على 127.0.0.1:5432/picpos، ثم يعطّل deleted_at فقط إذا لم توجد مراجع؛ لن تتغير القيود أو الأرصدة.` ثم `للتنفيذ الصريح أعد التشغيل مع -Apply. لم يُجر أي اتصال أو تعديل.`
- `. D:\qa\luna_tools.ps1; powershell -NoProfile -File .\scripts\fiscal_year_overlap_repair.ps1 -Apply -Port 5432` بلا تأكيد — فشل فوراً بـ`guard_exit=1` ورسالة `للتنفيذ على قاعدة المالك عبر 5432، يلزم -ConfirmOwnerDb YES-I-APPROVE صراحةً.` لم يُتصل بـ5432؛ الحارس يسبق العثور على psql والنسخة الاحتياطية.
- `-Apply -Port 58120` على النسخة: أنشأ `pg_dump` متحققاً، ثم `years=2; visible=2` قبل و`years=2; visible=1` بعد؛ `journal_entries=3`; `disabled id 2: 1 row(s) changed`; FK/كل أعمدة `fiscal_year_id` أظهرت صفر روابط؛ `verified invariants: journal_entries 3 -> 3, per-account balances unchanged`; الفترات بعده 12.
- فحص لاحق وإعادة `-Apply`: قبل/بعد الإعادة بقيت `visible=1`; `disabled id 2: 0 row(s) changed`; القيود 3، الفترات 12، الحسابات 185، المدين/الدائن `314.55/314.55`، وبصمة أرصدة الحسابات بقيت `8589fcbfaf32c8c367c223f43898f3b9`؛ id=2 بقي soft-deleted.
- فحص PowerShell المطلوب بعد آخر تعديل: `. D:\qa\luna_tools.ps1; powershell -NoProfile -Command "[scriptblock]::Create((Get-Content scripts/fiscal_year_overlap_repair.ps1 -Raw)) | Out-Null"` — بلا مخرجات، `[exit code: 0]`.
- اختبار Flutter: `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` — `00:09 +4: All tests passed!`.
- إزالة الحاوية بأمر `docker rm -f picpos-fy-overlap-qa` أعادت الاسم `picpos-fy-overlap-qa`؛ بعده لم يظهر أي container بهذا الاسم، والمنفذ أعاد `False`. بقيت الـvolume بلا حذف، كما بقيت الحاويتان المحظورتان `picpos-ui-audit` و`ay-scan-postgres-v2` في حالتيهما كما كانتا.

تنبيه حفظ النسخ: أول `-Apply` استخدم مجلد `backups/postgres` المشترك، وسجل `backup_postgres.ps1` أنه حذف النسخة السابقة في اليوم نفسه `picpos_20261102_021743.dump` أثناء retention (`Retention removed ...`). هذا حذف غير مقصود مني؛ لم أحاول استعادتها أو إعادة إنشائها. بعد ملاحظة ذلك عدّلت السكربت ليضع كل نسخة مسبقة في مجلد run خاص `backups/postgres/fiscal_year_overlap/<run-id>`؛ الإعادة اللاحقة سجلت `Retention: kept 1, removed 0` ولم تحذف نسخة أخرى. بقيت النسخة الأصلية المستخدمة والنسخة الجديدة الموثقة.

أمر المالك الدقيق — أوقف التطبيق الذي يتصل بقاعدة PostgreSQL قبل التنفيذ لتفادي الكتابة المتزامنة أثناء النسخ والتحقق:
`.\scripts\fiscal_year_overlap_repair.ps1 -Apply -Port 5432 -ConfirmOwnerDb 'YES-I-APPROVE'`
يتطلب الأمر أن يعيّن المالك `PGPASSWORD` في بيئته محلياً؛ السكربت ينشئ نسخة `pg_dump` ناجحة أولاً، ثم يتحقق من المراجع والقيود والأرصدة قبل/بعد. **لم أشغّل هذا الأمر؛ شغّلت فقط أمر 5432 بلا تأكيد الذي رفضه الحارس قبل الاتصال.**

## إصلاح مسار المستودع — 2026-11-02

### نقطة تفتيش: اختبارات المستودع قبل الإصلاح (TDD)
أُضيف `test/phase4/fiscal_overlap/repository_fiscal_year_test.dart` ليختبر المشاهدة والإنشاء عبر `DriftAccountingRepository` بعد مسار ترحيل فعلي، لا باستدعاء DAO مباشرةً. الأمر `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase4/fiscal_overlap/repository_fiscal_year_test.dart` فشل أولاً كما هو مطلوب:
- `repository watch excludes the repaired duplicate fiscal year`: `Expected ... length of <1>`؛ `Which: has length of <3>` بعد `repairFiscalYearOverlap`.
- `repository rejects overlap with the established Arabic error`: `Expected: throws satisfies function`; `Actual: <Instance of 'Future<int>'>`.
- `repository normalizes end of day and retains the deterministic global id`: `Expected: DateTime:<2035-12-31 23:59:59.999>`؛ `Actual: DateTime:<2035-12-31 00:00:00.000>`.
تحذير مرافق بالاختبار عن `ServicesBinding` غير المهيّأ لا يفسر إخفاقات التأكيد أعلاه.

### إصلاح مسار المستودع — التنفيذ ونتائج الاختبار
قبل: repo ينفّذ select/insert مباشرة، فيتجاوز إخفاء `deleted_at`, حارس التداخل، ورسالة DAO العربية وتوحيد نهاية اليوم. بعد: `watchFiscalYears` يفوّض إلى DAO؛ `createFiscalYear` يفوّض إلى DAO ويمرر globalId حتميًا مشتقًا من الاسم وتواريخ الإدخال كما كان repo يفعل سابقًا؛ DAO يقبل الوسيط الاختياري ويحافظ على اشتقاقه القديم للمستدعين الآخرين. لا تغيّر المسؤولية عن الفترات: شاشة السنة تولّدها بعد نجاح الإنشاء، ومسار المعالج لا يمر عبر repo `createFiscalYear` بل يستعمل `ensureFiscalYear` مباشرةً ثم `generatePeriodsForYear` منفصلاً.

بعد الإصلاح، `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase4/fiscal_overlap/repository_fiscal_year_test.dart` أعاد `00:06 +4: All tests passed!` بعد إعادة المحاولة الناشئة عن تصحيح fixtures ودقة SQLite. اختبر الملف عبر repo التصفية بعد repair، رفض التداخل برسالة DAO نفسها، end-of-day والـglobalId القديم، وإعادة استعمال `ensureFiscalYear` مرتين. Drift SQLite يخزن DateTime كـepoch seconds، لذا القراءة رجعت `23:59:59.000` مع أن DAO يرسل `.999`؛ asserted القراءة بما تسمح به دقة المخزن، واختبار الهوية يقارن باستدعاء `UuidV7.deriveFiscalYearGlobalId` على تاريخ الإدخال القديم.

### نقطة تفتيش: فحص النسخ المباشرة
بحث `grep` عن `_db.select(_db.fiscalYears)`, `_db.select(_db.accountingPeriods)`, `_db.into(_db.fiscalYears)` في repositories/services/presentation وجد: استعلاما اختيار سنة في repo أُضيف إليهما `deletedAt.isNull()`؛ watch/create أُصلحا بالتفويض؛ وواجهتا API لكل السنوات والفترات في `api_get_system.dart` كانتا تعرضان بيانات معطلة، فأصبحتا تستثنيان السنوات المعطلة والفترات المرتبطة بها. لم يظهر في presentation استعلام «كل الفترات»؛ `watchAccountingPeriods(yearId)` يقتصر على سنة يطلبها المستدعي، لذلك لم يتغير. DAO `ensureFiscalYear`/الإنشاء اليدوي وعمليات الإقفال/الفترات لا تُعد قوائم عرض عامة ولا أُعيد تصميمها.

التراجع: استعادة التغييرات المنتقاة في `D:\qa\phase4c-repo_backup` بعد مراجعة الأسطر فقط؛ لا استعادة لملفات/تغييرات متزامنة أخرى.

### نقطة تفتيش نهائية: الأوامر ونتائجها
كل أمر Flutter أدناه شُغّل بملف واحد عبر `. D:\qa\luna_tools.ps1; Invoke-FlutterTest <file>`:
- `test/phase4/fiscal_overlap/repository_fiscal_year_test.dart` — قبل الإصلاح: ثلاث حالات فشل كما سبق؛ بعد الإصلاح: `00:06 +4: All tests passed!`.
- `test/phase4/fiscal_overlap/fiscal_year_overlap_test.dart` — `00:07 +4: All tests passed!`.
- `test/phase4/fiscal_overlap/fiscal_overlap_pg_reports_test.dart` — `00:00 +0 ~1: All tests skipped.`؛ التشخيص: `Skip: Run via melos test:pg (Postgres-backed integration suite)`.
- `test/phase2/fiscal_statements_phase2_test.dart` — `00:10 +6: All tests passed!`.
- `test/scenarios/sc_j_fiscal_period_test.dart` — `00:08 +5: All tests passed!`.
- `test/scenarios/sc_k_trial_balance_test.dart` — `00:17 +10: All tests passed!`.
- `test/audit_repro/financial_statements/fs_02_fiscal_close_test.dart -RunSkipped` — `00:10 +6: All tests passed!`; خرج التشخيص `X3 orphan4121=200.0 bsBalanced=true A=730.0 L=0.0 E=730.0`.
- بقية ملفات fiscal: `test/integration/fiscal_close_no_double_balance_test.dart` — `00:06 +5: All tests passed!`; `test/unit/spec_136_fiscal_year_null_gid_guard_test.dart` — `00:03 +2: All tests passed!`; `test/unit/task_6a_fiscal_year_reopen_permission_test.dart` — `00:00 +3: All tests passed!`; `test/integration/fiscal_year_close_e2e_test.dart` — `00:03 +2: All tests passed!`; `test/integration/pir_fiscal_period_blocking_test.dart` — `00:06 +4: All tests passed!`; `test/phase2/fiscal_period_reopen_audit_test.dart` — `00:02 +1: All tests passed!`.
- اختبارات setup: `test/unit/setup_finish_runner_parity_test.dart` — `00:00 +7: All tests passed!`; `test/unit/spec_b3_setup_wizard_cache_hardening_test.dart` — `00:03 +3: All tests passed!`; `test/unit/setup_vat_rates_allowed_test.dart` — `00:00 +3: All tests passed!`; `test/unit/setup/server_setup_writer_test.dart` — `00:18 +5: All tests passed!`; `test/unit/setup/server_setup_writer_record_test.dart` — `00:15 +7: All tests passed!`. لا يوجد ملف باسم `setup_persistence` في `test/`.
- اختبارات budget: `test/data/analytics/financial_analytics_budget_test.dart` — `00:15 +14: All tests passed!`; `test/domain/analytics/budget_calendar_test.dart` — `00:00 +9: All tests passed!`.
- الهيكلية: `test/structural/file_size_ratchet_test.dart` — `00:00 +1: All tests passed!`; `test/structural/dark_mode_guard_test.dart` — `00:00 +3: All tests passed!`; `test/structural/i18n_coverage_test.dart` — `00:06 +1: All tests passed!`; `test/structural/i18n_runtime_safety_test.dart` — `00:05 +1: All tests passed!`.
- التحليل: الأمر الأول `flutter analyze` على الملفات الأربعة انتهى بـ`2 issues found` (تحذيرا import/متغير في الاختبار)؛ بعد إزالتهما، الأمر نفسه أعاد `Analyzing 4 items... No issues found! (ran in 44.9s)`.

## قائمة تحقق المهمة (4/4)
1. ✔ اختبارات repo فشلت أولاً؛ موثقة أعلاه، ثم نجحت بعد الإصلاح.
2. ✔ تفويض repo إلى DAO مع الحفاظ على الهوية الحتمية والفترات وسلوك ensure الآلي؛ watch مخفي للسنوات المعطلة.
3. ✔ تدقيق المسارات المشابهة؛ أُضيفت تصفية السنوات المعطلة لاستعلامات اختيار السنة وقوائم API، مع تصفية الفترات التابعة في قائمة كل الفترات. لم يُغيّر watch للفترات حسب yearId.
4. ✔ الحزم النهائية المذكورة أعلاه والتحليل بلا مشاكل. استثناء التحقق: PG integration test تخطى التشغيل لغياب إعداد `melos test:pg`؛ لم يُشغّل `flutter test` مباشرةً ولا واجهة PicPos.

## الملفات المعدّلة وفروقها المقتصرة على أسطري المهمة
- `lib/data/database/daos/accounting_fiscal_dao.dart`: معامل `globalId` اختياري وتمريره؛ إن غاب تبقى هوية DAO السابقة.
- `lib/data/repositories/drift_accounting_repository.dart`: watch/create يفوّضان إلى DAO، globalId القديم يُمرر، واستعلاما اختيار السنة يستثنيان deletedAt.
- `lib/services/api/routes/api_get_system.dart`: كل السنوات يستثني المعطّل، وكل الفترات يستبعد أي سنة معطّلة.
- `test/phase4/fiscal_overlap/repository_fiscal_year_test.dart`: ملف جديد (لا نسخة سابقة)، أربع اختبارات repo/ensure.
- هذا التقرير.
تمت مقارنة الملفات الموجودة بـ`Diff-AgainstBackup phase4c-repo`؛ النسخ في `D:\qa\phase4c-repo_backup` ولم تستبدل الملفات. لا تعليق أعمال ضُغط، ولم يتغير `file_size_baseline.txt`.

### تغييرات متزامنة خارج المهمة تُركت كما هي
ظهر `git status --short` النهائي الملفات/المجلدات غير المتعلقة التالية: `Cairo,Noto_Naskh_Arabic/`, `backups/postgres/fiscal_year_overlap/`, `docs/plans/2026-11-02-final-live-verification-2.md`, `docs/plans/audit_ui_shots_2026-11-02_r5/`, `تصميم شاشات فواتير PicPos-handoff/`, `صور لاعادة تصميم الشاشات الموضحه/`, و`طلب مراجعه.txt`. لم أعدّلها أو أستبدلها. لم أنفذ commit أو push أو reset أو checkout أو stash، ولم أشغل واجهة PicPos.

## التغييرات المنطقية المقصودة والتراجع
قبل: DAO يسمح بتداخل السنوات ويمسح `isCurrent` قبل الإدراج؛ الإقلاع/الإعداد يتصرفان كإنشاء جديد. بعد: الإدراج اليدوي يرفض التداخل برسالة عربية قبل تغيير السنة الحالية؛ المسارات الآلية تستخدم `ensureFiscalYear` وتعيد المعرّف القائم؛ السنوات soft-deleted مستبعدة من العرض والتغطية والاختيار. الإصلاح التاريخي لا يحذف صفوفاً أو قيوداً، ويستخدم `deleted_at` فقط بعد التحقق من جميع مراجع FK وأعمدة `fiscal_year_id`، ويتحقق من عدد القيود وأرصدة كل حساب قبل/بعد. التراجع الانتقائي: استعادة ملفات الكود المتأثرة من نسخ `Backup-ForTask phase4c` مع مراجعة الأسطر، أما قاعدة البيانات فيكون التراجع باستعادة dump المسبق على قاعدة اختبار/صيانة؛ لا تطبق التراجع على قاعدة المالك آلياً.

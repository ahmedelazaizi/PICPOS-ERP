# إثبات ترحيل مفتاح القاعدة على محرّك SQLCipher الحقيقي (E-01 — المرحلة ب)

التاريخ: 2026-10-11 · الجهاز: Windows (تطوير) · Flutter 3.41.2 · drift 2.32.1 · sqlite3 3.3.1 · sqlcipher_flutter_libs 0.6.8

كل ما سبق في المرحلة ب اختُبر بمحاكٍ (`FakeSqlCipherEngine`) لأن `flutter test` يحمّل `sqlite3.dll` عادية.
هذا المستند يسجّل أول تشغيل **على SQLCipher الفعلي**، وما كشفه.

## 1) كيف حُصل على SQLCipher DLL

- لم يُعَد البناء: `build\windows\x64\plugins\sqlcipher_flutter_libs\Release\sqlite3.dll` موجودة من بناء سابق
  (`flutter build windows --release …` أي نفس مخرجات `build_picpos.bat` الخطوة 4)، حجمها **5,427,200 بايت**،
  SHA-256 `3313217BDA3758907E8F1B275B07A94627241DFC540226FD691996C0B205050E`،
  وتحوي السلسلة `sqlcipher` (نفس فحص `build_picpos.bat` الخطوة 5). هي نفسها المنسوخة إلى `runner\Release`.
- الـDLL العادية التي يشحنها hook الحزمة `sqlite3` حجمها 1,665,536 بايت (لا `sqlcipher`).
- للحصول على DLL إن لم تكن موجودة: `flutter build windows --release --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified`
  (يتطلب Visual Studio C++). أو اضبط `PICPOS_SQLCIPHER_DLL` على أيّ SQLCipher DLL موثوقة.
- إثبات أنها SQLCipher فعلًا: الاختبارات تتحقق من `PRAGMA cipher_version` غير فارغ عبر `sqlCipherAvailable()`،
  وسجلّ المحرّك يطبع `sqlcipher_page_cipher: hmac check failed` عند المفتاح الخطأ (لا يصدر عن sqlite3 العادية).
  *(نص `cipher_version` نفسه لم يُسجَّل.)*

## 2) كيف شُغّل الاختبار على المحرّك الحقيقي

`sqlite3` 3.x لا تملك `DynamicLibrary.overrideFor` ولا متغيّر بيئة؛ تُحمَّل الـDLL بمسارٍ مطلق من
`.dart_tool\hooks_runner\sqlite3\*\output.json` ⇒ `…\shared\sqlite3\build\download-*\sqlite3.dll`.
لذا يبدّل السكربت `tool/run_sqlcipher_tests.ps1` تلك الملفات (داخل `.dart_tool` المتجاهَل) مؤقتًا بـSQLCipher DLL، ويشغّل
`flutter test` مع `PICPOS_REQUIRE_SQLCIPHER=1` (فيصبح التخطي فشلًا)، ثم يعيد الأصل في `finally`
(وعند التشغيل التالي يستعيد أي `*.plain-bak` تركها تشغيلٌ مقتول).

```powershell
# كل اختبارات db_key + المحرك الحقيقي (من جذر المشروع؛ لا يعمل مع أمر flutter آخر بالتوازي)
powershell -NoProfile -ExecutionPolicy Bypass -File tool\run_sqlcipher_tests.ps1
# اختبار محدد
powershell -File tool\run_sqlcipher_tests.ps1 test/integration/db_key_real_engine_test.dart --plain-name "WAL"
# قياس الزمن على قاعدة كبيرة
$env:PICPOS_BIG_DB_MB=200; powershell -File tool\run_sqlcipher_tests.ps1 test/integration/db_key_real_engine_test.dart --plain-name MB
```

ملاحظة: `*.ps1` في `.gitignore`؛ السكربت يحتاج `git add -f` (كحال `tool/run_e2e.ps1`).
في الوضع العادي (`flutter test` بلا السكربت) تتخطى الاختبارات الحقيقية نفسها برسالة واضحة ولا تفشل.

الملفات: `test/helpers/sqlcipher_real.dart` (عُدّة)، `test/integration/db_key_real_engine_test.dart` (جديد)،
`test/integration/db_key_rekey_engine_test.dart` (قائم؛ أُغلق فيه مقبض ملف كان يمنع حذف المجلد المؤقت).
كل التجارب في مجلدات `%TEMP%\picpos_real_engine_*` وتُحذف؛ لم يُلمس `Documents` ولا أي `*.db` للمستخدم
(`AppDatabase.withExecutor` فقط، لا `AppDatabase()` ولا `openConnection()`).

## 3) النتائج لكل سؤال

| | السؤال | النتيجة |
|---|---|---|
| أ | هل `sqlcipher_export` ينسخ `user_version`؟ | **لا** (الناتج `user_version = 0`، مثبت باختبار). `exportTo` ينسخه يدويًا بـ`PRAGMA v2.user_version = n` — يعمل (195 ⇒ 195). **لكن** كُشف خلل أخطر (القسم 4-1). |
| ب | صيغة المفتاح | `PRAGMA key = "x'<64hex>'"` و`ATTACH … KEY "x'<64hex>'"` تعملان. العبارة النصية بالأحرف نفسها لا تفتح ملفًا مشفرًا بالخام (المفتاحان مختلفان فعلًا). |
| ج | التشفير الفعلي | الناتج لا يبدأ بـ`SQLite format 3`؛ لا يفتح بالمفتاح القديم ولا بلا مفتاح؛ الأصل لم يُمَس. |
| د | WAL | انظر 3-د أدناه. |
| هـ | دورة `migrate()` كاملة | نجحت على (1) قاعدة بسيطة، و(2) **`AppDatabase` الحقيقي** (schema 195، >50 جدولًا، بذرة الإنتاج): عدّادات كل الجداول و`user_version` و`quick_check` مطابقة بعد الترحيل، drift يفتحها بالمفتاح الجديد ويقرأ الصفوف، والمفتاح القديم لا يفتحها، و`migrate()` الثانية ⇒ `alreadyMigrated`. |
| و | الانقطاع | موت العملية عند كل من الخطوات الثماني (M1…M7) ثم `recoverInterrupted` من «عملية جديدة»: في الحالات الثماني بقيت قاعدة سليمة تُفتح بمفتاحٍ ما بنفس الجداول و`user_version`، لا `.v2-new` متبقٍّ، وإعادة `migrate()` اكتملت والقديم لا يفتحها بعدها. |
| ز | الزمن | انظر 3-ز. |
| ح | ويندوز | انظر 3-ح. |

### 3-د) WAL
- **التصميم سليم لـWAL؛ لا خلل جوهري في `sqlcipher_export`.** صورة «انهيار» (نسخ db+‎-wal+‎-shm والمقبض حي، بـ50 صفًا موجودة في WAL فقط):
  فتح SQLCipher للصورة يستعيد WAL تلقائيًا، فدخلت الصفوف الـ50 في التصدير (52 صفًا).
- **الـcheckpoint ضروري للنسخة الاحتياطية لا للتصدير**: M3 تنسخ الملف الرئيس وحده (`db.copy`)؛ دون checkpoint تُفقد صفوف WAL
  (أثبتناه: نسخ الملف الرئيس وحده أعطى أقل من 52). بعد `wal_checkpoint(TRUNCATE)` احتوت النسخة الاحتياطية 52 صفًا و`user_version` 9.
- بعد التبديل الذرّي لا يبقى `-wal` ولا `-shm` قديمان (حُذفا بالتبديل وبإغلاق آخر مقبض في M7).
- القاعدة المرحَّلة تعمل بـ`journal_mode=WAL` كالإنتاج: فتحها بالمفتاح الجديد ثم `PRAGMA journal_mode=WAL` يعطي `wal` والكتابة/القراءة تعمل (وضع الملف قبل ذلك لم يُقَس).

### 3-ز) الزمن (قاعدة اصطناعية: جدول 201,649 صفًا × ~1KB blob + فهرس، **268.6 MB** على القرص — أكبر من 200MB المطلوبة بسبب الفهرس)
| الخطوة | ms |
|---|---|
| M1 مفتاح+keyinfo | 352 |
| M2 checkpoint | 216 |
| M3 نسخة احتياطية (نسخ ملف) | 288 |
| M4 تصدير `sqlcipher_export` | 5,614 |
| M5 تحقق (فتح بمقبضين + quick_check + عدّادات) | 8,466 |
| M6a/M6 تبديل | 2 + 16 |
| M7 فحص نهائي + التزام | 4,009 |
| **المجموع** | **18,965 (~19 ث)** |

إنشاء العيّنة نفسها 15 ث (خارج القياس). القرص: الملف 268.1 MB بعد الترحيل + `.pre-v2` 268.6 MB + نسخة احتياطية ⇒ ~3× الحجم أثناء الترحيل (فحص المساحة الحرة في الكود يطلب 2.2×).
جهاز واحد (SSD)؛ لا تعمّم على أقراص بطيئة.

### 3-ح) ويندوز الفعلي
- **القفل الحصري** (`FileLock.exclusive`): مقبض آخر يحمله ⇒ `busy` فورًا (لا تعليق، بحدّ 20 ث في الاختبار)، لم يبدأ أي شيء، وبعد تحريره ينجح الترحيل.
- **مقبض مفتوح على القاعدة أثناء التبديل** (مثلًا تطبيق يشغّلها): `rename` فشل بـ`PathAccessException` ⇒ `failed`، الأصل سليم ويفتح بالقديم، `.v2-new` يُنظَّف بالتعافي. (في الإنتاج الترحيل يسبق فتح القاعدة، فهذا حارس إضافي.)
- **M8 والتنظيف**: عملية جديدة تحذف `.pre-v2` فعلًا على ويندوز (لا مقابض)، `state=done`؛ نسخة `key-migration/*.pre-v2-*.db` الحديثة تبقى، والتي أُعتِّقت 40 يومًا تُحذف مع `keyinfo` الجانبي. ملف `.key-migration.lock` (0 بايت) يبقى بجانب القاعدة بعد الترحيل — أثر غير ضار.

## 4) الأخطاء المكتشفة

1. **(جوهري، أُصلح) `NativeSqlCipherEngine` كان يكتب `user_version = 1` فوق القاعدة عند كل `canOpen`/`inspect`/`checkpointTruncate`/`exportTo`.**
   السبب: `_NoopUser.schemaVersion` ثابت = 1، و`NativeDatabase` يستعمل `DynamicVersionDelegate` فينفّذ drift بعد `beforeOpen` الأمر `PRAGMA user_version = <schemaVersion>` متى اختلف عن المخزَّن (التعليق القديم كان يفترض `OnOpenVersionDelegate` وهذا خطأ).
   الأثر لو وُصل بالإقلاع: تخريب `user_version` للأصل والنسخ (195 ⇒ 1)، فيُعيد drift تشغيل `onUpgrade` من 1، وتخدع المقارنة (`a.matches(b)`) لأن الطرفين يصبحان 1. المحاكي لا يستطيع كشفه.
   الإصلاح: `_NoopUser.schemaVersion` يرجع قيمة تُقرأ في `setup` من القاعدة نفسها قبل أن يسأل drift ⇒ المكتوب هو المقروء. انحدار: `user_version` يبقى 195 بعد كل العمليات الأربع، و0 يبقى 0.
2. اختبار قائم (`db_key_rekey_engine_test.dart`) كان يترك `RandomAccessFile` مفتوحًا فيفشل حذف المجلد المؤقت على ويندوز — أُغلق.
3. أثناء العمل: تشغيلٌ خاطئ مبكر للسكربت (وسيط موضعي فُسّر كمسار DLL) بدّل ملفات الـhook بملف نصي؛ استُعيدت فورًا من `.plain-bak` وتحقق الحجم 1,665,536 للثلاثة، وشُدّد السكربت (لا معامل `-Dll`، فحص ترويسة MZ وحجم >3MB).

## 5) ما بقي مفتوحًا / غير مثبَت

- **الترحيل غير موصول بالإقلاع** (كما في التصميم)؛ لم يُجرَّب على قاعدة المستخدم الحقيقية ولا على إقلاع التطبيق فعليًا.
- **`AppDatabase.close()` لا يحرّر مقبض الملف** في الاختبار (قاعدة أُنشئت على ملف وأُغلقت؛ `rename` ظل يفشل بعد 3 ث). السبب غير محدد (مهامّ `DatabaseStartup` المؤجلة أو statements غير مُنهاة). لا يؤثر على الترحيل المقصود (قبل فتح القاعدة) لكنه يعني أن أي كود يفتح القاعدة قبل `migrate` سيجعل التبديل يفشل بأمان. حوّلنا الاختبار لإنشاء القاعدة في الذاكرة ثم تصديرها لتفادي المشكلة. يحتاج تحقيقًا منفصلًا.
- قواعد أُنشئت بإعدادات SQLCipher 3 / `cipher_compatibility` مختلفة، أو بـ`cipher_page_size` غير الافتراضي: لم تُختبر (قاعدة الاختبار أُنشئت بإعدادات SQLCipher 4 الافتراضية؛ وجودها عند العملاء غير معروف).
- انقطاع تيار/قتل عملية **حقيقي** (الاختبار يحاكيه بإلقاء استثناء في `stepHook` داخل نفس العملية)، وعمليتان حقيقيتان للقفل (اختُبر بمقبضين في عملية واحدة؛ `LockFileEx` يعامل المقبضين كمتنازعَين).
- التوقيت على قرص بطيء أو مع مضاد فيروسات يفحص `rename`/الحذف، وقاعدة بـ`-wal` ضخم أثناء الترحيل.
- فحص المساحة الحرة الإنتاجي (`freeSpaceBytes`) لم يُجرَّب على ويندوز الحقيقي (يُحقن في الاختبارات فقط).
- `cipher_version` النصية لم تُسجَّل.

## 6) نتائج التحقق (2026-10-11)

- `flutter analyze lib test/integration test/unit`: 0 أخطاء، 7 ملاحظات info قائمة مسبقًا (ليس منها شيء في الملفات المعدّلة هنا).
- اختبارات db_key (4 وحدة + محرّك قديم + محرّك حقيقي) في الوضع العادي: 84 نجح، 23 تخطّى (الحقيقية) ، 0 فشل.
- الوضع الحقيقي (`tool/run_sqlcipher_tests.ps1`): 106 نجح، 1 تخطّى (اختبار 200MB الاختياري)، 0 فشل. مع `PICPOS_BIG_DB_MB=200` نجح.
- `flutter test test/structural`: 696 نجح، 0 فشل.

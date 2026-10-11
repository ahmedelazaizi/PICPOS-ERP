# تصميم ترحيل مفتاح قاعدة البيانات المحلية وفصل أسرار الـAPI (E-01 / E-02)

> وثيقة تصميم فقط — لا تغيير في الكود. المرجع: [part3-secrets-supplychain.md](<part3-secrets-supplychain.md>) (E-01، E-02، E-05) و[part2b-api-auth.md](<part2b-api-auth.md>).
> الحالة: مسودة تصميم مكتملة — بانتظار قرارات المالك (§8.4). لم يُشغَّل أي اختبار أو بناء.

**الخلاصة:**
1. افصل أسرار الخادم أولًا (المرحلة A، §3): سرّان عشوائيان مستقلان لـHMAC الجلسات ورموز الطاولات. سر توكنات الأجهزة المقترنة مستقل أصلًا (`ural_lan_install_secret_v1`). أما الـbearer القديم فيُحسب من `LegacyDeviceSeed` داخل نافذة الانتقال فقط. الجلسات القائمة تُبطَل عمدًا ويعيد العملاء إصدارها تلقائيًا.
2. مفتاح SQLCipher عشوائي 256-بت في `flutter_secure_storage`، بفتحتين وسجل `keyinfo` غير سري بجانب القاعدة (§1). «أول تشغيل» يُستنتج من غياب ملف القاعدة لا من غياب المفتاح، لأن حزمة ويندوز تُرجع `null` عند أي عطل (§0.7).
3. الترحيل بـ`sqlcipher_export` إلى ملف جديد ثم التحقق ثم التبديل، مع تأكيد في الإقلاع التالي (§2). ومصدر الحقيقة عند أي انقطاع هو «أي مفتاح يفتح أي ملف».
4. يبقى المفتاح المشتق مرشّح فتح للقراءة فقط، فتُستعاد النسخ القديمة على نفس الجهاز ويُعاد تشفيرها تلقائيًا (§4).
5. رمز استرداد وتصدير بكلمة مرور شرطٌ لتفعيل الترحيل، لأن المفتاح صار مرتبطًا بحساب ويندوز واسم المنتج (§5).

## 0. الحقائق الحالية في الكود (مؤكدة بالقراءة)

### 0.1 اشتقاق المفتاح — [security_service.dart:433-497](<../../lib/services/security_service.dart#L433-L497>)
- `SecurityService.getDatabaseEncryptionKey()`:
  - ويندوز: `uniqueId = windowsInfo.deviceId` (`device_info_plus`)؛ أندرويد `androidInfo.id`؛ iOS `identifierForVendor`.
  - إن وُجد `uniqueId`: المفتاح = `sha256(utf8('$uniqueId:UralCash_Security_Pepper_v2')).toString()` ⇒ 64 حرف hex صغيرة.
  - وإلا (أو عند أي استثناء من `device_info_plus`): `_getOrCreateSecureFallbackKey()` يقرأ/يولّد مفتاحًا عشوائيًا في `flutter_secure_storage` بالاسم `ural_db_fallback_enc_key` (`Random.secure()` 32 بايت ثم `sha256` ⇒ hex)، ويرمي `DatabaseKeyUnavailableException` إن فشل التخزين الآمن.
- **عيب موجود الآن بمعزل عن E-01:** المسار الاحتياطي يُفعَّل عند **أي** استثناء عابر من `device_info_plus`، فيولّد مفتاحًا عشوائيًا جديدًا لقاعدة قائمة مشفّرة بالمفتاح المشتق ⇒ فشل فتح (`file is not a database`) بدل خطأ واضح. والعكس: جهاز بدأ بالمفتاح الاحتياطي ثم صار `deviceId` متاحًا يُقرأ له المفتاح المشتق الخاطئ. أي أن «أي المفتاحين يخص هذا الملف» غير مسجَّل في أي مكان. التصميم أدناه يعالج هذا بتسجيل صريح لنوع المفتاح.

### 0.2 الفتح — [connection_io.dart:31-117](<../../lib/data/database/connection_io.dart#L31-L117>)
- `openConnection()` → `LazyDatabase`: `_applyPendingRestore(file.path)` ثم `getDatabaseEncryptionKey()` ثم التحقق من الشكل `^[0-9a-f]{64}$` ثم `NativeDatabase.createInBackground(file, setup: …)` حيث `PRAGMA key = '<hex>'` (صيغة passphrase نصية — SQLCipher يشتق المفتاح الفعلي عبر PBKDF2 من نص الـhex، وليس مفتاحًا خامًا `x'..'`)، ثم فحص `PRAGMA cipher_version` غير الفارغ، ثم `foreign_keys/WAL/synchronous/...`.
- اسم الملف: `getDatabaseFileName()` = `'${Brand.dbPrefix}_${flavor.code}.db'` في `getApplicationDocumentsDirectory()`.
- `openTestConnection()` = `NativeDatabase.memory` **بلا مفتاح** ⇒ اختبارات الـDAO لا تمر بالمفتاح أصلًا.

### 0.3 النسخ والاستعادة — [connection_io.dart:360-672](<../../lib/data/database/connection_io.dart#L360-L672>)
- `createDatabaseBackup` = `File.copy` لملف القاعدة المشفّر إلى `Documents/backups/<db>_backup_<ts>.db` (آخر 7). النسخة مشفّرة **بنفس مفتاح القاعدة لحظة النسخ**.
- `restoreDatabaseBackup` ينسخ إلى `<db>.restore-pending`، و`_applyPendingRestore` يطبّقه قبل الفتح بلا أي فحص للمفتاح/السلامة.
- `exportBackupToPath` ينسخ أحدث نسخة إلى مجلد خارجي.
- مسار الويب [connection_web.dart](<../../lib/data/database/connection_web.dart>): `WasmDatabase` بلا مفتاح، وكل دوال النسخ stubs ترجع `null/false`. لا يستدعي `SecurityService` إطلاقًا.

### 0.4 مستهلكو المفتاح (بحث `getDatabaseEncryptionKey` في `lib/`)
1. [connection_io.dart:42](<../../lib/data/database/connection_io.dart#L42>) — `PRAGMA key`.
2. [network_service.dart:763-774](<../../lib/services/network_service.dart#L763-L774>) داخل `NetworkService.startServer` — `machineSeed` يغذّي ثلاثة أسرار:
   - `ApiAuthMiddleware.generateToken(machineSeed)` = `sha256('$seed:UralCash-API-v1')[:32]` → `_activeToken` (الـbearer **القديم المشترك**) — [api_auth_middleware.dart:140-150](<../../lib/services/api/api_auth_middleware.dart#L140-L150>).
   - `ApiSessionToken.deriveKey(machineSeed)` = `sha256('$seed:UralCash-Session-v1')` → مفتاح HMAC لرموز `X-Session-Token` (TTL 30 يومًا) ولرموز الويب `mintWeb` (`aud:'web'`، 12 ساعة) — [api_session_token.dart:44-46](<../../lib/services/api/api_session_token.dart#L44-L46>).
   - `TableBillToken.deriveKey(machineSeed)` = `sha256('$seed:PicPos-TableBill-v1')` → توقيع رموز QR **المطبوعة على الطاولات بلا انتهاء** — [table_bill_token.dart:81-92](<../../lib/services/api/table_bill_token.dart#L81-L92>).
3. لا مستهلك آخر في `lib/`. خارج `lib/`: [patches-for-uralcash/engine-fixes.diff](<../../patches-for-uralcash/engine-fixes.diff>) (رقعة للمنتج الشقيق — خارج النطاق لكن يجب أن تُحدَّث معه إن طُبّق التصميم على UralCash).

### 0.5 أسرار مستقلة **موجودة بالفعل** (نمط يُبنى عليه)
- `LanPairingService` ([lan_pairing_service.dart:14,61-79,150-155](<../../lib/services/api/lan_pairing_service.dart#L61-L79>)): سر تثبيت عشوائي 32 بايت `ural_lan_install_secret_v1` في التخزين الآمن عبر `SecureStorageService`؛ توكن كل جهاز = `HMAC(installSecret, deviceId)`؛ إبطال لكل جهاز (`revoke` → `lan_paired_devices.revoked=1`)؛ و**نافذة انتقال** للتوكن القديم المشترك (`lan_legacy_transition_started_at/_days/_ended`، افتراض 30 يومًا، `legacyAllowed()`). فشل التخزين ⇒ `DatabaseKeyUnavailableException`.
- `InvoiceIntegrityService` ([invoice_integrity_service.dart:14-47](<../../lib/services/invoice_integrity_service.dart#L14-L47>)): `ural_invoice_integrity_secret_v2` عشوائي في التخزين الآمن، يُهيَّأ في [main.dart:267-282](<../../lib/main.dart#L267-L282>) والـ`DatabaseKeyUnavailableException` يقود إلى `FatalSetupErrorApp`.
- إذن **توكن LAN لكل جهاز مفصول فعلًا**؛ ما بقي مربوطًا بمفتاح القاعدة هو: الـbearer القديم المشترك (خلال نافذة الانتقال فقط)، ومفتاح HMAC للجلسات (جهاز + ويب)، ومفتاح رموز الطاولات.
- ملاحظة مهمة في [api_auth_middleware.dart:254-256](<../../lib/services/api/api_auth_middleware.dart#L254-L256>): `if (_activeToken == null) return 403` — أي أن قبول **أي** طلب `/api/*` (حتى من جهاز مقترن حديثًا) مشروط حاليًا بوجود الـbearer القديم المشتق. وكذلك `verifyCredential` ([:154-165](<../../lib/services/api/api_auth_middleware.dart#L154-L165>)). فصل الجذور يستلزم فك هذا الشرط.
- خطر كامن: `SecureStorageService.clearAll()` ([secure_storage_service.dart:27-29](<../../lib/services/secure_storage_service.dart#L27-L29>)) يستدعي `deleteAll()` — غير مستدعى حاليًا في `lib/` (بحث `clearAll\(\)`)، لكن بعد التصميم سيمحو مفتاح القاعدة ⇒ فقدان بيانات. يجب حذفه أو استثناء مفاتيح القاعدة منه.

### 0.6 أوضاع التشغيل — [db_connection_strategy.dart:88-154](<../../lib/data/database/db_connection_strategy.dart#L88-L154>)
- العميل والـsqlite والـ«PG غير مُجهَّز» والـ«PG غير متاح (offline fallback)» كلها تفتح **نفس ملف SQLite المحلي** عبر `AppDatabase()` ⇒ نفس `openConnection()` ⇒ نفس المفتاح.
- خادم PG متصل: لا يُفتح ملف SQLite، لكن `startServer` ما زال يستدعي `getDatabaseEncryptionKey()` لاشتقاق أسرار الـAPI ⇒ مثال صريح على أن «مفتاح القاعدة» هنا مجرد بذرة جهاز لا علاقة لها بالقاعدة الفعلية.
- `AppDatabase()` singleton ([database.dart:974-985](<../../lib/data/database/database.dart#L974-L985>)) ⇒ `openConnection()` مرة واحدة لكل عملية؛ `AppDatabase.forTesting()` ⇒ `openTestConnection()` في الذاكرة بلا مفتاح.
- تطبيق الجذر لا يحوي مجلد `android/` ولا `ios/` (المجلدات العليا: `windows/`, `web/`, ...) ⇒ فروع `Platform.isAndroid/isIOS` في `getDatabaseEncryptionKey` ميتة عمليًا لهذا التطبيق.

### 0.7 كيف يخزّن `flutter_secure_storage` على ويندوز فعلًا (من مصدر الحزمة المحلولة)
`pubspec.lock` يحلّ `flutter_secure_storage 9.2.4` و`flutter_secure_storage_windows 3.1.2`. قرأتُ `windows/flutter_secure_storage_windows_plugin.cpp` في `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_secure_storage_windows-3.1.2`:
- **ليس DPAPI مباشرة**: كل قيمة تُشفَّر AES-GCM بمفتاح 128-بت عشوائي (`GetEncryptionKey`, سطر 314-359) محفوظ كـ Generic Credential في **Windows Credential Manager** (`CredWriteW`, `CRED_PERSIST_LOCAL_MACHINE`) باسم `key_<prefix>` — وCredential Manager نفسه محمي بـDPAPI لحساب المستخدم. الحماية الفعلية إذن = حساب مستخدم ويندوز.
- النص المشفّر يُكتب في ملف `%APPDATA%\<CompanyName>\<ProductName>\<prefix><key>.secure` (سطر 216-259 و549) حيث `CompanyName/ProductName` من مورد الإصدار في الـexe — [Runner.rc:109-115](<../../windows/runner/Runner.rc#L109-L115>)؛ PicPos: `BRAND_COMPANY_NAME=PicPos`, `BRAND_PRODUCT_NAME=PicPos` ([build_picpos.bat:27-33](<../../build_picpos.bat#L27-L33>))؛ الافتراضي بلا متغيرات بيئة (مثل `flutter run`): `Monexia` / `UralCash ERP` ([windows/CMakeLists.txt:24-36](<../../windows/CMakeLists.txt#L24-L36>)).
- **`read` يُرجع `null` عند أي فشل** (سطر 583-628 وما بعده): ملف مفقود، ملف مبتور، فشل فك GCM، أو غياب مفتاح Credential Manager — و`GetEncryptionKey` عند غياب الاعتماد **يولّد مفتاح AES جديدًا ويكتبه** فتصبح كل ملفات `.secure` القديمة غير قابلة للفك نهائيًا وتُقرأ `null`.
- `Write` يفتح الملف بـ`std::ios::trunc` ثم يكتب (سطر 549-557) ⇒ **ليس ذريًا**؛ انقطاع الكهرباء أثناء الكتابة يترك ملفًا مبتورًا ⇒ `null`.
- **النتائج التصميمية الحاسمة:**
  1. `null` من التخزين الآمن **لا يعني** «أول تشغيل». أي منطق «إن لم يوجد فولّد» (كما في `_getOrCreateSecureFallbackKey` اليوم) يدمّر الوصول لقاعدة قائمة. يجب أن يُستنتج «أول تشغيل» من غياب ملف القاعدة، لا من غياب المفتاح.
  2. المفتاح مرتبط بـ(مستخدم ويندوز × CompanyName × ProductName). تشغيل التطبيق بحساب ويندوز آخر، أو بناء تطوير بلا `BRAND_*`، أو تغيير اسم المنتج/الشركة في إصدار لاحق ⇒ المفتاح «يختفي». اليوم المفتاح المشتق لا يتأثر بأي من ذلك (يعتمد على الجهاز فقط) ⇒ **هذه انحدارات تشغيلية جديدة** يجب أن يغطيها التصميم (مفتاح استرداد + نسخة ثانية من المفتاح).
  3. يجب كتابة المفتاح ثم **إعادة قراءته ومقارنته** قبل الاعتماد عليه، والاحتفاظ بنسختين (فتحتين) منه.

---

## 1. المفتاح الجديد: التوليد والتخزين والقراءة ومعالجة الفشل

### 1.1 الشكل
- 32 بايت من `Random.secure()` تُرمَّز hex صغيرة (64 حرفًا) — **بلا** `sha256` فوقها (التجزئة فوق عشوائي لا تضيف شيئًا، كما في `_getOrCreateSecureFallbackKey` اليوم).
- يُمرَّر لـSQLCipher بصيغة **المفتاح الخام** `PRAGMA key = "x'<64hex>'";` لا كعبارة مرور: المفتاح عشوائي كامل فلا حاجة لـPBKDF2 (يوفّر زمن الفتح)، وصيغة `x'..'` تُبقي حارس الشكل في [connection_io.dart:52-57](<../../lib/data/database/connection_io.dart#L52-L57>) صالحًا (`^[0-9a-f]{64}$` ثم بناء النص). المفتاح القديم يبقى بصيغة العبارة (`PRAGMA key = '<hex>'`) — لذا كل مفتاح يحمل **نوعه** (`DbKeyKind.legacyPassphrase` / `DbKeyKind.rawV2`) ولا يُمرَّر نص مفتاح عارٍ بين الدوال.
- **قرار مالك (ق-1):** صيغة خام أم عبارة مرور للمفتاح الجديد. التوصية: خام. (الصيغة لا تؤثر على الأمان هنا لأن المفتاح عشوائي 256-بت.)

### 1.2 مكان التخزين — فتحتان + سجل حالة غير سري
مفتاح التخزين مرتبط **باسم ملف القاعدة** لأن لكل flavor/علامة ملفها (`getDatabaseFileName()`):

| العنصر | المكان | سري؟ | الغرض |
|---|---|---|---|
| `db_key_v2::<dbFileName>` | `flutter_secure_storage` (Credential Manager + `.secure`) | نعم | المفتاح الأساسي |
| `db_key_v2_shadow::<dbFileName>` | `flutter_secure_storage` (ملف `.secure` مستقل) | نعم | نسخة ثانية ضد بتر الكتابة غير الذرية (§0.7) |
| `<db>.keyinfo.json` بجانب القاعدة في `Documents` | ملف عادي | لا | `{version:1, kind:"rawV2", fingerprint:"<16 hex>", createdAt, migratedFrom:"legacyDerived"|"legacyFallback"|null, recoveryEnvelope:{...}}` |

- `fingerprint` = أول 8 بايت من `HMAC-SHA256(key, "picpos-dbkey-fp-v1")` — يكفي للتمييز بين المفاتيح دون كشف شيء.
- **لماذا ملف `keyinfo` بجانب القاعدة لا في SharedPreferences ولا في جدول `settings`:** جدول `settings` داخل القاعدة المشفّرة (لا يُقرأ قبل الفتح)، وقد يُزامَن؛ وSharedPreferences لا يرافق الملف عند نقله/استعادته. الملف المجاور يُعبّر عن «هذا الملف مشفّر بمفتاح بصمته X».
- `recoveryEnvelope` (§5): المفتاح مغلَّف بمفتاح مشتق من «رمز الاسترداد» — اختياري حسب قرار المالك.

### 1.3 الوحدة الجديدة (مقترحة) — `lib/data/database/db_key_manager.dart`
فصلها عن `SecurityService` (الذي صار خدمة ستاتيكية متعددة الأغراض) يسمح بالحقن في الاختبارات:

```dart
abstract class SecretStore { Future<String?> read(String k); Future<void> write(String k, String v); Future<void> delete(String k); }
// تنفيذ إنتاج يلفّ FlutterSecureStorage؛ وMemorySecretStore للاختبارات — نفس شكل
// packages/picpos_device/lib/src/store/db_key.dart (لا استيراد بين الحزمتين؛ نسخ النمط فقط).

abstract class CipherOps {            // كل ما يلمس محرك SQLCipher — قابل للتزييف في الاختبار
  Future<bool> canOpen(File db, DbKey key);            // PRAGMA key + SELECT count(*) FROM sqlite_master
  Future<void> exportTo(File src, DbKey srcKey, File dst, DbKey dstKey); // ATTACH … KEY + sqlcipher_export
  Future<bool> verify(File db, DbKey key);             // canOpen + PRAGMA cipher_integrity_check/quick_check + قراءة جدول
}

class DbKeyManager {
  Future<DbKey> resolveForOpen(File dbFile);   // يُستدعى من openConnection بدل getDatabaseEncryptionKey
}
```
- تنفيذ `CipherOps` في الإنتاج يستعمل `NativeDatabase(file, setup: (raw) {...})` من `drift/native.dart` (المستورد أصلًا في `connection_io.dart`) ويغلقه فورًا — **بلا** إضافة اعتماد مباشر على `sqlite3` (ممنوع بتعليق [pubspec.yaml:67-77](<../../pubspec.yaml#L67-L77>)). كل عملية فحص تتحقق أيضًا من `PRAGMA cipher_version` غير الفارغ (نفس حارس [connection_io.dart:83-96](<../../lib/data/database/connection_io.dart#L83-L96>)) — وإلا فإن `canOpen` على sqlite3 عادي سيعيد `true` لأي مفتاح.

### 1.4 خوارزمية `resolveForOpen(dbFile)` (القراءة)
1. `_applyPendingRestore` يبقى أولًا كما هو اليوم (لكن انظر §4.3 لتقويته).
2. **إن لم يوجد ملف القاعدة** (ولا `-wal`): تثبيت جديد ⇒ ولّد مفتاحًا، اكتبه في الفتحتين، **أعد قراءتهما وقارن**، اكتب `keyinfo.json`، أعد المفتاح. إن فشلت الكتابة/المقارنة ⇒ `DatabaseKeyUnavailableException` (المسار القائم إلى `FatalSetupErrorApp` في [main.dart:272-281](<../../lib/main.dart#L272-L281>) و[:507-517](<../../lib/main.dart#L507-L517>)) — **لا قاعدة بلا مفتاح ولا قاعدة بمفتاح غير محفوظ**.
3. **إن وُجد الملف:** اجمع المرشّحين بالترتيب: `primary` ثم `shadow` (إن اختلفت) ثم المفتاح المشتق القديم ثم `ural_db_fallback_enc_key` القديم. لكل مرشح غير `null`: `canOpen`. أول نجاح يحدد المفتاح.
   - استعمل `keyinfo.fingerprint` لترتيب/تأكيد المرشح لا كمصدر حقيقة (الملف قد يُستبدل بالاستعادة).
   - مرشح v2 نجح ⇒ إن كانت إحدى الفتحتين تالفة/مختلفة، أصلحها من الناجحة (كتابة + قراءة + مقارنة).
   - مرشح قديم نجح ⇒ القاعدة لم تُرحَّل بعد ⇒ شغّل الترحيل (§2) ثم أعد مفتاح v2.
4. **لم ينجح أي مرشح:**
   - إن بدأ الملف بـ`SQLite format 3\0` ⇒ قاعدة نصّية من قبل إصلاح 2026-08-30 ([go-blockers-roadmap.md:49-52](<../handoff/2026-08-30-go-blockers-roadmap.md#L49-L52>)) ⇒ رسالة صريحة (خارج نطاق هذا الترحيل؛ يمكن لاحقًا ترحيلها بنفس `exportTo` من مفتاح فارغ).
   - وإلا ⇒ `DatabaseKeyLostException` جديد (يرث/يُعامَل كـ`DatabaseKeyUnavailableException` في `main.dart`) يعرض شاشة **استرداد** (§5): إدخال رمز الاسترداد، أو اختيار نسخة احتياطية مصدَّرة بكلمة مرور. **ممنوع منعًا باتًا** توليد مفتاح جديد أو حذف/إعادة إنشاء الملف في هذا الفرع.
5. فشل التخزين الآمن نفسه (استثناء من `read`) ⇒ أعد المحاولة مرتين بفاصل قصير، ثم جرّب المرشحين القدامى (قد تكون القاعدة لم تُرحَّل)، ثم `DatabaseKeyUnavailableException`. لا يُشغَّل الترحيل أبدًا إن كان التخزين الآمن غير قابل للكتابة/القراءة الموثوقة.

### 1.5 إصلاح عيب قائم ضمن نفس العمل
`_getOrCreateSecureFallbackKey` يولّد مفتاحًا جديدًا عند `null` حتى لو القاعدة موجودة (§0.1 و§0.7). في التصميم الجديد يصبح المفتاح الاحتياطي القديم **مرشح قراءة فقط** ولا يُولَّد إطلاقًا.

---

## 2. ترحيل القاعدة القائمة من المفتاح المشتق إلى المفتاح العشوائي

### 2.1 الآلية: `sqlcipher_export` إلى ملف جديد ثم تبديل — بدل `PRAGMA rekey` في المكان
| | (أ) تصدير إلى ملف جديد + تبديل (موصى به) | (ب) `PRAGMA rekey` في المكان |
|---|---|---|
| الأصل أثناء العملية | **لا يُلمس** — يبقى قابلًا للفتح بالمفتاح القديم حتى لحظة التبديل | تُعاد كتابة كل الصفحات في نفس الملف |
| الانقطاع في المنتصف | يُحذف الملف الجديد ويُعاد المحاولة؛ لا شيء ضاع | يعتمد على يومية الرجوع؛ مع وضع WAL يلزم إطفاؤه أولًا؛ ملف في حالة غير معروفة يحتاج النسخة الاحتياطية |
| التحقق قبل الالتزام | ممكن بالكامل (فتح الملف الجديد بمفتاح جديد بمقبض منفصل) | لا يمكن إلا بعد الكتابة |
| المساحة | ~2× حجم القاعدة مؤقتًا | ~1× + اليومية |
| ملاحظة | `sqlcipher_export` **لا ينسخ** `user_version` (الذي يعتمد عليه drift لرقم السكيما) — يجب نسخه صراحةً (`PRAGMA v2.user_version = N`). *(من سلوك SQLCipher المعروف؛ يُتحقق منه في اختبار المحرك الحقيقي §6.3)* | يحفظ `user_version` |

إن أصرّ المالك على (ب): `PRAGMA wal_checkpoint(TRUNCATE)` ⇒ `PRAGMA journal_mode = DELETE` ⇒ `PRAGMA rekey = "x'<new>'"` ⇒ إغلاق ⇒ إعادة فتح بالجديد والتحقق ⇒ `journal_mode = WAL` في `setup` كالمعتاد — مع نفس النسخة الاحتياطية المسبقة وعلم التقدم أدناه. **قرار مالك (ق-2).**

### 2.2 مكان التنفيذ
داخل `openConnection()` في [connection_io.dart:32-58](<../../lib/data/database/connection_io.dart#L32-L58>)، بعد `_applyPendingRestore` وقبل `NativeDatabase.createInBackground` — هي اللحظة الوحيدة بلا أي مقبض مفتوح على الملف (نفس سبب اختيارها للاستعادة، التعليق في [:36-39](<../../lib/data/database/connection_io.dart#L36-L39>)). `getDatabaseEncryptionKey()` يُستبدل بـ`DbKeyManager.resolveForOpen(file)` الذي يستدعي `DbKeyMigrator.run(...)` عند الحاجة.
- قفل حصري على `<db>.key-migration.lock` (`RandomAccessFile.lock(FileLock.exclusive)`) طوال الترحيل — يمنع نسختين من التطبيق (أو خادم + أداة) من الترحيل معًا.
- مفتاح إيقاف طارئ: وسيط سطر الأوامر `--no-db-key-migration` بنفس نمط `--use-sqlite` في [main.dart:172-184](<../../lib/main.dart#L172-L184>) — يفتح بالمفتاح القديم ويتجاوز الترحيل (للدعم الفني إن ظهر عطل في الميدان).

### 2.3 الخطوات وعلم التقدم
علم التقدم: `<db>.key-migration.json` بجانب القاعدة: `{"state": "...", "newFp": "<fingerprint>", "oldKind": "legacyDerived|legacyFallback", "startedAt": ..., "backup": "<path>"}`. يُكتب إلى `*.tmp` ثم `rename` (لا يُعتمد عليه وحده؛ انظر §2.4 — **مصدر الحقيقة هو أي مفتاح يفتح أي ملف**).

| # | الخطوة | الحالة بعدها | عند الفشل |
|---|---|---|---|
| M0 | شروط مسبقة: الملف فُتح بمرشح قديم (من §1.4)؛ لا `.restore-pending`؛ مساحة حرة ≥ 2.2× (حجم `db` + `-wal`)؛ مسبار كتابة/قراءة للتخزين الآمن بمفتاح تجريبي ينجح | — | لا ترحيل هذه المرة؛ افتح بالقديم؛ سجّل `DiagnosticLogger` |
| M1 | المفتاح الجديد: إن وُجد في `db_key_v2::` بشكل صالح **أعد استعماله** (ترحيل سابق انقطع)، وإلا ولّد واكتب في الفتحتين وأعد القراءة وقارن | `keyStored` | لا ترحيل؛ افتح بالقديم |
| M2 | تفريغ WAL: افتح بالمفتاح القديم بمقبض مؤقت، `PRAGMA wal_checkpoint(TRUNCATE)` وتحقق `busy = 0` (نفس منطق [wal_checkpoint.dart:38-55](<../../lib/data/database/wal_checkpoint.dart#L38-L55>))، أغلق | — | لا ترحيل (الملف وحده ليس لقطة كاملة) |
| M3 | نسخة احتياطية مسبقة: نسخ `db` إلى `Documents/backups/key-migration/<db>.pre-v2-<ts>.db` + كتابة `*.keyinfo.json` بجانبها (`kind: legacyDerived`) — مجلد فرعي عمدًا كي لا يحذفها `_cleanOldBackups` (يحتفظ بآخر 7 من المجلد العلوي فقط، [connection_io.dart:584-608](<../../lib/data/database/connection_io.dart#L584-L608>)) | `backedUp` | لا ترحيل |
| M4 | التصدير: مقبض بالمفتاح القديم ⇒ `ATTACH DATABASE '<db>.v2-new' AS v2 KEY "x'<new>'"` ⇒ `SELECT sqlcipher_export('v2')` ⇒ `PRAGMA v2.user_version = <main.user_version>` ⇒ `DETACH` ⇒ إغلاق | `exported` | احذف `.v2-new`؛ افتح بالقديم |
| M5 | التحقق من الجديد بمقبض **منفصل**: `PRAGMA cipher_version` غير فارغ؛ فتح بالمفتاح الجديد؛ `PRAGMA quick_check` = `ok`؛ `user_version` مطابق؛ عدد الصفوف لكل جدول في `sqlite_master` مطابق للأصل؛ قراءة صف من `settings` و`users`؛ **و**المفتاح القديم **لا** يفتح `.v2-new` | `verified` | احذف `.v2-new`؛ افتح بالقديم؛ سجّل |
| M6 | التبديل: `rename db → <db>.pre-v2` ⇒ حذف `-wal`/`-shm` القديمين (نفس منطق [connection_io.dart:485-488](<../../lib/data/database/connection_io.dart#L485-L488>)) ⇒ `rename <db>.v2-new → db` | `swapped` | انظر §2.4 |
| M7 | فحص نهائي على المسار الحقيقي بالمفتاح الجديد ⇒ كتابة `<db>.keyinfo.json` (`kind: rawV2`, `migratedFrom`) ⇒ حالة `committedPendingConfirm` | — | ارجع لـ`.pre-v2` (§2.4) |
| M8 | **تأكيد في الإقلاع التالي** (عملية جديدة): إن قُرئ المفتاح من التخزين الآمن وفتح القاعدة ⇒ احذف `<db>.pre-v2` واحذف علم التقدم | `done` | يبقى `.pre-v2` (مشفّر بالقديم) — مسار رجوع |

لماذا M8 في إقلاع لاحق: التحقق أن المفتاح **يعيش** بعد إعادة تشغيل العملية (التخزين على القرص، لا ذاكرة القناة). النسخة المسبقة في `backups/key-migration/` تُحذف فقط بقرار المالك أو بعد مدة (ق-5).

### 2.4 سيناريوهات الانقطاع (الإقلاع التالي يقرر من الملفات الموجودة)
| ما يوجد على القرص | التفسير | الإجراء |
|---|---|---|
| `db` فقط، والقديم يفتحه | لم يبدأ أو فشل قبل M4 | أعد الترحيل من M0 (M1 يعيد استعمال المفتاح المخزَّن) |
| `db` + `.v2-new` | انقطع أثناء/بعد التصدير قبل التبديل | احذف `.v2-new`، أعد من M2 |
| لا `db`، يوجد `.pre-v2` + `.v2-new` | انقطع بين خطوتي `rename` في M6 | إن فتح الجديدُ `.v2-new` ونجح `quick_check` ⇒ `rename` إلى `db` وأكمل M7؛ وإلا `rename .pre-v2 → db` |
| `db` (يفتحه الجديد) + `.pre-v2` | بعد M6/M7 | أكمل M7/M8 |
| `db` لا يفتحه أي مرشح + `.pre-v2` يفتحه القديم | فُقد المفتاح الجديد بعد التبديل (أسوأ حالة: التخزين الآمن لم يحفظ) | `rename db → <db>.v2-orphan`، `rename .pre-v2 → db`، افتح بالقديم، سجّل وأعد الترحيل لاحقًا. لا يُحذف `.v2-orphan` آليًا |
| `db` لا يفتحه أي مرشح، ولا `.pre-v2` | فقد المفتاح بعد الالتزام | شاشة الاسترداد (§5): رمز الاسترداد ⇒ أو النسخة المسبقة في `backups/key-migration/` (تفقد ما بعد الترحيل) ⇒ أو نسخة مصدَّرة بكلمة مرور |

### 2.5 التراجع (rollback) المقصود
- آلي: أي فشل قبل M6 يترك الأصل كما هو (بالمفتاح القديم).
- يدوي بعد الالتزام: الدعم يشغّل بـ`--no-db-key-migration` ويستعيد `backups/key-migration/<db>.pre-v2-*.db` عبر `restoreDatabaseBackup` — يفتح بالمرشح المشتق. (يخسر ما كُتب بعد الترحيل؛ هذا متوقع من أي استعادة.)
- لا «rekey عكسي» إلى المفتاح المشتق: لا مبرر أمني، ويُبقي الشيفرة بسيطة.

---

## 3. فصل جذور الاشتقاق: أسرار الخادم مستقلة عن مفتاح القاعدة

### 3.1 الهدف
`NetworkService.startServer` ([network_service.dart:763-775](<../../lib/services/network_service.dart#L763-L775>)) يجب ألا يستدعي أي دالة لها علاقة بمفتاح القاعدة. هذا العمل **مستقل عن الترحيل في §2 ويسبقه** (التوصية نفسها في [part3:52](<part3-secrets-supplychain.md#L52>)): يمكن شحنه أولًا، ولا يمس بيانات.

### 3.2 الأسرار الجديدة (خدمة جديدة `lib/services/api/server_secrets.dart` على نمط `LanPairingService.initialize`)
| السر | مفتاح التخزين الآمن | يحل محل | المستهلك |
|---|---|---|---|
| مفتاح HMAC للجلسات (جهاز + ويب) | `ural_api_session_hmac_v1` (32 بايت base64url) | `ApiSessionToken.deriveKey(machineSeed)` | `ApiSessionToken.mint/verify/mintWeb/verifyWeb` |
| مفتاح HMAC لرموز الطاولات | `ural_table_bill_hmac_v1` | `TableBillToken.deriveKey(machineSeed)` | `TableBillToken.mintTable/mintSession/sessionPin` |
| سر التثبيت لتوكنات الأجهزة | `ural_lan_install_secret_v1` — **موجود بالفعل** ([lan_pairing_service.dart:14](<../../lib/services/api/lan_pairing_service.dart#L14>)) | — | `LanPairingService.tokenForDevice` |
| الـbearer القديم المشترك | لا تخزين — يُحسب من `LegacyDeviceSeed` فقط **داخل نافذة الانتقال** | `ApiAuthMiddleware.generateToken(machineSeed)` | الأجهزة غير المقترنة بعد |

- إن وُجد السر استُعمل؛ وإلا وُلِّد وكُتب وأُعيدت قراءته. **هنا** يجوز «ولِّد عند `null`» لأن فقدانه لا يفقد بيانات — بل يبطل جلسات/رموزًا (انظر §3.4). لكن يُسجَّل `DiagnosticLogger` بوضوح «سر الجلسات أعيد توليده» لأن `null` قد يعني عطلًا في التخزين (§0.7).
- فشل التخزين ⇒ نفس سلوك `LanPairingService.initialize` (رمي `DatabaseKeyUnavailableException`) — أو الأفضل استثناء خاص `ServerSecretsUnavailableException` يمنع **بدء الخادم فقط** لا التطبيق كله (قرار تنفيذي صغير).
- تعديلات الواجهات (بلا كسر الاختبارات القائمة): إضافة `ApiSessionToken.setSigningKey(List<int>)` و`TableBillToken.setSigningKey(List<int>)` و`setPreviousSigningKey(...)` للتحقق فقط؛ إبقاء `deriveKey(String)` و`setKeyForTesting(String)` لأن 9 ملفات اختبار تستدعيها (قائمة في §6.1)؛ وتعليمها `@visibleForTesting` بعد الانتقال.
- `LegacyDeviceSeed` (ملف جديد `lib/services/legacy_device_seed.dart`): ينقل منطق [security_service.dart:434-458](<../../lib/services/security_service.dart#L434-L458>) **حرفيًا** (نفس `deviceId` ونفس الـpepper) ويُستعمل في مكانين فقط: مرشح فتح قديم في `DbKeyManager`، والـbearer القديم أثناء نافذة الانتقال. الاسم يوضح أنه ليس سرًّا.

### 3.3 فك شرط `_activeToken` في الوسيط
[api_auth_middleware.dart:254-256](<../../lib/services/api/api_auth_middleware.dart#L254-L256>) يرفض **كل** `/api/*` إن كان `_activeToken == null`، و`verifyCredential` ([:154-165](<../../lib/services/api/api_auth_middleware.dart#L154-L165>)) كذلك. بعد الفصل:
- علم جاهزية منفصل `ApiAuthMiddleware.markReady()` يُضبط في `startServer` بعد تهيئة `LanPairingService` و`ServerSecrets`.
- `_activeToken` يُضبط فقط إن كان `await pairing.legacyAllowed()` صحيحًا عند البدء؛ والمقارنة `token == _activeToken` تبقى خلف `legacyAllowed()` كما هي ([:272-276](<../../lib/services/api/api_auth_middleware.dart#L272-L276>)).
- `/api/health` يسلّم `apiToken` أثناء نافذة الاقتران ([api_handler.dart:415-418](<../../lib/services/api/api_handler.dart#L415-L418>)) — بعد انتهاء نافذة الانتقال يصبح `null` فلا يُسلَّم شيء (الاقتران الجديد عبر `/api/pair` لا يحتاجه).

### 3.4 الأثر على الأجهزة المقترنة والجلسات القائمة عند التحويل
| ما يتأثر | هل يُبطَل؟ | كيف يعود |
|---|---|---|
| توكنات الأجهزة المقترنة (`HMAC(installSecret, deviceId)`) | **لا** — السر مستقل بالفعل | — |
| الـbearer القديم للأجهزة غير المقترنة | لا، ما دامت نافذة الانتقال مفتوحة (يُحسب من `LegacyDeviceSeed`، نفس القيمة) | بعد النافذة: إقران عبر الرمز كما هو اليوم |
| رموز `X-Session-Token` (30 يومًا) | **نعم، كلها فورًا** — وهذا مقصود: المفتاح القديم قابل للحساب، وقبوله ولو مؤقتًا يُبقي ثغرة تزوير جلسة المدير | العميل يحفظ الرمز والإثبات **في الذاكرة فقط** ويعيد السكّ: `ServerProxy.invalidateSessionToken` على 401 ثم `ensureSession` ([server_proxy.dart:2141-2164](<../../lib/services/server_proxy.dart#L2141-L2164>)). وإعادة تشغيل الخادم تعيد التشغيل للعملاء عادةً |
| رموز جلسات الويب (12 ساعة) | نعم | تسجيل دخول جديد من المتصفح |
| رموز QR للطاولات المطبوعة (بلا انتهاء) | **نعم** إن لم نفعل شيئًا ⇒ كل QR مطبوع يتوقف | خياران — **قرار مالك (ق-3)**: (أ) قبول المفتاح المشتق القديم **للتحقق فقط** في `TableBillToken.verifyTable` حتى يضغط المشغّل «أعدتُ طباعة رموز الطاولات» (علم `table_bill_legacy_accepted` في `settings`)، مع إصدار الرموز الجديدة بالمفتاح الجديد فقط؛ (ب) إبطال فوري وإعادة طباعة. الخطر في (أ) محدود: تزوير رمز طاولة يمنح **قراءة** حساب طاولة مفتوح؛ الكتابة محمية برمز الجلسة المشتق من الطلب (الذي يصبح بالمفتاح الجديد فورًا إن فُصلت دالتا `mintSession/sessionPin` لاستعمال المفتاح الجديد وحده) |

**خطر محدد يجب معالجته:** التعليق في [server_proxy.dart:116-121](<../../lib/services/server_proxy.dart#L116-L121>) يقول إن قراءات GET المقيدة بالفرع «تفشل مغلقةً (فارغة، لا 401)» عند رمز غير صالح، و`ensureSession` لا يعيد السكّ إلا بعد 12 ساعة (`_sessionRefreshAfter`) أو 401. بعد تدوير مفتاح الجلسات قد يرى عميل/مرآة لم يكتب شيئًا **قوائم فارغة حتى 12 ساعة**. العلاج المقترح: إضافة `sessionKeyId` (أول 8 hex من `HMAC(sessionKey, "kid")`) إلى جواب `/api/health` ([api_handler.dart:401-426](<../../lib/services/api/api_handler.dart#L401-L426>)) — ليس سرًّا — والعميل يستدعي `invalidateSessionToken` لكل المستخدمين عند تغيّره في دورة إعادة الاتصال. (لم أتحقق من موضع دورة الـ5 دقائق بالتفصيل — يُراجَع عند التنفيذ.)

### 3.5 آلية التدوير
- `ServerSecrets.rotate(ServerSecretKind kind)`: يولّد سرًّا جديدًا، ينقل الحالي إلى `<key>_prev`، يحدّث الذاكرة (`setSigningKey` + `setPreviousSigningKey` للطاولات فقط حسب ق-3)، ويُسجَّل في سجل النشاط.
  - الجلسات: بلا فترة سماح (السبب أعلاه)؛ العملاء يعيدون السكّ عبر `sessionKeyId`.
  - الطاولات: حسب ق-3.
  - سر التثبيت `ural_lan_install_secret_v1`: تدويره = إبطال كل الأجهزة المقترنة وإعادة إقرانها. الإبطال الفردي موجود (`LanPairingService.revoke`) ويكفي لجهاز مفقود — لذا تدوير سر التثبيت إجراء طوارئ فقط في واجهة الأجهزة مع تأكيد مزدوج.
- الواجهة: زر «تدوير مفاتيح الخادم» في قسم الأجهزة المتصلة (مكان قائمة الأجهزة الحالية؛ اختبار [settings_devices_section_test.dart](<../../test/widget/settings_devices_section_test.dart>) يغطي القسم) — يتطلب صلاحية المدير.
- تدوير تلقائي دوري: لا أوصي به الآن (يكسر QR المطبوع)؛ التدوير عند الحاجة يكفي.

### 3.6 وضع PostgreSQL
بعد الفصل لا يستدعي خادم PG أي شيء متعلق بمفتاح SQLite — هذا يصحح الخلط الحالي في §0.6. أسرار الخادم في التخزين الآمن لجهاز الخادم (لا في جدول `settings` المشترك في PG) حتى لا يقرأها من يملك صلاحية القاعدة.

---

## 4. النسخ الاحتياطية القديمة المشفّرة بالمفتاح المشتق

### 4.1 الحالة
كل نسخة اليوم (`createDatabaseBackup`، نسخة ما قبل ترحيل السكيما [database_migrations.dart:74-79](<../../lib/data/database/database_migrations.dart#L74-L79>)، النسخة الإجبارية لأدوات التصفير [data_wipe_service.dart:92-109](<../../lib/services/admin/data_wipe_service.dart#L92-L109>)، `autoBackupOnStartup` من [database_startup.dart:1744](<../../lib/data/database/database_startup.dart#L1744>)، والمصدَّرة عبر `exportBackupToPath`) هي نسخة ملف مشفّرة بالمفتاح المشتق. لا ترويسة ولا بيانات وصفية.

### 4.2 القرار المقترح: ثلاث طبقات معًا
1. **المفتاح المشتق مرشّح فتح للقراءة فقط (لا للتشفير أبدًا):** `LegacyDeviceSeed` يبقى في `DbKeyManager.resolveForOpen`. استعادة نسخة قديمة على **نفس الجهاز** تعمل بلا أي واجهة: `restoreDatabaseBackup` ⇒ `.restore-pending` ⇒ الإقلاع: `_applyPendingRestore` ⇒ المرشح المشتق يفتحها ⇒ الترحيل §2 يعيد تشفيرها تلقائيًا. (يفشل فقط إن تغيّر `deviceId` — كما هو اليوم.) لا يضيف خطرًا: من يعرف `deviceId` يحسب المفتاح سواء بقيت الدالة أم لا.
2. **إعادة تشفير النسخ المحلية بعد نجاح الترحيل (M8):** مهمة خلفية تمر على `listBackups()` (المجلد `Documents/backups`، المفلتر باسم القاعدة) وتصدّر كل نسخة إلى ملف جديد بالمفتاح الجديد (`exportTo`) ثم تتحقق وتستبدل. يغلق نافذة «من يملك القرص ويعرف `deviceId` يقرأ كل النسخ التاريخية». النسخ الخارجية (USB) لا يمكن الوصول إليها — تبقى ضعيفة وتوثَّق للمالك. **قرار مالك (ق-4):** إعادة التشفير، أو حذف النسخ القديمة بعد مدة، أو تركها.
3. **بيانات وصفية مجاورة لكل نسخة جديدة:** `<backup>.db.keyinfo.json` = `{version, kind, fingerprint, userVersion, appVersion, createdAt, dbFileName, recoveryEnvelope?}` (لا ترويسة داخل الملف: أول 16 بايت في SQLCipher هي الملح ولا مكان آمن لحقل). تعديلات لازمة:
   - `createDatabaseBackup` يكتب الملف المجاور بعد النسخ ([connection_io.dart:414-433](<../../lib/data/database/connection_io.dart#L414-L433>)).
   - `_cleanOldBackups` يحذف المجاور مع النسخة ([:601-604](<../../lib/data/database/connection_io.dart#L601-L604>)).
   - `exportBackupToPath` ينسخ المجاور مع النسخة ([:632-646](<../../lib/data/database/connection_io.dart#L632-L646>)).
   - `_isOwnBackup` لا يحتاج تغييرًا (`.keyinfo.json` لا ينتهي بـ`.db`).

### 4.3 تقوية الاستعادة (ضروري، لأن المفتاح لم يعد قابلًا للاشتقاق)
- `restoreDatabaseBackup` ([connection_io.dart:502-515](<../../lib/data/database/connection_io.dart#L502-L515>)) **يتحقق قبل الجدولة**: يفتح النسخة بالمرشحين (v2 الحالي، المشتق، الاحتياطي القديم، أو مفتاح من `recoveryEnvelope`/كلمة مرور §5) ويشغّل `PRAGMA quick_check`. لا مرشح يفتحها ⇒ يرفض برسالة واضحة. (يغلق أيضًا الجزء (ج) من E-05.)
- `_applyPendingRestore` ([:474-495](<../../lib/data/database/connection_io.dart#L474-L495>)) ينقل القاعدة الحالية إلى `<db>.pre-restore` **قبل** النسخ فوقها (اليوم `pending.copy(dbPath)` يكتب فوقها مباشرة). بعد أن يفتح `resolveForOpen` الملف المستعاد بنجاح يُحذف `.pre-restore`؛ وإن لم يُفتح يُعاد `.pre-restore` مكانه. بدون هذا، نسخة لا يُعرف مفتاحها تمحو القاعدة الحية.

### 4.4 مسار نسخ ثانٍ يحتاج انتباهًا (خارج النطاق — للإبلاغ)
`BackupService.performBackup` ([backup_service.dart:14-56](<../../lib/core/services/backup_service.dart#L14-L56>)) يُستدعى بمسار `database.sqlite` بجانب الـexe ([main_desktop.dart:58-64](<../../lib/main_desktop.dart#L58-L64>)) أو في `Directory.current` ([app_shell.dart:369-374](<../../lib/presentation/shell/app_shell.dart#L369-L374>)) — لا يطابق مسار القاعدة الفعلي (`Documents/<Brand.dbPrefix>_<flavor>.db`). يبدو أنه لا ينسخ شيئًا عادةً (**استنتاج** — لم أتحقق في الميدان). لا يتأثر بالتصميم، لكن إن أُصلح مساره يجب أن يمر بنفس `keyinfo` المجاور. `RemoteBackupService` غير مستدعى (E-05).

---

## 5. نقل القاعدة بين جهازين والاسترداد عند فقد المفتاح الآمن

### 5.1 لماذا هذا إلزامي الآن
اليوم: القاعدة/النسخة تُفتح على نفس الجهاز ما دام `deviceId` ثابتًا، بأي حساب ويندوز وبأي بناء. بعد التصميم المفتاح مرتبط بـ(حساب ويندوز × `CompanyName/ProductName` للـexe) (§0.7). سيناريوهات فقدٍ جديدة: إعادة تثبيت ويندوز، حساب ويندوز آخر على نفس الجهاز (شائع في نقاط البيع)، حذف الاعتماد من Credential Manager، بناء تطوير بلا `BRAND_*`، تلف ملف `.secure`.

### 5.2 آليتان (مكمّلتان) — **قرار مالك (ق-6)**
**(أ) رمز استرداد (للكوارث على نفس القاعدة):**
- عند توليد المفتاح (تثبيت جديد أو M1) يُولَّد رمز استرداد عشوائي ≥ 128 بت يُعرض بصيغة مجموعات Base32 (مثل `XXXX-XXXX-…`).
- الغلاف: `KEK = Argon2id(code, salt)` (الحزمة `cryptography` موجودة ومستعملة في [security_service.dart:147](<../../lib/services/security_service.dart#L147>)) ثم `AES-256-GCM(KEK, dbKey)` ⇒ يُخزَّن في `recoveryEnvelope` داخل `<db>.keyinfo.json` وفي كل `<backup>.keyinfo.json`. بما أن الرمز عالي الإنتروبيا تكفي معاملات Argon2id معتدلة.
- **متى يُعرض:** الترحيل يحدث قبل تسجيل الدخول، فلا يمكن عرضه حينها. يُحفظ الرمز مؤقتًا في التخزين الآمن (`db_recovery_code_pending::<db>` — بنفس حماية المفتاح فلا خسارة أمنية) ويظهر للمدير بعد الدخول في شريط لا يختفي حتى يؤكد «حفظته/طبعته»، ثم يُحذف من التخزين.
- الاسترداد: عند `DatabaseKeyLostException` تعرض `FatalSetupErrorApp` (أو شاشة جديدة على نمطها) حقل «رمز الاسترداد» ⇒ فك الغلاف ⇒ `canOpen` ⇒ كتابة المفتاح في التخزين الآمن لهذا المستخدم ⇒ متابعة الإقلاع. هذا يحل أيضًا «حساب ويندوز آخر».
- تدوير مفتاح القاعدة لاحقًا (بنفس آلية §2) يتطلب إعادة لف الغلاف — ورمزًا جديدًا إن اعتُبر القديم مكشوفًا.

**(ب) تصدير محمول بكلمة مرور (للنقل بين الأجهزة):**
- «تصدير نسخة محمولة»: مقبض بالمفتاح الحالي ⇒ `ATTACH '<out>.db' AS p KEY '<password>'` (صيغة عبارة مرور ⇒ PBKDF2 داخل SQLCipher) ⇒ `sqlcipher_export('p')` + `user_version` ⇒ ملف + `keyinfo` (`kind: passphrase`، بلا بصمة تكشف شيئًا).
- الاستيراد على جهاز آخر: اختيار الملف + كلمة المرور ⇒ التحقق ⇒ `exportTo` إلى `.restore-pending` بمفتاح v2 **لذلك الجهاز** ⇒ المسار المعتاد.
- فرض حد أدنى لطول كلمة المرور (الملف قد يُسرق مع USB).

**بديل نظري (لا أوصي به الآن):** لفّ المفتاح بـ DPAPI بنطاق الجهاز (`CryptProtectData` مع `CRYPTPROTECT_LOCAL_MACHINE`) ليعمل لكل حسابات ويندوز — غير متاح عبر `flutter_secure_storage`، ويتطلب FFI عبر `win32` (موجودة في `pubspec.lock` كاعتماد **انتقالي** 5.15.0 فقط). ونطاق الجهاز يعني أن أي مستخدم محلي يفك المفتاح — أي يعيدنا قريبًا من وضع E-01 أمام المهاجم المحلي.

### 5.3 العملاء والمرايا
قاعدة العميل/المرآة نسخة مزامنة من الخادم: فقد مفتاحها يُعالج بإعادة تهيئة ومزامنة كاملة — **إلا** صف الصادر (outbox) غير المرسل. لذا شاشة الاسترداد على العميل تعرض «إعادة التهيئة من الخادم» فقط بعد تحذير صريح، ورمز الاسترداد يبقى مفضلًا.

---

## 6. أوضاع الخادم/العميل/المرآة والاختبارات

### 6.1 الأوضاع
| الوضع | قاعدة SQLite محلية؟ | يتأثر بالترحيل §2؟ | يتأثر بالفصل §3؟ |
|---|---|---|---|
| standalone | نعم | نعم | لا (لا يبدأ الخادم — [main_desktop.dart:84-87](<../../lib/main_desktop.dart#L84-L87>)) |
| server + SQLite | نعم | نعم | نعم |
| server + PG متصل | لا | لا | نعم (ويزول استدعاء مفتاح SQLite بلا معنى) |
| server + PG offline fallback | نعم (نفس الملف) | نعم | نعم |
| client | نعم (مخزن محلي + مزامنة HTTP) | نعم — مستقل لكل جهاز، بلا تنسيق مع الخادم | لا (يحمل توكن الجهاز والجلسة فقط) |
| mirror | نعم | نعم | لا؛ لكن يتأثر بإبطال الجلسات (§3.4 وخطر الـ12 ساعة) |

ترتيب الطرح في شبكة متعددة الأجهزة: لا يلزم ترتيب — كل جهاز يرحّل قاعدته عند أول إقلاع بالإصدار الجديد. الخادم يُحدَّث أولًا (كالعادة) لأن الفصل §3 يبطل الجلسات؛ العملاء يعيدون السكّ.

### 6.2 الاختبارات التي تلمس المسار الحالي (بحث في `test/`)
- **لا اختبار يستدعي `getDatabaseEncryptionKey`** ولا يفتح ملف SQLCipher؛ `AppDatabase.forTesting()` في الذاكرة بلا مفتاح ([connection_io.dart:331-337](<../../lib/data/database/connection_io.dart#L331-L337>)).
- يتأثر نصيًا: [table_bill_routes_are_gated_test.dart:174-181](<../../test/structural/table_bill_routes_are_gated_test.dart#L174-L181>) يتطلب النص `TableBillToken.deriveKey(machineSeed)` في `network_service.dart` ⇒ يُحدَّث ليتطلب تهيئة المفتاح من `ServerSecrets` (الغرض نفسه: «المفتاح يُهيّأ عند إقلاع الخادم»).
- يستعمل واجهات يجب إبقاؤها: `ApiSessionToken.deriveKey(...)` في `api_session_auth_test`, `api_web_session_test`, `web_client_e2e_test`, `web_host_enable_test`, `web_read_channel_test`, `web_users_leak_test`, `web_write_path_test`؛ `ApiSessionToken.setKeyForTesting` في `api_auth_throttle_test`, `api_session_token_test`, `client_user_id_header_test`؛ `TableBillToken.setKeyForTesting` في `guest_order_request_api_test`, `table_bill_api_test`, `table_bill_token_test`؛ `ApiAuthMiddleware.generateToken` في `api_auth_middleware_test`. ⇒ إبقاء الدوال الثلاث بتوقيعها.
- `einvoice_server_worker_wiring_guard_test` يقتنص جسم `startServer` ويتحقق من `shelf_io.serve` و`_startEInvoiceWorker` — لا يتأثر.

### 6.3 كيف تُحقن البدائل في `flutter_test`
- **التخزين الآمن:** `FlutterSecureStorage.setMockInitialValues({})` مستعمل فعلًا ([security_phase1_gates_test.dart:133](<../../test/unit/security_phase1_gates_test.dart#L133>)). لكن الأنظف حقن `SecretStore` في `DbKeyManager`/`ServerSecrets` مع `MemorySecretStore` — ويُضاف `FlakySecretStore` يرجع `null` أو يرمي أو «يبتر» القيمة لاختبار §0.7.
- **المسارات:** نمط `_FakePathProvider extends PathProviderPlatform` في [data_wipe_service_test.dart:32-77](<../../test/integration/data_wipe_service_test.dart#L32-L77>) — يُعاد استعماله لمجلد مؤقت.
- **محرك التشفير:** `flutter test` يحمّل `sqlite3.dll` **العادية** من native-assets (`build/native_assets/windows/sqlite3.dll` كما يظهر في سجلات أعطال `flutter test` الموجودة في جذر المستودع)، فـ`PRAGMA key` يُتجاهل و`cipher_version` فارغ. و`sqlite3 3.3.1` المحلولة لا تحوي `open.overrideFor` (بحثتُ في مصدرها في الكاش). إذن:
  1. منطق الحالة (§1.4، §2.3، §2.4) يُختبر بـ`FakeCipherOps` في الذاكرة (يحاكي «أي مفتاح يفتح أي ملف» + حقن انقطاع بعد كل خطوة M0..M8). هذا هو الجزء الأهم ويغطي كل صفوف جدول §2.4.
  2. اختبار محرك حقيقي `test/integration/db_key_rekey_engine_test.dart` يتخطى نفسه (`skip:`) إذا كان `PRAGMA cipher_version` فارغًا — فيصبح ذا معنى فقط حيث يتوفر SQLCipher.
  3. تحقق يدوي إلزامي على بناء `build_picpos.bat` الحقيقي (§8 مهمة T10) لأنه البيئة الوحيدة المؤكدة الآن التي تحمل SQLCipher. **لم أتحقق** من طريقة لتحميل DLL الـSQLCipher داخل `flutter test` — بند مفتوح.
- **الفصل §3:** اختبارات `ServerSecrets` بـ`MemorySecretStore`: سر يُولَّد مرة ويثبت عبر «إعادة تشغيل» (مثيل جديد على نفس المخزن)؛ رمز سُكّ بالمفتاح المشتق القديم يُرفض؛ `rotate` يبطل الجلسات ويُبقي الطاولات حسب ق-3؛ الوسيط يقبل جهازًا مقترنًا حين `_activeToken == null`.

---

## 7. الويب والجوال — الحدود فقط

- **الويب (`web_app/`, `connection_web.dart`):** لا ملف قاعدة ولا `SecurityService` ولا نسخ احتياطي (stubs). عميل الويب يقرأ عبر `AppDatabase.forWebRemote` من المضيف ويحمل رمز جلسة ويب `aud:'web'` فقط. الأثر الوحيد: §3 يبطل جلسات الويب القائمة عند التحويل/التدوير (إعادة دخول). لا عمل آخر.
- **تطبيقات الجوال (`mobile/`, `mobile_pos/`, `mobile_admin/`, `packages/picpos_device`):** شيفرة منفصلة تستعمل `sqflite_sqlcipher` ومفتاحًا عشوائيًا 256-بت في `flutter_secure_storage` منذ البداية (`DatabaseKey.obtain` في [packages/picpos_device/lib/src/store/db_key.dart:39-53](<../../packages/picpos_device/lib/src/store/db_key.dart#L39-L53>)، وتوثيق [part1-cloud-mobile.md:189](<part1-cloud-mobile.md#L189>)). **خارج النطاق**، مع ملاحظتين: (1) `obtain()` يولّد مفتاحًا جديدًا عند `null` — نفس فئة الخطر في §0.7/§1.4 (على أندرويد `null` يحدث مثلًا بعد استعادة نسخة احتياطية للنظام أو تلف Keystore)؛ يستحق مراجعة منفصلة. (2) تطبيق الجذر لا يُبنى لأندرويد (لا مجلد `android/`)، فلا Keystore في نطاق هذا التصميم.
- الرقعة [patches-for-uralcash/engine-fixes.diff](<../../patches-for-uralcash/engine-fixes.diff>) تستدعي `getDatabaseEncryptionKey` — إن طُبّق التصميم على المنتج الشقيق UralCash تُحدَّث معه (نفس الـpepper ونفس مخطط التسمية `Brand.dbPrefix`).

---

## 8. خطة التنفيذ والجهد والمخاطر وقرارات المالك

### 8.1 المرحلة A — فصل أسرار الخادم (E-02). تُشحن أولًا، لا تمس البيانات.
| # | المهمة | الملفات | معيار النجاح | أمر التحقق |
|---|---|---|---|---|
| T1 | `SecretStore` (+`MemorySecretStore`) و`ServerSecrets` (توليد/قراءة/إعادة قراءة/`rotate`) | جديد `lib/services/secret_store.dart`، جديد `lib/services/api/server_secrets.dart` | السر ثابت عبر مثيلين على نفس المخزن؛ `null` ⇒ توليد + سجل تشخيص؛ استثناء التخزين ⇒ استثناء صريح | `flutter test test/unit/server_secrets_test.dart` |
| T2 | `setSigningKey`/`setPreviousSigningKey` مع إبقاء `deriveKey`/`setKeyForTesting` | `lib/services/api/api_session_token.dart`, `lib/services/api/table_bill_token.dart` | الاختبارات القائمة تمر بلا تعديل؛ رمز موقَّع بمفتاح سابق يُقبل في `verifyTable` فقط حين يُضبط السابق | `flutter test test/unit/api_session_token_test.dart test/unit/table_bill_token_test.dart test/unit/api_web_session_test.dart` |
| T3 | `LegacyDeviceSeed` — نقل حرفي للاشتقاق مع مزوّد `deviceId` قابل للحقن | جديد `lib/services/legacy_device_seed.dart`; `security_service.dart` يفوّض إليه مؤقتًا | اختبار ذهبي: `deviceId='ABC'` ⇒ `sha256('ABC:UralCash_Security_Pepper_v2')` | `flutter test test/unit/legacy_device_seed_test.dart` |
| T4 | ربط `startServer` بـ`ServerSecrets`؛ علم جاهزية في الوسيط بدل شرط `_activeToken`؛ الـbearer القديم من `LegacyDeviceSeed` داخل النافذة فقط | `lib/services/network_service.dart` (763-775)، `lib/services/api/api_auth_middleware.dart` (140-165, 254-285)، `test/structural/table_bill_routes_are_gated_test.dart` | لا استدعاء لـ`getDatabaseEncryptionKey` في `network_service.dart`؛ جهاز مقترن يُقبل بعد انتهاء النافذة و`_activeToken == null` | `flutter test test/services/api_auth_middleware_test.dart test/unit/lan_pairing_test.dart test/unit/lan_pairing_security_test.dart test/unit/client_user_id_header_test.dart test/structural/table_bill_routes_are_gated_test.dart test/integration/api_session_auth_test.dart` |
| T5 | `sessionKeyId` في `/api/health` وإبطال رموز العميل عند تغيّره | `lib/services/api/api_handler.dart` (`_healthCheck`)، `lib/services/server_proxy.dart` | عميل/مرآة يعيد السكّ خلال دورة إعادة اتصال واحدة بعد التدوير | اختبار جديد `test/unit/session_key_rotation_client_test.dart` |
| T6 | واجهة «تدوير مفاتيح الخادم» + سجل نشاط + قرار ق-3 للطاولات | قسم الأجهزة في الإعدادات + `server_secrets.dart` | زر للمدير فقط؛ تأكيد مزدوج لسر التثبيت | `flutter test test/widget/settings_devices_section_test.dart` |

**جهد A:** ~3–4.5 أيام مطوّر.

### 8.2 المرحلة B — مفتاح القاعدة العشوائي (E-01). خلف علم تفعيل حتى T12.
| # | المهمة | الملفات | معيار النجاح | أمر التحقق |
|---|---|---|---|---|
| T7 | `CipherOps` + `FakeCipherOps` + `DbKeyManager.resolveForOpen` (تثبيت جديد + مرشحون قدامى، بلا ترحيل) خلف علم `--dart-define=DB_KEY_V2` | جديد `lib/data/database/db_key_manager.dart`؛ `connection_io.dart` (31-58) يستدعيه بدل `getDatabaseEncryptionKey` | كل فروع §1.4 بما فيها: `null` مع ملف موجود ⇒ **لا توليد** واستثناء استرداد | `flutter test test/unit/db_key_manager_test.dart` |
| T8 | `DbKeyMigrator` (M0–M8) + قفل + `--no-db-key-migration` | جديد `lib/data/database/db_key_migrator.dart`; `lib/main.dart` (وسائط CLI) | اختبار انقطاع بعد **كل** خطوة يعيد الحالة إلى صف من جدول §2.4 ولا يفقد ملفًا قابلًا للفتح أبدًا | `flutter test test/unit/db_key_migrator_test.dart` |
| T9 | `CipherOps` الإنتاجي عبر `NativeDatabase(setup:)`: `canOpen`/`checkpoint`/`exportTo` (+`user_version`)/`verify` مع حارس `cipher_version` | `db_key_manager.dart` أو ملف منفصل `sqlcipher_ops.dart` | يرفض العمل إن كان المحرك ليس SQLCipher | `flutter test test/integration/db_key_rekey_engine_test.dart` (يتخطى نفسه بلا SQLCipher) |
| T10 | تحقق حقيقي على بناء الإصدار: نسخة من قاعدة بحجم عميل حقيقي، قياس زمن الترحيل، قتل العملية عند كل خطوة (بناء profile مع حقن انقطاع بمتغير بيئة يُقرأ في غير release فقط) | `build_picpos.bat`، قائمة فحص في هذا المستند | الملف يُفتح بعد كل انقطاع؛ أول 16 بايت ليست `SQLite format 3`؛ القديم لا يفتح الجديد | يدوي — يُسجَّل الناتج |
| T11 | `keyinfo` للنسخ، تحقق قبل جدولة الاستعادة، `.pre-restore` في `_applyPendingRestore`، تنظيف/تصدير المجاور | `lib/data/database/connection_io.dart` (360-515, 584-646) | استعادة ملف لا يُفتح تُرفض قبل الجدولة؛ القاعدة الحية لا تُمحى بنسخة سيئة | `flutter test test/integration/data_wipe_service_test.dart test/unit/backup_keyinfo_test.dart` |
| T12 | رمز الاسترداد + الغلاف + شاشة الاسترداد + `DatabaseKeyLostException` في `main.dart` (272-281, 507-517) | `db_key_manager.dart`، شاشة على نمط `FatalSetupErrorApp`، `lib/main.dart` | فقد التخزين الآمن ⇒ إدخال الرمز يعيد الفتح؛ رمز خاطئ لا يعدّل شيئًا | `flutter test test/unit/db_key_recovery_test.dart test/widget/fatal_setup_error_screen_test.dart` |
| T13 | تصدير/استيراد محمول بكلمة مرور | `connection_io.dart` + `settings_repository_impl.dart` (+ واجهة النسخ) | ملف يُستورد على مجلد/مستخدم آخر بكلمة المرور فقط | اختبار محرك (يتخطى) + T10 يدويًا |
| T14 | إعادة تشفير النسخ المحلية القديمة بعد M8 (حسب ق-4) | `db_key_migrator.dart` | لا نسخة في `Documents/backups` تُفتح بالمفتاح المشتق | ضمن `db_key_migrator_test` |
| T15 | حذف `SecureStorageService.clearAll()` أو استثناء مفاتيح `db_key_*` منه | `lib/services/secure_storage_service.dart` | لا مسار في `lib/` يمحو مفتاح القاعدة | grep `deleteAll` في `lib/` |
| T16 | تفعيل العلم افتراضيًا بعد تجربة ميدانية؛ تحديث [part3](<part3-secrets-supplychain.md>) وHANDOFF | — | — | — |

**جهد B:** ~10–12 يوم مطوّر + تجربة ميدانية. **الإجمالي ~13–17 يومًا.** (تقدير، يشمل الاختبارات لا المراجعة.)

ترتيب الشحن المقترح: A كاملًا ⇒ T3/T7–T11 + T15 ⇒ T12 (**قبل** تفعيل الترحيل لأي عميل) ⇒ T13/T14 ⇒ T16. لا يُفعَّل الترحيل في الميدان قبل T12، لأن المفتاح الجديد يجلب سيناريوهات فقد لم تكن موجودة (§5.1).

### 8.3 المخاطر
1. **فقد البيانات بسبب `null` من التخزين الآمن** (§0.7): أخطر خطر في التصميم. التخفيف: «أول تشغيل» يُستنتج من غياب الملف؛ فتحتان + إعادة قراءة؛ تأكيد في إقلاع ثانٍ (M8)؛ `.pre-v2` ونسخة `key-migration/`؛ رمز استرداد.
2. **انحدار تشغيلي جديد:** حسابات ويندوز متعددة على جهاز نقطة البيع، أو تغيّر `CompanyName/ProductName`، أو تشغيل بناء تطوير على قاعدة الإنتاج (المسار `Monexia\UralCash ERP` مقابل `PicPos\PicPos`) ⇒ «القاعدة لا تُفتح». يجب تثبيت `BRAND_COMPANY_NAME/BRAND_PRODUCT_NAME` كعقد لا يتغير (تعليق + اختبار هيكلي على `build_picpos.bat`).
3. **زمن الترحيل عند الإقلاع** على قاعدة كبيرة (يحدث داخل `LazyDatabase` قبل أول استعلام) — قد يبدو التطبيق متجمدًا. يُقاس في T10؛ إن تجاوز بضع ثوانٍ تلزم شاشة تقدم.
4. **`sqlcipher_export` و`user_version`** وأي إعدادات `cipher_*` — يجب التأكد على المحرك الحقيقي (T9/T10). وإبقاء الاعتماد على `sqlcipher_flutter_libs 0.6.8` (EOL، D-01): ترقية المحرك لاحقًا إلى `sqlite3 3.x`+SQLCipher قد تغيّر الإعدادات الافتراضية؛ يُختبر فتح قاعدة v2 بعد أي ترقية. الأفضل عدم دمج الترقيتين في إصدار واحد.
5. **إبطال الجلسات** عند الفصل: قراءات العميل/المرآة «الفارغة» حتى 12 ساعة إن لم يُنفّذ T5.
6. **QR الطاولات المطبوعة** تتعطل إن اختير الإبطال الفوري (ق-3).
7. **النسخ الخارجية (USB) القديمة** تبقى مفتوحة لمن يعرف `deviceId` — لا علاج تقني، توثيق للمالك فقط.
8. **الاختبار الآلي لا يرى SQLCipher** (`flutter test` يحمّل sqlite3 العادية) — المنطق مغطى بالمزيّف، والمحرك يدويًا فقط حتى يُحلّ ذلك.
9. **مثيلان للتطبيق** يرحّلان معًا — يغطيه القفل الحصري؛ يجب التأكد أن القفل يعمل على مجلد `Documents` المتزامن مع OneDrive إن وُجد (**لم أتحقق**).

### 8.4 قرارات تحتاج المالك
- **ق-1:** صيغة المفتاح الجديد: خام `x'..'` (موصى) أم عبارة مرور.
- **ق-2:** التصدير إلى ملف جديد + تبديل (موصى) أم `PRAGMA rekey` في المكان.
- **ق-3:** رموز QR للطاولات: قبول المفتاح القديم للتحقق حتى إعادة الطباعة، أم إبطال فوري.
- **ق-4:** النسخ المحلية القديمة: إعادة تشفير (موصى)، حذف بعد مدة، أم ترك.
- **ق-5:** مدة الاحتفاظ بنسخة `backups/key-migration/*.pre-v2-*.db` (مشفّرة بالمفتاح الضعيف؛ يوصى بحذفها بعد 30 يومًا من M8 أو بتأكيد المالك).
- **ق-6:** آلية الاسترداد: رمز استرداد + تصدير بكلمة مرور (موصى معًا)، أو أحدهما. ومن يحفظ الرمز (المالك/الموزع).
- **ق-7:** تفعيل الترحيل تلقائيًا عند الإقلاع (موصى بعد تجربة) أم بزر يدوي من الإعدادات.
- **ق-8:** سياسة الأجهزة متعددة حسابات ويندوز: قبول «رمز الاسترداد لكل حساب جديد»، أم فرض حساب واحد، أم دراسة DPAPI بنطاق الجهاز (§5.2، يضعف الحماية).

### 8.5 ما لم يُتحقق منه في هذه المراجعة
- لم أشغّل أي اختبار أو بناء (بطلب المهمة). كل أوامر التحقق أعلاه مقترحة لا منفّذة.
- سلوك `sqlcipher_export` مع `user_version`، ودعم `PRAGMA rekey` مع WAL في نسخة SQLCipher المضمّنة في `sqlcipher_flutter_libs 0.6.8` — لم يُقرأ مصدر المحرك.
- مسار دورة إعادة الاتصال ذات الـ5 دقائق في العميل (`ensureSession`) لم يُتتبع بالكامل.
- مصدر `deviceId` في `device_info_plus` على ويندوز — بقي «استنتاجًا» كما في part3.

# مراجعة أمنية — الجزء 1: خادم السحابة والجوال والعميل المشترك

> قراءة فقط · الالتزام المرجعي `b0aaad84` (2026-10-11) · الحالة: **مكتمل** · لم تُشغَّل أي اختبارات أو أدوات تحليل؛ كل النتائج من قراءة الكود.

## الملخص

الأساس الأمني للخادم جيد: كل SQL بمعاملات مسماة (لا حقن SQL)، عزل `company_id` متسق في كل المسارات (لم أجد IDOR)، رموز عشوائية 256 بت مخزنة كتجزئة، مقارنات ثابتة الزمن، PBKDF2 بـ120000 تكرار، فصل مفتاح HMAC لجلسات الإدارة، إبطال جلسات الإدارة بالـ`jti`، وتوقيع Ed25519 للّقطات مع ربط `kind/scope/asOf` داخل الحمولة. تطبيقا `mobile_admin` و`mobile_pos` مضبوطان جيدًا (HTTPS فقط في الإصدار عبر `UrlPolicy`، `allowBackup=false`، cleartext في debug فقط).

أهم المخاطر:
1. **تطبيق المندوب `mobile/` يقبل HTTP في نسخة الإصدار** (`usesCleartextTraffic="true"` في main وبلا `UrlPolicy`)، فرموز الجهاز والجلسة والـPIN تمر بنص واضح عند استخدام عنوان `http://` (وهو الافتراضي في شاشة الاقتران) — M-1، عالية.
2. **لا حدّ لحجم جسم الطلب في الخادم**، ويُقرأ الجسم كاملًا قبل المصادقة وحدّ المعدل على `/mobile/pair` و`/manage/pair` ⇒ حجب خدمة دون مصادقة — S-9، عالية.
3. **جلسات المندوب لا تُبطَل عند تعطيل الموظف** ولا يوجد خروج/إبطال لها — S-1.
4. **تخمين PIN المندوب دون اتصال بلا حدود** على الهاتف — M-4.
5. **الثقة بمفتاح التوقيع من السحابة في الاقتران اليدوي** لتطبيق الإدارة دون عرض البصمة، فيسقط هدف «لا تثق بالسحابة في الأرقام» — M-5.
6. مفتاح `ADMIN_KEY` بلا حدّ أدنى ولا حدّ محاولات، وأسرار المكدس التجريبي في git، وتوقيع الإصدارات بمفتاح debug، ومزوّد واتساب الافتراضي يطبع بيانات العملاء — S-5، S-13، M-2، S-12.

لا توجد نتيجة «حرجة» مؤكدة. التوزيع: عالية 2، متوسطة 8، منخفضة 9.

## جدول النتائج مرتبًا بالخطورة

| # | العنوان | الخطورة | الموضع الرئيسي | الجهد | الحالة |
|---|---|---|---|---|---|
| M-1 | تطبيق المندوب يقبل HTTP في الإصدار (رموز/PIN بنص واضح) | عالية | `mobile/android/app/src/main/AndroidManifest.xml:12`، `mobile/lib/data/cloud_api.dart:56-60` | صغير | مؤكد |
| S-9 | لا حدّ لحجم الجسم، ويُقرأ قبل المصادقة/حدّ المعدل | عالية | `server/lib/src/http/app.dart:229-235`، `admin_routes.dart:102-108` | صغير | مؤكد |
| S-1 | جلسة/جهاز المندوب لا يُبطلان عند تعطيل الموظف؛ لا خروج | متوسطة | `server/lib/src/service/auth_service.dart:105-134,189-195` | صغير | مؤكد |
| S-2 | حدّ الاقتران بعنوان المقبس، في الذاكرة، بلا تنظيف | متوسطة | `server/lib/src/service/rate_limiter.dart:11-23`، `app.dart:224-227` | صغير–متوسط | استنتاج |
| S-5 | `ADMIN_KEY` بلا حدّ أدنى للطول ولا حدّ محاولات | متوسطة | `server/lib/src/http/app.dart:199-204`، `picpos_cloud.dart:53` | صغير | مؤكد |
| S-12 | مزوّد واتساب mock افتراضي يطبع الهواتف والأرصدة | متوسطة | `server/lib/src/whatsapp/whatsapp.dart:54,102-110` | صغير | مؤكد |
| S-13 | أسرار المكدس التجريبي في git ومنفذ Postgres مكشوف | متوسطة | `docker/docker-compose.yml:10-12,37-39` | صغير | مؤكد (الأثر استنتاج) |
| M-2 | توقيع الإصدارات بمفتاح debug | متوسطة | `mobile/android/app/build.gradle.kts:34-39` | صغير | مؤكد |
| M-4 | تخمين PIN المندوب دون اتصال بلا حدود | متوسطة | `mobile/lib/state/app_controller.dart:182-207` | صغير | مؤكد |
| M-5 | الاقتران اليدوي يثق بمفتاح التوقيع من السحابة دون بصمة | متوسطة | `mobile_admin/lib/admin_session.dart:78-83` | صغير–متوسط | مؤكد (السيناريو استنتاج) |
| S-3 | PIN من 4 أرقام بلا قفل على الخادم | منخفضة | `server/lib/src/service/desktop_service.dart:112`، `auth_service.dart:174-183` | صغير | مؤكد |
| S-4 | عداد إخفاقات دخول الإدارة غير ذري | منخفضة | `server/lib/src/service/admin_service.dart:455-471` | صغير | مؤكد |
| S-6 | رموز الاقتران SHA-256 بلا مفتاح | منخفضة | `server/lib/src/service/auth_service.dart:50,70` | صغير | مؤكد |
| S-7 | إعادة الاقتران بـ`device_id` موجود تطرد جهازًا آخر وتلغي إبطاله | منخفضة | `server/lib/src/service/auth_service.dart:78-97` | صغير | مؤكد |
| S-10 | نصوص/مبالغ/تواريخ بلا حدود في مستندات الجوال | منخفضة | `server/lib/src/service/sync_service.dart:614-615,957,1065,1091` | صغير | مؤكد |
| S-11 | إعادة رسالة خطأ PostgreSQL للعميل | منخفضة | `server/lib/src/service/sync_service.dart:497-498` | صغير | مؤكد |
| C-1 | علم `tls` للشبكة المحلية يعلنه الخادم؛ التثبيت غير منفذ | منخفضة | `packages/picpos_api_client/lib/src/transport.dart:103-108,194` | متوسط | مؤكد |
| M-3 | `allowBackup` غير مضبوط في تطبيق المندوب | منخفضة | `mobile/android/app/src/main/AndroidManifest.xml:9-13` | صغير | مؤكد (الأثر استنتاج) |
| M-6 | تطبيق الإدارة بلا قفل تطبيق وبجلسة محفوظة | منخفضة | `mobile_admin/lib/admin_session.dart:44-63` | متوسط | مؤكد |

**حدود المراجعة:** لم أقرأ ملفات الطباعة/الماسح، ولا شاشات تطبيق المندوب غير المتعلقة بالاقتران/المزامنة، ولا `app_controller.dart` بعد السطر 339 إلا عبر grep (لا تخزين أسرار هناك حسب grep)، ولا ملفات الاختبار. لم أتحقق من إعداد الوكيل العكسي/TLS للإنتاج لأنه غير موجود في المستودع (S-2 وS-13 يعتمدان عليه). لم أشغّل أي اختبار.

---

## أ. خادم السحابة `server/`

الملفات المقروءة بالكامل: `server/lib/picpos_cloud.dart`، `server/lib/src/security.dart`، `server/lib/src/http/app.dart`، `server/lib/src/http/admin_routes.dart`، `server/lib/src/db/database.dart`، أجزاء `server/lib/src/db/migrations.dart` (الجداول الأمنية)، `server/lib/src/service/*.dart` كلها، `server/lib/src/whatsapp/whatsapp.dart`، `server/lib/src/seed.dart`، `server/bin/server.dart`، `server/Dockerfile`، `docker/docker-compose.yml`.

### المحور 1 — المصادقة والجلسات (الخادم)

ما فُحص وكان سليمًا:
- رمز الجلسة `body.HMAC-SHA256(secret, body)` مع `exp` و`jti` و`uid/did/cid` (`security.dart:71-111`)، والتحقق بمقارنة ثابتة الزمن (`security.dart:23-30`, `:94`)، ورفض المنتهي (`:97`).
- مفتاح HMAC لجلسات الإدارة منفصل عن جلسات المندوب (`picpos_cloud.dart:83` → `'$tokenSecret|manage'`)، فلا يمكن إعادة استخدام جلسة مندوب على `/manage/*`.
- رموز الأجهزة وروابط سطح المكتب عشوائية 256 بت (`Random.secure`) ويُخزَّن SHA-256 فقط (`auth_service.dart:77,94`، `desktop_service.dart:48-52`)، والمقارنة ثابتة الزمن (`auth_service.dart:115-119`، `admin_service.dart:433`، `desktop_service.dart:70`).
- PIN/كلمة مرور الإدارة: PBKDF2-HMAC-SHA256 بـ120000 تكرار وملح 16 بايت (`security.dart:33-67`)، وحدّ التكرارات للتجزئات المدفوعة من سطح المكتب 1000..1000000 (`admin_service.dart:239-245`).
- رموز الاقتران: 8 أحرف من 32 (~2^40)، صلاحية 10 دقائق، استعمال مرة واحدة مع `FOR UPDATE` داخل معاملة (`auth_service.dart:65-76`، `admin_service.dart:348-355`)، وحدّ 5 محاولات/IP/10 دقائق.
- الجلسة مربوطة بالجهاز والموظف (`auth_service.dart:189-195`)، وجلسة الإدارة مربوطة بالجهاز والمستخدم والشركة وتفحص قائمة الإبطال `admin_session_revocations` وتعيد قراءة المستخدم وصلاحية `mobile_admin_access` في كل طلب (`admin_service.dart:488-504`).
- إبطال جهاز الإدارة تلقائيًا عند تعطيل المستخدم على سطح المكتب (`admin_service.dart:226-234`).
- مفتاح المسؤول `X-Admin-Key` معطّل إذا كان `ADMIN_KEY` فارغًا (`app.dart:199-204`).
- `TOKEN_SECRET` أقصر من 32 حرفًا ⇒ يولَّد سرّ عشوائي بدل سرّ ضعيف (`picpos_cloud.dart:44-51`).

#### S-1 — جلسة المندوب لا تُبطَل عند تعطيل الموظف ولا يوجد خروج/إبطال لها
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/auth_service.dart:105-134` (`authenticateDevice` لا يفحص `employees.is_active`)، `:189-195` (`requireSession` يفحص التوقيع والجهاز فقط)، `server/lib/src/service/desktop_service.dart:568-584` (تحديث الموظف من سطح المكتب بـ`is_active=false` لا يلغي أجهزته — بخلاف مسار الإدارة `admin_service.dart:226-234`).
- **الاستغلال:** مندوب فُصل وعُطّل على سطح المكتب يبقى جهازه مقترنًا وجلسته (12 ساعة، `security.dart:72`) صالحة؛ يستطيع دفع فواتير/تحصيلات/مصروفات (`/mobile/sync/push`) وسحب بيانات العملاء والأرصدة حتى انتهاء الجلسة. `login` وحده يفحص `is_active` (`auth_service.dart:178`). لا يوجد مسار `/mobile/logout` ولا قائمة إبطال لجلسات المندوب (قائمة `admin_session_revocations` للإدارة فقط).
- **التوصية:** في `authenticateDevice` اجلب `e.is_active` بـJOIN وارفض إن كان false؛ أو عند `employee(... is_active=false)` في `_Upsert.employee` نفّذ `UPDATE devices SET revoked_at=... WHERE employee_id=...`. أضف خروجًا وإبطالًا بالـ`jti` لجلسات المندوب على غرار الإدارة.
- **الجهد:** صغير.

#### S-2 — حدّ محاولات الاقتران بحسب عنوان المقبس، في الذاكرة، وبلا تنظيف للمفاتيح
- **الخطورة:** متوسطة · **استنتاج** (يعتمد على طريقة النشر)
- **الموضع:** `server/lib/src/http/app.dart:224-227` و`server/lib/src/http/admin_routes.dart:97-100` (IP = `connectionInfo.remoteAddress`)، `server/lib/src/service/auth_service.dart:60`، `server/lib/src/service/admin_service.dart:343`، `server/lib/src/service/rate_limiter.dart:11-23`.
- **الاستغلال:** (أ) خلف موازن/وكيل عكسي (TLS terminator) يرى الخادم عنوان الوكيل لكل العملاء ⇒ 5 محاولات اقتران خاطئة من أي شخص تحجب الاقتران عن الجميع 10 دقائق (حجب خدمة). (ب) بلا وكيل، يستطيع مهاجم يملك عناوين كثيرة (IPv6) تجاوز الحدّ، وكل IP جديد يضيف مفتاحًا دائمًا إلى `_hits` لأن المفاتيح لا تُحذف أبدًا ⇒ نمو ذاكرة. (ج) الحدّ لكل نسخة (لا يصلح مع عدة نسخ، والتعليق `rate_limiter.dart:3-4` يقرّ بذلك).
- **التوصية:** قراءة `X-Forwarded-For` من وكيل موثوق فقط (قائمة عناوين)، حدّ عام إضافي على `/mobile/pair` و`/manage/pair`، حذف المفاتيح الفارغة بعد `removeWhere`، ونقل الحدود إلى Postgres/Redis قبل التوسع.
- **الجهد:** صغير–متوسط.

#### S-3 — PIN المندوب 4 أرقام مع حدّ 10 محاولات/جهاز/10 دقائق وبلا قفل
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/desktop_service.dart:112` (`^\d{4,8}$`)، `server/lib/src/service/auth_service.dart:174-183`.
- **الاستغلال:** من يملك رمز جهاز مقترن (هاتف مسروق مع استخراج الرمز من التخزين) يجرّب 10 PIN كل 10 دقائق ⇒ مساحة 10^4 تُستنفد في ~7 أيام دون قفل حساب (خلافًا للإدارة التي تقفل بعد 5). الأثر محدود لأن الإبطال اليدوي للجهاز يوقف الهجوم.
- **التوصية:** قفل تصاعدي بعد N إخفاقات لكل موظف/جهاز مع تنبيه في سطح المكتب، أو حدّ أدنى 6 أرقام.
- **الجهد:** صغير.

#### S-4 — عداد إخفاقات دخول الإدارة يُحدَّث بقراءة-ثم-كتابة غير ذرية
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/admin_service.dart:455-471`.
- **الاستغلال:** طلبات متوازية تقرأ `failed_logins` نفسه ثم تكتب `fails` نفسه، فتتجاوز عتبة القفل 5 (يبقى حدّ 10/جهاز/10 دقائق في الذاكرة). يتطلب رمز جهاز إدارة صالحًا.
- **التوصية:** `UPDATE admin_users SET failed_logins = failed_logins + 1 ... RETURNING failed_logins` ثم ضبط القفل ذريًا.
- **الجهد:** صغير.

#### S-5 — مفتاح المسؤول الثابت: بلا حدّ محاولات وبلا حدّ أدنى للطول
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/http/app.dart:199-204`، `server/lib/picpos_cloud.dart:53`؛ المسارات `/admin/pairing-codes`، `/admin/desktop-links` (تصدر بيانات اعتماد سطح مكتب لأي شركة)، `/admin/devices/<id>/revoke` (غير مقيّد بشركة)، `/admin/whatsapp/outbox` (أرقام هواتف كل الشركات) — `app.dart:69-94,140-149`.
- **الاستغلال:** أي قيمة غير فارغة لـ`ADMIN_KEY` مقبولة (المثال في `docker/docker-compose.yml:38` هو `test-admin-key`)، ولا حدّ لمحاولات التخمين. من يخمّن المفتاح يصدر رابط سطح مكتب لأي شركة ثم يقرأ كل مستنداتها ويكتب بياناتها الرئيسية. `constantTimeEquals` يكشف الطول فقط (`security.dart:24`) — ثانوي. التوثيق يصفه بأنه «للمكدس التجريبي» (`server/README.md:98`) لكن المسارات مُركّبة دائمًا متى ضُبط المفتاح.
- **التوصية:** رفض بدء التشغيل إن كان `ADMIN_KEY` أقصر من 32 حرفًا، حدّ معدل على `/admin/*`، تقييد `/admin/*` بشبكة داخلية/علم بيئة `ENABLE_ADMIN_ROUTES`، ومقارنة HMAC للقيمتين بدل المقارنة المباشرة.
- **الجهد:** صغير.

#### S-6 — رموز الاقتران تُخزَّن SHA-256 بلا ملح/مفتاح
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/auth_service.dart:50,70`، `server/lib/src/service/admin_service.dart:299,351`.
- **الاستغلال:** مساحة الرمز 2^40؛ من يقرأ جدول `pairing_codes` (تسرّب نسخة احتياطية) يستعيد رمزًا غير مستخدم خلال دقائق ويقترن قبل انتهاء الدقائق العشر. نافذة الاستغلال ضيقة.
- **التوصية:** `HMAC(TOKEN_SECRET, code)` بدل `sha256Hex(code)`.
- **الجهد:** صغير.

#### S-7 — إعادة الاقتران بـ`device_id` موجود تستولي على سجل جهاز آخر في الشركة نفسها
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/auth_service.dart:78-97`، `server/lib/src/service/admin_service.dart:362-383` (`ON CONFLICT (device_id) DO UPDATE ... revoked_at=NULL`).
- **الاستغلال:** حامل رمز اقتران صالح يرسل `deviceId` لجهاز زميل في الشركة نفسها ⇒ يُستبدل رمز الجهاز وموظفه، ويُطرد الجهاز الأصلي، ويُلغى أيضًا إبطال جهاز مُبطَل سابقًا (`revoked_at=NULL`). يتطلب رمز اقتران ومعرفة `device_id`.
- **التوصية:** رفض الاقتران إن كان `device_id` مملوكًا لجهاز نشط آخر أو لموظف مختلف، واشتراط أن يكون الجهاز المُبطل قد مُسح محليًا (أو توليد `device_id` من الخادم).
- **الجهد:** صغير.

### المحور 2 — التفويض وعزل الشركات (الخادم)

ما فُحص: كل مسار في `app.dart` و`admin_routes.dart`:
- `/mobile/*`: `pair` بلا مصادقة (مقصود)، `login` و`token/rotate` برمز الجهاز، و`bootstrap/pull/push` برمز الجهاز + جلسة (`app.dart:97-137`).
- `/desktop/*`: كلها عبر `_desktop` (رابط + سرّ)، و`companyId` يأتي من الرابط لا من الطلب (`app.dart:150-189`، `admin_routes.dart:27-55`). `revokeDevice` من سطح المكتب مقيّد بـ`companyId` (`app.dart:187`، `auth_service.dart:155-163`)، وكذلك `admin.revokeDevice` (`admin_service.dart:326-332`).
- `/manage/*`: رمز جهاز الإدارة + جلسة؛ `unpair` بالجهاز فقط (مقصود).
- الاستعلامات: كل استعلام قراءة/كتابة يأخذ `company_id` من السياق، أو يعمل على مفاتيح داخلية (`id`) مشتقة من صفوف سبق تقييدها بالشركة (مثل `rep_resources WHERE employee_id=@e` حيث `employee_id` من الجهاز المصادَق عليه، و`inventory_balances` بمعرّف المستودع الخاص بالمندوب). تحققتُ تحديدًا من: `_customerOnRoute` (عميل على خط المندوب اليوم فقط، `sync_service.dart:570-593`)، `_acceptReturn` (الفاتورة بالشركة ثم العميل على الخط، `:877-888`)، `claimBookLeaf` (الدفتر بالشركة + `holder_employee_id`، `field_expenses.dart:29-36`)، `fieldAttachment` (`field_expense_documents.dart:55-58`)، `ack` (`desktop_service.dart:443-463`)، `upsertMaster` (`ON CONFLICT (global_id) ... WHERE <t>.company_id = EXCLUDED.company_id` يمنع الكتابة فوق صفوف شركة أخرى، `desktop_service.dart:524-532`)، وقراءة اللقطات مفلترة بالصلاحية والفرع (`admin_service.dart:136-142,506-533`).
- **لم أجد IDOR ولا استعلامًا بلا شرط شركة يمكن أن يعيد بيانات شركة أخرى.** ملاحظة تصميمية فقط: مفاتيح `global_id` فريدة عالميًا (لا لكل شركة) في جداول مثل `parties`، فرسالة `global_id_conflict` (`field_customers.dart:39-40`) تكشف وجود UUID في شركة أخرى — بلا أثر عملي لأن UUID عشوائية.

- ملاحظة: مسارات `/admin/*` بمفتاح عام واحد غير مقيدة بشركة (مقصود تصميميًا للمكدس التجريبي) — أثرها مغطى في S-5. (الرقم S-8 غير مستخدم.)

### المحور 3 — حقن SQL (الخادم)

ما فُحص: grep على `\$\{`/`$var` داخل نصوص SQL في `server/lib/src/**`. كل القيم تمر كمعاملات `Sql.named` (`database.dart:52-56`). مواضع الاستيفاء النصي الوحيدة:
- `desktop_service.dart:444-462` و`:514` (`$table`, `$extra`) — من خرائط ثابتة `_ackTables` (`:414-421`) وأسماء جداول حرفية في `_ref(...)`؛ مفتاح الخريطة من المستخدم لكن القيمة ثابتة ⇒ آمن.
- `field_geo.dart:61` (`$table`) من `_geoTables` الثابتة ⇒ آمن.
- `auth_service.dart:158` جزء ثابت `AND company_id=@c` ⇒ آمن.
- `sync_service.dart:214,385,573` استيفاء `_scopedCustomersSql` الثابت ⇒ آمن.
- `database.dart:44-45,88` استيفاء اسم المخطط بعد تحقق regex `^[a-z_][a-z0-9_]*$` (`:25-27`)، ومصدره الاختبارات فقط ⇒ آمن.
- **لا توجد نتيجة حقن SQL في الخادم.**

### المحور 4 — التحقق من المدخلات وحجم الجسم وJSON (الخادم)

ما فُحص وكان سليمًا: حدود عدد العناصر (`documents ≤ 50` `app.dart:135`، `results ≤ 500` `:169`، `users ≤ 1000` `admin_service.dart:174`، `items ≤ 200` و`payload ≤ 512KiB` `:248-263`)، حدّ الصورة 1MiB مع فحص طول base64 قبل فك الترميز وتوقيع JPEG (`field_expenses.dart:89-104`)، التحقق من UUID (`sync_service.dart:521-522`)، والأرقام/الإحداثيات (`field_geo.dart:32-43`)، وأخطاء JSON تُعاد `400 invalid_json`.

#### S-9 — لا حدّ لحجم جسم الطلب، ويُقرأ كاملًا قبل المصادقة/حدّ المعدل
- **الخطورة:** عالية · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/http/app.dart:229-235` و`server/lib/src/http/admin_routes.dart:102-108` (`req.readAsString()` ثم `jsonDecode` بلا حدّ)، المسارات غير المصادَقة `app.dart:97-98` (`/mobile/pair`) و`admin_routes.dart:58-59` (`/manage/pair`) — حدّ المعدل يُطبَّق داخل `pair()` بعد قراءة الجسم. لا يوجد middleware لحجم الطلب في `app.dart:52-54` ولا في `bin/server.dart:55`.
- **الاستغلال:** مهاجم مجهول يرسل طلبات `POST /mobile/pair` بأجسام مئات الميغابايت (أو JSON متداخل بعمق كبير) ⇒ استهلاك ذاكرة/معالج في النسخة الوحيدة (`readAsString` يحمّل كل شيء في الذاكرة ثم يُنشئ نسخة UTF-16 ثم شجرة JSON) ⇒ إسقاط الخادم لكل الشركات. كذلك المسارات المصادَقة تقبل `storeSnapshots` حتى 200×512KiB ≈ 100MiB في طلب واحد.
- **التوصية:** middleware يرفض `Content-Length` > حدّ (مثلًا 2MiB عام، 8MiB لـ`/mobile/sync/push` بسبب الصور، 0 لـ GET) ويقرأ التدفق بعدّاد يقطع عند تجاوز الحدّ حتى مع chunked؛ ونقل `_pairLimiter.hit(ip)` إلى ما قبل قراءة الجسم؛ وحدّ في الوكيل العكسي (`client_max_body_size`).
- **الجهد:** صغير.

#### S-10 — حقول نصية/رقمية بلا حدود في مستندات الجوال
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/sync_service.dart:1065,1079` (`note` للزيارة بلا حدّ طول)، `:957,980` (`reason` للمرتجع بلا حدّ)، `:1091-1092` (مبلغ التحصيل بلا حدّ أعلى)، `:614-615` (`date` للمستند أي تاريخ من العميل، ماضٍ أو مستقبل)، `server/lib/src/service/auth_service.dart:62,79-102` (`deviceId`/`deviceName` بلا حدّ طول في اقتران المندوب، بخلاف الإدارة `admin_service.dart:345`)، `server/lib/src/service/admin_service.dart:257-258` (يُعاد `kind`/`scope` المدخل كما هو في رسالة الخطأ — بلا أثر في JSON).
- **الاستغلال:** مندوب (أو رمز مسروق) يملأ الجداول بنصوص ضخمة تصل لاحقًا إلى سطح المكتب في `/desktop/documents/pending`، أو يرسل تحصيلًا بمبلغ هائل يمحو رصيد عميل حتى يراجعه المحاسب، أو يؤرخ مستندات بتاريخ قديم/مستقبلي (التاريخ يدخل في تجزئة النزاهة فيبدو المستند «سليمًا»).
- **التوصية:** `_text(v, max)` لكل نص حر، حدّ أعلى للمبالغ (مثلًا ≤ رصيد العميل + هامش أو سقف لكل شركة)، ورفض `date` خارج نافذة (±N يوم من وقت الخادم)، وحدّ طول `deviceId`/`deviceName` (100/120).
- **الجهد:** صغير.

### المحور 5 — تسريب المعلومات في الأخطاء واللوغ (الخادم)

ما فُحص وكان سليمًا: الاستثناءات غير المتوقعة تُسجَّل في stderr وتُعاد كـ`{"error":"internal_error"}` فقط (`app.dart:246-249`)؛ `/health` لا يكشف خطأ قاعدة البيانات (`app.dart:63-65`)؛ لا يُسجَّل أي رمز/PIN/كلمة مرور؛ سجل التدقيق `audit_log` يخزن `device_id` والـIP فقط.

#### S-11 — إعادة رسالة خطأ PostgreSQL للعميل
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/service/sync_service.dart:493-498` (`'message': e.message` لاستثناء `ServerException` بالرمز 23505).
- **الاستغلال:** تُكشف أسماء القيود/الفهارس الداخلية للعميل (مثل `safe_tx_book_leaf_uq`)، ما يساعد في رسم مخطط القاعدة. الأثر محدود.
- **التوصية:** إعادة `code: 'conflict'` فقط وتسجيل الرسالة في stderr.
- **الجهد:** صغير.

#### S-12 — مزوّد واتساب الافتراضي «mock» يطبع أرقام الهواتف والأرصدة في stdout، ويُختار تلقائيًا
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود**
- **الموضع:** `server/lib/src/whatsapp/whatsapp.dart:54` (`[whatsapp:mock] $template/$language -> $toPhone $params`)، `:102-110` (`providerFromEnv` يعيد Mock عند غياب `WHATSAPP_PROVIDER`)، والمعاملات تتضمن اسم العميل والمبالغ والرصيد (`sync_service.dart:842-849,1120-1125`).
- **الاستغلال:** أي نشر ينسى `WHATSAPP_PROVIDER` يكتب بيانات شخصية ومالية للعملاء (هاتف، اسم، رصيد) في سجلات الحاوية/المجمّع المركزي، ويُعلَّم كل رسالة «sent» دون إرسالها فعليًا. `/health` يكشف اسم المزوّد للعامة (`app.dart:62`).
- **التوصية:** في الإنتاج اشترط ضبط المزوّد صراحة (فشل البدء إن لم يُضبط)، أخفِ الرقم (`+9627*****01`) ولا تطبع `params`، وأزل `whatsappProvider` من `/health` العام.
- **الجهد:** صغير.

### إعدادات النشر المرتبطة بالخادم

#### S-13 — مكدس docker التجريبي: أسرار ثابتة في git ومنفذ Postgres مفتوح وبيانات تجريبية بـPIN معروف
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود** (الأثر الفعلي استنتاج: يعتمد على استعمال الملف خارج الاختبار)
- **الموضع:** `docker/docker-compose.yml:10-12` (Postgres `picpos_test_only` منشور على `55432` لكل الواجهات)، `:37-39` (`TOKEN_SECRET` و`ADMIN_KEY: test-admin-key` و`SEED_DEMO: "true"`)، `server/lib/src/seed.dart:13-14` (PIN `1234`/`5678`)، `server/lib/picpos_cloud.dart:41-42` (كلمة مرور قاعدة افتراضية `picpos` وTLS لقاعدة البيانات معطّل افتراضيًا)، `server/bin/server.dart:55` (HTTP بلا TLS على `0.0.0.0` — يُفترض وجود وكيل TLS، استنتاج).
- **الاستغلال:** تشغيل الملف على خادم متصل بالإنترنت (أو على جهاز في شبكة المتجر؛ Docker على Windows/Linux يتجاوز الجدار الناري عادةً للمنافذ المنشورة) ⇒ دخول مباشر لـPostgres بكلمة مرور معروفة، أو صكّ جلسات بأي `uid/did/cid` بمعرفة `TOKEN_SECRET` المنشور في git، أو إصدار روابط سطح مكتب بالمفتاح `test-admin-key`.
- **التوصية:** ربط المنافذ بـ`127.0.0.1:55432:5432`، نقل الأسرار إلى `.env` غير متتبَّع مع قيم مولّدة، ورفض البدء إذا كان `TOKEN_SECRET`/`ADMIN_KEY` من القيم المعروفة أو `DB_SSL` غير مفعّل خارج وضع الاختبار.
- **الجهد:** صغير.

---

## ب. العميل المشترك `packages/picpos_api_client` و`packages/picpos_device`

الملفات المقروءة: `url_policy.dart`، `transport.dart`، `signature.dart`، `canonical_json.dart`، `manage_client.dart`، `headers.dart`، `mobile_password.dart`، `api_error.dart` (الجزء الخاص بالتعيين)؛ `store/db_key.dart`، `store/sqlcipher_store.dart`، `store/local_store.dart`، `sync/outbox.dart`. لم أقرأ ملفات الطباعة والماسح (`printing/*`، `scan/*`) بالتفصيل — خارج المحاور الأمنية المطلوبة باستثناء grep على اللوغ.

ما فُحص وكان سليمًا:
- **سياسة الروابط:** `UrlPolicy.release` يرفض كل `http` ويقبل `https` فقط، و`development` يسمح بـHTTP لـ`localhost`/`10.0.2.2`/`127/8`/`192.168/16` فقط (`url_policy.dart:20-50`)، ويُطبَّق في منشئ `HttpApiTransport` (`transport.dart:60`). التعليق يوضح صحيحًا أن Dart لا يقرأ `network_security_config`.
- **Ed25519:** المفتاح 32 بايت، التوقيع 64 بايت، ولا استثناء يتسرب من `verify` (`signature.dart:22-49`)؛ JSON قانوني يرفض `double` والمفاتيح غير النصية (`canonical_json.dart:31-70`)؛ `verifySnapshot` يربط `kind/scope/asOf` داخل الحمولة الموقعة فلا يمكن للسحابة نقل حمولة بين فروع/أنواع (`manage_client.dart:155-162`)، وتطبيق الإدارة يعرض `asOf` وتحذير «قديمة» بعد 15 دقيقة وعدد المرفوضات (`mobile_admin/lib/screens/dashboard_page.dart:113-168`) ⇒ التراجع إلى لقطة أقدم مرئي للمستخدم.
- **مقارنة التجزئة على العميل** ثابتة الزمن (`mobile_password.dart:42-47`).
- **مفتاح SQLCipher:** 256 بت من `Random.secure()` في `flutter_secure_storage` 11 (Keystore) (`db_key.dart:39-53`)، قاعدة البيانات في مسار التطبيق الخاص (`sqlcipher_store.dart:26-29`)، وكل الاستعلامات المحلية بمعاملات `whereArgs` (لا حقن SQL محلي).
- **صندوق الصادر:** مفتاح `globalId` ثابت لكل المحاولات (idempotency)، لا إسقاط للمرفوض، ولا تزامن مزدوج (`outbox.dart:46-93`).

#### C-1 — التحقق من TLS الشبكة المحلية (`tls`) قيمة يعلنها الخادم، والتثبيت (pinning) غير منفّذ بعد
- **الخطورة:** منخفضة (حاليًا) · **مؤكد بقراءة الكود**
- **الموضع:** `packages/picpos_api_client/lib/src/transport.dart:103-108,194` (`info.tls` يُقرأ من JSON الخادم)، `:50-51` (التثبيت «يُحقن» عبر `client`، ولا يوجد أي `badCertificateCallback`/`SecurityContext` في الحزم والتطبيقات — بحث grep بلا نتائج).
- **الاستغلال:** في وضع التطوير (`UrlPolicy.development`) يستطيع خادم HTTP على `192.168.x.x` أن يعلن `"tls": true` فيُختار كنقل LAN. في الإصدار يمنع `UrlPolicy.release` أي HTTP، وبدون التثبيت ستفشل شهادات سطح المكتب الموقعة ذاتيًا، لذا لا أثر حالي — لكن الحماية المعلنة في التعليق غير موجودة بعد.
- **التوصية:** اشتقاق `tls` من `baseUri.scheme == 'https'` ونجاح المصافحة المثبّتة لا من JSON، وتنفيذ `HttpClient` مثبّت ببصمة الشهادة من رمز QR قبل تفعيل M-2.
- **الجهد:** متوسط.

---

## ج. تطبيقات الجوال `mobile/` و`mobile_admin/` و`mobile_pos/`

الملفات المقروءة: `AndroidManifest.xml` (main/debug) و`build.gradle.kts` و`network_security_config.xml` (main/debug) للتطبيقات الثلاثة؛ `mobile/lib/main.dart`، `mobile/lib/data/{cloud_api,db_key,sqflite_store}.dart`، `mobile/lib/state/app_controller.dart:1-339`، `mobile/lib/screens/pairing_screen.dart` (grep)؛ `mobile_admin/lib/admin_session.dart`، `mobile_admin/lib/screens/onboarding_screen.dart`؛ `mobile_pos/lib/screens/onboarding_screen.dart` (واجهة فقط، الاقتران غير منفذ — M-5). grep على `print/debugPrint/log` في كل `lib/` للتطبيقات والحزمتين.

### المحور 6 — إعدادات Android وCleartext وexported

ما فُحص وكان سليمًا:
- `mobile_admin` و`mobile_pos`: `usesCleartextTraffic="false"` و`allowBackup="false"` و`networkSecurityConfig` بـ`cleartextTrafficPermitted="false"` في main (`mobile_admin/android/app/src/main/AndroidManifest.xml:23-29`، `.../res/xml/network_security_config.xml:7-9`؛ `mobile_pos/android/app/src/main/AndroidManifest.xml:31-37`)، والسماح بـcleartext موجود فقط في `src/debug/res/xml/network_security_config.xml` (لا يدخل الإصدار)، مع `UrlPolicy.release` في كود Dart لـ`mobile_admin` (`mobile_admin/lib/admin_session.dart:38`).
- `exported="true"` فقط على `MainActivity` (مطلوب لـLAUNCHER) في التطبيقات الثلاثة، ولا مكونات مصدّرة أخرى (receivers/providers/services) في الملفات المصدرية. `mobile_admin` يزيل أذونات البلوتوث غير اللازمة (`:14-17`).
- `key.properties` و`*.jks` و`*.keystore` في `.gitignore:208-212`.

#### M-1 — تطبيق المندوب يقبل HTTP في نسخة الإصدار: الرموز والـPIN وبيانات العملاء بنص واضح
- **الخطورة:** عالية · **مؤكد بقراءة الكود**
- **الموضع:** `mobile/android/app/src/main/AndroidManifest.xml:8-12` (`usesCleartextTraffic="true"` في main لا debug، والتعليق نفسه يقول «Remove for production»)، ولا `networkSecurityConfig`؛ `mobile/lib/data/cloud_api.dart:35-37,56-60` (`http.Client` عادي بلا `UrlPolicy`)؛ `mobile/lib/state/app_controller.dart:156-161` (أي URL يكتبه المستخدم)؛ `mobile/lib/screens/pairing_screen.dart:13` (القيمة الافتراضية `http://10.0.2.2:18080`).
- **الاستغلال:** إن اقترن المندوب بعنوان `http://` (الافتراضي، أو مكدس docker الحالي على `:18080`) فكل طلب يحمل `Authorization: Bearer <deviceToken>` و`X-Session-Token` وجسم `/mobile/login` يحمل الـPIN صريحًا، والردود تحمل قوائم العملاء وأرصدتهم — يلتقطها أي طرف على Wi-Fi عام/شبكة المشغّل/الوكيل، ثم ينتحل الجهاز (الرمز صالح حتى التدوير كل 30 يومًا، `app_controller.dart:69`) ويدفع مستندات مالية. حتى لو أُزيل `usesCleartextTraffic` فإن Dart لا يحترمه (كما يوضح `url_policy.dart:3-5`) فالحماية الوحيدة الفعالة هي سياسة في الكود.
- **التوصية:** استخدام `UrlPolicy.release` من `picpos_api_client` في `HttpCloudApi.pair` وكل الطلبات عند `kReleaseMode`، إزالة `usesCleartextTraffic="true"` من main ونقله إلى `src/debug` مع `network_security_config` على غرار `mobile_admin`، وجعل القيمة الافتراضية `https://`.
- **الجهد:** صغير.

#### M-2 — نسخ الإصدار تُوقَّع بمفتاح debug (دائمًا في تطبيق المندوب، وتلقائيًا عند غياب `key.properties` في الآخرين)
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود**
- **الموضع:** `mobile/android/app/build.gradle.kts:34-39` (`signingConfig = signingConfigs.getByName("debug")` دون شرط)، `mobile_admin/android/app/build.gradle.kts:14-21,58-61` و`mobile_pos/android/app/build.gradle.kts:15-20,60` (رجوع صامت مع تحذير فقط).
- **الاستغلال:** مفتاح debug غير سري (مشترك بين بيئات التطوير وقابل للاستخراج من أي جهاز مطوّر). APK موزع خارج Play (توزيع جانبي للمندوبين — استنتاج) يمكن استبداله بتحديث معدّل موقع بالمفتاح نفسه فيرث بيانات التطبيق (قاعدة SQLCipher ومفاتيح Keystore المرتبطة بالـUID) ويسرّب الرموز.
- **التوصية:** إعداد توقيع إصدار حقيقي للمندوب كالآخرين، وجعل البناء `release` يفشل (`throw GradleException`) عند غياب `key.properties` بدل الرجوع إلى debug (مع خاصية صريحة للتجربة المحلية).
- **الجهد:** صغير.

#### M-3 — `allowBackup` غير مضبوط في تطبيق المندوب (القيمة الافتراضية true)
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود** (الأثر استنتاج)
- **الموضع:** `mobile/android/app/src/main/AndroidManifest.xml:9-13` (لا `allowBackup` ولا `dataExtractionRules`).
- **الاستغلال:** ملفات التطبيق (قاعدة `picpos_van_enc.db` وملف تفضيلات `flutter_secure_storage`) تدخل نسخ Google الاحتياطية ونقل الجهاز. البيانات مشفرة والمفتاح في Keystore غير قابل للتصدير، لذا التسرب المباشر محدود؛ لكن الاستعادة على جهاز آخر تنقل `device_id`/حالة غير متسقة وقد تكشف بيانات وصفية.
- **التوصية:** `android:allowBackup="false"` (و`dataExtractionRules` تستثني كل شيء) كما في `mobile_admin`/`mobile_pos`.
- **الجهد:** صغير.

### المحور 7 — تخزين الأسرار على الجهاز وتسجيلها في اللوغ

ما فُحص وكان سليمًا:
- تطبيق المندوب: رمز الجهاز والجلسة وبيانات العملاء داخل قاعدة SQLCipher (`app_controller.dart:133-139,176-180`)، ومفتاحها في Keystore (`mobile/lib/data/db_key.dart:28-40`)؛ ترحيل القاعدة القديمة غير المشفرة ثم حذفها (`sqflite_store.dart:38-55`)؛ مسح كل البيانات عند `device_revoked` (`app_controller.dart:199,220-228,282-283`)؛ تدوير رمز الجهاز كل 30 يومًا (`:315-323`).
- تطبيق الإدارة: الرابط ورمز الجهاز والجلسة والمفتاح المثبّت في Keystore (`mobile_admin/lib/admin_session.dart:84-91,105`)، مسحها عند الخروج/إلغاء الاقتران/الإبطال (`:127-176`)؛ معرّف الجهاز 128 بت عشوائي آمن (`:67-71`)؛ رفض الاقتران إن اختلف مفتاح QR عن مفتاح السحابة (`:78-81`).
- **اللوغ:** لا يوجد أي تسجيل لرمز أو PIN أو كلمة مرور أو جلسة في `mobile/`، `mobile_admin/`، `mobile_pos/`، أو الحزمتين؛ المواضع الوحيدة `debugPrint` لأخطاء الطباعة والجدولة (`mobile/lib/state/app_controller.dart:543`، `mobile/lib/main.dart:44`، `mobile/lib/printing/print_service.dart:160,174`، `packages/picpos_device/lib/src/printing/print_service.dart:198`).

#### M-4 — PIN المندوب دون اتصال: تخمين غير محدود محليًا
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود**
- **الموضع:** `mobile/lib/state/app_controller.dart:182-207` (عند أي خطأ شبكة يُقارن الـPIN بتجزئة محلية SHA-256×20000 مملحة، بلا عدّاد محاولات ولا قفل ولا تأخير، والمقارنة `!=` نصية).
- **الاستغلال:** من يحصل على هاتف المندوب يفعّل وضع الطيران ويجرب 10^4 PIN من الواجهة (أو بأتمتة إدخال) حتى الدخول، فيرى العملاء والأرصدة وينشئ فواتير/تحصيلات/مصروفات تُدفع لاحقًا تلقائيًا بالجلسة المخزنة أو بعد دخول المندوب. حدّ الخادم (S-3) لا ينطبق هنا.
- **التوصية:** عدّاد إخفاقات محفوظ في القاعدة مع تأخير تصاعدي ومسح البيانات (أو اشتراط دخول متصل) بعد N محاولات، واستخدام PBKDF2 بتكرار أعلى بدل SHA-256 المتكرر.
- **الجهد:** صغير.

#### M-5 — الاقتران اليدوي في تطبيق الإدارة يثق بمفتاح التوقيع القادم من السحابة دون عرض البصمة
- **الخطورة:** متوسطة · **مؤكد بقراءة الكود** (سيناريو الاستغلال استنتاج)
- **الموضع:** `mobile_admin/lib/admin_session.dart:78-83` (`key = offer.desktopSigningKey ?? paired.desktopSigningKey`)، `packages/picpos_api_client/lib/src/manage_client.dart:14-17` (التعليق يعد بـ«shows its fingerprint»، ولا يوجد أي عرض للبصمة في `mobile_admin/lib` — grep على `fingerprint` بلا نتائج)، `server/lib/src/service/admin_service.dart:395` (السحابة تعيد المفتاح)، `:151-160` (أي رابط سطح مكتب للشركة يستبدل المفتاح المخزن على السحابة).
- **الاستغلال:** الغرض من توقيع Ed25519 أن الهاتف لا يثق بالسحابة في الأرقام. في المسار اليدوي (رابط + رمز) يأتي المفتاح من السحابة نفسها؛ فسحابة مخترقة، أو من يملك سرّ أي رابط سطح مكتب للشركة (يستبدل `signing_public_key` قبل الاقتران)، أو خادم وسيط على نطاق مشابه يمرر الاقتران، يستطيع تثبيت مفتاحه وتقديم لوحات أرقام مزوّرة «موثقة» للمالك.
- **التوصية:** عرض بصمة قصيرة للمفتاح بعد الاقتران اليدوي ومطالبة المستخدم بمطابقتها مع شاشة سطح المكتب، أو جعل QR المسار الوحيد في الإصدار؛ وعلى الخادم منع استبدال `signing_public_key` لرابط آخر دون إجراء إداري.
- **الجهد:** صغير–متوسط.

#### M-6 — تطبيق الإدارة بلا قفل تطبيق وبجلسة محفوظة
- **الخطورة:** منخفضة · **مؤكد بقراءة الكود**
- **الموضع:** `mobile_admin/android/app/src/main/AndroidManifest.xml:9` (إذن `USE_BIOMETRIC` مُعلن)، بينما لا توجد مكتبة `local_auth` ولا أي استخدام لها في `mobile_admin/lib` (grep)، والجلسة تُستعاد تلقائيًا من Keystore عند الفتح (`mobile_admin/lib/admin_session.dart:44-63`)؛ لا `FLAG_SECURE` للوحات المالية.
- **الاستغلال:** أي شخص يمسك الهاتف وهو غير مقفل يفتح لوحة الأرباح والنقدية والموافقات حتى انتهاء الجلسة (12 ساعة)، وتظهر الأرقام في لقطات الشاشة/معاينة التطبيقات الحديثة.
- **التوصية:** قفل بيومتري/رمز عند الفتح والعودة من الخلفية (المخطط في ARCHITECTURE-M M-1 حسب تعليق المانيفست)، و`FLAG_SECURE` على شاشات الأرقام.
- **الجهد:** متوسط.

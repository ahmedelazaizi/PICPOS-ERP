# مراجعة أمنية — الجزء 3 من 3: الأسرار، تاريخ git، التبعيات، CI، قاعدة البيانات المحلية، البنية التحتية

> الحالة: **مكتمل** (المحاور 1–7).
> نوع المراجعة: قراءة فقط — لم يُعدَّل أي ملف عدا هذا التقرير، ولم يُشغَّل `flutter test` ولا `dart test`.
> الفرع المفحوص: `go/full-remediation` @ `b0aaad84` (مطابق لـ`origin/main`).

## الملخص

- **لا نتيجة «حرجة»:** لم يُعثر في أي commit مرفوع إلى GitHub على مفتاح خاص حقيقي أو توكن سحابي (AWS/GitHub/Stripe/Slack/Google/Supabase service_role/JWT) أو ملف توقيع (`.jks`/`.keystore`/`key.properties`/`google-services.json`/`.pem`/`.p12`/`.env`). المفتاح الخاص للترخيص `tools/picpos-activation/license_private_key.txt` **غير متتبَّع ومُتجاهَل ولم يدخل التاريخ قط**.
- **ما تسرّب فعلًا إلى `origin/main`:** كلمة مرور PostgreSQL محلية حقيقية لحساب `postgres` (S-01، وما زالت في 4 ملفات docs حالية) وملح الترخيص المتماثل القديم الذي يسمح بتوليد مفاتيح تفعيل للإصدارات السابقة لـ2026-09-27 (S-02، وما زال في 5 ملفات docs حالية).
- **أخطر ما وُجد تصميمي لا تسريبي:** مفتاح SQLCipher مشتق حتميًا من `deviceId` + ثابت منشور في الكود (E-01)، **ويُعاد استخدامه** جذرًا لتوكن LAN ولمفتاح توقيع الجلسات (E-02) — فمن يعرف معرّف جهاز الخادم يفك القاعدة ويسكّ جلسة مدير. يضاف إليه إعادة إنشاء `admin/admin` صامتة بلا إلزام بالتغيير (S-04)، وتثبيت شهادة الناشر في مخزن Root على أجهزة العملاء (B-01).
- سلسلة التوريد: حزمة `sqlcipher_flutter_libs` منتهية الدعم ومتعارضة مع `sqlite3 3.x` (D-01) يرقّعها سكربت بناء غير مستعمل في CI (C-01)؛ Actions بوسوم متحركة (C-02)؛ لا توقيع Authenticode (B-02).

### جدول النتائج (مرتّب بالخطورة)

| المعرّف | العنوان | الخطورة | الموضع الرئيسي | مؤكد/استنتاج | الجهد |
|---|---|---|---|---|---|
| E-01 | مفتاح SQLCipher = SHA256(deviceId + pepper ثابت في الكود) | عالية | [security_service.dart:433-458](<../../lib/services/security_service.dart#L433-L458>) | مؤكد (مصدر deviceId استنتاج) | متوسط |
| E-02 | مفتاح القاعدة نفسه جذر توكن LAN وHMAC الجلسات وتوكن الطاولات | عالية | [network_service.dart:763-773](<../../lib/services/network_service.dart#L763-L773>) | مؤكد | متوسط |
| S-04 | إعادة إنشاء `admin/admin` صامتة بلا `force_password_change` | عالية | [main.dart:1077-1081](<../../lib/main.dart#L1077-L1081>)، [api_handler.dart:1947-1963](<../../lib/services/api/api_handler.dart#L1947-L1963>)، [database_startup.dart:1242-1266](<../../lib/data/database/database_startup.dart#L1242-L1266>) | مؤكد | صغير |
| B-01 | المثبّت يضيف شهادة الناشر إلى Root | عالية | [setup.iss:226-231](<../../installer/setup.iss#L226-L231>) | مؤكد (أثر MITM استنتاج) | متوسط |
| S-01 | كلمة مرور `postgres` حقيقية في التاريخ والشجرة الحالية | متوسطة | `5ecc0e0f`؛ [2026-full-project-audit.md:193](<../audit/2026-full-project-audit.md#L193>) | مؤكد | صغير |
| S-02 | ملح الترخيص القديم منشور → مفاتيح للإصدارات القديمة | متوسطة | `79a1ceaf`…`35a1b50a`؛ [HANDOFF.md:112](<../handoff/HANDOFF.md#L112>) | مؤكد | صغير/متوسط |
| S-05 | `--reset-admin-password`/`URAL_RESET_ADMIN_PASSWORD`/`--purge-users` بلا مصادقة | متوسطة | [main.dart:710-738](<../../lib/main.dart#L710-L738>) | مؤكد | متوسط |
| E-03 | كلمات مرور الأقسام نصّ صريح وتُسلَّم عبر `GET /api/settings` | متوسطة | [security_gate_wrapper.dart:39-107](<../../lib/presentation/widgets/auth/security_gate_wrapper.dart#L39-L107>)، [setting_sync_strategy.dart:61-67](<../../lib/services/sync/strategies/setting_sync_strategy.dart#L61-L67>) | مؤكد | صغير–متوسط |
| E-04 | Argon2id بـ4MiB؛ الهاش القديم يبقى مقبولًا | متوسطة | [security_service.dart:142-145](<../../lib/services/security_service.dart#L142-L145>) | مؤكد | صغير |
| E-05 | النسخ الاحتياطية = نسخ ملف مرتبط بمفتاح الجهاز | متوسطة | [connection_io.dart:387-424](<../../lib/data/database/connection_io.dart#L387-L424>) | مؤكد (فقدان الاستعادة استنتاج) | متوسط |
| D-01 | `sqlcipher_flutter_libs 0.6.8` EOL ومتعارضة مع `sqlite3 3.3.1` | متوسطة | [pubspec.yaml:39](<../../pubspec.yaml#L39>) | مؤكد | متوسط |
| C-01 | بناء الإصدار في CI بلا علامة/فرض SQLCipher/توقيع | متوسطة | [ci.yml:623-627](<../../.github/workflows/ci.yml#L623-L627>) | مؤكد (النتيجة الثنائية استنتاج) | صغير–متوسط |
| C-02 | Actions بوسوم متحركة (منها أطراف ثالثة بصلاحية كتابة) | متوسطة | [ci.yml:71](<../../.github/workflows/ci.yml#L71>)، [:673](<../../.github/workflows/ci.yml#L673>) | مؤكد | صغير |
| I-01 | منافذ Docker على `0.0.0.0` مع اعتمادات معروفة | متوسطة | [docker-compose.yml:10-42](<../../docker/docker-compose.yml#L10-L42>) | مؤكد | صغير |
| B-02 | لا توقيع Authenticode | متوسطة | [setup.iss:21-23](<../../installer/setup.iss#L21-L23>) | مؤكد | متوسط |
| B-03 | تنزيل وتنفيذ كمدير بلا بصمة؛ PostgreSQL 16.4 | متوسطة | [setup.iss:337-339](<../../installer/setup.iss#L337-L339>) | مؤكد (CVE استنتاج) | صغير |
| S-03 | أدوات keygen و`.exe` في وسوم محلية غير مرفوعة | منخفضة | `7c5f05c4`، `b6a732d7` | مؤكد | صغير |
| S-06 | مفتاح الترخيص الخاص و`key.properties` و`key.pem` داخل مجلد العمل | منخفضة | [generate_keypair.dart:14-24](<../../tool/license/generate_keypair.dart#L14-L24>) | مؤكد | صغير |
| S-07 | فجوات `.gitignore`/`check_no_secrets.ps1` (`.pem/.p12/.pfx/.env`) | منخفضة | [check_no_secrets.ps1:11](<../../tool/check_no_secrets.ps1#L11>) | مؤكد | صغير |
| L-01 | ملفات `.txt` كبيرة في الجذر غير مُتجاهَلة | منخفضة | الجذر | مؤكد | صغير |
| L-02 | دليل حسابات و`.bak` متتبَّعة | منخفضة | `invoice_templates/design/uploads/` | استنتاج | صغير |
| L-03 | `server_errors.log` يكتب وسائط SQL نصًّا | منخفضة | [connection_io.dart:182-193](<../../lib/data/database/connection_io.dart#L182-L193>) | مؤكد | صغير |
| E-06 | كلمة مفتاح TLS في SharedPreferences | منخفضة | [network_service.dart:582](<../../lib/services/network_service.dart#L582>) | مؤكد | صغير |
| E-07 | مقارنة نصّية لكلمة المدير القديمة | منخفضة | [admin_password_service.dart:125-129](<../../lib/services/admin_password_service.dart#L125-L129>) | مؤكد | صغير |
| D-02 | حزم زائدة/قديمة (supabase، ftp، secure_storage 9، packages/core) | منخفضة | [pubspec.yaml](<../../pubspec.yaml>) | مؤكد/استنتاج | صغير–متوسط |
| D-03 | صور Docker غير مثبّتة بـdigest | منخفضة | [server/Dockerfile](<../../server/Dockerfile>) | مؤكد | صغير |
| C-03 | gitleaks استشاري فقط | منخفضة | [ci.yml:56-74](<../../.github/workflows/ci.yml#L56-L74>) | مؤكد | صغير |
| C-04 | تشغيل مزدوج push/PR، كاش | منخفضة | [ci.yml:6-10](<../../.github/workflows/ci.yml#L6-L10>) | استنتاج | صغير |
| I-02 | `DB_PASSWORD` افتراضي `'picpos'` في الخادم السحابي | منخفضة | [picpos_cloud.dart:41](<../../server/lib/picpos_cloud.dart#L41>) | مؤكد | صغير |
| B-04 | ملاحظات سكربتات البناء | منخفضة | [build_picpos.bat](<../../build_picpos.bat>) | مؤكد | صغير |

### أولويات مقترحة
1. تدوير كلمة مرور `postgres` (S-01) وكلمات `key.properties` (S-06) فورًا، وحذف القيم من ملفات docs (S-01، S-02).
2. إصلاح S-04 (سطر `force_password_change` في ثلاثة مواضع) — أصغر جهد لأكبر أثر.
3. فصل أسرار الـAPI عن مفتاح القاعدة (E-02) ثم الانتقال لمفتاح SQLCipher عشوائي محفوظ بـDPAPI مع `PRAGMA rekey` (E-01).
4. إيقاف تثبيت الشهادة في Root (B-01) والحصول على توقيع كود معتمد (B-02).
5. تثبيت Actions بـSHA وجعل gitleaks حاجزًا (C-02، C-03)، وتوحيد بناء CI مع `build_picpos.bat` (C-01)، ثم الهجرة إلى `sqlite3` 3.x (D-01).

## سياق التسريب (مهم لتفسير كل نتيجة «في التاريخ»)

- `git ls-remote --heads --tags origin` (نُفِّذ فعلًا) أرجع مرجعًا **واحدًا فقط**: `refs/heads/main` @ `b0aaad84`. أي أن المرفوع إلى GitHub (`ahmedelazaizi/PICPOS-ERP`، خاص) هو تاريخ `main` فقط: **1175 commit** (`git rev-list --count origin/main`).
- محليًا يوجد **2088 commit** عبر كل المراجع (`git rev-list --count --all`): 75 فرعًا محليًا، 23 وسمًا، `refs/stash`، و`refs/original/refs/heads/feat/lite-profile-and-pos-ui` (أثر `git filter-branch` سابق). **الوسوم والفروع المحلية غير مرفوعة** وقت الفحص، ومن ثَمّ فالـcommits غير القابلة للوصول من `origin/main` (منها جذر التاريخ القديم `7c5f05c4` «URAL-ERP baseline» و`b6a732d7`) **ليست مسرَّبة إلى GitHub** — لكنها ستُسرَّب فور أي `git push --tags` أو `git push --all`.
- كل نتيجة أدناه تحمل وسم «على origin/main» (= مسرَّب للريبو الخاص على GitHub ولكل من له صلاحية قراءة عليه ولكل نسخة مستنسخة) أو «محلي فقط».
- **سياسة التنقيح في هذا التقرير:** لا تُكتب قيم الأسرار الحقيقية هنا (يُشار إليها بـ`<REDACTED>`/`<LEGACY_SALT>`) حتى لا يصبح التقرير نفسه نسخة جديدة منها — باستثناء ما هو **منشور أصلًا** في ملفات متتبَّعة على `origin/main` ويُذكر موضعه فقط.

---

## المحور 1 — الأسرار في الملفات المتتبَّعة وفي تاريخ git

### ما فُحص (الأوامر والأنماط)

- `git log --all --no-textconv -S<p>` لكل من: `BEGIN PRIVATE KEY`، `BEGIN RSA`، `BEGIN EC PRIVATE`، `BEGIN OPENSSH`، `AKIA`، `ghp_`، `github_pat_`، `sk_live`، `sk_test`، `service_role`، `xoxb-`، `AIza`، `SUPABASE_KEY`، `SUPABASE_ANON`، `storePassword`، `keyPassword`، و`<قيمة كلمة مرور PG المكتشفة في S-01>` لتتبّع مداها. (المحاولة الأولى بدون `--no-textconv` فشلت جزئيًا على ملف `.doc` بسبب `docx2txt.exe` غير موجود، فأُعيد الكل بـ`--no-textconv`.)
- `git log --all --no-textconv -G` بتعابير: JWT (`eyJ…\.eyJ`)، `password = '…'`، روابط `postgres://user:pass@`. (تعبيرا `secret=`/`api_key` فشلا بسبب اقتباس PowerShell؛ عُوِّضا ببحث الشجرة الحالية بأداة Grep على `(password|passwd|pwd|secret|token|apikey|api_key)\s*[=:]\s*…` في `*.{bat,ps1,sh,iss,sql,yml,yaml,json,py,toml,env,properties,cfg,ini,xml}`.)
- `git log --all --diff-filter=A --name-only` مع تصفية على `.jks .keystore .pem .p12 .pfx .env key.properties google-services.json GoogleService-Info license_private private_key .sqlite .db .log secret` → **لا ملف من هذه الأنواع أُضيف في أي commit** (الناتج الوحيد `tool/check_no_secrets.ps1` وهو سكربت فحص).
- `git log --all -- tools/picpos-activation …` و`git check-ignore -v`.
- قراءة: `.env.example`، `.gitleaks.toml`، `tool/check_no_secrets.ps1`، `docker/docker-compose.yml`، `web_app/supabase_migration.sql`، `supabase/migrations/*`، `lib/services/license_service.dart`.

### نتائج «نظيفة» (لا مشكلة)

- `BEGIN PRIVATE KEY`: الإصابة الوحيدة على `origin/main` هي [network_service_tls_test.dart](<../../test/services/network_service_tls_test.dart>) (`'-----BEGIN PRIVATE KEY-----\nfake\n'`) — **وهمي** لاختبار.
- `AKIA`: إصابات في `docs/USER-GUIDE/index.html` (commit `aaffd417`) وفي `tools/postgresql-18.3-2-windows-x64.exe` (commit `7c5f05c4`) — **إيجابيات كاذبة** (بيانات base64 لخط/ثنائي)، وكلا الـcommitين **محلي فقط** (موجودان في الوسوم `v3.1.0`… و`phase-5-complete`… وغير قابلين للوصول من `origin/main`).
- `service_role`/`SUPABASE_ANON`: تعليقات و`--dart-define=SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}` وقيم `defaultValue: ''` — لا مفتاح حقيقي. لا JWT (`eyJ…`) في أي commit.
- `ghp_`، `github_pat_`، `sk_live`، `sk_test`، `xoxb-`، `AIza`، `BEGIN RSA/EC/OPENSSH`: **صفر** إصابات في كل المراجع.
- [.env.example](<../../.env.example>) قيم نائبة فقط (`your-anon-key-here`).
- **`tools/picpos-activation/license_private_key.txt`**: **غير متتبَّع** (`git ls-files` فارغ)، **مُتجاهَل** بـ[.gitignore:191](<../../.gitignore#L191>) (`tools/picpos-activation/`)، و**لم يدخل التاريخ قط** (`git log --all -- tools/picpos-activation` فارغ على كل المراجع). ← انظر S-06 لملاحظة التخزين المحلي.
- ملفات التوقيع: `key.properties` لتطبيقَي الجوال **غير متتبَّعة ولم تدخل التاريخ** (`git log --all -- '*key.properties' '*.jks' '*.keystore'` فارغ)، و`storeFile` يشير إلى `D:/PICPOS-KEYS/…` خارج الريبو.
- المفتاح العام للترخيص `_licensePublicKeyB64` في [license_service.dart:82-83](<../../lib/services/license_service.dart#L82-L83>) مفتاح Ed25519 **عام** — وجوده في الكود صحيح.

### S-01 — كلمة مرور PostgreSQL حقيقية (مستخدم `postgres` الخارق) مسرَّبة في التاريخ وما زالت في الشجرة الحالية
- **الخطورة:** متوسطة (ترتفع إلى عالية إن كانت الكلمة نفسها مستخدمة على أي خادم آخر أو كان PG على جهاز المطوّر يستمع على الشبكة).
- **الموضع (مؤكد):**
  - أُضيفت قيمةً افتراضية إلى `scripts/gate.sh` في commit `5ecc0e0f` (2026-08-05) وأزيلت من السكربت في `e48da555` (2026-09-27) — كلاهما على `origin/main`. الحالي [gate.sh:511](<../../scripts/gate.sh#L511>) سليم (`${PG_TEST_DSN:?…}`).
  - **ما زالت في الشجرة الحالية (HEAD = origin/main):** [2026-08-04-road-to-go.md:194](<../superpowers/handoff/2026-08-04-road-to-go.md#L194>)، [2026-08-05-reports-a4-payroll.md:233](<../superpowers/handoff/2026-08-05-reports-a4-payroll.md#L233>)، و**تقرير التدقيق نفسه** [2026-full-project-audit.md:193](<../audit/2026-full-project-audit.md#L193>) و[:338](<../audit/2026-full-project-audit.md#L338>) الذي يقتبس الرابط كاملًا `postgres://postgres:<…>@127.0.0.1:5432/picpos`.
  - Commits أخرى على `origin/main` تحويها: `62c048a9`، `199f682f`، `4830f02e`.
- **الأثر:** كلمة مرور قصيرة (رقمية من 5 خانات) لحساب `postgres` الخارق على قاعدة اختبار محلية. كل من يقرأ الريبو على GitHub يعرفها. الخطر الفعلي يعتمد على `listen_addresses`/`pg_hba.conf` على جهاز المطوّر وعلى إعادة استخدام الكلمة. التقرير السابق أوصى بتغييرها لكن **لا دليل في الريبو على أنها غُيّرت**، وأُعيد نشرها داخل التقرير الذي أوصى بإزالتها.
- **التوصية:** (1) تغيير كلمة مرور `postgres` على كل جهاز استُخدمت فيه فورًا؛ (2) استبدالها في الملفات الأربعة بـ`<password>`؛ (3) إعادة كتابة التاريخ (`git filter-repo --replace-text`) اختيارية بعد التدوير — التدوير هو العلاج الحقيقي.
- **الجهد:** صغير (تدوير + تعديل 4 أسطر)؛ متوسط إن أُعيدت كتابة التاريخ.

### S-02 — ملح الترخيص القديم (المتماثل) منشور في الشجرة والتاريخ → توليد مفاتيح تفعيل لكل الإصدارات قبل `35a1b50a`
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** الثابت `_secretSalt` كان في `lib/services/license_service.dart` منذ أول commit مرفوع `79a1ceaf` (2026-07-13) حتى `35a1b50a` (2026-09-27، `git show 35a1b50a^:lib/services/license_service.dart` السطر 20). وما زالت القيمة **حرفيًا** في الشجرة الحالية في: [2026-full-project-audit.md:187](<../audit/2026-full-project-audit.md#L187>) و[:392](<../audit/2026-full-project-audit.md#L392>)، [HANDOFF.md:112](<../handoff/HANDOFF.md#L112>)، [2026-07-27-picpos-screens-redesign.md:1129](<../superpowers/plans/2026-07-27-picpos-screens-redesign.md#L1129>)، [2026-09-01-saas-web-design.md:152](<../superpowers/specs/2026-09-01-saas-web-design.md#L152>). (تحقّقتُ بمطابقة نصية مع الملح في أداة التوليد المحلية دون طباعته.)
- **الأثر:** المفتاح القديم = أول 16 خانة من `sha256(machineId + salt)`. أي شخص لديه الريبو يولّد مفتاح تفعيل صالحًا لأي تنصيبة تعمل بإصدار **أقدم من `35a1b50a`**. الإصدارات الحالية محمية: [license_service.dart:21-57](<../../lib/services/license_service.dart#L21-L57>) لا تقبل إلا `PP2-` موقَّعًا بـEd25519. وبالمثل كان سر سلامة الفواتير `UralCash-ERP-Integrity-v1` ثابتًا (`35a1b50a^:lib/services/invoice_integrity_service.dart:11`) → تزوير بصمة سلامة الفواتير ممكن على الإصدارات القديمة.
- **التوصية:** دفع التحديث لكل العملاء على إصدارات ما قبل 2026-09-27 (الإبطال الحقيقي)؛ حذف القيمة من ملفات docs الخمسة (استبدالها بـ`<LEGACY_SALT>`).
- **الجهد:** صغير (docs) / متوسط (ترقية العملاء).

### S-03 — أداة توليد المفاتيح القديمة والـ`.exe` في تاريخ محلي غير مرفوع
- **الخطورة:** منخفضة (حاليًا) — تصبح متوسطة لو دُفعت الوسوم.
- **الموضع (مؤكد):** `tools/keygen.dart`، `tools/keygen.exe`، `tools/gkeygen.exe`، `tools/UralCash_License_Tool.{dart,exe}`، `tools/license.txt`، `tools/test_license.dart` أُضيفت في `7c5f05c4` (2026-04-28) وحُذفت في `b6a732d7` «purge tracked credential tooling and backdoor seeds». **كلاهما غير قابل للوصول من `origin/main`** لكنهما محفوظان في الوسوم المحلية (`git for-each-ref --contains 7c5f05c4` → `phase-5-complete`، `v005-coa-hardening`، `v132`…؛ و`aaffd417` في `v3.1.0`، `v3.1.1`). كذلك `tools/postgresql-18.3-2-windows-x64.exe` (354MB) في `7c5f05c4`.
- **الأثر:** لا تسريب حاليًا إلى GitHub. أي `git push --tags` أو `--mirror` سيرفع أدوات توليد المفاتيح وبذور «الباب الخلفي» القديمة.
- **التوصية:** عدم دفع الوسوم القديمة أبدًا؛ أو حذف الوسوم المحلية التي تحتوي `7c5f05c4` (بعد أرشفتها خارج الريبو)، وإضافة حماية push للوسوم.
- **الجهد:** صغير.

### S-04 — كلمات مرور افتراضية `admin/admin`: إعادة إنشاء صامتة للمدير بكلمة معروفة ودون إلزام بتغييرها
- **الخطورة:** عالية.
- **الموضع (مؤكد بقراءة الكود):**
  - [main.dart:846-847](<../../lib/main.dart#L846-L847>) يستدعي `_bootTimeAdminHeal` في كل إقلاع على الخادم/الوضع المستقل؛ [main.dart:1077-1081](<../../lib/main.dart#L1077-L1081>): إن **لم يوجد مستخدم اسمه `admin`** يُستدعى `_resetAdminPasswordToDefault` الذي يُدرج `admin`/`admin` بدور «مدير النظام» [main.dart:1217-1235](<../../lib/main.dart#L1217-L1235>) **دون** `force_password_change` (والعمود افتراضه `false`).
  - مسار ثانٍ عبر الشبكة: [api_handler.dart:1947-1963](<../../lib/services/api/api_handler.dart#L1947-L1963>) (`_ensureBootstrapAdminOnce` عند أول `GET /api/users` في كل عملية) يُدرج `admin`/`admin` بـ`roleId: 1` دون `force_password_change`.
  - مسار ثالث: [database_startup.dart:1242-1266](<../../lib/data/database/database_startup.dart#L1242-L1266>) `_createFallbackAdmin` (نفس الشيء).
  - في المقابل المُبذِر الأساسي [database_seeder.dart:45-51](<../../lib/data/database/database_seeder.dart#L45-L51>) يضبط `force_password_change = true` — أي أن المسارات الثلاثة أعلاه تتجاوز الحماية التي أُضيفت عمدًا.
- **الأثر:** خطوة تقوية شائعة (إعادة تسمية حساب `admin` أو حذفه بعد إنشاء مدير باسم آخر) **تُلغى تلقائيًا** عند الإقلاع التالي بحساب مدير كامل كلمة مروره `admin` معروفة للجميع (موثّقة في الريبو)، ولا يُجبَر على تغييرها. على PostgreSQL المشترك يطال كل الفروع.
- **التوصية:** المسارات الثلاثة يجب أن تضبط `force_password_change = true` على الأقل؛ والأفضل ألّا تُنشئ «admin» إذا وُجد أي مستخدم فعّال بدور مدير النظام، واستخدام كلمة عشوائية تُعرض مرة واحدة للمشغّل.
- **الجهد:** صغير.

### S-05 — مفاتيح استعادة عبر سطر الأوامر/متغيرات البيئة بلا مصادقة
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [main.dart:710-738](<../../lib/main.dart#L710-L738>): `--reset-admin-password` أو `URAL_RESET_ADMIN_PASSWORD=1` → إعادة `admin/admin` وفك القفل؛ `--purge-users` أو `URAL_PURGE_USERS=1` → `DELETE FROM users` ثم إعادة بذر `admin/admin`؛ و[developer_auth_service.dart:154-164](<../../lib/services/developer_auth_service.dart#L154-L164>): `--reset-dev-password`/`URAL_RESET_DEV_PASSWORD=1` يمسح كلمة مرور المطوّر.
- **الأثر:** أي مستخدم ويندوز محلي يستطيع تشغيل الـexe (أو برمجية خبيثة بصلاحيات مستخدم عادي تضبط متغير بيئة مستخدم دائم) يستولي على حساب المدير، وفي وضع PostgreSQL يطال القاعدة المشتركة. لا يوجد إثبات حضور مالك (مثل مفتاح استرداد أو تأكيد من حساب مدير ويندوز).
- **التوصية:** حصر الاسترداد بأداة منفصلة تتطلب صلاحيات مدير نظام التشغيل أو «رمز استرداد» يُولَّد عند التنصيب؛ إزالة مسار متغيرات البيئة؛ سجل تدقيق `critical` (موجود لكلمة المطوّر فقط).
- **الجهد:** متوسط.

### S-06 — أسرار تشغيلية محفوظة نصًا صريحًا داخل مجلد العمل (غير متتبَّعة)
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** `tools/picpos-activation/license_private_key.txt` (43 بايت — مفتاح Ed25519 الخاص للترخيص، بحسب [tool/license/generate_keypair.dart](<../../tool/license/generate_keypair.dart>)) بجانب `picpos-key-generator.html` (أداة الملح القديم)؛ و`mobile_admin/android/key.properties` و`mobile_pos/android/key.properties` بكلمات مرور keystore صريحة (وكلمة المخزن = كلمة المفتاح في كلٍّ منهما).
  - التصميم يفرض ذلك: [generate_keypair.dart:14-19](<../../tool/license/generate_keypair.dart#L14-L19>) **يرفض** كتابة المفتاح الخاص خارج `tools/picpos-activation/` داخل الريبو، ويكتبه نصًّا غير مشفّر (السطر 24).
  - وبالمثل [generate_self_signed_cert.ps1:48-50](<../../scripts/generate_self_signed_cert.ps1#L48-L50>) يكتب افتراضيًا `key.pem` (مفتاح TLS لخادم LAN، بلا كلمة مرور `-nodes`) إلى `scripts/certs/` داخل الريبو، وهذا المسار **غير مُتجاهَل** (`git check-ignore scripts/certs/key.pem` → exit 1)، فـ`git add -A` سيضيفه.
- **الأثر:** لا تسريب في git (مؤكد). لكن أي نسخ احتياطي/مزامنة سحابية لمجلد `D:\PICPOS-ERP`، أو `git add -f`، أو أداة/وكيل يقرأ الشجرة (أداة Grep في هذه المراجعة نفسها أظهرت قيم `key.properties`) يكشف المفتاح الخاص للترخيص الذي يسمح بسكّ تراخيص لكل العملاء.
- **التوصية:** نقل `license_private_key.txt` خارج الريبو (مثل `D:\PICPOS-KEYS\` بجانب الـjks) ويُفضَّل تشفيره (DPAPI/مدير كلمات مرور/مفتاح عتادي)؛ استخدام كلمة مخزن مختلفة عن كلمة المفتاح. **وبما أن قيم `key.properties` ظهرت في سجل هذه الجلسة، يُستحسن تدويرها** (كلمات upload keystore قابلة للتغيير عبر `keytool -storepasswd/-keypasswd`).
- **الجهد:** صغير.

### S-07 — فجوات في أدوات منع الأسرار
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [check_no_secrets.ps1:11](<../../tool/check_no_secrets.ps1#L11>) يفحص فقط `key.properties|google-services.json|*firebase-adminsdk*.json|*.jks|*.keystore` — لا يشمل `*.pem`، `*.p12`، `*.pfx`، `.env`، `license_private_key*`. و[.gitignore](<../../.gitignore>) يتجاهل `*.jks`/`*.keystore`/`key.properties`/`.env` لكن **لا يتجاهل** `*.pem`/`*.p12`/`*.pfx` (شهادات TLS لخادم LAN تُحمَّل من ملفات — `network_service.dart`). gitleaks (انظر المحور 5) يغطي المحتوى لكنه لم يمنع S-01 لأن نمط كلمة مرور قصيرة داخل رابط في Markdown لا يطابق القواعد الافتراضية (استنتاج).
- **التوصية:** إضافة الامتدادات الناقصة إلى `.gitignore` و`check_no_secrets.ps1`؛ قاعدة gitleaks مخصصة لـ`postgres(ql)?://[^:]+:[^@]+@`.
- **الجهد:** صغير.

---

## المحور 2 — السجلات والملفات الناتجة

### ما فُحص
- `git ls-files` مع تصفية `\.(log|db|sqlite|sqlite3|db-wal|db-shm|bak|dump|csv)$` و`*.txt`.
- `git log origin/main --diff-filter=A --name-only` مع تصفية `\.(log|db|sqlite|…|exe|dll|zip|xlsx)$`.
- `git status --ignored --short` للجذر، وفحص محتوى السجلات المحلية بأداة Grep على `Bearer <token>`، `PRAGMA key = '<hex>`، `x-session-token:`، `eyJ…`.

### النتائج
- **لا ملف `.log` أو `.db`/`.sqlite` متتبَّع ولا في تاريخ `origin/main`** (مؤكد). [.gitignore:3](<../../.gitignore#L3>) `*.log`، [:100-101](<../../.gitignore#L100-L101>) `*.sqlite`/`*.db`، [:128](<../../.gitignore#L128>) `flutter_*.log`، [:118](<../../.gitignore#L118>) `build_*.log`.
- `flutter_01..47.log`، `build_picpos.log`، `final_combined.txt`، `analyze_final.txt`: **مُتجاهَلة** (`!!`). البحث فيها عن توكنات/مفاتيح فعلية: **صفر** نتائج؛ تحوي أسطر تشخيص مثل `admin_password_customized=…` فقط.

### L-01 — ملفات `.txt` كبيرة غير متتبَّعة وغير مُتجاهَلة في الجذر
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** `all_final.txt` (380KB)، `orig5.txt` (232KB)، `test_output.txt`، `all_print_tests*.txt`، `font_*.txt` — حالتها `??` (ليست في `.gitignore`)، ومجلدات غير متتبَّعة بأسماء عربية (`تصميم شاشات فواتير PicPos-handoff/` …).
- **الأثر:** خطر إضافتها عرضًا بـ`git add -A`. محتواها مخرجات اختبارات (لم أجد فيها أسرارًا)، لكنها قد تحوي بيانات عملاء/مسارات مستقبلًا.
- **التوصية:** إضافة نمط عام للجذر مثل `/*.txt` مع استثناء `!dart_version.txt`، أو نقلها خارج الريبو.
- **الجهد:** صغير.

### L-02 — ملفات متتبَّعة ذات محتوى تشغيلي
- **الخطورة:** منخفضة (استنتاج — لم أفحص المحتوى بالتفصيل).
- **الموضع:** `invoice_templates/design/uploads/coa-dump.txt`، `invoice_templates/design/uploads/chart-of-accounts.xlsx`، `tools/chart of accounts.xlsx` (على `origin/main`)، و`lib/data/database/database.dart.bak` و`lib/presentation/widgets/settings/pos_settings_widget_backup.dart.bak` أُضيفت في التاريخ.
- **الأثر:** دليل حسابات قد يكون لعميل حقيقي؛ ملفات `.bak` قد تحوي نسخًا قديمة من كود حساس.
- **التوصية:** التأكد من أن دليل الحسابات قالب عام لا بيانات عميل.
- **الجهد:** صغير.

### L-03 — سجلات تشخيص وقت التشغيل تكتب SQL مع وسائطه
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [connection_io.dart:182-193](<../../lib/data/database/connection_io.dart#L182-L193>) يكتب `sql:` و`args: $args` لكل استعلام PG فاشل إلى `Documents/server_errors.log` (نص صريح)؛ و[main.dart:1021-1048](<../../lib/main.dart#L1021-L1048>) يكتب `<brand>_startup_log.txt` في مجلد الـexe و`Documents` و`%TEMP%`.
- **الأثر:** وسائط الاستعلامات قد تشمل هاشات كلمات المرور (`UPDATE users SET password_hash = ?`) أو بيانات عملاء، في ملف غير مشفّر خارج قاعدة البيانات المشفّرة. سجل الإقلاع لا يحوي أسرارًا (أطوال فقط).
- **التوصية:** تنقيح الوسائط (أو تسجيل أنواعها/أطوالها فقط) في `_logFailed`.
- **الجهد:** صغير.

---

## المحور 3 — تشفير قاعدة البيانات المحلية (SQLCipher)، النسخ الاحتياطية، وكلمات المرور

### ما فُحص
قراءة كاملة لـ[connection_io.dart](<../../lib/data/database/connection_io.dart>)، [security_service.dart](<../../lib/services/security_service.dart>)، [security_gate_wrapper.dart](<../../lib/presentation/widgets/auth/security_gate_wrapper.dart>)، [admin_password_service.dart](<../../lib/services/admin_password_service.dart>)، [developer_auth_service.dart](<../../lib/services/developer_auth_service.dart>)، [user_dao.dart:335-430](<../../lib/data/database/daos/user_dao.dart#L335-L430>)، [api_session_token.dart](<../../lib/services/api/api_session_token.dart>)، [api_auth_middleware.dart:137-147](<../../lib/services/api/api_auth_middleware.dart#L137-L147>)، [network_service.dart:760-775](<../../lib/services/network_service.dart#L760-L775>)، [pg_config.dart:132-170](<../../lib/data/database/pg_config.dart#L132-L170>).

### نقاط إيجابية مؤكدة
- فحص `PRAGMA cipher_version` ورفض الفتح إن لم يكن المحرك SQLCipher ([connection_io.dart:83-96](<../../lib/data/database/connection_io.dart#L83-L96>)) — يمنع الشحن بقاعدة نصّية صامتة.
- التحقق من شكل المفتاح قبل إدراجه في `PRAGMA key` ([:52-57](<../../lib/data/database/connection_io.dart#L52-L57>)).
- كلمة مرور PostgreSQL في `flutter_secure_storage` مع هجرة من JSON ([pg_config.dart:132-170](<../../lib/data/database/pg_config.dart#L132-L170>)).
- Argon2id للتجزئة الجديدة مع إعادة تجزئة شفافة للقديم؛ مقارنة ثابتة الزمن؛ تحقق وهمي ضد تعداد المستخدمين ([user_dao.dart:356-370](<../../lib/data/database/daos/user_dao.dart#L356-L370>)).
- `isLegacyHash` (هاش 8 خانات hex) معرَّف في [security_service.dart:238](<../../lib/services/security_service.dart#L238>) لكنه **غير مستدعى** في `lib/` (بحث `isLegacyHash|migrateLegacyPassword`) — لا مسار قبول للهاش القديم جدًا.

### E-01 — مفتاح SQLCipher حتمي: `SHA256(deviceId + ':' + pepper ثابت في الكود)`
- **الخطورة:** عالية.
- **الموضع (مؤكد):** [security_service.dart:433-458](<../../lib/services/security_service.dart#L433-L458>). الـpepper مبني من `String.fromCharCodes` (تعتيم لا حماية) وقيمته مكتوبة في التعليقات نفسها (`Ural`/`Security`/`Pepper_v2`)، وهو في الكود المصدري المرفوع وفي كل ملف تنفيذي. على ويندوز `uniqueId = windowsInfo.deviceId`. التخزين الآمن (`flutter_secure_storage`) يُستخدم **فقط** كاحتياط عندما يتعذّر `deviceId` ([:460-497](<../../lib/services/security_service.dart#L460-L497>)).
- **الأثر:** المفتاح ليس سرًّا مخزَّنًا بل دالة لقيمتين: ثابت عام + معرّف جهاز. `deviceId` في `device_info_plus` على ويندوز يُقرأ من السجل (`HKLM\SOFTWARE\Microsoft\SQMClient\MachineId` — **استنتاج** من توثيق الحزمة، لم أتحقق من مصدر الحزمة هنا) ويقرؤه أي مستخدم محلي. أي مستخدم محلي/برمجية خبيثة/صورة قرص كاملة ⇒ مفتاح القاعدة ونسخها الاحتياطية. التشفير يحمي عمليًا فقط من سرقة ملف `.db` منفردًا. التعليق في الكود يقرّ أن الاشتقاق «unchanged intentionally» للتوافق.
- **التوصية:** مفتاح عشوائي 256-bit يُولَّد مرة ويُحفظ عبر DPAPI/Credential Manager (`flutter_secure_storage` على ويندوز) أو مغلَّفًا بمفتاح DPAPI؛ هجرة التنصيبات القائمة بـ`PRAGMA rekey` بعد الفتح بالمفتاح القديم.
- **الجهد:** متوسط (مع اختبار الهجرة).

### E-02 — نفس مفتاح القاعدة هو جذر توكن LAN وتوقيع الجلسات وتوكنات فواتير الطاولات
- **الخطورة:** عالية.
- **الموضع (مؤكد):** [network_service.dart:763-773](<../../lib/services/network_service.dart#L763-L773>): `machineSeed = await SecurityService.getDatabaseEncryptionKey()` ثم `ApiAuthMiddleware.generateToken(machineSeed)` (`sha256(seed:'UralCash-API-v1')[:32]` — [api_auth_middleware.dart:137-147](<../../lib/services/api/api_auth_middleware.dart#L137-L147>))، و`ApiSessionToken.deriveKey(machineSeed)` (`sha256(seed:'UralCash-Session-v1')` — [api_session_token.dart:44-46](<../../lib/services/api/api_session_token.dart#L44-L46>))، و`TableBillToken.deriveKey(machineSeed)`.
- **الأثر:** (1) من يعرف `deviceId` لجهاز الخادم (E-01) يحسب مفتاح HMAC للجلسات ويسكّ `X-Session-Token` لأي `uid` (مثل 1 = المدير) صالحًا 30 يومًا، ويحسب توكن الـbearer — أي تجاوز كامل لمصادقة الـAPI على الشبكة. (2) توكن الـbearer **ثابت مدى الحياة** ولا يمكن تدويره/إبطاله لجهاز مقترن مفقود دون تغيير مفتاح القاعدة. (3) خلط أغراض المفتاح (key reuse) يجعل تسريب أيٍّ منها تسريبًا للجميع.
- **التوصية:** أسرار مستقلة عشوائية لكل غرض (bearer، HMAC الجلسات، توكن الطاولات) تُخزَّن في التخزين الآمن وقابلة للتدوير من الواجهة.
- **الجهد:** متوسط.

### E-03 — كلمات مرور «حماية الأقسام» نصّ صريح، بلا حدّ محاولات، وتُسلَّم عبر `GET /api/settings`
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [security_gate_wrapper.dart:39](<../../lib/presentation/widgets/auth/security_gate_wrapper.dart#L39>) يقرأ الكلمة من جدول `settings` و[:90](<../../lib/presentation/widgets/auth/security_gate_wrapper.dart#L90>)/[:107](<../../lib/presentation/widgets/auth/security_gate_wrapper.dart#L107>) يقارن بـ`==` (غير ثابت الزمن، بلا عدّاد محاولات). المفاتيح: `inventory_access_password`، `purchases_access_password`، `accounting_access_password`، `reports_access_password`، `hr_access_password` ([guarded_sections.dart:54-78](<../../lib/presentation/settings_picpos/guarded_sections.dart#L54-L78>))، و`settings_access_password` ([settings_screen.dart:198](<../../lib/presentation/screens/settings_screen.dart#L198>)، [settings_picpos_screen.dart:327](<../../lib/presentation/settings_picpos/screens/settings_picpos_screen.dart#L327>)) — تُحفظ بـ`saveSetting` نصًّا. وهي **ليست** ضمن `kServerSecretSettingKeys` ([setting_sync_strategy.dart:61-67](<../../lib/services/sync/strategies/setting_sync_strategy.dart#L61-L67>))، و`_getSettings` يستثني تلك القائمة فقط ([api_handler.dart:778-794](<../../lib/services/api/api_handler.dart#L778-L794>)).
- **الأثر:** أي حامل لتوكن LAN (أي جهاز مقترن) يقرأ كل كلمات مرور الأقسام نصًّا، وتُزامَن إلى كل الطرفيات حيث تُقرأ من القاعدة (المحمية بمفتاح E-01). وتخمين غير محدود محليًا.
- **التوصية:** تخزينها Argon2id عبر خدمة مثل `AdminPasswordService` مع `ServerLoginThrottle`، وإضافة المفاتيح الستة إلى `kServerSecretSettingKeys`.
- **الجهد:** صغير–متوسط.

### E-04 — معاملات Argon2id ضعيفة واستمرار قبول الهاش القديم
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [security_service.dart:142-145](<../../lib/services/security_service.dart#L142-L145>): `m=4096 KiB (4MiB), t=3, p=1` — أقل من الحد الأدنى في توصيات OWASP (`m=19MiB,t=2` أو ما يكافئها). والتوثيق في [:164-165](<../../lib/services/security_service.dart#L164-L165>) و[:183](<../../lib/services/security_service.dart#L183>) يذكر `m=65536,t=3,p=4` خلافًا للفعلي (مضلِّل). الهاش القديم (SHA-256 مكرَّر 10000 مرة، الملح في الجولة الأولى فقط — [:87-97](<../../lib/services/security_service.dart#L87-L97>)) ما زال مقبولًا ويُرقّى **فقط عند دخول ناجح** ([user_dao.dart:398-405](<../../lib/data/database/daos/user_dao.dart#L398-L405>))؛ والحسابات الخاملة تبقى بالهاش القديم بلا حد زمني. كذلك `scripts/reset_user_password.dart` ما زال يولّد الصيغة القديمة وافتراضه `admin`.
- **الأثر:** هاشات المستخدمين تُسلَّم للطرفيات المقترنة (الجزء 2 من المراجعة) — كسرها دون اتصال أرخص مما يلزم.
- **التوصية:** رفع المعاملات (PHC يحمل المعاملات، فالترقية تدريجية بإعادة التجزئة عند الدخول حين تختلف `m/t`)؛ فرض تغيير كلمة المرور للحسابات التي ما زالت بالهاش القديم بعد مهلة.
- **الجهد:** صغير (المعاملات) / متوسط (فرض الترحيل).

### E-05 — النسخ الاحتياطية: نسخ ملف مشفّر بمفتاح مرتبط بالجهاز
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [connection_io.dart:387-424](<../../lib/data/database/connection_io.dart#L387-L424>) `createDatabaseBackup` = `File.copy` إلى `Documents/backups/<db>_backup_<ts>.db` (يحتفظ بآخر 7)؛ [:632-646](<../../lib/data/database/connection_io.dart#L632-L646>) `exportBackupToPath` ينسخ أحدث نسخة إلى مجلد خارجي (USB)؛ [:474-495](<../../lib/data/database/connection_io.dart#L474-L495>) الاستعادة نسخ ملف `.restore-pending` بلا تحقق من سلامة/أصل الملف.
  - مسار نسخ ثانٍ مستقل: [backup_service.dart:14-56](<../../lib/core/services/backup_service.dart#L14-L56>) (`BackupService.performBackup`، مستدعى من [main_desktop.dart:63](<../../lib/main_desktop.dart#L63>) و[app_shell.dart:374](<../../lib/presentation/shell/app_shell.dart#L374>)) ينسخ الملف إلى `Documents/<Brand.backupFolderName>/*.sqlite` ويحتفظ بـ20 نسخة، دون تفريغ WAL. ومساره للرفع إلى Supabase Storage (`uploadToCloud`) غير مستدعى بأي موضع (بحث `uploadToCloud:`).
  - `RemoteBackupService` ([remote_backup_service.dart:60-71](<../../lib/services/backup/remote_backup_service.dart#L60-L71>)) يرفع عبر **FTP نصّي** (`FTPConnect` بلا `securityType`)، وكلمة مرور FTP في التخزين الآمن ([remote_backup_config.dart:69-100](<../../lib/services/backup/remote_backup_config.dart#L69-L100>)) — والخدمة **غير مستدعاة** حاليًا (بحث `RemoteBackupService` لا يجد إلا تعريفها)؛ إن فُعّلت فستُرسل اعتماد FTP والقاعدة المشفّرة نصًّا على الشبكة.
- **الأثر:** (أ) السرية = سرية E-01 (مفتاح قابل للاشتقاق). (ب) **استنتاج:** لأن المفتاح مشتق من `deviceId`، النسخة المصدَّرة لا تُفتح على جهاز آخر أو بعد إعادة تثبيت ويندوز إن تغيّر المعرّف — خطر فقدان بيانات في سيناريو الكارثة الذي وُجدت النسخ لأجله (لم أجد مسار تصدير للمفتاح). (ج) الاستعادة تقبل أي ملف يضعه المستخدم في المسار دون فحص.
- **التوصية:** تصدير نسخة مشفّرة بكلمة مرور يختارها المالك (أو تصدير مفتاح الاسترداد مرة واحدة)، واختبار استعادة على جهاز آخر؛ فحص `PRAGMA integrity_check` على النسخة قبل جدولة الاستعادة.
- **الجهد:** متوسط.

### E-06 — كلمة مرور مفتاح TLS لخادم LAN في SharedPreferences نصًّا
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [network_service.dart:86](<../../lib/services/network_service.dart#L86>) `_prefTlsKeyPassword = 'network_tls_key_password'`، [:252](<../../lib/services/network_service.dart#L252>) قراءة، [:582](<../../lib/services/network_service.dart#L582>) `prefs.setString`.
- **الأثر:** SharedPreferences على ويندوز ملف JSON في `AppData` غير مشفّر ⇒ كلمة فك المفتاح الخاص لـTLS مكشوفة لأي مستخدم محلي، بخلاف كلمة PG التي نُقلت إلى التخزين الآمن.
- **التوصية:** نقلها إلى `flutter_secure_storage` بنفس نمط `pg_config.dart`.
- **الجهد:** صغير.

### E-07 — مسار مقارنة نصّية لكلمة مرور المدير القديمة
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [admin_password_service.dart:125-129](<../../lib/services/admin_password_service.dart#L125-L129>) يقارن `admin_password` نصًّا بـ`==` إن لم يوجد هاش؛ `migrateIfNeeded` يرقّيها عند الإقلاع.
- **الأثر:** نافذة الهجرة فقط؛ أثر محدود.
- **التوصية:** بعد عدد كافٍ من الإصدارات، حذف المسار القديم.
- **الجهد:** صغير.

---

## المحور 4 — التبعيات (pubspec.yaml / pubspec.lock)

### ما فُحص
- قراءة [pubspec.yaml](<../../pubspec.yaml>) للجذر.
- تحليل كل ملفات القفل المتتبَّعة (11 ملفًا: الجذر، `mobile`، `mobile_admin`، `mobile_pos`، `packages/{core,picpos_api_client,picpos_device,picpos_rules,picpos_ui}`، `server`، `web_app`) باستخراج `source:` لكل حزمة: **لا توجد أي تبعية `git`**؛ كل التبعيات غير المستضافة من نوع `path` وتشير إلى حزم داخل الريبو (`picpos_api_client`، `picpos_device`، `picpos_rules`، `picpos_ui`) — موثوقة.
- لم يُشغَّل `pub outdated` (غير مطلوب). مصدر حالة EOL: صفحة الحزمة على pub.dev ([sqlcipher_flutter_libs](https://pub.dev/packages/sqlcipher_flutter_libs)). محاولة جلب `UPGRADING_TO_V3.md` من GitHub فشلت (HTTP 503) فلم أعتمد عليها.

### D-01 — `sqlcipher_flutter_libs 0.6.8` منتهية الدعم (EOL) ومتعارضة مع `sqlite3 3.3.1` المستخدمة فعليًا
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [pubspec.yaml:39](<../../pubspec.yaml#L39>) `sqlcipher_flutter_libs: ^0.6.8`؛ و`pubspec.lock` للجذر يحلّ `sqlcipher_flutter_libs 0.6.8` و`sqlite3 3.3.1` (انتقاليًا عبر `drift 2.32.1`). صفحة pub.dev تنص: الحزمة «Not used anymore, update to version 3.x of package:sqlite3 instead» وأن الإصدار `0.7.0+eol` لا يفعل شيئًا، وأنها تخص `sqlite3` 2.x فقط.
- **الأثر:** (1) محرك SQLCipher المشحون مجمَّد على ما تحمله 0.6.8 ولن يتلقى تحديثات أمنية لـSQLite/SQLCipher/OpenSSL المضمّنة. (2) الخلط بين جيلين يسبب بالضبط ظاهرة «تظليل `sqlite3.dll`» الموثّقة؛ والحل الحالي **ترقيع في سكربت البناء** ([build_picpos.bat:94-133](<../../build_picpos.bat#L94-L133>) ينسخ DLL الـSQLCipher فوق النسخة العادية ويتحقق بـ`findstr sqlcipher`)، وهذا الترقيع **غير موجود في CI** (انظر C-01). الحارس وقت التشغيل ([connection_io.dart:83-96](<../../lib/data/database/connection_io.dart#L83-L96>)) يمنع الكتابة نصًّا لكنه يحوّل البناء الخاطئ إلى تطبيق لا يفتح.
- **التوصية:** الهجرة إلى `sqlite3` 3.x بآلية SQLCipher الرسمية فيها (إعداد hooks لمصدر SQLCipher — بحسب توثيق الحزمة) وإزالة `sqlcipher_flutter_libs` وإزالة خطوة النسخ اليدوي من سكربتات البناء؛ مع اختبار فتح قاعدة قائمة (توافق إصدار SQLCipher 4).
- **الجهد:** متوسط.

### D-02 — حزم إضافية توسّع سطح الهجوم أو قديمة
- **الخطورة:** منخفضة.
- **الموضع (مؤكد للإصدارات، استنتاج للأثر):**
  - `supabase_flutter ^2.8.0` (مقفلة 2.12.4) في تطبيق سطح المكتب [pubspec.yaml:64](<../../pubspec.yaml#L64>) مع أن رفع النسخ إلى Supabase غير مستدعى، و`web_app/` (Supabase) يبدو إرثًا. كل حزمة غير مستخدمة = كود طرف ثالث إضافي في الثنائي.
  - `ftpconnect 2.0.10` (FTP نصّي — موازين الملصقات و`RemoteBackupService`)، و`flutter_zkteco 1.2.0` (بروتوكول TCP لأجهزة البصمة، حزمة مجتمعية صغيرة) — بروتوكولات بلا تشفير على LAN بطبيعتها.
  - تفاوت إصدارات `flutter_secure_storage`: الجذر `9.2.4` (`flutter_secure_storage_windows 3.1.2`) مقابل `11.2.0` (`…_windows 4.2.2`) في تطبيقات الجوال — الجذر متأخر بإصدارين رئيسيين في الحزمة التي تحفظ أسرار التطبيق.
  - `js 0.6.7` (الجذر) — حزمة متوقفة لصالح `dart:js_interop` (انتقالية).
  - `packages/core/pubspec.lock` يقفل `sqlite3_flutter_libs 0.5.41` و`drift 2.30.1`، ولا يشير أي `pubspec.yaml`/`melos.yaml` إلى `packages/core` (بحث `git grep packages/core`) — حزمة يتيمة.
- **التوصية:** إزالة `supabase_flutter` من تطبيق سطح المكتب إن لم يعد مستخدمًا؛ ترقية `flutter_secure_storage` في الجذر؛ حذف `packages/core` أو توثيقه؛ تشغيل `dart pub outdated` و`osv-scanner` (يدعم `pubspec.lock`) دوريًا في CI.
- **الجهد:** صغير–متوسط.

### D-03 — صورة Docker الأساسية غير مثبّتة
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [server/Dockerfile](<../../server/Dockerfile>) `FROM dart:stable AS build` (وسم متحرك)، و[docker-compose.yml:6](<../../docker/docker-compose.yml#L6>) `postgres:16-alpine`.
- **الأثر:** بناءات غير قابلة للتكرار؛ تغيّر صامت في سلسلة الأدوات. (المرحلة النهائية `FROM scratch` ممتازة.)
- **التوصية:** تثبيت بـdigest (`dart:3.x@sha256:…`).
- **الجهد:** صغير.

---

## المحور 5 — CI (`.github/workflows/ci.yml`)

### ما فُحص
قراءة كاملة لـ[ci.yml](<../../.github/workflows/ci.yml>) (680 سطرًا؛ الملف الوحيد تحت `.github/`).

### نقاط إيجابية مؤكدة
- `permissions: contents: read` افتراضيًا ([ci.yml:19-20](<../../.github/workflows/ci.yml#L19-L20>))، و`contents: write` فقط لمهمة `release` المقيّدة بوسوم `v*` ([:655-661](<../../.github/workflows/ci.yml#L655-L661>)).
- المشغّل `pull_request` (لا `pull_request_target`)، فلا أسرار ولا توكن كتابة لطلبات الدمج من forks. الأسرار المستعملة: `GITHUB_TOKEN` و`GITLEAKS_LICENSE` فقط ([:73-74](<../../.github/workflows/ci.yml#L73-L74>)). لا مفاتيح توقيع ولا Supabase في الـworkflow الحالي (`SUPABASE_ANON_KEY` كان في نسخة `79a1ceaf` كـ`${{ secrets.… }}` وأُزيل).
- لا يُطبع أي سر في الخطوات؛ كلمة مرور Postgres الخدمية `picpos_test_only` قيمة اختبارية على مشغّل مؤقت ([:403-413](<../../.github/workflows/ci.yml#L403-L413>)، [:455-465](<../../.github/workflows/ci.yml#L455-L465>)) — مقبول.
- الـartifacts: `coverage/lcov.info`، `merged.info`، `build/e2e_logs/`، `build/web`، و`dist/*.zip` لنسخة ويندوز. لا يتضمن أيٌّ منها ملفات أسرار (لا `key.properties`/jks في CI أصلًا). سجلات E2E قد تحوي توكنات اختبار وهمية من خادم E2E (السر `e2e-secret-…` وهمي ومستثنى في `.gitleaks.toml`) — استنتاج، أثر منخفض.

### C-01 — بناء الإصدار في CI لا يطابق بناء الإنتاج: لا علامة تجارية، لا فرض SQLCipher، لا توقيع
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [ci.yml:623-627](<../../.github/workflows/ci.yml#L623-L627>) `flutter build windows --release` **بدون** `--dart-define=APP_BRAND=picpos` وبدون خطوة فرض `sqlite3.dll` الخاصة بـSQLCipher (الموجودة فقط في [build_picpos.bat:114-133](<../../build_picpos.bat#L114-L133>))، ثم يُضغط وينشر كـGitHub Release عند الوسوم ([:655-680](<../../.github/workflows/ci.yml#L655-L680>)) بلا توقيع Authenticode ولا checksums/provenance.
- **الأثر:** إصدار GitHub الرسمي قد يحمل `sqlite3.dll` عاديًا (بحسب ما يوثّقه السكربت نفسه: «Removing the direct sqlite3 dependency … is NOT enough … the plain dll was still shipped»)، فيرفض التطبيق فتح القاعدة (الحارس في `connection_io.dart`) أو — لو أُزيل الحارس يومًا — يكتب قاعدة نصّية. وبلا توقيع/بصمات لا يستطيع العميل التحقق من أن الملف المنزَّل هو ما بناه CI. (استنتاج: لم أشغّل بناء CI.)
- **التوصية:** جعل CI يستدعي نفس سكربت البناء (`build_picpos.bat`) أو ينسخ خطوة الفرض والتحقق؛ إرفاق `SHA256SUMS` و`actions/attest-build-provenance`؛ توقيع الـexe والمثبّت.
- **الجهد:** صغير–متوسط.

### C-02 — Actions مثبّتة بوسوم متحركة لا بـSHA (منها أطراف ثالثة بصلاحية كتابة)
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** `actions/checkout@v4` (كل المهام)، `actions/upload-artifact@v4`، `actions/download-artifact@v4`، **`subosito/flutter-action@v2`** (طرف ثالث، في كل مهمة بناء)، **`gitleaks/gitleaks-action@v2`** (طرف ثالث، يتلقى `GITHUB_TOKEN`) [ci.yml:71](<../../.github/workflows/ci.yml#L71>)، **`softprops/action-gh-release@v2`** (طرف ثالث، في مهمة `contents: write`) [ci.yml:673](<../../.github/workflows/ci.yml#L673>).
- **الأثر:** اختراق مستودع أي Action طرف ثالث أو إعادة توجيه وسمه (نمط حادثة `tj-actions/changed-files` 2025) يُنفّذ كودًا في CI؛ في `release` يمكنه استبدال الملف المنشور أو العبث بالريبو، وفي `build-windows` العبث بالثنائي قبل رفعه.
- **التوصية:** تثبيت كل `uses:` بـcommit SHA كامل مع تعليق الإصدار، وتفعيل Dependabot لـ`github-actions`.
- **الجهد:** صغير.

### C-03 — فحص الأسرار استشاري فقط وفحص الملفات محدود
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [ci.yml:56-74](<../../.github/workflows/ci.yml#L56-L74>) `continue-on-error: true` لـgitleaks؛ و`secrets` يشغّل `check_no_secrets.ps1` المحدود بامتدادات (S-07). كلمة مرور PG (S-01) والملح (S-02) دخلا `origin/main` رغم وجود gitleaks.
- **الأثر:** لا شيء يمنع دمج سر؛ النتيجة تظهر كتحذير فقط (إن ظهرت).
- **التوصية:** جعل gitleaks حاجزًا (إزالة `continue-on-error`) مع قواعد مخصصة (روابط DSN بكلمة مرور، `_secretSalt`، و«كلمة السر `…`» في Markdown) وتشغيله محليًا كـpre-commit؛ إن كان الريبو ملك منظمة لاحقًا فـgitleaks-action يتطلب ترخيصًا، أو استخدم `gitleaks` CLI مباشرة.
- **الجهد:** صغير.

### C-04 — ملاحظات CI أخرى
- **الخطورة:** منخفضة.
- `on: push: branches: ['**']` + `pull_request` يشغّلان كل شيء مرتين لنفس الكود (تكلفة لا أمن). `cache: true` في `flutter-action` — ذاكرة الكاش على مستوى الفرع ولا تكتبها PRs من forks؛ لا خطر ملحوظ (استنتاج).
- `build-windows` يعمل على `refs/heads/main` كذلك؛ artifacts بعمر 30 يومًا مرئية لكل من يقرأ الريبو الخاص — مقبول.

---

## المحور 6 — Docker والبنية التحتية

### ما فُحص
[docker-compose.yml](<../../docker/docker-compose.yml>)، [server/Dockerfile](<../../server/Dockerfile>)، [docker/smoke.ps1](<../../docker/smoke.ps1>)، [server/lib/picpos_cloud.dart:33-55](<../../server/lib/picpos_cloud.dart#L33-L55>)، [server/lib/src/http/app.dart:201](<../../server/lib/src/http/app.dart#L201>).

### نقاط إيجابية مؤكدة
- الملف موسوم صراحة «TEST stack … Not for production» ([docker-compose.yml:1](<../../docker/docker-compose.yml#L1>)).
- `TOKEN_SECRET` أقصر من 32 حرفًا ⇒ سر عشوائي ([picpos_cloud.dart:44-51](<../../server/lib/picpos_cloud.dart#L44-L51>))؛ `ADMIN_KEY` فارغ ⇒ نقاط الإدارة مرفوضة ([app.dart:201](<../../server/lib/src/http/app.dart#L201>)) — fail-closed.
- الصورة النهائية `FROM scratch` بلا shell.

### I-01 — منافذ مكشوفة على كل الواجهات مع اعتمادات معروفة وبيانات تجريبية
- **الخطورة:** متوسطة (إن شُغّل على جهاز متصل بشبكة غير موثوقة)، منخفضة على جهاز مطوّر معزول.
- **الموضع (مؤكد):** [docker-compose.yml:11-12](<../../docker/docker-compose.yml#L11-L12>) `"55432:5432"` و[:41-42](<../../docker/docker-compose.yml#L41-L42>) `"18080:8080"` — بلا `127.0.0.1:`، فيستمع Docker على `0.0.0.0`. مع `POSTGRES_PASSWORD: picpos_test_only` ([:10](<../../docker/docker-compose.yml#L10>))، `TOKEN_SECRET: test-only-token-secret-change-me-0123456789` ([:37](<../../docker/docker-compose.yml#L37>))، `ADMIN_KEY: test-admin-key` ([:38](<../../docker/docker-compose.yml#L38>))، `SEED_DEMO: "true"` ([:39](<../../docker/docker-compose.yml#L39>)). وكلها منشورة في الريبو.
- **الأثر:** أي جهاز على نفس الشبكة (مقهى/عميل) يصل إلى PostgreSQL بكلمة معروفة وإلى نقاط الإدارة بـ`test-admin-key`، ويستطيع سكّ توكنات الجلسات بالسر المعروف. وعلى ويندوز يتجاوز Docker Desktop قواعد الجدار الناري عادةً (استنتاج).
- **التوصية:** ربط المنافذ بـ`127.0.0.1:55432:5432` و`127.0.0.1:18080:8080`؛ نقل القيم إلى ملف `.env` غير متتبَّع مع قيم مولّدة.
- **الجهد:** صغير.

### I-02 — قيمة افتراضية لكلمة مرور قاعدة الخادم السحابي
- **الخطورة:** منخفضة.
- **الموضع (مؤكد):** [picpos_cloud.dart:41](<../../server/lib/picpos_cloud.dart#L41>) `env['DB_PASSWORD'] ?? 'picpos'`.
- **الأثر:** نشر إنتاجي ينسى `DB_PASSWORD` يتصل بكلمة معروفة بصمت بدل الفشل.
- **التوصية:** الفشل عند غياب `DB_PASSWORD` خارج وضع الاختبار (كما يُعامَل `ADMIN_KEY`).
- **الجهد:** صغير.

---

## المحور 7 — سكربتات البناء والتوقيع والمثبّت

### ما فُحص
[build_picpos.bat](<../../build_picpos.bat>)، [installer/setup.iss](<../../installer/setup.iss>)، [scripts/generate_self_signed_cert.ps1](<../../scripts/generate_self_signed_cert.ps1>)، `mobile_*/android/key.properties` (محليًا، دون نسخ القيم)، بحث Grep على `signtool|certificate|.pfx|timestamp|Authenticode|checksum|sha256|curl|http` في `*.bat|*.iss|*.ps1`.

### نقاط إيجابية مؤكدة
- توقيع أندرويد خارج الريبو: `storeFile=D:/PICPOS-KEYS/picpos-*-upload.jks`، و`key.properties` مُتجاهَل ([mobile_admin/android/.gitignore:12](<../../mobile_admin/android/.gitignore#L12>)، [mobile_pos/android/.gitignore:12](<../../mobile_pos/android/.gitignore#L12>)) ولم يدخل التاريخ.
- المثبّت لا يضمّن كلمة مرور PostgreSQL ([setup.iss:357-359](<../../installer/setup.iss#L357-L359>)).
- `build_picpos.bat` يتحقق من أن `sqlite3.dll` المشحون هو SQLCipher ويفشل خلاف ذلك ([:126-132](<../../build_picpos.bat#L126-L132>)).

### B-01 — المثبّت يضيف شهادة الناشر إلى مخزن **Root** الموثوق على أجهزة العملاء
- **الخطورة:** عالية (تُفعَّل تلقائيًا متى وُجد ملف `.cer` في مجلد البناء — مسار UralCash؛ ومعطّلة حاليًا لـPicPos لغياب `.cer`).
- **الموضع (مؤكد):** [setup.iss:226-231](<../../installer/setup.iss#L226-L231>) `certutil -addstore -f Root "{app}\<CertName>"` ثم `TrustedPublisher`؛ وإزالة بالـSubject عند إلغاء التثبيت ([:236-242](<../../installer/setup.iss#L236-L242>)). الشهادة «produced out-of-tree» وذاتية التوقيع ([:21-23](<../../installer/setup.iss#L21-L23>)).
- **الأثر:** كل جهاز عميل يثق بهذه الشهادة كمرجع جذر. من يحصل على مفتاحها الخاص (من جهاز المطوّر) يوقّع برمجيات تُعامَل «ناشرًا موثوقًا» على كل أجهزة العملاء، وإن لم تكن امتدادات الشهادة مقيّدة بـCodeSigning فقط فيمكنه أيضًا إصدار شهادات TLS لأي نطاق وتنفيذ MITM (استنتاج — لم أفحص امتدادات الشهادة لأنها خارج الريبو). كما أن `-delstore` بالاسم قد يحذف شهادة مطابقة الاسم ليست للبرنامج.
- **التوصية:** عدم تثبيت أي شهادة في Root؛ شراء شهادة توقيع كود من جهة معتمدة (OV/EV أو Azure Trusted Signing) والتوقيع بـ`signtool … /tr <timestamp>`؛ وإن استمر الحل الذاتي مؤقتًا فلتكن شهادة `CA:FALSE` و`EKU=codeSigning` فقط وتُضاف إلى `TrustedPublisher` وحدها مع تخزين مفتاحها على عتاد (HSM/token).
- **الجهد:** متوسط.

### B-02 — لا توقيع Authenticode للتطبيق ولا للمثبّت (PicPos)
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** لا وجود لـ`signtool` في أي `*.bat|*.iss|*.ps1` متتبَّع؛ [setup.iss:21-23](<../../installer/setup.iss#L21-L23>) «PicPos has no signing certificate yet»؛ `[Setup]` بلا `SignTool=`.
- **الأثر:** لا يمكن للعميل/للمحدّث التحقق من سلامة الملف؛ تحذيرات SmartScreen تدفع المستخدمين لتجاهل التحذيرات؛ أي ملف معدَّل يبدو مطابقًا.
- **التوصية:** توقيع `PicPos.exe` و`sqlite3.dll` والمثبّت بشهادة معتمدة مع ختم زمني، ضمن سكربت البناء وCI.
- **الجهد:** متوسط.

### B-03 — المثبّت ينزّل وينفّذ ملفات بصلاحية المدير دون التحقق من البصمة، وبإصدار PostgreSQL قديم
- **الخطورة:** متوسطة.
- **الموضع (مؤكد):** [setup.iss:133-135](<../../installer/setup.iss#L133-L135>) روابط `vc_redist.x64.exe` و`postgresql-16.4-1-windows-x64.exe`؛ [:337-339](<../../installer/setup.iss#L337-L339>) `DownloadPage.Add(url, file, '')` — الوسيط الثالث (SHA-256) فارغ؛ ثم `Exec` بصلاحيات المثبّت (`PrivilegesRequired=admin`، [:176](<../../installer/setup.iss#L176>)) في [:371](<../../installer/setup.iss#L371>) و[:382](<../../installer/setup.iss#L382>).
- **الأثر:** الحماية الوحيدة هي HTTPS؛ أي تلاعب بالمصدر/إعادة توجيه/وكيل TLS مؤسسي يُنفَّذ كمدير. وPostgreSQL `16.4` أقدم من إصدارات صيانة 16.x اللاحقة التي تضمنت إصلاحات أمنية (استنتاج عام — لم أتحقق من قائمة CVE هنا)، والرابط مثبّت على هذا الإصدار.
- **التوصية:** تمرير بصمة SHA-256 المتوقعة لـ`DownloadPage.Add` (Inno 6.1+ يدعمها)؛ تحديث رابط PostgreSQL لآخر 16.x/17.x دوريًا ضمن قائمة إصدار.
- **الجهد:** صغير.

### B-04 — سكربتات البناء: ملاحظات طفيفة
- **الخطورة:** منخفضة.
- `build_picpos.bat` يضبط `APP_BRAND` و`APP_FLAVOR` فقط؛ لا أسرار تُمرَّر عبر `--dart-define` (مؤكد) — جيد، لأن قيم `--dart-define` تُضمَّن نصًّا في الثنائي.
- ملفات `*.ps1` مُتجاهَلة عمومًا ويُضاف بعضها بـ`git add -f` ([ci.yml:47-48](<../../.github/workflows/ci.yml#L47-L48>)) — سكربت أمني جديد قد لا يُتتبَّع عرضًا (استنتاج).


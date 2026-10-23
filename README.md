<div align="center">

# PicPos ERP

**نظام ERP + نقطة بيع (POS) عربي أولًا — يعمل دون إنترنت، بمحاسبة قيد مزدوج حقيقية**

![Platform](https://img.shields.io/badge/Desktop-Windows-0078D6?style=flat-square&logo=windows)
![Mobile](https://img.shields.io/badge/Mobile-Android-3DDC84?style=flat-square&logo=android)
![Flutter](https://img.shields.io/badge/Flutter-3.41.x-02569B?style=flat-square&logo=flutter)
![Dart SDK](https://img.shields.io/badge/Dart-%5E3.10.4-0175C2?style=flat-square&logo=dart)
![Schema](https://img.shields.io/badge/Drift%20schema-v195-orange?style=flat-square)
![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)

</div>

---

## English summary

**PicPos ERP** is an Arabic-first (RTL, with a full English UI chosen per user) ERP + POS for small and medium
businesses in Jordan and Egypt: supermarkets, retail, wholesale, distribution, restaurants, cafés and light
manufacturing. It covers the full cycle from the point of sale to the financial statements in one system, with
double-entry accounting, an encrypted local database (SQLCipher) that works offline, and LAN sync.

This monorepo contains:

- the **Windows desktop app** (repo root, Flutter) — the primary product;
- a **web mirror client** (`lib/main_web_entry.dart`) that reads from a server instance over WebSocket (drift remote) and writes through the HTTP API;
- three **Android apps**: *PicPos Van* (field rep, `mobile/`), *PicPos Admin* (`mobile_admin/`), *PicPos Cashier* (`mobile_pos/`);
- shared packages under `packages/` and a pure-Dart **cloud server** (`server/`, `shelf` + PostgreSQL).

Quick start (Windows): `flutter pub get`, then
`flutter run -d windows --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified`.
Release build: `build_picpos.bat`. License: **Proprietary — all rights reserved.**

---

## نظرة عامة

PicPos ERP نظام متكامل يغطي دورة العمل كاملة من نقطة البيع حتى القوائم المالية، ويستهدف المحلات والشركات
الصغيرة والمتوسطة في الأردن ومصر (سوبرماركت، تجزئة، جملة، توزيع، مطاعم وكافيهات، وتصنيع خفيف). وفق
[`PRODUCT.md`](PRODUCT.md):

- **عربي أولًا:** واجهة RTL أصلية مع واجهة إنجليزية كاملة تُختار لكل مستخدم.
- **محاسبة حقيقية:** قيد مزدوج متوافق مع IFRS — قيود تلقائية، سنوات مالية، مراكز تكلفة، فروق عملة وإعادة تقييم.
- **يعمل دون إنترنت:** قاعدة بيانات محلية مشفّرة (SQLCipher) ومزامنة عبر الشبكة المحلية، وخادم سحابي للتطبيقات المحمولة.
- **إصدارات حسب النشاط:** مطاعم، كافيهات، سوبرماركت، تجاري، وموحّد، لكل منها الشاشات والميزات المناسبة.
- **الفوترة الإلكترونية:** متوافق مع JoFotara (الأردن) وETA (مصر).

> الكود يدعم علامتين تجاريتين من نفس المحرك (`Brand.isPicPos`). المنتج الحالي **PicPos**، والعلامة الأقدم
> **UralCash** ما زالت موجودة في الكود كعلامة بديلة (انظر [العلامة التجارية والإصدارات](#العلامة-التجارية-والإصدارات)).

---

## المكوّنات

| المكوّن | المسار | الحالة (من الكود والوثائق) |
|---|---|---|
| **PicPos ERP — سطح المكتب** | الجذر `lib/` | تطبيق Flutter لويندوز؛ المنتج الأساسي. الإصدار الحالي `3.9.1+275` (`pubspec.yaml`). |
| **تطبيق الويب (وضع المرآة)** | `lib/main_web_entry.dart`، `lib/web/` | نقطة دخول مستقلة للدورة المحاسبية والمخزنية دون POS/طباعة حرارية. القراءة عبر `/webdb` (drift remote)، والكتابة عبر HTTP API. التصميم في [`2026-09-01-saas-web-design.md`](docs/superpowers/specs/2026-09-01-saas-web-design.md)؛ الكتابات غير المدعومة بعد تُحجب برسالة عربية ([`2026-web-write-audit.md`](docs/superpowers/specs/2026-web-write-audit.md)). |
| **PicPos Van** (المندوب) | [`mobile/`](mobile/README.md) | تطبيق Android (`picpos_van`، `0.1.0+1`) يعمل دون اتصال: اقتران، دخول بـ PIN، خط اليوم، بيع، مرتجع، تحصيل، سندات مصروف، زيارات، مزامنة وطباعة حرارية Bluetooth. |
| **PicPos إدارة** (Admin) | [`mobile_admin/`](mobile_admin/README.md) | تطبيق Android للمالك/المدير المالي (`com.picpos.admin`، `0.1.0+1`). الموجود في الكود: قشرة التطبيق، الاقتران، لوحة المؤشرات، الموافقات، الإعدادات، فك الربط؛ وبعض الأقسام ما زالت صفحات مؤقتة (`placeholder_page.dart`) — المرحلة M-1 جارية. |
| **PicPos كاشير** (Cashier) | [`mobile_pos/`](mobile_pos/README.md) | تطبيق Android لجهاز لوحي (`com.picpos.pos`، `0.1.0+1`). الحالة الفعلية **M-0**: هيكل وقشرة بلا شبكة وشاشة اقتران معطّلة؛ لا بيع فعليًا بعد ([`docs/testing/E2E.md`](docs/testing/E2E.md)). |
| **`packages/picpos_rules`** | `packages/picpos_rules` | Dart خالص: قواعد الضريبة والإجماليات والتسعير والمرتجعات وحد الائتمان وتطبيع الباركود؛ يستخدمه السيرفر وتطبيقات الجوال. |
| **`packages/picpos_api_client`** | `packages/picpos_api_client` | عميل API (Dart خالص): JSON القانوني، التحقق من توقيع Ed25519، منتقي النقل LAN/سحابة، وعقود `/manage/*` و`/api/m1/*`. |
| **`packages/picpos_ui`** | `packages/picpos_ui` | واجهات الجوال المشتركة: رموز `DESIGN.md`، Material 3 فاتح/داكن، خطوط Cairo وNoto Naskh، وهيكل متجاوب. |
| **`packages/picpos_device`** | `packages/picpos_device` | أساسيات الجهاز: مخزن SQLCipher بمفتاح في Keystore، صندوق صادر بإعادة محاولة، طباعة ESC/POS (Bluetooth وTCP 9100)، وإدخال الماسح. |
| **السيرفر السحابي** | [`server/`](server/README.md) | `picpos_cloud`: خادم Dart خالص (`shelf` + `postgres`) بلا Flutter؛ مسارات `/mobile/*` و`/desktop/*` و`/manage/*` و`/admin/*`. |
| **حزم أخرى** | `packages/{accounting,core,inventory,pos,shared_widgets,treasury}` | هياكل قديمة؛ `docs/mobile/ARCHITECTURE-M.md` (F12) يصفها بأنها غير مستخدمة. |

> مجلد `web_app/` مشروع Flutter منفصل (README افتراضي، وSupabase)؛ لم أتحقق من أنه ما زال ضمن مسار التسليم.

---

## الميزات

من [`PRODUCT.md`](PRODUCT.md) وقوائم الشاشات في وثائق التصميم:

- **نقطة البيع:** بيع سريع، فتح/إغلاق الورديات، فواتير مبيعات ومشتريات ومرتجعاتها، طاولات ومطبخ، حجوزات.
- **المحاسبة:** قيد مزدوج، سنوات مالية، مراكز تكلفة، أصول ثابتة، مصروفات تشغيلية، مطابقة بنكية، شيكات وأوراق تجارية.
- **المخزون والمشتريات:** أصناف، تحويلات مخزنية، جرد دوري، تكاليف الاستيراد (Landed Cost)، موازين وPLU.
- **الخزينة:** سندات قبض وصرف (مع دفاتر سندات ورقية لكل موظف)، شيكات، تسليم العهدة.
- **التوزيع:** منطقة توزيع ← خط ← مندوب واحد وأيام زيارة وقائمة عملاء مرتّبة؛ تحميل وتفريغ سيارة المندوب.
- **الأذونات:** صلاحيات تفصيلية على مستوى الزر والإجراء، وتجاوز المدير للعمليات الحساسة.
- **الأجهزة:** طابعات حرارية 58/80 مم وA4/A5، وموازين، وقارئات باركود، وأدراج نقد.
- **اللغات:** العربية والإنجليزية لكل مستخدم؛ مستندات الطباعة بلغة الشركة.
- **الفوترة الإلكترونية:** JoFotara (الأردن) وETA (مصر).
- **المزامنة:** شبكة محلية (خادم رئيسي وأجهزة عميلة باقتران برمز/QR) + خادم سحابي للتطبيقات المحمولة.

---

## العلامة التجارية والإصدارات

- العلامة تُحدَّد وقت البناء بـ `--dart-define=APP_BRAND=<id>` (`lib/core/config/brand.dart`)، والمعرّفان المعروفان: `picpos` و`uralcash`.
- **تنبيه:** القيمة الافتراضية لـ Dart عند غياب `APP_BRAND` ما زالت `uralcash` (اختبارات المستودع تعتمد عليها)؛ لذا مرّر `APP_BRAND=picpos` دائمًا عند تشغيل أو بناء PicPos (`build_picpos.bat` وCI يفعلان). أمّا افتراضات النظام الأصلي (CMake، `Runner.rc`، `main.cpp`) فصارت PicPos.
- قرار المالك (2026-10-23): النظام PicPos فقط؛ لا يظهر اسم أي منتج آخر في أي ناتج PicPos. سكربتات PicPos: `build_picpos.bat` (يحذف الأصول غير PicPos بـ `tool/prune_picpos_bundle.ps1` ثم يشغّل `test/structural/brand_artifact_guard_test.dart` على الحزمة) و`build_installer_picpos.bat` (يستخدم `installer/setup_picpos.iss`). تفاصيل الجرد: [docs/audits/2026-10-23-release-audit/BRAND-REMEDIATION-NOTES.md](docs/audits/2026-10-23-release-audit/BRAND-REMEDIATION-NOTES.md).
- الـ Flavors (`lib/core/config/app_flavor.dart`): `unified`، `restaurant`، `cafe`، `supermarket`، `supermarket_pro`، `supermarket_plus`، `commercial`. بناء `build_picpos.bat` يستخدم `APP_FLAVOR=unified`.
- ملف النشاط (Business Profile) والميزات يُختاران وقت التشغيل ويُخزَّنان في قاعدة البيانات، دون ملف تنفيذي لكل نشاط (تعليق `build_release.bat`).

---

## التقنيات

- **Flutter / Dart:** `environment.sdk: ^3.10.4` في `pubspec.yaml`؛ يثبّت CI قناة stable بإصدار `3.41.x`. (حزم الجوال والسيرفر تطلب `^3.8.0`.)
- **قاعدة البيانات:** Drift فوق SQLite المشفّر (SQLCipher)، مع PostgreSQL اختياريًا. `schemaVersion` الحالي **195** (`lib/data/database/database.dart`).
- **الحالة:** Riverpod.
- **السيرفر:** Dart خالص، `shelf` و`postgres`، صورة Docker (AOT).
- **الجوال:** Flutter على Android (Material 3)، SQLCipher، `flutter_secure_storage`، `mobile_scanner`.
- **الخطوط:** Cairo للواجهة، Noto Naskh Arabic للطباعة (`DESIGN.md`).

---

## هيكل المشروع

```
PICPOS-ERP/
├── lib/                     تطبيق سطح المكتب
│   ├── core/config/         Brand وAppFlavor وسياسات الميزات
│   ├── data/database/       Drift: database.dart وDAOs
│   ├── main_web_entry.dart  نقطة دخول الويب (وضع المرآة)
│   └── web/                 مزودات وجلسة وقشرة الويب
├── windows/                 مشروع Windows (CMake / Runner)
├── mobile/                  PicPos Van (picpos_van)
├── mobile_admin/            PicPos إدارة (picpos_admin)
├── mobile_pos/              PicPos كاشير (picpos_pos)
├── packages/                picpos_rules · picpos_api_client · picpos_ui · picpos_device (+ هياكل قديمة)
├── server/                  السيرفر السحابي picpos_cloud
├── docker/                  docker-compose لحزمة الاختبار (PostgreSQL + API)
├── installer/               إعداد المثبّت (Inno Setup: setup.iss)
├── test/                    اختبارات الجذر (unit, widget, structural, integration, e2e …)
├── tool/                    run_e2e.ps1 · check_no_secrets.ps1
├── docs/                    الوثائق
└── .github/workflows/       CI (ci.yml)
```

---

## التثبيت والتشغيل

**المتطلبات:** Windows، Flutter (stable؛ المثبّت في CI `3.41.x`)، Docker Desktop للسيرفر والاختبارات السحابية، وInno Setup 6 لبناء المثبّت.

```powershell
git clone https://github.com/ahmedelazaizi/PICPOS-ERP.git
cd PICPOS-ERP
flutter pub get
```

### تشغيل سطح المكتب

```powershell
flutter run -d windows --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified
```

### بناء Windows

```powershell
.\build_picpos.bat            # يفحص عزل العلامة ثم flutter build windows --release؛ المخرجات في FlavorBuilds\PicPos
.\build_installer_picpos.bat  # يغلّف مخرجات PicPos في مثبّت (شغّل build_picpos.bat أولًا)
```

`build_picpos.bat` يحذف `build\windows` قبل البناء، ويضمن نسخ محرك SQLCipher بدل `sqlite3.dll` العادي (انظر تعليقات الملف).

### بناء الويب

```powershell
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run -t lib/main_web_entry.dart
```

الويب عميل مرآة يحتاج سيرفر PicPos مفعّلًا فيه «الوصول من المتصفح». يبني CI تطبيق الويب ويرفع `build/web` كـ artifact.

### تطبيقات Android (APK)

```powershell
cd mobile;          flutter build apk --release   # PicPos Van   (ويوجد --debug في mobile/README.md)
cd ..\mobile_admin; flutter build apk --release   # PicPos إدارة
cd ..\mobile_pos;   flutter build apk --release   # PicPos كاشير
```

التوقيع من `android/key.properties` (خارج Git) وإلا يُستعمل مفتاح debug (حسب README التطبيقين). تفاصيل كل تطبيق في README الخاص به.

### السيرفر السحابي وPostgreSQL (حزمة اختبار)

```powershell
cd docker
docker compose up -d --build
docker compose ps                        # الخدمتان postgres وapi
curl.exe http://localhost:18080/health   # فحص الصحة
powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke.ps1   # اختبار دخاني طرف-لطرف
docker compose down                      # إيقاف مع إبقاء البيانات
```

- `postgres` على المنفذ `55432`، و`api` على `18080` (المنفذ 8080 يستعمله خادم الشبكة المحلية للسطح).
- الحزمة **للاختبار فقط**: كلمات المرور والمفاتيح الافتراضية موجودة عمدًا في `docker-compose.yml`. نشر الإنتاج بقائمة منفصلة (`docs/mobile/ARCHITECTURE-I.md` §12).
- تشغيل محلي دون Docker: `cd server; dart run bin/server.dart` مع متغيرات البيئة في [`server/README.md`](server/README.md).
- نشر الخادم المحلي وتأمينه: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

---

## الاختبارات

```powershell
flutter test                                 # اختبارات الجذر
flutter test test/structural                 # اختبارات البنية (حدود الاستيراد، نطاق الويب …)
powershell -NoProfile -ExecutionPolicy Bypass -File tool/run_e2e.ps1   # E2E: سيرفر + عملاء + تطبيقات (يشغّل Postgres تلقائيًا)
cd server; dart test -j 1                    # اختبارات السيرفر (تتابعية)
```

- `tool/run_e2e.ps1 -Only server,mobile` لمجموعات محددة؛ المجموعات: `server, packages, mobile, mobile_admin, mobile_pos, root, web`.
- لا تشغّل أوامر `flutter` بالتوازي (قفل الإقلاع وتعارض `sqlite3.dll`).
- اختبارات Postgres الاختيارية للجذر: `dart run scripts/run_pg_tests.dart` (انظر `test/integration_pg/README.md`).
- دليل E2E الكامل: [`docs/testing/E2E.md`](docs/testing/E2E.md).

---

## الأمان

- قاعدة البيانات المحلية مشفّرة بـ SQLCipher؛ وفي الجوال يُحفظ مفتاحها في Android Keystore.
- أذونات تفصيلية على مستوى الإجراء، وتجاوز المدير للعمليات الحساسة، وتوقيع لقطات الإدارة بـ Ed25519.
- حدود معدّل على الاقتران والدخول في السيرفر السحابي، وإبطال الأجهزة من المكتب.
- **لا أسرار في الريبو:** مفاتيح التوقيع (`*.jks`، `key.properties`) و`google-services.json` وملف `.env` خارج Git؛ و`.env.example` قالب بقيم وهمية فقط.
- فحص محلي: `powershell -File tool/check_no_secrets.ps1` — يفشل (exit 1) إذا تتبّع Git أي ملف سر توقيع/Firebase.
- حزمة `docker/` للاختبار فقط ولا تُستعمل كما هي في الإنتاج.

---

## التكامل المستمر (CI)

سير العمل في [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (**PicPos ERP CI**) يعمل عند كل push وpull_request: فحص أسرار (`tool/check_no_secrets.ps1` + Gitleaks استشاري) ← تحليل واختبارات الجذر مع بوابة تغطية ← حزم وتطبيقات الجوال (analyze + test) ← السيرفر مع Postgres 16 ← اختبارات E2E ← بناء الويب ← بناء Windows (على `main` والوسوم `v*.*.*` فقط) ← إصدار GitHub عند وسم `v*.*.*`.

---

## الوثائق

| الوثيقة | المحتوى |
|---|---|
| [`PRODUCT.md`](PRODUCT.md) | المنتج والمستخدمون والتموضع |
| [`DESIGN.md`](DESIGN.md) | نظام التصميم |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | ملخّص المعمارية وحالة تقسيم الملفات الضخمة |
| [`docs/ARCHITECTURE-MAP.md`](docs/ARCHITECTURE-MAP.md) | خريطة دخول المطوّر الجديد: المجلدات، أنماط `part`، وصفات الإضافة، الاختبارات وCI، الأمن |
| [`docs/mobile/ARCHITECTURE-I.md`](docs/mobile/ARCHITECTURE-I.md) | السيرفر السحابي وتطبيق المندوب |
| [`docs/mobile/ARCHITECTURE-M.md`](docs/mobile/ARCHITECTURE-M.md) | تطبيقا الإدارة والكاشير |
| [`docs/mobile/ARCHITECTURE-MC.md`](docs/mobile/ARCHITECTURE-MC.md) | تطبيق المخازن (خطة) |
| [`docs/testing/E2E.md`](docs/testing/E2E.md) | اختبارات E2E |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | نشر الخادم المحلي وتأمينه |
| [`2026-09-01-saas-web-design.md`](docs/superpowers/specs/2026-09-01-saas-web-design.md) | تصميم الويب SaaS |
| [`2026-web-drift-remote-spike.md`](docs/superpowers/specs/2026-web-drift-remote-spike.md) | قياس drift remote |
| [`2026-web-write-audit.md`](docs/superpowers/specs/2026-web-write-audit.md) | تدقيق الكتابات في الويب |
| [`server/README.md`](server/README.md) · [`docker/README.md`](docker/README.md) | السيرفر وحزمة Docker |
| [`mobile/README.md`](mobile/README.md) · [`mobile_admin/README.md`](mobile_admin/README.md) · [`mobile_pos/README.md`](mobile_pos/README.md) | تطبيقات الجوال |

---

## الترخيص

**Proprietary — جميع الحقوق محفوظة.**

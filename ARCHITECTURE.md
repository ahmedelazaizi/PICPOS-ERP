# PicPos ERP — المعمارية (ملخّص)

> هذا الملف نظرة سريعة. التفصيل ووصفات «أين أضيف…؟» في [`docs/ARCHITECTURE-MAP.md`](docs/ARCHITECTURE-MAP.md).
> خطة تفكيك الملفات الضخمة القديمة (v1.0، مارس 2026) استُبدلت بهذا الملخّص: انظر «حالة التقسيم» أدناه.

## 1. الصورة العامة

```
                         ┌────────────────────────────────────────────┐
  Windows desktop  ───►  │ lib/  (Flutter + Riverpod + Drift/SQLCipher)│  المنتج الأساسي
  (يُشغّل أيضًا خادم     │   presentation → providers/repositories     │
   HTTP/WebSocket        │   → data/database (AppDatabase + DAOs)      │
   مضمَّنًا: LAN)        │   services/api  ← mobile + web clients      │
                         └───────────┬───────────────┬────────────────┘
                                     │ LAN sync      │ cloud sync
        Web mirror (lib/web)  ◄──────┘               ▼
        قراءة: /webdb (drift remote)         server/ (picpos_cloud: shelf + PostgreSQL)
        كتابة: HTTP API                          ▲
                                                 │ HTTPS
                          mobile/ (Van) · mobile_admin/ · mobile_pos/   +   packages/
```

- **قاعدة البيانات:** Drift فوق SQLite المشفَّر (SQLCipher)، وPostgreSQL اختياريًا؛ `schemaVersion` الحالي **195** (`lib/data/database/database.dart`).
- **الحالة:** Riverpod. **العلامة:** `--dart-define=APP_BRAND=picpos|uralcash` (`lib/core/config/brand.dart`، الافتراضي عند الغياب `uralcash`) و`APP_FLAVOR` (`lib/core/config/app_flavor.dart`).
- **الأنظمة الفرعية:** المحاسبة (قيد مزدوج)، المخزون، الخزينة، POS، التوزيع، الموارد البشرية، الفوترة الإلكترونية (JoFotara/ETA)، الموازين والطباعة.

## 2. الطبقات داخل `lib/`

| الطبقة | المسار | ملاحظة |
|---|---|---|
| core | `lib/core/` | config، auth، permissions، navigation، i18n (`tr`)، theme، errors |
| data | `lib/data/` | `database/` (Drift: tables، daos، migrations)، `repositories/`، `providers/` |
| domain | `lib/domain/` | entities، models، واجهات repositories، usecases |
| services | `lib/services/` | `api/` (+`data/`، `routes/`)، `web_read/`، `interceptor/`، `cloud_sync/`، `sync/`، `scale_protocols/`… |
| presentation | `lib/presentation/` | شاشات حسب الميزة، ومجلدات `*_picpos/` لإعادة تصميم PicPos |
| web | `lib/web/` + `lib/main_web_entry.dart` | عميل مرآة بنطاق محدود |

## 3. المبادئ

1. **PicPos/UralCash من محرّك واحد:** الفرق في الواجهة والهوية؛ فرّع الواجهة بـ`Brand.isPicPos`.
2. **الويب: قراءة فقط عبر `/webdb` بسياسة جداول، والكتابة عبر HTTP API** بصلاحية المستخدم.
3. **أسرار الخادم مفصولة عن مفتاح القاعدة**؛ ومفتاح القاعدة يُرحَّل يدويًا بتأكيد في الإقلاع التالي.
4. **الأخطاء المركزية في API** (`ApiErrors`): لا تسريب لتفاصيل داخلية للعميل.
5. **الملفات الضخمة تُقسَّم بـ`part`/`part of` + `extension`، نقلًا بحتًا بلا تغيير سلوك**، وتُخفَّض عتبتها في CI ولا تُرفع.
6. **ملفات جديدة ≤ 30KB**؛ **لا أسرار في الريبو** (`tool/check_no_secrets.ps1`، `.gitleaks.toml`).
7. يُفضَّل أن تمر الشاشات عبر Repositories/providers لا `AppDatabase` مباشرةً (غير مُطبَّق بالكامل اليوم).

## 4. حالة التقسيم (مقاسة، وقت الكتابة)

| الملف الأم | الحجم تقريبًا | أجزاؤه | عتبة CI (بايت) |
|---|---|---|---|
| `lib/data/database/database.dart` | 40.0KB | `tables/` `daos/` `migrations/` `database_*.dart` | 40500 |
| `lib/services/api/api_handler.dart` | 7.8KB | `routes/` | 8200 |
| `lib/services/api/api_data_handler.dart` | 6.8KB | `data/` | 7000 |
| `lib/data/database/daos/treasury_dao.dart` | 18.1KB | `daos/treasury_*` | 18500 |
| `lib/services/scale_protocols.dart` | 8.7KB | `scale_protocols/` | 9000 |
| `lib/services/client_write_interceptor.dart` | 1.7KB | ملفات `interceptor/cwi_*` (ليست `part`) | 2000 |
| `lib/presentation/pos/screens/pos_table_service_screen.dart` | 6.2KB | — | 70000 |
| `lib/presentation/screens/tables_screen.dart` | 11.9KB | — | 70000 |

`treasury_voucher_dao.dart` (≈38.8KB، عتبة 39000) ما زال كبيرًا. `users_management_screen.dart` ≈34KB وليس تحت بوابة CI.
العتبات في `.github/workflows/ci.yml` (خطوة «Check God-File size thresholds»).

## 5. أين أقرأ بعد ذلك

- [`README.md`](README.md) — المكوّنات، البناء، التشغيل. [`PRODUCT.md`](PRODUCT.md) · [`DESIGN.md`](DESIGN.md).
- [`docs/ARCHITECTURE-MAP.md`](docs/ARCHITECTURE-MAP.md) — خريطة المجلدات، أنماط `part`، وصفات API/شاشة/جدول/ترحيل، الاختبارات وCI، الأمن.
- المزامنة: [`docs/handoff/SYNC_ARCHITECTURE.md`](docs/handoff/SYNC_ARCHITECTURE.md). الجوال والسيرفر: [`docs/mobile/ARCHITECTURE-I.md`](docs/mobile/ARCHITECTURE-I.md)، [`ARCHITECTURE-M.md`](docs/mobile/ARCHITECTURE-M.md)، [`ARCHITECTURE-MC.md`](docs/mobile/ARCHITECTURE-MC.md).
- الاختبارات: [`docs/testing/E2E.md`](docs/testing/E2E.md). الأمن: [`docs/security/`](docs/security/).

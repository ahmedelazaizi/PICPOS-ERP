# UralCash ERP — Sync Architecture Documentation
## استراتيجية المزامنة بين السيرفر والعميل

---

## 1. نظرة عامة (Overview)

يدعم النظام 4 أوضاع تشغيل:
- **مستقل (Standalone)**: قاعدة بيانات واحدة، لا مزامنة
- **سيرفر (Server)**: يخدم العملاء عبر HTTP API + WebSocket
- **عميل (Client)**: يتصل بالسيرفر ويزامن البيانات دورياً
- **مرآة (Mirror — Spec 097 + 125)**: قاعدة بيانات محلية مرتبطة بسيرفر HQ
  بشكل ثنائي الاتجاه — تستقبل البيانات للعرض، وتُرسِل العمليات اللي
  يتم تنفيذها عليها من الـ admin/managers. **نسخة إدارية** لصاحب الشركة
  أو المدير المالى أو مدير كل الفروع — مش viewer. تستخدم نفس الـ outbox
  pattern للعميل لكن مع admin-tier write capability (قاعدة R9 — الـ broadened
  `isClientMode` gate، انظر §8 أدناه). **للتفصيل الكامل
  لدور المرآة، راجع §8 أدناه.**

### المبدأ الأساسي
> **السيرفر هو المصدر الوحيد للحقيقة (Single Source of Truth)**

العميل يحتفظ بنسخة محلية مشفرة (SQLite + sqlcipher) للعمل offline، ويزامن مع السيرفر عند الاتصال.

---

## 2. آلية المزامنة (Sync Mechanism)

### 2.1 المزامنة التزايدية (Incremental Sync)
```
Client → GET /api/sync/{table}?since={timestamp}
Server → JSON array of records updated since {timestamp}
Client → Upsert records locally using SyncStrategy
```

### 2.2 ترتيب المزامنة (FK Dependency Tiers)
```
Tier 0: Settings, Accounts, Categories, Units, Roles, Permissions,
        FiscalYears, CostCenters, Regions, DocumentSequences, AccountingPeriods
Tier 1: Branches, Warehouses, Safes, RolePermissions, Users, AccountMappings
Tier 2: UserBranchAccess, UserRegionAccess, Products, ProductBarcodes,
        ProductUnits, ProductBatches, Parties, Offers, OfferItems
Tier 3: Shifts, Sales + Items, Purchases + Items, JournalEntries + Lines,
        SafeTransactions, StockMovements, InventoryBalances,
        CommercialPapers, HeldOrders + Items, Payments, PaymentAllocations,
        SalesOrders + Items, PurchaseOrders + Items
```

### 2.3 WebSocket (Real-time Push)
```
Server → Client: { "event": "data_changed", "table": "sales_invoices" }
Server → Client: { "event": "record_deleted", "table": "sales_invoices", "recordId": 42 }
```
عند استلام حدث `data_changed`: العميل يبدأ مزامنة تزايدية للجدول المتأثر.
عند استلام حدث `record_deleted`: العميل يحذف السجل محلياً (soft-delete).

---

## 3. استراتيجيات حل التعارضات (Conflict Resolution)

### 3.1 السياسات المتاحة

| السياسة | الوصف | الاستخدام |
|---------|-------|----------|
| **serverWins** | السيرفر هو المرجع — يتم استبدال النسخة المحلية | البيانات الرئيسية (منتجات، حسابات، إعدادات) |
| **appendOnly** | لا تعارض — كل سجل فريد بالـ ID | المعاملات (فواتير، قيود، حركات مخزون) |
| **lastWriteWins** | مقارنة `updatedAt` — الأحدث يفوز | بيانات الأطراف (تعديل اسم/هاتف من فروع متعددة) |
| **clientWins** | نسخة العميل أولوية | نادر — مسودات محلية فقط |

### 3.2 توزيع السياسات على الجداول

```
serverWins:  products, categories, accounts, branches, warehouses,
             safes, users, roles, permissions, settings, offers,
             sales_invoices (updates: isDeleted, isLocked, status)

appendOnly:  journal_entries, safe_transactions, stock_movements,
             inventory_balances, purchase_invoices, commercial_papers

lastWriteWins: parties (customer/supplier edits)
```

### 3.3 تسجيل التعارضات (Conflict Logging)
كل تعارض يُسجَّل في جدول `sync_conflict_log` مع:
- الجدول المتأثر
- ID السجل
- القرار (server_wins / client_wins)
- بيانات العميل والسيرفر (JSON)
- السبب
- الطابع الزمني

---

## 4. نمط الكتابة المزدوجة (Dual-Write Pattern)

### 4.1 كتابة العميل
عندما ينشئ العميل فاتورة/عملية:

```
1. إرسال للسيرفر (fire-and-forget) عبر ClientWriteInterceptor
2. تخزين محلي خفيف (cache فقط — بدون مخزون/محاسبة/خزينة)
3. السيرفر يعالج العملية كاملة (مخزون + GL + خزينة)
4. المزامنة التالية تجلب النتيجة النهائية من السيرفر
```

### 4.2 Outbox Pattern
إذا فشل الإرسال للسيرفر:
```
1. العملية تُحفظ في sync_outbox
2. OfflineSyncWorker يحاول إعادة الإرسال دورياً
3. عند نجاح الإرسال → يُحذف من الـ outbox
4. عند فشل متكرر (>3 محاولات) → يُسجَّل كخطأ
```

---

## 5. حماية سلامة البيانات (Data Integrity)

| الآلية | الوصف |
|--------|-------|
| **integrityHash** | HMAC-SHA256 على الفواتير المرحَّلة — كشف التلاعب |
| **deletedBy** | تسجيل من قام بالحذف — audit trail |
| **isLocked** | قفل الفواتير بعد الترحيل — منع التعديل |
| **failed_autoposts** | تسجيل فشل الترحيل التلقائي — تنبيه المدير |
| **field_audit_logs** | تتبع التغييرات على الحقول الحرجة |
| **sync_conflict_log** | تسجيل كل تعارض مع بيانات الطرفين |

---

## 6. الحدود والقيود (Limitations)

1. **الوحدات التالية تعمل محلياً فقط** (لا مزامنة):
   - الموارد البشرية (HR) — إدارة محلية لكل فرع
   - المطعم (Tables/Kitchen) — خاص بكل موقع
   - القوالب والطباعة — إعدادات محلية
   - سجلات التدقيق — لأمان كل جهاز

2. **اتجاه المزامنة**: Server → Client (أحادي الاتجاه)
   - العميل لا يرسل بيانات sync مباشرة
   - الكتابة عبر HTTP API → السيرفر يعالج → المزامنة تجلب النتيجة

3. **الحد الأقصى للانقطاع**: لا حد نظري، لكن يُفضل ألا يتجاوز 7 أيام
   - بعد ذلك قد تتراكم تغييرات كبيرة تبطئ المزامنة الأولى

---

## 7. المزامنة الأولى للعميل (Client First Sync — Spec 001)

### 7.1 المشكلة
عند فتح قاعدة البيانات لأول مرة، النظام لا يعرف الوضع (`isClientMode` غير محدد بعد)،
فيقوم الـ seeder بإدراج بيانات افتراضية: فرع رئيسي، مخزن، وحدات، خزائن، شجرة حسابات،
وثلاث شركات توصيل. عندما يختار المستخدم لاحقاً وضع **العميل** ويربط الجهاز بسيرفر،
السيرفر يحوي نسخه الخاصة من نفس البيانات بـ `globalId` و `id` مختلفين، فتظهر صفوف
مكرَّرة على العميل (فرعان "الفرع الرئيسي"، شركتا "طلبات"، إلخ).

### 7.2 الحل: `ClientFirstSyncService`
يُستدعى من Setup Wizard **مرة واحدة فقط** بعد الإقران الناجح:

```
1. wipeSeededMasterDataForClient()        ← يمسح الصفوف الزرعية محلياً
2. SyncService.fullSync()                 ← يجلب البيانات من السيرفر
3. settings['client_first_sync_completed'] = 'true'
```

العقد: في أي وقت **إما متزامن بالكامل أو فارغ بالكامل**. لا حالة وسطى.
لو فشلت أي خطوة، يبقى الـ flag = `false` والمحاولة التالية تعيد المسح.

### 7.3 ثلاث طبقات للـ Deduplication
حتى لو جاء صف من السيرفر بعد wipe ناقص (لأي سبب)، استراتيجيات الـ sync تحاول
المطابقة على ثلاث طبقات قبل إدراج صف جديد:

**`branch_sync_strategy`:**
| Tier | المطابقة | حالة الاستخدام |
|---|---|---|
| 1 | `globalId` | الحالة الطبيعية (بعد wipe ناجح) |
| 2 | `name` | seed محلي بـ globalId مختلف لكن نفس الاسم |
| 3 | server `id` | legacy fallback |

**`party_sync_strategy`:**
| Tier | المطابقة | حالة الاستخدام |
|---|---|---|
| 1 | `globalId` | الحالة الطبيعية |
| A | `name` + `phone` | عميل/مورد حقيقي بنفس الهاتف على الطرفين |
| B | `isDeliveryCompany` + `priceLevel` | شركة توصيل ('talabat'/'careem'/'ashyae') |

> **متعمَّد ألا نطابق على الاسم وحده** للأطراف، لأن المستخدمين عندهم أطراف
> حقيقية بنفس الاسم (عدة عملاء "أحمد" بدون هاتف)، والدمج العشوائي يُتلف بيانات.

### 7.4 Telemetry — `SyncWarning`
عند نجاح المطابقة عبر طبقة fallback (Tier 2/3 للفروع، Tier A/B للأطراف)،
الاستراتيجية تكتب سطر `[SYNC-WARN]` في `Documents/uralcash_login_log.txt`
عبر `DiagnosticLogger`. هذا **ليس خطأ** — العملية نجحت، لكن استخدام طبقة
أضعف يشير إلى انحراف بيانات في الميدان يستحق التحقيق.

تنسيق السطر:
```
[2026-04-28T...] [SYNC-WARN] branches matched on name fallback (name="..." serverId=5 serverGlobalId=... localId=1 localGlobalId=...)
```

---

## 8. دور المرآة (Mirror Role) — نسخة ادارية (Spec 125)

**المرآة ليست viewer.** هى نسخة كاملة وفعّالة من النظام، مخصصة لدور إدارى محدد، لها نفس صلاحيات الكتابة تقريباً مثل السيرفر — لكن **عبر السيرفر** (مش كتابة محلية).

### 8.1 من يستخدمها

- صاحب الشركة (Owner)
- المدير المالى (Financial Manager)
- مدير كل الفروع (Multi-branch Manager)

أى دور يحتاج رؤية شاملة + قدرة على تنفيذ إجراءات إدارية على بيانات أى فرع دون الحاجة للذهاب الفعلى للفرع.

### 8.2 ما تفعله المرآة

- **قراءة شاملة**: تقارير عامة، إدارة المستخدمين، إعدادات النظام، كل الفروع، كل المخازن.
- **كتابة عبر السيرفر**: كل write يمر عبر `WriteRouter` (انظر R9) ويُوجَّه لـ `ServerProxy` → السيرفر يُنفّذ العملية → النتيجة تعود للمرآة عبر sync.
- **عمليات إدارية**: فتح/إغلاق ورديات، اعتماد voucher، تعديل permissions، إدارة الـ chart of accounts، تحرير journal entries.

### 8.3 ما لا تفعله المرآة

- ❌ **لا تشغّل POS مباشرة** — POS مهمة الفرع نفسه. المرآة قد تعرض POS للمراقبة لكن لا تكتب فاتورة POS كأنها بائعة من الفرع.
- ❌ **لا تكتب محلياً** — كل write يُرفض من `WriteRouter` لو الاتصال بالسيرفر منقطع (تصبح read-only تلقائياً عبر `MutationGuard`).
- ❌ **لا تستهلك local-only services** — مثلاً لا تتصل مباشرة بـ PLU/scale، لا تستقبل KOT printer، لا تطبع KOT.

### 8.4 الفرق عن السيرفر

| | السيرفر | المرآة |
|---|---|---|
| من يخدم؟ | العملاء (Clients) عبر HTTP | المستخدم الإدارى فقط |
| الـ HTTP API | يستضيفه | يستهلكه |
| الكتابة | محلية مباشرة | عبر السيرفر |
| pairing | لا يحتاج | يحتاج (الـ MirrorPairingService) |
| heartbeat | لا | نعم (`MirrorHeartbeatService`) |

### 8.5 الفرق عن العميل العادى

| | العميل (Client) | المرآة |
|---|---|---|
| الغرض | جهاز فرعى للـ POS فى فرع | إدارة شاملة |
| Branch isolation | مقيد بـ branch واحد (`client_branch_id`) | لا قيد — يرى كل الفروع |
| الـ write scope | محدود (مبيعات الفرع، مردود، voucher محلى) | شامل (كل ما السيرفر يقدر يفعله) |
| Permissions | role-based عادى | admin-tier (cross-branch elevation) |
| UI | محسّن للـ POS | محسّن للتقارير/الإدارة |

### 8.6 قواعد التصميم — حماية الـ split-brain

أى feature جديد يلمس مسار المرآة لازم يحترم:

1. **R9 — broadened isClientMode gate**: استخدم `SyncInterceptor.isClientMode` (true لـ client + mirror) لـ gate أى write يجب أن يمر عبر السيرفر. لا تستخدم `NetworkService.instance.isClient` (false لـ mirror = bug).
2. **DeploymentModeCommitter (Spec 125)**: كل تغيير لـ `network_mode` يمر عبر `lib/services/deployment/deployment_mode_committer.dart` — مش setting مباشر. الـ grep test فى `test/static/no_direct_network_mode_writes_test.dart` يحمى الـ invariant.
3. **MirrorState.isConfigured**: شرط ضرورى لتشغيل المرآة. لو غير مهيأ، `NetworkService.reconcileWithDb` يفشل loud (شاشة Fatal العربية) بدلاً من silent downgrade لـ standalone.
4. **R8 — ClientFirstSyncService.mirror()**: الـ first-sync للمرآة يستخدم flag منفصل `mirror_first_sync_completed` (مش يشارك العميل). لا تخلطهم.

### 8.7 مراجع

- `lib/services/mirror_pairing_service.dart` (Spec 097)
- `lib/services/mirror_state.dart`
- `lib/services/mirror_heartbeat_service.dart`
- `lib/services/sync/client_first_sync_service.dart` — الـ `.mirror()` constructor
- `lib/services/write_router.dart` — توجيه الكتابة
- `lib/services/deployment/deployment_mode_committer.dart` (Spec 125)
- `lib/presentation/screens/fatal_setup_error_screen.dart` (Spec 125)
- قواعد المزامنة في وضع العميل (R8 + R9) — انظر §7 و§8 أعلاه

### 8.8 قاعدة حمراء للمستقبل

> **لا تكتب أى feature يتعامل مع المرآة على افتراض إنها viewer.**
> المرآة تكتب، تُعدّل، وتُوافق على عمليات حساسة. أى منطق يحجب الكتابة عنها تماماً = bug فى الفهم. الصحيح: الكتابة تمر عبر السيرفر (R9)، لا تُنفَّذ محلياً.

### 8.9 Mirror Cache Integrity (Spec 131)

مكمل لـ §8 — يحدد كيف تظل الـ master-data cache فى المرآة طبق الأصل من السيرفر.

**العقد**: كل صف فى الـ master-data tables على المرآة يجب أن يطابق نفس الصف على السيرفر (نفس id ، نفس name ، نفس branch_id). لا توجد master-data rows مرآة-فقط.

**ثلاث طبقات دفاع**:

1. **Pair-time (FR-001/002/003)** — كل mirror pairing يستدعى `ClientFirstSyncService.mirror.performFirstSync()` الذى يـ:
   - يـ wipe `wipeSeededMasterDataForClient` (متضمنة الجداول السبعة + 6 settings keys: `pos_default_warehouse_id` ، `pos_default_safe_id` ، `pos_default_customer_id` ، `pos_default_branch_id` ، `pos_default_cost_center_id` ، و LIKE-prefix `pos_default_warehouse_branch_%`).
   - يـ pull من السيرفر عبر `DeltaPullService`.
   - يضبط flag `mirror_cache_integrity_v1_applied = 'true'` (الـ A5 upgrade trigger).
   - الـ wipe كله داخل `transaction()` واحد (FR-012 atomicity).

2. **Sale-time pre-flight (FR-005)** — `SalesTransactionOrchestrator._preflightSaleParity` يفحص قبل أى DB write أن:
   - `warehouse_id` ، `branch_id` ، `customer_id` (لو غير adhoc) ، `cost_center_id` (لو غير null) ، و `safe_id` (لكل من cash/bank/click لو غير null) كلها موجودة فى الـ local cache.
   - First-miss-wins: أول id مفقود يُلقى `MirrorCacheDivergenceException`.
   - الـ gate: `SyncInterceptor.isClientMode` (covers client + mirror؛ server + standalone bypass).

3. **Fatal-screen recovery (FR-006)** — كلا الـ raise sites (pre-flight + server 500 "Strict Mapping Violation") يمران عبر `MirrorDivergenceHandler.surface()` → `runApp(FatalSetupErrorApp(kind: mirrorCacheDivergence))`. زر "إعادة المزامنة مع السيرفر" يستدعى `performFirstSync` مرة أخرى ويُعيد الـ POS cart إلى حالة فاضية (الـ user يُعيد إدخال السلة بعد الاستعادة).

**Upgrade trigger (A5)**:
- `NetworkService.reconcileWithDb` يـ check `mirror_cache_integrity_v1_applied` على كل boot فى وضع المرآة.
- لو الـ flag غائب → `ReconcileOk(forceFirstSync: true)`.
- `main.dart` يلتقط ذلك ويستدعى `performFirstSync()` بصمت قبل تشغيل الـ UI.

**Diagnostic breadcrumbs (FR-007)** — 5 tags، كلها عبر `DiagnosticLogger.log` (مش `debugPrint`):
- `[MIRROR-WIPE] removed warehouses=N ...` — مرة لكل wipe.
- `[MIRROR-FIRST-SYNC] pulled warehouses=N ... duration=Tms` — مرة لكل sync.
- `[MIRROR-UPGRADE-FORCED-SYNC] triggered_at_boot reason=upgrade` — مرة فى عمر الـ install.
- `[MIRROR-MASTERDATA-CHECK] sale=<#> ... all_resolved=true|false` — مرة لكل sale على mirror/client.
- `[MIRROR-CACHE-DIVERGENCE] kind=<table>_missing requested=N cached=[...] server_response=<text> origin=pre-flight|server-500` — مرة لكل divergence event.

**Admin audit (FR-010)** — `showMirrorParityAuditDialog` فى Settings → "تدقيق مزامنة المرآة" (visible فقط فى وضع mirror). يعرض الـ counts المحلية + زر type-to-confirm لإعادة المزامنة الكاملة. يُصدر `[MIRROR-AUDIT-START]` / `[MIRROR-AUDIT-OK]`.

**ملفات المرجعية**:
- `lib/data/database/database_seeder.dart` — `wipeSeededMasterDataForClient` (extends settings DELETEs)
- `lib/services/sync/mirror_settings_keys.dart` — الـ canonical literals
- `lib/services/sync/mirror_cache_divergence_exception.dart` — الـ exception type + Arabic names
- `lib/services/sync/mirror_divergence_handler.dart` — installRunner / surface seam
- `lib/services/sync/client_first_sync_service.dart` — performFirstSync + breadcrumbs
- `lib/services/network_service.dart` — upgrade trigger detection
- `lib/data/repositories/sales_transaction_orchestrator.dart` — _preflightSaleParity + catch
- `lib/presentation/screens/fatal_setup_error_screen.dart` — mirrorCacheDivergence variant
- `lib/presentation/widgets/settings/mirror_parity_audit_dialog.dart` — admin audit

**القاعدة الحمراء**:
> globalId-based threading للـ master-data references على الـ wire هو Spec 132 (Master Data GlobalId Threading). Spec 131 يعتمد فقط على id-equality بعد الـ wipe + first-sync.

---

## 9. PG Schema Parity (Spec 130)

السيرفر فى وضع PostgreSQL يحتوى schema يجب أن يطابق Drift schema المُولَّد بالكامل. Spec 130 يضيف **defense-in-depth catch-all** يضمن هذه المطابقة بدون لمس الـ creation paths الموروثة.

### 9.1 طبقات الإصلاح

```
boot beforeOpen → Phase 1  _createPostgresCompatLayer (strftime + bool ops)
              → Phase 2  _ensureSchemaDefaults (SQLite only)
              → Phase 2b _ensureDatabaseIntegrity (PK/UNIQUE constraints)
              → Phase 2c _ensurePostgresSyncInfrastructure (sync columns + triggers)
              → Phase 2d _ensurePostgresSchemaParity ← Spec 130 NEW
              → Phase 3+ seed + permissions + patches
```

Spec 130 لا يلمس `_createAllForPostgres()` ولا `_ensurePostgresSyncInfrastructure()`. الـ parity pass يعمل **بعدهما** كـ generic catch-all (Clarification Q3).

### 9.2 نطاق الـ self-heal

| Entity Kind | إجراء الـ pass | DDL |
|-------------|---------------|-----|
| Table مفقود | يُنشَأ بـ PG-dialect DDL | `CREATE TABLE IF NOT EXISTS "..." (...)` |
| Column مفقود | يُضاف للجدول الموجود | `ALTER TABLE "..." ADD COLUMN IF NOT EXISTS ...` |
| Index مفقود | يُنشَأ عبر Migrator | `CREATE INDEX IF NOT EXISTS ...` |
| FK constraint مفقود | يُسجَّل warning (Drift API limitation) | — |
| Trigger/View | `[PG-PARITY-SKIP]` صراحة | out of scope |
| Type/nullability drift | `[PG-PARITY-DRIFT]` warn-only (Q4) | لا ALTER COLUMN TYPE |
| Extra entity (في PG، ليس في Drift) | `[PG-PARITY-EXTRA]` warn-only | لا DROP (FR-004) |

### 9.3 السلوك عند الفشل

DDL exec فشل بـ permission denied / connection lost → `PgSchemaParityException` يُرمَى → `main.dart` يلتقطه → `FatalSetupErrorApp` بـ `kind: pgSchemaParity`:

- شاشة كاملة بـ orange accent + database icon
- 3 أزرار: "إعادة محاولة الإصلاح الذاتى" + "خيارات المطور" + "إعادة اعداد البدء"
- Block-all (Clarification Q2): لا reads ولا writes حتى الإصلاح

### 9.4 Breadcrumbs

| Tag | متى |
|-----|-----|
| `[PG-PARITY-OK]` | كل boot، aggregate `healed=N drift=M duration=Tms` |
| `[PG-PARITY-HEAL]` | كل DDL نجاح (table/column/index) |
| `[PG-PARITY-SKIP]` | كل Trigger/View/unknown kind |
| `[PG-PARITY-DRIFT]` | type mismatch أو nullability أو index create فشل |
| `[PG-PARITY-EXTRA]` | جدول PG ليس فى Drift |
| `[PG-PARITY-FATAL]` | DDL غير قابل للتجاوز — يرفع PgSchemaParityException |

### 9.5 Tests

- `test/unit/pg_schema_parity_static_test.dart` — invariants (FR-008 transaction guard، FR-004 no destructive DDL، DriftSqlType coverage)؛ يجرى فى `flutter test` بدون PG.
- `test/integration_pg/pg_schema_parity_bug_repro_test.dart` — reproduces the `category_station_mappings` field bug.
- `test/integration_pg/pg_schema_parity_integration_test.dart` — 6 self-heal scenarios + Fatal-path. يجرى عبر `melos test:pg`.
- `scripts/git-hooks/pre-commit-schema-parity.ps1` — pre-commit reminder، warning-only (Clarification Q5).

### 9.6 قاعدة حمراء للمستقبل

> **لا تُغلِّف `_ensurePostgresSchemaParity()` فى `db.transaction(...)`.**
> الـ pass لازم يجرى **خارج** أى transaction نشطة. السبب: لو table مفقود ظهر داخل transaction، PG يصدر `25P02 current transaction is aborted` على كل query لاحق — وهى بالضبط cascade الـ bug الميدانى الذى دفع Spec 130. الـ static test يُمسك أى regression.

---

*آخر تحديث: 2026-05-25 — أُضيف §9 بعد دمج Spec 130 (PG Schema Parity). آخر تحديث سابق: 2026-05-25 — أُضيف §8 بعد دمج Spec 125 (Mirror Foundation). آخر تحديث سابق سابق: 2026-04-28 — أُضيف القسم §7 بعد دمج Spec 001 + Spec 002.*

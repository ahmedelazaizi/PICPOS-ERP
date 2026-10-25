# مراجعة تطبيق «PicPos مخازن» — المراحل W2…W5 (إعادة بناء بلا تقرير منفّذ)

> **النوع:** مراجعة قراءة فقط (read-only audit). لم يُعدَّل كود المنتج، ولم يُنفَّذ أي commit، ولم يُشغَّل `flutter` ولا `dart` ولا أي اختبار (عامل آخر يشغّل مختبر Android، وأقفال Flutter تتعارض).
> **السجل الموحّد للنتائج:** [FINDINGS.md](<FINDINGS.md>) (المعرّفات `WH-001…WH-030`).
> **سياسة الأدلة:** ملف المالك «طلب مراجعه.txt» §12. كل حكم موسوم بأحد ثلاثة:
> - **VERIFIED-BY-READING**: قرأتُ الكود بنفسي، ومعه `file:line`.
> - **INFERRED**: استنتاج من القراءة لم يُثبَت بالتشغيل.
> - **NOT_RUN**: فحص يحتاج تشغيلًا لم يُنفَّذ.
>
> لا يُدّعى هنا نجاح أي اختبار.

## 0. نقطة المراجعة والبيئة

| البند | القيمة |
|---|---|
| الفرع | `feat/tables-reservations-permissions` |
| HEAD | `1ff2b6c1cad5b6f9a654c87082dcf3c93bc1b69f`، وهو commit المنفّذ نفسه «feat(warehouse,lab): PicPos Warehouse W2-W5 …» بتاريخ 2026-10-25 |
| الأساس المقارَن | `909f2d38` (batch 3: manager console، وP5 four-eyes) |
| حجم التغيير | 181 ملفًا، +7748/−122 (`git log -1 --stat 1ff2b6c1`) |
| تغييرات محلية غير ملتزمة (ليست من هذه المراجعة، ولم تُلمس) | `Cairo,Noto_Naskh_Arabic/`، `test/repro_mirror/`، «تصميم شاشات فواتير PicPos-handoff/»، «صور لاعادة تصميم الشاشات الموضحه/»، «طلب مراجعه.txt» (كلها untracked) |
| البيئة | Windows، قراءة ملفات وأوامر `git` فقط |
| حدود الصلاحية | لم يُتحقَّق من حالة الفرع البعيد (لا `fetch`)؛ HEAD المحلي هو المرجع |

**مصادر إعادة البناء:**
- الكود في الشجرة.
- قسم «العقد المنفَّذ — W2…W5» الذي أضافه المنفّذ إلى الخطة ([الخطة](<../../plans/2026-10-23-warehouse-app-plan.md>) من السطر 541). عومل هذا القسم **كادّعاء** يُتحقَّق منه، لا كدليل.
- [DEVICE-LAB-RESULTS.md](<../2026-10-24-mirror-and-admin-login/DEVICE-LAB-RESULTS.md>).

القراءة الواسعة لملفات الشاشات والاختبارات جاءت من قارئَين فرعيين read-only. كل ادعاء منهما بُني عليه حكم في FINDINGS أعدتُ التحقق منه بنفسي بقراءة الموضع المذكور، مثل `transfer_pages.dart:69`، و`line_picker.dart:10,19`، وغياب أي استدعاء `convert` من التطبيق.

---

## 1. الحكم المختصر

**«غير جاهز بسبب موانع مثبتة»**، وذلك لإقران هواتف موظفين حقيقيين وتشغيل W2–W5 على بيانات فعلية. الموانع:

1. **WH-001 (Critical):** أمر شراء استُلم جزئيًا من الهاتف ثم حُوِّل يبقى قابلًا للتحويل الكامل من سطح المكتب. النتيجة مخزون وذمة مورد مزدوجان.
2. **WH-002 (High):** مسار R-A غير قابل للاستعمال فعليًا. مسار `convert` لا يصل إليه إلا جهاز مخازن، ولا توجد له أي واجهة، ولا يرى المحاسب الاستلامات على سطح المكتب. فالاستلامات تتكدّس في `submitted`.
3. **WH-003 (High):** تحويل الاستلام لفاتورة يُسقط خصم أمر الشراء وضريبته.
4. **WH-004 (High):** طابور الـoutbox غير مربوط بالمستخدم. عمليات مستخدم سجّل خروجه تُرسَل بهوية من يدخل بعده.
5. **WH-005 (High):** أي استثناء غير متوقع يصبح `500` بلا نص، والعميل يعدّه «قابلًا لإعادة المحاولة»، فيحجب الطابور كله إلى الأبد. من أسبابه فترة مقفلة، وحساب غير مربوط، وتكرار `globalId`.
6. **WH-017 (Medium، مانع إجرائي):** بنود الخطة الحاكمة G-2 (فحص العلامة على الـAPK) وG-3 (SEC-006) ما زالت مفتوحة بحسب الخطة نفسها، والخطة تمنع إقران هاتف موظف قبلها. كذلك شغّل مختبر الأجهزة خادمًا من `909f2d38`، أي بلا كود W2–W5.

**ما ثبت جيّدًا بالقراءة:**
- سجل أوامر idempotent داخل معاملة الأثر.
- آلات حالة مع حراسة `row_version`.
- فحص صريح يمنع السالب في dispatch وسند الإخراج.
- four-eyes على الخادم دون استثناء لمدير النظام.
- عزل النطاق (فرع الجهاز ∩ مخازن المستخدم) في **كل** مسارات `/api/m1/wh/*`.
- حصر جهاز المخازن بثلاث بادئات.
- DTO العدّاد بلا كميات.
- منفذ طباعة صادق لا يدّعي النجاح.

---

## 2. ما بُني فعلًا

### 2.1 قرار التخزين: بلا Drift وبلا ترحيل (VERIFIED-BY-READING)
- ثلاثة جداول SQL خام في [wh_mobile_docs_schema.dart](<../../../lib/data/database/wh_mobile_docs_schema.dart#L27-L52>): `wh_mobile_docs`، و`wh_mobile_doc_lines`، و`wh_mobile_doc_events`.
  - القيود: `global_id UNIQUE` و`line_global_id UNIQUE` و`command_id UNIQUE`، مع أربعة فهارس.
  - تُنشأ **كسولًا** بـ`CREATE TABLE IF NOT EXISTS`، مرة واحدة لكل instance عبر `Expando` (:16-19).
  - أنواع PG/SQLite مفرّعة (`SERIAL`/`AUTOINCREMENT`، و`DOUBLE PRECISION`/`REAL`، و`BIGINT`).
- **لماذا هذا الشكل:** `database.g.dart` لا يمكن إعادة توليده، و`schemaVersion` يبقى 196، ولا يُمسّ `database.dart` ولا `database_startup.dart`. هذا انحراف معلن عن «الترحيل الوحيد» في W2، ومقبول تقنيًا. الثمن:
  - لا ترحيل مختبَر.
  - لا FK من `wh_mobile_doc_lines.product_id` إلى المنتجات.
  - فشل إنشاء المخطط يُخزَّن في الـExpando بلا إعادة محاولة (WH-025).
- **لا مزامنة:** أُضيفت الجداول إلى `_unsyncedBaseline` في `test/structural/sync_coverage_guard_test.dart`. المستندات تعيش على الحاسوب الرئيسي وحده. قرار المالك هنا مفتوح (WH-021).
- **الأثر المخزني والمحاسبي** يمرّ عبر الدوال القائمة:
  - `adjustStock`.
  - `consumeBatchesForIssue`.
  - `createPurchaseInvoice`.
  - `finalizeCycleCountTask`.
  - `moveStockBetweenBins`.
  - `createJournalEntry`: قيود GIT صريحة في `wh_transfer_service.dart:42-69`.

  لا كتابة مباشرة في `inventory_balances`. الكتابة المباشرة الوحيدة على جداول قائمة:
  - `purchase_order_items.received_quantity` ([wh_receipt_handlers.dart:185-189](<../../../lib/services/api/m1_wh/wh_receipt_handlers.dart#L185-L189>)).
  - `product_batches` (`_restoreLot`، و`insertBatch`).
  - `cycle_count_items` (إدراج الأصناف غير المتوقعة).

### 2.2 القواعد العامة لكل مسار (VERIFIED-BY-READING، [wh_http.dart](<../../../lib/services/api/m1_wh/wh_http.dart#L85-L116>))
1. **الجهاز:** `lanDeviceKind == 'warehouse'` مع `lanDeviceBranchId` و`lanDeviceId`، وإلا `403 device_scope` (:93-95).
2. **المستخدم والصلاحية:** `ApiUserCtx.requirePermission` لكل كود (:96-99). يفحص `isUserLive`، ويقبل بديلًا عنه بصمة P5 فقط.
3. **النطاق:** `resolveWhScope` (:101). المعادلة: مخازن فرع الجهاز النشطة غير المحذوفة ∩ `getWarehouseScopeForUser`. يُشترط وصول المستخدم إلى الفرع، ويفشل مغلقًا ([wh_scope.dart:23-47](<../../../lib/services/api/m1_wh/wh_scope.dart#L23-L47>)).
4. **الكتابات:** `X-Idempotency-Key` بطول ≥ 8 (:45-49)، ثم `WhDocStore.command`:
   - الفحص والأثر وسطر `wh_mobile_doc_events` في **معاملة واحدة**.
   - الإعادة تعيد النتيجة المخزّنة مع `replayed:true`.
   - نفس المفتاح بجسم مختلف يعطي `409 idempotency_conflict`.
   - البصمة sha256 لـJSON مرتّب المفاتيح يضم `action` والجسم ومعرّف المستند ([wh_doc_store.dart:269-293](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L269-L293>)).
5. **الأخطاء غير المتوقعة:** `500 internal` بلا نص (:113-115)، حتى لا تتسرب كميات. لهذا أثر جانبي على العميل (WH-005).

### 2.3 المسارات المسجّلة (VERIFIED-BY-READING، [api_routes_m1_wh.dart](<../../../lib/services/api/routes/api_routes_m1_wh.dart>))
أُضيفت 25 سطرًا إلى `test/golden/api_routes.txt`، وهو عدد يطابق المسارات الجديدة.

| الطريقة والمسار | الصلاحيات (بعد `warehouse_mobile_access`) | النطاق | Idempotency والحماية |
|---|---|---|---|
| `GET /api/m1/info` | لا شيء (exempt) | — | — |
| `GET /api/m1/wh/session` | — | النطاق المحسوب | قراءة |
| `GET /api/m1/wh/items?barcode=\|q=` | `inventory_view` | أرصدة النطاق فقط، و`blind:true` للعدّاد | قراءة |
| `GET /api/m1/wh/po[?warehouse=]` | `goods_receipt_mobile` | `?warehouse` يُرفض خارج النطاق | قراءة |
| `GET /api/m1/wh/po/<ref>` | `goods_receipt_mobile` | مخزن الأمر | قراءة |
| `POST /api/m1/wh/po/<ref>/receipts` | `goods_receipt_mobile` | مخزن الأمر، والأمر `sent/confirmed` وغير محوَّل | مفتاح + `lineGlobalId` فريد؛ الإلحاق للمنشئ فقط |
| `POST /api/m1/wh/receipts/<gid>/submit` | `goods_receipt_mobile` | مخزن المستند، والمنشئ فقط | مفتاح + انتقال `draft→submitted` |
| `GET /api/m1/wh/receipts?state=` | `goods_receipt_mobile` | النطاق + `created_by = me` | قراءة |
| `POST /api/m1/wh/receipts/<gid>/convert` | `purchases_create` | مخزن المستند | مفتاح + `submitted→posted` |
| `GET /api/m1/wh/locations/by-barcode/<code>` | `inventory_view` | مخزن الموقع | قراءة |
| `GET /api/m1/wh/approvals` | `stock_adjust_approve` | from **أو** to في النطاق | يستبعد عمل المستدعي |
| `GET /api/m1/wh/labels?kind=item\|location&ref=` | `inventory_view` | الموقع فقط (الصنف عام) | قراءة |
| `GET /api/m1/wh/counts/tasks` | `stock_count_submit` | مخزن الخطة | `countableBy` |
| `POST /api/m1/wh/counts/<ref>/entries` | `stock_count_submit` | مخزن الخطة | مفتاح |
| `POST /api/m1/wh/counts/<ref>/submit` | `stock_count_submit` | مخزن الخطة | مفتاح + المنشئ فقط |
| `GET /api/m1/wh/counts/<ref>/review` | `stock_adjust_approve` | مخزن الخطة | قراءة (كميات المدير) |
| `POST /api/m1/wh/counts/<ref>/approve` | `stock_adjust_approve` | مخزن الخطة | مفتاح + four-eyes + `already_finalized` |
| `POST /api/m1/wh/transfers` | `inventory_transfer` | **المصدر** في النطاق؛ الوجهة أي مخزن نشط | مفتاح + إعداد `wh_staged_transfers_enabled` |
| `GET /api/m1/wh/transfers?state=` | `inventory_transfer` | from أو to | إعداد |
| `POST /api/m1/wh/transfers/<gid>/approve`، `/reject` | `stock_adjust_approve` | المصدر | مفتاح + approver ≠ creator |
| `POST /api/m1/wh/transfers/<gid>/dispatch` | `inventory_transfer` | المصدر | مفتاح + منع السالب + تغطية دفعة صالحة |
| `POST /api/m1/wh/transfers/<gid>/receive` | `inventory_transfer` | الوجهة | مفتاح + رفض الزيادة |
| `POST /api/m1/wh/transfers/<gid>/resolve` | `stock_adjust_approve` | المصدر | مفتاح + approver ∉ {creator, dispatcher, receiver} |
| `POST /api/m1/wh/vouchers` | `inventory_edit` | المخزن | مفتاح + سبب إلزامي |
| `GET /api/m1/wh/vouchers?state=` | `inventory_edit` | النطاق | قراءة |
| `POST /api/m1/wh/vouchers/<gid>/approve`، `/reject` | `stock_adjust_approve` | المخزن | مفتاح + approver ≠ creator |

### 2.4 أنواع المستندات وآلات الحالات (VERIFIED-BY-READING، [wh_doc_store.dart:17-35](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L17-L35>))
| النوع (`kind`) | الانتقالات |
|---|---|
| `po_receipt` | `draft →submit→ submitted →convert→ posted`. الانتقال `draft →cancel→ cancelled` معرَّف، **لكن لا مسار ينفّذه** |
| `transfer` | `requested →approve→ approved`، أو `requested →reject→ rejected`. ثم `approved →dispatch→ in_transit`، ثم `→receive→ received` أو `→receive_short→ received_short`، ثم `received_short →resolve→ closed`. **لا إلغاء** بعد `approved` |
| `voucher` (`data.type ∈ in\|out\|damage`) | `pending →approve→ posted`، أو `pending →reject→ rejected` |
| `count_submission` | `draft →submit→ submitted →post→ posted` |

كل انتقال يمرّ بـ`UPDATE … WHERE id=? AND row_version=?`، فإن لم يتأثر صف واحد بالضبط يعود `409 stale` (:249-253). `expectedVersion` اختياري، والتطبيق لا يرسله (WH-019).

### 2.5 حسب المرحلة: موجود / جزئي / مفقود مقابل الخطة

#### W2 — البحث + الاستلام مقابل PO
| بند الخطة | الحالة | الدليل |
|---|---|---|
| ترحيل vN + مزامنة + `database_startup` | **مستبدَل** بجداول كسولة بلا مزامنة | §2.1 |
| `GET/POST` للـPO والاستلامات | **موجود** | الجدول §2.3 |
| `received_quantity` تراكمي «بقفل الصف»، ورفض الزيادة (سماحية `wh_receipt_overage_pct`) | **جزئي**: الرفض موجود؛ **لا قفل** صف (قراءة ثم كتابة مطلقة) | [wh_receipt_handlers.dart:167-189](<../../../lib/services/api/m1_wh/wh_receipt_handlers.dart#L167-L189>)، WH-006 |
| الزيادة تُسجَّل `over` بانتظار المدير | **مفقود** (تُرفض كليًّا، معلن) | :176-183 |
| دفعة/انتهاء لصنف `trackExpiry` | **موجود** (`batch_required`) | :132-136 |
| `convertPOReceiptToInvoice` بكميات `ok` ودفعات وuserId حقيقي ثم put-away | **موجود في الخادم**، **غير قابل للوصول** من أي واجهة | [wh_receipt_posting.dart](<../../../lib/services/api/m1_wh/wh_receipt_posting.dart>)، WH-002 |
| الحفاظ على خصم وضريبة الأمر في الفاتورة | **مفقود** | :41-52، WH-003 |
| شاشة سطح مكتب «طلبات المخازن» | **مفقود** (معلن) | grep: لا ذكر لـ`m1/wh` في `lib/presentation` |
| منع التحويل المزدوج | **جزئي**: داخل مسار الهاتف نعم؛ **مقابل مسار سطح المكتب لا** | WH-001 |
| `partially_received` | **مفقود** (معلن) | — |
| الشاشات: `PoListPage` و`PoReceivePage` و`LookupPage` و`OutboxPage` | **موجود** (مسوّدة الاستلام في الذاكرة فقط حتى الإرسال) | `mobile_warehouse/lib/screens/receive_pages.dart` |

#### W3 — التحويل المرحلي والسندات
| بند الخطة | الحالة | الدليل |
|---|---|---|
| إعداد `wh_staged_transfers_enabled` مطفأ افتراضيًا ويحرس كل المسارات | **موجود** | [wh_transfer_service.dart:34-38](<../../../lib/services/api/m1_wh/wh_transfer_service.dart#L34-L38>)؛ `_act`/`_create`/`_list` في [wh_stock_doc_handlers.dart](<../../../lib/services/api/m1_wh/wh_stock_doc_handlers.dart#L55>) |
| dispatch: منع السالب صراحة + دفعات + تكلفة مجمَّدة + Dr GIT/Cr inventory | **موجود** (بلا قفل صف على PG، WH-006) | :158-205 |
| receive: إدخال بالتكلفة المجمّدة + استعادة الدفعات + Dr inv/Cr GIT؛ التالف ⇒ سند damage معلّق؛ النقص يبقى؛ الزيادة مرفوضة | **موجود في الخادم**؛ **الواجهة لا ترسل التالف أبدًا** | :208-275؛ `transfer_pages.dart:69`، WH-012 |
| resolve `return_to_source\|write_off_loss` مع four-eyes ثلاثي | **موجود** | :278-311 |
| `accept_damaged_then_damage_voucher` | **مدمج** في receive | :260-270 |
| اقتراح FEFO بالموقع، و dispatch بالمسح، وoverride الدفعة | **مفقود** (معلن) | — |
| السندات `in/out/damage` بسبب إلزامي، واعتماد ≠ منشئ، وترحيل عبر `adjustStock` | **موجود** | [wh_voucher_service.dart](<../../../lib/services/api/m1_wh/wh_voucher_service.dart>) |
| تبويبات inbox على سطح المكتب | **مفقود** | — |
| `staged_transfer_vs_legacy_test` | **مفقود** | — |
| مسار LAN المعيب E-9أ | **مسوَّر لجهاز المخازن فقط**؛ ما زال معيبًا ومتاحًا لأجهزة pos/admin/mirror | WH-028 |

#### W4 — الجرد الأعمى
| بند الخطة | الحالة | الدليل |
|---|---|---|
| `countTasksForCounter` بلا expected | **موجود** | [wh_count_service.dart:78-100](<../../../lib/services/api/m1_wh/wh_count_service.dart#L78-L100>) |
| entries/submit بالتجميع لكل صنف، والأصناف غير المتوقعة بمتوقع = الرصيد الحالي، ثم `submitCount` | **موجود** (الموقع والدفعة يُخزَّنان ولا يُستعملان في التجميع) | :102-171 |
| عتبة E-4: أي فرق ⇒ مرور ثانٍ بعدّاد آخر | **موجود**؛ **ينسدّ** مع `assignedTo` | :28-38، WH-007 |
| مراجعة المدير (expected/counted/variance/حركات منذ العد) | **موجود** | :174-211 |
| `approveCount` بفصل الأدوار ثم `finalizeCycleCountTask` مرة واحدة | **موجود** على الهاتف؛ **قابل للتجاوز** من شاشة سطح المكتب | :213-222، WH-008 |
| منع المهام المتداخلة (§B.2-5) | **مفقود** | WH-014 |
| «إعادة عدّ» يطلبها المدير | **مفقود** | WH-014 |
| حجب الكميات في `/items` و`stock_changed` | **موجود**، لكنه مبني على الدور لا على الإسناد | [wh_blind.dart:26-35](<../../../lib/services/api/m1_wh/wh_blind.dart#L26-L35>)، WH-009 |
| إنشاء مهمة من الهاتف | **مفقود** (معلن؛ اختياري في W5) | — |

#### W5 — الاعتمادات والطباعة والـoutbox
| بند الخطة | الحالة | الدليل |
|---|---|---|
| صندوق الاعتمادات بفلترة four-eyes | **موجود** (عمر الجرد ثابت 0) | [wh_approval_handlers.dart:32-59](<../../../lib/services/api/m1_wh/wh_approval_handlers.dart#L32-L59>) |
| `GET /labels` بلا تكلفة | **موجود** | :61-81 |
| `label_builder` وCode128/QR و`PrintService` و58/80mm | **موجود** | `mobile_warehouse/lib/printing/*` |
| حالة «لا توجد طابعة» بلا نجاح مزيّف | **موجود** | [label_printer.dart:28-62](<../../../mobile_warehouse/lib/printing/label_printer.dart#L28-L62>) |
| أذونات Bluetooth في الـmanifest | **موجود** | §3.11 |
| طلب الإذن وقت التشغيل | **مفقود** (معلن) | WH-015 |
| outbox مشفّر + replay + قواعد تعارض | **موجود**؛ لكن بلا ربط بالمستخدم (WH-004)، ومع حجب دائم عند 5xx (WH-005)، وبلا حارس ضغط مزدوج (WH-011) | [wh_outbox.dart](<../../../mobile_warehouse/lib/sync/wh_outbox.dart>) |
| `ScanIntentPlugin` و`scanner_profiles` وقائمة العتاد اليدوية | **مفقود** (معلن) | — |
| إرسال P5 من التطبيق | **مفقود** (معلن)؛ والمسار الخادمي **غير قابل للوصول** من الهاتف | WH-010 |
| مبدّل مخزن، وSemantics، وتنقّل لوحة المفاتيح | **غير متحقَّق** | NOT_RUN |

### 2.6 الشاشات (من قارئ فرعي، مع تحقّق نقطي)
- الـshell بخمسة تبويبات: الرئيسية، البحث، المستندات، الـOutbox، الإعدادات.
- محور المستندات يُظهر البلاطات حسب `ops.can(code)` من `GET /session`، أي إظهار فقط، والخادم هو الحدّ:
  - استلام PO: `goods_receipt_mobile`.
  - جرد: `stock_count_submit`.
  - تحويلات: `inventory_transfer` أو `stock_adjust_approve`.
  - سند: `inventory_edit`.
  - اعتمادات: `stock_adjust_approve`.
  - ملصقات: `inventory_view`.
- **تمرّ عبر الـoutbox:** الاستلام، والجرد، وطلب التحويل وdispatch وreceive، والسند.
- **مباشرة أونلاين:** اعتماد التحويل ورفضه وحلّه، وكل قرارات صندوق الاعتمادات.
- لا توجد شاشة تستدعي `receipts/<gid>/convert` (grep على `mobile_warehouse/lib` و`packages/picpos_api_client/lib/src`: صفر).

### 2.7 الاختبارات الموجودة وما تثبته (قراءة فقط؛ لم يُشغَّل شيء)
| الملف | يمرّ بـ | يثبت (إن نجح) | لا يثبت |
|---|---|---|---|
| `test/integration/wh_po_receipt_flow_test.dart` | ApiHandler + middleware حقيقيان، SQLite في الذاكرة | النطاق، والصلاحية، والمفتاح (إعادة وتعارض وغياب)، ورفض الزيادة، وأن submit لا يحرّك مخزونًا، وأن convert مرة واحدة ولا يُدخل التالف | مبالغ الفاتورة، والقيود، والضريبة والخصم (أوامر الاختبار بلا خصم وضريبة: `wh_api_harness.dart:135`)، ومسار سطح المكتب بعد التحويل الجزئي |
| `test/integration/staged_transfer_conservation_test.dart` | حقيقي | حفظ الكمية، وتصفير رصيد GIT بالتكلفة المجمّدة، والإعادة، وfour-eyes، والسالب مرفوض رغم `enable_negative_sales`، والنقص والشطب والتالف والزيادة، والدفعة المنتهية، وفرعان | توازن القيد الكلي، والمقارنة مع `transferStock` القديم |
| `test/integration/wh_voucher_flow_test.dart` | حقيقي | السبب، والمعتمد ≠ المنشئ، ومنع السالب، وبصمة P5 (مسكوكة مباشرة بـ`mint`)، والدفعة الواردة | القيد (يفحص `movement_type` فقط)، وربط البصمة بمستند |
| `test/integration/wh_blind_count_leak_test.dart` | حقيقي، بتسلسل الاستجابة | غياب `expected\|variance\|system\|"available"` والأرقام 137/29 من استجابات العدّاد | عدّاد يحمل `stock_adjust_approve`؛ والـregex ضيّق |
| `test/integration/wh_count_finalize_test.dart` | حقيقي | فرض المرور الثاني، وحركة واحدة، و`already_finalized` | القيد، وحالة `assignedTo`. فيه تأكيد شبه تحصيل حاصل: `anyOf(200, 403)` و`anyOf(200, 409)` في السطرين :81-82 |
| `test/integration/wh_approvals_labels_test.dart` | حقيقي | فلترة الصندوق، والملصقات بلا تكلفة، و`device_scope` لخمسة مسارات قديمة | `/api/parties` و`/api/sync/pull` عبر الموجّه (اختبار وحدة للسياسة فقط) |
| `test/e2e/warehouse_docs_lan_e2e_test.dart` | `WarehouseLanClient` حقيقي على socket | الاستلام بعد سقوط المضيف، وتحويل بهاتفين، وجرد، و`device_scope` | GL |
| `test/integration_pg/wh_mobile_docs_pg_test.dart` | PostgreSQL (`@Tags(['pg'])`) | DDL، والتفرّد، و`row_version`، وسجل الأوامر، والفلاتر | **أي خدمة** (استلام، تحويل، سند، جرد) على PG، والتزامن |
| `mobile_warehouse/test/docs_flow_test.dart` | واجهات ضد `FakeOffice` | التنقّل والنصوص | قواعد الخادم (الـfake يطبّق كل أمر بلا قواعد)؛ **أغلبها تأكيدات نصية** |
| `mobile_warehouse/test/outbox_drain_test.dart` | outbox حقيقي + fake | الترتيب، وبقاء المعلّق، والإعادة بعد «انهيار» محاكى، والرفض النهائي، و401 | 5xx المتكرر (poison)، وتبديل المستخدم، و422 و429 |
| `mobile_warehouse/test/e2e/warehouse_app_e2e_test.dart` | شاشات حقيقية + fake | W2–W5 مسارات سعيدة | اختبار عتاد `skip` بجسم فارغ؛ و`contains('137')` لا يمكن أن يفشل (:107) |
| `packages/picpos_api_client/test/wh_doc_client_test.dart` | FakeTransport | الترويسات والتحليل | — |
| `test/device_lab/serve_host_test.dart` | `skip` ما لم `LAB_HOST=1` | أن المضيف يقلع بـhttps وبصمة | ليس اختبار انحدار |
| `mobile_warehouse/test/docs_golden_test.dart` + `golden_test.dart` | pixel goldens | — | **64 صورة فشل مرتكَبة** تحت `mobile_warehouse/test/failures/` (WH-024) |

---

## 3. مصفوفة الفحوص المستعرضة

| # | المحور | النتيجة | الوسم | المرجع |
|---|---|---|---|---|
| 3.1 | المخزون لا يصير سالبًا من مستندات المخازن | dispatch وسند `out/damage` يفحصان `requireCoveredStock` قبل `adjustStock` بصرف النظر عن `enable_negative_sales`. الوارد (receive، return_to_source، convert، in) لا يُنقص. الجرد يكتب المعدود ≥ 0. **لكن** الفحص يقرأ `inventory_balances` بلا `FOR UPDATE`، والقفل يأتي داخل `adjustStock` بعده؛ على PG مع إعداد السالب مفعّلًا يمكن لطلبين متزامنين تجاوزه | SQLite: VERIFIED-BY-READING؛ PG race: INFERRED | [wh_stock_guard.dart:12-37](<../../../lib/services/api/m1_wh/wh_stock_guard.dart#L12-L37>)، [inventory_dao.dart:170-176,210-214](<../../../lib/data/database/daos/inventory_dao.dart#L170-L214>)، WH-006 |
| 3.2 | حمل الدفعات | dispatch يستهلك الدفعات صراحة (`consumeBatchesForIssue`)، و`adjustStock(type:'transfer_out')` لا يستهلكها لأن النوع خارج `outboundTypes`، فلا استهلاك مزدوج. receive يستعيد الدفعات المأخوذة، والنقص يحمل `shortLots`. انحراف الدفعات مع `cycle_count`/`adjustment` لغير `trackExpiry` سلوك قائم | VERIFIED-BY-READING (+ INFERRED للانحراف) | [inventory_dao.dart:289-331](<../../../lib/data/database/daos/inventory_dao.dart#L289-L331>)، WH-020 |
| 3.3 | منع الاستلام والترحيل المزدوج | داخل مسار الهاتف: `command_id UNIQUE`، وآلة الحالة، و`row_version`، و`line_global_id UNIQUE`. **عبر المسارات:** سطح المكتب يحوّل الأمر كاملًا بعد تحويل جزئي من الهاتف | VERIFIED-BY-READING | WH-001، WH-011 |
| 3.4 | four-eyes | `requireDistinct` على الخادم بلا استثناء لمدير النظام: التحويل والسند ضد المنشئ، والـresolve ضد المنشئ والمرسل والمستلم، والجرد ضد كل العدّادين و`assignedTo`. **تجاوز** من شاشة جرد سطح المكتب | VERIFIED-BY-READING | [wh_http.dart:131-133](<../../../lib/services/api/m1_wh/wh_http.dart#L131-L133>)، WH-008 |
| 3.5 | إعادة استعمال بنية P5 | `requirePermission → ApprovalGate.authorise` يتحقق من التوقيع والطالب والجهاز والصلاحية وانتهاء الصلاحية واستعمال واحد لكل عملية. `approverOf` يعيد قراءة البصمة الموقَّعة. **لكن** `/api/approvals/grant` محجوب عن جهاز المخازن، والبصمة مقيّدة بجهاز مُصدِرها، و`scope` لا يُفحص | VERIFIED-BY-READING | WH-010 |
| 3.6 | الجرد الأعمى | DTO العدّاد: `{ref, warehouseId, warehouse, date, draftGlobalId?, items:[productId,code,name,barcode]}`. جواب submit `{globalId,state}`. `/items` يعيد `blind:true`. `stock_changed` بلا `available` للعدّاد. خطأ 500 بلا نص. نموذج العميل `CountReviewLine.expected` يُستعمل في المراجعة فقط. لا cache أرصدة محليًا. **ثغرة:** العدّاد الذي يحمل `stock_adjust_approve` ليس أعمى | VERIFIED-BY-READING | WH-009 |
| 3.7 | النطاق في **كل** مسار wh | §2.3: كل مسار يفحص `ctx.scope` على المخزن المعني. لا مسار بلا فحص (المنتجات عامة بطبيعتها في `items` و`labels?kind=item`) | VERIFIED-BY-READING | — |
| 3.8 | سياسة مسارات جهاز المخازن | `LanDeviceRoutePolicy.warehousePaths = ['/api/m1/info','/api/auth/session','/api/m1/wh']`، تُفحص في الـmiddleware بعد التحقق من التوكن. `/ws` مرفوض لجهاز المخازن. البادئات المعفاة (`/api/health` …) تمرّ قبل الفحص لأي أحد، وهذا سلوك قائم | VERIFIED-BY-READING | [lan_device_route_policy.dart:21-56](<../../../lib/services/api/lan_device_route_policy.dart#L21-L56>)، [api_auth_middleware.dart:315-322](<../../../lib/services/api/api_auth_middleware.dart#L315-L322>) |
| 3.9 | الأكواد ونقاط الإنفاذ والمنح | الأكواد الثلاثة الجديدة معرّفة في [warehouse_permission_codes.dart](<../../../lib/core/permissions/warehouse_permission_codes.dart>)، وكلها مُنفَّذة في مسارات wh. المنح يطابق §B.4 **إلا** أن «مدير مخزون» بلا `inventory_edit`، فلا ينشئ سندات ولا يسردها | VERIFIED-BY-READING | WH-013 |
| 3.10 | الأثر المحاسبي | الاستلام لا قيد له قبل convert (R-A محترم). التحويل: قيود GIT فقط عند تفعيل الإعداد، وفشل مغلق `accounts_not_mapped`. السند: قيد تلقائي عبر `adjustmentAccountedTypes`. الجرد: `finalizeCycleCountTask` القائم. **مشاكل:** الخصم والضريبة (WH-003) والمسار المزدوج (WH-001) | VERIFIED-BY-READING (المبالغ: INFERRED) | — |
| 3.11 | Bluetooth في الـmanifest | `BLUETOOTH`/`BLUETOOTH_ADMIN` حتى SDK 30، و`BLUETOOTH_CONNECT`، و`BLUETOOTH_SCAN neverForLocation` (`tools:targetApi="s"`)، و`uses-feature bluetooth required=false`. لا طلب runtime. نتيجة دمج manifest الإضافة غير معروفة | VERIFIED-BY-READING (الدمج: NOT_RUN) | WH-015 |
| 3.12 | أمن الـoutbox | مشفّر بـSQLCipher بمفتاح في `DatabaseKey`/Keystore (`wh_local_store.dart:18-21`)، والتشفير الفعلي على الجهاز NOT_RUN. الإعادة بنفس المعرّف. الترتيب صارم. 4xx نهائي، و5xx/429/شبكة معلّق. **لا ربط بالمستخدم، ولا حد محاولات، ولا dead-letter، ولا حارس ضغط مزدوج.** الساعة: المعرّف يحوي وقت الجهاز للتفرّد فقط، والخادم لا يثق بوقت الجهاز | VERIFIED-BY-READING | WH-004، WH-005، WH-011 |
| 3.13 | صدق الطباعة | `NoPrinter` افتراضي في الاختبارات. `ServiceLabelPrinter` يعيد `noPrinter` أو `queued` أو `printed` حسب `PrintService`. لا نجاح مزيّف | VERIFIED-BY-READING | — |
| 3.14 | i18n/RTL والنصوص الثابتة | لا رموز عملات في التطبيق. نصوص عربية ثابتة في أوصاف القيود والملاحظات على الخادم. نصوص مختلطة الاتجاه بلا عزل | VERIFIED-BY-READING (قارئ + تحقّق نقطي) | WH-022 |
| 3.15 | ratchet/أحجام | كل ملفات `lib/` الجديدة < 15KB. `role_grant_matrix.dart` = 26,863B. لا مساس بـ`permission_codes.dart` ولا `database.dart` ولا `inventory_dao.dart` ولا `purchase_dao.dart`. `api_handler.dart` = 8,447B فوق عتبة CI البالغة 8,200، **لكنه كان 8,456 قبل هذا الـcommit** (سابق وغير متعلق) | VERIFIED-BY-READING (قياس LF) | WH-029 |
| 3.16 | تكافؤ PG | DDL مفرّع. `?` في `customStatement` مستعمل أصلًا مع PG في الكود القائم. `is_active = 1` على عمود INTEGER صحيح. **لا اختبار PG للخدمات ولا للتزامن** | VERIFIED-BY-READING / NOT_RUN | WH-006، WH-016 |
| 3.17 | الكود الميت وما يُعرض كميزة وهو غير منتهٍ | `cancel` لاستلام بلا مسار. `convert` بلا واجهة. مسار P5 غير قابل للوصول. التالف في الاستلام غير قابل للإدخال. تعليق W0 قديم في `wh_local_store.dart:6-8`. «غير متاح بعد» تظهر لصلاحية ناقصة | VERIFIED-BY-READING | WH-002، WH-010، WH-012، WH-023 |

---

## 4. ما يجب على القائد التحقق منه بالتشغيل (NOT_RUN هنا)

> تُشغَّل **بعد** انتهاء مختبر Android، لا بالتوازي (أقفال Flutter).

```powershell
# 1) حراس الجذر والاختبارات الجديدة
flutter test test/integration/wh_po_receipt_flow_test.dart test/integration/staged_transfer_conservation_test.dart test/integration/wh_voucher_flow_test.dart test/integration/wh_blind_count_leak_test.dart test/integration/wh_count_finalize_test.dart test/integration/wh_approvals_labels_test.dart
flutter test test/e2e/warehouse_docs_lan_e2e_test.dart
flutter test test/unit/warehouse_role_grants_test.dart test/unit/api_routes_golden_test.dart test/unit/permission_enforcement_coverage_test.dart
flutter test test/structural   # يشمل file_size_ratchet و sync_coverage_guard و unsynced_tables_have_no_writer إن وُجد
# 2) PostgreSQL (يحتاج خادم PG كما في test/integration_pg/_support)
flutter test --tags pg test/integration_pg/wh_mobile_docs_pg_test.dart
# 3) التطبيق والحزم
cd mobile_warehouse; flutter analyze; flutter test; cd ..
cd packages/picpos_api_client; dart test; cd ../..
cd packages/picpos_device; flutter test; cd ../..
# 4) بوابة الأحجام في CI (تفشل سلفًا على api_handler.dart بحسب القياس — WH-029)
# 5) الـmanifest المدموج
cd mobile_warehouse; flutter build apk --debug; & "$env:ANDROID_HOME\build-tools\<ver>\aapt2" dump permissions build\app\outputs\flutter-apk\app-debug.apk
```

**اختبارات إعادة إنتاج مقترحة** (لم تُكتب لأن هذه المراجعة لا تعدّل `test/`):
- WH-001: استلام جزئي من الهاتف، ثم `convert`، ثم `db.convertPOToInvoice(poId)`. المتوقع رفض، والفعلي المتوقع فاتورة ثانية كاملة.
- WH-003: أمر بخصم وضريبة، ثم `convert`. يُقارَن `purchase_invoices.total`/`tax` بقيمة الأمر.
- WH-004: outbox فيه عنصر للمستخدم A، ثم `signOut`، ثم دخول B، ثم `drain`. يُفحص `created_by` على الخادم.
- WH-005: فترة مقفلة، ثم سند `out` من الهاتف يعتمده المشرف. يُفحص الرمز (المتوقع `period_closed` 409، والفعلي `500 internal`)، ثم سلوك الطابور.
- WH-007: مهمة `assignedTo=X` بفرق، ثم تعذّر المرور الثاني والاعتماد.
- WH-006: على PG، طلبا dispatch متزامنان (`Future.wait`) مع `enable_negative_sales=true`.

**ما لا يمكن التحقق منه بالقراءة:**
- التشفير الفعلي لملف `picpos_warehouse_enc.db` على الجهاز.
- سلوك أذونات Bluetooth على Android 12+.
- دمج الـmanifest.
- مطابقة الـgoldens.
- سلوك PG تحت التزامن.
- حالة CI الفعلية.
- أداء الماسحات.
- أي مسار W2–W5 على جهاز فعلي: المختبر شغّل مضيفًا من `909f2d38` بحسب `DEVICE-LAB-RESULTS.md:8-10` (قارئ فرعي).

---

## 5. الملفات المنشأة في هذه المراجعة
- `docs/audits/2026-10-25-warehouse-w2-w5-review/REVIEW.md` (هذا الملف).
- `docs/audits/2026-10-25-warehouse-w2-w5-review/FINDINGS.md`.

لا شيء غيرهما. لم تُمسّ التغييرات المحلية غير الملتزمة المذكورة في §0.

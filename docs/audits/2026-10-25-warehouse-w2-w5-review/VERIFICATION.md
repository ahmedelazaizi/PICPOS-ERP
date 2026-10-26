# VERIFICATION — التحقق من إصلاحات WH-001 … WH-030

> **النسخة المفحوصة:** `feat/tables-reservations-permissions` @ `b44098a7`. الإصلاحات في `b2f974df`، مقارنةً بـ`1ff2b6c1` (`git diff 1ff2b6c1 b2f974df`). أما `b44098a7` فيغيّر سكربتات المختبر ووثائقه فقط (4 ملفات، لا كود منتج).
> **البيئة:** Windows. قراءة ملفات و`git` فقط. **لم يُشغَّل أي اختبار، ولا `flutter`، ولا `dart`**؛ كل حكم «would fail before the fix» استدلال من قراءة الكود القديم كما وصفته [FINDINGS.md](<FINDINGS.md>) ومن الـdiff، وليس نتيجة تشغيل.
> **الأدلة:** **[V]** = VERIFIED-BY-READING (قرأتُ السطر بنفسي أو عبر قارئ فرعي وتحقّقتُ نقطيًا). **[I]** = INFERRED (استنتاج يحتاج تشغيلًا أو قراءة إضافية).
> **المساعدون:** ثلاثة قرّاء read-only. الأول للجرد والتزامن (WH-006…009 وWH-014)، والثاني لمستندات الخادم (WH-010…013 وWH-018…028 وWH-030)، والثالث لواجهة الهاتف والاختبارات والحجم (WH-015…017 وWH-022…024 وWH-029). راجعتُ تقاريرهم وتحقّقتُ نقطيًا من: `wh_blind.dart:38`، و`wh_concurrency_pg_test.dart`، و`api_data_inventory.dart:266-341`، و`git ls-files`، وأحجام LF.
> **ملفات أضافتها هذه المراجعة:** هذا الملف وحده.
>
> **الحالات:** FIXED-PROVEN = السبب الجذري أُزيل وله اختبار سلوكي يفشل على الكود القديم (استدلالًا). FIXED-UNTESTED = الإصلاح صحيح بالقراءة بلا اختبار قادر على الفشل. PARTIAL = بقي جزء. NOT-FIXED. DEFERRED = مؤجَّل أو قرار مالك، مع سببه.

## 1. الملخص

| WH | الحالة | ملفات الاختبار |
|---|---|---|
| **001** | **PARTIAL** (مسار سطح المكتب المستقل/الخادم مُثبت؛ مسار العميل/المرآة مفتوح) | `test/integration/wh_receipt_conversion_integrity_test.dart` |
| **002** | **PARTIAL** (الخدمة والمسار مُثبتان؛ سطح مكتب العميل/المرآة يرى قائمة فارغة؛ لا اختبار للواجهة) | `test/integration/wh_receipts_inbox_test.dart` |
| **003** | **FIXED-PROVEN** (العملة N/A بالمخطط) | `test/integration/wh_receipt_conversion_integrity_test.dart` |
| **004** | **FIXED-PROVEN** (ربط في العميل فقط) | `mobile_warehouse/test/outbox_drain_test.dart`، `packages/picpos_device/test/device_test.dart` |
| **005** | **FIXED-PROVEN** + خطر جديد NEW-02 على PG | `test/integration/wh_error_classification_test.dart`، `mobile_warehouse/test/outbox_drain_test.dart` |
| 006 | FIXED-UNTESTED | `test/integration_pg/wh_concurrency_pg_test.dart` (ضعيف) |
| 007 | FIXED-PROVEN | `test/integration/wh_count_integrity_test.dart` |
| 008 | PARTIAL | `test/integration/wh_count_integrity_test.dart` |
| 009 | PARTIAL (مُثبت على SQLite؛ PG غير مُثبت) | `test/integration/wh_count_integrity_test.dart` |
| 010 | DEFERRED (قرار مالك) | — |
| 011 | FIXED-PROVEN (الخادم + صفحة السند)؛ صفحة طلب التحويل بلا اختبار | `test/integration/wh_error_classification_test.dart`، `mobile_warehouse/test/docs_flow_test.dart` |
| 012 | PARTIAL | `mobile_warehouse/test/docs_flow_test.dart` |
| 013 | FIXED-PROVEN | `test/unit/warehouse_role_grants_test.dart`، `test/integration/wh_voucher_flow_test.dart` |
| 014 | PARTIAL (الفلترة مُثبتة؛ التداخل وإعادة العدّ DEFERRED) | `test/integration/wh_count_integrity_test.dart` |
| 015 | DEFERRED (يحتاج جهاز Android 12+) | — |
| 016 | PARTIAL | — |
| 017 | NOT-FIXED (إجرائي) | — |
| 018 | FIXED-PROVEN على SQLite؛ خطر PG | `test/integration/wh_error_classification_test.dart` |
| 019 | DEFERRED | — |
| 020 | DEFERRED | — |
| 021 | DEFERRED (قرار مالك؛ يتقاطع مع WH-001) | — |
| 022 | PARTIAL | `mobile_warehouse/test/docs_flow_test.dart` |
| 023 | PARTIAL | `mobile_warehouse/test/shell_test.dart` |
| 024 | FIXED-PROVEN (بدليل `git`) | — (`git ls-files`) |
| 025 | FIXED-UNTESTED | — |
| 026 | FIXED-PROVEN (الخادم) | `test/integration/wh_misc_integrity_test.dart` |
| 027 | FIXED-PROVEN | `test/integration/wh_misc_integrity_test.dart` |
| 028 | PARTIAL | `test/integration/wh_lan_transfer_route_test.dart` |
| 029 | FIXED-UNTESTED (7,049 بايت LF < 8,200 مقيس؛ خطوة CI لم تُشغَّل) | `test/structural/file_size_ratchet_test.dart` |
| 030 | DEFERRED (قرار مالك) | — |

**ملاحظة على [FIXES.md](<FIXES.md>):** يصف WH-001 وWH-002 بأنهما «مُعالَج»، ويقول إن `dismiss` في WH-023 «لم تُنفَّذ». هذا التحقق يُبقي WH-001 وWH-002 على **PARTIAL** للأسباب في §2. أما WH-023 فمتّسق مع ما كتبه الـfixer.

---

## 2. WH-001 … WH-005 (سطرًا بسطر)

### WH-001: فوترة مزدوجة لأمر شراء مستلَم جزئيًا

**(a) العيب:** الهاتف يستلم 6 من 12 ويحوّلها فاتورةً، والأمر يبقى بلا `convertedToInvoiceId`. ثم يفوتر سطح المكتب (`convertPOToInvoice` أو «سحب أمر شراء») الكمية كاملة، فيتضاعف المخزون والذمة.

**(b) موضع الإصلاح [V]:**
- [purchase_orders_dao.dart:188-202](<../../../lib/data/database/daos/purchase_orders_dao.dart#L188-L202>): `_requireConsumablePurchaseOrder` يرفض أي أمر له سطر `received_quantity > 0`.
- [purchase_orders_dao.dart:206-209](<../../../lib/data/database/daos/purchase_orders_dao.dart#L206-L209>): `markPurchaseOrderConvertedByReceipts`.
- [wh_receipt_posting.dart:78-121](<../../../lib/services/api/m1_wh/wh_receipt_posting.dart#L78-L121>): الفاتورة وختم الأمر ونقل الـbins وانتقال المستند في `db.transaction` واحدة، ولم يعد `sourceOrderId` يُمرَّر.

**(c) هل أُزيل السبب الجذري؟ جرد كل المداخل التي تُنشئ فاتورة مشتريات من أمر شراء:**

| المدخل | يمرّ بالحارس؟ | الحكم |
|---|---|---|
| `convertPOToInvoice` (زر «استلام وتحويل لفاتورة» في [purchase_orders_screen.dart:369-381](<../../../lib/presentation/screens/purchase_orders_screen.dart#L369-L381>)) على خادم/مستقل | نعم: [purchase_orders_dao.dart:227](<../../../lib/data/database/daos/purchase_orders_dao.dart#L227>) داخل المعاملة [V] | مُغلق |
| «سحب أمر شراء» → `createPurchaseInvoice(sourceOrderId)` على خادم/مستقل | نعم: [purchase_dao.dart:102-104](<../../../lib/data/database/daos/purchase_dao.dart#L102-L104>) قبل أي حركة؛ [purchases_repository_impl.dart:208](<../../../lib/data/repositories/purchases_repository_impl.dart#L208>) [V] | مُغلق |
| «سحب أمر شراء» على **سطح مكتب عميل/مرآة** | **لا.** مسار العميل يرسل `submitPurchase` بلا `sourceOrderId` ([purchases_repository_impl.dart:99-123](<../../../lib/data/repositories/purchases_repository_impl.dart#L99-L123>))، ثم يكتب نسخة محلية بلا حارس (:151-167). والخادم `api_purchase_handler.dart:263-282` لا يستقبل `sourceOrderId` أصلًا (grep على `lib/services`: صفر) [V] | **مفتوح.** عيب سباكة قائم قبل W2، لكنه مدخل حيّ إلى WH-001: الأمر يُفوتر كاملًا على الخادم ولا يُستهلَك |
| `convertPOToInvoice` على سطح مكتب عميل | يمرّ بالحارس على **القاعدة المحلية** ([purchase_orders_repository_impl.dart:59-60](<../../../lib/data/repositories/purchase_orders_repository_impl.dart#L59-L60>)). `received_quantity` المحلي يأتي بالسحب ([purchase_order_sync_strategy.dart:82,140](<../../../lib/services/sync/strategies/purchase_order_sync_strategy.dart#L82>))، ومسارات `m1_wh` لا تُطلق `broadcast('purchase_orders')` بعد submit (grep: صفر) [V] | **[I] نسخة محلية قديمة ⇒ الحارس يمرّ.** يتوقف على إتاحة الشاشة في وضع العميل |
| سحب أمر ثم «فكّ الربط» ([picpos_invoice_form.dart:772-776](<../../../lib/presentation/invoice_form_picpos/picpos_invoice_form.dart#L772-L776>)): البنود تبقى بكمية الأمر و`sourceOrderId=null` | لا [V] | ثغرة يدوية. المستخدم يحفظ عمدًا فاتورة بكامل الكمية |
| مسار الاستلام من الهاتف `POST /api/m1/wh/receipts/<gid>/convert` | لا يحتاج الحارس. `po.convertedToInvoiceId != null ⇒ 409` ([wh_receipt_posting.dart:31](<../../../lib/services/api/m1_wh/wh_receipt_posting.dart#L31>)) وآلة الحالات `submitted→posted` مرة واحدة ([wh_doc_store.dart:21](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L21>)) [V] | سليم |
| مكتب المحاسب `WhReceiptsInbox.convert` و`POST /api/m1/wh/desk/receipts/<gid>/convert` | نفس `WhReceiptPosting` [V] | سليم |
| `POST /api/purchase-orders` و`PUT …/status` ([api_data_documents.dart:90-105](<../../../lib/services/api/data/api_data_documents.dart#L90-L105>)) | لا يُنشئان فواتير. لكن `status` يُكتب بأي قيمة، و`DELETE` يحذف أمرًا مستلَمًا ([api_data_documents.dart:107-117](<../../../lib/services/api/data/api_data_documents.dart#L107-L117>)، عبر القارئ) [V] | خارج WH-001 |

**الحالات الحدّية (مسار الخادم):**
- **استلامان جزئيان R1(6) وR2(6) بأي ترتيب:** `complete && !stillWaiting` يختم الأمر عند آخر تحويل فقط. `stillWaiting` يستبعد المستند الحالي ([wh_receipt_posting.dart:71-73](<../../../lib/services/api/m1_wh/wh_receipt_posting.dart#L71-L73>)) [V].
- **مسودة جوال (draft) ثم تحويل كامل من سطح المكتب:** المسودة لا تمسّ `received_quantity` (الزيادة عند submit فقط: [wh_receipt_handlers.dart:176-199](<../../../lib/services/api/m1_wh/wh_receipt_handlers.dart#L176-L199>)). لذلك يمرّ الحارس ويُختم الأمر، ثم يُرفض submit لاحقًا بـ`po_not_receivable` لأن `_requireOpen` في :174 يفحص `convertedToInvoiceId`. **لا ازدواج** [V].
- **إعادة الإرسال (replay):** `store.command` يجيب من `wh_mobile_doc_events` بنفس `X-Idempotency-Key` ([wh_doc_store.dart:285-291](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L285-L291>)) [V].
- **تحويلان متزامنان لنفس الاستلام:** الثاني يفشل في `UPDATE … WHERE row_version = ?` ⇒ `stale`، فتتراجع فاتورته مع المعاملة ([wh_doc_store.dart:256-260](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L256-L260>)) [V على SQLite؛ I على PG]. لكن على PG قد يصل قبله `23505` على `invoice_number` أو على `command_id`، ويُصنَّف `duplicate_document` نهائيًا (انظر NEW-02).
- **مسودة مهجورة:** `stillWaiting` يعتبر أي مسودة للأمر «انتظارًا»، فلا يُختم الأمر أبدًا ولو اكتمل استلامه. المخزون والذمة صحيحان والأمر يبقى `confirmed` مفتوحًا. أثر دفتري لا مالي [V].
- **الدفتر (bookkeeping):** الفواتير الجزئية لا ترتبط بالأمر إلا عبر `posted_ref_id` في `wh_mobile_docs` ونص `notes`. لم يُنشأ جدول الربط الذي اقترحته FINDINGS، و`convertedToInvoiceId` يحمل آخر فاتورة فقط. التتبّع أمر ← فواتير ناقص [V].
- **PG مقابل SQLite:** الحارس استعلام drift عادي ومحمول [V].
- **الأرقام (مستلَم جزئي ثم محاولة تحويل كامل):** الاختبار يؤكد: مخزون 6، وذمة 240، وفاتورة واحدة. القيد يُرحَّل داخل `createPurchaseInvoice` ولم يتغير [V]. مجموع `stock_movements(type=purchase)` لم يُفحص صراحةً، بل الرصيد وحده.

**(d) الاختبارات:** [wh_receipt_conversion_integrity_test.dart](<../../../test/integration/wh_receipt_conversion_integrity_test.dart>)

| الاختبار | يفشل على الكود القديم؟ |
|---|---|
| `the exact double-invoicing sequence: phone 6 of 12, then desktop convertPOToInvoice` (:43) | **نعم.** القديم: `convertedToInvoiceId=null` والحارس بلا فحص `received` ⇒ التحويل ينجح فيفشل `throwsException`، والمخزون 18 لا 6 |
| `"pull PO" into a purchase invoice (sourceOrderId) is refused the same way` (:57) | **نعم** (نفس السبب). لكنه يستدعي الـDAO مباشرة، لا مسار الشاشة ولا مسار العميل |
| `a submitted-but-not-converted receipt also blocks the legacy full conversion` (:76) | **نعم** |
| `the receipt route still finishes the order: 6 + 6 = 12 stock, PO stamped once` (:83) | لا. اختبار انحدار يحرس أن مسار الاستلام لم يُكسر بالحارس الجديد (لو بقي `sourceOrderId` لرُفض التحويل الثاني) |
| `an untouched PO still converts through the legacy path (no regression)` (:94) | لا، انحدار |

الضعف: `throwsException` عامّ ولا يتحقق من سبب الرفض. ولا اختبار لمسار العميل/المرآة، ولا لـ«فكّ الربط»، ولا لمسودة مهجورة، ولا لتحويل متزامن.

**(e) الحالة:** **PARTIAL.** السبب الجذري أُزيل على الخادم والتنصيب المستقل ومُثبت باختبار. يبقى مسار سطح مكتب العميل/المرآة بلا أي حارس.

**(f) المعالجة المطلوبة:**
1. تمرير `sourceOrderId` (أو `sourceOrderGlobalId`) في `ClientWriteInterceptor.submitPurchase` وفي `api_purchase_handler.dart` إلى `createPurchaseInvoice(sourceOrderId:)` على الخادم، حتى يعمل الحارس على **القاعدة المرجعية**.
2. تحويل `convertPOToInvoice` في وضع العميل إلى مسار خادم، أو منعه هناك.
3. اختبار تكامل: حمولة `POST /api/purchases` لعميل تحمل `sourceOrderId` لأمر له `received_quantity>0` ⇒ رفض، ومخزون الخادم لا يتغيّر. واختبار لأمر سليم ⇒ يُستهلَك (`convertedToInvoiceId` مضبوط).
4. (اختياري) جدول ربط أمر↔فواتير جزئية، وتجاهل المسودات الأقدم من مهلة في `stillWaiting`.

### WH-002: مكتب المحاسب لاستلامات الهاتف

**(a) العيب:** الاستلامات تتكدّس في `submitted`. لا شاشة ولا مسار لغير جهاز `warehouse`، والمحاسب يأخذ `403 device_scope`.

**(b) موضع الإصلاح [V]:**
- الخدمة: [wh_receipts_inbox.dart](<../../../lib/services/api/m1_wh/wh_receipts_inbox.dart>). تفرض `purchases_create` (:27-29) ونطاق مخازن المستخدم (:31-33)، وتحوّل عبر `WhReceiptPosting`.
- الحوار: [wh_receipts_inbox_dialog.dart](<../../../lib/presentation/purchases_picpos/screens/wh_receipts_inbox_dialog.dart>)، وفيه busy flag (:65).
- الزر: `purchases.whReceipts` في `purchases_picpos_screen.dart:187-197`، مشروط بـ`hasPermissionProvider(purchasesCreate)`.
- المزوّد: [wh_receipts_inbox_provider.dart](<../../../lib/data/providers/wh_receipts_inbox_provider.dart>).
- المسارات: [api_routes_m1_wh.dart:22-23](<../../../lib/services/api/routes/api_routes_m1_wh.dart#L22-L23>)، بحارس `runDesk` الذي يرفض `warehouse` و`mirror` ([wh_http.dart:124-141](<../../../lib/services/api/m1_wh/wh_http.dart#L124-L141>)).
- golden المسارات: `test/golden/api_routes.txt`.

**(c) السبب الجذري:**
- **الوصول (navigation):** `AppScreen.purchases` ⇒ `PurchasesPicposScreen` عند `Brand.isPicPos` فقط ([app_main_screen_catalog.dart:91-99](<../../../lib/app_main_screen_catalog.dart#L91-L99>)). العلامات الأخرى (`PurchaseInvoicesScreen`) بلا زر [V].
- **الصلاحية:** تُفرض في الخدمة (`_require`)، لا في الزر وحده [V].
- **سياسة المسار لجلسات سطح المكتب:** `LanDeviceRoutePolicy` يمرّر `/api/m1/wh/*` لجهاز `warehouse`، ثم يرفضه `runDesk`. المرآة مرفوضة بالسياسة وبـ`runDesk`. أجهزة `pos`/`admin` وجلسة بلا جهاز تمرّ ([lan_device_route_policy.dart:21-56](<../../../lib/services/api/lan_device_route_policy.dart#L21-L56>)) [V].
- **الفجوة الأولى [V]:** الحوار يقرأ **القاعدة المحلية** (`databaseProvider`). على سطح مكتب **عميل أو مرآة** لا توجد مستندات الهاتف محليًا (WH-021: غير مُزامَنة)، و`ensureWhMobileDocsSchema` يُنشئ جدولًا فارغًا، فيرى المحاسب «لا توجد استلامات» زورًا. ومسار `desk/receipts` عبر LAN لا يستدعيه أي عميل (grep في `lib/`: الحوار يستدعي الخدمة المحلية فقط).
- **الفجوة الثانية [V]:** `runDesk` لا يفحص فرع جهاز `pos`. النطاق هو نطاق المستخدم (`getWarehouseScopeForUser`). مستخدم غير مقيَّد يحوّل استلامات كل الفروع. مقبول إن طابق سياسة سطح المكتب [I].
- **الفجوة الثالثة [V]:** الخدمة المحلية لا تمرّر الاستثناءات عبر `classifyWhFailure`، فرسائل `period_closed`/`accounts_not_mapped` في الحوار (:46-47) لا تُطابَق إلا لو جاءت `WhError`. المستخدم يرى «تعذّر التحويل؛ لم يُسجَّل شيء» وهو صادق لكنه أقل دقة.
- **قائمة المكتب [V]:** `store.list` بحدّ 200 وترتيب `id DESC` قبل فلترة النطاق، فأقدم الاستلامات قد تختفي إن تجاوز العدد 200.

**(d) الاختبارات:** [wh_receipts_inbox_test.dart](<../../../test/integration/wh_receipts_inbox_test.dart>)

| الاختبار | يفشل قبل الإصلاح؟ |
|---|---|
| `the inbox lists the submitted receipt with order, supplier, warehouse and lines` (:33) | نعم: الصنف غير موجود (compile) |
| `a user without purchases_create is refused by the service itself` (:41) | نعم. يؤكد صفر فواتير |
| `convert posts the invoice with accepted quantity only, marks the receipt posted, once` (:47) | نعم. مخزون 4 (التالف خارج)، وتحويل ثانٍ مرفوض، وفاتورة واحدة |
| `a paired DESKTOP (pos) device converts; a warehouse phone is refused device_scope` (:68) | نعم: المسار كان 404. يغطي replay ⇒ `replayed: true` |

لا widget test للزر أو الحوار، ولا اختبار لوضع العميل.

**(e) الحالة:** **PARTIAL.** مُثبت على الحاسوب الرئيسي/المستقل على مستوى الخدمة والمسار. غير قابل للاستعمال على سطح مكتب عميل/مرآة، والواجهة بلا اختبار.

**(f) المعالجة:** في وضع العميل/المرآة يستدعي الحوار `GET/POST /api/m1/wh/desk/receipts…` عبر عميل المزامنة، مع `X-Idempotency-Key` ثابت لكل استلام، أو يُخفى الزر برسالة «افتح من الحاسوب الرئيسي». مع widget test: صلاحية ⇒ الزر ظاهر، وبدونها ⇒ مخفي، وتحويل ⇒ toast نجاح والقائمة تتحدث. وتمرير استثناءات الخدمة عبر `classifyWhFailure`.

### WH-003: الخصم والضريبة والعملة ومركز التكلفة في الفاتورة

**(a) العيب:** تحويل الاستلام كان يُسقط `discount` و`taxRate` و`taxAmount` للسطر، وخصم الرأس، و`costCenterId`.

**(b) موضع الإصلاح [V]:** [wh_receipt_posting.dart:43-69](<../../../lib/services/api/m1_wh/wh_receipt_posting.dart#L43-L69>) (نسبة الكمية `qty / i.quantity`)، و:89-91 (`discount` = خصم الرأس النسبي + مجموع خصوم السطور، و`costCenterId: po.costCenterId`).

**(c) مقارنة الإجماليات بأسطر الأمر:**
- محرك الشراء يحترم `taxAmount` الممرَّر ([purchase_dao.dart:132-135](<../../../lib/data/database/daos/purchase_dao.dart#L132-L135>))، و`total = Σ(gross+tax) − discount`. ويفسّر `discount` بأنه **إجمالي المستند** ولا يقلّ عن مجموع خصوم السطور (:165-191). لذلك يتسق جمع الرأس مع السطور [V].
- مثال الاختبار: سطر 10×40 بخصم 20 وضريبة 60، والمستلَم 5 ⇒ إجمالي 200 + 30 − 10 = 220 = ذمة المورد [V].
- **العملة:** `PurchaseOrders` لا يحمل `currencyId/exchangeRate` ([sales_purchase_tables.dart:506-534](<../../../lib/data/database/tables/sales_purchase_tables.dart#L506-L534>)) ⇒ N/A بالمخطط [V].
- **خصم الرأس:** لا كاتب في الإنتاج يضبط `purchase_orders.discount`. `createPurchaseOrder` ([purchase_orders_dao.dart:109-123](<../../../lib/data/database/daos/purchase_orders_dao.dart#L109-L123>)) و`postPurchaseOrder` ([api_data_documents.dart:39-52](<../../../lib/services/api/data/api_data_documents.dart#L39-L52>)) لا يضبطانه ⇒ فرع `headerDiscount` ميت اليوم وغير مختبَر. لو كُتب لاحقًا بمعنى «إجمالي يشمل خصوم السطور» لتضاعف الخصم [I].
- **خصم سطر الأمر:** شاشة الأوامر لا تكتبه (`purchase_orders_screen.dart:786-794` تكتب `taxRate/taxAmount` فقط) ⇒ الأثر العملي اليوم هو الضريبة [V].
- **التقريب:** نسب الاستلامات الجزئية تُقرَّب كلٌّ على حدة، فقد يختلف مجموعها عن الأمر بـ0.01 [I].
- **مرتبط وخارج النطاق [V]:** `convertPOToInvoice` القديم لا يمرّر `taxRate/taxAmount` ولا `costCenterId` ([purchase_orders_dao.dart:236-245](<../../../lib/data/database/daos/purchase_orders_dao.dart#L236-L245>)) ⇒ فاتورة المسار القديم بلا ضريبة مدخلات. انظر NEW-04.

**(d) الاختبارات:** `half of a discounted+taxed line -> half the discount and half the tax, journal balanced` (:103). **يفشل قبل الإصلاح:** القديم ⇒ `tax=0` و`discount=0` و`total=200` و`costCenterId=null`. يتحقق من توازن القيود (Σدائن = Σمدين على كل `journal_entry_lines`) وذمة المورد 220 وسطر الفاتورة.

**(e) الحالة:** **FIXED-PROVEN.**

**(f) تحسين اختياري:** اختبار لخصم رأس الأمر حين يُكتب، أو حذف الفرع الميت إلى أن يُعرَّف معنى `po.discount`.

### WH-004: ربط الـoutbox بالمستخدم والجهاز

**(a) العيب:** عناصر المستخدم A تُرسَل بجلسة B بعد تبديل الدخول على نفس الهاتف.

**(b) موضع الإصلاح [V]:**
- [wh_outbox.dart:112-127](<../../../mobile_warehouse/lib/sync/wh_outbox.dart#L112-L127>): كل عنصر يحمل `userId` و`userName` و`deviceId`، ويُرفض `enqueue` بلا جلسة معروفة.
- `_mine` (:129-130): `userId` و`deviceId` يطابقان الجلسة الحالية.
- `drain(where: _mine)` (:192): بعد إعادة التشغيل يُسأل الخادم أولًا من المستخدم (`refresh`)، ولا يُرسَل شيء ما دام `info == null`.
- [outbox.dart:65-71](<../../../packages/picpos_device/lib/src/sync/outbox.dart#L65-L71>): معامل `where`.
- العرض: «محفوظة للمستخدم X» وشارة في الشريط (`outbox_page.dart`، `wh_widgets.dart`).

**(c) السبب الجذري، بسيناريوهات:**
- **A يخرج ثم B يدخل:** `signOut` يمسح `info` ورمز الجلسة ([wh_session.dart:204-209](<../../../mobile_warehouse/lib/session/wh_session.dart#L204-L209>)) ولا يمسّ الطابور. عناصر A تبقى `pending` وتُحسب `foreign`، وعناصر B تخرج بجلسة B [V].
- **عودة A:** تخرج بجلسة A [V].
- **عنصر قديم بلا مالك:** لا يُرسَل أبدًا [V].
- **التخزين المشفّر:** الحقول الجديدة داخل `payload` في جدول `outbox` بـSQLCipher (`toRow` يكتب `jsonEncode(payload)`؛ [sqlcipher_store.dart:87-88](<../../../packages/picpos_device/lib/src/store/sqlcipher_store.dart#L87-L88>)) [V].
- **إلغاء الإقران (revoke):** `wipe` يسقط كل الطابور (للمستخدمين جميعًا)، ورسالة الإقران تذكر العدد (`handleRevoked`) [V].
- **حدود الإصلاح:**
  - الربط **في العميل فقط**. الخادم لا يقارن مالك العنصر بجلسة الطلب. الحماية تعتمد على سلامة التطبيق، وهذا مقبول بمعيار القبول في FINDINGS [V].
  - **نافذة TOCTOU:** `where(e)` يُقيَّم قبل `send(e)`، وبينهما `await outboxEntry(after)`. لو اكتمل تسجيل دخول B في تلك اللحظة لخرج عنصر A بجلسة B. احتمال ضئيل جدًا (يتطلب تسجيل دخول كاملًا خلال قراءة محلية) [I].
  - صفحة الـoutbox تحسب «لي/لغيري» بـ`userId` وحده (`outbox_page.dart` `_mine`)، والطابور بـ`userId+deviceId`: تباين عرض فقط [V].
  - عناصر مستخدم غادر أو أُوقف تبقى «مقفلة» إلى الأبد، بلا إجراء تحرير للمدير ولا إسقاط (زر الإسقاط للمرفوض فقط). لا تحجب غيرها [V].

**(d) الاختبارات:**
- [outbox_drain_test.dart](<../../../mobile_warehouse/test/outbox_drain_test.dart>) `A queues, signs out; B signs in: nothing goes out under B; A returns and it goes out as A` (:127). **يفشل قبل الإصلاح:** القديم يرسل بـ`session.client` الحالي، فيصل `office.posts` بمستخدم 9 فورًا. تعمل FakeOffice على `MemoryLocalStore` لا SQLCipher، والهوية مستخرجة من رمز `SESS-<id>`.
- `an entry without an owner (written by an older build) is never sent` (:159): يفشل قبله.
- [device_test.dart](<../../../packages/picpos_device/test/device_test.dart>) `where: entries the caller may not send now are skipped, kept pending, and sent later in order`: يفشل قبله (المعامل غير موجود).

**(e) الحالة:** **FIXED-PROVEN** على مستوى العميل.

**(f) تحسين اختياري:**
- فحص في الخادم: يحمل الطلب `x-op-owner`، ويُرفض إن خالف مستخدم الجلسة.
- إعادة تقييم `_mine` داخل `send` مباشرة قبل `client.command`.
- إجراء مدير لإسقاط عناصر مستخدم غير نشط.

### WH-005: تصنيف الأخطاء ومنع حجب الطابور

**(a) العيب:** أي استثناء غير مصنَّف ⇒ `500` ⇒ retryable ⇒ الطابور يقف عند العنصر إلى الأبد.

**(b) موضع الإصلاح [V]:**
- الخادم: [wh_error_classifier.dart](<../../../lib/services/api/m1_wh/wh_error_classifier.dart>)، مستعملًا في `WhHttp.run` و`runDesk` ([wh_http.dart:114-116,138-140](<../../../lib/services/api/m1_wh/wh_http.dart#L114-L116>)). التصنيف: `period_closed` 409، و`accounts_not_mapped` 409، وUNIQUE/`23505` ⇒ `duplicate_document` 409، وقفل/`40001`/`40P01` ⇒ `busy` 503، والباقي `internal` 500. نص الاستثناء لا يُعاد.
- العميل: [wh_outbox.dart:146-184](<../../../mobile_warehouse/lib/sync/wh_outbox.dart#L146-L184>). لكل 5xx: `serverFailures++` و`retryAt` بـ`Backoff.lan` (5 ث، 15، 45، 135، بحد أقصى 5 د)، وعند المحاولة الخامسة `dead_letter` (rejected) فيمضي التالي. والتابع لعنصر مرفوض (`after:`) ⇒ `dependency_rejected` دون إرسال.

**(c) السبب الجذري:**
- **العبارات المطابَقة موجودة فعلًا في الطبقات الدنيا [V]:**
  - `accounting_dao_reads.dart:127,133,155` (لا توجد سنة مالية/سنة مالية مغلقة/فترة محاسبية مغلقة).
  - `inventory_dao.dart:192` (فترة محاسبية مغلقة).
  - `inventory_dao.dart:385,396,413` («غير مربوط»).
- **الاستمرارية:** `serverFailures/retryAt` داخل `payload` وتُحفظ بـ`updateOutbox` (`toRow` يكتب الـpayload كاملًا)، فتنجو من إعادة التشغيل [V].
- **الحدّ:** محاولات 5xx محدودة (5). أخطاء الشبكة و429 بلا حد، وهو صحيح لأن الخادم لم يُجب [V].
- **الترتيب:** يقف الـdrain عند عنصر في backoff، فيُحفظ الترتيب [V].
- **ثغرات:**
  - **اعتماد على نص رسائل عربية.** أي إعادة صياغة في DAO تُرجع المسار إلى 500 بصمت. يخفّفه الحد الأقصى للمحاولات [V].
  - **`503 busy` يُحتسب ضمن المحاولات الخمس** (الشرط `status >= 500`)، رغم أن تعليق المصنِّف يقول «الهاتف يعيد المحاولة». خمس أقفال متتالية (≈3.3 دقيقة) تجعل عملية مشروعة `dead_letter` [V].
  - **`dead_letter` نهائي.** المخرج الوحيد «إسقاط»، ولا «أعد المحاولة»، فالعملية تضيع ما لم يُعِدها المستخدم يدويًا [V].
  - **حالة backoff تُعرض «لا اتصال»:** تُرمى `ApiError(unavailable,'backoff')` فيصير `sync.unreachable` [V].
  - **خطر جديد NEW-02 (PG):** UNIQUE ⇒ 409 نهائي قد يحدث لإعادة إرسال **ناجحة فعلًا**. التفصيل في §4 [I].

**(d) الاختبارات:**
- [wh_error_classification_test.dart](<../../../test/integration/wh_error_classification_test.dart>):
  - `a closed accounting period is 409 period_closed, nothing is posted, the voucher stays pending` (:42): **يفشل قبله** (كان 500). يتحقق من التراجع، والمخزون 10، والسند `pending`.
  - `an unmapped inventory account is 409 accounts_not_mapped (not 500)` (:57): **يفشل قبله.**
  - `re-creating a document under another command id but the same document id is 409 duplicate_document` (:67): **يفشل قبله.**
  - `classifier: transient lock is 503 busy, unknown is 500 internal…` (:100): وحدة، يفشل قبله (الصنف غير موجود).
- [outbox_drain_test.dart](<../../../mobile_warehouse/test/outbox_drain_test.dart>):
  - `repeated 500s back off, then park the entry as dead_letter so the next one flows` (:188): **يفشل قبله** (القديم يعيد 5xx بلا حد فيبقى `pending`).
  - `an operation that depends on a rejected one is not sent` (:210): يفشل قبله.
  - `a period closed at the office rejects the entry…` (:175): **ضعيف.** على FakeOffice التي تعيد 409 مباشرة، فالكود القديم كان سيرفضه ويمضي أيضًا. العيب كان في الخادم، والاختبار الحقيقي هو اختبار الخادم أعلاه.
- لا اختبار لـ503 في العميل، ولا لـPG.

**(e) الحالة:** **FIXED-PROVEN** للسبب الجذري (الحجب الأبدي + التصنيف). مع خطر NEW-02 وملاحظات `busy`/`dead_letter`.

**(f) المعالجة الموصى بها:**
- استثناء `503 busy` من عدّاد `dead_letter`، أو عدّاد مستقل أعلى.
- إجراء «إعادة المحاولة» لعناصر `dead_letter`.
- معالجة NEW-02 (§4).
- اختبار وحدة يقفل نص رسائل DAO المطابَقة (اختبار يرمي الاستثناء الحقيقي من `validateFinancialPeriod` يغطيه جزئيًا، وهو موجود).

---

## 3. WH-006 … WH-030

**WH-006: سباق الرصيد و`received_quantity` على PG.**
- (a) فحص بلا قفل، وكتابة مطلقة.
- (b) [wh_stock_guard.dart:15-21](<../../../lib/services/api/m1_wh/wh_stock_guard.dart#L15-L21>) (`FOR UPDATE` على PG فقط)، و:42-44، و:68-77 (`UPDATE … SET received_quantity = received_quantity + ? WHERE … + ? <= ?`)، واستعماله في [wh_receipt_handlers.dart:189](<../../../lib/services/api/m1_wh/wh_receipt_handlers.dart#L189>) [V].
- (c) صحيح بالقراءة. قراءة `averageCost` تسبق القفل في `wh_voucher_service.dart:81` و`wh_transfer_service.dart:167`؛ التكلفة وحدها قديمة، والكمية سليمة [V].
- (d) [wh_concurrency_pg_test.dart](<../../../test/integration_pg/wh_concurrency_pg_test.dart>):
  - اختبارا :41 و:50 يستدعيان الدالة الجديدة مباشرة، لا مسار submit.
  - اختبار :59 يشغّل `Future.wait` على **نفس** `AppDatabase` (منفّذ واحد)، وdrift يسلسل المعاملات على المنفّذ الواحد [I]، فالأرجح أنه ينجح حتى بلا قفل ⇒ **ضعيف**.
  - موسوم `pg` ومتخطّى افتراضيًا (`dart_test.yaml`).
- (e) **FIXED-UNTESTED.**
- (f) اختبار PG باتصالين (`AppDatabase` اثنين)، مع تداخل قسري (A يقفل وينتظر، وB يحاول). واختبار HTTP لـsubmit يتجاوز المسموح ⇒ `over_receipt`، و`received_quantity` لا يتغيّر.

**WH-007: انسداد المهمة المسندة.**
- (b) [wh_count_service.dart:39-40](<../../../lib/services/api/m1_wh/wh_count_service.dart#L39-L40>): الإسناد يحصر المرور الأول فقط [V].
- (d) `assigned to clerk, first pass differs -> clerk2 recounts -> approval posts the second count` (`wh_count_integrity_test.dart:50`) يفشل قبله. و`a stranger still cannot take the FIRST pass of an assigned task` (:66) انحدار.
- (e) **FIXED-PROVEN.**

**WH-008: إكمال سطح المكتب يتجاوز إعادة العدّ وfour-eyes.**
- (b) [cycle_count_repository_impl.dart:139-155](<../../../lib/data/repositories/cycle_count_repository_impl.dart#L139-L155>) و`wh_count_service.dart:239-255`. الشاشتان تمرّران `user?.id`، ولا مستدعٍ آخر في `lib/` [V].
- (c) جزئي:
  - `hasPhonePasses` يفحص `submitted` فقط ([wh_count_service.dart:232-234](<../../../lib/services/api/m1_wh/wh_count_service.dart#L232-L234>)). مهمة لها مرور جوال **مسودة** تُكمَل بالمسار القديم تحت العدّاد [V/I].
  - الفحص خارج معاملة الإكمال (سباق ضئيل) [I].
- (d) `phone pass with a variance: desktop finalize is refused…` (:77) و`the counter himself cannot finalize from the desktop (four-eyes)` (:85) يفشلان قبله، لكن بـ`throwsA(anything)` المتساهل. و`an approver who is none of the counters finalizes once…` (:92) قوي.
- (e) **PARTIAL.**
- (f) اعتبار المسودة مانعة. نقل الفحص والإكمال إلى معاملة واحدة. مطابِق محدد للاستثناء. اختباران: مسودة فقط، و`approverUserId=null`.

**WH-009: العمى بالدور.**
- (b) [wh_blind.dart:34-55](<../../../lib/services/api/m1_wh/wh_blind.dart#L34-L55>)، ومراجعة المدير مغلقة على العدّادين (`wh_count_handlers.dart:82`) [V].
- (c) صحيح على SQLite. على PG: `CAST(d.ref_id AS INTEGER)` (:38) والجدول نفسه يحمل `ref_id` غير رقمي (`refId: doc.gid` في [wh_transfer_service.dart:264](<../../../lib/services/api/m1_wh/wh_transfer_service.dart#L264>)). إن قيّم PG الـcast قبل فلتر `kind` ⇒ `invalid input syntax for type integer` [I]. واختبار PG (:85) يعمل على جدول فارغ.
- (d) `a supervisor who has started counting the task is blind on its items` (:130) و`...and after submitting; the manager review is closed…` (:137) يفشلان قبله.
- (e) **PARTIAL** (PG غير مُثبت).
- (f) `d.ref_id = CAST(t.id AS TEXT)` المحمول، مع اختبار PG فيه صفوف `ref_id` غير رقمية.

**WH-010:**
- لا تغيير. `/api/approvals/grant` خارج `warehousePaths`، و`approverOf` بلا ربط مستند، ومستعمل في approve/reject/resolve للتحويل والسند والجرد [V].
- **DEFERRED** (FIXES: قرار مالك لربط `scope` بمستند).
- المعالجة: ربط الإثبات بـ`kind:gid:action`، واختبار إثبات A على B ⇒ 403.

**WH-011: الضغط المزدوج.**
- (b) [wh_doc_store.dart:152-159](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L152-L159>) ⇒ `409 doc_mismatch` داخل معاملة `command`، فلا مستند فارغ. الخدمتان ترفضان `lines` الفارغة. والتطبيق: `_docId` ثابت و`_busy` في صفحتي طلب التحويل والسند (`transfer_pages.dart:161-212,236-303`) [V].
- (d) `a line id that belongs to ANOTHER document is 409 doc_mismatch and leaves no empty document (double tap)` (`wh_error_classification_test.dart:74`) يفشل قبله. و`WH-011: a double tap on «send for approval» queues ONE voucher document` (`docs_flow_test.dart:398`) يفشل قبله (على FakeOffice). لا اختبار لصفحة طلب التحويل.
- (e) **FIXED-PROVEN** (الخادم يضمن السلامة أيًّا كان العميل).
- (f) اختبار ضغطتين لصفحة طلب التحويل.

**WH-012:**
- التالف في استلام التحويل يُرسَل، مع فحص سليم+تالف ≤ المرسل في التطبيق والخادم (`transfer_pages.dart:71-81`، `wh_transfer_service.dart:228-231,261-271`) [V].
- مستند مطالبة/مرتجع المورّد لتالف أمر الشراء **لم يُنفَّذ**.
- الاختبار `WH-012: the damaged quantity of a transfer receipt is sent to the office` (`docs_flow_test.dart:364`) يفشل قبله، لكنه على FakeOffice فقط.
- **PARTIAL.**
- المعالجة: مستند مطالبة مورّد (قرار مالك)، واختبار خادم لاستلام تحويل بتالف > 0 والسند الناتج.

**WH-013:**
- `inventory_edit` في [role_grant_matrix.dart:463](<../../../lib/core/permissions/role_grant_matrix.dart#L463>) [V].
- `§B.4 «المدير»: كل ما سبق…` (`warehouse_role_grants_test.dart`) و`WH-013: the stock manager creates and lists vouchers` (`wh_voucher_flow_test.dart:117`) يفشلان قبله. «مخزني» و«مدير مخزون» ما زالا بـ`containsAll`.
- **FIXED-PROVEN.**
- تحسين: مطابقة المجموعات الأربع حرفيًا.

**WH-014:**
- الفلترة قبل `limit(100)` ([wh_count_service.dart:71-78](<../../../lib/services/api/m1_wh/wh_count_service.dart#L71-L78>))، والاختبار `WH-014: 150 newer tasks of another branch do not hide this branch's task` (:108) يفشل قبله.
- منع التداخل ومسار recount: لا تغيير ⇒ **PARTIAL** (المتبقي DEFERRED لقرار سلوك).

**WH-015:**
- لا تغيير. `BLUETOOTH_SCAN` ما زال في `AndroidManifest.xml:17`، ولا طلب إذن وقت التشغيل [V].
- **DEFERRED** (FIXES: لا جهاز Android 12+).

**WH-016:**
- أُصلح: `warehouse_app_e2e_test.dart:107-112` (صار تأكيدًا سلبيًا)، و`wh_count_finalize_test.dart:79-83` (قيم محددة) [V].
- لم يُصلح: `label_builder_test.dart:30-35` (تحصيل حاصل)، و`anyOf(403, 404)` في [wh_blind_count_leak_test.dart:112](<../../../test/integration/wh_blind_count_leak_test.dart#L112>)، و`throwsA(anything)` في `wh_count_integrity_test.dart:79,87`.
- **PARTIAL.**

**WH-017:**
- آخر تشغيل للمختبر: `20261026-012136`، 67 PASS / 0 FAIL / 2 N/A ([DEVICE-LAB-RESULTS.md:111-199](<../../2026-10-24-mirror-and-admin-login/DEVICE-LAB-RESULTS.md#L111-L199>)).
- المضيف «from the working tree» **بلا commit hash**، فلا يمكن ربطه بـ`b2f974df`.
- لا سيناريو سند ولا تبديل مستخدم. البند 5 في نفس الوثيقة (:103) يقول إن تبديل المستخدم لم يُمارَس، وهو بالضبط WH-004.
- G-2 (فحص العلامة على الـAPK) وG-3/SEC-006 (إبطال رمز الجلسة عند الخروج) مفتوحان (الخطة :526,540) [V].
- **NOT-FIXED.**
- المعالجة: إعادة المختبر على مضيف مبني من `b44098a7` مع تسجيل الـhash، وإضافة سيناريو سند وسيناريو A→B→A، وإغلاق G-2/G-3.

**WH-018:**
- `_audit` داخل معاملة `command` بعد سطر الحدث، والإعادة (replay) لا تُسجَّل مرتين، ومسار المكتب يمرّر `audit:false` [V].
- `every state change is written to the activity log with user and device (WH-018)` (:91) يفشل قبله.
- خطر PG: `ActivityLogger` يبتلع الاستثناء، لكن INSERT فاشلًا داخل معاملة PG يُفسد المعاملة كلها ⇒ فشل الأمر [I].
- **FIXED-PROVEN** على SQLite.
- المعالجة: SAVEPOINT للسجل على PG، مع اختبار.

**WH-019:** لا تغيير [V]. **DEFERRED** (Low/P3).

**WH-020:** لا تغيير (`inventory_dao.dart:289-295`، و`wh_voucher_service.dart:87-93`) [V]. **DEFERRED.**

**WH-021:**
- الاستراتيجية سحب فقط، فلا تكتب على الخادم [V].
- لكن الحارس الجديد في WH-001 يقرأ `received_quantity` محليًا على العميل (نسخة قديمة) [I]. ومسار `DELETE /api/purchase-orders/<id>` يحذف أمرًا له استلام [V].
- **DEFERRED** (قرار مالك). مرتبط بمعالجة WH-001 (f).

**WH-022:**
- `ltr()` مطبَّق في الاستلام والاعتمادات، وتسميات `kind_*` موجودة، ونصوص الخادم في `wh_constants.dart` [V].
- غير معزول بعد: `transfer_pages.dart:67,71,140`، و`count_pages.dart:59`، و`outbox_page.dart:60`، و`labels_page.dart:106` (نص خطأ خام).
- `docs_flow_test.dart:235` يتحقق من `\u2066137\u2069` ويفشل قبله.
- **PARTIAL.**

**WH-023:**
- `noPermission` في الشاشة الرئيسية، واختبار `shell_test.dart` يتحقق من «No permission» (يفشل قبله).
- **`dismiss()` ما زال يضبط `accepted`** ([wh_outbox.dart:249-255](<../../../mobile_warehouse/lib/sync/wh_outbox.dart#L249-L255>)) ⇒ `isDrained()` يحتسبه مقبولًا. وتعليق W0 قديم كما هو.
- **PARTIAL** (متّسق مع FIXES).

**WH-024:** `git ls-files mobile_warehouse/test/failures` = 0 ملف، و`.gitignore:231-232` يتجاهل المجلد [V]. **FIXED-PROVEN** بدليل `git`. حالة الـgoldens المعاد توليدها NOT_RUN.

**WH-025:**
- [wh_mobile_docs_schema.dart:19-31](<../../../lib/data/database/wh_mobile_docs_schema.dart#L19-L31>): الفشل يمسح الـExpando، والمستدعيان المتزامنان يتشاركان محاولة واحدة، والـDDL لم يتغيّر في `b2f974df` (الـdiff يمسّ دالة التخزين المؤقت فقط) [V].
- لا اختبار.
- **FIXED-UNTESTED.**

**WH-026:**
- المطابقة بـ`poItemId` مع تحقق المنتج ([wh_receipt_handlers.dart:124-134](<../../../lib/services/api/m1_wh/wh_receipt_handlers.dart#L124-L134>))، والتطبيق يرسله دائمًا (`receive_pages.dart:134`) [V].
- `WH-026: two lines of the same product are received separately, by poItemId` (:21) و`WH-026: a poItemId that is not of that product is refused` (:54) يفشلان قبله.
- **FIXED-PROVEN.** العميل القديم بلا `poItemId` يقع على آخر سطر للصنف.

**WH-027:**
- الفلترة بنطاق المصدر (`wh_approval_handlers.dart:41,47`) [V].
- `WH-027: a transfer request into my warehouse is not offered for approval unless the SOURCE is mine` (:69) يفشل قبله.
- **FIXED-PROVEN.**

**WH-028:**
- `transferStock` يُستعمل، و400 للكمية ≤ 0 وللمخزن المتطابق، و409 للنقص، ويرفض السالب أيًّا كان الإعداد ([api_data_inventory.dart:294-337](<../../../lib/services/api/data/api_data_inventory.dart#L294-L337>)) [V].
- يبقى ما ذكرته FINDINGS «ولا نطاق»: **لا فحص لنطاق مخازن المستخدم** في المعالج [V].
- `userId` يُؤخذ من الجسم (`data['userId']`، :276) لا من الجلسة [V].
- منع التكرار بـ`globalId` خارج المعاملة (:282-292) [V].
- المرآة ما زالت تصل المسار.
- 409 بمطابقة نص عربي (:333).
- اختبارات `a negative quantity no longer reverses the transfer` (:47) و`stock never goes negative, even with enable_negative_sales` (:54) و`the same warehouse on both sides is refused` (:74) تفشل قبله. أما :62 و:79 فضعيفان.
- **PARTIAL.**
- المعالجة: فحص النطاق، والمستخدم من الجلسة، ومنع التكرار داخل المعاملة، مع اختبار نطاق.

**WH-029:**
- `api_handler.dart` = **7,049** بايت LF (مقيس من `HEAD`) < 8,200 في `ci.yml:164` [V].
- النقل كان لتعليقات فقط، إلى `routes/api_handler_notes.dart` (`part of`). فيه عنوانان مشوَّهان (`roadcastChange`، وtab قبل `ransactionalPull`) [V عبر القارئ].
- خطوة CI لم تُشغَّل.
- **FIXED-UNTESTED.**

**WH-030:** لا تغيير (`wh_transfer_service.dart:215-216`) [V]. **DEFERRED** (قرار مالك).

---

## 4. مخاطر جديدة أدخلتها الإصلاحات

| المعرّف | الخطر | الدليل | الثقة |
|---|---|---|---|
| NEW-01 | المخطط والتوليد: **لا تغيير** في `database.g.dart` ولا `tables/` ولا `database.dart` ولا migrations (`git diff --stat 1ff2b6c1 b2f974df` فارغ لهذه المسارات). `wh_mobile_docs_schema.dart` غيّر التخزين المؤقت فقط، لا الـDDL | `git diff` | [V] |
| NEW-02 | **UNIQUE ⇒ 409 `duplicate_document` نهائي قد يصيب عملية نجحت.** على PG بمجمّع اتصالات: طلبان بنفس `X-Idempotency-Key` متزامنان (الهاتف يعيد بعد timeout بينما الأول قيد التنفيذ). كلاهما يقرأ `_event(id)` فارغًا ([wh_doc_store.dart:285-292](<../../../lib/services/api/m1_wh/wh_doc_store.dart#L285-L292>))، والثاني يصطدم بـUNIQUE على `global_id`/`command_id` ⇒ 409، فيعلّمه الهاتف `rejected` رغم أن الأول طُبِّق. قبل الإصلاح كان 500 ⇒ إعادة ⇒ replay ⇒ مقبول. ومثله تصادم `invoice_number` المولَّد تحت التزامن. على SQLite بمنفّذ واحد تُسلسَل المعاملات فلا يقع | قراءة | [I] (يحتاج اختبار PG) |
| NEW-03 | `503 busy` يدخل عدّاد `dead_letter` (5 محاولات ≈ 3.3 د)، و`dead_letter` بلا «إعادة» | `wh_outbox.dart:172-178` | [V] |
| NEW-04 | مرتبط وقائم: `convertPOToInvoice` القديم يُنشئ فاتورة **بلا ضريبة** وبلا مركز تكلفة وبأول مستخدم | `purchase_orders_dao.dart:232-257` | [V] |
| NEW-05 | الحارس الجديد يجعل زر «استلام وتحويل لفاتورة» ظاهرًا لأمر مستلم جزئيًا ثم يرفض بـtoast. وأمر مستلم جزئيًا لن يكتمل لا يُغلق إلا بالإلغاء | `purchase_orders_screen.dart:369-386` | [V] |
| NEW-06 | WH-028 يغيّر سلوك `POST /api/inventory/transfer` لعملاء سطح المكتب: تحويلات مطابقة لسلوك قديم (سالب مسموح) صارت 400/409. أثرها على طابور عميل سطح المكتب الصادر (هل يحجبه 409؟) لم يُفحص | `api_data_inventory.dart:300-337` | [I] |
| NEW-07 | SQL خاص بمحرك: `FOR UPDATE` محصور بـ`isPostgres` [V]؛ `CAST(ref_id AS INTEGER)` محمول نحويًا ويختلف سلوكه على PG (WH-009) [I] | `wh_stock_guard.dart:18`، `wh_blind.dart:38` | — |
| NEW-08 | File size ratchet: الملف المقيَّد الوحيد من الملفات المعدَّلة، `purchase_dao.dart`، لم يتغيّر (40,738 = الأساس). وكل الملفات المعدَّلة الأخرى تحت 30 KB (عتبة `file_size_ratchet_test`) بالقياس/التقدير: `api_data_inventory.dart` 23,831، و`purchases_picpos_screen.dart` 21,319، و`purchase_orders_dao.dart` 11,458، و`wh_outbox.dart` 10,130 | قياس LF من `HEAD` | [V] للمقيس |
| NEW-09 | `classifyWhFailure` يعتمد على نص رسائل عربية في DAOs. إعادة صياغة رسالة ترجع المسار إلى 500 بصمت (يحدّ أثرها `dead_letter`) | `wh_error_classifier.dart:21-35` | [V] |

---

## 5. ما يحتاج معالجة (بالأولوية)

1. **WH-001 (P0):** `sourceOrderId` عبر مسار العميل/المرآة إلى خادم `createPurchaseInvoice`، ومنع `convertPOToInvoice` محليًا في وضع العميل، مع اختبار تكامل `POST /api/purchases` بأمر مستلم جزئيًا ⇒ رفض.
2. **WH-002 (P0):** حوار المكتب في وضع العميل/المرآة عبر `desk/receipts` (أو إخفاء الزر بشرح)، مع widget test.
3. **NEW-02 (P1 على PG):** في `command`، `INSERT` لسطر الحدث **أولًا** (`ON CONFLICT DO NOTHING`، ثم replay إن وُجد)، أو قفل استشاري على `command_id`. وتحويل UNIQUE على `command_id`/`global_id` لنفس الـkey إلى replay لا إلى 409. اختبار PG بطلبين متزامنين بنفس الـkey ⇒ كلاهما 200 والثاني `replayed`.
4. **WH-006:** اختبار PG حقيقي باتصالين.
5. **WH-008:** المسودة تمنع الإكمال، والفحص داخل المعاملة، ومطابِقات محددة.
6. **WH-009:** cast نصّي محمول، واختبار PG.
7. **WH-028:** نطاق المخازن، والمستخدم من الجلسة، ومنع التكرار داخل المعاملة.
8. **WH-005/NEW-03:** فصل `busy` عن عدّاد `dead_letter`، وإجراء «إعادة».
9. **WH-017:** إعادة المختبر على `b44098a7` مع تسجيل الـhash وسيناريو A→B→A وسيناريو السند، وإغلاق G-2/G-3.
10. **WH-012 وWH-014 وWH-016 وWH-018 (PG) وWH-022 وWH-023 وWH-025:** كما في §3.

## 6. الأوامر التي يشغّلها القائد لإثبات البنود

لم يُشغَّل أيٌّ منها في هذه المراجعة.

```powershell
# من جذر المستودع D:\PICPOS-ERP (SQLite)
flutter test test/integration/wh_receipt_conversion_integrity_test.dart   # WH-001, WH-003
flutter test test/integration/wh_receipts_inbox_test.dart                 # WH-002
flutter test test/integration/wh_error_classification_test.dart           # WH-005, WH-011, WH-018
flutter test test/integration/wh_count_integrity_test.dart                # WH-007, WH-008, WH-009, WH-014
flutter test test/integration/wh_count_finalize_test.dart                 # WH-016 (anyOf removed)
flutter test test/integration/wh_misc_integrity_test.dart                 # WH-026, WH-027
flutter test test/integration/wh_lan_transfer_route_test.dart             # WH-028
flutter test test/integration/wh_voucher_flow_test.dart                   # WH-013
flutter test test/unit/warehouse_role_grants_test.dart                    # WH-013
flutter test test/structural/file_size_ratchet_test.dart                  # WH-029 / NEW-08
flutter test test/golden/                                                 # api_routes.txt (desk routes)
flutter test test/integration/                                            # كل wh_* معًا (انحدار)

# PostgreSQL (WH-006, WH-009 PG) — موسوم pg ومتخطّى افتراضيًا
$env:PG_TEST_DSN = '<dsn>'; flutter test test/integration_pg/wh_concurrency_pg_test.dart --tags pg --run-skipped

# حزمة الجهاز (WH-004 where)
cd packages/picpos_device; flutter test test/device_test.dart

# تطبيق المخازن (WH-004, WH-005 client, WH-011, WH-012, WH-022, WH-023, WH-024 goldens)
cd mobile_warehouse; flutter test test/outbox_drain_test.dart test/docs_flow_test.dart test/shell_test.dart test/e2e/warehouse_app_e2e_test.dart
cd mobile_warehouse; flutter test          # كاملًا: يجب ألا تُنشأ test/failures/

# فحص CI للحجم (WH-029): خطوة «Check God-File size thresholds» في .github/workflows/ci.yml
git ls-files mobile_warehouse/test/failures   # WH-024: يجب أن يكون فارغًا
```

## 7. حدود هذا التحقق

- لا تشغيل لأي اختبار. «يفشل قبل الإصلاح» استدلال من قراءة الكود القديم والـdiff، والتأكيد بتشغيل الاختبار على `1ff2b6c1` (يتطلب نسخ الاختبار إلى شجرة معزولة).
- لم أقرأ `transferStock` كاملًا (WH-028: الدفعات وGIT)، ولا `ClientWriteInterceptor.submitPurchase` نفسه. غياب `sourceOrderId` عنه مستنتج من grep على `lib/services` (صفر نتائج) ومن موضع استدعائه.
- إتاحة شاشة أوامر الشراء في وضع العميل (`AppConfig.allowedScreenIds`) لم تُفحص. لذلك WH-001 لمسار `convertPOToInvoice` على العميل [I]، أما مسار «سحب أمر شراء» على العميل فـ[V].
- سلوك PG (القفل، والـcast، والمعاملة الفاسدة، وNEW-02) كله [I].

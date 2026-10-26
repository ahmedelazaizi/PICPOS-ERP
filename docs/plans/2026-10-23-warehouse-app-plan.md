# خطة: تطبيق «PicPos مخازن» (`com.picpos.warehouse`) — 2026-10-23

## سجل التغييرات
**2026-10-23 — مواءمة مع قرار المالك 3 ومع المراجعة `docs/audits/2026-10-23-release-audit/`.** المعرّفات من `FINDINGS.md` هناك.

- **قرار المالك 3:** التطبيق لأربعة أدوار (مسؤول المخزن، المشرف، المدير، الموظف)، يُثبَّت على هاتف الموظف، ويُقرن بصلاحية المدير المسؤول عن ربط وإقران الأجهزة. أُضيف §B.4 (نموذج الصلاحيات):
  - صلاحية جديدة `devices_pair_manage` تحرس إصدار رموز الإقران وإلغاءها في طبقة الخدمة. اليوم تُحرس الواجهة فقط بعلامة `system_admin`.
  - ربط الأدوار الأربعة بأدوار قائمة وجديدة.
  - حُدِّثت §B.3 وW1 وE-7، وأُضيف E-12 وE-13.
- **بنود حاكمة لـW0 (G-1…G-7) من المراجعة:**
  - توقيع Android يفشل مغلقًا (REL-004).
  - بناء APK في CI مع فحص العلامة (ARCH-006، BRAND-012).
  - تحصين الإقران (SEC-006، SEC-007، حمولة P7 v2).
  - إبطال التوكنات وفحص المستخدم النشط (SEC-003).
  - القراءات غير الموثّقة على LAN (SEC-008).
  - فرض تغيير كلمة المرور على مسار الـAPI (SEC-002).
  - صلاحية الإقران الجديدة.
- **تصحيح:** §A.7 كانت تقول إن QR المشرف يحمل «مفتاح توقيع طويل العمر». المراجعة نقضت ذلك (SEC-017): الـQR يحمل المفتاح **العام** مع رمز لمرة واحدة صالح 10 دقائق. يبقى فقط غياب مسار تدوير المفتاح.
- **التقدير:** W1 صارت 6.5–7 أيام بدل 6 (+0.5–1 يوم للصلاحية والأدوار). البنود الحاكمة عمل منفصل في خارطة المعالجة (SPEC-02، SPEC-10، SPEC-11، ≈ 5–8 أيام) وليست ضمن أيام W0.
- **طريقة التعليم:** النص المصحَّح أو الملغى يُعلَّم صراحةً، ولا يبقى نص متعارض.

> وثيقة تخطيط فقط (لا كود). الفرع: `feat/tables-reservations-permissions` (HEAD `d69be1ea`). `schemaVersion` الحالي **196** (`lib/data/database/database.dart:673`).
> المرجع المعماري: `docs/mobile/ARCHITECTURE-MC.md` (المرحلة M-C، «plan only»، **لم تُنفَّذ قط**)، ويُبنى على `ARCHITECTURE-M.md` (ADR-M1..M5) و`ARCHITECTURE-I.md`.
> كل بند موسوم **[مقروء]** (تحقّقتُ منه بالقراءة، مع file:line) أو **[استنتاج]**. لم يُشغَّل أي `flutter`/`dart`/build_runner/اختبار/Android. أرقام الأسطر لقطة وقت الكتابة، فالمنفّذ يعيد تحديد المواضع بـgrep قبل التحرير.
> المنفّذ (Sonnet) يلتزم بـ`docs/ARCHITECTURE-MAP.md` §2–§4 و§7: الملفات الجديدة ≤ 30KB، لا نموّ لملف مسجَّل في `test/structural/file_size_baseline.txt`، ترحيلات idempotent بـ`_safeMigrate`، تحديث `test/golden/api_routes.txt`، ولا أوامر `flutter` متوازية.

## فهرس
- §A النتائج: ما تقوله MC، وما في الكود فعلًا، والتعارضات
- §B قرارات التصميم + قواعد سلامة البيانات + تجربة الاستخدام + §B.4 نموذج صلاحيات الإقران والأدوار (2026-10-23)
- §C خطة التنفيذ W0–W6 + جدول التوازي
- §D الحراس البنيوية
- §E قرارات المالك المطلوبة (مع الافتراضي الموصى به)
- §F حدود هذا التخطيط

---

## A. النتائج (Findings)

### A.1 — ما تحدّده `ARCHITECTURE-MC.md` [مقروء]
- **ADR-MC1** (:19): تطبيق offline-first منفصل بجانب M-A/M-B يشارك `picpos_ui`/`picpos_api_client`/`picpos_device`/`picpos_rules`. فيه catalog محلي مشفّر بنطاق المخزن، وtask cache، وdurable command outbox. يصل إلى سطح المكتب مباشرة على LAN، وعن بُعد عبر cloud command relay (ADR-M2) **وليس دفتر مخزون سحابي**. «pending» و«rejected» تظهران منفصلتين.
- **ADR-MC2** (:20): scan pipeline موحّد `ScannerInput{value,symbology?,source,at}` بمصادر camera وwedge وZebra DataWedge intent وHoneywell وUrovo broadcast، مع dedup للصدى المزدوج، وإدخال يدوي، وحلّ الملصق إلى صنف أو دفعة أو موقع.
- **ADR-MC3** (:21): جرد أعمى (blind count). DTO العدّاد لا يحمل `expectedQty` ولا القيمة ولا الفرق ولا عدّ الآخرين. يُعاد العدّ عند تجاوز العتبة، ويعتمد مدير مختلف قبل `finalizeCycleCountTask`. لا إنهاء offline، ولا يُعاد استعمال `CycleCountItemView`.
- **ADR-MC4** (:22): ledger للمواقع (bins) بلا «حقيقة مخزون ثانية». مجموع المواقع = رصيد المخزن، والنقل بين المواقع صفري الأثر على المخزن وGL.
- **ADR-MC5** (:23): مستندات مرحلية تنفّذها سطح المكتب: طلب تحويل ← اعتماد ← dispatch بمسح FEFO ← استلام بمسح + فروقات. استلام PO منفصل عن فاتورة المحاسب. السندات بسبب واعتماد. `transferStock` لا يُستدعى مرتين.
- **النطاق R1** (:27-36): Lookup، Counts، Transfers، PO goods receipt، Stock vouchers، Labels. **خارج النطاق:** فاتورة شراء من الجوال، تقييم المخزون على الجهاز، اعتماد تلقائي، تعدد الشركات، ادعاءات عتاد بلا تجربة فعلية.
- **العقود** (:48-65): مسارات LAN مقترحة `/api/m1/wh/*` (bootstrap/pull/items/movements/counts/review/approve/transfers/po receipts/vouchers/labels). أرقام عشرية كنصوص، و`X-Idempotency-Key` = `globalId`/`commandId`، و`expectedVersion`. الأخطاء: `permission_denied|stale|invalid_transition|stock_changed|batch_expired|discrepancy_requires_approval|period_closed|desktop_offline`. جسم مختلف لنفس المفتاح ⇒ `409 idempotency_conflict`.
- **مصفوفة الصلاحيات** (:67-82): أكواد مقترحة `warehouse_mobile_access`, `stock_count_submit`, `stock_adjust_approve`, `goods_receipt_mobile`. أكواد التنقّل (`stock_view`, `stock_audit`, `warehouses_view`) لا تُستعمل للفحص الخادمي. الرفض افتراضي، وDTO العدّ نوعٌ منفصل.
- **الشاشات** (:84-93): هاتف بتبويبات سفلية (Tasks, Scan/Lookup, Documents, Outbox)، وhandheld 480×800 scan-first بأزرار كبيرة، وtablet بلوحتين. AR/EN وlight/dark وفق `DESIGN.md`. أهداف لمس ≥ 48dp واهتزاز/صوت مع النص.
- **الطريق** (:97-105): M-C0 (spike عتاد + shell + outbox + طباعة) ← M-C1 (bins + lookup) ← M-C2 (blind counts) ← M-C3 (تحويلات/استلام/سندات) ← M-C4 (UI + مراجعة المالك). وفيه مصفوفة عتاد فعلي (:107).

### A.2 — تعارضات MC مع الكود الحالي (مهم للمنفّذ)
| بند في MC | الواقع اليوم | الأثر على الخطة |
|---|---|---|
| «لا bin/location في الجداول» (:9) والترحيل «not implemented» (:40) | **[مقروء] المواقع موجودة منذ v195:** جدولا `warehouse_locations` و`location_stock` raw SQL (`lib/data/database/warehouse_locations_schema.dart:86-135`)، وعمودا `stock_movements.location_id/batch_id` (:9-12)، وbackfill لموقع `DEFAULT` بباركود `BIN-<wh>-DEFAULT` (:16-48)، وتقرير فروقات (:50-75)، وتفعيل `warehouse_bins_enabled` لا يُكتب إلا بلا فروقات (:77-83). الترحيل في `epoch_3_v174_v195.dart:373-375`. CRUD والنقل بين المواقع في `daos/warehouse_locations_ops.dart:13-163` (النقل يكتب حركتين `bin_move` بلا GL). الخصم من المواقع `daos/bin_stock_ledger.dart` (`deductIssuedBinStock` :8 بترتيب `bin_code`، و`syncDefaultBinStock` :39). الشاشة `presentation/screens/warehouse_locations_screen.dart`. الجدولان مُزامنان (`api_sync_pull_tables.dart:81,240`؛ `delta_pull_service.dart:81,116`). | **M-C1 منجز في معظمه.** لا ترحيل للمواقع. ينقص: lookup موقع بالباركود (لا DAO له [مقروء: grep])، وتمرير الموقع في الاستلام والتحويل. |
| `transferStock` يرحّل الطرفين فورًا (:11) | **[مقروء]** صحيح (`inventory_transfers_dao.dart:53-239`). يمنع السالب في المصدر دائمًا (:97-108)، ويكلّف بمتوسط المصدر (:117-120)، ويحمل الدفعات `carryTransferLots` (`bin_transfer_lots.dart:6`)، ويرحّل قيدين عبر `goods_in_transit` (:193-234 بحسب القارئ). | التحويل المرحلي يُبنى بتقسيم هذا المنطق إلى `dispatch`/`receive` في ملف جديد، ويبقى المسار القديم. |
| — (لم تذكره MC) | **[مقروء] مسار LAN `POST /api/inventory/transfer` تنفيذ موازٍ مختلف:** `api_data_inventory.dart:266-352` يستدعي `adjustStock` للطرفين مباشرة بنوعَي `transfer_out/transfer_in`. لا يمرّ بـ`transferStock`: لا منع صريح للسالب، ولا `carryTransferLots`، ولا قيود `goods_in_transit`. ونوعا الحركة خارج `adjustmentAccountedTypes` (`inventory_dao.dart:371-373`) ⇒ **لا قيد** [استنتاج]. | **تطبيق المخازن لا يستعمل هذا المسار إطلاقًا.** يُبلَّغ كتباين قائم خارج نطاق هذه الخطة (§E-9). |
| «PO `convertPOToInvoice` يجمع الاستلام والفاتورة ويُسقط batch/expiry» (:46) | **[مقروء]** صحيح: `purchase_orders_dao.dart:205-239` يحوّل **كل** كميات الأمر إلى فاتورة آجلة عبر `createPurchaseInvoice`، ولا يمرّر batch/expiry (:216-225)، ويأخذ **أول مستخدم في الجدول** كـ`defaultUser` (:212). منع التحويل المزدوج بـ`convertedToInvoiceId` (:177-188). العمود `PurchaseOrderItems.receivedQuantity` **موجود** (`sales_purchase_tables.dart:546`) لكن لا كاتب له في `lib/` سوى المزامنة (`purchase_order_sync_strategy.dart:82,140`) [مقروء: grep]. | استلام جزئي ممكن **بلا عمود جديد على PO** باستعمال `received_quantity`. التحويل للفاتورة بالكميات المستلمة يأتي في ملف جديد. |
| Count tasks «store expected» (:12) | **[مقروء]** `CycleCountItems.expectedQty/countedQty/variance` (`cycle_count_tables.dart:75-91`). المهمة بلا `warehouseId` (تُؤخذ من الخطة). `generateCycleCountTask` يختار أصنافًا رصيدها > 0 فقط (`cycle_count_dao.dart:89,97-131`). `finalizeCycleCountTask` (:458-545) idempotent بقيد مجمّع واحد (`inventory_shrinkage`/`inventory_surplus`)، والفرق = المعدود − الرصيد **الحالي** (:394-440). | يُعاد استعماله كما هو. المواقع والأصناف غير المتوقعة تُجمَّع على سطح المكتب قبل `submitCount`. |
| relay سحابي `/manage/commands` → `/desktop/relay/next` | **[مقروء] غير موجود:** لا مسارات (`server/lib/src/http/app.dart`, `admin_routes.dart`)، و`migrations.dart:575-576` يؤجّلها، ولا `MobileGateway`/`remote_commands`/`CloudRelayWorker` في `lib/` [grep: صفر]. | **R1 = LAN فقط** (§B.1، §E-1). المسار السحابي مرحلة لاحقة خارج W0–W6. |
| `picpos_device` فيه wedge فقط (:13) | **[مقروء]** صحيح: `scan/scanner_input.dart` فيه `normalizeScan` (:10) و`KeyboardWedgeBuffer` (:12-42) فقط. لا camera ولا intents. الطباعة ESC/POS raster مع Code128/QR داخل الصورة، ولا ZPL/TSPL ولا ملصقات (`printing/escpos.dart:39-91`, `receipt_renderer.dart:141-166`). | W0 يضيف `ScanEvent`/dedup. الكاميرا في التطبيق. intents وملصقات العتاد في W5 خلف profiles. |
| TLS pinning على LAN | **[مقروء]** الخادم المضمَّن يدعم TLS بشهادة يوفّرها المشغّل (`network_service.dart:799-821`). العميل بلا pinning (`transport.dart:50-51`، و`docs/security/part1-cloud-mobile.md` C-1 :192-196). `TransportSelector` يجسّ `GET /api/m1/info` (`transport.dart:96-129`)، والمسار **غير مسجّل** على سطح المكتب (لا يظهر في `test/golden/api_routes.txt`). | W1 يضيف `/api/m1/info` وTOFU fingerprint (قرار المالك F.5 في خطة 2026-10-18). |

### A.3 — ما هو موجود من API وجداول للتدفقات [مقروء]
- **المسارات (179 في `test/golden/api_routes.txt`).** القراءة: `GET /api/products` :6، `/warehouses` :17، `/stock-movements` :32، `/inventory-balances` :33، `/product-barcodes` :36، `/products/barcode` :37، `/user-warehouse-access` :39، `/product-units` :41، `/product-batches` :46، `/purchase-orders` :48. الكتابة: `/api/inventory/adjust` :86 (`inventory_edit`، `api_data_inventory.dart:14`)، و`/inventory/transfer` :87 (`inventory_transfer` :270)، و`/inventory/bond` :88 (`inventory_edit` :378)، وpurchase-orders :144-146 (تعيد استعمال `purchases_create/edit/delete`، `api_data_documents.dart:14,94,111`)، و`GET /api/sync/pull` :168، و`POST /api/auth/session` :162 (`api_auth_handler.dart:156`، يصدر `X-Session-Token` من username/password أو `cardCode`). **لا `/api/m1/*`، ولا مسارات count/requisition/location.** `POST /api/pair` يُعالَج داخل الـmiddleware (`api_auth_middleware.dart:218-220`).
- **النطاق.** القراءات تمرّ بـ`_resolveBranchWarehouseIds` (`routes/api_branch_scope.dart:75-156`)، وبعضها يفشل مغلقًا بلا هوية (`api_get_documents.dart:166,226,263,359`). **الكتابات adjust/transfer/bond لا تفحص نطاق الفرع ولا المخزن** [استنتاج من القراءة :54, :274-275, :386].
- **Idempotency.** `processed_messages` + `checkIdempotency`/`storeIdempotency` (`api_handler_base.dart:77-137`). التخزين **بعد** الـcommit، ولا مقارنة hash للجسم. التحويل والسند يمنعان التكرار بـ`inventory_bonds.globalId` (`api_data_inventory.dart:279-292`).
- **مصادقة جهاز LAN.** `/api/pair` يقبل `deviceKind` بقيمتي `admin|pos` فقط (`lan_pairing_api_handler.dart:47-57`). التوكن HMAC(install secret, deviceId) (`lan_pairing_service.dart:404-411`)، والأجهزة في `lan_paired_devices` مع `device_kind, branch_id, terminal_code` (:323-331, :594-611). **`deviceKind` لا يقيّد أي مسار** بعد الإقران [مقروء: لا ذكر له في `api_auth_middleware.dart`].
- **المخزون.** `adjustStock` (`inventory_dao.dart:116-149`) فيه `FOR UPDATE` على PG (:167-179) ومنع الفترات المغلقة (:184-194). **السالب** مسموح إذا مُرِّر `allowNegativeSale` **أو** كان الإعداد `enable_negative_sales` **أو** علم الصنف (:210-214)، فتمرير `false` وحده لا يمنعه. عند تفعيل المواقع والحركة صادرة يستدعي `syncDefaultBinStock` (:228-231). القيد التلقائي لأنواع `cycle_count|adjustment|write_off|loss|waste|damage` فقط (:371-377). الدفعات FEFO/FIFO في `inventory_batch_dao.dart` (`getBatchesForIssue` :65، `consumeBatchesForIssue` :137، `restoreBatchForReturn` :196). الشراء `createPurchaseInvoice` (`purchase_dao.dart:25-69`): المخزون بـ`adjustStock(type:'purchase')` (:396)، والدفعة فقط إذا `trackExpiry` + تاريخ انتهاء (:415-431)، والقيد (:620).
- **الباركود.** `getProductByBarcode` (`product_barcode_units_dao.dart:13`: `products.barcode` ثم `product_barcodes`)، و`getProductByUnitBarcode` :260، و`getUnitByBarcode` :275.
- **نطاق المستخدم.** `UserWarehouseAccess`/`UserBranchAccess` (`auth_tables.dart:100-115`). `getWarehouseScopeForUser` (`user_dao.dart:640`) يعيد null للمطلق و`{}` لعدم الوصول. `Warehouses.branchId` اختياري (`inventory_tables.dart:45-62`).
- **الطلبات (requisitions).** على مستوى **الفرع** لا المخزن (`inventory_tables.dart:214-241`). `updateStockRequisitionStatus` كتابة حالة عارية (`inventory_transfers_dao.dart:285-291`).
- **التدقيق.** `ActivityLogs` بسلسلة hash (`auth_tables.dart:129-149`)، والخدمة `ActivityLogger.log` (`services/activity_logger.dart:117`)، ومساعدات `logging/log_inventory.dart`.

### A.4 — شاشات سطح المكتب الحالية [مقروء]
`inventory_picpos/screens/inventory_picpos_screen.dart` (الأرصدة)؛ `stock_transfer_picpos/screens/stock_transfer_picpos_screen.dart:184` «سند تحويل اصناف» (+القديمة `screens/inventory/stock_transfer_screen.dart`)؛ `screens/inventory/inventory_bonds_screen.dart:148` «أرصدة المخزون»؛ `screens/stock_audit_screen.dart` (جرد `StockAudits`)؛ `cycle_count_picpos/screens/cycle_count_picpos_screen.dart` (+القديمة)؛ `screens/inventory/stock_requisitions_screen.dart`؛ `screens/warehouse_locations_screen.dart`؛ `screens/purchase_orders_screen.dart:370` «استلام وتحويل لفاتورة». شاشتا الجرد تمنعان الاعتماد من جهاز عميل/مرآة (`cycle_count_picpos` :332، `stock_audit` :404).

### A.5 — الصلاحيات [مقروء]
`permission_codes.dart`: `inventory_view` :237، `inventory_edit` :240، `inventory_transfer` :243، `warehouses_manage` :246، `warehouses_view` :898، `stock_view` :901، `stock_audit` :904، `products_stock_view` :292، `purchases_*` :364-376، `purchase_orders_view` :397. **الأكواد الأربعة المقترحة في MC غير موجودة.** الأدوار: `'مخزني'` (`role_grant_matrix.dart:203`؛ بلا `inventory_transfer`) و`'مدير مخزون'` (:426). `knownUnenforced` لا يحوي أكواد مخزون (`permission_enforcement_registry.dart:28-121`).
**قيد حجم حرج:** `permission_codes.dart` = **93,670 بايت = سقف الـbaseline بالضبط**، و`database_seeder_permissions.dart` = 62,492 (السقف) [مقروء: قياس LF]. أي إضافة تتطلب تعويضًا بنفس عدد البايتات أو ملفًا جديدًا (§C-W1).

### A.6 — التطبيقان الشقيقان والحزم [مقروء]
- **`mobile_pos/`** (`picpos_pos`, `com.picpos.pos`): `lib/{main,app}.dart` و`shell/pos_shell.dart` (`PicPosAdaptiveScaffold`: rail للتابلت وbottom bar للهاتف) و`screens/*` و`l10n/strings.dart` (`L10nTable` بأزواج (ar,en)، `t('key')`). لا Riverpod ولا router (تبديل `setState`، `app.dart:38-46`). الربط معطَّل بالكامل (`onboarding_screen.dart:6-7,40-64`). الاختبارات: `structural_test.dart` (لا ألوان hard-coded :12-29، وكل `t('key')` موجود :38-47)، و`golden_test.dart` (AR/EN × light/dark × phone 411×891 / tablet 1280×800، `support.dart:6-15` يحمّل الخطوط)، و`shell_test.dart`، و`e2e/pos_app_e2e_test.dart` (اثنان فعليان، وستة `skip`). التوقيع يرجع إلى debug key عند غياب `key.properties` (`build.gradle.kts:14-21,60`).
- **`mobile_admin/`** (`com.picpos.admin`): `admin_session.dart` (ChangeNotifier). الأسرار في `KeystoreSecretStore` (:8-10, :50-53). الإقران `/manage/pair` مع مطابقة `desktopSigningKey` (:109-165)، وsnapshots موقّعة Ed25519 (:55,135,211)، وTOTP اختياري، و`deviceRevoked` ⇒ wipe (:190-194). **قفل التطبيق موجود الآن** (`app_lock.dart:9,66,91`، PIN بـPBKDF2 :81-101)، فبند M-6 في المراجعة الأمنية متقادم. التوقيع يفشل مغلقًا (`build.gradle.kts:10-34,87`) — **هو النمط الذي يُنسخ**. e2e حقيقي ضد خادم السحابة كعملية فرعية (`test/e2e/support/e2e_cloud.dart:47-74`).
- **`mobile/`** (Van): `mobile_scanner ^7.4.2` (`screens/barcode_scanner.dart:2,26,76`)، و`sqflite_sqlcipher`، و`workmanager`.
- **الحزم:** `picpos_device`: `SqlCipherLocalStore` (`store/sqlcipher_store.dart:15-30`)، و`DatabaseKey` (`db_key.dart:39-53`)، و`Outbox` (enqueue idempotent بـglobalId، drain بالترتيب، `pending|accepted|rejected`، `outbox.dart:36-94`، `local_store.dart:8-37`)، و`Backoff` (:98-118)، و`PrintService` بطابور إعادة (`print_service.dart:115-230`)، و`BluetoothThermalTransport`/`NetworkPrinterTransport`. `picpos_api_client` (Dart خالص): `HttpApiTransport`، و`UrlPolicy` (release=https، `url_policy.dart:20-50`)، و`ApiHeaderBuilder` مع `x-idempotency-key` (`headers.dart:7-78`)، و`ApiError` (:69-125). `CloudManageClient` هو العميل الوحيد المنفَّذ، و`M1PosApi`/`M1AdminApi` واجهات بلا تنفيذ (`contracts.dart:188-213`). `picpos_ui`: `PicPosMaterialApp`، والثيم M3 light/dark، و`ConnectionChip`، و`AsOfBadge`، و`PicPosDataList`. **لا** offline banner ولا scan field ولا keypad. `picpos_rules`: بلا قواعد مخزون.
- **الجذر يعتمد على `picpos_api_client`** (`pubspec.yaml:47-48`) ⇒ يمكن لاختبار جذري أن يشغّل عميل المخازن الحقيقي ضد `ApiHandler` حقيقي (النمط موجود: `test/scenarios/sc_n_api_sale_test.dart:44-45`).
- **CI/E2E:** مصفوفة `packages_and_mobile` (`.github/workflows/ci.yml:352-367`)، وأسطر `run_suite` (:542-544)، وجدول `$suites` في `tool/run_e2e.ps1` (:126-134، نسخ helper :46-51)، و`docs/testing/E2E.md` (:24,31,41,84-86). **الـratchet يفحص `lib/` في الجذر فقط** (`file_size_ratchet_test.dart:36`)، فالتطبيقات تحتاج حارسها الخاص.

### A.7 — قصة الإقران الحالية والمعروفة المشاكل [مقروء]
- خطة 2026-10-18 §A.3/P7: Cashier بلا إقران، وحوار LAN نصي بلا QR، ولا `/api/m1/info`.
  - **[مصحَّح 2026-10-23 — SEC-017]** وصف تلك الخطة لـQR المشرف بأنه «يحمل `desktopSigningKey` طويل العمر» غير دقيق. الحقل هو المفتاح **العام** Ed25519 (`linked_devices_section.dart:799-816`، `cloud_link_controller.dart:202-209`)، والرمز لمرة واحدة لمدة 10 دقائق. كشف الـQR لا يكشف سرًّا؛ الناقص فقط مسار تدوير أو إبطال للمفتاح.
- قرار المالك F.5 في خطة 2026-10-18: TLS ذاتي + TOFU عبر `fp` في الـQR، ولا cleartext في release.
- **حالة P7 الآن [مقروء: grep]:** لا `pairing_payload.dart` في `picpos_api_client` (`PairingOffer` v1 فقط، `manage_client.dart:18-65`)، و`/api/pair` ما زال `admin|pos` ⇒ **P7 لم يُنفَّذ بعد.**
- السحابة: أكواد 8 أحرف، 10 دقائق، استعمال واحد، مخزّنة sha256 (`server/lib/src/security.dart:10-19`، `auth_service.dart:45-76`). الأجهزة في `devices`/`admin_devices`. **السحابة تحمل مخزون الفان فقط** (`desktop_service.dart:154-168, 895-917`)، ولا تحويلات ولا جرد. آخر ترحيل سحابي **8** (`migrations.dart:640`).

---

## B. قرارات التصميم

### B.1 — المعمارية (ADR-W1..W8)
- **ADR-W1 — النقل في R1 هو LAN فقط إلى الخادم المضمَّن في سطح المكتب.** المسارات `/api/m1/wh/*` تُسجَّل في `ApiHandler`. لا relay سحابي في R1 لأنه غير موجود (A.2)، وبناؤه مشروع بحجم M-2 كاملًا. يعمل التطبيق offline بالكامل للقراءة والمسودات، ويُرسل عند عودة الشبكة. المخازن البعيدة في R1 تحتاج VPN أو أن تكون على شبكة الفرع. **قرار المالك E-1.** لا تغيير في `server/` إلا اختياريًا (W6).
- **ADR-W2 — الإقران يعيد استعمال `/api/pair` بنوع جديد `deviceKind:'warehouse'`.** المطلوب `branchId`، ولا يُخصَّص terminal code. الـpayload v2 من P7 (`{v:2,kind:'lan',url,code,exp,fp}` **بلا أسرار**). إن لم يكن P7-A مدموجًا تنفّذ W1 الحد الأدنى منه: `PairingPayload` في الحزمة + خيار «مخازن» في `lan_pairing_dialog.dart` مع `QrImageView` (`qr_flutter` موجود في `pubspec.yaml:49`). الدخول بعد الإقران: `POST /api/auth/session` (username/password أو `cardCode`)، ثم قفل محلي بـPIN بنمط `mobile_admin/app_lock.dart`.
- **ADR-W3 — حصر المسارات بنوع الجهاز.** ملف جديد `lib/services/api/lan_device_route_policy.dart`: جهاز `warehouse` لا يقبل إلا `/api/m1/info` و`/api/auth/session` و`/api/m1/wh/*`، والباقي `403 device_scope`. يُستدعى من `api_auth_middleware.dart` بسطر واحد بعد التحقق من الجهاز. (تقييد `pos` مشكلة قائمة تُبلَّغ في §E-9 ولا تُعالَج هنا.)
- **ADR-W4 — النطاق.** المخازن المسموحة = `getWarehouseScopeForUser(user)` (null = الكل) ∩ مخازن فرع الجهاز (`warehouses.branch_id = device.branch_id`، أو `branch_id IS NULL` إن قرّر المالك ذلك). يُفحَص في **كل** مسار `/api/m1/wh/*` على الخادم، لا في الواجهة فقط. الحل الموحّد في ملف جديد `lib/services/api/m1_wh/wh_scope.dart`. **لا ترحيل.**
- **ADR-W5 — مستندات الجوال جدولان + سجل أوامر، والترحيل عبر المسارات الحالية فقط.**
  - الجدول `wh_mobile_docs` يحمل: `global_id UNIQUE`، `kind`، `state`، `warehouse_id`، `to_warehouse_id?`، `ref_type/ref_id` (PO أو مهمة الجرد)، `reason`، `created_by`، `device_id`، `approved_by/at`، `posted_ref_type/id`، `row_version`، وأعمدة المزامنة. قيم `kind`: `po_receipt|transfer|voucher_in|voucher_out|voucher_damage|count_submission`.
  - الجدول `wh_mobile_doc_lines` يحمل: `doc_id`، `line_global_id UNIQUE`، `product_id`، `unit_id?`، `qty_base`، `location_id?`، `batch_id?`، `batch_number?`، `expiry_date?`، `condition`، `po_item_id?`، `pass`، `observed_at`، `counter_user_id?`. قيم `condition`: `ok|damaged|short|over`.
  - الجدول `wh_mobile_doc_events` يحمل: `command_id UNIQUE`، `doc_id`، `action`، `actor_user_id`، `device_id`، `payload_hash`، `result_json`، `at`. هو سجل الأوامر وidempotency معًا، ويُكتب **داخل نفس معاملة الأثر**. هذا بخلاف `storeIdempotency` الذي يكتب بعد الـcommit (`api_handler_base.dart:118`).
  - **ترحيل واحد فقط** في الخطة كلها (W2).
  - الأثر المخزني والمحاسبي **حصرًا** عبر `adjustStock` و`createPurchaseInvoice` و`finalizeCycleCountTask` و`moveStockBetweenBins` ودالة الإرسال/الاستلام المستخرجة من `transferStock`. لا كتابة مباشرة في `inventory_balances` ولا القيود.
- **ADR-W6 — «رحّل ثم ضع في الموقع» (post-then-put-away).** الوارد يُرحَّل على مستوى المخزن، فيذهب إلى `DEFAULT` عبر `syncDefaultBinStock`. ثم يُنقل إلى الموقع الممسوح بـ`moveStockBetweenBins(DEFAULT→bin)`، وهو صفري GL [مقروء: `warehouse_locations_ops.dart:79-163` لا يرحّل قيدًا]. الصادر من موقع محدد: `moveStockBetweenBins(bin→DEFAULT)` ثم الترحيل. هذا يحقق ADR-MC4 بلا ledger ثانٍ. يعمل فقط عند `warehouse_bins_enabled='true'`، وإلا تُخفى حقول الموقع في التطبيق.
- **ADR-W7 — جرد أعمى بمهام الجرد الدوري الحالية.** المهمة تُنشأ على سطح المكتب (`generateCycleCountTask`)، أو من المدير على الجوال لاحقًا (W5). العدّاد يرسل إدخالات لكل (موقع، صنف، دفعة) في `wh_mobile_doc_lines` (`kind=count_submission`، `pass`). عند الإرسال يجمع الخادم الإدخالات لكل صنف، ويضيف أسطرًا للأصناف غير المتوقعة (expected = الرصيد الحالي)، ويستدعي `submitCount`. المراجعة والاعتماد عبر DTO مدير منفصل، ثم `finalizeCycleCountTask` الموجود. **العتبة** (§E-4) تفرض pass=2 بعدّاد آخر قبل الاعتماد.
- **ADR-W8 — المسح.** في `picpos_device` تُضاف `ScanEvent{value,symbology?,source(camera|wedge|intent|manual),at}` و`ScanDeduper(window=800ms)` و`WedgeScanSource` (تغليف `KeyboardWedgeBuffer`). الكاميرا (`mobile_scanner`) في **التطبيق** وحده، حتى لا تُفرض على POS/Admin. DataWedge يُضبط في R1 على keystroke output (= wedge)، وadapter الـintent/broadcast (Kotlin `BroadcastReceiver` + `EventChannel`) في W5 خلف profile لكل موديل مجرَّب فعليًا. `normalizeBarcode` من `picpos_rules`. الحلّ: `BIN-` ⇒ موقع، وإلا باركود منتج/وحدة، وإلا رقم دفعة ضمن نطاق المخزن.

### B.2 — قواعد سلامة البيانات
1. **السالب:** مستندات المخازن **لا تُسقط أي رصيد تحت الصفر مهما كان `enable_negative_sales`**، على نهج `transferStock` :97-108. فحص صريح داخل المعاملة قبل `adjustStock` يقرأ الرصيد بعد القفل، وعند العجز يعيد `stock_changed` مع الكمية المتاحة لمن يملك `inventory_view` فقط. (تمرير `allowNegativeSale:false` لا يكفي، A.3.)
2. **الاستلام المزدوج:**
   - `wh_mobile_docs.global_id UNIQUE`.
   - تحديث `purchase_order_items.received_quantity` تراكميًا داخل المعاملة بقفل الصف، والرفض إن تجاوز المستلم (ok + damaged) المطلوب + سماحية (الافتراضي 0%، §E-5). الزيادة تُسجَّل `over` وتنتظر المدير ولا تدخل المخزون.
   - التحويل لفاتورة مرة واحدة لكل استلام (`posted_ref_id` + فحص `convertedToInvoiceId` القائم).
3. **أثر الاستلام المحاسبي (الافتراضي R-A، §E-2):** الاستلام من الجوال **لا يرحّل مخزونًا ولا ذمة**. يسجّل الكميات الفعلية والدفعة والتاريخ والموقع، ويحدّث `received_quantity`. المحاسب على سطح المكتب يضغط «تحويل الاستلام لفاتورة» فتستدعي دالة جديدة `convertPOReceiptToInvoice(receiptDocId, userId)` الدالة `createPurchaseInvoice` **بالكميات المقبولة** مع batch/expiry ثم put-away. النتيجة: مخزون + ذمة مرة واحدة عبر الخط الحالي. الـ`damaged` لا يدخل المخزون الصالح (يُرد للمورد أو يُعدم بسند `voucher_damage` معتمد). البديل R-B (GRNI، المخزون عند الاستلام) يمسّ `purchase_dao.dart` الـratcheted ويحتاج توقيع المحاسب، فهو مؤجَّل.
4. **التحويل المرحلي:**
   - **dispatch:** خصم المصدر + قيد Dr `goods_in_transit` / Cr `inventory` بنفس منطق `transferStock`، والحالة `in_transit`.
   - **receive:** إضافة الوجهة + Dr `inventory` / Cr `goods_in_transit` بالكمية المستلمة.
   - **الفرق:**
     - `short`: يبقى في `in_transit` حتى قرار المدير، إما «إعادة للمصدر» (قيد عكسي) أو «فقد» (`adjustStock(type:'loss')` على حساب `inventory_shrinkage`).
     - `damaged`: يُستلم ثم يُعدم بسند `damage` معتمد.
     - `over`: مرفوض آليًا ويحتاج تحويلًا جديدًا.
   - تكلفة الوحدة **تُجمَّد عند dispatch** (متوسط المصدر) وتُخزَّن على السطر، فلا تُعاد قراءتها عند receive.
   - **يحتاج توقيع المحاسب (§E-3).** `transferStock` القديم يبقى لسطح المكتب.
5. **الجرد المتزامن:** مهمة جرد نشطة واحدة لكل (مخزن، صنف). الخادم يرفض إنشاء مهمة متداخلة. الحركات أثناء الجرد مسموحة. شاشة المدير تعرض «حركات منذ العدّ» لكل صنف (من `stock_movements` بعد `observed_at`)، وأي حركة ⇒ شارة «يُنصح بإعادة العد». الاعتماد يستعمل سلوك `finalizeCycleCountTask` القائم (المعدود − الرصيد الحالي) — **قرار المالك E-6**.
6. **الفصل بين الأدوار:** المعتمِد ≠ أي عدّاد للمهمة، ≠ منشئ المستند، ويُفحص على الخادم. «مدير النظام» لا يتجاوز ذلك (على نهج `criticalFinancialOps`).
7. **الإصدارات والتعارض:** كل أمر يحمل `expectedVersion` (= `wh_mobile_docs.row_version`)، والاختلاف ⇒ `409 stale`. نفس `command_id` بجسم مختلف (sha256 لـcanonical JSON من `picpos_api_client/canonical_json`) ⇒ `409 idempotency_conflict`. المرفوض يبقى `rejected` في outbox الجهاز ولا يُعاد بهوية جديدة.
8. **الفترات المغلقة:** `adjustStock` يرفضها أصلًا (:184-194)، ويُترجم الخطأ إلى `period_closed`.
9. **الدفعات:** صنف `trackExpiry` في الاستلام يتطلب `batch_number` + `expiry_date`. الإصدار من مستند جوال يفشل مغلقًا عند نقص تغطية دفعة صالحة (غير منتهية) بدل قبول نتيجة `consumeBatchesForIssue` الفارغة. هذا فحص مسبق في منفّذ المستند، **لا تعديل** في `inventory_batch_dao.dart`.
10. **التدقيق:** كل انتقال حالة يكتب `wh_mobile_doc_events` + `ActivityLogger.log(entityType:'wh_mobile_doc')` بالمستخدم والجهاز والموقع والدفعة.

### B.3 — تجربة الاستخدام (الشاشات)
**الأدوار:** أربعة حسب قرار المالك 3، والتفصيل في §B.4.

- عمود «clerk» في الجدول أدناه يشمل الموظف ومسؤول المخزن.
- عمود «manager» يشمل المشرف والمدير.
- الفرق بين مسؤول المخزن والموظف: التحويل والسندات.
- الفرق بين المشرف والمدير: التكلفة والنطاق.

[مُستبدَل 2026-10-23: النص السابق «أمين مخزن / مدير مخزن» بدورين فقط.]

| الشاشة | clerk | manager | ملاحظات |
|---|---|---|---|
| الإقران/الدخول | مسح QR ← اسم الخادم والبصمة ← دخول ← PIN محلي | نفسه | أخطاء صريحة (`url_not_allowed`، كود منتهٍ، بصمة مختلفة) وزر إلغاء |
| الرئيسية/المهام | بطاقات: استلامات PO المفتوحة، تحويلات واردة، مهام جرد مسندة، مسوداتي | + «بانتظار اعتمادي» بعدّاد | شريط علوي: المخزن الحالي (مبدِّل إن تعدّد) + `ConnectionChip` + آخر مزامنة (`AsOfBadge`) |
| مسح/بحث صنف | مسح ← بطاقة الصنف: الوحدات والباركودات والرصيد لكل موقع ودفعة/انتهاء وآخر الحركات | نفسه + التكلفة لمن يملك `products_cost_view` | **محجوب الرصيد** أثناء مهمة جرد نشطة على نطاقه (ADR-MC3) |
| بحث موقع | مسح `BIN-…` ← محتويات الموقع | + نقل بين مواقع | |
| استلام PO | اختيار PO (أو مسح رقمه) ← مسح صنف ← كمية (keypad كبير) ← دفعة/انتهاء إن لزم ← حالة (سليم/تالف) ← موقع ← مراجعة ← إرسال | + حلّ الزيادة/النقص | تقدّم لكل سطر «المستلم/المطلوب» |
| تحويل | طلب (من→إلى، أسطر) ← إرسال للاعتماد؛ dispatch: قائمة انتقاء FEFO بالموقع والدفعة ← مسح للتأكيد؛ receive: مسح ← فروقات | اعتماد الطلب، حلّ الفروقات، override الدفعة مع سبب | الاستبدال الصامت للدفعة مرفوض |
| جرد | المهمة ← مسح موقع ← مسح صنف/دفعة ← كمية ← «أسطري» ← إرسال | مراجعة: المتوقع/المعدود/الفرق/حركات منذ العدّ ← إعادة عدّ/اعتماد | لا أرقام متوقعة عند العدّاد |
| سندات | إدخال/إخراج/تالف بسبب إلزامي ← إرسال | اعتماد/رفض بسبب | |
| الاعتمادات | — | صندوق موحّد بالنوع والعمر | |
| Outbox/المزامنة | قائمة pending/accepted/rejected، «أعد المحاولة»، تفاصيل الرفض | نفسه | شريط offline دائم أعلى كل الشاشات عند الانقطاع |
| الإعدادات | اللغة، الثيم، الطابعة، ملف الماسح، اختبار المسح، فك الإقران (بعد تفريغ outbox) | نفسه | |

**الإرغونوميا:**
- scan-first: حقل مسح مركّز دائمًا، ولوحة المفاتيح الناعمة مطفأة حتى يطلبها المستخدم.
- أهداف ≥ 56dp للأفعال الأساسية و≥ 48dp للباقي.
- keypad رقمي كبير مع ±.
- نجاح = اهتزاز قصير + نغمة + نص أخضر؛ خطأ = اهتزاز مزدوج + نص.
- اتجاه RTL، والأرقام والأكواد LTR (`AmountText`/`ltrIsolate`).
- Material 3 light/dark من `picpos_ui`. الأحجام: هاتف 411×891، وhandheld 480×800 (عمود واحد، شريط فعل سفلي ثابت)، وtablet 1280×800 (لوحتان).

**Wireframe (handheld 480×800، RTL):**
```
┌──────────────────────────────┐
│ مخزن الرئيسي ▾   ● متصل  12:04│
├──────────────────────────────┤
│ استلام أمر شراء PO-0042      │
│ الموقع: A-03-2  [تغيير]      │
│ ┌──────────────────────────┐ │
│ │ ▌ امسح صنفًا…             │ │  ← تركيز دائم
│ └──────────────────────────┘ │
│ حليب 1ل  ·  6/12 كرتونة      │
│ دفعة: L2310  انتهاء 2027-01  │
│ ┌────┬────┬────┐             │
│ │ 7  │ 8  │ 9  │  الكمية: 6   │
│ │ 4  │ 5  │ 6  │  [سليم|تالف] │
│ │ 1  │ 2  │ 3  │             │
│ │ ±  │ 0  │ ⌫  │             │
│ └────┴────┴────┘             │
├──────────────────────────────┤
│ [ إلغاء ]        [ تأكيد ✓ ] │
└──────────────────────────────┘
```

### B.4 — نموذج الصلاحيات: إقران الأجهزة وأدوار المخازن (قرار المالك 3، 2026-10-23)

**الوضع الحالي [مقروء 2026-10-23]:**
- إقران الأجهزة وإلغاؤه في PicPos يتم من الإعدادات › «ربط التطبيقات والأجهزة» (`lib/presentation/settings_picpos/screens/linked_devices_section.dart:54-86`).
  - القسم يُظهر الإجراءات فقط لمن يحمل العلامة `system_admin` (دور «مدير النظام») أو `*`؛ غيره يرى «للعرض فقط — ربط الأجهزة وإلغاؤه لمدير النظام وحده».
  - زر «إقران جهاز» في حوار وضع الشبكة (`network_mode_settings_picpos.dart:306`) لا يُفتح في PicPos إلا من هذا القسم.
- **لا يوجد كود صلاحية مخصّص للإقران**، والفحص في الواجهة فقط.
  - `issuePairingCode({...})` (`lan_pairing_service.dart:93`) و`revoke(String deviceId)` (`:503`) لا تفحصان الفاعل **[مقروء]**: لا معامل للمستخدم، ولا ذكر لأي صلاحية في الملف (grep).
  - `/api/pair` يستهلك الرمز دون هوية مستخدم، وهذا صحيح بالتصميم: الرمز نفسه هو التفويض.

**المطلوب:**
1. **صلاحية جديدة `devices_pair_manage`** «ربط وإقران الأجهزة وإلغاء ربطها»، في فئة «الربط والأجهزة».
   - **تحرس:** إصدار أي رمز إقران LAN لأي `deviceKind` (`admin|pos|warehouse`)، وإلغاء جهاز (revoke، ويتبعه wipe على `warehouse`)، وعرض قائمة الأجهزة المقرونة بتفاصيلها.
   - **موضع الإنفاذ:**
     - **طبقة الخدمة:** `issuePairingCode(..., actorUserId)` و`revoke(deviceId, actorUserId)` ترفضان من لا يحمل الكود (نمط `PermissionEnforcer`)، والواجهة تعكس ذلك فقط. هذا تجنّبًا لنمط AUTHZ-010 (حراسة الواجهة فقط).
     - يُستبدل فحص `_isAdmin` في `linked_devices_section.dart` بـ`hasPermissionWithAdminBypass(perms, 'devices_pair_manage')`.
   - **المانحون افتراضيًا:** «مدير النظام» (عبر تجاوز المدير ومنحة صريحة في المصفوفة). يمنحه المالك لدور «المدير المسؤول عن ربط وإقران الأجهزة» أيًّا كان. ليس من `criticalFinancialOps`. **لا يُمنح لأدوار المخازن الأربعة.**
   - **الرمز مقيَّد:** رمز الإقران يُصدَر لنوع `warehouse` **وفرع محدد** يختاره المُصدِر، والجهاز لا يختار فرعه (نمط `issuePairingCode({branchId})` في خطة الإعداد P6).
   - **تدقيق:** كل إصدار وإلغاء يُكتب في `ActivityLogs` بالفاعل والنوع والفرع ومعرّف الجهاز.
   - **إقران الجهاز ≠ صلاحية المستخدم:** الموظف يدخل من الهاتف بحسابه (`POST /api/auth/session`)، وأفعاله تحكمها صلاحيات دوره ونطاق المخازن (ADR-W4). الإقران وحده لا يمنح أي صلاحية بيانات.
   - **البديل (قرار E-12):** كود منفصل لكل نوع جهاز، مثل `devices_pair_warehouse`.
2. **الأدوار الأربعة ← أدوار النظام** (المنح في `role_grant_matrix.dart`؛ الأكواد الأربعة الجديدة من A.5/W1: `warehouse_mobile_access`، `goods_receipt_mobile`، `stock_count_submit`، `stock_adjust_approve`):

| الدور (قرار المالك) | دور النظام | الأكواد على تطبيق المخازن | ملاحظات |
|---|---|---|---|
| **الموظف** (عدّاد/مستلم) | **جديد** «موظف مخزن» | `warehouse_mobile_access`، `stock_count_submit`، `goods_receipt_mobile`، `inventory_view` | لا تحويل، ولا سندات، ولا اعتماد، ولا تكلفة. يرى «مهامي» فقط. الكميات محجوبة أثناء جرد مسند (ADR-MC3) |
| **مسؤول المخزن** | القائم «مخزني» (`role_grant_matrix.dart:203`) + الأكواد الجديدة | ما سبق + `inventory_transfer` (طلب/dispatch/receive) + إنشاء السندات (`inventory_edit`، قائم) | الدور القائم يحمل `products_cost_view` اليوم، فيرى التكلفة في بطاقة الصنف كما على سطح المكتب (لا تغيير في السلوك القائم) |
| **المشرف** | **جديد** «مشرف مخزن» | ما سبق + `stock_adjust_approve` (اعتماد الجرد والسندات والفروقات وطلبات التحويل ضمن نطاقه) | الفصل بين الأدوار يبقى إلزاميًا (§B.2-6): لا يعتمد ما عدّه أو أنشأه |
| **المدير** | القائم «مدير مخزون» (`role_grant_matrix.dart:426`) + الأكواد الأربعة | كل ما سبق + `products_cost_view` (قائم) + «بانتظار اعتمادي» لكل المخازن في نطاقه | يمكن للمالك منح `warehouse_mobile_access` لـ«مدير فرع» للاطلاع فقط |

   - **[استنتاج] كلفة الدورين الجديدين:**
     - الدوران يحتاجان صفّي بذرة. `database_seeder_permissions.dart` على سقف الـbaseline (62,492)، فإمّا ملف بذرة جديد يُستدعى بسطر مع تعويض بايتات، أو إنشاء الدورين عبر مسار `grantMissingDefaults()` إن كان ينشئ الأدوار الناقصة (يتحقق المنفّذ).
     - يُحدَّث `picpos_permission_parity_test`.
     - **البديل (E-13):** بلا أدوار جديدة؛ الموظف ومسؤول المخزن = «مخزني»، والمشرف والمدير = «مدير مخزون»، ويخصّص المالك يدويًا.
3. **حماية الحساب على الهاتف:** يجب ألا تبقى جلسة موظف موقوف أو هاتف مفقود صالحة 30 يومًا. لذلك البنود G-4 (SEC-003) وG-7 (SEC-002) حاكمة قبل أي إقران، وفك الإقران من سطح المكتب يُبطل الجهاز ويمسح بياناته (موجود: `device_revoked` ⇒ wipe).

---

## C. خطة التنفيذ المرحلية

**الترتيب:** W0 ← W1 ← (W2 ∥ W3-desktop-prep) ← W3 ← W4 ← W5 ← W6. **ترحيل واحد** (W2) برقم = `schemaVersion` الفعلي + 1 وقت التنفيذ. خطة 2026-10-18 تحجز v197/v198 في رأس `epoch_3_v196_v205.dart:5-6`، فإن لم تُدمجا بعد يأخذ المنفّذ أول رقم بعدهما **بعد تنسيق** (§E-8)، ويحدّث تعليق الرأس.

**قواعد عامة:**
- نصوص سطح المكتب `tr('…')` + `assets/i18n/en.json` (`i18n_coverage_test`).
- نصوص التطبيق `t('key')` في `mobile_warehouse/lib/l10n/strings.dart` (`L10nTable`).
- ألوان من الثيم فقط.
- ملفات `lib/` الجديدة ≤ 30KB.
- **ملفات ratcheted ممنوع نموّها:** `permission_codes.dart` (93,670)، و`database_seeder_permissions.dart` (62,492)، و`inventory_dao.dart` (80,300)، و`purchase_dao.dart` (40,738)، و`database.dart` (40,837؛ الحالي 40,836)، و`purchase_orders_screen.dart`، و`api_purchase_handler.dart`، و`linked_devices_section.dart` (36,695). أي إضافة تذهب إلى **ملف جديد** (`part`/extension)، ويُعوَّض كل سطر `part`/spread بحذف مكافئ.
- المسارات الجديدة تُسجَّل في ملف أجزاء جديد `lib/services/api/routes/api_routes_m1_wh.dart` يُستدعى من `api_handler.dart` (7,963 بايت، عتبة CI 8,200، فالإضافة سطر واحد)، و`test/golden/api_routes.txt` يُحدَّث بنفس ترتيب التسجيل.

### W0 — الأساس: هيكل التطبيق والحزم وCI (4 أيام، تسلسلي)

**بنود حاكمة (gating) — أُضيفت 2026-10-23 من المراجعة.** يبدأ هيكل التطبيق بالتوازي معها، لكن:
- **لا تُعدّ W0 منجزة** قبل G-1 وG-2.
- **لا يبدأ W1** (الإقران) قبل G-3…G-7.
- **لا يُقرن أي هاتف موظف** قبل اكتمال G-1…G-7.

البنود تُنفَّذ في Specs خارطة المعالجة (SPEC-02/10/11)، وليست ضمن أيام W0.

| # | البند | المصدر | معيار القبول |
|---|---|---|---|
| G-1 | **توقيع Android يفشل مغلقًا** في التطبيقات الثلاثة القائمة وفي `mobile_warehouse` (نمط `mobile_admin` `validateReleaseSigning`)؛ `mobile/` يوقّع اليوم دائمًا بمفتاح debug و`mobile_pos/` يرجع إليه | REL-004 | `flutter build apk --release` يفشل بلا `key.properties` في كل تطبيق؛ `apksigner verify --print-certs` يُظهر شهادة الإصدار؛ المفتاح خارج الريبو مع نسخة احتياطية موثّقة |
| G-2 | **بناء APK في CI** لكل تطبيق، يفشل على توقيع debug، ويشمل **فحص العلامة** على الـAPK (لا نصوص أو صور لعلامة أخرى — قرار المالك 1) | ARCH-006، BRAND-012، UX-011(3)(4) | Job في `ci.yml` أخضر، وحالة توقيع أو علامة مكسورة عمدًا تُفشله |
| G-3 | **تحصين الإقران:** لا نافذة bearer قديمة مشتركة على تثبيت جديد بلا أجهزة قديمة، ومقارنة ثابتة الزمن (SEC-006)؛ TLS مفعّل مع بصمة `fp` في حمولة QR v2 من P7، ورفض cleartext في release (SEC-007، قرار F.5) | SEC-006، SEC-007، P7-A/B | `legacyAllowed()` = false على تثبيت جديد؛ هاتف مقرون يخزّن بصمة؛ اتصال ببصمة مختلفة مرفوض |
| G-4 | **إبطال الجلسات:** `iat` + «صالح بعد» لكل مستخدم يُرفع عند التعطيل/القفل/تغيير كلمة المرور/الخروج؛ `requirePermission` يفحص `is_active`/`is_locked` | SEC-003 | تعطيل أو قفل أو تغيير كلمة ⇒ التوكن القديم 401 |
| G-5 | **القراءات غير الموثّقة على LAN:** أرصدة الأطراف و`accounts`/`users` لا تُخدم بلا جلسة، و`GET /api/parties` بنطاق الفرع؛ أو على الأقل سياسة ADR-W3 (حصر مسارات جهاز `warehouse`) مفروضة ومختبرة **قبل** أول إقران مخازن | SEC-008 | سحب `parties` بلا توكن لا يحوي `balance`؛ جهاز `warehouse` يُرفض على `/api/sync/pull` و`/api/parties` |
| G-6 | **صلاحية الإقران** `devices_pair_manage` مفروضة في طبقة الخدمة (§B.4) | قرار المالك 3، AUTHZ-010 | مستخدم بلا الكود لا يُصدر رمزًا ولا يُلغي جهازًا حتى عبر استدعاء الخدمة مباشرة (اختبار وحدة) |
| G-7 | **تغيير كلمة المرور الإجباري على الـAPI:** حسابات الموظفين تُنشأ بكلمة أولية، و`POST /api/auth/session` يصدر اليوم جلسة دون فرض التغيير | SEC-002 | مستخدم عليه `force_password_change` يُرفض أو يحصل على جلسة «تغيير كلمة المرور فقط» |

- **الهدف:** تطبيق `mobile_warehouse/` يقلع offline بغلاف وثيم ولغتين وماسح وoutbox مشفّر، ويدخل CI.
- **ملفات جديدة:**
  - `mobile_warehouse/pubspec.yaml`: الاسم `picpos_warehouse`؛ path deps على `picpos_api_client` و`picpos_device` و`picpos_ui` و`picpos_rules`؛ و`mobile_scanner` بنفس إصدار Van (`^7.4.2`)؛ وdev كما `mobile_pos`.
  - `android/app/build.gradle.kts`: `applicationId "com.picpos.warehouse"`، و`minSdk ≥ 24`، و**توقيع يفشل مغلقًا** بنسخ `mobile_admin/android/app/build.gradle.kts:10-34,87` لا `mobile_pos`.
  - `AndroidManifest`: INTERNET، ACCESS_NETWORK_STATE، CAMERA، VIBRATE، BLUETOOTH_CONNECT/SCAN، و`network_security_config` (debug فقط cleartext).
  - `lib/main.dart`, `lib/app.dart` (نمط `mobile_pos/lib/app.dart:21-46`).
  - `lib/shell/warehouse_shell.dart` (`PicPosAdaptiveScaffold`: المهام، المسح، المستندات، Outbox، الإعدادات).
  - `lib/screens/{onboarding,home,lookup,documents,outbox,settings}_page.dart` (placeholders مسمّاة).
  - `lib/l10n/strings.dart`.
  - `lib/widgets/{scan_field,qty_keypad,offline_banner,scan_feedback}.dart`.
  - `lib/scan/camera_scan_view.dart` (`MobileScanner`).
  - `lib/store/wh_local_store.dart`: `SqlCipherLocalStore.open(fileName:'picpos_warehouse_enc.db')` + `DatabaseKey`.
  - README.
- **الحزم:**
  - `packages/picpos_device/lib/src/scan/scan_event.dart`: `ScanEvent`, `ScanSource`, `ScanDeduper`, `WedgeScanSource`، مع تصديرها في `picpos_device.dart`. لا تغيير في سلوك `KeyboardWedgeBuffer`.
  - `packages/picpos_ui/lib/src/widgets/offline_banner.dart` (اختياري هنا، أو يبقى في التطبيق إلى أن يحتاجه تطبيق ثانٍ — الافتراضي: في التطبيق).
- **الاختبارات:**
  - `mobile_warehouse/test/structural_test.dart`: نسخ `mobile_pos/test/structural_test.dart`، **+ حارس حجم** (لا ملف `lib/**.dart` > 30KB).
  - `test/support.dart` (الخطوط وأحجام phone/tablet **+ handheld 480×800**).
  - `test/golden_test.dart`: home × AR/EN × light/dark × phone/handheld/tablet = 12 صورة، تُولَّد على Windows كما ينص `ci.yml:349-350`.
  - `test/shell_test.dart`.
  - `test/scan_test.dart`: dedup وwedge→event وتطبيع.
  - `packages/picpos_device/test/scan_event_test.dart`.
  - `test/e2e/warehouse_app_e2e_test.dart`: هيكل مع `skip` للمراحل اللاحقة.
- **CI/أدوات:**
  - `ci.yml`: عنصر مصفوفة `- dir: mobile_warehouse / tool: flutter` بعد :366، وسطر `run_suite mobile_warehouse mobile_warehouse flutter test test/e2e` بعد :544.
  - `tool/run_e2e.ps1`: سطر في `$suites` بعد :131 وتحديث تعليق الترتيب :6.
  - `docs/testing/E2E.md`: :24,31 وجدول العدّ :84-86.
  - أيقونة عبر `tool/mobile_icons/` إن كان النمط موجودًا [استنتاج].
- **القبول:**
  - `cd mobile_warehouse; flutter analyze; flutter test` أخضر، والـgoldens الـ12 مولَّدة.
  - APK debug يقلع offline ويقرأ مسح الكاميرا وwedge (USB/BT HID) حدثًا واحدًا لكل مسح (يدوي على جهاز).
  - **و(2026-10-23):** G-1 وG-2 مستوفيان، أي APK release موقَّع من CI ويمرّ فحص العلامة.
- **الحجم:** ≈ 25 ملفًا جديدًا. **المخاطر:** اختلاف goldens بين Windows وLinux، والحل توليدها على Windows كما الشقيقين. **التوازي:** لا (الأساس).

### W1 — الإقران والدخول والنطاق ونقاط القراءة (6.5–7 أيام؛ نطاقان متوازيان؛ شرط البدء: G-3…G-7)
- **W1-desktop:**
  - `lan_pairing_api_handler.dart:51`: قبول `'warehouse'`. `lan_pairing_service.dart` (25.9KB، غير ratcheted، وهامشه ≈ 4.8KB): `warehouse` يتطلب `branchId` مثل `pos` (:153)، لكن بلا terminal code.
  - جديد `lib/services/api/lan_device_route_policy.dart` (ADR-W3) + سطر في `api_auth_middleware.dart` (14.6KB).
  - جديد `GET /api/m1/info` (عام: `{serverId, apiLevel:1, tls, companyName}` مطابق لـ`LanInfo`، `transport.dart:96-129`). إن أنجز P7-A هذا المسار فلا تكرار.
  - جديد `lib/services/api/m1_wh/` بالملفات: `wh_scope.dart` (ADR-W4)، `wh_errors.dart` (رموز §A.1)، `wh_dto.dart` (DTOs منفصلة: `CounterTaskDto` **بلا** expected، و`ManagerCountReviewDto`)، `wh_read_handlers.dart`.
  - مسارات القراءة:
    - `GET /api/m1/wh/bootstrap` (المستخدم والصلاحيات والمخازن المسموحة وإعداد المواقع والقواميس).
    - `GET /api/m1/wh/pull?entity=products|barcodes|units|locations|batches|stock&cursor=` (keyset على `last_modified_at`؛ و`stock` على `inventory_balances.lastUpdated` لأنه بلا globalId/rowVersion [مقروء A.3]؛ بحد 500).
    - `GET /api/m1/wh/items/{globalId}` و`GET /api/m1/wh/movements?item=&cursor=` (`inventory_view`).
    - `GET /api/m1/wh/locations/by-barcode/{code}` (DAO جديد `daos/warehouse_location_lookup.dart`، `part` في `database.dart` مع تعويض بايتات §C).
  - **حجب الجرد:** دالة `isUnderActiveCount(user, warehouse, product)` مستعملة في items/pull/stock. تعيد البيانات بلا كميات للعدّاد المسند.
  - **الصلاحيات:** ملف جديد `lib/core/permissions/warehouse_mobile_permission_codes.dart` بالثوابت الأربعة وقائمة `warehouseMobilePermissionEntries` (code/name/category=`warehouse_mobile`). سطر spread واحد في `PermissionCodes.masterList` (`permission_codes.dart:1108`) ومفتاح في `categoryNames` (:1775)، **مع حذف تعليقات مكافئة** في نفس الملف حتى يبقى ≤ 93,670. الأدوار في `role_grant_matrix.dart` (25.8KB، هامش ≈ 4.9KB) **حسب §B.4** (مُستبدَل 2026-10-23؛ كان النص «`'مخزني'` يأخذ access+receipt+count، و`'مدير مخزون'` يأخذ الأربعة»):
    - «موظف مخزن» (جديد): access + count + receipt.
    - «مخزني»: access + receipt + count + `inventory_transfer`.
    - «مشرف مخزن» (جديد): ما سبق + `stock_adjust_approve`.
    - «مدير مخزون»: الأربعة.
    - **و`devices_pair_manage`** لـ«مدير النظام» فقط افتراضيًا، في ملف ثوابت جديد بنفس تقنية الـspread، مع تعويض البايتات. البذر يمرّ عبر `syncAllPermissions()` من `masterList` [مقروء: تعليق :1106-1107]؛ ولا تعديل في `database_seeder_permissions.dart` إلا إن أثبت المنفّذ الحاجة (مع تعويض).
  - **واجهة سطح المكتب:** خيار «جهاز مخازن» في نوع الجهاز، مع **منتقي فرع إلزامي**. يُضاف في لوحة P7-A (`mobile_pairing_qr_panel.dart`) إن وُجدت، وإلا في `lan_pairing_dialog.dart` (5.9KB) مع `QrImageView` للـpayload v2.
    - يظهر الخيار ويعمل فقط لمن يحمل `devices_pair_manage`، والخدمة ترفض غيره (G-6).
    - قائمة الأجهزة المقرونة تعرض نوع `warehouse` والفرع وآخر ظهور، مع «إلغاء الربط» (wipe).
- **W1-packages/app:**
  - جديد `packages/picpos_api_client/lib/src/pairing_payload.dart` (v1/v2، `isExpired`، `kind`) — **مشترك مع P7-B**، فمن يصل أولًا ينشئه والآخر يعيد استعماله.
  - جديد `packages/picpos_api_client/lib/src/wh_client.dart`: `WarehouseLanClient` (pair, session, bootstrap, pull, item, movements, locationByBarcode, لاحقًا أوامر المستندات)، **يحقن دائمًا `x-idempotency-key` = commandId** في الأوامر. و`lib/src/wh_contracts.dart` (المسارات وDTOs).
  - **TLS pinning:** `PinnedHttpClient(fpSha256)` في `lib/src/pinned_client.dart` بـ`badCertificateCallback` يقارن sha256 الشهادة بـ`fp` (TOFU). هذا مقبول في الحزمة لأن `dart:io` متاح لـDart خالص على الأجهزة [استنتاج].
  - في التطبيق: `lib/session/wh_session.dart` (نمط `admin_session.dart`: `KeystoreSecretStore`، deviceId عشوائي، token، sessionToken، PIN verifier PBKDF2، wipe عند `device_revoked`)، و`lib/session/app_lock.dart` (نسخ نمط `mobile_admin/lib/app_lock.dart`)، و`screens/onboarding_page.dart` (مسح QR بالكاميرا + إدخال يدوي + عرض البصمة + إلغاء)، و`lib/sync/wh_sync.dart` (bootstrap + pull إلى `entities` المحلية).
- **DB:** لا ترحيل (`lan_paired_devices.device_kind` نصي).
- **الاختبارات:**
  - الجذر: `test/unit/lan_pairing_warehouse_kind_test.dart`، `test/unit/device_pairing_permission_test.dart` (2026-10-23: إصدار وإلغاء بلا `devices_pair_manage` ⇒ مرفوض في الخدمة؛ الرمز مقيَّد بالنوع والفرع؛ تدقيق مكتوب)، `test/unit/warehouse_role_grants_test.dart` (الأدوار الأربعة تحمل أكواد §B.4 بالضبط ولا تحمل `devices_pair_manage`)، `test/unit/lan_device_route_policy_test.dart` (جهاز warehouse يُرفض على `/api/sales` ويُقبل على `/api/m1/wh/bootstrap`)، `test/integration/m1_wh_read_scope_test.dart` (مستخدم بمخزن واحد لا يرى الآخر، وجهاز فرع A لا يرى مخازن فرع B، وعدّاد أثناء جرد نشط لا يرى الكمية)، و`test/unit/api_routes_golden_test.dart` (تحديث الملف)، و`test/unit/api_handler_perm_gate_grep_test.dart`.
  - **e2e جذري حقيقي** `test/e2e/warehouse_lan_e2e_test.dart`: `ApiHandler` + الـmiddleware على `AppDatabase` في الذاكرة مخدومًا بـ`shelf_io` على loopback، و`WarehouseLanClient` الحقيقي يقرن ويدخل ويسحب. يُضاف إلى `run_e2e.ps1` كجزء من suite `root` القائمة.
  - الحزمة: `pairing_payload_test.dart`, `wh_client_test.dart` (fake transport)، `pinned_client_test.dart`.
  - التطبيق: `onboarding_flow_test.dart`, `app_lock_test.dart`، وgoldens للإقران.
- **القبول:** QR من سطح المكتب ⇒ الهاتف يقترن ويدخل ويعرض المخازن المسموحة فقط. جهاز المخازن يُرفض على أي مسار خارج القائمة. فك الإقران من سطح المكتب ⇒ wipe على الجهاز.
- **المخاطر:**
  - `permission_codes.dart` على السقف: إن تعذّر التعويض يُنقل `categoryNames` الخاص بالفئة الجديدة إلى الملف الجديد مع دمج map.
  - نشر TLS: ما لم يُفعَّل TLS على الخادم يرفض release الاتصال بقصد (قرار F.5). **يحتاج دليل تشغيل** لإنشاء شهادة ذاتية (W6).
- **التوازي:** W1-desktop ∥ W1-packages/app (العقد في `wh_contracts.dart` يُكتب أولًا كـspec مشترك).

### W2 — الترحيل + البحث + استلام PO (8 أيام)
- **DB (الترحيل الوحيد، vN):**
  - جديد `lib/data/database/wh_mobile_docs_schema.dart` (`part of 'database.dart'`، raw SQL لـSQLite/PG على نمط `warehouse_locations_schema.dart`): الجداول الثلاثة في ADR-W5، وفهارس `(kind,state,warehouse_id)` و`(ref_type,ref_id)`، و`UNIQUE(global_id)` و`UNIQUE(command_id)`.
  - الكتلة `if (from < N) await _safeMigrate('vN wh mobile docs', ensureWhMobileDocsSchema);` في `epoch_3_v196_v205.dart`، و`ensureWhMobileDocsSchema()` أيضًا في `database_startup.dart` كطبقة دفاع (نمط :45)، وسطر في `database_schema_history.dart`.
  - **المزامنة:** الجداول تُكتب على الخادم فقط وتُسحب إلى عملاء سطح المكتب، فتُضاف إلى `pullTables` (`delta_pull_service.dart`) و`_syncPullTables` (`api_sync_pull_tables.dart`) و`_syncHardenedTables` و`id_namespace_service.dart` ونظير PG. المنفّذ يتبع حراس §3.3.6. البديل «محلي عمدًا» مرفوض لأن صندوق الاعتماد يحتاجه أي سطح مكتب عميل.
  - **`database.dart` على هامش بايت واحد:** سطرا `part` جديدان يُعوَّضان بحذف تعليق.
- **سطح المكتب (منطق):**
  - جديد `lib/data/database/daos/wh_mobile_docs_dao.dart` (`part`، extension): `createDoc`, `appendLines`, `transition(docGid, commandId, expectedVersion, action, actor, device, payloadHash)` بآلة حالات صريحة لكل kind، و`recordEvent`, `docsForApprover`.
  - جديد `daos/wh_po_receipt_dao.dart`: `submitPoReceipt` يحدّث `received_quantity` تراكميًا بقفل ويطبّق §B.2-2، و`convertPOReceiptToInvoice(receiptDocId, userId)` يستدعي `createPurchaseInvoice` بالكميات المقبولة مع batch/expiry وبـ`userId` الحقيقي (لا `defaultUser`)، ثم put-away (ADR-W6)، ثم يكتب `posted_ref`. يختم `convertedToInvoiceId` فقط إذا اكتمل الأمر، وإلا يضبط `status='partially_received'` إن كانت الحالة مسموحة في الواجهة (يتحقق المنفّذ من قيم status المعروفة).
- **API:**
  - `GET /api/m1/wh/po?warehouse=&status=open`، و`GET /api/m1/wh/po/{gid}` (الأسطر مع المطلوب/المستلم، **بلا تكلفة**).
  - `POST /api/m1/wh/po/{gid}/receipts` (إنشاء/إلحاق) و`POST /api/m1/wh/receipts/{gid}/submit` (`goods_receipt_mobile`).
  - في ملف جديد `m1_wh/wh_receipt_handlers.dart`.
- **سطح المكتب (واجهة):** شاشة جديدة «طلبات المخازن» `lib/presentation/warehouse_mobile_picpos/screens/warehouse_mobile_inbox_screen.dart` بتبويبات: استلامات بانتظار التحويل لفاتورة، اعتمادات، تحويلات في الطريق. زر «تحويل الاستلام لفاتورة» بصلاحية `purchases_create`. التسجيل حسب §3.2 (`AppScreen`, `ScreenId`, `screen_registry`, `ScreenConfig`، و`screenPermissionMap[warehouseMobileInbox]='warehouse_mobile_access'` بالشكل الحرفي، و`kAllNavItemDefs`). **لا توأم قديم** فلا فرع `Brand.isPicPos`، ويُتحقق من `picpos_screen_fork_guard`.
- **التطبيق:** `screens/lookup_page.dart` (صنف وموقع)، `screens/po_list_page.dart`, `screens/po_receive_page.dart`، `lib/outbox/wh_outbox_sender.dart` (يغلف `Outbox.drain` ويرسل `x-idempotency-key`)، `screens/outbox_page.dart`.
- **الاختبارات:**
  - `test/integration/vN_wh_mobile_docs_migration_test.dart` (من قاعدة v196، idempotent عند الإعادة).
  - `test/unit/wh_mobile_docs_dao_test.dart` (الانتقالات غير الشرعية، `stale`، `idempotency_conflict`).
  - `test/integration/wh_po_receipt_flow_test.dart`: استلام جزئي ثم كامل، ومخزون واحد + ذمة واحدة بعد التحويل، وإعادة الأمر نفسه لا تكرّر، وزيادة مرفوضة، وتالف لا يدخل المخزون الصالح، ودفعة/انتهاء على `ProductBatches`، والموقع بعد put-away، وتطابق `warehouseBinDiscrepancies()` = فارغ.
  - الـe2e الجذري يُمدَّد بالاستلام.
  - التطبيق: `po_receive_flow_test.dart` (fake client)، `outbox_drain_test.dart` (قتل/إعادة لا يكرّر)، وgoldens لشاشة الاستلام.
- **القبول:** أمين المخزن يستلم PO جزئيًا offline، فيظهر pending ثم accepted عند الاتصال. المحاسب يحوّل الاستلام لفاتورة فيدخل المخزون مرة واحدة بالكميات الفعلية والدفعات. لا قيد ولا مخزون قبل التحويل (R-A).
- **المخاطر:** `createPurchaseInvoice` بمعاملات كثيرة، فيُستدعى كما هو دون تعديل. حالة `partially_received` قد لا تدعمها الواجهات القائمة ⇒ عرض فقط.
- **التوازي:** W2-desktop (DAO/API/migration/inbox) ∥ W2-app (الشاشات ضد fake client من `wh_contracts`).

### W3 — التحويل المرحلي والسندات (8 أيام)
- **سطح المكتب:**
  - جديد `daos/staged_transfer_dao.dart` يستخرج من `transferStock` الدالتين `dispatchTransferLines(docId, lines, userId)` و`receiveTransferLines(docId, lines, userId)`، كلٌّ بطرفه وقيده عبر `goods_in_transit` كما في `inventory_transfers_dao.dart:193-234`، مع التكلفة المجمّدة (§B.2-4) و`carryTransferLots`. **`transferStock` نفسه لا يتغيّر.** المنفّذ يقرأ :123-239 كاملًا قبل الاستخراج، والاستخراج نسخ مع إعادة استعمال الدوال الخاصة إن أمكن دون تعديل الأصل.
  - اقتراح FEFO مقيّد بالموقع عبر `getBatchesForIssue` + `location_stock`.
  - حلّ الفروقات (`return_to_source|write_off_loss|accept_damaged_then_damage_voucher`).
  - جديد `daos/wh_voucher_dao.dart`: `in/out/damage` بعد الاعتماد عبر `adjustStock(type:'adjustment'|'damage')`، و`postAdjustmentJournal` الافتراضي يرحّل القيد (:371-377) بالفحص المسبق للسالب §B.2-1.
- **API:**
  - `POST /api/m1/wh/transfers` و`/{gid}/{approve|dispatch|receive|resolve}`.
  - `POST /api/m1/wh/vouchers` و`/{gid}/{approve|reject}`.
  - الصلاحيات حسب MC §5، والاعتماد `stock_adjust_approve` + فصل الأدوار.
- **التطبيق:** `screens/transfer_*_page.dart` (طلب، dispatch، receive، فروقات)، `screens/voucher_page.dart`، `screens/approvals_page.dart` (للمدير).
- **سطح المكتب واجهة:** تبويب «تحويلات في الطريق» + «اعتمادات» في الـinbox (يعتمد المدير من سطح المكتب أيضًا).
- **الاختبارات:**
  - `test/integration/staged_transfer_conservation_test.dart`: مجموع المخزنين + in-transit ثابت، وقيدا GIT متوازنان ويُصفَّى GIT عند الاستلام الكامل، وجزئي/نقص/تالف/زيادة، ودفعة منتهية مرفوضة، وفرعان مختلفان.
  - `test/integration/staged_transfer_vs_legacy_test.dart`: نفس الأسطر بالمسارين تعطي نفس الأرصدة والقيود النهائية.
  - `test/integration/wh_voucher_flow_test.dart` (سالب مرفوض رغم `enable_negative_sales=true`، والمعتمد ≠ المنشئ).
  - `test/unit/journal_balance_single_rule` يبقى أخضر.
  - e2e جذري: dispatch→receive عبر HTTP مع إعادة إرسال مكررة.
  - التطبيق: flows + goldens.
- **القبول:** طلب ← اعتماد ← dispatch بمسح ← receive بمسح على جهاز آخر ⇒ الأرصدة والقيود صحيحة، والفروقات تنتظر المدير.
- **المخاطر:** المحاسبة المرحلية تحتاج **توقيع المحاسب** (§E-3)، والتنفيذ خلف إعداد `wh_staged_transfers_enabled` (الافتراضي off حتى التوقيع). **التوازي:** desktop ∥ app.

### W4 — الجرد الأعمى (6 أيام)
- **سطح المكتب:**
  - جديد `daos/wh_count_dao.dart`:
    - `countTasksForCounter(user)` تعيد DTO بلا expected.
    - `appendCountEntries`.
    - `submitCountPass(taskId, pass, user)`: يجمع حسب الصنف، ويضيف أسطر الأصناف غير المتوقعة، ويستدعي `submitCount` (`cycle_count_dao.dart:237`)، ويحسب الحاجة لإعادة العد وفق العتبة دون إرجاعها للعدّاد.
    - `reviewForManager(taskId)`: المتوقع والمعدود والفرق وحركات منذ `observed_at`.
    - `approveCount(taskId, approver)`: يفحص الفصل ثم يستدعي `finalizeCycleCountTask` (:458) مرة واحدة.
  - منع المهام المتداخلة (§B.2-5).
- **API:** `GET /api/m1/wh/counts/tasks`، `POST /api/m1/wh/counts/{gid}/entries`، `POST /api/m1/wh/counts/{gid}/submit` (`stock_count_submit`)، `GET /api/m1/wh/counts/{gid}/review`، `POST /api/m1/wh/counts/{gid}/approve` (`stock_adjust_approve`).
- **التطبيق:** `screens/count_task_page.dart`, `screens/count_review_page.dart` (مدير). **تفريغ cache الأرصدة المحلية** للنطاق عند استلام مهمة جرد.
- **الاختبارات:**
  - `test/integration/wh_blind_count_leak_test.dart`: تسلسل كل استجابة وكل صف في pull وكل رسالة خطأ للعدّاد لا يحوي `expected|variance|system` لأي صنف في النطاق، ويشمل `/items` و`/pull?entity=stock`.
  - `test/integration/wh_count_finalize_test.dart`: العدّاد لا يعتمد، والعتبة تفرض pass 2، والإعادة تعطي حركة واحدة لكل سطر وقيدًا مجمّعًا واحدًا، ومواقع متعددة تُجمَّع.
  - التطبيق: flow + goldens.
- **القبول:** معايير M-C2 في `ARCHITECTURE-MC.md:103`. **التوازي:** desktop ∥ app.

### W5 — الاعتمادات والطباعة والصقل (6 أيام)
- **الطباعة:**
  - ملصقات صنف/موقع عبر `PrintService` + `ReceiptBarcode` (Code128) و`ReceiptQrCode` القائمين (raster، 58/80mm).
  - جديد `mobile_warehouse/lib/printing/label_builder.dart`.
  - ملصقات الطابعات المخصّصة (ZPL/TSPL) **خارج R1** إلا بقرار §E-10.
  - `GET /api/m1/wh/labels?kind=&ref=` (بيانات فقط).
  - فشل الطباعة لا يمسّ المخزون، ويُعاد من طابور `PrintService`.
- **العتاد:** `android/app/src/main/kotlin/.../ScanIntentPlugin.kt` (`BroadcastReceiver` لـDataWedge وHoneywell وUrovo) + `EventChannel` → `ScanEvent(source:intent)`، مع profiles في `lib/scan/scanner_profiles.dart` لكل موديل **مُجرَّب فعليًا** فقط.
- **الصقل:**
  - صندوق الاعتمادات بعدّادات.
  - مبدّل مخزن.
  - إنشاء مهمة جرد سريعة من المدير (موقع/فئة) عبر API جديد يستدعي `generateCycleCountTask`. **اختياري.**
  - إتاحة: `Semantics`، تنقّل لوحة مفاتيح للماسحات، اختبار عرض 480×800.
- **الاختبارات:** goldens لكل الشاشات بالأحجام الثلاثة، و`scanner_profiles_test.dart`، و`label_builder_test.dart` (الباركود يُقرأ عكسيًا بمكتبة `barcode`). **قائمة فحص يدوية** للعتاد في `docs/mobile/warehouse-hardware-checklist.md` (ملف جديد، يُكتب في W5 لا الآن).
- **التوازي:** printing ∥ hardware ∥ polish (ملفات منفصلة).

### W6 — التحصين والإصدار (4 أيام)
- التوقيع بمفتاح إنتاج (`key.properties` خارج الريبو، و`tool/check_no_secrets.ps1` يبقى أخضر).
- `--obfuscate --split-debug-info` وحجم APK (هدف < 30MB لكل ABI، قياس فعلي).
- R8/proguard لـ`mobile_scanner`.
- اختبار kill/replay وانقطاع Wi-Fi واختلاف الساعة.
- إبطال الجهاز والمستخدم.
- دليل تشغيل `docs/mobile/دليل_ربط_تطبيق_المخازن.md` (شهادة TLS الذاتية، والإقران، والأدوار).
- metadata المتجر (أيقونات، لقطات AR/EN، سياسة خصوصية الكاميرا).
- تحديث `ARCHITECTURE-MC.md` (ترويسة الحالة + تصحيح A.2) و`ARCHITECTURE-MAP.md` §1.1.
- **اختياري — server:** لا شيء في R1. وإن قرّر المالك المسار السحابي فهو مرحلة W7 مستقلة (relay وفق ADR-M2) خارج هذه الخطة.
- **القبول:** بناء release موقّع يعمل على هاتف + handheld + tablet فعلية، وقائمة الفحص اليدوية موقّعة من المالك، وكل suites الـe2e خضراء.

### جدول التوازي والنطاقات الحصرية
| عامل | المراحل | النطاق الحصري |
|---|---|---|
| WA (app) | W0 ثم W1-app ثم W2..W5-app | `mobile_warehouse/**`، `packages/picpos_device/lib/src/scan/**` |
| WB (client pkg) | W1-pkg ثم الأوامر في W2..W4 | `packages/picpos_api_client/lib/src/{wh_client,wh_contracts,pinned_client,pairing_payload}.dart` + اختباراتها |
| WC (desktop API) | W1-desktop ثم API في W2..W5 | `lib/services/api/m1_wh/**`، `routes/api_routes_m1_wh.dart`، `lan_device_route_policy.dart`، أسطر في `api_handler.dart`/`api_auth_middleware.dart`/`lan_pairing_*`، `test/golden/api_routes.txt` |
| WD (desktop data) | W2-DB ثم DAOs في W2..W4 (تسلسلي) | `wh_mobile_docs_schema.dart`، `daos/wh_*_dao.dart`، `daos/staged_transfer_dao.dart`، `daos/warehouse_location_lookup.dart`، `epoch_3_v196_v205.dart`، `database.dart` (أسطر part)، قوائم المزامنة |
| WE (desktop UI/perm) | W1-perm ثم inbox في W2/W3 | `core/permissions/warehouse_mobile_permission_codes.dart`، `permission_codes.dart` (سطران + تعويض)، `role_grant_matrix.dart`، `presentation/warehouse_mobile_picpos/**`، تسجيل الشاشة، `lan_pairing_dialog.dart` |
| WF (CI/docs) | W0 ثم W6 | `.github/workflows/ci.yml`، `tool/run_e2e.ps1`، `docs/testing/E2E.md`، `docs/mobile/**` |

**تعارضات معروفة:**
- WB وP7-B (خطة 2026-10-18) يتشاركان `pairing_payload.dart`.
- WE وP7-A يتشاركان لوحة الإقران.
- WD وP4/P6 يتشاركان `epoch_3_v196_v205.dart` و`database.dart`، فهي تسلسلية بالضرورة.
- WC وWD يتفقان على توقيعات الـDAO أولًا (stub يرمي `UnimplementedError` يكتبه WD).

---

## D. الحراس البنيوية التي يجب أن تبقى خضراء
- **الجذر:**
  - `test/structural/file_size_ratchet_test.dart`: الملفات الجديدة ≤ 30KB، ولا نموّ لـ`permission_codes.dart`/`database.dart`/`inventory_dao.dart`/`purchase_dao.dart`/`database_seeder_permissions.dart`/`linked_devices_section.dart`.
  - بوابة الأحجام في `ci.yml` (`api_handler.dart` ≤ 8,200، `database.dart`).
  - `test/unit/api_routes_golden_test.dart` + `api_handler_perm_gate_grep_test.dart`.
  - `migration_numbering_test`, `alter_table_sync_columns_guard_test`, `sync_coverage_guard_test`, `sync_column_membership_guard_test`, `pg_sync_hardened_tables_guard_test`, `unsynced_tables_have_no_writer_test`, `pg_schema_parity_static_test`.
  - `test/unit/permission_enforcement_coverage_test.dart` (كل كود جديد له موضع إنفاذ — مسارات `m1_wh` — ولا يدخل `knownUnenforced`)، و`test/structural/picpos_permission_parity_test.dart`، و`screen_permission_map_test`، و`allowed_screens_can_render_test` (الشكل الحرفي `ScreenId.x: 'code'`).
  - `picpos_screen_fork_guard_test`, `screenconfig_builds_the_picpos_fork_test`, `screen_tabs_are_wired_test`.
  - `i18n_coverage_test`, `dark_mode_guard_test`.
  - `journal_balance_single_rule`, `safe_balance_single_write`.
  - `web_entry_scope_test` (الـinbox لا يُستورد من مسار الويب).
  - `mirror_write_dispatch_test`/`no_bare_client_write_submit_test` (إن احتاج عميل سطح مكتب أن يعتمد عبر LAN، فتمرّ الكتابة بـ`ClientWriteInterceptor` في `cwi_*` جديد).
  - `lan_pairing_security_test`, `lan_pairing_test`.
- **التطبيق:** `mobile_warehouse/test/structural_test.dart` (ألوان + `t('key')` + حجم ≤ 30KB)، والـgoldens، و`flutter analyze`.
- **الحزم:** `packages/picpos_api_client` (`dart test`)، و`packages/picpos_device` (`flutter test`).
- **e2e:** `tool/run_e2e.ps1` كاملًا (server, packages, mobile, mobile_admin, mobile_pos, **mobile_warehouse**, root بما فيه `warehouse_lan_e2e_test.dart`, web).
- **الأمن:** `tool/check_no_secrets.ps1` (لا `key.properties`/`*.jks`).

---

## E. قرارات المالك المطلوبة (مع الافتراضي الموصى به)
1. **النقل في R1:** *الافتراضي: LAN فقط إلى سطح المكتب (+VPN للمخازن البعيدة)*. البديل: بناء relay سحابي (W7، ≈ 3–4 أسابيع إضافية لأنه غير موجود).
2. **أثر استلام PO:** *الافتراضي R-A: الجوال يسجّل الاستلام، والمخزون والذمة عند تحويل المحاسب لفاتورة بالكميات المستلمة.* البديل R-B: المخزون عند الاستلام مع حساب GRNI، ويحتاج تعديل خط الشراء وتوقيع المحاسب.
3. **التحويل المرحلي (in-transit):** *الافتراضي: نعم، بحساب `goods_in_transit` القائم، خلف إعداد off حتى توقيع المحاسب*. البديل: تحويل فوري واحد من الجوال (أبسط، بلا تتبّع الطريق).
4. **عتبة إعادة العد:** *الافتراضي: أي فرق ≠ 0 يفرض عدًّا ثانيًا بعدّاد آخر* (محافظ، كما MC :118). البديل: نسبة أو قيمة مطلقة لكل فئة.
5. **سماحية الاستلام الزائد:** *الافتراضي 0%*؛ الزيادة تنتظر المدير ولا تدخل المخزون.
6. **حركات أثناء الجرد:** *الافتراضي: الاعتماد بالسلوك القائم (المعدود − الرصيد الحالي) مع شارة تحذير وإمكان إعادة العد*. البديل: تجميد حركات النطاق أثناء الجرد.
7. **صلاحيات الأدوار:** *[مُستبدَل 2026-10-23 — قرار المالك 3]*. الافتراضي الآن هو جدول §B.4 بأربعة أدوار:
   - موظف مخزن (جديد).
   - مخزني، ويأخذ `inventory_transfer` افتراضيًا.
   - مشرف مخزن (جديد).
   - مدير مخزون.

   كان الافتراضي السابق «`'مخزني'` access+receipt+count و`inventory_transfer` يدويًا».
8. **ترقيم الترحيل:** *الافتراضي: أول رقم حرّ بعد ما تحجزه خطة 2026-10-18 (v197/v198)*، بالتنسيق مع من ينفّذ P4/P6.
9. **تباينات قائمة خارج النطاق (للعلم، لا تُصلَح هنا):** (أ) `POST /api/inventory/transfer` لا يطابق `transferStock` (السالب، الدفعات، قيود GIT) — `api_data_inventory.dart:266-352`. (ب) كتابات المخزون عبر API لا تفحص نطاق الفرع/المخزن. (ج) `deviceKind:'pos'` غير مقيّد المسارات. (د) `convertPOToInvoice` يسند العملية لأول مستخدم (`purchase_orders_dao.dart:212`). *الافتراضي: مهام منفصلة بعد W3.*
10. **طابعات الملصقات المخصّصة (ZPL/TSPL):** *الافتراضي: خارج R1؛ ملصقات raster على طابعات 58/80mm الحرارية*.
11. **الموديلات المدعومة رسميًا:** *الافتراضي: كاميرا + HID wedge فقط في R1*، وZebra/Honeywell/Urovo بعد تجربة جهاز فعلي يوفّره المالك.
12. **صلاحية الإقران (جديد 2026-10-23):** *الافتراضي: كود واحد `devices_pair_manage` لكل أنواع الأجهزة*، يُمنح لمدير النظام ولمن يعيّنه المالك مسؤولًا عن الربط. البديل: كود خاص لكل نوع جهاز (`devices_pair_warehouse` …)، وهو أدق لكنه يزيد إدارة الصلاحيات. (سؤال المراجعة Q13.)
13. **أدوار المخازن (جديد 2026-10-23):** *الافتراضي: دوران جديدان «موظف مخزن» و«مشرف مخزن» إضافة إلى «مخزني» و«مدير مخزون»* (§B.4). البديل: بلا أدوار جديدة، فالموظف ومسؤول المخزن = «مخزني»، والمشرف والمدير = «مدير مخزون». (سؤال المراجعة Q13.)

---

## F. حدود هذا التخطيط
- **[مقروء]** كل ما ذُكر بـfile:line. القراءة الواسعة (مسارات السيرفر، الحزم، الشاشات، الأدوار) جاءت عبر قرّاء فرعيين، وتحقّقتُ بنفسي من: `ARCHITECTURE-MC.md` كاملًا، و`warehouse_locations_schema.dart`، و`warehouse_locations_ops.dart`، و`lan_pairing_api_handler.dart`، و`api_data_inventory.dart:266-355`، و`inventory_transfers_dao.dart:53-122,240-299`، و`purchase_orders_dao.dart:170-239`، و`inventory_dao.dart:355-394`، و`api_handler_base.dart:70-144`، و`network_service.dart:790-824`، و`file_size_ratchet_test.dart`، و`mobile_pos/test/structural_test.dart`، و`epoch_3_v196_v205.dart`، وأحجام الملفات بقياس LF.
- **[استنتاج]** غياب القيد عن `transfer_out/in` في مسار API، وعمل `badCertificateCallback` لـpinning في الحزمة، وتقديرات الأيام، وسلوك goldens بين المنصّات.
- لم أقرأ: `carryTransferLots` وأسطر `transferStock` :123-239 كاملة، وقيود `createPurchaseInvoice` :620، و`approveRequisition`، ونص الأذونات الثلاثة الأخيرة في manifest الكاشير.
- لم يُشغَّل أي اختبار. حالة الحراس «خضراء الآن» غير مُتحقَّق منها.
- `ARCHITECTURE-MC.md` يذكر فرع `go/full-remediation` (HEAD `3bcf7158`) — أقدم من الحالي، فتعارضات A.2 ناتجة عن عمل لاحق (v195).
- **مواءمة 2026-10-23:** تحقّق المنسّق بالقراءة من:
  - حارس الإقران الحالي `linked_devices_section.dart:54-86` (علامة `system_admin` أو `*`، بلا كود صلاحية).
  - مدخل «إقران جهاز» في `network_mode_settings_picpos.dart:306` واستدعاء الحوار من القسم فقط.
  - منح «مخزني» (`role_grant_matrix.dart:203-228`) و«مدير مخزون» (`:426-456`).

  - غياب فحص الفاعل في `LanPairingService.issuePairingCode` (:93) و`revoke` (:503)، بالتوقيعات وgrep.

  لم يُتحقق من قدرة `grantMissingDefaults()` على إنشاء أدوار جديدة.

  لم يُشغَّل أي اختبار.


---

## قرارات المالك (2026-10-23) — تُلغي ما يخالفها في الخطة

> القرار 3 مطبَّق على متن الخطة في 2026-10-23 (§B.4، W0 G-1…G-7، W1، E-7، E-12، E-13)؛ انظر «سجل التغييرات» أعلاه. القرار 1: التطبيق باسم PicPos وفحص العلامة يشمل الـAPK (G-2). القرار 2 لا يمس هذه الخطة.

1. **النظام الآن لـPicPos فقط.** لا يُذكر UralCash في أي شيء يخص PicPos (ملفات، صور، أيقونات، نصوص، أسماء، حزم). يُراجع كل ما يتصل بذلك ويُجعل خاصًا بـPicPos. (يُغطّى ضمن مراجعة الهوية في docs/audits/2026-10-23-release-audit/.)
2. **تفعيل النسخة خارج نطاق الإعداد الأولي.** منطق التفعيل الأصلي موجود داخل النظام في الإعدادات (توليد كود تفعيل مرتبط بهاردوير الجهاز). **يُحذف من التصميم** كل ما يخص خطوة التفعيل/ملف التفعيل/الباقة المرخّصة في معالج أول تشغيل، ولا يُكرَّر منطق التفعيل. المعالج يكتفي بالإعداد، والتفعيل يبقى من الإعدادات.
3. **تطبيق المخازن:** تطبيق موبايل لمسؤول المخزن والمشرف والمدير والموظف، يُثبَّت على هاتفه ويُقرَن بالنظام بصلاحية المدير المسؤول عن ربط وإقران الأجهزة.
4. **قسم العقارات:** غير موجود حاليًا، وهو خطة إضافية لاحقة بعد مراجعة النظام وتطبيقاته.
5. **الترتيب:** تُنفَّذ مراجعة شاملة أولًا (طلب المراجعة) ثم يُصاغ الترتيب.

---

## حالة التنفيذ (W0 + W1) — 2026-10-23

**منجز:**
- `mobile_warehouse/` (`com.picpos.warehouse`، «PicPos مخازن»): توقيع يفشل مغلقًا، مفتاح اختبار عبر `tool/gen_android_keystore.ps1`، عملية CI (مصفوفة `packages_and_mobile` + `android-release`) وسطر `tool/run_e2e.ps1`، وAPK موقَّع.
- `picpos_api_client`: `PairingPayload` (v1/v2)، `WarehouseLanClient`، `wh_contracts` (مع تثبيت البصمة عبر `lan_pinning.dart` الموجود). `picpos_device`: `ScanEvent`/`ScanDeduper`.
- سطح المكتب: الصلاحية `devices_pair_manage` تُفرض في `LanPairingService` (إصدار/إلغاء/عرض) مع تدقيق في `ActivityLogs`؛ نوع الجهاز `warehouse` مقيَّد بالفرع من الرمز لا من الجهاز؛ `LanDeviceRoutePolicy` (ADR-W3)؛ `401 device_revoked` للجهاز الملغى؛ المسارات `GET /api/m1/info` و`/api/m1/wh/session` و`/api/m1/wh/items` (قراءة فقط، نطاق الفرع ∩ مخازن المستخدم).
- G-1، G-2 (بلا فحص علامة على الـAPK)، G-6 منجزة. G-4 كان قائمًا (`isUserLive`)، وG-7 كان قائمًا (`forcePasswordChange` في `issueSession`).

**مصفوفة الصلاحيات المنفَّذة** (`role_grant_matrix.dart`؛ الدوران الجديدان يُنشآن بـ`ensureWarehouseRoles` داخل `grantMissingDefaults`):

| الدور | الأكواد |
|---|---|
| موظف مخزن (جديد) | `warehouse_mobile_access`, `inventory_view` |
| مخزني | الموجود + `warehouse_mobile_access`, `inventory_transfer` |
| مشرف مخزن (جديد) | `warehouse_mobile_access`, `inventory_view`, `inventory_edit`, `inventory_transfer` |
| مدير مخزون | الموجود + `warehouse_mobile_access` |
| مدير النظام | + `devices_pair_manage` (ولا دور آخر) |

الأكواد `goods_receipt_mobile` و`stock_count_submit` و`stock_adjust_approve` **لم تُضف بعد**: تُضاف مع المرحلة التي تفرضها (W2–W4) كي لا يظهر كود بلا إنفاذ.

**فجوات معروفة:** حجب الأرصدة أثناء جرد نشط (W4)؛ بقية G-3 (نافذة bearer القديمة SEC-006)، وG-5 لغير أجهزة المخازن (`/api/parties` بلا جلسة)؛ فحص العلامة على الـAPK في CI؛ لا إبطال لرمز الجلسة عند الخروج (رمز موقَّع بلا حالة)؛ لم تُجرَّب أي أجهزة فعلية.

**حالة البوابات بعد مراجعة 2026-10-25 (WH-017، بصدق):** G-2 **مفتوحة** — لا فحص علامة على الـAPK في CI (لم يُنفَّذ ولم يُبنَ APK في هذه الجولة). G-3/SEC-006 **مفتوحة** — لا إبطال لرمز الجلسة عند الخروج، ونافذة bearer القديمة قائمة. آخر تشغيل للمختبر (20261026-012136: 67 PASS / 0 FAIL / 2 N/A) كان على مضيف «من الشجرة العاملة» **بلا commit hash**، ولا يشمل سيناريو السند ولا تبديل المستخدم A→B→A (WH-004)، فلا يُنسَب إلى 44098a7. المطلوب لإغلاقها: إعادة المختبر على مضيف مبني من commit مسجَّل مع هاش، وإضافة السيناريوين، وفحص العلامة على الـAPK، وإبطال الجلسة عند الخروج. **لا تُعدّ W0/W1 منجزتين قبل ذلك.**

---

## العقد المنفَّذ — W2…W5 (2026-10-25)

> ما كُتب هنا هو **ما نُفِّذ فعلًا وخُتبر**؛ يعلو على نص المراحل أعلاه عند التعارض. الاختبارات: `test/integration/{wh_po_receipt_flow,staged_transfer_conservation,wh_voucher_flow,wh_blind_count_leak,wh_count_finalize,wh_approvals_labels}_test.dart` على الموجّه والـmiddleware الحقيقيين، و`test/e2e/warehouse_docs_lan_e2e_test.dart` (العميل الحقيقي `WarehouseLanClient` على socket loopback)، و`test/integration_pg/wh_mobile_docs_pg_test.dart`.

### قرار التخزين: بلا جداول Drift وبلا ترحيل
- المستندات في ثلاثة جداول SQL خام `wh_mobile_docs` و`wh_mobile_doc_lines` و`wh_mobile_doc_events` (`lib/data/database/wh_mobile_docs_schema.dart`) على نمط `lan_pairing_schema` و`warehouse_locations_schema`.
- **لا تغيير في `database.g.dart` ولا `schemaVersion` (يبقى 196) ولا `database.dart` ولا `database_startup.dart`** (كلاهما في الـratchet).
- الجداول تُنشأ كسولًا عند أول عملية مستند (`CREATE TABLE IF NOT EXISTS`، مرة واحدة لكل اتصال)، لا في `_safeMigrate`. SQLite وPostgreSQL.
- **لا مزامنة** إلى عملاء سطح المكتب: المستندات تعيش على الحاسوب الرئيسي الذي يخدم الهواتف. هذا بديل عن بند «المزامنة» في W2 ويحتاج قرارًا إن أُريد صندوق اعتماد على سطح مكتب عميل.
- سجل الأوامر `wh_mobile_doc_events` (`command_id UNIQUE`) يُكتب **داخل معاملة الأثر** نفسها؛ إعادة الإرسال تُجاب من السجل (`replayed:true`) ولا تُنفَّذ ثانية؛ نفس المعرّف بجسم مختلف ⇒ `409 idempotency_conflict`.

### قواعد عامة لكل مسارات `/api/m1/wh/*` (الجديدة)
- جهاز `warehouse` فقط (`403 device_scope` لغيره)، مستخدم حيّ، `warehouse_mobile_access` + كود المسار، والنطاق = مخازن فرع الجهاز ∩ مخازن المستخدم (`WhScope`).
- كل كتابة تتطلب `X-Idempotency-Key` (≥ 8 محارف، = معرّف الأمر في outbox الجهاز) وإلا `400 idempotency_key_required`.
- الكميات نصوص. لا تكلفة في أي استجابة. الخطأ غير المتوقع `500 internal` **بلا نص** (حتى لا تتسرب كمية).
- الأخطاء: `permission_denied | stale | invalid_transition | stock_changed | batch_expired | idempotency_conflict | over_receipt | self_approval | warehouse_forbidden | staged_transfers_disabled | …` (القائمة الكاملة في `mobile_warehouse/lib/session/wh_session.dart: kDomainCodes` ولكل كود نص عربي/إنجليزي).
- الاعتماد: `stock_adjust_approve` عبر `ApiUserCtx.requirePermission`، وهو يقبل أيضًا بصمة المدير P5 (`x-approval-proof`، مرتبطة بالكود)؛ **المعتمِد الفعلي** = المستخدم إن حمل الكود وإلا مُعتمِد البصمة، ويُرفض `403 self_approval` إن كان منشئ المستند أو مُرسِله أو مستلمه أو أحد عدّاديه، بلا استثناء لمدير النظام.

### W2 — الاستلام مقابل أمر شراء (مكتمل)
| الطريقة والمسار | الكود | الوصف |
|---|---|---|
| `GET /api/m1/wh/po?warehouse=&status=open` | `goods_receipt_mobile` | أوامر `sent`/`confirmed` غير المحوَّلة في النطاق، مع المطلوب/المستلم، بلا تكلفة |
| `GET /api/m1/wh/po/<ref>` | نفسه | أمر واحد (`ref` = `globalId` أو الرقم) |
| `POST /api/m1/wh/po/<ref>/receipts` | نفسه | جسم `{globalId, note?, lines:[{lineGlobalId, productId, quantity, condition: ok\|damaged, batchNumber?, expiryDate?, locationBarcode?}]}`؛ ينشئ/يُلحق مسودة. صنف `trackExpiry` يتطلب دفعة وتاريخًا (`batch_required`) |
| `POST /api/m1/wh/receipts/<gid>/submit` | نفسه | مسودة ← `submitted`؛ يزيد `purchase_order_items.received_quantity`؛ الكاتب فقط (`not_owner`)؛ **زيادة عن المطلوب (سماحية `wh_receipt_overage_pct`، الافتراضي 0) ⇒ `409 over_receipt` ولا يُسجَّل شيء** |
| `GET /api/m1/wh/receipts?state=` | نفسه | استلاماتي |
| `GET /api/m1/wh/locations/by-barcode/<code>` | `inventory_view` | موقع `BIN-…` في النطاق |
| `POST /api/m1/wh/receipts/<gid>/convert` | `purchases_create` | **المحاسب**: `createPurchaseInvoice` بالكميات `ok` فقط مع الدفعة/الانتهاء وبـ`userId` الحقيقي ثم put-away إلى الموقع الممسوح؛ يختم الأمر `converted` فقط إن اكتمل المستلم ولا استلام آخر معلّق |
- **R-A محترم:** الاستلام لا يحرّك مخزونًا ولا قيدًا قبل `convert`؛ التالف لا يدخل المخزون؛ التحويل مرة واحدة (حالة `posted` + إعادة الأمر بنفس المفتاح تُجاب من السجل).
- **انحرافات:** (1) الزيادة تُرفض ولا تُسجَّل `over` بانتظار المدير؛ (2) لا شاشة «طلبات المخازن» على سطح المكتب: التحويل لفاتورة بالمسار أعلاه لمن يملك `purchases_create` (تطبيق/خدمة)، وواجهة المحاسب على سطح المكتب **غير مبنية**؛ (3) لا حالة `partially_received` على الأمر (التقدم يُقرأ من `received_quantity`).

### W3 — التحويل المرحلي والسندات (مكتمل خلف إعداد مطفأ)
- الإعداد `wh_staged_transfers_enabled` (الافتراضي **غير موجود = مطفأ**) يحرس كل مسارات التحويل: `409 staged_transfers_disabled` وتقول الواجهة ذلك. لا يُفعَّل قبل توقيع المحاسب على حساب `goods_in_transit`.
- **مسار LAN المعيب (E-9أ) مسوَّر:** جهاز `warehouse` يأخذ `403 device_scope` على `POST /api/inventory/transfer` و`/adjust` و`/bond` و`/api/purchase-orders` (اختبار). مستندات المخازن لا تستعمله؛ و`transferStock` لم يُلمَس. **لم يُصلَح** المسار نفسه لأجهزة سطح المكتب (خارج النطاق).
- الحالات: `requested → approved → in_transit → received | received_short → closed` (+`rejected`).
| المسار | الكود |
|---|---|
| `POST /transfers` `{globalId, fromWarehouseId, toWarehouseId, note?, lines:[{lineGlobalId, productId, quantity}]}` | `inventory_transfer` |
| `GET /transfers?state=` | `inventory_transfer` |
| `POST /transfers/<gid>/approve` · `/reject` | `stock_adjust_approve` (+ four-eyes) |
| `POST /transfers/<gid>/dispatch` | `inventory_transfer`؛ المصدر في النطاق |
| `POST /transfers/<gid>/receive` `{lines:[{lineGlobalId, received, damaged}]}` | `inventory_transfer`؛ الوجهة في النطاق |
| `POST /transfers/<gid>/resolve` `{resolution: return_to_source\|write_off_loss}` | `stock_adjust_approve` |
- **dispatch:** فحص رصيد صريح (لا سالب أبدًا حتى مع `enable_negative_sales`)، تغطية دفعة صالحة (`batch_expired`)، التكلفة تُجمَّد على السطر (متوسط المصدر)، خصم المصدر `transfer_out` عبر `adjustStock`، حمل الدفعات، قيد Dr `goods_in_transit` / Cr `inventory`.
- **receive:** إدخال الوجهة بالتكلفة المجمَّدة، استعادة الدفعات، قيد Dr `inventory` / Cr `goods_in_transit`؛ التالف يُستلم ثم يُنشأ تلقائيًا سند `damage` معلّق؛ النقص يبقى في الطريق (`received_short`)؛ الزيادة `409 over_receipt`.
- **resolve:** `return_to_source` (إدخال للمصدر + قيد عكسي) أو `write_off_loss` (Dr `inventory_shrinkage` / Cr `goods_in_transit`)؛ المعتمِد ≠ المنشئ ≠ المُرسِل ≠ المستلم؛ بعده `goods_in_transit` = صفر (مُختبَر).
- **السندات:** `POST /vouchers` `{globalId, type: in\|out\|damage, warehouseId, reason (إلزامي), lines:[…]}` (`inventory_edit`)، `GET /vouchers?state=`، `POST /vouchers/<gid>/approve|reject` (`stock_adjust_approve`، المعتمِد ≠ المنشئ). الترحيل عند الاعتماد فقط عبر `adjustStock` (`adjustment`/`damage` فيُقيَّد تلقائيًا)، والصادر يُعاد فحص رصيده داخل المعاملة.
- **غير منفَّذ:** اقتراح FEFO بالموقع، `dispatch` بمسح الدفعة/الموقع، override الدفعة بسبب، وجهة تحويل خارج مخازن المستخدم من واجهة التطبيق (الخادم يقبلها).

### W4 — الجرد الأعمى (مكتمل)
| المسار | الكود |
|---|---|
| `GET /api/m1/wh/counts/tasks` | `stock_count_submit`؛ مهام `pending/in_progress` في النطاق التي يحق للمستخدم عدّها؛ DTO العدّاد = `{ref, warehouseId, warehouse, date, draftGlobalId?, items:[{productId, code, name, barcode}]}` **بلا أي كمية** |
| `POST /counts/<ref>/entries` `{globalId, entries:[{lineGlobalId, productId, quantity≥0, locationBarcode?, batchNumber?}]}` | نفسه |
| `POST /counts/<ref>/submit` `{globalId}` | نفسه؛ **الجواب `{globalId, state:'submitted'}` فقط** (لا يُخبَر العدّاد بحاجة إعادة العد) |
| `GET /counts/<ref>/review` | `stock_adjust_approve`؛ المتوقع (الرصيد الحالي) والمعدود والفرق وحركات منذ العدّ (`recountAdvised`) |
| `POST /counts/<ref>/approve` | `stock_adjust_approve`؛ `finalizeCycleCountTask` مرة واحدة |
- `<ref>` = `globalId` المهمة أو رقمها. المهام تُنشأ على سطح المكتب (`generateCycleCountTask`)؛ إنشاؤها من الهاتف **غير منفَّذ**.
- E-4 (الافتراضي): أي فرق ≠ 0 في المرور الأول يفرض مرورًا ثانيًا بعدّاد **آخر** (الأول لا يرى المهمة بعد إرساله)، والاعتماد قبله `409 recount_required`. المرور الثاني يستبدل القيم. العدّ يجب أن يغطي كل الأصناف (`incomplete_count`)، والصنف خارج المهمة يُضاف بمتوقع = الرصيد الحالي.
- المعتمِد ≠ كل العدّادين (حتى مدير النظام) وإلا `self_approval`؛ بعد الاعتماد `already_finalized`.
- **عدم التسرب (مُختبَر بتسلسل كل استجابة):** العدّاد = من يحمل `stock_count_submit` بلا `stock_adjust_approve`. `GET /items` يعيد `blind:true` بلا كمية للصنف تحت جرد مفتوح؛ ورفض `stock_changed` لا يحمل `available` لعدّاد ذلك الصنف؛ كل خطأ غير متوقع `500` بلا نص. ليس في الاستجابات حقل `expected|variance|system`.
- E-6 (الافتراضي): الاعتماد بسلوك `finalizeCycleCountTask` (المعدود − الرصيد الحالي) مع شارة «حركة بعد العدّ».

### W5 — الاعتمادات والطباعة وoutbox (مكتمل إلا العتاد)
- `GET /api/m1/wh/approvals` (`stock_adjust_approve`): طلبات تحويل، نقص تحويل، سندات، جرد جاهز؛ **يستبعد ما أنشأه/نفّذه/عدّه المستدعي** (four-eyes). `GET /api/m1/wh/labels?kind=item|location&ref=` (`inventory_view`): بيانات ملصق بلا تكلفة (`no_barcode` إن لم يكن للصنف باركود).
- **التطبيق:** `lib/printing/label_builder.dart` يبني `Receipt` مستقلًا عن النقل (Code128؛ وQR للموقع)؛ `LabelPrinter` منفذ طباعة: `NoPrinter` (الافتراضي: «لا توجد طابعة متصلة» ولا يدّعي الطباعة) و`ServiceLabelPrinter` فوق `PrintService` (Bluetooth SPP أو شبكة 9100، 58/80 مم) بطابور إعادة؛ فشل الطباعة لا يمسّ المخزون. شاشة اختيار الطابعة. أذونات Bluetooth أُضيفت للـmanifest الآن (`BLUETOOTH_CONNECT`، و`BLUETOOTH_SCAN` بـ`neverForLocation`، والقديمان حتى SDK 30).
- **outbox:** `WhOutbox` فوق `SqlCipherLocalStore` المشفَّر؛ معرّف الإدخال = `x-idempotency-key`؛ إرسال بالترتيب. قواعد التعارض: 2xx مقبول (`replayed` ⇒ مكرر)، لا اتصال/429/5xx يبقى معلّقًا، 401 يبقى معلّقًا ويطلب دخولًا، **أي 4xx آخر (stale، stock_changed، self_approval، over_receipt…) مرفوض نهائي لا يُعاد إرساله بهوية جديدة** ويظهر بسببه مع زر «إخفاء». شريط عدم اتصال/عمليات معلّقة فوق كل التبويبات.
- **الشاشات:** المستندات (استلام، جرد، تحويلات، سند، اعتمادات، ملصقات حسب صلاحيات الجلسة)، الـoutbox، الإعدادات (الطابعة).
- **غير منفَّذ (يقول ذلك ولا يزيّف):** `ScanIntentPlugin` وملفات Zebra/Honeywell/Urovo (تحتاج عتادًا — E-11؛ المدعوم الكاميرا وماسح لوحة المفاتيح)، `docs/mobile/warehouse-hardware-checklist.md`، طلب إذن Bluetooth وقت التشغيل (الواجهة تعرض رسالة «امنح الإذن من الإعدادات»)، تخزين قائمة أوامر الشراء للعمل بلا اتصال (الشاشة تقول إنها تحتاج المكتب)، إرسال بصمة الموافقة P5 من واجهة التطبيق (العميل `command(..., approvalProof:)` يدعمها والخادم يقبلها ومُختبَر).

### مصفوفة الصلاحيات المنفَّذة (محدَّثة)
| الدور | الأكواد |
|---|---|
| موظف مخزن | `warehouse_mobile_access`، `inventory_view`، `goods_receipt_mobile`، `stock_count_submit` |
| مخزني | الموجود + `warehouse_mobile_access`، `goods_receipt_mobile`، `stock_count_submit`، `inventory_transfer` |
| مشرف مخزن | `warehouse_mobile_access`، `inventory_view`، `inventory_edit`، `inventory_transfer`، `goods_receipt_mobile`، `stock_count_submit`، `stock_adjust_approve` |
| مدير مخزون | الموجود + `warehouse_mobile_access`، `inventory_transfer`، `goods_receipt_mobile`، `stock_count_submit`، `stock_adjust_approve` |
| مدير النظام | + `devices_pair_manage` |
- الأكواد الثلاثة الجديدة معرَّفة في `lib/core/permissions/warehouse_permission_codes.dart` ومسجَّلة في `masterList` عبر السطر القائم (بلا نمو في `permission_codes.dart`).
- نقاط الإنفاذ: `goods_receipt_mobile` ← `wh_receipt_handlers.dart`، `stock_count_submit` ← `wh_count_handlers.dart` وحجب الجرد، `stock_adjust_approve` ← `wh_stock_doc_handlers.dart` و`wh_count_handlers.dart` و`wh_approval_handlers.dart`.

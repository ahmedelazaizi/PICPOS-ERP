# FIXES-4 — WH-014 / WH-015 / WH-019 / WH-020 / WH-030 (2026-10-26)

العقد التفصيلي والقرارات: الخطة، قسم «العقد المنفَّذ — جولة FIXES-4». كل الاختبارات كُتبت أولًا وفشلت قبل الإصلاح (أو لم يكن المسار موجودًا).

| البند | السبب الجذري | الإصلاح (ملفات) | اختبارات | الحالة |
|---|---|---|---|---|
| WH-014 | لا فحص تداخل عند الاعتماد، ولا مسار recount | `m1_wh/wh_count_overlap.dart` (جديد)، `wh_count_service.dart`، `wh_count_handlers.dart`، `wh_doc_store.dart` (انتقال `recount`→`superseded`)، `routes/api_routes_m1_wh.dart`، `test/golden/api_routes.txt` | `test/integration/wh_count_overlap_test.dart` (8) | **مُنجَز** (منع التداخل عند إنشاء المهمة على المكتب غير منفَّذ) |
| WH-015 | الإذن يُطلب داخل الإضافة بلا انتظار، ودمج الـmanifest يُبطل `maxSdkVersion` | `picpos_device/.../bluetooth_permission.dart` (جديد)، `printer_transport.dart`، `MainActivity.kt`، `AndroidManifest.xml`، `label_printer.dart`، `labels_page.dart`، `printer_settings_page.dart`، `main.dart`، `strings.dart` | `packages/picpos_device/test/bluetooth_permission_test.dart` (7)، `mobile_warehouse/test/bluetooth_manifest_test.dart` (6)، `label_builder_test.dart` (+2) | **مُنجَز في الكود والاختبارات؛ غير مُتحقَّق على جهاز** (Android 14 + `aapt2` للمختبر) |
| WH-019 | `expectedVersion` اختياري ولا يُرسَل؛ والفحص بعد الأثر في بعض المسارات؛ `convert` بلا فحص | `wh_stock_doc_handlers.dart`، `wh_doc_store.dart` (`requireVersion`)، `wh_receipt_posting.dart`، `wh_receipt_handlers.dart`، `wh_receipts_inbox.dart`، `wh_approval_handlers.dart`، `picpos_api_client` (`voucherAction`، `WhApprovalItem.version`)، `transfer_pages.dart`، `approvals_page.dart` | `test/integration/wh_version_checks_test.dart` (6)؛ `mobile_warehouse/test/docs_flow_test.dart` (+2) | **مُنجَز** (استثناءات موثَّقة في الخطة) |
| WH-020 | `adjustStock` لا يستهلك الدفعات لـ`cycle_count`، والسند يستهلكها لـ`trackExpiry` فقط | `daos/inventory_batch_dao.dart` (`shrinkBatchesForLoss`)، `daos/cycle_count_dao.dart`، `wh_voucher_service.dart` | `test/integration/wh_batch_ledger_test.dart` (9) | **مُنجَز** (الزيادة لا تخلق دفعة — قرار) |
| WH-030 | لا فصل بين المرسِل والمستلم | `wh_transfer_service.dart` | `test/integration/wh_transfer_distinct_test.dart` (2)؛ عُدِّل فاعل الاستلام في `staged_transfer_conservation_test`، `wh_transfer_damaged_receive_test` | **مُنجَز** (قرار محافظ) |

## ما لم يُتحقَّق
- PostgreSQL: لم يُغيَّر SQL خام جديد (استعلامات Drift فقط)، لذا لم يُشغَّل `run_pg_tests`.
- الجهاز: إذن Bluetooth وقت التشغيل على Android 12+/14 و`aapt2 dump permissions`.
- `test/integration/wh_receipts_inbox_test.dart` («a paired DESKTOP (pos) device converts…») يفشل بـ`403 device_scope` عند التحويل من جهاز `pos`: مصدره تعديلات العامل C غير المُرسَلة في `lan_device_route_policy.dart`/`api_auth_middleware.dart` (لم ألمسهما)؛ يحتاج مراجعة هناك.
- `mobile_warehouse/test/e2e/warehouse_app_e2e_test.dart` («blind count…») متذبذب مسبقًا: يبحث عن `137` في معرّفات عشوائية؛ نجح في إعادة التشغيل.
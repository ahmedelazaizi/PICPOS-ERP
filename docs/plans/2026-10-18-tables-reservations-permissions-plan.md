# خطة: الطاولات والحجوزات والصلاحيات وربط الجوال — 2026-10-18

> وثيقة تصميم/تخطيط فقط (لا كود). الفرع: `feat/financial-intelligence`. `schemaVersion` الحالي **195** (`lib/data/database/database.dart`).
> كُتبت بقراءة الكود الفعلي؛ كل بند موسوم **[مقروء]** (تحقق بالقراءة، مع file:line) أو **[استنتاج]**. لم يُشغَّل أي اختبار أو بناء أو Android.
> المنفّذ (Sonnet) ينفّذ المراحل بالترتيب في §C، ويلتزم بقواعد `docs/ARCHITECTURE-MAP.md` §2–§4 و§7 (ملفات جديدة ≤ 30KB، لا نموّ للملفات المسجَّلة في `test/structural/file_size_baseline.txt`، ترحيلات idempotent بـ`_safeMigrate`).

## فهرس
- §A النتائج لكل متطلب 1–10
- §B قرارات التصميم (8، 9، 10) مع البدائل
- §C خطة التنفيذ المرحلية P0–P7
- §D المخاطر والأسئلة المفتوحة للمالك
- §E استراتيجية الاختبار والتحقق

---

## A. النتائج (Findings) لكل متطلب

### A.1 — قائمة «الشاشة الافتراضية» تعرض 4 خيارات فقط

**السلوك الحالي [مقروء]:**
- القائمة مكتوبة يدويًا (hardcoded) في **ثلاث نسخ غير متطابقة**:
  - PicPos: `lib/presentation/users_picpos/screens/users_management_picpos_screen.dart:636-665` — `DropdownButtonFormField<String>` بأربعة عناصر `pos / dashboard / products / inventory`؛ ودالة `_homeScreenLabel` :504-517 تعكس نفس المفاتيح الأربعة (`default: 'غير محددة'`).
  - Legacy (UralCash): `lib/presentation/screens/users_management_screen.dart:255-284` — نفس الأربعة؛ الحفظ `_updateDefaultScreen` :553-571 يكتب النص الخام.
  - ودجت الإعدادات: `lib/presentation/widgets/settings/user_management_widget.dart:300-304` و:475 — قائمة **مختلفة** (`pos / dashboard / tables`).
- التخزين: `users.default_screen` نص، default `'pos'` — `lib/data/database/tables/auth_tables.dart:74-75`؛ الكيان `UserEntity.defaultScreen: String?` (`lib/domain/entities/user_entity.dart:13`). DAO: إنشاء `?? 'pos'` (`user_dao.dart:197`) لكن التحديث `?? ''` (`user_dao.dart:253`) — عدم اتساق.
- التطبيق عند الدخول: `lib/app_main_screen_lifecycle.dart:61-96` (`initializeDefaultScreen`) — `switch` يدوي على 5 مفاتيح (`pos→1, dashboard→0, tables→3, products→4, inventory→8`) ثم `int.tryParse` ثم fallback إلى POS، ثم تحقق من `userAllowedScreensProvider`. لا استعمال لـ`AppScreen`/`ScreenId`. إعادة التطبيق: `app_main_screen_navigation.dart:262-281`.
- الكتالوج الكامل للشاشات: `lib/core/enums/app_screen.dart:7-138` (≈90 قيمة بأرقام `value`)، `lib/core/navigation/screen_id.dart:26-269` (`navigationIndex`, `fromIndex`)، `screen_registry.dart` (`forProfile(profile, features)` :518-529 يطبّق قوائم النشاط وتحويلات PicPos)، `AppConfig.allowedScreenIds` (`lib/core/config/app_config.dart:198-210`)، التسميات المترجمة موجودة في `ScreenConfig.label` (`lib/app_main_screen_catalog.dart`, `buildAllScreens()`).
- `ScreenConfig` (`lib/app_main_screen_dialogs.dart:32-53`) **لا يحمل أي حقل صلاحية**؛ الربط شاشة↔صلاحية في `screenPermissionMap` فقط (`lib/data/providers/auth_providers.dart:1152-1254`).

**السبب الجذري:** القائمة ثابتة ومنسوخة ولا تُشتق من الكتالوج ولا من صلاحيات الدور. **خطر إضافي [مقروء]:** `initialValue: user.defaultScreen` يُمرَّر مباشرة؛ أي قيمة خارج العناصر الأربعة (مثل `'tables'` المحفوظة من ودجت الإعدادات أو رقم) تُسقط assertion الـDropdown في debug.

**لا اختبار** يغطي هذه القائمة [مقروء] (`test/` لا يحتوي `الشاشة الافتراضية`).

### A.2 — دلالات الصلاحيات: فتح الشاشة مقابل الأفعال داخلها

**القاعدة الحالية [مقروء]:** فتح الشاشة = **كود واحد بالضبط** من `screenPermissionMap` (`auth_providers.dart:1152-1254`، النوع `Map<ScreenId, String>`)، يُفحَص على دور الجلسة مع تجاوز `مدير النظام` (`hasSystemAdminBypass` :245-250). وليس بالضرورة كود `_view`:
- `products/categories → products_add` (:1157-1158) و`products_view` موسوم `nonToggleable` (`permission_codes.dart:1036`) ⇒ مَن يملك `products_edit` فقط لا يدخل.
- `purchases → purchases_create` (:1163)؛ `bookings → tables_view` (:1213) رغم وجود 11 كود `bookings_*` كلها في `knownUnenforced` (`permission_enforcement_registry.dart:117-131`)؛ `floorPlanDesigner → tables_manage` (:1253)؛ `receiptVoucher/paymentVoucher → treasury_view` (:1247-1248)؛ `customers/suppliers/parties → customers_view` (:1159-1161).
- `userAllowedScreensProvider` (:1256-1316) و`userNavItemsProvider` (:1063-1140) يطبّقان نفس الكود الواحد؛ `kAllNavItemDefs` يحمل `permission:` موازيًا يُجبره اختبار `test/unit/screen_permission_map_test.dart:51-79` على مطابقة الخريطة 1:1.
- أدوات الفحص داخل الشاشة: `PermissionGuard({permission|allOf|anyOf, showDisabled, allowManagerOverride})` (`lib/presentation/widgets/permission_guard.dart:69-181`)، `ensurePermission(ref, context, code)` (:863-890)، نسخة POS `_ensure` (`pos_picpos/widgets/picpos_cart_permissions.dart:45-83`)، `PermissionBuilder` بلا bypass (:782-805)، `hasPermissionWithAdminBypass` (:835-845).
- `SecurityScreenGate` **ليس** بوابة صلاحيات بل كلمة سرّ قسم (`widgets/auth/security_gate_wrapper.dart:10-54`).

**الصلاحيات الشرطية الموجودة [مقروء]:**
- `role_permissions.grant_mode` (`allow|conditional`) — `auth_tables.dart:54`، ترحيل v163؛ تُصدَّر كعلامات `cond:<code>` (`permissions_dao.dart:298-314`) وتُجبر مسار موافقة المدير في `PermissionGuard` :216-239 و`ensurePermission` :880. ثنائية بلا قيمة حدّ.
- سقف خصم لكل مستخدم `users.max_discount_percent` — مُنفَّذ فقط في POS القديم (`pos/widgets/cart/cart_discount_dialog.dart:233-266`)؛ **صفر مراجع في `pos_picpos`**.
- سقف خصم للمتجر (PicPos) `disccap/discappr` في `quick_sale_policy.dart:331-343` مُنفَّذ في `ensureDiscountWithinPolicy` (`picpos_cart_permissions.dart:246-274`).
- نطاق الفرع ليس صلاحية: `user_branch_access` → `branchScopeProvider` (`branch_scope_provider.dart:157`)؛ `criticalFinancialOps` (`permission_codes.dart:991`) لا يتجاوزها حتى المدير.
- لا يوجد `PermissionCondition`/`limitValue`.

**أزرار بلا بوابة [مقروء]:**
1. `screens/tables/table_order_dialogs.dart:384-394` «دمج مع طاولة أخرى» يستدعي `_onMergeTable` مباشرة متجاوزًا `TableActionsRunner.run` (الفحص الوحيد لـ`tables_merge` في `table_operations.dart:1124-1131`)؛ «إضافة أصناف» :399-417 و«تحصيل الحساب» :418-435 تدفع `TablePosScreen` بلا `tables_add_items/tables_checkout`.
2. `table_operations.dart:728-769` إلغاء الحجز/إجلاس بلا فحص؛ حفظ الحجز :990-1019 بلا `tables_reserve`.
3. مجلد `bookings_picpos/` كامل بلا أي `PermissionGuard`/`PermissionCodes` (حفظ الحجز `new_booking_panel.dart:108-113`، محرّرات الكتالوج `booking_catalog_editors.dart:120,320`).
4. `customers_add/edit/delete` بلا إنفاذ في الواجهة (فقط API `api_party_handler.dart:34-42`).
5. `table_sections_crud.dart:148-156` أزرار الأقسام غير محمية عمدًا.

**الحراس التي تقيّد الحل [مقروء]:** `test/structural/allowed_screens_can_render_test.dart` يقرأ الخريطة بـregex `ScreenId\.(\w+):\s*'` من `auth_providers.dart` (:50) ⇒ يجب إبقاء الشكل الحرفي `ScreenId.x: 'code'`. `screen_permission_map_test.dart` يفرض nav/map 1:1 وكود واحد. `picpos_permission_parity_test`، `permission_enforcement_coverage_test` (كل كود في `masterList` يجب أن يُنفَّذ أو يُسجَّل في `knownUnenforced`؛ والسجل يجب أن **ينكمش**)، `picpos_respects_conditional_permission_test`.

### A.3 — ربط تطبيقات الجوال

**الموثَّق [مقروء]:** `docs/mobile/دليل_ربط_تطبيق_المندوب.md` — الهاتف يكلّم **السيرفر السحابي** (`:18080`) لا سطح المكتب؛ رمز 8 أحرف/10 دقائق/مرة واحدة من ملف الموظف؛ الهاتف يُدخل URL يدويًا. لا QR ولا اكتشاف شبكة.

**سطح المكتب — آليتان منفصلتان [مقروء]:**
- **LAN pairing** (`POST /api/pair` معفى من المصادقة — `api_auth_middleware.dart:48-55`؛ المعالج `lan_pairing_api_handler.dart:17-68` يقبل `deviceKind: admin|pos` و`branchId`): الحوار `widgets/settings/lan_pairing_dialog.dart:48-68` يعرض **نصًا فقط** مع زر «نسخ payload QR» ورأسه يصرّح بعدم رسم QR رغم وجود `qr_flutter ^4.1.0` في `pubspec.yaml:49`. العرض في الذاكرة فقط (`lan_pairing_service.dart:112`), TTL 10 دقائق (:20)، payload `{serverHost, port, pairingCode, serverFingerprint}` (:101-106)، الخادم على **8080 HTTP** افتراضيًا (`network_service.dart:56,257,816-821`).
- **Cloud pairing**: المندوب (`hr_picpos/widgets/rep_pairing_flow.dart:51-58`) نص فقط؛ المشرف (`settings_picpos/screens/linked_devices_section.dart:799-832`) يعرض `QrImageView` بـJSON `{v:1, cloudUrl, cloudCode, desktopSigningKey}` — **يحمل سرًّا طويل العمر (`desktopSigningKey`) داخل الـQR** [مقروء]، و`_pair()` ينفّذ 3 نداءات سحابية متتابعة (حتى 30 ث لكلٍّ، `cloud_link_api.dart:43`) **بلا مؤشر انشغال**.
- لا `/api/m1/info` على الخادم المضمَّن رغم أن `TransportSelector` في `packages/picpos_api_client` يجسّه (`transport.dart:145-205`) [مقروء].
- لا اكتشاف LAN (mDNS/UDP) في أي طرف [مقروء].

**الجوال [مقروء]:**
| | Van `mobile/` | Admin `mobile_admin/` | Cashier `mobile_pos/` |
|---|---|---|---|
| الشاشة | `lib/screens/pairing_screen.dart` | `lib/screens/onboarding_screen.dart` | `lib/screens/onboarding_screen.dart` |
| المدخلات | URL + كود (:37-51) | URL+كود أو **لصق JSON** الـQR (:241-271) | **كل الحقول `enabled:false` والأزرار `onPressed:null`** (:40,47-55) — «Pairing arrives in M-5» |
| URL افتراضي | `http://10.0.2.2:18080` مُثبَّت (:13) — لا يعمل على هاتف حقيقي | فارغ | — |
| النداء | `POST /mobile/pair` مهلة 20 ث (`cloud_api.dart:57`) | `POST /manage/pair` مهلة 30 ث | — |
| mobile_scanner | نعم `^7.4.2` (للباركود فقط) | لا | لا |
| Manifest | INTERNET، `usesCleartextTraffic=false`، NSC (debug يسمح cleartext) | INTERNET + CAMERA | INTERNET + CAMERA + WIFI_STATE |

سياسة الروابط `packages/picpos_api_client/lib/src/url_policy.dart:31-50`: release = HTTPS فقط؛ debug يسمح HTTP لـ`localhost/10.0.2.2/127.*/192.168.*` فقط ⇒ شبكة `10.x`/`172.16.x` تُرفض فورًا بـ`url_not_allowed` [مقروء].

**أسباب «الشاشة لا تستجيب» (مرتّبة):** (1) Cashier app لا يملك ربطًا أصلًا — كل شيء معطَّل [مقروء]. (2) Van: URL افتراضي خاطئ + رفض السياسة ⇒ فشل فوري/أو انتظار صامت حتى 20 ث عند IP غير قابل للوصول بلا زر إلغاء [مقروء؛ الإحساس بالتجمّد استنتاج]. (3) Admin: حوار بصمة modal في منتصف الطلب (:57-101) قد لا يُلاحَظ [مقروء]. (4) Desktop admin/rep pairing بلا مؤشر تقدّم حتى 90 ث [مقروء]. (5) كتابة المفاتيح في store مشفّر على UI isolate [استنتاج].

### A.4 — زر «إضافة طاولة» مقصوص في رأس الشاشة

**[مقروء]** الشاشة الفعلية في PicPos هي `TablesPicposScreen` (`app_main_screen_catalog.dart:31-33`). الرأس `tables_picpos_screen.dart:142-207` يمرّر 6 عناصر إلى `PicPosScreenScaffold(headerActions:)` → `PicPosPageHeader(actions:)` (`picpos_shell/picpos_screen_scaffold.dart:43-49`). تخطيط الرأس `picpos_shell/picpos_page_header.dart:39-158`:
```dart
Row(children: [
  Flexible(flex: 28, child: Column(title/subtitle)),
  Expanded(flex: 72, child: Align(centerEnd,
    child: SingleChildScrollView(scrollDirection: horizontal, reverse: true,
      child: Row(mainAxisSize: min, children: [...actions])))),
])
```
**السبب الجذري:** الأفعال محصورة في 72% من العرض؛ عند تجاوزها يُثبَّت الـScrollView على النهاية (`reverse: true`) فينزلق **أول** عنصر بالترتيب (في RTL هو «إضافة طاولة») خارج المنطقة المرئية **بصمت** بلا overflow error. تعليق في الملف نفسه (:119-127) يوثّق العرض «ة طاولة». لا اختبار يغطي الرأس (`TablesPicposScreen` لا يُضَخّ في الاختبارات — `test/widget/tables_designer_mode_button_permission_gate_test.dart:9-11`).

### A.5 — مصمم القاعة بلا زر رجوع

**[مقروء]** `floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart` (40,050 بايت — **في الـbaseline، لا يجوز أن ينمو**) يُفتح كشاشة في الشِّل: `screenNavigationProvider.notifier.open(ScreenId.floorPlanDesigner.navigationIndex)` (`tables_picpos_screen.dart:199-201`)، ورأسه `PicPosScreenScaffold` يُظهر زر الرجوع فقط `if (Navigator.canPop(context))` (`picpos_page_header.dart:50`) — وهو false داخل الشِّل. **الحالة المتسخة موجودة:** `_dirty` (:136-142)، `_confirmDiscard()` (:460-486)، undo/redo؛ لكن **لا `PopScope`** ولا تأكيد عند مغادرة الشاشة عبر الشريط الجانبي.

### A.6 — بطاقة الطاولة لا تعرض القسم

**[مقروء]** `screens/tables/widgets/table_card.dart` تعرض الاسم (:100)، السعة (:117-125)، شريحة الحالة (:140-165)، الوقت المنقضي، تقدّم الدفع — **لا اسم القسم**. البيانات متاحة: `RestaurantTables.sectionId → TableSections` (`tables/restaurant_tables.dart:82-124, 44-80`)، ومزوّدات خاصة بالشاشة `_sectionsProvider/_tablesInSectionProvider` (`screens/tables/providers/tables_state_provider.dart:45-55`).

### A.7 — فلاتر الحالة تُخفي الطاولات

**[مقروء]** `tables_picpos_screen.dart:308-310`:
```dart
final shown = uiState.statusFilter == 'all' ? tables
    : [for (final t in tables) if (t.status == uiState.statusFilter) t];
```
وتُمرَّر `statusFilter` نفسها للخريطة (:301-302). شريط الحالات `tables_picpos/widgets/tables_status_rail.dart:59-81` (الضغط مرتين يلغي). الحالات: `available/occupied/paid/reserved/out_of_service` (`domain/models/table_status.dart:6-22`). **خريطة الألوان hex ثابتة لا theme tokens**: `screens/tables/widgets/table_status_info.dart:19-30` (لونها وحده هو المميِّز بجانب شريحة نصية).

### A.8 — التصميم الحالي وما يمكن إعادة استعماله

- **الفروع** `claude/booking-system-qr-list-036e85`، `claude/tables-reservations-logic-673340`، `claude/shifts-payments-tables-requests-d03c7d`، `claude/table-service-three-items-434fee` كلها **أسلاف لـHEAD (مدموجة)** [مقروء: `git merge-base --is-ancestor` = 0]. لا عمل غير مدموج يُستعاد منها.
- مواصفات سابقة قابلة لإعادة الاستعمال: `docs/superpowers/specs/2026-08-19-tables-picpos-restyle-design.md`، `2026-08-20-booking-core-engine-design.md`، `2026-08-22-bookings-ui-design.md`، و`2026-08-20-next-session-prompt-reservations-and-qr.md` الذي يثبّت **قرار المالك**: `TableReservations` (حجز مكان) يبقى مستقلًا عن `Bookings` (حجز وقت إنسان) — **لا دمج في جدول واحد**، وقاعدتاه «لكل زرّ صلاحية» و«كل عمل يُسجَّل في سجل العمليات من الخدمة».
- **محرّك الأفعال** `screens/tables/table_operations.dart` (51,902 بايت، ratcheted) عبر `TableActionsRunner.run` و`actionsForStatus` (`domain/models/table_actions.dart:24-64`) و`permissionForAction` (:75-100) — يُعاد استعماله كما هو.
- **حجوزات الطاولات اليوم [مقروء]:** `TableReservations` (`restaurant_tables.dart:295-315`): `tableId, customerName, customerPhone, reservationTime, partySize, notes, status(pending|confirmed|seated|cancelled|no_show)`. **لا** `partyId` ولا مدّة ولا `endsAt` ولا عربون. DAO `tables_dao.dart:589-713` (`watchTodayReservations`, `getActiveReservationForTable`)، repo `IRestaurantRepository.createReservation/cancelReservation/seatReservation` (`domain/repositories/restaurant_repository.dart:44-55`).
- POS للطاولة: `pos/screens/pos_table_service_screen.dart` (`TablePosScreen(tableId, tableName)`) يُدفع بـ`Navigator.push` من `table_operations.dart:400-411`؛ لا شاشات طاولات في `pos_picpos/`.
- عرض الشبكة: `GridView.builder` بـ`maxCrossAxisExtent: 200` (:308-339)؛ عمود أفعال يمين 220px (`tables_action_rail.dart`) محمي بـ`PermissionGuard(showDisabled: true)` و`run()` معًا.

### A.9 — الخدمات والفوترة في شاشة الحجوزات

**[مقروء]** الشاشة `bookings_picpos/screens/bookings_picpos_screen.dart`؛ التبويبات `BookingsDestination` (`domain/models/picpos_booking_view.dart:393-405`)؛ تبويب الخدمات `BookingsServicesView` (`bookings_simple_views.dart:472-537`).
- **الخدمة** صف في `BookingServices` (`tables/booking_tables.dart:84-140`: `name, durationMinutes, bufferMinutes, price, colorHex, productId?→Products, isActive, sortOrder, branchId`). المحرّر `booking_catalog_editors.dart:213-234` → `db.upsertBookingService` (`bookings_dao.dart:310`) **لا يُنشئ صنفًا**؛ يسمح فقط بربط صنف موجود نوعه `'service'` (:107-109, 149-160؛ الـDAO يرفض غيره :326-338). لا مفتاح تفعيل ولا حذف في الواجهة (`softDeleteBookingService` :412 بلا مستدعٍ).
- **المنتجات:** `products.productType` نص افتراضي `'general'` بقيم موثّقة `general|raw_material|finished_goods|service` (`tables/product_tables.dart:125-127`) — **لا enum**؛ `trackInventory` (:105)؛ `sales_mutations_dao.dart:371` يتخطى حركة المخزون لغير المتتبَّع و`zero_cost_policy` يُطبَّق على المتتبَّع فقط (:336-356)؛ الضريبة `taxRate` (:131) + `itemTaxType/itemTaxSubtype/egsCode/gpcCode` (:140-146)؛ الوحدة `unitId?` (:79).
- **الفوترة اليوم:** «تفويتر» → `showBookingInvoiceDialog` (`bookings_picpos_screen.dart:180-190`) → `_handOff` (`booking_invoice_dialog.dart:93-117`) يستدعي `assertBookingInvoiceable` (`bookings_dao.dart:641`) ثم `bookingInvoicingProvider.notifier.begin(id)` ويغلق — **تعليق الرأس (:15) يدّعي تحميل الصنف والعميل في السلة والكود لا يفعل أيًّا منهما**. بعد البيع في POS: `pos/providers/checkout_controller.dart:296-315` → `applyBookingDepositToInvoice` (`bookings_dao.dart:723`) يشترط `booking.partyId != null && invoice.customerId == partyId` (:745-759) ويكتب `Bookings.invoiceId` (:799-800).
- **خط الفواتير:** `SalesTransactionOrchestrator.completeSalesTransaction(SaleRequest)` (`data/repositories/sales_transaction_orchestrator.dart:617`؛ `createSalesInvoice` :101-148)؛ `SaleRequest` (`domain/repositories/sales_repository.dart:294-393`: items, customerId, paymentMethod, paidAmount, cash/bank/clickAmount + safe ids, adhocCustomer*, branchId, globalId…)؛ القيد المحاسبي `_accountingService.generateSalesAccountingEntry` (:446-470)؛ الفوترة الإلكترونية fire-and-forget `eInvoiceAutoSubmitterProvider.submitSaleInvoice` (`checkout_controller.dart:267-281`)؛ idempotency: `SalesInvoices.idempotencyKey` + فهرس (`sales_purchase_tables.dart:285,412`) و`globalId` فريد. **لا `sourceType/sourceId` على الفاتورة**؛ الربط عكسي `Bookings.invoiceId`. طرق الدفع `cash|card|click|credit|multiple` (:376-378).

### A.10 — عملاء الحجوزات

**[مقروء]**
- `Bookings` فيه `partyId?→Parties` (`booking_tables.dart:147`) لكن لوحة الحجز الجديدة تأخذ اسم/هاتف نصًّا فقط و**لا تضبط `partyId` أبدًا** (`new_booking_panel.dart:259-270`) ⇒ تطبيق العربون عند الدفع يرمي «غير مرتبط بعميل مسجَّل» لكل حجز أُنشئ من اللوحة. `TableReservations` بلا `partyId` أصلًا (A.8).
- `Parties` (`sales_purchase_tables.dart:37-109`): `name, phone?, address?, taxId, isCustomer, isSupplier, balance, creditLimit, priceLevel, branchIds (CSV), isActive, deletedAt, globalId…` — **لا `phone2` ولا `notes` ولا `mergedInto`**. v190 أضاف `system_role` (العميل النقدي).
- البحث: `IPartiesRepository.searchParties(query)` (`domain/repositories/parties_repository.dart:39`؛ تنفيذ `party_profile_dao.dart:376`)، `searchCustomerByPhone(phone)` (:86؛ `database_misc_dao_methods.dart:316`)، `watchCustomersForBranches` (:29).
- حوار الإضافة: `showAddPartyDialogPicpos(context, ref, {initialType})` (`parties_picpos/dialogs/add_party_dialog_picpos.dart:54-58`, 29,362 بايت) **يرجع `void`** ويغلق بـ`Navigator.pop(context)` (:316) — لا يُعيد الطرف المُنشأ.
- منتقيات موجودة: `PartySearchableDropdown` (`widgets/searchable_dropdown.dart:402`)، `_PartyPickerDialog` خاص في `party_statement_picpos_screen.dart:670`، POS: `PosCustomerSelectionDialog` → `CustomerSelectorV2` (`pos/widgets/pos_customer_selection_dialog.dart:31`).
- ملف العميل: `PartyStatementPicposScreen` بتبويبات `_customerTabs` (`party_statement_tabs_picpos.dart:200-231`: ledger, aging, match, papers, profile) و`loadTab(tab.id)` (:240) — نقطة إدراج تبويب «الحجوزات».

---

## B. قرارات التصميم

### B.8 — إدارة قاعة المطعم + حجوزات الطاولات

**النمط المرجعي (ما تفعله أنظمة POS الرائدة للمطاعم — Toast/Lightspeed/Square for Restaurants/SevenRooms/OpenTable):** خريطة قاعة حيّة بألوان الحالة + **مؤقّت** منذ الإشغال، أقسام/مناطق كتبويبات، لوحة أفعال سياقية للطاولة المختارة (one-tap)، شارة حجز قادم مع عدّ تنازلي، خط زمني يومي (صفوف الطاولات × خانات 15/30 دقيقة)، منع التداخل بمدّة الجلوس (turn time)، تعامل مع التأخر/عدم الحضور، قائمة انتظار walk-in، وفحص الحجم مقابل السعة.

**القرار الواحد: «Floor Board» — عرضان لمصدر حقيقة واحد + «Reservations Timeline».**

1. **العرض الافتراضي يبقى الخريطة (`FloorPlanDesigner` للقراءة)** لمن صمّم قاعته، و**الشبكة تُعاد صياغتها كـ«لوحة مجمَّعة بالأقسام»** (section groups) للمنشآت التي لا تصمّم خريطة. كلاهما يعرض **كل الطاولات دائمًا**؛ فلتر الحالة = **تمييز/تخفيت** (`Opacity 0.35` + حدّ مُبرَز) لا إخفاء.
2. **بطاقة الطاولة الموحّدة** `TableTile` (ملف جديد): الاسم، شريحة القسم، شريحة الحالة **لون+أيقونة+نص** من tokens (`Theme.colorScheme` + `StatusPalette` جديدة)، سعة/عدد الضيوف، مؤقّت منذ `lastStatusAt`، المبلغ المفتوح، شارة «حجز بعد 25 د» عند وجود حجز خلال نافذة `reservationHoldMinutes` (افتراضي 30)، أيقونة تنبيه عند تأخر الحجز.
3. **لوحة الأفعال السياقية**: سطح المكتب ≥ 1100px: لوحة جانبية 280px (الطاولة المختارة: رأس بالحالة + 8 أفعال موجودة في `railActions` + «حجوزات الطاولة اليوم»)؛ أضيق: شريط أفعال سفلي قابل للتمرير. الأفعال تمرّ **حصرًا** عبر `TableActionsRunner.run` (الصلاحية + السجل).
4. **الحجوزات**: توسيع `TableReservations` (لا جدول جديد — قرار المالك بالاستقلال عن `Bookings` يبقى) بأعمدة: `party_id` (nullable→parties)، `duration_minutes` (default من إعداد `table_turn_minutes`=90)، `ends_at` (محسوب ومخزَّن للاستعلام)، `seated_at`، `source` (`walk_in|phone|pos`)، `deposit_amount` (default 0، اختياري)، `hold_until` (وقت انتهاء السماح بالتأخر = reservation_time + `late_grace_minutes` 15). **منع التداخل**: تحقق في الـDAO داخل transaction: لا حجز نشط (`pending|confirmed|seated`) لنفس `table_id` يتقاطع مع `[reservation_time, ends_at)`؛ وفحص `party_size <= capacity` مع تحذير قابل للتجاوز بصلاحية `tables_reserve`. **حالات**: الحالية + `late` مُشتقة (ليست عمودًا: الآن > reservation_time ولم يُجلَس) و`no_show` يُضبط يدويًا أو تلقائيًا بعد `hold_until` (زر «تحديد كعدم حضور» + مهمة دورية اختيارية).
5. **Timeline يومي** (تبويب داخل شاشة الطاولات «الحجوزات»): صفوف = الطاولات مجمَّعة بالقسم، أعمدة = خانات 30 د من ساعة الفتح إلى الإغلاق؛ كتلة لكل حجز بلون الحالة؛ نقر على خانة فارغة = حجز جديد مُسبق التعبئة؛ شريط «الآن». لا سحب/إفلات في النسخة الأولى (تعديل عبر الحوار) — السحب يُؤجَّل.
6. **قائمة انتظار walk-in**: جدول صغير `table_waitlist` (`party_id?, customer_name, phone, party_size, quoted_minutes, status(waiting|seated|left), created_at, seated_table_id?`) مع لوحة جانبية صغيرة؛ «إجلاس» يفتح الطاولة ويغلق السطر. (اختياري P4b — انظر §D).
7. **أداء 100+ طاولة**: استعلام واحد يراقب الطاولات مع الحجز القادم (`LEFT JOIN` على أقرب حجز نشط اليوم) بدل N مزوّدات؛ `GridView.builder`/`SliverGrid` بـ`RepaintBoundary` للبطاقة؛ المؤقتات بـ`Timer.periodic` واحد على مستوى الشاشة يبثّ `DateTime.now()` كل 30 ث (لا timer لكل بطاقة)؛ الخريطة بـ`CustomPainter` موجودة.
8. **إتاحة**: كل شريحة حالة تحمل نصًا وأيقونة (لا اعتماد على اللون)، `Semantics(label)` على البطاقة «طاولة 5، قسم الحديقة، مشغولة منذ 40 دقيقة»، تباين ≥ 3.0 في الوضعين (`dark_mode_guard`)، أهداف لمس ≥ 44px، تنقّل لوحة مفاتيح (أسهم بين البطاقات، Enter يفتح).

**Wireframe سطح المكتب (RTL، ≥ 1366):**
```
┌──────────────────────────────────────────────────────────────────────────────┐
│ إدارة الطاولات · كل المناطق        [+ إضافة طاولة] [الأقسام] [خريطة|شبكة|حجوزات] [⋯] │
├──────────────┬───────────────────────────────────────────────┬───────────────┤
│ لوحة الطاولة │  [متاحة 12] [مشغولة 7] [مدفوعة 2] [محجوزة 3] [خارج 1] (تمييز) │ الأقسام      │
│ ▸ طاولة 5    │  ── الصالة الرئيسية ──────────────────────────  │ ● الكل (25)   │
│ الحديقة      │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │ ○ الصالة (14) │
│ ● مشغولة 40د │  │ 1 ●  │ │ 2 ◐  │ │ 3 ■  │ │ 4 ◷  │           │ ○ الحديقة (8) │
│ 4/4 ضيوف     │  │صالة  │ │صالة  │ │صالة  │ │صالة  │           │ ○ VIP (3)     │
│ 185.00       │  │متاحة │ │مشغولة│ │مدفوعة│ │محجوزة│           │               │
│──────────────│  │ 4 👤 │ │40د 👤4│ │ 120  │ │ 18:30│           │ قائمة الانتظار│
│ [فتح الطاولة]│  └──────┘ └──────┘ └──────┘ └──────┘           │ أحمد ×4 12د   │
│ [نقل] [دمج]  │  ── الحديقة ─────────────────────────────────── │ [+ إضافة]     │
│ [تقسيم][طباعة]│ ...                                            │               │
│ [حجز] [حالة] │                                                │               │
│ [إغلاق]      │                                                │               │
│ حجوزات اليوم │                                                │               │
│ 18:30 سارة ×2│                                                │               │
└──────────────┴───────────────────────────────────────────────┴───────────────┘
```
**تبويب الحجوزات (Timeline):**
```
│ اليوم ◂ 18 أكتوبر ▸   [+ حجز جديد]   الآن 17:42 ▼                     │
│ الطاولة │12:00│12:30│13:00│…│17:30│18:00│18:30│19:00│19:30│20:00│     │
│ صالة 1  │     │█ علي ×2 (مؤكد)│    │     │     │     │                 │
│ صالة 4  │     │     │     │   │     │     │█ سارة ×2 ━━━━━│           │
│ حديقة 2 │     │     │     │   │ ▒ متأخر: محمد ×6 │     │               │
```
**ضيق (< 1100px / تابلت):** اللوحة الجانبية تختفي؛ الأقسام تبويبات أفقية أعلى الشبكة؛ اختيار بطاقة يفتح **شريط أفعال سفليًا** (bottom sheet ثابت 72px: الأفعال المتاحة للحالة فقط + «المزيد»).

**البدائل المرفوضة:** (أ) دمج حجوزات الطاولات في `Bookings` — مرفوض: قرار المالك موثّق، ونموذج Bookings يدور حول خدمة/مورد لا مكان. (ب) خريطة فقط بلا شبكة — مرفوض: أكثر المقاهي الصغيرة لن تصمّم قاعة. (ج) سحب/إفلات في الـTimeline من اليوم الأول — مؤجَّل: كلفة اختبار عالية مقابل قيمة أقل من منع التداخل والشارات. (د) جدول حجوزات جديد `table_reservations_v2` — مرفوض: إضافة أعمدة nullable أبسط ومتوافقة مع المزامنة.

### B.9 — الخدمة = صنف، والفوترة تلقائية من الحجز

**القرار:**
1. **عند حفظ خدمة جديدة** في المحرّر: إن لم يُختَر صنف يُنشأ صنف تلقائيًا في نفس الـtransaction: `productType='service'`, `trackInventory=false`, `isActive=true`, `salePrice=price`, `taxRate` من حقل جديد في المحرّر (افتراضي من إعدادات الضريبة), `unitId` = وحدة «خدمة» (تُبذر إن غابت)، `categoryId` = فئة «خدمات» (تُبذر)، باركود فارغ. يُكتب `BookingServices.productId`. **تعديل سعر الخدمة يحدّث سعر الصنف** (اتجاه واحد: الخدمة ⇒ الصنف). يُضاف مفتاح **isActive** في المحرّر والقائمة (يعطّل الصنف المرتبط معه).
2. **الفوترة التلقائية**: خدمة جديدة `BookingBillingService.issueInvoice({bookingId, paymentMethod, paidAmount, cash/bank/click + safeIds, userId})` في `lib/services/booking_billing_service.dart` تبني `SaleRequest` ببند واحد من صنف الخدمة (الكمية 1، السعر من الخدمة وقت الحجز، الضريبة من الصنف) و`customerId = booking.partyId` (أو `adhocCustomerName/Phone` لضيف بلا طرف — عندها **لا عربون**)، `globalId` و`idempotencyKey = 'booking:<booking.globalId>'`، `branchId` من الحجز، ثم `completeSaleUseCase.execute`، ثم `applyBookingDepositToInvoice` الموجود، ثم `setBookingStatus(completed)`، وتُسجَّل العملية في سجل العمليات بـ`entityType: 'booking'`، وتُستدعى `eInvoiceAutoSubmitter.submitSaleInvoice` كما في POS.
3. **Idempotency**: `Bookings.invoiceId != null` ⇒ رفض مبكّر برسالة «مفوتَر مسبقًا» مع زر «عرض الفاتورة»؛ و`idempotencyKey` الفريد على `sales_invoices` حاجز ثانٍ ضد النقر المزدوج/الإعادة بعد عطل.
4. **عربون/دفع جزئي**: الحوار يعرض السعر، العربون المحتجز، المتبقي؛ `paidAmount` الافتراضي = المتبقي؛ اختيار `credit` مسموح فقط لطرف مسجَّل وبصلاحية `pos_payment_credit` الموجودة؛ `multiple` عبر الحقول الثلاثة.
5. **إلغاء بعد الفوترة**: لا حذف؛ زر «مرتجع» يفتح مسار المرتجعات الموجود (`isReturn` في `SaleRequest`) مرجعًا للفاتورة، وقرار العربون (`refunded|forfeited`) يبقى كما في `BookingActionsService.cancel`.
6. **حوار «تفويتر» الحالي** يُستبدل بحوار «إصدار الفاتورة» (طريقة الدفع + المبالغ + زر ثانوي «فتح في نقطة البيع لإضافة أصناف» يحافظ على المسار القديم للحالات المركّبة).
7. **الصلاحيات**: كود جديد `bookings_invoice` (فئة `bookings`) للزر + إعادة استعمال `sales_create` في الخدمة (`ensurePermission` قبل البناء). يُضاف في `masterList` و`categoryNames` والبذرة ومصفوفة المنح الافتراضية.

**البدائل المرفوضة:** (أ) إبقاء التسليم إلى POS وإصلاح تعبئة السلة فقط — يحلّ نصف الشكوى ويبقي 3 نقرات وخطأ اختيار عميل. (ب) إنشاء الفاتورة مباشرة بـDAO خاص متجاوزًا الـOrchestrator — مرفوض: يكسر «الدفتر هو الحقيقة» (القيود، الخزينة، الفوترة الإلكترونية، `journal_balance_single_rule`). (ج) جعل الخدمة هي الصنف (حذف `BookingServices`) — مرفوض: المدّة/الـbuffer/الألوان/الموارد حقول حجز لا صنف، والترحيل مكلف.

### B.10 — عملاء الحجوزات = أطراف النظام

**القرار:**
1. **المرجع المباشر**: `Bookings.partyId` (موجود) يُلزَم ضبطه من الواجهة؛ `TableReservations.party_id` يُضاف. تبقى `customerName/customerPhone` **لقطة (snapshot)** للعرض والطباعة والـwalk-in؛ قاعدة: إن وُجد `partyId` فالعرض من الطرف الحيّ مع fallback إلى اللقطة.
2. **مكوّن موحّد** `CustomerPickerField` (`lib/presentation/shared_widgets/customer_picker/`): حقل بحث واحد (اسم/هاتف/كود) بـdebounce 250ms على `searchParties` + `searchCustomerByPhone` (عند إدخال ≥ 7 أرقام)، نتائج بلوحة منسدلة بالأسهم/Enter، عنصر أخير دائم «+ عميل جديد: "النص المكتوب"» يفتح الإضافة السريعة، وبعد الاختيار **بطاقة العميل**: الهاتف، العنوان، الرصيد مع شارة «عليه دين/حد ائتمان»، آخر 3 زيارات (حجوزات + فواتير) وزر «الملف الكامل». وضع «ضيف بلا تسجيل» يُبقي الاسم/الهاتف نصًّا (`partyId=null`) مع زر لاحق «ترقية إلى عميل».
3. **الإضافة السريعة**: تعديل `showAddPartyDialogPicpos` ليُرجع `Future<int?>` (id الطرف المُنشأ؛ تغيير سطرين: نوع الإرجاع و`Navigator.pop(context, id)`) + معامل اختياري `initialName/initialPhone`؛ **منع التكرار بالهاتف**: قبل الإدراج، `searchCustomerByPhone(normalized)`؛ عند التطابق يُعرض «هذا الرقم مسجَّل باسم X — استخدامه؟ / إنشاء على أي حال (بصلاحية `customers_add`)». التطبيع في helper خالص `normalizePhone` (أرقام فقط، إزالة `+`/`00`/مفاتيح الدولة 20/962 وصفر البداية) مع اختبار وحدة.
4. **الترحيل (v196)**: أعمدة nullable + فهارس؛ ثم **backfill في الإقلاع التالي غير العميل** (نمط `backfillHrCoreData`): لكل حجز/حجز طاولة بـ`party_id IS NULL` وهاتف غير فارغ: مطابقة بالهاتف المطبَّع على أطراف نشطة `isCustomer=1` → ضبط `party_id`. **لا إنشاء أطراف تلقائي** للمتبقّي (يبقى ضيفًا بلقطته — صفر فقدان بيانات، صفر أطراف وهمية)؛ تقرير عدّاد في السجل. (الخيار البديل في §D.)
5. **حالات الحافة**: هاتف مكرَّر لعدّة أطراف → عرض الكل والاختيار اليدوي؛ طرف محذوف (`deletedAt`) → البطاقة تعرض «عميل محذوف» واللقطة تبقى، ولا يُسمح باختياره لحجز جديد؛ لا يوجد دمج أطراف في النظام (لا `mergedInto`) — خارج النطاق؛ نطاق الفرع: البحث عبر `watchCustomersForBranches(branchScope)` فلا يرى المستخدم أطراف فروع أخرى؛ الخصوصية: الهاتف يُعرض كاملًا لمن يملك `customers_view`، وإلا `PermissionMaskedText`.
6. **سجل العميل**: تبويب `reservations` جديد في `_customerTabs` يعرض حجوزات الخدمات وحجوزات الطاولات (UNION مرتَّب تنازليًا) بالحالة والمبلغ ورقم الفاتورة.

**البدائل المرفوضة:** (أ) إنشاء طرف لكل حجز تلقائيًا في الترحيل — يلوّث قائمة العملاء بأسماء ناقصة ويعطّل البحث. (ب) حذف أعمدة اللقطة بعد الربط — يكسر walk-in والتاريخ عند تعديل اسم الطرف. (ج) إعادة استعمال `PosCustomerSelectionDialog` كما هو — مصمَّم للسلة (يكتب `cart.selectedCustomerId`) ولا يعرض بطاقة معلومات.

---

## C. خطة التنفيذ المرحلية

**ترتيب التنفيذ:** P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7. **التوازي الممكن (نطاقات ملفات منفصلة):** {P1} ∥ {P2} ∥ {P7-desktop}؛ بعد P3: {P4} ∥ {P6}؛ P5 بعد P4. أي مرحلة تمسّ `database.dart`/`epoch_3_v196_*.dart`/`database.g.dart` **تسلسلية** (P3 ثم P4 ثم P6 كلٌّ برقم ترحيل متتالٍ 196، 197، 198 — المنفّذ يقرأ `schemaVersion` فعليًا قبل الكتابة).

**قواعد عامة لكل مرحلة:** نصوص عبر `tr('نص عربي')` + مفتاح في `assets/i18n/en.json` (`i18n_coverage_test`)؛ ألوان من `Theme.of(context).colorScheme`/tokens (`dark_mode_guard_test`)؛ ملفات جديدة ≤ 30KB؛ الملفات التالية **ratcheted ولا تنمو**: `table_operations.dart`, `tables_dao.dart`, `bookings_dao.dart`, `auth_providers.dart`, `sales_transaction_orchestrator.dart`, `floor_plan_designer_picpos_screen.dart`, `floor_plan_canvas_picpos.dart`, `users_management_screen.dart`, `users_management_picpos_screen.dart`, `linked_devices_section.dart`, `party_statement_picpos_screen.dart`, `sales_purchase_tables.dart`, `split_table_dialog.dart` — أي إضافة إليها تُكتب في **ملف جديد** (extension/part/widget) ويُستبدل الكود القديم بنداء أقصر؛ وإن أمكن تقليصها شغّل `dart run tool/update_file_size_baseline.dart`.

### P0 — بذرة الترحيل والمقاييس (نصف يوم، تسلسلي)
- **الهدف:** إنشاء ملف جزء الترحيل الجديد ليبدأ منه P3/P4/P6 دون تعارض، وقياس الـbaseline.
- **ملفات:** جديد `lib/data/database/migrations/epoch_3_v196_v205.dart` (`part of '../database.dart';` + `_migrateEpoch3V196ToV205(m, from)` فارغ)، استدعاؤه في نهاية `epoch_3.dart:18`، `part` في `database.dart`. سطر في `database_schema_history.dart`.
- **اختبارات:** `flutter test test/structural/migration_numbering_test.dart test/structural/file_size_ratchet_test.dart`.

### P1 — إصلاحات سريعة 4، 5، 6، 7 (2–3 أيام، يوازي P2/P7)
- **الهدف:** رأس لا يقصّ، رجوع من المصمّم، القسم على البطاقة، كل الطاولات ظاهرة دائمًا.
- **ملفات:**
  - جديد `lib/presentation/picpos_shell/picpos_header_actions.dart`: `PicPosHeaderAction({label, icon, onPressed, priority, tooltip})` + ودجت `PicPosHeaderActionsBar(actions)` تستعمل `LayoutBuilder` وتقيس عرض الأزرار (تقدير `TextPainter` + padding ثابت) وتنقل الأقل أولوية إلى `PopupMenuButton` «⋯» عندما لا يتسع العرض. `picpos_page_header.dart` (8KB، غير ratcheted): إضافة معامل اختياري `actionsBar` يُستخدم بدل `SingleChildScrollView`، وتغيير `Flexible(flex: 28)` إلى `ConstrainedBox(minWidth: 160)` للعنوان؛ السلوك القديم يبقى لمن لم يمرّر `actionsBar`.
  - `tables_picpos_screen.dart` (21.9KB): تحويل الأزرار الستة إلى `PicPosHeaderAction` (أولوية: إضافة طاولة = 1، تبديل العرض = 2، كل المناطق = 3، الأقسام = 4، المصمم = 5).
  - **رجوع المصمّم:** `PicPosScreenScaffold`/`PicPosPageHeader` معامل جديد `onBack: VoidCallback?` (يرسم السهم حين لا يستطيع `Navigator.canPop`). في `floor_plan_designer_picpos_screen.dart` (ratcheted!) — استبدال سطر `PicPosScreenScaffold(` بتمرير `onBack: () => _leave(ref)` حيث `_leave` تُكتب في **ملف جديد** `floor_plan_picpos/screens/floor_plan_designer_navigation.dart` كـextension على الـState: إن `_dirty` → `_confirmDiscard()` ثم `screenNavigationProvider.notifier.open(ScreenId.tables.navigationIndex)` (أو `close` للتبويب الحالي إن وفّرها `screen_tabs`، يتحقق المنفّذ في `lib/presentation/shell/`). إضافة `PopScope(canPop: !_dirty, onPopInvokedWithResult: …)` حول الجسم. يُعوَّض النمو بنقل دوال مساعدة إلى الملف الجديد.
  - **القسم على البطاقة:** `table_card.dart` معامل اختياري `sectionName` يُرسم كشريحة صغيرة تحت الاسم؛ `tables_picpos_screen.dart` يبني `Map<int, String>` من `_sectionsProvider` ويمرّره. في وضع «كل المناطق» تُجمَّع الشبكة برؤوس أقسام (`SliverList` رأس + `SliverGrid`) — تمهيدًا لـP5.
  - **عدم الإخفاء:** `tables_picpos_screen.dart:308-310` تصبح `shown = tables` دائمًا و`highlightStatus = uiState.statusFilter`؛ `TableCard` معامل `dimmed: bool` (Opacity 0.35 + إزالة الظل)؛ `FloorPlanDesigner(statusFilter:)` تُفسَّر كتمييز في `screens/tables/floor_plan_designer.dart` (30.5KB، غير ratcheted لكن قريب من الحد — تعديل الفلترة فقط). شريط الحالات يعرض العدّ ويكتب «تمييز» بدل الإخفاء، مع زر «إلغاء التمييز».
  - **الحالة نص+أيقونة+لون:** `table_status_info.dart` يُضاف `IconData icon` لكل حالة؛ الألوان تنتقل إلى ملف جديد `lib/core/theme/table_status_palette.dart` يعيد ألوانًا من `ColorScheme`/extension ثيم (فاتح/داكن) — تُستبدل الـhex الثابتة.
- **i18n (en.json):** «تمييز الحالة»، «إلغاء التمييز»، «القسم: {p0}»، «تغييرات غير محفوظة — المغادرة؟»، «رجوع إلى الطاولات»، «خارج الخدمة» (تحقّق من الموجود).
- **اختبارات تُضاف:** `test/widget/picpos_header_actions_overflow_test.dart` (عرض 1125 و1366: `find.text('إضافة طاولة')` hitTestable، وعند 900 يظهر «⋯» ويحوي الأقل أولوية)؛ `test/widget/table_card_section_and_dim_test.dart`؛ `test/widget/tables_status_filter_highlights_not_hides_test.dart` (يحتاج fake للمزوّدات — تُبنى شاشة شبكة مصغّرة أو يُختبر منطق `visibleTables/highlight` كدالة خالصة في ملف جديد `tables_picpos/logic/tables_grid_model.dart`)؛ `test/widget/floor_plan_designer_back_guard_test.dart`؛ تحديث `test/widget/floor_plan_status_filter_test.dart` إن كان يفترض الإخفاء.
- **قبول:** عند 1125px كل الأزرار قابلة للنقر أو في «⋯»؛ المصمّم له سهم رجوع ويسأل عند التعديل؛ كل بطاقة تعرض القسم؛ الضغط على «محجوزة» يخفّت الباقي ولا يخفيه؛ لا ألوان hex جديدة في presentation.
- **مخاطر/تراجع:** تغيير `PicPosPageHeader` يمسّ كل الشاشات — لذلك opt-in عبر `actionsBar`. التراجع = عدم تمرير المعامل.
- **حراس يجب أن تبقى خضراء:** `dark_mode_guard_test`, `i18n_coverage_test`, `file_size_ratchet_test`, `picpos_screen_fork_guard_test`, `floor_plan_keeps_its_section_test`, `floor_plan_grid_step_guard_test`, `tables_action_rail_test`, `tables_status_rail_test`.
- **الأمر:** `flutter test test/widget/picpos_header_actions_overflow_test.dart test/widget/table_card_section_and_dim_test.dart test/widget/floor_plan_designer_back_guard_test.dart test/widget/floor_plan_status_filter_test.dart test/structural`.

### P2 — محلّل فتح الشاشة (2) + قائمة الشاشة الافتراضية (1) (3 أيام، يوازي P1)
- **الهدف:** قاعدة واحدة: `canOpenScreen(perms, screenId) = bypass || perms ∩ screenPermissionSet(screenId) ≠ ∅`، وقائمة افتراضية مشتقة منها.
- **ملفات:**
  - جديد `lib/core/permissions/screen_access_resolver.dart`: `const screenActionCodes = <ScreenId, List<String>>{}` (الأكواد الفعلية لكل شاشة: مثلًا `tables: [tables_view, tables_manage, tables_pos_access, tables_add_items, tables_checkout, tables_transfer, tables_cancel, tables_print_bill, tables_discount, tables_merge, tables_split_bill, tables_reserve]`, `bookings: [bookings_*]`, `products: [products_view, products_add, products_edit, …]`, `customers: [customers_view, customers_add, customers_edit, customers_delete, customer_message_send]`, `salesInvoices: [sales_view, sales_create, sales_edit, sales_delete, sales_return, …]`, …) + `Set<String> screenPermissionSet(ScreenId id)` = `{screenPermissionMap[id]} ∪ screenActionCodes[id]` + `bool canOpenScreen(Iterable<String> perms, ScreenId id, {required bool bypass})` + `bool isConditional(perms, code)`. **لا يُنقل** `screenPermissionMap` (يبقى حرفيًا في `auth_providers.dart` للحارس).
  - `auth_providers.dart` (**ratcheted 84,988**): تعديل سطرين فقط — في `userAllowedScreensProvider` :1301-1304 وفي `userNavItemsProvider` :1132-1136 استبدال `userPermissions.contains(x)` بـ`canOpenScreen(...)`؛ لتعويض البايتات انقل التعليقات الطويلة أو `kAllNavItemDefs`؟ لا — `kAllNavItemDefs` تقرؤه اختبارات؛ الأبسط: نقل كتلة `screenPermissionMap` **لا يجوز**. البديل: حذف تعليقات زائدة بمقدار الزيادة (~120 بايت) أو نقل `getWarehouseScopeForUser` (:1367-1394) إلى ملف جديد `lib/data/providers/auth_scope_providers.dart` مع `export`. ثم `dart run tool/update_file_size_baseline.dart`.
  - **قائمة الشاشة الافتراضية:** جديد `lib/presentation/shared_widgets/default_screen_dropdown.dart`: `DefaultScreenDropdown({roleId, value, onChanged})` يبني العناصر من `buildAllScreens()` (label/icon) ∩ `AppConfig.allowedScreenIds` ∩ `canOpenScreen(rolePerms, id)` ∩ ليس في قائمة استبعاد صغيرة `{floorPlanDesigner, helpCenter, syncConflicts}` (شاشات أدوات لا يُعقل الهبوط عليها)، مرتَّبة بترتيب الشريط الجانبي؛ القيمة المخزَّنة = `ScreenId.name` (مثل `'salesInvoices'`)؛ إن كانت القيمة المحفوظة غير موجودة تُعرض «غير محددة» (null) بدل assertion. جديد `lib/core/navigation/default_screen_resolver.dart`: `int resolveDefaultScreenIndex(String? stored, List<int> allowed)` — يفهم `ScreenId.name`، ثم المفاتيح القديمة الخمسة، ثم الرقم، ثم fallback؛ `app_main_screen_lifecycle.dart:61-96` يستدعيه. الثلاث نسخ (`users_management_picpos_screen.dart`, `users_management_screen.dart`, `user_management_widget.dart`) تستبدل الـDropdown اليدوي بالودجت المشترك (يقلّص الملفين الـratcheted).
  - **سدّ الأزرار بلا بوابة (الحد الأدنى):** `table_order_dialogs.dart` (دمج/إضافة أصناف/تحصيل → عبر `TableActionsRunner.run` أو `ensurePermission`)، `table_operations.dart:728-769,990-1019` (`tables_reserve`/`tables_cancel` — الإضافة بسطر `ensurePermission` مع حذف تعليقات مكافئة)، `bookings_picpos`: `PermissionGuard` على «حفظ الحجز» (`bookings_add`)، تغيير الحالة (`bookings_status`)، الإلغاء (`bookings_cancel`)، محرّرات الخدمات/الموارد (`bookings_services_manage/resources_manage`)، الإعدادات (`bookings_settings`)؛ ثم **حذفها من `knownUnenforced`** في `permission_enforcement_registry.dart` (السجل ينكمش — مطلوب). `screenPermissionMap[ScreenId.bookings]` يبقى `tables_view`؟ **لا**: يُغيَّر إلى `bookings_view` مع تحديث `kAllNavItemDefs` المقابل و`screen_permission_map_test` (التوقعات :23-34) ومصفوفة المنح `role_grant_matrix.dart` حتى يحتفظ الكاشير/المدير بالوصول.
  - **قاعدة الأمان:** فتح الشاشة بكود فعل فقط لا يمنح قراءة إضافية: الأعمدة الحساسة محكومة أصلًا (`products_cost_view`, `PermissionMaskedText`)، ونطاق الفرع يُحقن في الاستعلام؛ يضاف اختبار يؤكد أن مستخدمًا بـ`tables_reserve` فقط يفتح الطاولات لكن `PermissionGuard(showDisabled)` يعطّل بقية الأفعال.
- **i18n:** «غير محددة»، «الشاشة الافتراضية غير متاحة لهذا الدور»، تسميات موجودة أصلًا في الكتالوج.
- **اختبارات:** جديد `test/unit/screen_access_resolver_test.dart` (أي كود من المجموعة يفتح؛ bypass؛ كود من شاشة أخرى لا يفتح؛ كل كود في `screenActionCodes` موجود في `masterList`؛ كل شاشة في `screenPermissionMap` لها مجموعة تحتوي كودها)؛ `test/unit/default_screen_resolver_test.dart`؛ `test/widget/default_screen_dropdown_test.dart` (دور كاشير يرى ≥ 5 عناصر ولا يرى شاشات لا يملك أي كود لها؛ قيمة قديمة `'0'` لا تكسر)؛ تحديث `screen_permission_map_test.dart`, `permission_enforcement_coverage_test.dart` (إزالة من `knownUnenforced`)، `users_picpos_permission_test.dart`.
- **قبول:** مستخدم بـ`products_edit` فقط يرى «المنتجات» في الشريط ويفتحها؛ مستخدم بـ`bookings_add` فقط يفتح الحجوزات؛ القائمة الافتراضية للكاشير تعرض كل شاشاته المسموحة؛ لا شاشة في القائمة يفشل فتحها.
- **مخاطر:** توسيع الوصول يجب أن يرافقه تعطيل الأزرار — لذلك «سدّ الأزرار» جزء من نفس المرحلة لا لاحقًا. تراجع: `canOpenScreen` يقبل علمًا `strict` يعيد السلوك القديم.
- **حراس:** `allowed_screens_can_render_test`, `screen_permission_map_test`, `permission_enforcement_coverage_test`, `picpos_permission_parity_test`, `picpos_respects_conditional_permission_test`, `guarded_sections_have_real_gates_test`, `screen_tabs_are_wired_test`, `file_size_ratchet_test`.
- **الأمر:** `flutter test test/unit/screen_access_resolver_test.dart test/unit/default_screen_resolver_test.dart test/widget/default_screen_dropdown_test.dart test/unit/screen_permission_map_test.dart test/unit/permission_enforcement_coverage_test.dart test/structural`.

### P3 — نموذج العملاء + منتقي العميل (10) (4 أيام، تسلسلي قبل P4/P6)
- **الهدف:** `partyId` كمرجع مباشر في الحجزين، منتقٍ موحّد، إضافة سريعة بمنع التكرار، backfill آمن، تبويب في ملف العميل.
- **DB (v196)** في `epoch_3_v196_v205.dart`: `_safeMigrate('v196 reservation parties', ensureReservationPartiesSchema)` حيث الدالة في ملف جديد `lib/data/database/reservation_parties_schema.dart` (`part of 'database.dart'`): `ALTER TABLE table_reservations ADD COLUMN party_id INTEGER REFERENCES parties(id)` (idempotent عبر فحص `pragma table_info`)، فهرس `idx_table_reservations_party`، فهرس `idx_bookings_party` إن غاب. **لا `m.alterTable`** (الجدولان مُزامنان — `alter_table_sync_columns_guard_test`). Drift: إضافة `IntColumn get partyId => integer().nullable().references(Parties, #id)()` في `restaurant_tables.dart` + إعادة توليد `database.g.dart`. PostgreSQL parity: `database_pg_create.dart`/`database_pg_parity.dart`. مزامنة: العمود يُلتقط تلقائيًا بـ`sync_column_membership_guard_test` — راجع قائمة الأعمدة في استراتيجية مزامنة الطاولات إن وُجدت (`lib/services/sync/strategies/`). ويب: لا تغيير في `WebTablePolicy` إلا إن كان الجدول مسموحًا أصلًا.
- **Backfill**: ملف جديد `lib/data/database/reservation_parties_backfill.dart` (`backfillReservationParties()`) يُستدعى من `database_startup.dart` مرة واحدة (علم إعداد `reservation_parties_backfill_done`) على غير العميل؛ المطابقة بـ`normalizePhone` (SQL: مقارنة على آخر 9 أرقام `substr(replace(replace(phone,' ',''),'+',''), -9)` لتجنّب جلب كل الأطراف)؛ يسجّل العدّ في `app_log`.
- **Dart:** جديد `lib/core/utils/phone_normalizer.dart` (`normalizePhone`, `phoneTail9`). جديد `lib/presentation/shared_widgets/customer_picker/customer_picker_field.dart` (+ `customer_picker_card.dart`, `customer_picker_results.dart` إن قارب 30KB) بالمواصفة B.10؛ مزوّد `customerPickerSearchProvider.family(query)` في ملف جديد `lib/data/providers/customer_picker_providers.dart` (يستخدم `partiesRepositoryProvider.searchParties` + `searchCustomerByPhone` + `branchScopeProvider`). `add_party_dialog_picpos.dart`: الإرجاع `Future<int?>` + `initialName/initialPhone` + فحص التكرار قبل الإدراج (إن قارب 30KB انقل فحص التكرار إلى `party_phone_dedupe.dart` جديد). `new_booking_panel.dart:259-270`: استبدال حقلَي الاسم/الهاتف بـ`CustomerPickerField` وتمرير `partyId` إلى `BookingActionsService.create`. حجز الطاولة في `table_operations.dart:990-1019` (ratcheted): حوار الحجز ينتقل إلى ملف جديد `screens/tables/table_reservation_dialog.dart` (نقل بحت + المنتقي) ويُستبدل في الأصل بنداء — يقلّص الملف. `IRestaurantRepository.createReservation` يأخذ `partyId` اختياريًا؛ `tables_dao.dart` (ratcheted): الإضافة في extension جديدة `daos/table_reservations_dao.dart` (`part`) وتُنقل إليها دوال الحجوزات الموجودة :589-713 (نقل بحت) — يقلّص الأصل.
- **ملف العميل:** `party_statement_tabs_picpos.dart` (17KB): إضافة `_StatementTab('reservations', 'الحجوزات', Icons.event_available, …)`؛ المحتوى في ملف جديد `party_statement_picpos/widgets/party_reservations_tab.dart` بمزوّد `partyReservationsProvider.family(partyId)` (UNION من `bookings` و`table_reservations`).
- **الصلاحيات:** المنتقي يحترم `customers_view` (البحث) و`customers_add` (الإضافة السريعة؛ زر معطَّل بـ`showDisabled` دونها).
- **i18n:** «ابحث بالاسم أو الهاتف»، «+ عميل جديد: {p0}»، «ضيف بلا تسجيل»، «ترقية إلى عميل»، «هذا الرقم مسجَّل باسم {p0}»، «استخدام العميل الموجود»، «إنشاء على أي حال»، «آخر الزيارات»، «الرصيد»، «عليه دين»، «عميل محذوف»، «الحجوزات»، «لا حجوزات سابقة».
- **اختبارات:** `test/unit/phone_normalizer_test.dart`؛ `test/integration/v196_reservation_parties_migration_test.dart` (قاعدة v195 → 196، أعمدة موجودة، backfill يطابق بالهاتف ولا يُنشئ أطرافًا، اللقطة تبقى)؛ `test/unit/table_reservations_dao_test.dart`؛ `test/widget/customer_picker_field_test.dart` (بحث، أسهم/Enter، عنصر «عميل جديد»، بطاقة العميل، وضع ضيف)؛ `test/widget/add_party_dialog_returns_id_test.dart`؛ `test/widget/party_reservations_tab_test.dart`؛ تحديث `picpos_booking_panels_test.dart`, `booking_actions_service_test.dart`.
- **قبول:** حجز جديد (خدمة أو طاولة) يُنشئ/يختار طرفًا ويُخزَّن `partyId`؛ الحجوزات القديمة ذات الهاتف المطابق تُربط؛ لا صف يفقد اسمه/هاتفه؛ ملف العميل يعرض تبويب الحجوزات.
- **مخاطر:** backfill على قاعدة كبيرة — يعمل بدفعات 500 وفي معاملة لكل دفعة؛ تراجع: الأعمدة nullable ولا يعتمد عليها أي مسار قديم.
- **حراس:** `migration_numbering_test`, `alter_table_sync_columns_guard_test`, `sync_coverage_guard_test`, `sync_column_membership_guard_test`, `pg_schema_parity_static_test`, `unsynced_tables_have_no_writer_test`, `file_size_ratchet_test`, `i18n_coverage_test`, `dark_mode_guard_test`, `picpos_permission_parity_test`.
- **الأمر:** `flutter test test/unit/phone_normalizer_test.dart test/integration/v196_reservation_parties_migration_test.dart test/unit/table_reservations_dao_test.dart test/widget/customer_picker_field_test.dart test/widget/add_party_dialog_returns_id_test.dart test/widget/party_reservations_tab_test.dart test/structural test/unit/pg_schema_parity_static_test.dart`.

### P4 — محرّك حجوزات الطاولات + Timeline (8 جزء؛ يعتمد على P3) (5 أيام)
- **DB (v197)**: `_safeMigrate('v197 table reservation engine', ensureTableReservationEngineSchema)` في ملف جديد `table_reservation_engine_schema.dart`: أعمدة على `table_reservations`: `duration_minutes INTEGER NOT NULL DEFAULT 90`, `ends_at INTEGER` (backfill = reservation_time + duration), `seated_at INTEGER`, `source TEXT DEFAULT 'phone'`, `deposit_amount REAL NOT NULL DEFAULT 0`, `hold_until INTEGER`؛ فهرس `(table_id, reservation_time, status)`. جدول جديد `table_waitlist` (P4b، اختياري) بنمط SQL خام + Drift class في ملف جديد `tables/table_waitlist_tables.dart`، مزامنة: إضافته إلى `pullTables`, `_syncPullTables`, `_syncHardenedTables` وpg_create. إعدادات: مفاتيح `table_turn_minutes`, `table_late_grace_minutes`, `table_reservation_hold_minutes` في إعدادات الطاولات.
- **Dart:** `daos/table_reservations_dao.dart` (من P3): `createReservationChecked` (transaction + فحص التداخل + السعة)، `watchReservationsForDay(date, sectionId?)`, `watchNextReservationPerTable(date)`, `markNoShow`, `seatReservation(reservationId, tableId)` يضبط `seated_at` ويحدّث حالة الطاولة إلى `reserved→occupied`. خدمة جديدة `lib/services/table_reservation_service.dart` (الصلاحيات `tables_reserve`/`tables_cancel` + سجل العمليات `entityType: 'table_reservation'` + استثناءات `ReservationConflict`, `CapacityExceeded`). واجهة: جديد `tables_picpos/screens/tables_reservations_timeline.dart` (+ `widgets/reservation_block.dart`, `widgets/timeline_grid_painter.dart` بـ`CustomPainter`)، حوار الحجز من P3 يُوسَّع (المدّة، المصدر، العربون اختياري، تحذير السعة)، شارة الحجز القادم على `TableCard`/`TableTile` بعدّ تنازلي (من بثّ الدقيقة المشترك). مهمة no-show تلقائية: `Timer.periodic` 5 دقائق في الخدمة خلف إعداد `table_auto_no_show` (افتراضي off).
- **الصلاحيات:** إعادة استعمال `tables_reserve`, `tables_cancel`, `tables_manage` (الإعدادات)؛ لا أكواد جديدة. سجل العمليات يُكتب من الخدمة.
- **i18n:** «الخط الزمني»، «حجز جديد»، «المدّة (دقيقة)»، «تعارض مع حجز آخر على هذه الطاولة»، «عدد الضيوف أكبر من سعة الطاولة ({p0})»، «متأخر»، «لم يحضر»، «تحديد كعدم حضور»، «إجلاس»، «الحجز القادم بعد {p0} د»، «قائمة الانتظار»، «الوقت المتوقع {p0} د»، «غادر».
- **اختبارات:** `test/unit/table_reservation_overlap_test.dart` (تداخل/عدم تداخل/الحدود/الحالات الملغاة لا تحجب)، `test/unit/table_reservation_service_test.dart` (صلاحية، سجل، no-show)، `test/integration/v197_table_reservation_engine_migration_test.dart` (backfill `ends_at`)، `test/widget/tables_reservations_timeline_test.dart` (كتل في الخانات الصحيحة، نقر خانة فارغة)، `test/widget/table_card_reservation_badge_test.dart`.
- **قبول:** لا يمكن حفظ حجزين متقاطعين لنفس الطاولة؛ الطاولة تعرض شارة الحجز القادم؛ الـTimeline يعرض يوم العمل لكل الطاولات مجمَّعة بالقسم؛ 120 طاولة × 300 حجز تُرسم دون jank ملحوظ (اختبار أداء بسيط بوقت بناء الويدجت < 16ms/إطار في `test/perf` اختياري).
- **حراس:** كما P3 + `sync_coverage_guard_test` (إن أُضيف `table_waitlist`), `unsynced_tables_have_no_writer_test`, `api_routes_golden_test` (إن أُضيفت مسارات API للمزامنة).
- **الأمر:** `flutter test test/unit/table_reservation_overlap_test.dart test/unit/table_reservation_service_test.dart test/integration/v197_table_reservation_engine_migration_test.dart test/widget/tables_reservations_timeline_test.dart test/widget/table_card_reservation_badge_test.dart test/structural`.

### P5 — إعادة تصميم لوحة الطاولات (8) (5 أيام؛ بعد P4)
- **ملفات (كلها جديدة أو صغيرة):** `tables_picpos/widgets/table_tile.dart` (يحل محل استعمال `TableCard` في PicPos؛ `TableCard` يبقى لـUralCash)، `tables_picpos/widgets/table_context_panel.dart` (اللوحة الجانبية: رأس الطاولة + الأفعال من `railActions` + حجوزات اليوم للطاولة)، `tables_picpos/widgets/table_bottom_action_bar.dart` (الضيق)، `tables_picpos/widgets/section_tabs_strip.dart`، `tables_picpos/logic/tables_board_model.dart` (دوال خالصة: تجميع بالقسم، ترتيب، تمييز، العدّادات، اختيار التخطيط حسب العرض)، `tables_picpos/providers/tables_board_providers.dart` (استعلام واحد `watchTablesBoard(sectionId?)` = الطاولات + القسم + الطلب المفتوح + الحجز القادم عبر DAO جديد `daos/tables_board_dao.dart` بـ`customSelect`)، وبثّ الدقيقة `boardClockProvider`. `tables_picpos_screen.dart` يُعاد تركيبه على هذه الأجزاء ويضاف تبويب ثالث «الحجوزات» (من P4). `tables_action_rail.dart` يبقى ويُستعمل داخل `table_context_panel`.
- **ثيم:** `table_status_palette.dart` (P1) هو مصدر الألوان؛ `StatusChip` تستعمل `colorScheme.onX`.
- **إتاحة:** `Semantics` على كل `TableTile`، `FocusTraversalGroup` بالأسهم، اختصارات: `R` حجز، `O` فتح، `Esc` إلغاء الاختيار (تُوثَّق في «⋯ → اختصارات»).
- **i18n:** «الطاولة المختارة»، «لا طاولة مختارة — اختر طاولة من اللوحة»، «منذ {p0} د»، «{p0}/{p1} ضيوف»، «المزيد»، «اختصارات لوحة المفاتيح».
- **اختبارات:** `test/unit/tables_board_model_test.dart` (التجميع/التمييز/التخطيط حسب العرض)، `test/unit/tables_board_dao_test.dart` (استعلام واحد يُرجع الحجز القادم الصحيح)، `test/widget/table_tile_test.dart` (نص+أيقونة+لون، dimmed، شارة الحجز، Semantics)، `test/widget/table_context_panel_test.dart` (الأفعال المتاحة للحالة + تعطيل بلا صلاحية)، `test/widget/tables_board_narrow_layout_test.dart` (900px ⇒ شريط سفلي)، `test/structural/dark_mode_guard_test` يبقى أخضر.
- **قبول:** بمقارنة مع لقطة المالك (3): الحالات ظاهرة لكل الطاولات بنص وأيقونة، القسم على كل بطاقة، لوحة الأفعال تتفعّل بالاختيار، الأقسام تبويبات، الشاشة تعمل عند 1366×768 و1024 عرضًا بلا overflow.
- **مخاطر:** حجم `tables_picpos_screen.dart` — يجب أن ينقص لا يزيد بعد التفكيك. تراجع: علم إعداد `tables_board_v2` (افتراضي on) يعيد العرض القديم.
- **الأمر:** `flutter test test/unit/tables_board_model_test.dart test/unit/tables_board_dao_test.dart test/widget/table_tile_test.dart test/widget/table_context_panel_test.dart test/widget/tables_board_narrow_layout_test.dart test/structural`.

### P6 — الخدمات كأصناف + الفوترة التلقائية (9) (4 أيام؛ بعد P3، يوازي P4/P5)
- **DB (v198)**: `_safeMigrate('v198 booking billing', ensureBookingBillingSchema)` — بذر وحدة «خدمة» وفئة «خدمات» إن غابتا (idempotent بالاسم/`isSystemDefault`)؛ `booking_services.tax_rate REAL` (nullable، يُستخدم عند إنشاء الصنف)؛ backfill: لكل خدمة بلا `product_id` يُنشأ صنف خدمة مرتبط (`trackInventory=0`, `productType='service'`) — **قرار المالك في §D.3**؛ فهرس فريد جزئي على `sales_invoices.idempotency_key` إن لم يكن فريدًا (تحقق أولًا من `sales_purchase_tables.dart:412`).
- **Dart:** `bookings_dao.dart` (ratcheted): الإضافات في extension جديدة `daos/booking_billing_dao.dart` (`markBookingInvoiced`, `getBookingForBilling`)؛ `booking_catalog_editors.dart` (23KB): مفتاح `isActive`, حقل `taxRate`, وإنشاء الصنف عبر خدمة جديدة `lib/services/booking_service_catalog_service.dart` (`ensureProductForService(serviceId)` داخل transaction؛ تحديث السعر/الاسم/التفعيل للصنف المرتبط). خدمة جديدة `lib/services/booking_billing_service.dart` (B.9 §2–5) تستخدم `completeSaleUseCaseProvider` و`applyBookingDepositToInvoice` و`eInvoiceAutoSubmitterProvider` و`activityLog`. حوار جديد `bookings_picpos/widgets/booking_issue_invoice_dialog.dart` (يستبدل استدعاء `showBookingInvoiceDialog` في `bookings_picpos_screen.dart:180-190`؛ الملف القديم يبقى لزر «فتح في نقطة البيع» ويُصحَّح تعليقه). تعديل `checkout_controller.dart:296-315` غير مطلوب (المسار القديم يبقى صالحًا). `picpos_booking_view.dart` الفعل «تفويتر» → «إصدار فاتورة».
- **الصلاحيات:** كود جديد `bookings_invoice` ('إصدار فاتورة حجز', category `bookings`) في `permission_codes.dart` (آخر القوائم) + `masterList` + `categoryNames` موجود + `database_seeder_permissions.dart` + `role_grant_matrix.dart` (مدير/كاشير)؛ الخدمة تفحص `bookings_invoice` ثم `sales_create`، وطريقة `credit` تفحص `pos_payment_credit`. يُضاف `bookings_invoice` إلى اختبار `test/static/bookings_permission_registration_test.dart`.
- **i18n:** «إصدار فاتورة»، «مفوتَر مسبقًا — عرض الفاتورة»، «العربون المحتجز»، «المتبقي»، «طريقة الدفع»، «فتح في نقطة البيع لإضافة أصناف»، «الخدمة مفعّلة»، «نسبة الضريبة»، «أُنشئ الصنف {p0} تلقائيًا»، «لا يمكن البيع الآجل لضيف غير مسجَّل»، «صُدرت الفاتورة رقم {p0}».
- **اختبارات:** `test/unit/booking_service_catalog_service_test.dart` (إنشاء صنف خدمة غير متتبَّع، تحديث السعر، التعطيل)، `test/unit/booking_billing_service_test.dart` (فاتورة + قيد عبر الـOrchestrator الحقيقي على DB في الذاكرة، تطبيق العربون، idempotency: نداء ثانٍ يرمي ولا يُنشئ فاتورة ثانية، ضيف بلا طرف ⇒ adhoc بلا عربون، credit يُرفض للضيف)، `test/integration/v198_booking_billing_migration_test.dart`، `test/widget/booking_issue_invoice_dialog_test.dart`، تحديث `booking_invoicing_vs_plain_sale_test.dart`, `booking_catalog_writes_test.dart`, `booking_deposit_money_test.dart`.
- **قبول:** إضافة خدمة ⇒ صنف ظاهر في المنتجات نوع خدمة بلا مخزون بسعر/ضريبة/وحدة؛ «إصدار فاتورة» من الحجز يُنشئ فاتورة مبيعات وقيدًا ويحدّث الخزينة ويخصم العربون ويضبط الحالة «مكتمل» ورقم الفاتورة على الحجز؛ النقر مرتين لا يكرّر؛ الفوترة الإلكترونية تُستدعى كما في POS.
- **مخاطر:** `journal_balance_single_rule`/`safe_balance_single_write` — لا كتابة مباشرة في القيود أو الخزنة خارج الـOrchestrator. تراجع: إعداد `booking_auto_invoice` يعيد زر «تفويتر» القديم.
- **حراس:** `permission_enforcement_coverage_test`, `bookings_permission_registration_test`, `bookings_activity_category_parity_test`, `journal_balance_single_rule`, `safe_balance_single_write`, `mirror_write_dispatch_test`/`no_bare_client_write_submit_test` (إن مرّت الكتابة من عميل LAN عبر `ClientWriteInterceptor` — أضف `cwi_*` دالة إن لزم), `api_routes_golden_test` (إن أُضيف مسار).
- **الأمر:** `flutter test test/unit/booking_service_catalog_service_test.dart test/unit/booking_billing_service_test.dart test/integration/v198_booking_billing_migration_test.dart test/widget/booking_issue_invoice_dialog_test.dart test/unit/booking_invoicing_vs_plain_sale_test.dart test/static test/structural`.

### P7 — ربط الجوال بـQR (3) (سطح المكتب 3 أيام ∥ الجوال 4 أيام؛ نطاقات منفصلة)
- **P7-A سطح المكتب:** شاشة/قسم جديد «ربط جهاز جوال» في ملف جديد `lib/presentation/settings_picpos/screens/mobile_pairing_qr_panel.dart` (≤30KB) يُستدعى من `linked_devices_section.dart` (ratcheted: استبدال جسم `_pair()` :799-832 بنداء للملف الجديد يقلّصه) ومن `lan_pairing_dialog.dart` و`rep_pairing_flow.dart`: خطوات (1) اختيار نوع الجهاز (كاشير LAN / مشرف / مندوب)، (2) مؤشر تقدّم مع إلغاء لكل نداء سحابي، (3) `QrImageView` + الكود نصًّا + URL + عدّ تنازلي 10 دقائق + زر «رمز جديد»، (4) تعليمات: «الهاتف على نفس الشبكة — IP: …:8080». **Payload v2 موحّد:** `{"v":2,"kind":"lan|cloud","url":"http://192.168.1.10:8080","code":"ABCD2345","exp":1760000000,"fp":"<sha256 prefix>","link":"<desktop link id>"}` — **بلا `desktopSigningKey`** (يُنقل إلى استجابة `/manage/pair` بعد نجاح الكود؛ تغيير في `server/lib/src/http/admin_routes.dart` و`mobile_admin/lib/admin_session.dart`؛ يُوثَّق كإصلاح أمني). خدمة `lan_pairing_service.dart` (25.9KB): `qrPayload()` يُحدَّث إلى v2 ويضاف `kind`. إضافة مسار `GET /api/m1/info` (عام، يعيد `{name, version, fp, tls}`) في `api_routes_read.dart` + تحديث `test/golden/api_routes.txt`.
- **P7-B الجوال (ثلاثة تطبيقات):** حزمة مشتركة صغيرة `packages/picpos_api_client/lib/src/pairing_payload.dart` (`PairingPayload.parse(String)` v1/v2 + `isExpired`) + اختبار. شاشة ماسح مشتركة في `packages/picpos_ui/lib/src/pairing_qr_scanner.dart` تعتمد `mobile_scanner` (إضافته إلى `mobile_admin/pubspec.yaml` و`mobile_pos/pubspec.yaml`؛ `CAMERA` معلن أصلًا). Van: `pairing_screen.dart` — URL افتراضي **فارغ** مع آخر URL محفوظ، زر «مسح QR»، تعبئة تلقائية وإرسال، زر إلغاء يُلغي الطلب (`CancelableOperation`/token) ورسالة واضحة لكل خطأ (`url_not_allowed` ⇒ «الرابط يجب أن يبدأ بـhttps في الإصدار النهائي»). Admin: استبدال «لصق JSON» بالمسح + فحص البصمة من الـpayload (`fp`) قبل الطلب فلا حوار modal مفاجئ. Cashier (`mobile_pos`): تنفيذ الربط فعليًا: مسح QR نوع `lan` → `POST {url}/api/pair {pairingCode, deviceId, deviceName, deviceKind:'pos', branchId}` → تخزين التوكن في `picpos_device` secure storage → شاشة «متصل بـ{name}». سياسة URL: `url_policy.dart` يسمح cleartext في debug لكل النطاقات الخاصة (`10/8`, `172.16/12`, `192.168/16`)، وفي release يسمح HTTP **لـLAN فقط عندما `kind=lan` وبصمة الخادم مثبّتة** (TOFU على `fp`) — أو يبقى HTTPS-only مع تفعيل TLS الذاتي في `network_service.dart:800-814` وتوثيق ذلك (قرار §D.5). manifests: إضافة `network_security_config` بنطاقات LAN للـrelease إن اختير HTTP-LAN.
- **i18n (desktop en.json):** «ربط جهاز جوال»، «امسح الرمز من التطبيق»، «الرمز صالح لمدة {p0}»، «رمز جديد»، «الهاتف يجب أن يكون على نفس الشبكة»، «نوع الجهاز»، «كاشير (شبكة محلية)»، «مشرف»، «مندوب»، «جارٍ إنشاء الرمز…»، «إلغاء». (الجوال له نصوصه الخاصة بلا `tr`.)
- **اختبارات:** desktop `test/unit/lan_pairing_payload_v2_test.dart` (لا سرّ، انتهاء)، `test/widget/mobile_pairing_qr_panel_test.dart` (QR يُرسم، العدّ، الحالات)، تحديث `lan_pairing_dialog_test.dart`, `api_routes_golden_test.dart`؛ packages `pairing_payload_test.dart`, `url_policy_test`؛ mobile `mobile/test/pairing_screen_test.dart` (حالات: نجاح/انتهاء/رفض URL/إلغاء)، `mobile_pos/test/pairing_flow_test.dart` بـfake transport؛ server `admin_routes` (السرّ في الاستجابة لا في الكود).
- **قبول:** من سطح المكتب: زر واحد يعرض QR خلال < 2 ث مع تقدّم مرئي؛ الهاتف يمسح ويرتبط دون كتابة؛ كل خطأ له رسالة؛ لا تجمّد > 1 ث؛ تطبيق الكاشير يرتبط فعلًا.
- **ما لا يمكن التحقق منه هنا:** سلوك Android الفعلي (كاميرا، cleartext) — يحتاج جهازًا؛ يُدرج في checklist يدوي.
- **حراس:** `api_routes_golden_test`, `api_handler_perm_gate_grep_test`, `lan_pairing_security_test`, `check_no_secrets.ps1`, `file_size_ratchet_test`, `i18n_coverage_test`, `web_entry_scope_test` (لا تستورد الشاشة الجديدة من مسار الويب).
- **الأمر:** `flutter test test/unit/lan_pairing_payload_v2_test.dart test/widget/mobile_pairing_qr_panel_test.dart test/widget/lan_pairing_dialog_test.dart test/unit/api_routes_golden_test.dart test/unit/lan_pairing_security_test.dart` ثم `cd packages/picpos_api_client; flutter test` ثم `cd mobile; flutter test` و`cd mobile_admin; flutter test` و`cd mobile_pos; flutter test` ثم `cd server; dart test -j 1`.

### جدول التوازي والنطاقات
| عامل | المراحل | نطاق الملفات الحصري |
|---|---|---|
| W1 | P1 ثم P5 | `picpos_shell/picpos_header_actions.dart`, `picpos_page_header.dart`, `tables_picpos/**`, `screens/tables/widgets/**`, `floor_plan_picpos/**`, `core/theme/table_status_palette.dart` |
| W2 | P2 | `core/permissions/screen_access_resolver.dart`, `core/navigation/default_screen_resolver.dart`, `shared_widgets/default_screen_dropdown.dart`, `auth_providers.dart` (سطور محددة), `users_*`, `permission_enforcement_registry.dart`, `bookings_picpos/**` (بوابات فقط), `table_order_dialogs.dart` |
| W3 | P0 → P3 → P4 → P6 (تسلسلي؛ DB) | `migrations/epoch_3_v196_v205.dart`, `*_schema.dart` الجديدة, `tables/restaurant_tables.dart`, `daos/table_reservations_dao.dart`, `daos/booking_billing_dao.dart`, `services/table_reservation_service.dart`, `services/booking_*`, `shared_widgets/customer_picker/**`, `party_statement_picpos/**`, `new_booking_panel.dart`, `booking_catalog_editors.dart`, `database.g.dart` |
| W4 | P7 | `settings_picpos/screens/mobile_pairing_qr_panel.dart`, `linked_devices_section.dart`, `lan_pairing_*`, `rep_pairing_flow.dart`, `api_routes_read.dart`, `test/golden/api_routes.txt`, `packages/**`, `mobile*/**`, `server/**` |

**تعارض معروف يجب تنسيقه:** W2 وW3 كلاهما يلمس `bookings_picpos/widgets/new_booking_panel.dart` (W2 بوابة الزر، W3 المنتقي) — W2 ينفّذ أولًا سطر البوابة فقط؛ وW1 وW3 يلمسان `table_operations.dart` (W1 لا يلمسه؛ W3 ينقل حوار الحجز) — مقبول.

---

## D. المخاطر والأسئلة المفتوحة (مع الافتراضي الموصى به)

1. **الحجوزات القديمة بلا طرف مطابق:** تبقى ضيوفًا (لا إنشاء أطراف تلقائي) مع زر «ترقية». *الافتراضي: نعم (B.10 §4).* البديل: إنشاء طرف لكل هاتف فريد — يُفعَّل بعلم إعداد فقط إن طلبه المالك.
2. **فتح الشاشة بأي كود فعل:** هل تشمل القاعدة شاشات مالية حساسة (الخزينة/القيود) أم تُستثنى بقائمة `strictScreens`؟ *الافتراضي: القاعدة عامة، مع استثناء `settings`, `users`, `rolesAndPermissions` (تبقى على كودها الوحيد).*
3. **تحويل الخدمات الموجودة إلى أصناف في الترحيل (v198 backfill):** *الافتراضي: نعم، تلقائيًا، مع فئة «خدمات».* البديل: زر «إنشاء الصنف» يدوي لكل خدمة.
4. **قائمة انتظار walk-in (P4b):** *الافتراضي: تُنفَّذ (جدول صغير)*؛ يمكن تأجيلها دون أثر على بقية P4.
5. **نقل HTTP للكاشير على LAN في إصدار release:** *الافتراضي: TLS ذاتي على الخادم المضمَّن + تثبيت البصمة (TOFU) عبر `fp` في الـQR؛ لا cleartext في release.* البديل الأسرع: السماح بـcleartext للنطاقات الخاصة فقط (أضعف أمنيًا).
6. **`screenPermissionMap[bookings]` من `tables_view` إلى `bookings_view`:** قد يُفقد وصول أدوار مخصّصة لم تُمنح `bookings_view`. *الافتراضي: التغيير + ترحيل بيانات يمنح `bookings_view` لكل دور يملك `tables_view` (idempotent).*
7. **مدّة الجلوس الافتراضية وفترة سماح التأخر:** *الافتراضي 90 د / 15 د، قابلة للتعديل في إعدادات الطاولات.*
8. **العربون على حجز الطاولة:** *الافتراضي: حقل اختياري بلا قيد محاسبي في P4 (يُسجَّل كملاحظة مبلغ)؛ القيد المحاسبي (customer_advances) يُستعار من `createBooking` في مرحلة لاحقة إن طُلب.*

---

## E. استراتيجية الاختبار والتحقق

- **قبل كل مرحلة:** `flutter analyze lib/` و`flutter test test/structural` (لا أوامر `flutter` متوازية).
- **الحراس البنيوية المتأثرة مباشرة:** `file_size_ratchet_test` (P1, P2, P3, P5, P7 — الملفات الـratcheted المذكورة)، `i18n_coverage_test` (كل المراحل)، `dark_mode_guard_test` (P1, P5, P7)، `allowed_screens_can_render_test` + `screen_permission_map_test` + `permission_enforcement_coverage_test` + `picpos_permission_parity_test` (P2, P6)، `migration_numbering_test` + `alter_table_sync_columns_guard_test` + `sync_coverage_guard_test` + `sync_column_membership_guard_test` + `pg_schema_parity_static_test` + `unsynced_tables_have_no_writer_test` (P0, P3, P4, P6)، `api_routes_golden_test` + `api_handler_perm_gate_grep_test` (P7, وP6 إن أُضيف مسار)، `picpos_screen_fork_guard_test` + `screenconfig_builds_the_picpos_fork_test` (P5 إن أُضيفت شاشة)، `web_entry_scope_test` (P3 المنتقي قد يُستورد من الويب — لا يجوز سحب `TablePosScreen`)، `bookings_permission_registration_test` + `bookings_activity_category_parity_test` (P6)، `journal_balance_single_rule` + `safe_balance_single_write` (P6)، `guarded_sections_have_real_gates_test` (لا تُلمس `settingKey:`).
- **اختبارات ترحيل** من قاعدة v195 حقيقية لكل من v196/v197/v198 (`test/integration/`)، وتشغيل `ensureSchemaDefaults` كطبقة ثانية.
- **PostgreSQL:** `dart run scripts/run_pg_tests.dart` بعد P3/P4/P6 (parity للأعمدة/الجداول الجديدة).
- **بعد كل مرحلة:** `flutter test` كاملًا مرة واحدة على الأقل قبل الدمج، و`scripts/gate.sh` محليًا؛ CI يبقى 12 shard — إن تجاوزت قائمة المسارات 7500 حرف ارفع العدد.
- **التحقق بعين المالك (إلزامي — الدرس الموثّق في `2026-08-20-next-session-prompt-reservations-and-qr.md`):** بناء `build_picpos.bat` وتشغيل سيناريو: مستخدم كاشير بصلاحيات جزئية → القائمة الافتراضية → الطاولات عند 1366×768 و1125px → تمييز الحالة → حجز طاولة لعميل جديد ثم موجود → الخط الزمني → إضافة خدمة ⇒ صنف → إصدار فاتورة من حجز ⇒ فاتورة + قيد → ربط الهاتف بـQR (جهاز حقيقي). النتائج تُدوَّن في `docs/handoff/`.
- **حدود هذا التخطيط:** لم يُشغَّل أي أمر `flutter`؛ أحجام الملفات مقاسة بـ`Get-Item` وقت الكتابة؛ أرقام الأسطر قد تنزاح مع التعديلات — المنفّذ يعيد تحديد المواضع بـgrep قبل التحرير.


---

## F. قرارات المالك (2026-10-18) — تُلغي الافتراضيات المخالفة في القسم D

1. **الحجوزات القديمة بلا طرف:** يُنشأ عميل (party) لكل رقم هاتف فريد، **مع فلترة التكرار**: (أ) مطابقة الهاتف (بعد تطبيع الأرقام: إزالة المسافات والرموز وكود الدولة) مع عميل موجود ⇒ يُربط به ولا يُنشأ جديد؛ (ب) لا هاتف مطابق لكن الاسم مطابق تمامًا (بعد التطبيع) لعميل موجود **ولا هاتف له** ⇒ يُربط به ويُستكمل هاتفه؛ (ج) الاسم مطابق لكن هاتفه مختلف ⇒ يُنشأ عميل جديد **ولا يُدمج تلقائيًا** ويُسجَّل في تقرير «اشتباه تكرار» يراه المالك؛ (د) حجز بلا هاتف ⇒ يبقى ضيفًا مع زر «ترقية». الترحيل idempotent ولا يفقد أي بيانات (تبقى اللقطات النصية القديمة).
   - **توضيح (2026-10-23، تدقيق DATA-002):** مفتاح المطابقة يبقى الرقم الوطني بلا كود الدولة (القاعدة أعلاه كما هي). لكن **إذا حمل الرقمان كود دولة صريحاً (+/ 0) وكانا مختلفين فهما شخصان مختلفان** (+966 50… ≠ +971 50…)؛ الرقم المحلي (بلا كود) يطابق أيّاً منهما. المنفّذ في phoneCountryCode / samePhone (lib/core/utils/phone_normalizer.dart) وفي مجموعات eservation_parties_backfill.dart.
2. **فتح الشاشة بأي كود فعل:** موافق — القاعدة عامة مع استثناء `settings`, `users`, `rolesAndPermissions`.
3. **تحويل الخدمات الموجودة إلى أصناف تلقائيًا في الترحيل (فئة «خدمات»):** موافق.
4. **قائمة انتظار walk-in:** تُنفَّذ (P4b).
5. **ربط الكاشير على LAN:** TLS ذاتي التوقيع على الخادم المضمَّن + تثبيت البصمة (TOFU) عبر `fp` في الـQR؛ لا cleartext في release.
6. **`screenPermissionMap[bookings]` ← `bookings_view`:** موافق مع ترحيل يمنح `bookings_view` لكل دور يملك `tables_view` (idempotent).
7. **مدة الجلوس الافتراضية 90 دقيقة وسماح التأخر 15 دقيقة:** موافق، قابلة للتعديل في الإعدادات.
8. **العربون على حجز الطاولة — تغيير عن الافتراضي:** **العربون يُسجَّل كسند قبض لصالح العميل بقيد محاسبي حقيقي** (نقدية/بنك مدين ← سلفة عميل `customer_advances` دائنة على حساب العميل)، يُنشأ عبر خط سندات القبض الموجود (treasury voucher pipeline) وليس حقلًا ملاحظة. يُخصَم تلقائيًا من فاتورة الحجز/الطاولة عند الفوترة، ويُردّ أو يُحجز عند الإلغاء وفق إعداد صريح. **حجز بعربون يتطلب عميلًا مسجَّلًا (ليس ضيفًا)** — يُنشأ/يُختار قبل أخذ العربون. ينطبق نفس النموذج على عربون حجوزات الخدمات (يوجد مسار `createBooking` + `customer_advances` للاقتباس منه). يدخل ضمن P4 (محرك الحجوزات) وP6 (الفوترة التلقائية) وليس مرحلة لاحقة.

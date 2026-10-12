# تحليل: إلغاء فاتورة مبيعات بعد وجود مرتجع (void-after-return)

> حالة: مكتمل (تحليل قراءة فقط؛ لم يُعدَّل أي ملف شيفرة). الوسم [مؤكد] = مقروء من الكود، [استنتاج] = استدلال.

## 0. وصف العيب
`SalesActionsDao.voidSalesInvoice` لا يتحقق من وجود مرتجعات سابقة؛ يعيد كامل الكميات وكامل القيد والنقدية.
المصدر: `test/scenarios/sc_c_sales_return_void_test.dart:125-139` (skip).

## 1. الدالة نفسها — `lib/data/database/daos/sales_actions_dao.dart`
- [مؤكد] الحمايات الموجودة في `voidSalesInvoice` (السطر 23): الفاتورة غير موجودة → return (29)؛
  `status == 'voided'` → «الفاتورة ملغية بالفعل» (30-32)؛ صلاحية `voidPaidInvoice` للفواتير المدفوعة كليًا (37-45)؛
  فحص الفترة المالية (48). **لا فحص لـ `partial_return`/`returned` ولا لحركات مرتجع.**
- [مؤكد] يعيد المخزون بـ `item.quantity * quantityInBase` لكل سطر كاملًا (53-83)، وخامات BOM بكسر 1.0 (110-116)،
  ويعكس **كل** `safe_transactions` ذات `referenceType='sales_invoice'` (119-154) — حركات المرتجع مكتوبة بـ `'sales_return'`
  فلا تُمسّ، ويعكس `total - paid - rounding` من رصيد العميل (157-166) دون طرح ما قاصّه المرتجع،
  ويعكس قيد البيع الأصلي سطرًا بسطر (196-243) دون مسّ قيد المرتجع.

## 2. تمثيل المرتجع
### 2.1 مسار شاشة المرتجعات (standalone/server) — `returns_repository_impl.dart` `processSalesReturn` (131)
- [مؤكد] **لا يُنشأ مستند مستقل** في `sales_invoices`: المخزون `adjustStock(type:'return', referenceType:'sales_return', referenceId: invoice.id)` (407-421)،
  النقدية `safe_transactions(referenceType:'sales_return', referenceId: invoice.id, voucher SRET-n)` (531-545, 565-579)،
  القيد `autoPostSalesReturn(originalInvoice: invoice, returnEventId: SRET-n)` (650-670)،
  ثم تُعدَّل حالة الفاتورة الأصلية إلى `'returned'` أو `'partial_return'` (715-718).
### 2.2 مسار العميل (client mode) — نفس الدالة 203-352
- [مؤكد] يرسل `submitSalesReturn` للخادم مع `originalInvoiceId/GlobalId/Number`؛ الخادم ينشئ صف `saleType='return'` مستقل (تعليق 286-297)،
  ومحليًا صف ترويسة `SRET-xxxx` مربوط بملاحظة `localReturnLinkNote` (327) + تعديل حالة الأصل (347-350).
### 2.3 المرتجع السريع من POS — `sales_mutations_dao.dart` (372-392)
- [مؤكد] فاتورة مستقلة `saleType='return'`، وحركة مخزونها `referenceType:'sales_invoice', referenceId: <معرّف فاتورة المرتجع نفسها>`.

### 2.4 قراءة «المرتجع السابق»
- [مؤكد] الربط بلا عمود FK: `sales_dao.dart:11-41` (`localReturnLinkNote` في `notes`) — «FOLLOW-UP (not done): replace … with a real `sales_invoices.original_invoice_id`».
- [مؤكد] `getReturnedAmountsForInvoices` (`sales_dao.dart:1202-1276`) يجمع الشكلين: `safe_transactions(reference_type='sales_return', deleted_at IS NULL)` + صفوف `sale_type='return'` المرتبطة بالملاحظة.
- [مؤكد] الكمية المرتجعة: `getAlreadyReturnedQty` (`sales_actions_dao.dart:267-283`) و`getReturnedQuantitiesForInvoice` (`inventory_dao.dart:957-977`)
  تعدّان `stock_movements` بـ `movement_type='return' AND reference_type='sales_invoice' AND reference_id=<الأصل>`،
  بينما مسار الشاشة يكتب `reference_type='sales_return'` (2.1) ومسار الخادم يكتب `'sales_invoice'` لكن بـ `reference_id=<فاتورة المرتجع>` (2.3).
  ⇒ **عيب جانبي (مؤكد بقراءة الكود، ويؤكده تعليق `exchange_repository_impl.dart:305-309`)**: سياج «لا ترجع أكثر من المباع» (`returns_repository_impl.dart:149-167`)
  وعمود «سبق إرجاعه» في `sales_return_provider.dart:236-255` لا يريان المرتجعات السابقة على الأرجح في الشكلين. خارج نطاق هذه المهمة لكنه يعني أن
  «الكمية المرتجعة» **لا يمكن** الاعتماد عليها كما هي لبناء خيار (ج).
- [مؤكد] حالة الأصل `partial_return`/`returned` هي الأثر الموحد للشكلين (returns_repository_impl 347-350 / 715-718، api_sales_handler 620-640)،
  و`cancelSalesReturn` يعيدها `'completed'` (`journal_entry_factory.dart:1026-1031`).
  تحذير: `updateSalesInvoice` يعيد كتابة الحالة `completed/pending` (`sales_mutations_dao.dart:1003-1013`) — لفواتير غير مقفلة أو بصلاحية `modifyLockedInvoice` — فالحالة وحدها ليست دليلًا مطلقًا.

## 3. مداخل الإلغاء وحماياتها
| المدخل | الملف:السطر | فحص مرتجع؟ |
|---|---|---|
| حذف فاتورة واحدة (شاشتان) | `sales_invoices_picpos/screens/sales_invoices_table.dart:698-706` (الزر فقط إن `!invoice.isLocked`) → `sales_invoice_save_edit.dart:945-1030` (كلمة سر المدير) → `sales_invoices_controller.dart:1055-1065` `cancelInvoice` | لا. الحماية الوحيدة غير المباشرة: الزر مخفي للفواتير المقفلة (المرحَّلة). النسخة القديمة: `screens/widgets/sales_invoices/sales_invoices_table.dart:338-351` و`sales_invoice_save_edit.dart:878` |
| حذف مجمّع | `sales_invoices_picpos/screens/sales_batch_action_bar.dart:68-127` (+ `screens/widgets/sales_invoices/sales_batch_action_bar.dart:116`) | **لا** — الاختيار `toggleSelection`/`toggleAllSelection` (`sales_invoices_controller.dart:969-987`) لا يرشّح `isLocked` ولا الحالة؛ فقط تأكيد + موافقة ثنائية اختيارية (مطفأة افتراضيًا) |
| المستودع | `sales_repository_impl.dart:433-438` `cancelInvoice` → `465-558` `voidInvoice` | فحص `voided` فقط (483-485) |
| API: `POST /api/sales/void` | `api_routes_write.dart:23` → `api_sales_handler.dart:1181-1309` | صلاحية `salesDelete` + idempotency `voided` + هوية الجلسة؛ لا فحص مرتجع |
| API: `DELETE /api/sales/<id>` | `api_routes_write.dart:28` → `api_sales_handler.dart:1147-1168` → `deleteSalesInvoice` (`sales_actions_dao.dart:261`) | لا؛ ويمرر `deletedBy=null` |
| الصندوق الصادر | `cwi_trading_sales.dart:185-211` (`submitVoidSalesInvoice`) و`133-144` (`deleteSalesInvoice`)؛ إعادة التشغيل `offline_sync_worker_replay.dart:34-43` | لا فحص؛ يصل الخادم إلى `voidSalesInvoice` |
| POS | `picpos_pos_invoice_actions.dart:5-40` `_cancelInvoice` = إلغاء السلة/وضع المرتجع فقط؛ `pos_previous_invoices_dialog.dart` بلا إلغاء | لا يُلغي فاتورة مرحّلة |
| سحابة المندوبين `server/` | `server/lib/src/service/sync_service.dart` / `desktop_service.dart`: لا يوجد إلغاء فاتورة بيع إطلاقًا؛ المرتجعات تُرحَّل للمكتب عبر `cloud_document_poster.dart:283` → `processSalesReturn` | غير منطبق — لكنه **مصدر** مرتجعات على فواتير المكتب |
- [مؤكد] بحث نصي عن «لا يمكن (إلغاء|حذف)…مرتجع» في كامل المستودع: **لا نتائج**.

## 4. إثبات تشغيلي
- [مؤكد بالتشغيل] `flutter test test/scenarios/sc_c_sales_return_void_test.dart --run-skipped --plain-name "إلغاء فاتورة سبق ارتجاع جزء منها"`
  ⇒ فشل: `Expected: <= 50.005, Actual: <52.0>`. السجل يُظهر `SAFE-MOVE delta=-200` (المرتجع) ثم `SAFE-MOVE delta=-500` (الإلغاء) ⇒ خزينة −200.
  الاستثناء لم يُرمَ أصلًا (الإلغاء نجح). ملاحظة: أثر الفشل أشار إلى `sc_c_sales_return_void_test.dart 142:7` بينما قراءتي للملف وضعت `expect` في 134 — ربما عدّل الملفَ طرفٌ آخر أثناء العمل؛ لم أعدّله.

## 5. هل يصل إليه المستخدم؟
- [مؤكد] نعم، عبر **الحذف المجمّع** في شاشة فواتير البيع: لا يرشّح المقفل ولا الحالة، ويستدعي `cancelInvoice` → `voidInvoice` → `voidSalesInvoice`.
- [مؤكد] وعبر الحذف المفرد إن كانت الفاتورة غير مقفلة (`isLocked=false`): مثل فاتورة توصيل بإيراد مؤجل (`_autoPostDeferredRevenue` لا يضع `isLocked` — تعليق `sales_actions_dao.dart:184-188`)؛
  [استنتاج] وأي فاتورة لم يكتمل ترحيلها. شاشة المرتجعات تمنع إرجاع فواتير التوصيل (`sales_return_provider.dart:204-207`) فالحالة الأخيرة أضيق.
- [مؤكد] وعبر API (`POST /api/sales/void`، `DELETE /api/sales/<id>`) لأي عميل/مرآة بصلاحية `salesDelete`، وعبر إعادة تشغيل الصندوق الصادر.
- [استنتاج] السيناريو الميداني: كاشير يُرجع قطعتين اليوم؛ لاحقًا يقرر المحاسب «إلغاء الفاتورة» (خطأ إدخال) من الحذف المجمّع أو من جهاز عميل ⇒ مخزون زائد وخزينة دفترية أقل من الدرج، والمرتجع النقدي يُصرف مرتين في الأستاذ.
  وأيضًا: مرتجع من مندوب سحابي (`cloud_document_poster`) يصل المكتب على فاتورة ثم يلغيها أحدهم في المكتب.

## 6. الأثر الدفتري للإلغاء بعد مرتجع جزئي (5 مباعة، 2 مرتجعة، نقدًا)
- المخزون: +5 فوق +2 ⇒ 52 (زيادة 2) [مؤكد بالتشغيل].
- الخزينة: يعكس 500 فوق −200 ⇒ −200 [مؤكد بالتشغيل].
- الأستاذ: قيد البيع يُعكس كاملًا وقيد المرتجع (`sales_return`) يبقى ⇒ مردودات 4211 مدين 200 وتكلفة/مخزون معكوسان مرتين بمقدار 2×التكلفة [استنتاج من قراءة 196-243 + `autoPostSalesReturn`].
- الآجل: يطرح `total-paid-rounding` كاملًا بينما المرتجع قاصّ جزءًا ⇒ العميل يصبح دائنًا بقيمة المرتجع [استنتاج من 157-166 + `returns_repository_impl.dart:484-486`].
- خامات BOM: كسر 1.0 فوق كسر المرتجع ⇒ [استنتاج] قد يمنعه وسم `salesReturnId` في `reverseSaleConsumption` جزئيًا؛ لم أتحقق.

## 7. ما يفعله باقي المشروع
- [مؤكد] `voidPurchaseInvoice` (`purchase_void_dao.dart:15-36`) نفس الحمايات بلا فحص مرتجع ⇒ العيب نفسه مرجَّح في المشتريات [استنتاج، لم يُختبر].
- [مؤكد] تعديل فاتورة مرحّلة يُحال إلى «استخدم المرتجعات بدلاً من التعديل» (`sales_mutations_dao.dart:938-946`) — سياسة ضمنية: المستند المرحّل يُصحَّح بمستند لاحق لا بمسحه.
- [مؤكد] يوجد مسار «إلغاء المرتجع» قائم: `cancelSalesReturn` (`journal_entry_factory.dart:909-1043`) يعكس المخزون/النقدية/الذمم/القيد ويعيد الحالة `completed`،
  ومتاح من الواجهة (`sales_returns_picpos_record_actions.dart:41`، `sales_returns_picpos_logic.dart:418`، `screens/sales_returns/return_logic.dart:672`).
- [مؤكد] لا وثيقة سياسة في `docs/` تقرر الإلغاء بعد المرتجع؛ المذكور فقط `docs/testing/BUSINESS-SCENARIOS.md:26,43` كعيب مفتوح.

## 8. التوصية: (أ) منع الإلغاء
- أبسط وأكثر أمانًا: لا يتطلب حساب كمية مرتجعة (وهي غير موثوقة اليوم — §2.4)، ويتسق مع سياسة «صحّح بمستند لاحق»، والمسار البديل موجود: ألغِ المرتجع ثم الفاتورة.
- (ب) يتطلب تنسيق `cancelSalesReturn` داخل معاملة الإلغاء مع شكلين مختلفين للمرتجع، و`cancelSalesReturn` نفسه لا يتعامل مع الشكل B (حركات مربوطة بمعرّف فاتورة المرتجع) ⇒ مخاطرة.
- (ج) يتطلب كمية/مبلغًا/قيدًا صافيًا دقيقًا لكل سطر، ومصادره الحالية (`getAlreadyReturnedQty`) معيبة ⇒ غير آمن الآن.

### الإصلاح المقترح (الطبقة الخدمية)
في `SalesActionsDao.voidSalesInvoice` (`lib/data/database/daos/sales_actions_dao.dart`) بعد فحص `voided` (السطر 32) وقبل فحص الصلاحية:
```dart
if (inv.saleType == 'return') {
  throw Exception('هذا مستند مرتجع — استخدم «إلغاء المرتجع» من سجل مرتجعات المبيعات بدل إلغاء الفاتورة.');
}
final hasReturn = inv.status == 'partial_return' || inv.status == 'returned' ||
    await _hasActiveLinkedReturnInvoice(inv); // صفوف sale_type='return' و is_deleted=0 المرتبطة بالملاحظة (gid ثم المعرّف) — نفس منطق getReturnedAmountsForInvoices (فرع invRows)
if (hasReturn) {
  throw Exception('لا يمكن إلغاء فاتورة لها مرتجع. ألغِ المرتجع أولاً من «سجل مرتجعات المبيعات» ثم أعد المحاولة.');
}
```
- لا أستعمل فرع `safe_transactions` من `getReturnedAmountsForInvoices` كدليل: `cancelSalesReturn` لا يحذف صفوف `sales_return` بل يضيف `return_cancel` ⇒ سيمنع الإلغاء للأبد بعد إلغاء المرتجع [مؤكد بقراءة 959-992].
- كتلة `saleType=='return'` [مؤكد]: حلقة المخزون (53-83) تضيف `+quantity` بلا اعتبار للنوع، فإلغاء مستند مرتجع كان سيضاعف المخزون بدل خصمه. [استنتاج] لم أتحقق إن كانت شاشة الفواتير تعرض صفوف المرتجع.
- لأنه في الـDAO يشمل: الواجهة، `postVoidSale`، `DELETE /api/sales/<id>`، `deleteSalesInvoice`، وإعادة تشغيل الصندوق الصادر على الخادم.

### تكميلات صغيرة مقترحة
- `SalesRepositoryImpl.voidInvoice` (`sales_repository_impl.dart:483`): نفس فحص الحالة قبل الإرسال في وضع العميل — لأن المسار يضع `voided` محليًا (543) حتى لو رفضه الخادم، فبدون فحص محلي يرى العميل «ملغاة» حتى DeltaPull التالي. الحالة المحلية `partial_return` مضبوطة في وضع العميل (`returns_repository_impl.dart:347-350`).
- `postVoidSale`/`deleteSalesInvoice` في `api_sales_handler.dart`: تحويل هذا الرفض إلى 409/422 بدل 500 (`ApiErrors.fail`) [استنتاج: يجب التحقق من سلوك `_CwiCoreSupport.tryOrQueueVoid` مع رد الخطأ حتى لا يعيد المحاولة إلى ما لا نهاية].
- الواجهة: إخفاء/تعطيل الحذف للحالات `returned/partial_return` وترشيح الاختيار المجمّع — تجميلي فقط بعد حماية الـDAO.

### الأثر
- المزامنة: الخادم (HQ) هو من يرفض؛ الإلغاءات المعلّقة في الصندوق الصادر لفواتير لها مرتجع ستُرفض عند إعادة التشغيل — سلوك صحيح لكنه يحتاج رسالة واضحة [استنتاج].
- الفواتير القديمة: الفحص قراءة فقط؛ لا ترحيل بيانات. الفواتير التي أُلغيت سابقًا بعد مرتجع تبقى منحرفة — تحتاج تقرير كشف (فواتير `voided` لها صفوف `sales_return` أو مرتجعات مرتبطة) [اقتراح].
- الاختبارات القائمة: بحثت في كل مستدعي `voidSalesInvoice` في `test/` (sc_c، sc_k، sc_j، sc_l، pir_*، e2e_scenarios، void_* ، go_blockers_void_bom، round_wiring، critical_financial_ops_gate، spec_151_sales_void_gate، erp_load_bench): **لا يوجد اختبار يلغي فاتورة بعد مرتجع عليها**؛ `sc_k_trial_balance_test.dart:55,103-104` يُرجع من فاتورة ويلغي فاتورة **أخرى**. اختبار `sc_c…:125-139` يقبل الرفض صراحة فيُزال `skip`.
  `spec_151_sales_void_gate_test.dart` اختبار بنية نصية للشيفرة — يجب التأكد أن الإضافة لا تكسر مطابقاته [لم يُشغَّل].

## 9. الخطورة
- عالية محاسبيًا (مخزون وخزينة وأستاذ وذمم منحرفة بصمت، بلا إصلاح تلقائي)، متوسطة الاحتمال: تتطلب مستخدمًا بصلاحية حذف + (حذف مجمّع أو API/عميل أو فاتورة غير مقفلة). ليست افتراضية: المسار المجمّع متاح من الشاشة الرئيسية للفواتير.

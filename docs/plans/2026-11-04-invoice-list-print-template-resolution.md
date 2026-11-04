# طباعة فاتورة البيع والمرتجع من قائمة الفواتير وتفاصيلها — حسم القالب المربوط (2026-11-04)

المرجع: الجولة الحية `docs/plans/2026-11-04-live-final4.md` (البندان 1 و4)، وملفاتها
`D:\qa\print_live5\out_a4_SINV-6.pdf` و`D:\qa\print_live5\out_a4_SINV-7-return-detail.pdf`.
القاعدة: `HEAD 57c972a7`، بلا `build_runner` وبلا تغيير schema.

## حالة sandbox كما قُرئت (قراءة فقط)

| الجدول | ما فيه |
|---|---|
| `template_bindings` | `id=3 sales_invoice · printer_id=1 · locale=ar → template 2` و`id=2 sales_return · printer_id=2 · locale=ar → template 4` (والفرع `NULL` في الاثنين) |
| `printers` | `1 QA A4 (210mm)` و`2 QA 80 (80mm)`، **كلتاهما** `purpose=pos_receipt` ونشطتان |
| `invoice_templates` | `1 الفاتورة الحرارية (thermal/receipt, v1, افتراضي)`، `2 فاتورة A4 (a4/invoice, v2, افتراضي)`، `4 إيصال مرتجع مبيعات (thermal/sales_return, v2)` |
| `sales_invoices` | `SINV-6 (id=8)` و`SINV-7 (id=9, status=returned)` وكلتاهما `branch_id=1` |

## السبب الجذري

### العيب (1): فاتورة البيع خرجت بالقالب الحراري داخل صفحة A4

مسار الزر في الشاشة الحية (PicPos) هو [sales_invoice_dialogs.dart](<../../lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart>): زر «طباعة» في الحوار وزر الطباعة في صف القائمة (`onPrint: _printInvoice`) كلاهما ينادي `_printInvoice`. وهذه كانت تنادي **`PrintingService.printReceipt(invoice.id)`**، وهو مسار إيصال نقطة البيع نفسه. وفي التوأم UralCash ([sales_invoice_dialogs.dart](<../../lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart>)) النداء نفسه.

داخل [printing_service.dart](<../../lib/services/printing_service.dart>) (`printReceipt`):

1. **الطابعة المختارة**: `getActivePrinterByPurpose('pos_receipt')`، أي أول طابعة نشطة بالغرض مع `limit(1)` **بلا ترتيب**. في sandbox الطابعتان بالغرض نفسه، فخرجت الورقة على `QA A4`. لم تُستشر الروابط في اختيار الطابعة.
2. **نوع المستند المحسوم**: `documentType: 'sales_receipt'`، والزوج `type='thermal'` و`category='receipt'`. لم يمر المسار بالنوع `sales_invoice` أصلاً.
3. **لماذا لم يطابق الربط**: سلسلة الحسم (`TemplateResolver.resolve`) تبدأ بتصفية الروابط على `documentType`. ولا رابطة لـ`sales_receipt`، فسقط الحسم إلى المستوى 6 (الافتراضي بالفئة `thermal/receipt`)، وهو القالب 1 «الفاتورة الحرارية». أما رابطة `sales_invoice → printer 1 → template 2` فلم تُقرأ قط.
4. **هل يتجاوز مسار القائمة الحاسم**: لا، فهو يمر بالحاسم لكن **بنوع مستند خاطئ**. والنتيجة قالب افتراضي حراري.
5. **الطابعة وعرض الورق**: يُمرَّر `printerId` الطابعة A4 مع `directPrint: true`. أما العرض فيؤخذ من القالب لا من الطابعة: القالب 1 عرضه 80mm، ومساحته المرسومة `80 − 8 = 72mm` (`printWithTemplate`، التدفق v1). فخرج شريط عرضه 72mm على صفحة A4، وأعمدة الجدول الستة ضيقة على ذلك العرض فانكسرت الأرقام إلى سطرين («0.0» ثم «0»). هذا يطابق ما وُصف حياً.

و`printerId` الذي مرّره عامل سابق في [invoice_generator.dart](<../../lib/services/invoice_generator.dart>) (`printSalesInvoice` و`printSalesReturnReceipt` و`printPurchaseInvoice` و`printPartyStatement`) يأخذ قيمته الاحتياطية من `getActivePrinterByPurpose('pos_receipt')` كذلك. ولا يقع شيء منها على مسار القائمة أصلاً، لأن القائمة لا تنادي `printSalesInvoice`.

### العيب (2): «طباعة» تفاصيل SINV-7 طبعت الفاتورة الأصلية

* حوار التفاصيل فيه زر واحد هو `_printInvoice(invoice)`، فهو `printReceipt` على **الفاتورة الأصلية** (id=9). ولا يوجد في الواجهة مسار يطبع إيصال مرتجع لفاتورة بعد ترحيل مرتجعها.
* SINV-7 مرتجعها من الشكل A: تُقلب حالة الفاتورة الأصلية `returned` ويُكتب صف في `safe_transactions` وحركة `stock_movements`، ولا يُنشأ مستند `sale_type='return'`. فلا مستند مرتجع يمكن أن يطبعه `printReceipt` أصلاً.
* وفي سجل المرتجعات كان `reprintPostedReturn` يمر بفرع «من السجل» في `getSalesReturnPrintData`، وهو فرع يطبع **كل بنود الفاتورة** بكمياتها الكاملة، فلا يعكس ما أُرجع فعلاً. ويبحث عن الفاتورة برقمها في آخر 30 يوماً فقط.
* وحتى `printSalesReturnReceipt` كانت تختار الطابعة بـ`pos_receipt` الأولى، أي `QA A4` في sandbox. فرابطة `sales_return` على `QA 80` تخسر مستواها الأول، ويحسم الافتراضي بالفئة القالب 4 نفسه، لكنه يُرسل إلى طابعة A4.

### ملاحظة على الفرع (اكتُشفت بالاختبار)

المستوى 1 في `TemplateResolver._matchesLevel` يشترط `b.branchId == branchId` حرفياً. فرابطة sandbox (`branch_id = NULL`، أي كل الفروع، مع طابعة) **لا تطابق** فاتورة فرعها 1 إذا مُرِّر الفرع، والمستويات 2 إلى 4 لا تقبل رابطة لها طابعة. لذلك يحسم المسار الجديد **بلا فرع**، كبقية منادي الطباعة اليوم. ولم أعدّل السلسلة لأن تعديلها يمس `explain()` وشاشة الحسم واختبار `template_resolution_chain_test`. (الوضع الحالي: الرابطة الخاصة بفرع مع طابعة لا يحترمها أي مسار طباعة.)

## الإصلاح (أضيق تعديل)

| الملف | التغيير |
|---|---|
| [document_print_route.dart](<../../lib/services/printing/document_print_route.dart>) (جديد) | `resolveDocumentPrinterId`: تختار الطابعة النشطة التي تسميها رابطة لنوع المستند (الأخص أولاً، ثم الأولوية، ثم المعرّف الأقدم)، وإلا تعود إلى `getActivePrinterByPurpose('pos_receipt')` كما كان. `boundDocumentTemplate`: القالب **المربوط صراحة** (المستويات 1 إلى 4 فقط)، وتعيد `null` إن كان أعرض من الطابعة (`checkPaperFit`). |
| [printing_service.dart](<../../lib/services/printing_service.dart>) | `IPrintingService.printSalesInvoiceDocument(invoiceId)`: تحسم `sales_invoice/invoice` على الطابعة المحسومة. إن وُجدت رابطة صريحة تطبع بقالبها مع `directPrint`، وتمرّر الطابعة واللغة ورمز الإيصال، وتسجّل في السجل اسم القالب. وإن لم توجد فهي `printReceipt` بحرفه. ومستند `sale_type='return'` يبقى على `printReceipt`. |
| [invoice_generator.dart](<../../lib/services/invoice_generator.dart>) | في `printSalesReturnReceipt` صارت الطابعة الاحتياطية `resolveDocumentPrinterId(db, documentType: 'sales_return')` بدل أول `pos_receipt`. |
| [posted_sales_return_print.dart](<../../lib/services/printing/posted_sales_return_print.dart>) (جديد) | `printPostedSalesReturn`: إيصال مرتجع مرحَّل لفاتورة. البنود تُحسب من الكميات المرتجعة الصافية (`getReturnedQuantitiesForInvoice`، بعد طرح الإلغاءات) وتُوزَّع على البنود بوحدة البيع (`returnedSaleUnitsByItem`، وهي خوارزمية `SalesReturnNotifier` نفسها). المبلغ هو المسترد الفعلي، والإيصال يُطبع بنوع `sales_return`. وإن غابت حركات المخزون محلياً يبقى فرع «من السجل» القائم كما هو. |
| [sales_invoice_print_actions.dart](<../../lib/presentation/sales_invoices_picpos/screens/sales_invoice_print_actions.dart>) (جديد) | في الحوار زرّان منفصلان: «طباعة الفاتورة» يظهر دائماً، و«طباعة المرتجع» يظهر حين `returnedAmounts[id] > 0` ويحرسه `sales_return_print` بـ`ensurePermission`. النصوص بـ`tr()` داخل `build`/المعالج، ولا ألوان حرفية فيها. |
| [sales_invoice_dialogs.dart](<../../lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart>) وتوأمه UralCash | صار `_printInvoice` ينادي `printSalesInvoiceDocument`، وحلّ الودجت الجديد محل زر «طباعة» الوحيد في الحوار. حجم الملف 39065 بايت تحت سقفه 39134، والسقف لم يُرفع. |
| [sales_returns_picpos_record_actions.dart](<../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_record_actions.dart>) و[sales_return_records_picpos_screen.dart](<../../lib/presentation/sales_returns_picpos/screens/sales_return_records_picpos_screen.dart>) | زر «طباعة» في سجل المرتجعات يمرّر `originalInvoiceId`، فيطبع ببنود المرتجع الفعلية. وغياب المعرّف يُبقي المسار القديم (مع تعليق يشرحه). |
| `assets/i18n/en.json` | مفتاح جديد: «لا مرتجعَ مرحَّلاً لهذه الفاتورة» (No posted return for this invoice). أما «طباعة الفاتورة» و«طباعة المرتجع» فموجودان مسبقاً. |

لم يُحذف منطق، ولم يتغير schema، ولم يُشغَّل `build_runner`. والطبقة presentation لا تستورد `data/database` في الملفات الجديدة.

## قبل / بعد (صفحات PDF مصيَّرة)

صُيِّرت ملفات PDF التي التقطها الاختبار (`PdfComputeHelper.nativeLayoutOverride`، بلا طابعة) بـ`render_page` من `tool/print_audit/render_scale_label.py` عبر `importlib`، وبـpython المرفق. الملفات في `docs/plans/invoice_list_print_2026-11-04/`.

### (1) فاتورة البيع: رابطة `sales_invoice → QA A4 → فاتورة A4`

| قبل (حياً، SINV-6) | قبل (الاختبار، مسار `printReceipt` نفسه) | بعد (`printSalesInvoiceDocument`) |
|---|---|---|
| ![SINV-6 حياً](<invoice_list_print_2026-11-04/live_before_SINV-6_a4.png>) | ![قبل](<invoice_list_print_2026-11-04/before_sales_invoice_receipt_path.png>) | ![بعد](<invoice_list_print_2026-11-04/after_sales_invoice_a4.png>) |

صورة «قبل» في الاختبار تعيد العيب الحي بالضبط: «اسم الشركة» على شريط عرضه 72mm، و«0.0 / 0» مكسورة على سطرين. وصورة «بعد» على صفحة A4 كاملة (595.3pt) بقالب «فاتورة A4» v2 وبأعمدة لا تلتف.

### (2) المرتجع: رابطة `sales_return → QA 80 → إيصال مرتجع مبيعات`

| قبل (حياً، تفاصيل SINV-7) | قبل (الاختبار، زر التفاصيل القديم) | بعد (`printPostedSalesReturn`) |
|---|---|---|
| ![SINV-7 حياً](<invoice_list_print_2026-11-04/live_before_SINV-7_return_detail.png>) | ![قبل](<invoice_list_print_2026-11-04/before_return_detail_receipt_path.png>) | ![بعد](<invoice_list_print_2026-11-04/after_sales_return_80.png>) |

في صورة «بعد» يظهر عنوان «*** مرتجع مبيعات ***»، ورقم سند `SRET-1`، والفاتورة الأصلية `SINV-1` مرجعاً. البند المرتجع وحده ظاهر (1 × 6.99 من صنف بيع منه 2)، والصنف غير المرتجع (37.00) غائب، و«إجمالي المرتجع 6.99» مع «استرداد نقدي 6.99». أما «قبل» فكان يطبع الفاتورة كلها (50.98).

## الاختبارات

ملفان جديدان:

* [invoice_list_print_template_resolution_test.dart](<../../test/unit/invoice_list_print_template_resolution_test.dart>): يبني الحالة بـ`ScenarioWorld` (بيع حقيقي ومرتجع بالمسار الحي)، والقوالب المبذورة مع هجرة A4 والمرتجع إلى v2 كما في sandbox، وطابعتين `pos_receipt` تُدرج A4 أولاً، والربط بـ`TemplateBindingDao.activateBinding` كما في sandbox:
  1. الطابعة المحسومة لـ`sales_invoice` هي A4، والقالب المختار هو «فاتورة A4» المربوط. والمطبوع صفحة A4 كاملة يمتد محتواها أكثر من 120mm، ولا رقم مكسور في الجدول. وفي المقابل يكسرها مسار «قبل» (فحص مرساة). والسجل يذكر اسم القالب.
  2. الطابعة المحسومة لـ`sales_return` هي QA 80 مع أن A4 أُدرجت أولاً، والحسم مستوى 1 إلى قالب المرتجع. والمطبوع 72mm، فيه 6.99 وSRET ورقم الفاتورة الأصلية، وليس فيه 37.00 ولا 50.98. ويختلف عن مطبوع زر التفاصيل القديم.
  3. فاتورة بلا مرتجع: `noReturnData` ولا ورقة.
  4. بلا ربط: بصمة `printSalesInvoiceDocument` تساوي بصمة `printReceipt`، أي السلوك الحالي بحرفه، وبالعرض الحراري.
  5. رابطة عامة لقالب A4 على طابعة 80mm وحدها: ترفضها `checkPaperFit`، فيُطبع القالب الحراري.
  6. `returnedSaleUnitsByItem`: البند المرتجع 1 والبقية 0.
* [sales_invoice_print_actions_test.dart](<../../test/widget/sales_invoice_print_actions_test.dart>): بلا مرتجع يظهر زر الفاتورة وحده، ومع مرتجع يظهر زران بتسميتين، وزر الفاتورة لا ينادي إلا مسار الفاتورة.

### ما شُغِّل فعلاً (`. D:\qa\luna_tools.ps1` ثم `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos …`)

دفعة واحدة من 43 ملفاً: **`+270: All tests passed!`**. وتشمل:

* اختباري هذا التقرير.
* `test/unit/template_binding_reaches_paper_test.dart` و`test/unit/printing_characterization_test.dart` و`test/widget/template_resolution_screen_test.dart`.
* الحراس الستة: `file_size_ratchet_test`، `i18n_coverage_test`، `i18n_runtime_safety_test`، `dark_mode_guard_test`، `analytics_parity_test`، `presentation_db_import_guard_test`.
* حراس الطباعة: `print_callers_pass_document_type_test`، `print_dialog_funnel_guard_test`، `pdf_print_guard_test`، `template_resolution_chain_test`، `ready_template_deployment_test`، `i18n_catalog_quality_test`.
* الاختبارات البنيوية التي تقرأ الملفات المعدّلة: `go_blockers_print_failure_not_reported_as_success_test`، `go_blockers_tax_rate_unit_mismatch_test`، `picpos_second_door_guards_test`، `spec_085_cancel_dialog_mounted_test`، `attachments_mounted_where_documents_live_test`، `invoice_due_date_single_formula_test`، `invoice_form_scope_parity_test`، `purchase_invoice_has_no_draft_test`، `sales_invoice_preview_has_no_number_test`، `sales_invoice_details_masking_test`، `screens_theme_contrast_round7a/6c`.
* اختبارات الفواتير والمرتجعات: `picpos_sales_invoices_test`، `picpos_return_records_j2_test`، `purchase_return_records_screen_test`، `picpos_sales_returns_test`، `sales_return_refund_split_test`، `sales_returns_history_parity_test`، وفي integration: `sales_return_shift_and_branch_safe`، `sales_returns_history_e2e`، `picpos_sales_return_cancel_stock`، `sales_return_wac_gl_drift`، `sales_returns_void_predicate_parity`، `spec_136_iss26_customer_statement_sales_return`، وفي scenarios: `sc_c2_cancel_sales_return`، `sc_c_sales_return_void`.

في تشغيل سابق أحمرّ `file_size_ratchet_test` لأن `sales_invoice_dialogs.dart` زاد 255 بايت عن سقفه. أُصلح ذلك بنقل المنطق إلى الودجت وتقصير التعليق، لا برفع السقف، ثم أُعيدت الدفعة كاملة خضراء.

`flutter analyze lib`: معلومتا `use_build_context_synchronously` القديمتان فقط (`purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84`).

## حدود معلنة

* **لم يُتحقق حياً** على الحاوية بعد الإصلاح: لا طابعة حقيقية ولا إعادة تشغيل للتطبيق في هذه الجولة. الدليل كله من بناء PDF في الاختبار.
* المستوى 1 لا يطابق رابطة «كل الفروع مع طابعة» على مستند له فرع (انظر الملاحظة أعلاه). المسار الجديد يتجنب ذلك بالحسم بلا فرع، فالرابطة **الخاصة بفرع** مع طابعة ما زالت لا تصل الورق، كما في كل مسار طباعة اليوم.
* تاريخ إيصال المرتجع المعاد طبعه هو `DateTime.now()`، كما كان في إعادة الطباعة من السجل، لا تاريخ سند المرتجع.
* قالب المرتجع المبذور القديم (sandbox id=4) ما زال يرسم أعمدته الستة متراكبة بخط 12، ويظهر ذلك في صورة «بعد». هذا عيب قالب يعالجه نشر القوالب الجاهزة (`ready_template_deployment.dart`، ترقية `thermal80_sales_return.json`)، لا عيب حسم.
* مرتجع لا حركات مخزون محلية له (عميل لم يسحب حركات الخادم) يسقط إلى فرع «من السجل» القديم الذي يطبع كل البنود.
* يجمع الإيصال كل المرتجعات المرحّلة للفاتورة صافية. ولا يوجد اليوم مفتاح يفصل مرتجعين جزئيين في إيصالين.

الخطوة التالية المقترحة: إعادة الجولة الحية على sandbox بالبناء الجديد، للزر في قائمة الفواتير و«طباعة المرتجع» في تفاصيل SINV-7، ومقارنة `out_a4.pdf` و`out_80.pdf` بالصور أعلاه.

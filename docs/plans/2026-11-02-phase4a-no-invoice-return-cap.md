# المرحلة 4a — سقف المرتجع بلا فاتورة

## قائمة التحقق النهائية
- [✔] اختبار أحمر أولاً: عُطّل استدعاء الحارس مؤقتاً في نقطتي الكتابة، ففشلت اختبارات الحد كما ينبغي؛ أُعيد الاستدعاءان قبل كل تحقق لاحق.
- [✔] حراسة مشتركة داخل معاملة الإدراج المحلي ومرآة العميل، مع استثناء المرتجع المرتبط بفاتورة أصلية.
- [✔] إثبات SQLite تسلسلي وPostgreSQL متزامن 3+3 من صافي 5، بما فيه احتساب المرتجع المرتبط.
- [✔] تحديث اختبارات التكامل القديمة بإضافة مبيعات سابقة مشروعة، دون حذف أي حالة.
- [✔] إعادة فحوص التسليم المحددة ملفاً ملفاً، مع توثيق قيد المخزون التاريخي وتشخيص `sc_c`.

## Checkpoints

### البداية
أظهر `Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` قبل التعديل `NOINV-01` و`NOINV-04` مع `Actual: <2.0>` حيث كان المتوقع ألا يبقى مخزون بعد المرتجع. ظهر أيضاً `VOID-02` مع `Actual: <0.0>` بدلاً من `-50.0`؛ هذا من تغيير العامل الآخر في الإلغاء، ولم أعدّل مساره.

قراءة التدفق: `checkout_controller.dart` يمرر `saleType='return'` للمرتجع غير المرتبط؛ المحلي ينفذ `createSalesInvoice`، والعميل يرسل `postSale` ثم يحفظ المرآة عبر `insertSalesInvoiceWithoutStock`. `postSalesReturn` مخصص للمرتجع المرتبط بفاتورة.

### الاختبار الأحمر وإصلاح الصافي
عُطّل الحارس مؤقتاً عند موقعي الاستدعاء فقط. شغّل `Invoke-FlutterTest test/phase4/noinv_cap/no_invoice_return_cap_test.dart` وأخفق تحديداً في:
- `excess return is rejected before invoice, journal, stock, or safe effects`: `Expected: false`, `Actual: <true>`.
- `a prior no-invoice return reduces the amount available for the next return`: `Expected: false`, `Actual: <true>`.
- `a product never sold has zero returnable quantity`: `Expected: false`, `Actual: <true>`.

أُعيد الحارس بعد التجربة. كشف اختبار إضافي أن المرتجع المرتبط يسجل حركة `stock_movements` موجبة باسم `sales_return` على معرّف فاتورة البيع، ولا ينشئ دائماً سطر مرتجع مستقل. لذلك يجمع الحارس كميات فواتير البيع/المرتجع غير الملغاة بوحدة الأساس، ثم يطرح صافي حركات `sales_return` و`return_cancel` الموقعة. يظل مستند `saleType='return'` غير المرتبط محسوباً من سطور فواتيره مرة واحدة. يثبت الاختبار أن مرتجعاً مرتبطاً 2 من بيع 5 يجعل المتاح 3؛ كما يغطي التحويل لوحدة الأساس، الصنف الخدمي، والصنف غير المتتبع.

على PostgreSQL يقفل الحارس صف المنتج بـ`SELECT ... FOR UPDATE` قبل الحساب، لتسلسل محاولتي المرتجع للمنتج نفسه. تبقى الحراسة محصورة في `saleType='return'` بلا رابط إلى فاتورة أصلية، وتسبق إنشاء المستند والقيد/المخزون/الخزنة. الرسالة العربية تذكر اسم المنتج والمتاح. المنتجات المركبة تحسب بصفتها المنتج المباع، دون تفكيك BOM. المبيعات الملغاة/المحذوفة مستثناة. القرار لا يقسم الكمية بين الفروع ولا يضيف إعفاءً للمدير.

### تحديث التكامل القديم
لم تُحذف أي حالة من `test/integration/no_invoice_return_persist_test.dart`. أضيف بيع سابق صالح لكل من حالات المرتجع الخالص الثلاث وحالتي السلة المختلطة، كي تظل هذه الحالات تقيس التكلفة، الضريبة، القيود، الصندوق والتقاصّ بدلاً من اختبار مخزون شراء غير مباع. أُبقي اختبار عدم وجود وردية دون تغيير. النتيجة النهائية بعد إعادة التشغيل الأخيرة: `00:14 +9: All tests passed!`.

### PostgreSQL والسباق
شُغّل `test/phase4/noinv_cap/no_invoice_return_cap_pg_test.dart` على PostgreSQL 18 خاص بهذه المهمة، مربوطاً على `127.0.0.1:57850` فقط. كشفت المحاولة الأولى أن PostgreSQL يتطلب `p.id` في `GROUP BY` (`42803`)، فأُضيف ثم أُعيد الاختبار: `00:48 +1: All tests passed!`. الاختبار يجري محاولتي 3+3 المتزامنتين من صافي 5، ويقبل واحدة فقط. ظهر بعد نتيجة النجاح سجل تنظيف غير فاشل: `AUTOPOST-RETRY ... Can't re-open a database after closing it` / `deferred phase 6 aborted`. تحققت من اسم الحاوية والمنفذ ثم أزلت الحاوية؛ لا توجد قاعدة/حاوية مشتركة استُخدمت.

### `sc_c` وتغييرات العامل الآخر
كان تشغيل أقدم قد فشل في `sc_c_sales_return_void_test.dart:275`: المتوقع رصيد طرف `0` والفعلي `-500.0`، ضمن تغييرات إلغاء الفاتورة/المرتجع للعامل الآخر. لم ألمس تغييرات العامل. بعد أن أصبحت إصلاحاته الحالية موجودة، أُعيد تشغيل الملف منفرداً: `00:43 +16: All tests passed!`؛ ونجحت كذلك ملفات `sc_a`, `sc_b`, `sc_c2`, `sc_c3`, `sc_c4` كلٌّ على حدة.

## نتائج التحقق النهائي
كل أمر أدناه نُفذ باستخدام `. D:\qa\luna_tools.ps1` حيث يلزم، وخرج بنجاح:

- `Invoke-FlutterTest test/phase4/noinv_cap/no_invoice_return_cap_test.dart` — `00:19 +8: All tests passed!`.
- `Invoke-FlutterTest test/phase4/noinv_cap/no_invoice_return_cap_pg_test.dart -PgDsn ...` على الحاوية الخاصة — `00:48 +1: All tests passed!`.
- `Invoke-FlutterTest test/integration/no_invoice_return_persist_test.dart` — `00:14 +9: All tests passed!`.
- `Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` — `00:43 +24: All tests passed!`.
- `Invoke-FlutterTest test/unit/no_invoice_return_unit_test.dart` — `00:00 +29: All tests passed!`.
- `Invoke-FlutterTest test/widget/pos_picpos/picpos_no_invoice_return_lines_test.dart` — `00:03 +9: All tests passed!`.
- `Invoke-FlutterTest test/phase1/returns_cap/cumulative_returns_cap_test.dart` — `00:24 +10: All tests passed!`؛ `test/phase1/edit_guard_live_path/edit_guard_live_path_test.dart` — `00:11 +4: All tests passed!`؛ `test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart` — `00:17 +6: All tests passed!`.
- `test/scenarios/sc_a_cash_sale_cycle_test.dart` — `+3`; `sc_b_credit_sale_receipts_test.dart` — `+2`; `sc_c_sales_return_void_test.dart` — `+16`; `sc_c2_cancel_sales_return_test.dart`, `sc_c3_return_link_by_gid_test.dart`, و`sc_c4_voided_after_return_report_test.dart` — `+1` لكل ملف؛ كلها `All tests passed!`.
- `test/structural/file_size_ratchet_test.dart` — `+1`; `dark_mode_guard_test.dart` — `+3`; `i18n_coverage_test.dart` — `+1`; `i18n_runtime_safety_test.dart` — `+1`; كلها `All tests passed!`.
- `flutter analyze lib/data/database/daos/sales_mutations_dao.dart test/phase4/noinv_cap/no_invoice_return_cap_test.dart test/phase4/noinv_cap/no_invoice_return_cap_pg_test.dart test/integration/no_invoice_return_persist_test.dart test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart` — `No issues found! (ran in 52.7s)`.

## حد المخزون التاريخي وخيارات العمل
بعد تفعيل القاعدة، مخزون افتتاحي أو رصيد شراء قديم بلا فاتورة بيع غير ملغاة يعطي كمية مرتجعة متاحة `0.0`، ولذلك يُرفض إرجاعه بلا فاتورة. هذا قيد تاريخ البيانات السابق للنظام/لإنفاذ السياسة، وليس بيعاً قابلاً للإثبات آلياً. البدائل الممكنة لاحقاً — ولم يُنفذ أي منها — هي إدخال مبيعات تاريخية صحيحة، أو صلاحية تجاوز موثقة للمدير، أو إعداد شركة صريح لتعطيل السقف.

## الملفات وتغييرات الملكية
- `lib/data/database/daos/sales_mutations_dao.dart`: فحص الصافي، قفل PostgreSQL، واستثناء المنتجات غير المتتبعة/الخدمات؛ حافظت على تعديلات العامل الآخر القريبة في الملف.
- `test/phase4/noinv_cap/no_invoice_return_cap_test.dart`: ثمانية سيناريوهات، بما فيها عدم وجود أثر عند الرفض، 3+3 التسلسلي، المرتجع المرتبط، تحويل وحدة الأساس، الخدمي وغير المتتبع.
- `test/phase4/noinv_cap/no_invoice_return_cap_pg_test.dart`: اختبار التزامن PostgreSQL.
- `test/integration/no_invoice_return_persist_test.dart`: احتفظت بالحالات التسع وأضفت تهيئة البيع السابق للحالات الموجبة؛ أُخذت نسخة عبر `Backup-ForTask phase4a test/integration/no_invoice_return_persist_test.dart` قبل التحرير.
- `test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart` و`test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart`: تحديث توقعات/تهيئة السلوك؛ تغييرات العامل الآخر باقية.
- هذا التقرير.

## الأثر والتراجع
الأثر التشغيلي المقصود هو رفض مرتجع بلا فاتورة اعتماداً على مخزون موجود فقط دون صافي مبيعات مثبت. إن لزم التراجع، اعكس أسطر الحارس المحددة فقط نسبةً إلى النسخة الاحتياطية؛ لا تستعد الملف كاملاً كيلا تمحى تغييرات العامل الآخر. لم يُنفذ commit أو push أو reset أو checkout أو stash.

## إصلاح انحدار
- `test/integration/sales_return_shift_and_branch_safe_test.dart`: أضيفت في إعداد حالتي المرتجع السريع ذي الوردية والمرتجع النقدي عبر DAO بيعة نقدية سابقة فعلية للمنتج بكمية 1، مع الوردية مفتوحة. أُخذ رصيد الخزنة المتوقع بعد تحصيل البيع كي يظل التوقع معنياً بخصم المرتجع وحده (-100)؛ أضيف تعليق يشرح سبب التهيئة وحساب خط الأساس. لم يتغير الحارس ولا التوقعات الوظيفية.
- قبل الإصلاح: `Invoke-FlutterTest test/integration/sales_return_shift_and_branch_safe_test.dart` فشل في الحالتين برسالة `Bad state: لا يمكن إرجاع منتج بلا فاتورة بكمية أكبر من صافي المباع منه (المتاح: 0.0)`.
- بعد الإصلاح: `Invoke-FlutterTest test/integration/sales_return_shift_and_branch_safe_test.dart` — `00:38 +25: All tests passed!`.
- نقطة تفتيش: الإصلاح وإعادة اختبار الملف اكتملَا؛ بحث المرشحين وتشغيل الملفات كلٌّ على حدة، ثم فحوص التسليم النهائية ما زالت مطلوبة.
- نتائج التشغيل المنفرد للمرشحين حتى الآن: `test/phase4/noinv_cap/no_invoice_return_cap_test.dart` `+8 All tests passed`; `test/integration/no_invoice_return_persist_test.dart` `+9 All tests passed`; `test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart` `+6 All tests passed`; `test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` `+24 All tests passed`; `test/audit_repro/shift_close/shift_close_audit_matrix_test.dart` `+0 ~20 All tests skipped` (اختبارات التدقيق كلها متخطاة).
- نتائج سيناريوهات المرتجع: `sc_c_sales_return_void_test.dart` `+16`; `sc_c2_cancel_sales_return_test.dart` `+1`; `sc_c3_return_link_by_gid_test.dart` `+1`; `sc_c4_voided_after_return_report_test.dart` `+1`; `return_e2e_test.dart` `+3`; `sales_returns_void_predicate_parity_test.dart` `+1` — جميعها `All tests passed!`.
- نتائج مرشحي التكامل والتسمية: `picpos_sales_return_cancel_stock_test.dart` `+6`; `sales_return_wac_gl_drift_test.dart` `+2`; `sales_returns_history_e2e_test.dart` `+2`; `sales_report_net_of_returns_e2e_test.dart` `+2`; `shift_closing_aggregates_test.dart` `+8`; `spec_136_iss25_shift_window_visibility_test.dart` `+5` — جميعها `All tests passed!`.
- نتائج مرشحي الوحدة/الواجهة: `no_invoice_return_unit_test.dart` `+29`; `picpos_no_invoice_return_lines_test.dart` `+9`; `picpos_quick_return_lines_test.dart` `+16`; `sales_return_refund_split_test.dart` `+20`; `sales_returns_history_parity_test.dart` `+5`; `picpos_sales_returns_test.dart` `+1` — جميعها `All tests passed!`.
- نتائج مرشحي DAO/API والتقارير: `einvoice_sweeper_query_test.dart` `+7`; `sales_dao_last_invoice_test.dart` `+8`; `api_sale_price_discount_guard_test.dart` `+5`; `failed_autopost_retry_test.dart` `+4`; `hr_payroll_j4_test.dart` `+12`; `picpos_report_consistency_test.dart` `+16`; `autopost_return_not_a_sale_test.dart` `+3`; `distribution_model_phase_f_test.dart` `+13`; `go_blockers_vat_reconciliation_test.dart` `+8`; `invoice_number_unique_index_test.dart` `+5`; `party_period_aggregates_test.dart` `+8`; `party_statement_queries_test.dart` `+10`; `product_profit_and_inventory_value_test.dart` `+8`; `sales_report_card_matches_table_test.dart` `+9`; `sr1_return_party_balance_sign_test.dart` `+4` — جميعها `All tests passed!`.
- `test/integration_pg/phase1_quick_return_pg_test.dart`, `test/integration_pg/invoice_number_unique_index_pg_test.dart`, `test/integration_pg/pg_einvoice_sweeper_pg_test.dart` و`test/phase4/noinv_cap/no_invoice_return_cap_pg_test.dart`: لكل ملف خرج `00:00 +0 ~1: All tests skipped!` مع سبب `Skip: Run via melos test:pg (Postgres-backed integration suite)`؛ لم أفعّل اتصال PostgreSQL اتباعاً للمنع.
- `test/phase1/returns_cap/cumulative_returns_cap_test.dart` — `00:17 +10: All tests passed!`; `test/structural/return_no_auto_deplete_test.dart` — `00:00 +4: All tests passed!`.
- إعادة تحقق التسليم النهائية: `test/integration/sales_return_shift_and_branch_safe_test.dart` `00:38 +25: All tests passed!`; `test/phase4/noinv_cap/no_invoice_return_cap_test.dart` `00:13 +8: All tests passed!`; `test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` `00:37 +24: All tests passed!`; `test/integration/no_invoice_return_persist_test.dart` `00:11 +9: All tests passed!`.
- سيناريوهات التسليم أُعيدت كلٌّ على حدة: `sc_a_cash_sale_cycle_test.dart` `00:05 +3`; `sc_b_credit_sale_receipts_test.dart` `00:04 +2`; `sc_c_sales_return_void_test.dart` `00:25 +16`; `sc_c2_cancel_sales_return_test.dart`, `sc_c3_return_link_by_gid_test.dart` و`sc_c4_voided_after_return_report_test.dart` `00:02 +1` لكل ملف — كلها `All tests passed!`.
- `test/structural/file_size_ratchet_test.dart` — `00:02 +1: All tests passed!`; `flutter analyze test/integration/sales_return_shift_and_branch_safe_test.dart` — `No issues found! (ran in 92.6s)`.
- لا فشل حارس إضافي بين المرشحين المحليين. رسائل `ServicesBinding` التحذيرية وسطر `[AUDIT-RET] RCV-04 result=EXC: Bad state: لا يمكن أن يُنقص التحصيل المدفوع المسجل مسبقاً...` طُبعت أثناء اختبار التدقيق، لكن نتيجته كانت `All tests passed!` ولم تكن فشلاً للاختبار أو سبب الحارس.
- نقطة تفتيش نهائية: الإصلاح والمرشحون والفحوص المطلوبة اكتملت؛ لم يُعدّل `sales_mutations_dao.dart`، ولا أُجري تنسيق شامل، ولا commit/push/reset/checkout/stash.

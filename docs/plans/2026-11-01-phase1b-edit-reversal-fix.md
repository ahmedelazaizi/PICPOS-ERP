# إصلاح مسار تعديل الفاتورة SP-02

## قائمة التحقق
- [x] تحديد المسار الفعلي — القلم في `lib/presentation/sales_invoices_picpos/screens/sales_invoice_save_edit.dart:905–918` يمر إلى `SalesRepository.updateFullSalesInvoice`؛ لا يستدعي DAO المحلي `AppDatabase.updateSalesInvoice`.
- [x] اختبار يفشل أولاً — الاختبار الجديد وصل إلى assertion 5211 وفشل قبل الإصلاح؛ بعده كشف الاستعلام الاختباري خطأ عمود `type` وصُحّح إلى `movement_type`.
- [x] إصلاح المخزون — عكس/إعادة كحركات محفوظة؛ مخزون 2→3 و3→1 وno-op موثّقة بالأرقام.
- [x] إصلاح التكلفة والقيد — تكلفة WAC ملتقطة قبل الاستعادة، 5211/1136 سليمان، والآجل متوازن.
- [x] تكافؤ PostgreSQL — نجح PostgreSQL 18 على منفذ 57327؛ 57300 مستثنى من Windows.
- [ ] حزمة التحقق النهائية — نفذت المطلوب؛ بقيت 3 إخفاقات غير تحريرية خارج نطاق هذا التغيير في تدقيق المرتجعات الكامل (NOINV-01/04 وVOID-02). اختبارات EDIT-01..04 المعزولة نجحت.

## نقاط التفتيش
- نقطة تفتيش: فُحص المسار في `sales_invoice_save_edit.dart` (الأسطر 440–453 و890–919) والمستودع `sales_repository_impl.dart` (810–1017). القلم يصل إلى `updateFullSalesInvoice` لا إلى `AppDatabase.updateSalesInvoice` المغطاة في اختبار المرحلة. المستودع يعكس القيد ويعيد إدراج البنود ثم يرحّلها، لكنه لا يحدّث حركات المخزون، ولا يكتب `costPrice` على البنود الجديدة؛ لذلك يتولد COGS صفري. حمولة الواجهة لا تحمل `costPrice` وهذا وحده يفسّر التكلفة، لكنه لا يفسّر غياب المخزون.
- النسخ الاحتياطي السابق للتحرير أُنشئ عبر `Backup-ForTask phase1b-edit-fix lib/data/repositories/sales_repository_impl.dart`، ونسخة الملف محفوظة في `D:\qa\phase1b-edit-fix_backup\lib\data\repositories\sales_repository_impl.dart`.

## الأوامر وخرجها
- الأمر: `. D:\qa\luna_tools.ps1; Backup-ForTask phase1b-edit-fix lib/data/repositories/sales_repository_impl.dart; Get-Item D:\qa\phase1b-edit-fix_backup\lib\data\repositories\sales_repository_impl.dart | Select-Object FullName,Length`
- الخرج الحرفي: `D:\qa\phase1b-edit-fix_backup\lib\data\repositories\sales_repository_impl.dart 42205`

## الملفات والتغييرات
- `lib/data/repositories/sales_repository_impl.dart`: إضافة no-op gate واستدعاءات reconciler والذمم. الملف يتضمن تعديلاً متزامناً في `recordPayment` قرب السطر 381 لم ألمسه.
- `lib/data/repositories/sales_invoice_edit_reconciler.dart` (جديد): يلتقط WAC قبل استعادة السطر التاريخي، ثم يعكس المخزون/يعيد تسجيله ويفرز تكاليف السطور. اختيار التكلفة هو WAC الحالي لكل كمية السطر المعدل؛ القيد القديم يعكس لقطة تكلفته الأصلية. ذلك يعيد تقييم السطر كله لتبسيط نموذج السطر الواحد بدلاً من تمثيل طبقتي الكمية الأصلية/المضافة.
- `lib/domain/usecases/sales/calculate_invoice_totals_usecase.dart`: خيار `pricesIncludeTax` افتراضيه false لحفظ سلوك المستدعين الحاليين.
- `test/phase1/edit_reversal_live_path/edit_reversal_live_path_test.dart` و`edit_reversal_live_path_pg_test.dart` (جديدان): يستدعيان مسار المستودع الفعلي ويتحققان من الكاش/المخزون/الدفتر وPG.
- تغييرات متزامنة في ملفات fiscal/permissions/collections وسياسة المخزون تُركت دون تعديل.

## أوامر التحقق ومخرجاتها الحرفية
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase1/edit_reversal_live_path/edit_reversal_live_path_test.dart` — `00:11 +6: All tests passed!` (كاش 2→3، عدم التغيير، التخفيض 3→1، WAC الحالي عند التعديل، آجل، وخصم/ضريبة شاملة).
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase1/edit_reversal_live_path/edit_reversal_live_path_pg_test.dart -PgDsn 'postgres://postgres:<pw>@localhost:57327/postgres'` عبر حاوية `postgres:18-alpine` — `00:32 +1: All tests passed!`; أزيلت الحاوية في `finally`، وفحص `docker ps -a --filter name=picpos-phase1b-pg- --format '{{.Names}} {{.Status}} {{.Ports}}'` لم يُظهر حاوية.
- `. D:\\qa\\luna_tools.ps1; Invoke-FlutterTest test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart` — `00:11 +6: All tests passed!` (مسار DAO المحلي الموجب).
- `. D:\\qa\\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart '--plain-name=EDIT' -RunSkipped` — `00:08 +4: All tests passed!`؛ يثبت EDIT-01..04.
- `. D:\\qa\\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` — إخفاقات: NOINV-01 وNOINV-04 `Expected: a value less than or equal to <0>` / `Actual: <2.0>`؛ VOID-02 `Expected: ... <-50.0>` / `Actual: <0.0>`. EDIT cases عُزلت أعلاه ونجحت؛ VOID-02 يتأثر بتغيير تحصيل متزامن، وNOINV بسياسة المخزون المتزامنة.
- `test/scenarios/sc_a_cash_sale_cycle_test.dart` — `00:06 +3: All tests passed!`; `sc_b_credit_sale_receipts_test.dart` — `00:04 +2: All tests passed!`; `sc_c_sales_return_void_test.dart` — `00:25 +16: All tests passed!`; `sc_c2_cancel_sales_return_test.dart` — `00:02 +1: All tests passed!`; `sc_c3_return_link_by_gid_test.dart` — `00:03 +1: All tests passed!`; `sc_c4_voided_after_return_report_test.dart` — `00:03 +1: All tests passed!`.
- `test/structural/file_size_ratchet_test.dart` — `00:12 +1: All tests passed!`; `dark_mode_guard_test.dart` — `00:00 +3: All tests passed!`; `i18n_coverage_test.dart` — `00:07 +1: All tests passed!`.
- `. D:\qa\luna_tools.ps1; flutter analyze lib/data/repositories/sales_repository_impl.dart lib/data/repositories/sales_invoice_edit_reconciler.dart lib/domain/usecases/sales/calculate_invoice_totals_usecase.dart test/phase1/edit_reversal_live_path/edit_reversal_live_path_test.dart test/phase1/edit_reversal_live_path/edit_reversal_live_path_pg_test.dart` — `No issues found! (ran in 96.3s)`.
- المنفذ 57300 فشل برسالة `ports are not available... bind: An attempt was made to access a socket in a way forbidden by its access permissions.` وخرج 125؛ `netsh interface ipv4 show excludedportrange protocol=tcp` أظهر `57227–57326` محجوزاً. أُزيلت الحاوية الفاشلة، ثم نجح الاختبار على 57327 داخل النطاق المسموح.
- النسخ الاحتياطية: `Backup-ForTask phase1b-edit-fix lib/data/repositories/sales_repository_impl.dart` (42205 bytes) و`Backup-ForTask phase1b-edit-fix lib/domain/usecases/sales/calculate_invoice_totals_usecase.dart` (5656 bytes). `Diff-AgainstBackup` أظهر في المستودع no-op gate واستبدال منطق البنود باستدعاء reconciler وتسوية الذمم؛ وظهر أيضاً تعديل recordPayment المتزامن غير المملوك لي. فرق use case اقتصر على خيار الأسعار الشاملة وتمريره للحسابات. baseline لم يتغير واختبار الحجم نجح.

## مخاطر، قرارات مفتوحة، وتراجع
- الحزمة الكاملة لتدقيق المرتجعات ليست خضراء: إخفاقات NOINV-01/04 وVOID-02 بالتفصيل أعلاه تخص مسارات أخرى وتغييرات متزامنة؛ لا أصلحها هنا. **EDIT-01..04 نجحت** في التشغيل المعزول.
- مسار المستودع `updateFullSalesInvoice` نفسه لا يتضمن حالياً حارس مرتجع، بخلاف DAO الذي يرفضه. لم أغيّر هذا الاختلاف؛ إن كان مطلوباً منع التعديل من الشاشة أيضاً فهو قرار/إصلاح منفصل.
- لا تغيير في سلوك زيادة فاتورة نقدية مع بقاء المدفوع ثابتاً: البدائل للمالك (طلب تحصيل الفرق: يحافظ على النقدية/الذمم لكنه يحتاج عملية قبض؛ رفض الزيادة عند فاتورة نقدية مسددة: أبسط محاسبياً؛ قبولها كذمة: يتطلب عميلاً معرفاً وحساب AR واضحاً). لا يُنفّذ أي خيار دون موافقة.
- لا حذف صلب للقيد المصدر أو حركاته؛ reversal وحركات edit_reversal/edit_adjustment تبقى. التعديلات ضمن transaction.
- للتراجع: لا تسترجع الملفات كاملة. أزل فقط no-op gate واستدعاءات reconciler/تسوية الذمم من المستودع، واحذف helper الجديد، وأزل خيار `pricesIncludeTax` بعد مراجعة كل مستدعيه؛ أبقِ تغيير `recordPayment` المتزامن وأي تغييرات أخرى لعمال آخرين.

- Checkpoint: تحديد المسار الفعلي؛ الاختبار الأحمر وصل إلى assertion 5211 في المسار الحي.
- Checkpoint: إضافة حركات edit_reversal/edit_adjustment ولقطة التكلفة؛ الرسالة الكاملة للـrunner أظهرت لاحقاً خطأ SQL في الاختبار نفسه، لا خطأ قاعدة بيانات.
- [2026-11-01 19:03] تشخيص الرسالة الكاملة: الفشل كان خطأ اختبار فقط، no such column: type في SELECT stock_movements؛ اسم العمود الصحيح movement_type. لا يدل هذا الخطأ على فشل adjustStock أو فتح قاعدة ثانية. صححت الاستعلام وأعيد التشغيل.
- [2026-11-01 19:04] بعد تبديل شرط الاختبار إلى movement_type، نجح Invoke-FlutterTest لمسار المستودع: All tests passed!؛ الخطأ السابق كان اسم عمود في SQL الاختباري لا خطأ تنفيذ.
- [2026-11-01 19:15] بعد تفعيل prices_include_tax في إعداد قاعدة الاختبار، ظهر فشل إجمالي 253 مقابل المتوقع 220، ما أثبت أن المستودع كان يضيف VAT على السعر الشامل. أضيف دعم الأسعار الشاملة في CalculateInvoiceTotalsUseCase وتمرير القيمة من إعداد القاعدة، وحساب سطور الضرائب من FinancialUtils. كما كشف اختبار الآجل أن رصيد العميل بقي 13.98 بدل 20.97؛ أضيفت تسوية فرق الذمم داخل المعاملة. حالات الكاش/عدم التغيير/التخفيض/الآجل/الخصم والضريبة الشاملة أصبحت خضراء محلياً.
- Checkpoint: بعد انتظار تحديثات العامل المتزامن، اختبار DAO المباشر عاد أخضر (`+6`)؛ PG والحراس والسيناريوهات اجتازت، وسجل التدقيق العام بقي بثلاثة إخفاقات غير EDIT موثقة.
- [2026-11-01 19:52] Checkpoint نهائي: أضاف الاختبار تأكيد بقاء حركة sale الأصلية، ونجحت الحالات الست All tests passed؛ flutter analyze للملفات الخمسة No issues found. بقيت فقط إخفاقات التدقيق العام غير التحريرية NOINV-01/04 وVOID-02 كما هي دون تعديل.
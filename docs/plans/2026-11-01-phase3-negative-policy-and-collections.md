# المرحلة 3 — سياسة السالب والتحصيل

## قائمة التحقق
- ✔ (1) السماح بالسالب عبر `stock_shortage_policy` — SQLite/API نجحا، وAPI يرفض مع `block`.
- ✔ (2) رفض التحصيل الزائد على فاتورة محددة — DAO/API/PG يرفضون قبل أي أثر.
- ✔ (3) رفض التحصيل ≤ 0 — DAO/API يرفضان مع 422 ثابت.
- ✔ (4) منع `recordPayment` من خفض المدفوع — الرفض مع ثبات الذمم والخزنة والقيد.
- ✔ (5) أخطاء التحصيل في API برمز 422 وتصنيف دائم — الرمزان مضافان ومختبران.

## نقاط التفتيش
- البداية: قُرئ ميثاق `D:\qa\luna_charter.md` ومراجع التدقيق والمرحلة 1 وخدمة السياسة.
- خط أساس السياسة: `a_negative_stock_policy_audit_test.dart -RunSkipped` أظهر أربع فروق NEG-02/03/04/05 (`Expected: false`, `Actual: <true>`). مراجعة التوقعات بينت أن NEG-02/03/04 هي بالفعل سماح السياسة المطلوب، بينما NEG-05 كانت تثبت بقاء cache قديم `allow_negative` بعد كتابة `block`؛ NEG-09 بلا سياسة بقي مرفوضاً كما ينبغي.
- TDD قبل الإصلاح: `c_returns_void_edit_audit_test.dart -RunSkipped` أعاد RCV-02 وRCV-03 قبولاً غير متوقع (`Expected: not <true> / Actual: <true>`) وRCV-04 `Expected: 150 / Actual: 20`؛ بعد تفعيل حالات RCV من دون skip، الملف أعاد الفشل نفسه، مع 20 اختباراً متخطىً.
- TDD قبل الإصلاح: تشغيل SP-23 مع `-RunSkipped` بالتوازي اصطدم بتهيئة SQLite (`package:drift/native.dart ... _NativeDelegate.openDatabase`)، ثم التشغيل المنفرد أعاد `Expected: <200> / Actual: <422>` في حالة السماح؛ نجح اختبار idempotency `statuses=200/200 rows=1`.

## سلوك موثق وقرار التعديل
خدمة السياسة تحسم أولوية الطرفية ثم الفرع ثم العام؛ fallback الإعداد القديم يُستخدم فقط إذا لم توجد أي قيمة سياسة. وقت الفحص كان DAO والمنسق المحلي يمرران `allowNegativeStock` بالفعل، كما يحافظ `inventory_dao.dart` على سماح الصنف أو `enable_negative_sales=true`؛ أضفت القراءة الطازجة لإزالة cache stale. الفجوة التي أثبتها اختبار SP-23 كانت في `postSale` الذي لم يمرر المعامل إلى `createSalesInvoice`؛ `applyAutoDepleteForSale` المجاور يعالج خامات التصنيع لا مخزون الصنف المباع.

## Checkpoint التنفيذ
- **Checkpoint 1/5 — السياسة:** API `postSale` يمرر القرار إلى DAO؛ القرار المحلي صار يقرأ الطبقات الفعّالة بلا stale cache. اختبارات SQLite والسياسة وAPI السماح/المنع والتكلفة تعمل أدناه.
- **Checkpoint 2/5 — التحصيل الزائد:** DAO/API يرفضان المبلغ الأكبر من باقي فاتورة محددة، قبل أي أثر؛ `recordVoucherAllocations` لديه حارس تخصيص قائم، والسند العام بلا تخصيص فاتورة لا يخضع لسقف الفاتورة.
- **Checkpoint 3/5 — المبلغ غير الموجب:** DAO وAPI يرفضان `<= 0`، وAPI يستخدم 422/`PAYMENT_NOT_POSITIVE`.
- **Checkpoint 4/5 — خفض المدفوع:** repository يرفض القيمة المطلقة الأقل من `invoice.paid`؛ لم ألمس مسار إلغاء الفاتورة أو استراتيجية تخصيص المزامنة.
- **Checkpoint 5/5 — الرفض الدائم:** API يعيد 422 بالرموز العربية الثابتة؛ helper التصنيف المستدعى أثناء drain يعدّها دائمة، واختبار الوحدة يغطي الرمزين.
- DAO يرفض قيمة التحصيل ≤0 والزيادة عن المتبقي بعد جلب الفاتورة وقبل أي تحديث للمدفوع أو سند القبض؛ سند القبض العام بلا فاتورة لم يتغير.
- `SalesRepository.recordPayment` يرفض هدفاً ≤0، أو هدفاً ينقص المدفوع، أو يتجاوز الإجمالي؛ لا يحدث في هذه الحالات كتابة محلية ولا dispatch إلى outbox. المزامنة عبر `PaymentAllocationSyncStrategy` بقيت دون تعديل، ومسار الإلغاء لم يُمس.
- `postSalesPayment` يعيد 422 برمز `PAYMENT_NOT_POSITIVE` أو `PAYMENT_EXCEEDS_REMAINING` ورسالة عربية قبل أي أثر. أُضيف الرمزان لتصنيف `isPermanentSalesRejection` المستدعى في drain.
- `postSale` صار يمرر سياسة المخزون الفعالة ذات طبقات الفرع/العام إلى `createSalesInvoice`; سياسة الخامات `applyAutoDepleteForSale` بقيت منفصلة. اختبار API allow صار أخضر.
- اختبارات RCV بعد تعديل الـassert: RCV-01/02/03/04 مرّت عند `-RunSkipped`. RCV-04 يثبت رفض الخفض وثبات `paid=150` والذمة/الخزنة/1121 (`50/150/50`) وثبات عدد القيود.
- اختبار سياسة SQLite بعد تحديث التوقعات وقراءة الكاش أعاد `00:13 +9: All tests passed!` مع `-RunSkipped` (NEG-01..09). أضيف فحص حركة المخزون `unit_cost=6` وقيد 5211=78 في NEG-02؛ أُعيد تشغيل الملف بعد هذا الفحص ضمن التحقق النهائي.
- منطق السياسة تغير في `resolveForSaleWith`: قبل كان cache static يظل يطبق `allow_negative` بعد تغيير خارجي إلى `block`؛ بعد صار القرار يقرأ tiers الحالية عند كل بيع، مع أولوية الطرفية ثم الفرع ثم العام وfallback legacy كما هو. التراجع: إعادة المقطع الاحتياطي للخدمة؛ لا حذف لمنطق.

## دليل الأوامر والنتائج
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/a_negative_stock_policy_audit_test.dart -RunSkipped` — NEG-02/03/04/05 فشلت؛ NEG-09 رفض بيعاً مع رصيد 3.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` — RCV-02/03/04 فشلت؛ عيوب إضافية غير مستهدفة في NOINV/VOID.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/server_client/sp23_api_sales_test.dart -RunSkipped` — محاولة أولى فشلت ترجمةً عند `sales_repository_impl.dart:909:26` لأن `SalesInvoiceEditReconciler` لم يكن قد ظهر بعد في الشجرة المتزامنة؛ بعد ظهور `sales_invoice_edit_reconciler.dart` دون تدخلي، التشغيل النهائي أعاد `00:11 +7: All tests passed!`.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/e_pg_parity_audit_test.dart -PgDsn 'postgres://postgres@localhost:57500/postgres'` — `PG-RCV` اجتاز رفض 250 بلا أثر؛ الملف الكامل أظهر `PG-DUP-01 Expected: true / Actual: false` (عيب تكرار globalId خارج البنود). عُدّلت لاحقاً توقعات PG-NEG-02 لتطابق السماح المطلوب ولم يُعد تشغيل ملف PG بعد ذلك.
- حاوية خاصة `postgres:18-alpine` على `127.0.0.1:57500` أُزيلت بـ`docker rm -f picpos-phase3-pg`؛ لم تُستخدم كلمة مرور أو قاعدة المالك.
- نُفّذ `Backup-ForTask phase3` قبل أول تعديل لكل ملف موجود؛ `Diff-AgainstBackup phase3 <path>` راجع تغييراتنا الموضعية. بقيت تغييرات جلسات أخرى خارج نسخنا كما هي.

## نطاق الاختبارات والملفات
اختبارات السيناريو `sc_a/sc_b/sc_c/sc_d/sc_f` نجحت (`+3`, `+2`, `+16`, `+4`, `+6`). `a_negative_stock_policy_audit_test.dart -RunSkipped` أعاد `00:12 +9: All tests passed!`، و`sp23_api_sales_test.dart -RunSkipped` أعاد `00:11 +7: All tests passed!`. `c_returns_void_edit_audit_test.dart -RunSkipped` شغّل كل حالات RCV بنجاح، لكنه ظل فاشلاً بثلاثة عيوب خارج النطاق: `NOINV-01/04` (`Expected ≤0, Actual 2`, **AUD-SP-11**) و`VOID-02` (`Expected -50, Actual 0`, **AUD-SP-04**). اختبارات الدفع/القبض ذات الصلة شُغّلت ملفاً ملفاً؛ نجحت، مع فشلين عابرين `sqlite3_initialize`/error 126 في دفعة متوازية، ثم نجح كل منهما منفرداً. `file_size_ratchet_test.dart`, `dark_mode_guard_test.dart`, `i18n_coverage_test.dart` كلها أعادت `All tests passed!`. التحليل النهائي للـ13 ملفاً أعاد `No issues found! (ran in 38.3s)`. لم تُشغّل الواجهة أو الفأرة أو قاعدة المالك.

## سجل التحقق النهائي
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/phase3/negative_policy_and_payment_rejection_test.dart` → `00:00 +4: All tests passed!`.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/a_negative_stock_policy_audit_test.dart -RunSkipped` → `00:12 +9: All tests passed!`; NEG-02 أثبت مخزوناً `-13` وتكلفة حركة `6` وقيد 5211 بقيمة `78`.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` → RCV-01..04 نجحت؛ الملف الإجمالي `00:31 +21 -3` بسبب AUD-SP-11 `NOINV-01/04` وAUD-SP-04 `VOID-02` فقط.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/audit_repro/server_client/sp23_api_sales_test.dart -RunSkipped` → `00:11 +7: All tests passed!` (السماح/المنع/zero-cost والتحصيل الزائد/السالب/الجزئي/الكامل).
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/unit/offline_sync_sales_rejection_test.dart` → `00:02 +2: All tests passed!`، ويتضمن الرمزين الجديدين.
- السيناريوهات `sc_a_cash_sale_cycle_test.dart`, `sc_b_credit_sale_receipts_test.dart`, `sc_c_sales_return_void_test.dart`, `sc_d_purchase_cycle_test.dart`, `sc_f_inventory_test.dart` → `All tests passed!` (على الترتيب `+3/+2/+16/+4/+6`).
- `test/structural/file_size_ratchet_test.dart`, `dark_mode_guard_test.dart`, `i18n_coverage_test.dart` → `All tests passed!` بعد فصل helper؛ لا تعديل على baseline ولا إضافة ترجمة.
- مجموعة اختبارات أسماء `payment`/`receipt` شُغلت ملفاً ملفاً عبر `Invoke-FlutterTest`؛ نجحت كلها. محاولتان في دفعة متوازية فشلتا مؤقتاً بالرسالة `Couldn't resolve native function 'sqlite3_initialize' ... error code: 126`، وأُعيد `cheque_receipt_drift_repair_test.dart` و`receipt_qr_reaches_paper_test.dart` منفردين فنجحا. بقية دفعة الـ18 ملفاً اكتملت job `pwsh-2667` بـ`[status: completed, exit code: 0]` وكلها `All tests passed!`.
- `. D:\qa\luna_tools.ps1; flutter analyze lib/data/database/daos/sales_mutations_dao.dart lib/data/repositories/sales_repository_impl.dart lib/services/api/api_sales_handler.dart lib/services/api/sales_payment_rejection.dart lib/services/stock_shortage_policy_service.dart lib/services/offline_sync_worker.dart lib/services/offline_sync_worker/offline_sync_worker_drain.dart test/phase3/negative_policy_and_payment_rejection_test.dart test/unit/offline_sync_sales_rejection_test.dart test/audit_repro/sales_purchases/a_negative_stock_policy_audit_test.dart test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart test/audit_repro/sales_purchases/e_pg_parity_audit_test.dart test/audit_repro/server_client/sp23_api_sales_test.dart` → `No issues found! (ran in 38.3s)`.
- PG: `PG-RCV` بلا آثار؛ `PG-DUP-01` فشل منفصلاً (`Expected: true / Actual: false`).

## الملفات والفروق مقابل النسخ
- `lib/data/database/daos/sales_mutations_dao.dart` — أُضيفت حواجز `amount <= 0` و`settledAtBooking > remaining` داخل `addSalesPayment` قبل أي أثر؛ حُسب `settledAtBooking` مرة واحدة قبل الحارس. لم تُمس `updateSalesInvoice` أو ترحيلات البيع النقدي.
- `lib/data/repositories/sales_repository_impl.dart` — فرقنا الموضعي الوحيد هنا هو `recordPayment`: قبل كان `delta <= 0` يكتب `paid` مباشرة؛ بعد يرفض الهدف غير الموجب/المنخفض/الأعلى من الإجمالي. توجد في الملف تغييرات متزامنة أخرى لمسار التحرير (`SalesInvoiceEditReconciler`) ليست لنا ولم نعدلها.
- `lib/services/api/api_sales_handler.dart` و`lib/services/api/sales_payment_rejection.dart` — `postSale` يمرر السياسة؛ رفض التحصيلين يخرج 422 برمز ورسالة عربية. نُقلت صياغة الرد إلى ملف helper لتجاوز سقف حجم الملف دون رفعه.
- `lib/services/stock_shortage_policy_service.dart` — قرار البيع يقرأ tiers حديثة مباشرةً بدل cache stale؛ الأولوية بقيت terminal ثم branch ثم global ثم legacy fallback.
- `lib/services/offline_sync_worker.dart` — `isPermanentSalesRejection` يتعرف على رمزي التحصيل؛ `offline_sync_worker_drain.dart` بقي دون تعديل لأن drain يستدعي هذا المصنف.
- الاختبارات: `test/phase3/negative_policy_and_payment_rejection_test.dart` جديد؛ تحديثات RCV/NEG/SP23/PG في ملفات الاستنساخ و`test/unit/offline_sync_sales_rejection_test.dart`. تقرير المرحلة هذا جديد.

## قبل/بعد/السبب/التراجع
1. قبل: policy cache قديمة وAPI `postSale` لا يمرر `allowNegativeStock`; بعد: السماح الفعال يصل للـDAO والقراءة محدثة؛ السبب تحقيق السياسة ذات الأولوية المذكورة؛ التراجع: إعادة دالة `resolveForSaleWith` وموضع تمرير API إلى نسختيهما في `D:\qa\phase3_backup\`.
2. قبل: DAO يقبل تحصيلاً سالباً أو أكبر من الباقي ويكتب الخزنة/القيد؛ بعد: يرفض قبل المعاملة المالية. تظل الدفعة المقدمة في سند قبض عام بلا تخصيص فاتورة خارج سقف فاتورة بعينها؛ التراجع: إعادة موضع الحارس في نسخة DAO.
3. قبل: `recordPayment` يخفض `paid` بلا قيد؛ بعد: يرفض الخفض و`<=0` والزيادة، ولا يكتب ولا يرسل outbox؛ لا يوجد استعمال تسوية مشروع عبر هذا المسار في `grep`، وتخصيصات المزامنة مستقلة. الإلغاء لم يتغير؛ التراجع: إعادة فرع `delta <= 0` من نسخة المستودع.
4. قبل: API يعيد 400 لنقص المبلغ ولا يعطي أخطاء معلّمة دائمة؛ بعد: 422 برموز ثابتة ورسائل عربية وتصنيف dead-letter؛ التراجع: إعادة مواضع API والمصنف من نسخها، ثم إزالة `sales_payment_rejection.dart` المضافة حديثاً بعد إعادة callsites.

لم يُحذف منطق أعمال آخر أو يُرفع baseline. لم تُنفذ أي عمليات commit/push/reset/checkout/stash. تغييرات الجلسات الأخرى بقيت كما وجدناها؛ لم نلمس تغيير التحرير المتزامن في المستودع أو ملفات التقارير/السنة المالية.

CHECKLIST: 5/5

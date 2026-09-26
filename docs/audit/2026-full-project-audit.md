# تدقيق شامل لمشروع PicPos / UralCash ERP — 2026

- **الفرع:** `review/full-audit-2026` (آخر commit وقت التدقيق: `6104ae1e`)
- **النطاق:** `lib/` (1434 ملف Dart)، `test/` (1164 ملف `*_test.dart`)، `supabase/`، `scripts/`، `tools/`، `.github/workflows/ci.yml`، وجذر المستودع.
- **المنهج:** بحث نصّي واسع (ripgrep/`Select-String`) بأنماط محددة، ثم قراءة الأسطر المُستشهد بها. كل بند أدناه يستشهد بملف وسطر قُرئ فعلًا. لم يُقرأ `lib/data/database/database.g.dart`. لم تُشغَّل مجموعة الاختبارات. نتيجة `flutter analyze lib/` مذكورة في §3.11 (لم يكتمل التشغيل).
- **مفتاح التصنيف:**
  - الخطورة: **حرج** / **عالٍ** / **متوسط** / **منخفض**.
  - القابلية: **آمن للإصلاح الآن** (تعديل صغير ومحلي، لا يغيّر الدلالة المحاسبية ولا مخطط قاعدة البيانات) أو **يحتاج قرارًا/تصميمًا**.

> تنبيه منهجي: بعض البنود (المُعلَّمة «قراءة مساعدة») جُمعت عبر قارئ آلي قرأ الأسطر المذكورة؛ أعدتُ التحقق بنفسي من كل البنود الحرجة والعالية ومن كل بنود قائمة الإصلاحات الآمنة (§5). البنود المتوسطة/المنخفضة المُعلَّمة كذلك تستحق تأكيدًا سريعًا قبل العمل عليها.

---

## 1. ملخص تنفيذي ونظرة على البنية

### 1.1 الخلاصة

المشروع ناضج ومحمي باختبارات كثيرة، ويحتوي على **بوابة مركزية جيدة لتوازن القيد** (`createJournalEntry` مع مقارنة بوحدات صغرى وحساب فروق تقريب). مع ذلك توجد فجوات حقيقية، أهمها:

1. **حرج — نظام الترخيص قابل للكسر بالكامل:** الملح السري في `lib/services/license_service.dart:20` مكرر في أداة توليد مفاتيح **مُتتبَّعة في git** (`tools/picpos-activation/picpos-key-generator.html:174`)، والتحقق متماثل (`sha256(machineId+salt)`). أي شخص لديه المستودع أو الملف الثنائي يستطيع توليد مفاتيح تفعيل.
2. **عالٍ — مسارات تعديل تحذف قيودًا مُرحَّلة حذفًا فعليًا** بدل القيد العكسي: `sales_repository_impl.dart:855-856`، `sales_mutations_dao.dart:1092-1093` (قبل فحص الفترة)، `operational_expenses_dao.dart:922-924` (بلا فحص فترة). هذا يكسر مسار التدقيق.
3. **عالٍ — دورة حياة الشيكات:** لا يوجد تحقق من صحة انتقالات الحالة (`commercial_papers_dao.dart:169-223`)، وقيد التظهير يُحمَّل على حساب العميل الأصلي بدل المورد المُظهَّر إليه (`:314-322`، `:475-489`).
4. **عالٍ — إقفال الوردية غير ذري:** قيد العجز/الزيادة «غير قاتل» ويمكن أن يُتخطى بصمت (`treasury_dao.dart:474-477`، `:530-548`، `:805-809`)، مع أن التعليق في `:766-770` يَعِد بعكس ذلك.
5. **عالٍ — كتابات مالية/مخزنية غير ذرية أو تبتلع الخطأ:** `inventory_service.dart:127-166` يبتلع فشل قيد سند المخزون، و`api_data_handler.dart:3517-3600` (`postStockTransfer`) لا يلتف بـ`transaction`.
6. **عالٍ — كلمة مرور `admin` الافتراضية تعيد نفسها تلقائيًا** عند الإقلاع إذا لم تُضبط علامة التخصيص (`database_startup.dart:822-852`).
7. **عالٍ — الصلاحيات تُفرض في الواجهة فقط** لمعظم الكتابات المالية (سندات القبض/الصرف، القيود اليدوية): `treasury_dao.dart` لا يحتوي أي فحص صلاحية.
8. **متوسط/عالٍ — CI أحمر حتمًا:** بوابة حجم `client_write_interceptor.dart` حدّها 43,000 بايت، والملف في HEAD بحجم **48,876 بايت** (`.github/workflows/ci.yml`، خطوة *Check God-File size thresholds*).
9. **واجهة:** الخط `Cairo` مستخدم بالاسم في 6 مواضع دون إعلان في `pubspec.yaml`، وأوزان Cairo العريضة غير مضمّنة (تُجلب من الإنترنت عبر `google_fonts`). الواجهة ثابتة على `ar` (`lib/main.dart:1296`)، و54 `EdgeInsets.only(left/right)` في `lib/presentation`، و3398 نصًا عربيًا مباشرًا في `Text('…')` مقابل 28 استخدامًا فقط لـ`AppLocalizations.of`.

**عدد بنود الإصلاح الآمن في §5: 24 بندًا.**

### 1.2 البنية والوحدات

| الطبقة | المسار | ملاحظات |
|---|---|---|
| التطبيق/الإقلاع | `lib/main.dart`، `lib/app_main_screen.dart` (2095 سطرًا) | `MaterialApp` بلغة مثبتة `ar_EG` (`main.dart:1296`) |
| النواة | `lib/core/` (theme, utils, config, trial, design_system) | `financial_utils.dart` مصدر أدوات التقريب والتفاوت |
| البيانات | `lib/data/database/` (Drift + SQLCipher، DAOs، migrations، extensions)، `lib/data/repositories/` | `database.g.dart` مُولَّد ومُلتزَم في المستودع |
| المجال | `lib/domain/` (models, usecases) | بعض use cases غير مستخدمة (مثل `payroll_usecase.dart`) |
| الخدمات | `lib/services/` (journal_entry_factory, sync, api LAN server, printing, licensing, security) | خادم API محلي كبير (`api_data_handler.dart` 4740 سطرًا) |
| العرض | `lib/presentation/` — شاشات قديمة `screens/` بجانب شاشات `*_picpos/` جديدة | ازدواج واضح (مثل `reports_screen.dart` و`reports_picpos_screen.dart`) |
| المزامنة | `offline_sync_worker.dart`، `delta_pull_service.dart`، `conflict_resolution_service.dart`، `client_write_interceptor.dart` | PostgreSQL/Supabase اختياري |
| أخرى | `supabase/migrations/`، `web_app/` (مشروع ويب منفصل)، `invoice_templates/`، `tools/`، `scripts/` | |

**أكبر الملفات (بدون المولَّدة)** — مقاسة بعدد الأسطر:

| الأسطر | الملف |
|---|---|
| 4740 | `lib/services/api/api_data_handler.dart` |
| 3779 | `lib/data/database/daos/treasury_dao.dart` |
| 3519 | `lib/services/api/api_handler.dart` |
| 3385 | `lib/data/database/migrations/epoch_3.dart` |
| 3344 | `lib/presentation/pos_picpos/screens/picpos_pos_operations.dart` |
| 3006 | `lib/services/scale_protocols.dart` |
| 2927 | `lib/data/database/database.dart` |
| 2704 | `lib/data/database/daos/party_dao.dart` |
| 2581 | `lib/presentation/reports_picpos/screens/reports_picpos_screen.dart` |
| 2549 | `lib/data/database/daos/purchase_dao.dart` |
| 2327 | `lib/services/templated_invoice_service.dart` |
| 2274 | `lib/data/database/daos/accounting_autopost_dao.dart` |

---

## 2. الفجوات المالية والمحاسبية

### 2.0 ما هو مُنجز جيدًا (للسياق)

- **بوابة توازن مركزية بوحدات صغرى:** `lib/core/utils/financial_utils.dart:38-50` (`balanceTolerance = 0.01`، `toMinorUnits`)، ويُطبَّق نفس القاعدة في `lib/services/journal_entry_factory.dart:186-195` و`lib/data/database/daos/accounting_dao_writes.dart:142-149`. الفروق داخل التفاوت تُرحَّل إلى حساب `rounding_difference` مع إعادة فحص (`accounting_dao_writes.dart:148-243`)، وما فوقه يرمي استثناء.
- **فحص الفترة المالية مركزي:** `validateFinancialPeriod` (`accounting_dao_reads.dart:87-118`) يُستدعى داخل `createJournalEntry` (`accounting_dao_writes.dart:121`) لكل القيود عدا قيود الإقفال/الافتتاح.
- **إلغاء فواتير المبيعات بقيد عكسي** مع حماية التكرار: `sales_actions_dao.dart:24-48`؛ الحذف يُحوَّل إلى إلغاء (`sales_actions_dao.dart:261`، `purchase_dao.dart:2606`).
- **مرتجع المبيعات يعيد المخزون بالتكلفة المجمدة على سطر الفاتورة** (`returns_repository_impl.dart:388-407`, `:429`).
- **فرق الوردية يُحسب ويُرحَّل على حسابي العجز/الزيادة** بمعرّف قيد حتمي (`treasury_dao.dart:670-705`, `:822-888`) — لكن انظر البند 2.6.

### 2.1 فرض توازن القيد (Debit == Credit)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-01 | القيد يتوازن **بالتركيب** في قيد المبيعات: الإيراد هو الرقم الموازِن `netSalesCredit = (paid + remaining + roundingAdjustment) - vatLeg - deliveryLeg`، فخطأ في الضريبة أو الإجمالي القادم من المستدعي لا يُكتشف بل ينتقل إلى الإيراد. وإن لم يُربط حساب `output_vat` تُدمج الضريبة في المبيعات مع تحذير سجلّي فقط. | `lib/services/journal_entry_factory.dart:440-441`، `:404-409` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا |
| FA-02 | قيد المشتريات يُدين `subtotal` و`tax` ويُدائن `paid` و`remaining` دون سطر خصم ودون تحقق أن `subtotal + tax = paid + remaining` إلا عبر التفاوت العام. | `journal_entry_factory.dart:553-626` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا |
| FA-03 | فروقات حتى 0.01 تُرحَّل بصمت إلى `rounding_difference`؛ مسار خاطئ يُنتج دائمًا فرقًا صغيرًا لن يُلاحظ. في وضع العميل إن لم يُزامَن حساب التقريب يُضاف الفرق إلى أكبر سطر. | `accounting_dao_writes.dart:148-243`، `:170-210` (قراءة مساعدة) | منخفض | يحتاج قرارًا (تقرير دوري لحركة حساب التقريب) |

### 2.2 الدقة العشرية والتقريب (double مقابل وحدات صغرى)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-04 | كل المبالغ `double`/`RealColumn` في المخطط: **263** تعريف `RealColumn` في `lib/data/database/tables/*.dart`، وصفر أعمدة وحدات صغرى. الوحدات الصغرى تُستخدم فقط للمقارنة. | `lib/data/database/tables/accounting_tables.dart:23`, `:106-107` (`balance`, `debit`, `credit`) | متوسط | يحتاج قرارًا/تصميمًا (تغيير مخطط) |
| FA-05 | طريقتا تقريب مختلفتان: كاتب القيد يستخدم `double.parse(line.debit.toStringAsFixed(AppConstants.decimalPlaces))` بينما بقية الكود يستخدم `(v*m).roundToDouble()/m`. تختلفان عند أنصاف القيم الممثلة ثنائيًا، فتولّدان ترحيلات صغيرة إلى حساب التقريب. توجد أيضًا ثلاث دوال مغلِّفة متكافئة حاليًا (`FinancialUtils.round`، `NumberUtils.roundCurrency`، `AccountingValidator.roundCurrency`). | `accounting_dao_writes.dart:127-130`؛ `financial_utils.dart:54-56`؛ `number_utils.dart:49-52`؛ `accounting_validator.dart:336-338` | متوسط | يحتاج قرارًا (توحيد دالة التقريب يغيّر نتائج على الحواف) |
| FA-06 | الرواتب بلا تقريب: `netSalary = payableAmount - advancesSettled` وأجر الساعة `employee.salary / (hours * days)` يبقيان `double` خامًا، فقد تُرحَّل قيم مثل 2333.3333… | `lib/data/database/extensions/hr_extensions.dart:414`, `:1084` (قراءة مساعدة) | منخفض/متوسط | يحتاج قرارًا |

### 2.3 احتساب ضريبة القيمة المضافة وتقريبها وتوزيع الخصم

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-07 | الضريبة تُحسب **لكل سطر** على الصافي بعد الخصم ثم تُجمع؛ صافي السطر بعد توزيع خصم الفاتورة (`lineBeforeTax * discountRatio`) لا يُقرَّب ولا يُسند باقي التقريب لسطر، فمجموع الأسطر قد يختلف عن الإجمالي ببضع وحدات صغرى. المنطق مكرر في أربعة أماكن؛ واحد فقط (`table_order_totals.dart`) يُسند الانحراف لآخر سطر. | `lib/.../sales_transaction_orchestrator.dart:648-696`؛ `calculate_invoice_totals_usecase.dart:42-53`؛ `table_order_totals.dart:185-212`؛ `financial_utils.dart:121-151` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا (مصدر واحد لحساب الإجماليات) |
| FA-08 | لا دعم لأسعار شاملة الضريبة (tax-inclusive) — كل المسارات حصرية. | نفس الملفات أعلاه (قراءة مساعدة) | منخفض/متوسط | يحتاج قرارًا (متطلب سوقي) |
| FA-09 | خصم فاتورة المشتريات يوزَّع نسبيًا بلا تقريب (`v * factor`)، ثم يُخزَّن `unitCost = round(lineNet/qty)` و`total = quantity * unitCost + taxAmount`، فمجموع الأسطر قد يخالف رأس الفاتورة. | `lib/domain/models/purchase_line_discount.dart:56-63`؛ `purchase_dao.dart:972-974`, `:999` (قراءة مساعدة) | منخفض/متوسط | يحتاج قرارًا |
| FA-10 | حسابات ضريبة في طبقة الحالة/الواجهة وفي خدمات الفوترة الإلكترونية دون تقريب وقبل الخصم (`taxAmount => subtotal * (taxRate / 100)`) — قد تخالف الضريبة المخزنة. | `purchases_state.dart:27-29`؛ `sales_invoice_save_edit.dart:576-577`؛ `eta_service.dart:377`؛ `jofotara_service.dart:273` (قراءة مساعدة؛ الأخيرتان من نتائج بحث) | متوسط | يحتاج قرارًا (الفوترة الإلكترونية يجب أن تستخدم القيم المخزنة) |

### 2.4 الترحيل/إلغاء الترحيل/تعديل المستندات المُرحَّلة

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-11 | **`updateFullSalesInvoice` يحذف القيد المرحَّل حذفًا فعليًا** (`db.delete(db.journalEntryLines)` ثم `db.delete(db.journalEntries)`)، والحارس الوحيد `isLocked`. ثم يعيد حساب أرصدة الحسابات بـ`SUM(debit)-SUM(credit)` على **كل** أسطر القيود دون فلترة `is_posted`/`is_deleted`. يكسر مسار التدقيق وسلسلة الـhash. `.getSingleOrNull()` يرمي إن وُجد أكثر من قيد مطابق. | `lib/data/repositories/sales_repository_impl.dart:829`, `:840-872` | عالٍ | يحتاج قرارًا/تصميمًا (استبداله بـ`reverseJournalEntryById` + قيد جديد) |
| FA-12 | نفس الدالة تعيد حساب الإجماليات **بدون خصم وبدون تقريب**: `lineTotal = item.quantity * item.unitPrice`، `total = subtotal + totalTax`، وتأخذ `item.taxAmount` كما هو، وتحدد الحالة بمقارنة `double` مباشرة `paid >= total`. | `sales_repository_impl.dart:879-905` | عالٍ | يحتاج قرارًا/تصميمًا |
| FA-13 | **`updateSalesInvoicePayment` يحذف القيد المرحَّل قبل فحص الفترة**: الحذف في `:1092-1093` بينما `validateFinancialPeriod` في `:1109`. (الـtransaction ستتراجع إن رُمي استثناء، لكن الترتيب خاطئ وإعادة حساب الرصيد في `:1096-1101` بلا فلترة `is_posted`.) | `lib/data/database/daos/sales_mutations_dao.dart:1073-1109` | عالٍ | يحتاج قرارًا (نقل الفحص قبل الحذف آمن بذاته — انظر §5 بند 16) |
| FA-14 | **`updateSalesInvoice` (DAO) يعدّل مبالغ فاتورة مقفلة دون أي قيد**: مع صلاحية `modifyLockedInvoice` يعيد كتابة `subtotal/discount/tax/total` من قيم المستدعي، ولا يوجد داخل الدالة أي `createJournalEntry`/`reverseJournal`/`autoPost` (بحث في المدى 822-1051). النتيجة: انحراف دفتر الأستاذ عن الفواتير. | `sales_mutations_dao.dart:845-853`, `:896-910` | عالٍ | يحتاج قرارًا/تصميمًا |
| FA-15 | **`deleteExpense` يحذف القيد وأسطره حذفًا فعليًا بلا `validateFinancialPeriod`** — حذف مصروف في شهر مقفل يغيّر أرقامًا مقفلة. | `lib/data/database/daos/operational_expenses_dao.dart:905-929` | عالٍ | يحتاج قرارًا (إضافة فحص الفترة وحدها آمنة — §5 بند 17) |
| FA-16 | `rejectJournalEntry` ينفّذ `UPDATE journal_entries SET status = 'rejected'` دون شرط أن القيد مسودة — يمكن وسم قيد مرحَّل «مرفوضًا» وتبقى أرصدته محسوبة. | `accounting_dao_writes.dart:1579-1584` | متوسط | آمن للإصلاح الآن (§5 بند 15) |
| FA-17 | `approveJournalEntry` لا يستدعي `validateFinancialPeriod` (الاستدعاء الوحيد في الملف هو السطر 121) — مسودة بتاريخ في شهر أُقفل لاحقًا تُرحَّل إليه. | `accounting_dao_writes.dart:1462` (+ بحث: `validateFinancialPeriod` يظهر فقط في `:121`) | متوسط | يحتاج قرارًا (سلوك مقصود؟) |
| FA-18 | `createDraftJournalEntry` يستدعي `createJournalEntry` **مرحَّلًا** (يحرك الأرصدة ويدفع للخادم) ثم يقلب `is_posted = false` — الأرصدة المخزنة تبقى خاطئة. بلا مستدعين حاليًا (كود كامن). | `accounting_dao_writes.dart:1432-1457` (قراءة مساعدة؛ البحث يُظهر التعريف فقط) | متوسط | آمن للإزالة بعد تأكيد عدم الاستخدام (§5 بند 20) |
| FA-19 | `reverseTransaction` يختار بـ`referenceType/referenceId` فقط، بلا فحص `isPosted`/محذوف، وبلا مفتاح تكرار خاص، ولا ينقل `branchId`. | `accounting_dao_writes.dart:1383-1424` (قراءة مساعدة) | متوسط | يحتاج قرارًا |
| FA-20 | `fiscalYearId` للقيد يؤخذ من السنة **الحالية** (`getCurrentFiscalYear()`) لا من تاريخ القيد — القيود المؤرخة بأثر رجعي تُنسب للسنة الخطأ. | `accounting_dao_writes.dart:389`, `:411` | متوسط | يحتاج قرارًا (يؤثر على الإقفال) |
| FA-21 | `_checkPeriodLock` في المصنع يبتلع أي استثناء غير `PeriodLockedException` ويسمح بالقيد (خطأ قاعدة بيانات = لا فحص). الفحص الحقيقي في الـDAO يبقى قائمًا. | `lib/services/journal_entry_factory.dart:217-228` | منخفض | يحتاج قرارًا |
| FA-22 | فحص الفترة في تغيير حالة الأوراق التجارية والسندات يستخدم `DateTime.now()` لا تاريخ المستند. | `commercial_papers_dao.dart:186`؛ `treasury_dao.dart:2149`, `:2354` (الأخيران قراءة مساعدة) | منخفض | يحتاج قرارًا |

### 2.5 المرتجعات والقيود العكسية وتكلفة المخزون (COGS)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-23 | طريقة التكلفة الوحيدة المنفّذة هي المتوسط المرجّح (`enum CostingMethod { weightedAverage }`)؛ FIFO غير منفّذ رغم أن الدفعات تُستهلك FIFO/FEFO كسجل كميات فقط — تقييم المخزون من الدفعات سيخالف حساب المخزون. | `lib/services/costing_method_service.dart:35-37`؛ `inventory_dao.dart:297-305`؛ `journal_entry_factory.dart:301` (قراءة مساعدة) | متوسط | يحتاج قرارًا |
| FA-24 | مرتجع المشتريات يعكس المتوسط بتكلفة السطر الأصلية، لكن `adjustStock(type: 'purchase_return')` يُستدعى بلا `unitCost` فتُختم الحركة بالتكلفة الحالية — سجل الحركة يخالف القيد. | `purchases_repository_impl.dart:838-852`؛ `inventory_dao.dart:253` (قراءة مساعدة) | متوسط | يحتاج قرارًا (يغير تقييم التقارير) |
| FA-25 | البيع بالسالب مسموح (إعداد عام أو علم للمنتج) ويُكلَّف بالمتوسط الحالي؛ عند وصول الشراء يُعاد ضبط المتوسط دون ترحيل فرق التكلفة — المخزون والحساب 1136 ينحرفان. | `inventory_dao.dart:209-212`, `:644-661` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا |
| FA-26 | قيد سند المخزون (`createAddingBond`) **يُبتلع فشله**: `try { ... createJournalEntry ... } catch (e) { print('[FINANCIAL_WARNING] ...'); }` داخل الـtransaction، فيُلتزم المخزون والتكلفة بلا قيد؛ ويُتخطى القيد بصمت إن لم تُربط الحسابات (`if (invAccount != null && targetAccount != null)`). | `lib/services/inventory_service.dart:127-166` | عالٍ | يحتاج قرارًا (جعله قاتلًا يغيّر سلوك الحفظ) |
| FA-27 | إرسال السند للخادم يثبّت `'type': 'in'` متجاهلًا `bondType` — سندات الافتتاح/الصرف تصل للخادم كـ`in`. | `inventory_service.dart:185-186` | عالٍ | يحتاج تحققًا من معالجة الخادم قبل الإصلاح |
| FA-28 | ترحيل تكلفة المنتج صفرية التكلفة يخضع لـ`ZeroCostPolicy` (block/warn/allow)؛ مع `warn`/`allow` لا يُرحَّل COGS إطلاقًا. | `journal_entry_factory.dart:287-297` (قراءة مساعدة) | منخفض | يحتاج قرارًا (تحديد الافتراضي) |

### 2.6 إقفال الفترات المالية والوردية

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-29 | **`closeShiftWithAudit` بلا transaction شاملة** ("Removed outer transaction() wrapper")؛ الوردية تُعلَّم `closed` أولًا ثم يُرحَّل قيد الفرق «غير قاتل» (يُسجَّل الخطأ فقط). وعند عدم ربط الحسابات يعود بصمت (`variance JE skipped`) دون استدعاء callback الواجهة. تعليق الدالة نفسها (`:766-770`) يقول إن الفشل «يجب أن يتراجع عن الإقفال كله» — الكود لم يعد يفعل ذلك. | `lib/data/database/daos/treasury_dao.dart:474-477`, `:530-548`, `:766-770`, `:805-809` | عالٍ | يحتاج قرارًا/تصميمًا |
| FA-30 | قفل فواتير الوردية يتم بـ`userId` ونافذة `createdAt` لا بمعرّف الوردية؛ فواتير نفس المستخدم من محطة أخرى في نفس النافذة تُقفل أيضًا. | `treasury_dao.dart:585-593`, `:651-666` (قراءة مساعدة) | متوسط | يحتاج قرارًا |

### 2.7 الرواتب

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-31 | الرواتب **على الأساس النقدي** موظفًا موظفًا لحظة الصرف (`date: DateTime.now()`)؛ لا استحقاق رواتب مستحقة آخر الشهر، ولا «مسيّر رواتب». صرف راتب فبراير بعد إقفال مارس يفشل (التعليق نفسه يقرّ). | `hr_extensions.dart:609-611`, `:626-652` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا |
| FA-32 | منع الصرف المزدوج بفحص تطبيقي فقط؛ القيد الفريد في المخطط ما زال `TODO(owner)`، ولا يوجد مسار لعكس صرف راتب خاطئ. | `hr_extensions.dart:467` (TODO مقروء)، `:471-484`, `:509-511` | متوسط | يحتاج قرارًا (مخطط) |

### 2.8 الشيكات/الأوراق التجارية

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-33 | **لا تحقق من صحة الانتقالات** في `changePaperStatus`: يكتب `status: Value(newStatus)` مباشرة؛ التعليق «Prevent redundant status change» بلا كود. مسار `bounced → cashed` أو إعادة الإيداع بعد الارتداد ثم التحصيل يدائن «أوراق القبض» مرة ثانية فتصبح سالبة. | `lib/data/database/daos/commercial_papers_dao.dart:169-223` (خاصة `:188-201`)؛ واجهة إعادة الإيداع `commercial_papers_screen.dart:596-599` (قراءة مساعدة) | عالٍ | يحتاج قرارًا/تصميمًا (آلة حالات)؛ فحص «نفس الحالة» وحده آمن — §5 بند 18 |
| FA-34 | **قيد التظهير على الطرف الخطأ**: `payables = partySubAccount ?? payablesControl` حيث `partySubAccount` هو حساب `paper.partyId` (العميل الذي سلّمنا الشيك)، ولا يُستخدم `endorsedToPartyId` في بناء القيد. المورد المُظهَّر إليه لا ينخفض رصيده. | `commercial_papers_dao.dart:314-322`, `:475-489` | عالٍ | يحتاج قرارًا (تغيير دلالة محاسبية) |
| FA-35 | فحص تكرار القيد يعتمد جزئيًا على `description.like('$description%')` — مطابقة نصية قد تتخطى قيودًا حقيقية. | `commercial_papers_dao.dart:596-630` (قراءة مساعدة) | متوسط | يحتاج قرارًا |

### 2.9 التسوية البنكية

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-36 | `completeReconciliation` يعلّم الجلسة `completed` دون اشتراط فرق صفري أو صفر أسطر غير مطابقة. | `lib/data/database/daos/bank_reconciliation_dao.dart:301-330` | عالٍ | يحتاج قرارًا (سياسة) |
| FA-37 | البنود المطابقة غير مقفلة: `unmatchStatement` يلغي المطابقة دون فحص أن تسوية مكتملة تغطيها؛ `BankStatementLines` بلا معرّف تسوية. | `bank_reconciliation_dao.dart:213-221`؛ `tables/bank_reconciliation_tables.dart:11-32` (قراءة مساعدة) | عالٍ | يحتاج قرارًا/تصميمًا (مخطط) |
| FA-38 | المطابقة الآلية: مبلغ مطابق ±0.01 وتاريخ ±3 أيام و`LIMIT 1` بلا ترتيب أو استخدام للمرجع. | `bank_reconciliation_dao.dart:114-168` (قراءة مساعدة) | متوسط | يحتاج قرارًا |

### 2.10 أرصدة العملاء/الموردين وكشوف الحساب

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-39 | رصيد الطرف عمود مخزَّن يُعدَّل تزايديًا (`UPDATE parties SET balance = balance + ?`) بالتوازي مع القيود، وكشف الحساب يُبنى من المستندات لا من أسطر الأستاذ. يوجد كاشف انحراف جيد (`getPartyBalanceMismatches`) لكنه تشخيصي. | `party_dao.dart:1414-1436`, `:1609-1669`, `:2363-2397` (قراءة مساعدة) | عالٍ (خطر انحراف) | يحتاج قرارًا/تصميمًا |
| FA-40 | إعادة حساب أرصدة الحسابات تفلتر `je.is_posted = 1` فقط دون `is_deleted`، ويمكنها الكتابة فوق الأرصدة (`autoCorrect`). | `lib/services/balance_reconciliation_service.dart:87-91`؛ `party_dao.dart:1371-1381` (قراءة مساعدة) | متوسط | يحتاج تحققًا من دلالة `is_deleted` ثم قد يكون آمنًا |

### 2.11 العملات المتعددة

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-41 | سعر الصرف يُخزَّن لقطةً على فاتورة الشراء، لكن لا يوجد أي ترحيل لفروق صرف محققة/غير محققة رغم زرع حساب خسائر الصرف `6313`. `calculateFxRevaluation` كود ميت (يجمع مدين−دائن لكل الحسابات ≈ صفر، ولا مستدعين). | `multi_currency_dao.dart:43-60`, `:76-103`؛ `domain/models/import_purchase_plan.dart:27-32`؛ `database_seeder_accounts.dart:282` (قراءة مساعدة؛ غياب المستدعين مؤكَّد بالبحث) | متوسط | يحتاج قرارًا (قرار المالك 2026-09-18 موثق في `import_purchase_plan.dart`) |

### 2.12 مسار التدقيق (Audit Trail)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| FA-42 | لا يوجد تسجيل تدقيق داخل `accounting_dao_writes.dart` (العكس/الحذف الناعم/الاعتماد للقيود)؛ التسجيل في الواجهة فقط. كتابات التدقيق مصممة لعدم الرمي أبدًا. | `accounting_dao_writes.dart` (بحث)؛ `lib/services/audit_log.dart:54-56`, `:91-93` (قراءة مساعدة) | متوسط | يحتاج قرارًا |
| FA-43 | `AuditLogIntegrityService` (سلسلة hash للتدقيق) غير مستدعى من أي مكان في `lib/` سوى تعريفه. | `lib/services/audit_log_integrity_service.dart:19` (البحث لا يجد مستدعين) | متوسط | يحتاج قرارًا |
| FA-44 | صفوف تغيير الرصيد لا تُدقَّق عندما `changedBy <= 0` — وهي بالضبط مسارات النظام/API. | `party_dao.dart:1442` (قراءة مساعدة) | منخفض | يحتاج قرارًا |

---

## 3. الفجوات الفنية/التقنية

### 3.1 الأسرار المضمّنة والتشفير

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-01 | **ملح الترخيص مضمّن ومتماثل ومكشوف في أداة مُتتبَّعة.** `_secretSalt = 'UralCash_Secure_Salt_2026'`، و`generateKey` = أول 16 خانة من `sha256(machineId + salt)`، و`verifyKey` يعيد التوليد ويقارن. الأداة `tools/picpos-activation/picpos-key-generator.html` (السطر 174: `var SALT='UralCash_Secure_Salt_2026';`) **مُلتزمة في git** (commit `6104ae1e`)، رغم أن `.gitignore` ينص «license/keygen tooling must NEVER be tracked» — النمط `tools/*keygen*` لا يطابق `tools/picpos-activation/picpos-key-generator.html`. | `lib/services/license_service.dart:20`, `:71-77`, `:82`؛ `tools/picpos-activation/picpos-key-generator.html:173-177`؛ `.gitignore` (قسم «Security: license/keygen tooling») | **حرج** | يحتاج قرارًا/تصميمًا (توقيع غير متماثل Ed25519 + تدوير + إزالة من التاريخ) |
| TE-02 | مفتاح SQLCipher مشتق من `deviceId` + «pepper» ثابت مُخفى بـ`String.fromCharCodes` (`UralCash_Security_Pepper_v2`) — قابل لإعادة البناء لمن يملك الثنائي والجهاز. الأسوأ: عند فشل التخزين الآمن يُولَّد **مفتاح عشوائي لكل جلسة** → قاعدة بيانات لا يمكن فتحها مجددًا (فقدان بيانات). | `lib/services/security_service.dart:440-447`, `:484-489` | عالٍ | يحتاج قرارًا/تصميمًا |
| TE-03 | نفس مفتاح قاعدة البيانات يُستخدم بذرةً لرمز API المحلي وHMAC الجلسات (`const salt = 'UralCash-API-v1'`، `_salt = 'UralCash-Session-v1'`) — سرّ واحد يحمي ثلاثة أشياء. | `lib/services/api/api_auth_middleware.dart:50`؛ `lib/services/api/api_session_token.dart:30`؛ `network_service.dart:656` (قراءة مساعدة) | متوسط | يحتاج قرارًا |
| TE-04 | مفتاح HMAC لسلامة الفواتير ثابت في المصدر (`_secretKey = 'UralCash-ERP-Integrity-v1'`) — كشف التلاعب فعليًا غير موجود. مثله `table_bill_token.dart:81`. | `lib/services/invoice_integrity_service.dart:11`, `:141`؛ `lib/services/api/table_bill_token.dart:81` | متوسط | يحتاج قرارًا |
| TE-05 | **كلمة مرور `admin` تعيد نفسها**: `shouldHeal = saltBroken || hashBroken || (!defaultVerifies && !adminPasswordCustomized)` ثم `UPDATE users SET password_hash=?, password_salt=?, is_active=true WHERE username='admin'`. أي تغيير لكلمة المرور لا يضبط علامة `admin_password_customized` (API/مزامنة/فقدان الإعداد) يُعاد إلى `admin` ويُعاد تفعيل الحساب عند الإقلاع التالي. | `lib/data/database/database_startup.dart:812-852`؛ مشابه `lib/main.dart:1126-1135` و`scripts/reset_user_password.dart:45` (قراءة مساعدة) | عالٍ | يحتاج قرارًا |
| TE-06 | كلمة مرور PostgreSQL تُحفظ نصًا صريحًا في `SharedPreferences` (`prefs.setString(_configKey, jsonEncode(toJson()))`)، بينما `remote_backup_config.dart` يستخدم التخزين الآمن للغرض نفسه. | `lib/data/database/pg_config.dart:59`, `:147-151`؛ مقارنة `lib/services/backup/remote_backup_config.dart:67`, `:96-102` | متوسط | يحتاج تصميمًا بسيطًا (ترحيل الإعداد المخزن) |
| TE-07 | كلمة مرور قاعدة اختبار حقيقية في سكربت مُتتبَّع: `postgres://postgres:14590@127.0.0.1:5432/picpos`. | `scripts/gate.sh:511`؛ `docs/superpowers/handoff/2026-08-04-road-to-go.md:196` (قراءة مساعدة) | منخفض | آمن للإصلاح الآن (§5 بند 3) |
| TE-08 | ما هو سليم: Supabase عبر `String.fromEnvironment` بقيمة افتراضية فارغة (`lib/core/config/supabase_config.dart:12-21`)؛ `.env` مُتجاهل و`.env.example` فقط موجود؛ لا مفاتيح `service_role` سوى تعليق في `supabase/migrations/0002_rls_policies.sql:17`. فحص `gitleaks` في CI لن يلتقط أملاحًا نصية مثل TE-01/TE-04. | الملفات المذكورة؛ `.github/workflows/ci.yml` (job `secrets-scan`) | — | — |

### 3.2 فرض الصلاحيات

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-09 | الصلاحيات ثلاث طبقات: واجهة (`PermissionGuard`)، API (`ApiUserCtx.requirePermission`)، وDAO عبر `PermissionEnforcer` **للعمليات الحرجة فقط** (مثل `voidPaidInvoice`، `modifyLockedInvoice`). على سطح المكتب تُستدعى الـDAOs مباشرة. `treasury_dao.dart` (3779 سطرًا) **لا يحتوي أي كلمة `permission`**؛ `createReceiptVoucher` (`:2091`) و`createPaymentVoucher` (`:2322`) بلا فحص. `createJournalEntry` كذلك. | `treasury_dao.dart:2091`, `:2322` (بحث)؛ `accounting_dao_writes.dart:12-66` (قراءة مساعدة)؛ `lib/services/permission_enforcer.dart`؛ `sales_mutations_dao.dart:845-853` (مثال على الفرض الصحيح) | عالٍ | يحتاج قرارًا/تصميمًا |
| TE-10 | مدير التمهيد (bootstrap admin) يتجاوز كل صلاحيات API (`if (isBootstrapAdmin(userId)) { ... return null; }`) بينما طبقة DAO لا تستثني المدير من العمليات الحرجة — تناقض في فصل المهام، ومع TE-05 يصبح خطيرًا. | `lib/services/api/api_user_context.dart:87-100` | متوسط | يحتاج قرارًا |

### 3.3 معالجة الأخطاء والاستثناءات المبتلعة

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-11 | **216** موضعًا لـ`catch (_) {}` بسطر واحد في `lib/` (باستثناء `database.g.dart`)، منها في المزامنة والمال: `offline_sync_worker.dart` (6)، `client_write_interceptor.dart` (3)، `websocket_sync_client.dart` (3)، `sales_transaction_orchestrator.dart` (3)، `purchase_dao.dart` (2)، `treasury_dao.dart` (1)، `journal_sync_strategy.dart` (1)، `conflict_resolution_service.dart` (1). | عدّ بالبحث؛ أمثلة: `journal_sync_strategy.dart:134-144`، `conflict_resolution_service.dart:177-178`, `:188-199` (قراءة مساعدة) | متوسط | يحتاج مراجعة حالة بحالة |
| TE-12 | تخطي القيد بصمت عند غياب ربط الحساب بـ`debugPrint` بدل خطأ: `treasury_dao.dart:805-809` (مؤكَّد)، و`:828`، `:847`، `inventory_dao.dart:349-350`، `landed_cost_dao.dart:401`, `:478` (قراءة مساعدة). | كما ذُكر | متوسط | يحتاج قرارًا |
| TE-13 | `print(` مستخدم في 102 سطر في `lib/`، و`avoid_print: false` في `analysis_options.yaml`؛ رسائل مالية حرجة مثل `[FINANCIAL_WARNING]` تذهب إلى stdout لا إلى `DiagnosticLogger`. | `analysis_options.yaml` (قسم `linter`)؛ `inventory_service.dart:164-165` | منخفض | آمن جزئيًا (§5 بند 19) |

### 3.4 المزامنة وحل التعارضات

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-14 | الخادم يفوز لكل الجداول عدا `parties` و`shifts` اللذين يستخدمان `newerWins`: `row_version` ثم `last_modified_at` (ساعة الجهاز بدقة ثانية عبر trigger) ثم `origin_client_id`. انحراف الساعة أو كثرة التعديلات يحسم الفائز. | `conflict_resolution_service.dart:51-56`, `:123-165`؛ `migrations/epoch_3.dart:1529-1536` (قراءة مساعدة) | متوسط | يحتاج قرارًا/تصميمًا |
| TE-15 | الحذف الناعم القادم من الخادم يُطبَّق **قبل** `shouldApplyServerRow` وداخل `catch (_) {}`؛ وعند التعارض يُعلَّم تعديل العميل المحلي «متزامنًا» ويُسحب حال الخادم (`server_wins_pull_triggered`) — تعديلات مالية محلية قد تُفقد والأثر الوحيد سجل تعارض يُدرَج داخل `catch (_) {}` أيضًا. | `delta_pull_service.dart:863-877`؛ `offline_sync_worker.dart:568-584` (قراءة مساعدة) | متوسط/عالٍ | يحتاج قرارًا/تصميمًا |
| TE-16 | البحث الاحتياطي بالمعرّف الرقمي `id` عند غياب `global_id` قد يقارن بسجل محلي غير مرتبط (المعرّفات تتباعد بين العميل والخادم). | `conflict_resolution_service.dart:111-118` (قراءة مساعدة) | متوسط | يحتاج قرارًا |

### 3.5 الذرّية (Transactions)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-17 | **`postStockTransfer` في خادم API بلا `db.transaction`**: يُدرج رأس السند (`:3547`) ثم يدور على الأصناف بـ`adjustStock` خروجًا (`:3576`) ودخولًا (`:3587`)؛ رمي في منتصف الحلقة (`:3570`) يترك أصنافًا منقولة جزئيًا أو مخصومة من المصدر دون إضافتها للوجهة. | `lib/services/api/api_data_handler.dart:3517-3600` | عالٍ | يحتاج قرارًا بسيطًا (التغليف بـtransaction تغيير صغير لكنه في مسار إنتاجي حساس — مرشح قوي لإصلاح قريب مع اختبار) |
| TE-18 | أرقام السندات بالطابع الزمني بالملّي ثانية (`'BND-${DateTime.now().millisecondsSinceEpoch}' // Temporary logic`، `TRF-…`) — تصادم محتمل تحت الكتابة المتزامنة. | `inventory_service.dart:61-62`؛ `api_data_handler.dart:3549` | منخفض | يحتاج قرارًا (ترقيم تسلسلي) |
| TE-19 | أمثلة سليمة للمقارنة: `voidSalesInvoice` (`sales_actions_dao.dart:24`)، `createJournalEntry` (`accounting_dao_writes.dart:66`)، `createPaymentVoucher` (`treasury_dao.dart:2352`)، `createAddingBond` (`inventory_service.dart:57`، لكن انظر FA-26). | — | — | — |

### 3.6 الملفات العملاقة (God files) وبوابات CI

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-20 | **بوابة حجم CI ستفشل على HEAD:** الحد لـ`lib/services/client_write_interceptor.dart` هو `43000` بايت («never raise»)، وحجم الملف في HEAD `48,876` بايت (`git cat-file -s HEAD:...`)؛ آخر تعديل عليه في `7a1d8a53`. | `.github/workflows/ci.yml` (خطوة «Check God-File size thresholds») | متوسط/عالٍ | يحتاج قرارًا (تقسيم الملف كما يعِد التعليق، لا رفع الحد) |
| TE-21 | البوابة تراقب 3 ملفات فقط، اثنان منها صغيران الآن (`tables_screen.dart` 12,143 بايت، `pos_table_service_screen.dart` 6,304 بايت)، بينما أكبر الملفات (جدول §1.2، مثل `api_data_handler.dart` 4740 سطرًا و`treasury_dao.dart` 3779 سطرًا) غير مراقبة. | `ci.yml`؛ قياس الأحجام | منخفض | آمن للإصلاح الآن كإضافة حدود «سقف الحجم الحالي» (§5 بند 5) |

### 3.7 الكود الميت وTODO

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-22 | ملفات `.bak` مُتتبَّعة داخل `lib/`: `lib/data/database/database.dart.bak` (35 KB) و`lib/presentation/widgets/settings/pos_settings_widget_backup.dart.bak` (31 KB)؛ تظهر في نتائج البحث وتضلل المدققين. | `git ls-files lib` | منخفض | آمن للإصلاح الآن (§5 بند 2) |
| TE-23 | دوال مستودع مبيعات تعيد `null` دائمًا (`return null; // TODO: Implement mapping`) — بلا مستدعين حاليًا لكنها تلبي واجهة. | `lib/data/repositories/sales_repository_impl.dart:131-144` | منخفض | يحتاج قرارًا (تنفيذ أو `UnimplementedError`) |
| TE-24 | كود كامن غير مستخدم في مجال مالي: `createDraftJournalEntry` (FA-18)، `calculateFxRevaluation` (FA-41)، `AuditLogIntegrityService` (FA-43)، `payroll_usecase.dart:24-26` (قراءة مساعدة). | كما ذُكر | منخفض | يحتاج قرارًا |
| TE-25 | TODO/FIXME قليلة (12 فعلية) — أهمها قانونية/مالية: `treasury_dao.dart:2002` (لا مسار حذف لسند القبض)، `sales_mutations_dao.dart:398` (ترحيل تاريخي لمرتجعات آجلة)، `hr_extensions.dart:467` و`fingerprint_repository_impl.dart:47` (قيود UNIQUE مفقودة)، `stock_requisitions_screen.dart:154` (زر ميت)، `sync_service.dart:596` (مزامنة الفروع غير مفعلة). | بحث `TODO|FIXME` | منخفض | — |

### 3.8 إعدادات التحليل الساكن

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-26 | `analysis_options.yaml` يُسكت تشخيصات مهمة: `unrelated_type_equality_checks`، `use_build_context_synchronously`، `invalid_use_of_protected_member`، `invalid_use_of_visible_for_testing_member`، `dead_code`، `unused_*`، `body_might_complete_normally_catch_error`. الأول بالذات يخفي أخطاء مقارنة حقيقية (مثل مقارنة `int` بـ`String`). | `analysis_options.yaml` (قسم `analyzer.errors`) | متوسط | يحتاج قرارًا (تفعيلها تدريجيًا كـwarning) |

### 3.9 تغطية الاختبارات للمنطق المالي

- التغطية المقيسة ~21% وأرضية CI 18% (تعليق في `.github/workflows/ci.yml`، خطوة «Coverage hard gate»).
- توجد اختبارات كثيرة وجيدة للتوازن والعكس والتقريب والضريبة والشيكات والتسوية البنكية والرواتب (أمثلة: `test/unit/journal_balance_validation_test.dart`، `test/structural/journal_balance_single_rule_test.dart`، `test/integration/pir_fiscal_period_blocking_test.dart`، `test/unit/commercial_papers_state_machine_test.dart`، `test/integration/bank_reconciliation_cycle_test.dart`، `test/unit/salary_payment_duplicate_guard_test.dart`).
- **فجوات اختبار** (من أسماء الملفات وغياب المطابقات): لا اختبار واضح لـ`updateFullSalesInvoice`/`updateSalesInvoicePayment` (حذف القيد، FA-11/FA-13)، ولا لـ`rejectJournalEntry`/`reverseTransaction`/`createDraftJournalEntry`، ولا لحذف مصروف في فترة مقفلة (FA-15)، ولا لاعتماد مسودة بعد إقفال شهرها (FA-17)، ولا لتظهير الشيك إلى مورد (FA-34) أو ارتداد→إعادة إيداع→تحصيل (FA-33)، ولا لذرّية `postStockTransfer` (TE-17)، ولا لسلامة سلسلة سجل التدقيق.
- لم أشغّل الاختبارات؛ الحكم على التغطية مبني على أسماء الملفات والبحث فقط.

### 3.10 نظافة المستودع

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| TE-27 | ملفات `flutter_01..12.log` و`build_picpos.log` وملفا `.zip` في الجذر **غير مُتتبَّعة ومُتجاهلة فعلًا** (`.gitignore`: `flutter_*.log`، `build_*.log`، `*.zip`) — فوضى محلية فقط، لا مشكلة في المستودع. | `git check-ignore -v` | منخفض | آمن (حذف محلي اختياري، ليس جزءًا من هذا التقرير) |
| TE-28 | `assets/fonts/NotoNaskhArabic-Regular.ttf.root-backup` غير مُتتبَّع **وغير مُتجاهل** — عرضة للالتزام العرضي. | `git status --short` | منخفض | آمن للإصلاح الآن (§5 بند 1) |
| TE-29 | مُتتبَّع في الجذر: 5 ملفات SQL (`migration_v122_regions.sql`، `migration_v123_shift_closing.sql`، `migration_v151_shift_closing_snapshot.sql`، `supabase_migration_v118.sql`، `supabase_migration_v119.sql`) بجانب `supabase/migrations/`؛ و`test_runner.dart`؛ ونحو 30 ملف HANDOFF/PLAN/RELEASE_NOTES/PROMPT. `supabase_migration_v118.sql` مُشار إليه من `lib/services/api/api_handler_base.dart:83` ومن وثائق — نقله يتطلب تحديث المراجع. | `git ls-files` | منخفض | يحتاج قرارًا (نقل إلى `docs/handoff/` و`db/legacy_migrations/`) |
| TE-30 | توثيق مكرر: `invoice_templates/*.md` مكررة تحت `invoice_templates/design/invoice_templates/`، و`NEXT-SESSION-PROMPT.prev-2026-08-28.md`. | `git ls-files "*.md"` | منخفض | يحتاج قرارًا |

### 3.11 نتيجة `flutter analyze lib/`

**لم تكتمل.** شُغّل `flutter analyze lib/ --no-pub` في الخلفية وبقي أكثر من 40 دقيقة دون أي مخرجات (بالتزامن مع عمليات `flutter_tester` من جلسة أخرى على نفس الجهاز)، فأُوقف. لا يدّعي هذا التقرير أن التحليل نظيف أو غير نظيف؛ يُنصح بتشغيله منفردًا. ويُلاحظ أن أي نتيجة «نظيفة» تبقى محدودة بسبب التشخيصات المُسكتة في TE-26.

---

## 4. فجوات الواجهة (UI/UX)

### 4.1 الخطوط

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-01 | لا يوجد قسم `fonts:` في `pubspec.yaml` (الأسطر 172-188 قالب معلّق)؛ الخطوط مضمّنة كـ`assets:` فقط: `Cairo-Regular.ttf` (`:145`)، `NotoNaskhArabic-Regular.ttf` (`:160`)، `NotoNaskhArabic-Bold.ttf` (`:163`). | `pubspec.yaml:143-188` | متوسط | آمن للإصلاح الآن (§5 بند 6) |
| UI-02 | الاسم `'Cairo'` مستخدم مباشرة في 6 مواضع دون إعلان عائلة بهذا الاسم ⇒ يسقط إلى خط النظام: `pos_main_operations.dart:113`, `:188`, `:314`, `:320`, `:333`؛ `fatal_setup_error_screen.dart:81`. | `lib/presentation/pos/screens/pos_main_operations.dart`؛ `lib/presentation/screens/fatal_setup_error_screen.dart` | متوسط | آمن للإصلاح الآن (§5 بند 6/7) |
| UI-03 | الثيم يعتمد `GoogleFonts.cairo(...)` (886 استدعاء `GoogleFonts.` في `lib/`) مع تضمين الوزن العادي فقط؛ الأوزان w600/w700/w800 تُجلب من الشبكة وقت التشغيل (لا يوجد `allowRuntimeFetching` في أي مكان)، والتعليق في `app_theme.dart:23-24` يقرّ بأن «أوزان مش مضمّنة». على POS غير متصل يسقط الخط العريض إلى خط النظام. | `lib/core/theme/app_theme.dart:23-24`, `:56`, `:84`؛ `lib/core/theme/picpos_theme.dart` (قراءة مساعدة للأسطر) | متوسط | آمن للإصلاح الآن بإضافة ملفات الأوزان (§5 بند 8) |
| UI-04 | `fontFamily: 'monospace'` في 60 موضعًا (مثل `lib/core/design_system/typography.dart:76`, `:83`) — اسم عام بلا تعيين مضمون على Windows؛ و`'Consolas'` (مرتان) و`'Courier'` (مرة). | بحث `fontFamily: '…'` | منخفض | آمن للإصلاح الآن (§5 بند 9) |

### 4.2 الاتجاه RTL

الواجهة مثبتة على `locale: const Locale('ar', 'EG')` (`lib/main.dart:1296`) مع إعلان `en_US` مدعومًا (`:1297`) — لذا القيم الفيزيائية تعمل «بالصدفة» اليوم؛ `right` = البداية و`left` = النهاية. **عند تحويلها إلى Directional يجب التعيين `right → start` و`left → end` للحفاظ على الشكل الحالي.**

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-05 | الأعداد في `lib/presentation`: `EdgeInsets.only(left|right:` = 54، `Alignment.centerLeft/Right` = 74، `TextAlign.left/right` = 16، `Positioned(left|right:` = 2، مقابل `EdgeInsetsDirectional` = 25 فقط. | بحث | منخفض (اليوم) / عالٍ (عند تفعيل الإنجليزية) | آمن للإصلاح الآن للأمثلة في §5 |
| UI-06 | أمثلة مؤكدة: `shell/nav_widgets.dart:358` (`EdgeInsets.only(right: 22, left: 6, …)`)، `shell/report_category_nav.dart:98`, `:140`، `screens/general_ledger_screen.dart:509` (إزاحة الشجرة `right: 16.0 + (level * 12.0)`)، `widgets/notifications/notification_bell.dart:30` (`Alignment.centerLeft` مع تعليق يقرّ بالمشكلة)، `pos/widgets/header/pos_header_button.dart:20`، `widgets/enhanced_components.dart:361` (`Positioned(right: 0, …)`)، `screens/help_center_screen.dart:244` (`fromLTRB(40, 0, 16, 12)`). | الملفات تحت `lib/presentation/` | منخفض | آمن للإصلاح الآن |
| UI-07 | استخدامات مقصودة يجب تركها: `TextDirection.ltr` في لوحات المفاتيح الرقمية/الإنجليزية وحقول الرموز، و`Directionality(rtl)` الصريحة في `pos_main_operations.dart:610`، وإحداثيات مصمم المخطط. | (قراءة مساعدة) | — | لا تُعدَّل |

### 4.3 أزرار بلا معالِج

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-08 | **زر ميت:** أيقونة «عرض» في طلبات المخزون `onPressed: () { // TODO: View details }` — يبدو فعالًا ولا يفعل شيئًا. هو الموضع الوحيد لـ`onPressed: () {}` الفارغ في `lib/presentation`. | `lib/presentation/screens/inventory/stock_requisitions_screen.dart:150-156` | متوسط | آمن للإصلاح الآن (§5 بند 10) |
| UI-09 | زر «الميزان ▾» كابن لـ`PopupMenuButton` بـ`onPressed: null` ⇒ يُرسم بمظهر معطَّل (رمادي) رغم أن القائمة هي الفعل. المشروع نفسه وثّق الحل في `tables_picpos_screen.dart:363-367` (`IgnorePointer` + `onPressed: () {}`)، وذكر أن الزر المعطَّل «يبتلع الضغطة». | `lib/presentation/screens/products/widgets/product_search_header.dart:208-214` | متوسط | آمن للإصلاح الآن (§5 بند 11) |
| UI-10 | حالات تعطيل مقصودة (لا تُعدَّل): `permission_guard.dart:309-333`، `e_invoicing_picpos_screen.dart:1048`, `:1068`، `pos/widgets/product_grid.dart:619-646`، `editor_properties_panel.dart:448`. | (قراءة مساعدة) | — | — |

### 4.4 الألوان والوضع الداكن

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-11 | 674 `Color(0x…)` و911 `Colors.white` و92 `Colors.black…` في `lib/presentation`. الألوان المركزية في `lib/core/theme/app_colors.dart` (ثابتة للوضع الفاتح)، والمساعدات الواعية بالوضع الداكن في `lib/presentation/picpos_shell/picpos_surface.dart:17-50` (`context.picposCard/Field/Text`). لوحات حالة مكررة محليًا في عدة شاشات (`_ok/_warn/_err` في `analytics_picpos_screen.dart:55`، `e_invoicing_picpos_screen.dart:71`، …). | بحث؛ (قراءة مساعدة للملفين) | متوسط | يحتاج خطة (تدريجي) |
| UI-12 | كاسرات الوضع الداكن المؤكدة: `journal_templates_screen.dart:37` (`AppBar backgroundColor: Colors.white`)، `chart_of_accounts_screen.dart:317` و`journal_entries_screen.dart:323` (`fillColor: Colors.white`)، `cost_centers_screen.dart:180` (بطاقة `color: Colors.white`)، `widgets/dialogs/product_form_helpers.dart:136` (`color: Colors.black87` لنص الإدخال). | `lib/presentation/screens/...` | منخفض/متوسط | آمن للإصلاح الآن (§5 بنود 12-13) |

### 4.5 النصوص غير المترجمة

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-13 | l10n مُعد (`l10n.yaml`، `lib/l10n/app_ar.arb`، `app_en.arb`، `generate: true`) لكنه شبه غير مستخدم: 28 استدعاء `AppLocalizations.of` مقابل **3398** سطرًا من `Text('<عربي>…')` في `lib/presentation`. أمثلة: القيم الافتراضية `'تأكيد'`/`'إلغاء'` في `widgets/common_widgets.dart:20-21`، التلميح `'الإشعارات'` في `notification_bell.dart:21`. | بحث؛ الملفات المذكورة | منخفض (طالما العربية وحدها) | يحتاج قرارًا (هل الإنجليزية هدف؟) |

### 4.6 مخاطر الفيض (Overflow)

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-14 | عنوان `ConfirmDialog` داخل `Row` بلا `Flexible` (`Text(title)`) — عنوان طويل يفيض. | `lib/presentation/widgets/common_widgets.dart:34-42` | منخفض | آمن للإصلاح الآن (§5 بند 14) |
| UI-15 | `Text('تعديل فاتورة #${widget.invoice.invoiceNumber}')` في `Row` عنوان الحوار. | `lib/presentation/pos/widgets/pos_edit_invoice_dialog.dart:108-117` | منخفض | آمن للإصلاح الآن (§5 بند 14) |
| UI-16 | اسم الطاولة بخط 18 w800 داخل `Column` في `Row` رأس POS بلا `Flexible`/`ellipsis`. | `lib/presentation/pos/widgets/table_pos/table_pos_header.dart:89-97` | منخفض | آمن للإصلاح الآن (§5 بند 14) |

### 4.7 تناسق الأزرار

| # | البند | الدليل | الخطورة | القابلية |
|---|---|---|---|---|
| UI-17 | 285 استدعاء `ElevatedButton.styleFrom(` في `lib/presentation` ولا يوجد مكوّن زر مشترك؛ ألوان الخطر خام ومتباينة: `Colors.red` (`sales_batch_action_bar.dart:90`، `sales_returns_picpos_logic.dart:651`)، `Colors.red.shade600` (`sales_batch_action_bar.dart:137`، `purchases_picpos_screen.dart:368`)، `Colors.red.shade700` (`pos_main_operations.dart:118`)، `Colors.red` (`pos_main_operations.dart:436`). | بحث مؤكَّد | منخفض | آمن للإصلاح الآن للأمثلة (§5 بند 21)؛ مكوّن مشترك يحتاج قرارًا |
| UI-18 | ازدواج الشاشات القديمة والجديدة (`screens/` مقابل `*_picpos/`)، مثل `screens/reports_screen.dart` (1840 سطرًا) و`reports_picpos/screens/reports_picpos_screen.dart` (2581 سطرًا)، و`screens/inventory/widgets/stock_movements_table.dart` مقابل `inventory_picpos/widgets/stock_movements_table_picpos.dart` — تباين في السلوك والمظهر وتكلفة صيانة مضاعفة. | قياس الأحجام؛ (قراءة مساعدة) | متوسط | يحتاج قرارًا |

---

## 5. قائمة الإصلاحات الآمنة المقترحة

كل بند مستقل، صغير، لا يغيّر مخطط قاعدة البيانات ولا نتيجة محاسبية لمسار صحيح. التحقق المقترح لكل بند: `flutter analyze lib/` + فحص بصري/اختبار ذي صلة.

**نظافة المستودع وCI**

1. **`.gitignore`**: أضف سطر `*.root-backup` (يغطي `assets/fonts/NotoNaskhArabic-Regular.ttf.root-backup` دون حذفه). التحقق: `git status --short` لم يعد يُظهره.
2. **ملفات `.bak`**: `git rm lib/data/database/database.dart.bak lib/presentation/widgets/settings/pos_settings_widget_backup.dart.bak` وأضف `*.bak` إلى `.gitignore`. التحقق: `git ls-files lib | Select-String '\.bak$'` فارغ.
3. **`scripts/gate.sh:511`**: استبدل القيمة الافتراضية `postgres://postgres:14590@127.0.0.1:5432/picpos` بـ`${PG_TEST_DSN:?PG_TEST_DSN must be set}` (أو قيمة عامة مثل `postgres:postgres`)، ثم غيّر كلمة المرور الفعلية على قاعدة الاختبار. وحدّث المثال في `docs/superpowers/handoff/2026-08-04-road-to-go.md:196`.
4. **`.gitignore`**: أضف `tools/picpos-activation/` بجانب قسم «license/keygen tooling» (لمنع إعادة الإضافة مستقبلًا). *ملاحظة:* لا يزيل الملف المُلتزم؛ الإزالة والتدوير في §6 (TE-01).
5. **`.github/workflows/ci.yml`**: أضف إلى `THRESHOLDS` أكبر الملفات بسقف = حجمها الحالي بالبايت (منع النمو فقط)، مثل `lib/services/api/api_data_handler.dart` و`lib/data/database/daos/treasury_dao.dart` و`lib/services/api/api_handler.dart`. (لا تمس حد `client_write_interceptor.dart` — انظر §6.)

**الخطوط**

6. **`pubspec.yaml`**: أضف تحت `flutter:` قسم:
   ```yaml
   fonts:
     - family: Cairo
       fonts:
         - asset: assets/fonts/Cairo-Regular.ttf
   ```
   فيصبح `fontFamily: 'Cairo'` في `pos_main_operations.dart:113,188,314,320,333` و`fatal_setup_error_screen.dart:81` صالحًا. التحقق: تشغيل شاشة POS ورؤية Cairo في الحوارات.
7. **بديل/مكمّل للبند 6**: في `lib/presentation/pos/screens/pos_main_operations.dart` احذف `fontFamily: 'Cairo'` من الأسطر 113، 188، 314، 320، 333 ليرث خط الثيم.
8. **أوزان Cairo**: أضف `assets/fonts/Cairo-SemiBold.ttf` و`Cairo-Bold.ttf` و`Cairo-ExtraBold.ttf` (رخصة OFL) وأعلنها في `assets:` بنفس نمط `Cairo-Regular.ttf` (`pubspec.yaml:145`) — `google_fonts` يلتقط الأصول المحلية بالاسم ولن يحتاج الشبكة. التحقق: تشغيل دون إنترنت والتأكد من ظهور العريض.
9. **`lib/core/design_system/typography.dart:72-84`**: أضف `fontFamilyFallback: ['Consolas', 'Courier New']` إلى `priceLarge` و`priceRegular`.

**الأزرار**

10. **`lib/presentation/screens/inventory/stock_requisitions_screen.dart:150-156`**: إما ربط الزر بحوار تفاصيل موجود، أو (الأبسط) `onPressed: null` مع `tooltip: 'قريبًا'`، أو إزالة الزر. لا تتركه فعالًا بلا فعل.
11. **`lib/presentation/screens/products/widgets/product_search_header.dart:208-209`**: لفّ `OutlinedButton.icon` بـ`IgnorePointer(child: ...)` وغيّر `onPressed: null` إلى `onPressed: () {}` — مطابقًا للنمط الموثق في `lib/presentation/tables_picpos/screens/tables_picpos_screen.dart:363-367`. التحقق: الزر بلون `AppColors.warning` والقائمة تُفتح.

**الوضع الداكن**

12. **`lib/presentation/screens/journal_templates_screen.dart:37-38`**: احذف `backgroundColor: Colors.white` و`foregroundColor: AppColors.textPrimary` ليأخذ `appBarTheme`. وفي **`lib/presentation/screens/cost_centers_screen.dart:180`** استبدل `color: Colors.white` بـ`color: Theme.of(context).cardColor`.
13. **حقول الإدخال**: في `lib/presentation/screens/chart_of_accounts_screen.dart:317` و`lib/presentation/screens/journal_entries_screen.dart:323` استبدل `fillColor: Colors.white` بـ`fillColor: Theme.of(context).colorScheme.surface` (أو احذفه ليأخذ `inputDecorationTheme`)؛ وفي `lib/presentation/widgets/dialogs/product_form_helpers.dart:136` احذف `color: Colors.black87` (يبقى `fontSize: 13`).

**الفيض**

14. **عناوين الحوارات**: في `lib/presentation/widgets/common_widgets.dart:40` استبدل `Text(title)` بـ`Flexible(child: Text(title, overflow: TextOverflow.ellipsis))`؛ ونفس التغيير في `lib/presentation/pos/widgets/pos_edit_invoice_dialog.dart:115`؛ وفي `lib/presentation/pos/widgets/table_pos/table_pos_header.dart:90` لفّ `Column` بـ`Flexible` وأضف `maxLines: 1, overflow: TextOverflow.ellipsis` إلى `Text(tableName, …)` (`:93`).

**فحوص دفاعية لا تغيّر النتائج المحاسبية للمسارات الصحيحة**

15. **`lib/data/database/daos/accounting_dao_writes.dart:1579-1584`** (`rejectJournalEntry`): أضف شرطًا يمنع رفض قيد مرحَّل — مثلًا قراءة القيد أولًا و`if (entry.isPosted) throw Exception('لا يمكن رفض قيد مُرحَّل')`، أو إضافة `AND is_posted = <false>` إلى `WHERE` (مع مراعاة `sqlBool` للتوافق مع PostgreSQL كما في `database_startup.dart:848`). التحقق: اختبار وحدة جديد يرفض قيدًا مرحَّلًا.
16. **`lib/data/database/daos/sales_mutations_dao.dart:1108-1109`**: انقل استدعاء `validateFinancialPeriod(invoice.invoiceDate, …)` إلى ما قبل كتلة `if (needsJournalReversal)` في `:1073` — نفس الفحص، فقط قبل الحذف. (لا يعالج FA-13 الأعمق.)
17. **`lib/data/database/daos/operational_expenses_dao.dart:905-906`** (`deleteExpense`): أضف في بداية الـtransaction قراءة المصروف و`await accountingDao.validateFinancialPeriod(expense.expenseDate, operation: 'حذف مصروف تشغيلي');` (العمود `expenseDate` معرَّف في `lib/data/database/tables/operational_expenses_tables.dart:49`؛ وتأكد أن `accountingDao` متاح في هذا الـDAO كما في `sales_mutations_dao.dart:856`) قبل حذف القيد. يمنع فقط تعديل فترة مقفلة (سلوك مطلوب أصلًا).
18. **`lib/data/database/daos/commercial_papers_dao.dart:188-189`**: حقق التعليق الموجود: بعد `final oldStatus = paper.status;` أضف `if (oldStatus == newStatus) return;` — يمنع سجل حالة وقيدًا مكررين لطلب لا يغيّر شيئًا.
19. **`lib/services/inventory_service.dart:164-165`**: استبدل `print('[FINANCIAL_WARNING] …')` بـ`debugPrint` + `unawaited(DiagnosticLogger.log('FINANCIAL_WARNING', …))` (نفس النمط في `treasury_dao.dart:548`) حتى يظهر الفشل في السجل التشخيصي. (لا يغيّر السلوك؛ جعل الخطأ قاتلًا في §6.)
20. **`lib/data/database/daos/accounting_dao_writes.dart:1432-1457`** (`createDraftJournalEntry`): بعد التأكد بالبحث من عدم وجود مستدعين، علّمها `@Deprecated('Use createJournalEntry(asDraft: true)')` أو احذفها — تمنع استخدامًا مستقبليًا يحرك الأرصدة.

**RTL (تعيين يحافظ على الشكل الحالي: `right→start`، `left→end`)**

21. **ألوان الخطر في الأزرار**: استبدل `Colors.red` بـ`AppColors.error` في `lib/presentation/sales_invoices_picpos/screens/sales_batch_action_bar.dart:90` و`lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart:651`، و`Colors.red.shade600` في `sales_batch_action_bar.dart:137`.
22. **`lib/presentation/shell/nav_widgets.dart:358`**: `EdgeInsetsDirectional.only(start: 22, end: 6, top: 1, bottom: 1)`؛ **`lib/presentation/shell/report_category_nav.dart:98`**: `EdgeInsetsDirectional.only(start: 18, end: 6, bottom: 1)`، و**`:140`**: `EdgeInsetsDirectional.only(start: 30, end: 6, bottom: 1)`.
23. **`lib/presentation/screens/general_ledger_screen.dart:509`**: `EdgeInsetsDirectional.only(start: 16.0 + (level * 12.0), end: 16.0)`؛ **`lib/presentation/pos/widgets/header/pos_header_button.dart:20`**: `EdgeInsetsDirectional.only(start: 8)`؛ **`lib/presentation/screens/help_center_screen.dart:244`**: `EdgeInsetsDirectional.fromSTEB(16, 0, 40, 12)`.
24. **`lib/presentation/widgets/notifications/notification_bell.dart:30`**: `AlignmentDirectional.centerEnd` (واحذف التعليق المتردد)؛ **`lib/presentation/widgets/enhanced_components.dart:361`**: `PositionedDirectional(start: 0, bottom: 0, child: badge!)`.

---

## 6. توصيات مرحلية (Roadmap) للفجوات التي تحتاج قرارًا

### المرحلة 0 — فورًا (أمن وسلامة بيانات)

- **الترخيص (TE-01):** اعتبار الملح `UralCash_Secure_Salt_2026` مكشوفًا. الانتقال إلى توقيع غير متماثل (Ed25519: المفتاح الخاص خارج المستودع، والعام فقط في التطبيق)، إزالة `tools/picpos-activation/picpos-key-generator.html` من المستودع (ومن التاريخ إن كان المستودع مشاركًا) ونقله لمستودع خاص، وخطة ترحيل للمفاتيح القديمة.
- **كلمة مرور admin (TE-05):** قصر «الإصلاح الذاتي» على حالة الملح/الهاش الفارغ فقط، أو اشتراط علم صريح (`--reset-admin-password`)؛ وضبط `admin_password_customized` في كل مسارات تغيير كلمة المرور بما فيها API والمزامنة.
- **مفتاح SQLCipher (TE-02):** إزالة «المفتاح العشوائي لكل جلسة» (الفشل الصريح أفضل من قاعدة لا تُفتح)، والاتجاه لمفتاح عشوائي محفوظ في DPAPI/Credential Manager بدل الاشتقاق من `deviceId` + pepper.
- **ذرّية (TE-17، FA-26):** تغليف `postStockTransfer` بـ`db.transaction`، وجعل فشل قيد سند المخزون قاتلًا (أو بديلًا صريحًا للواجهة)، مع اختبارات.
- **CI (TE-20):** تقسيم `client_write_interceptor.dart` لإعادة البوابة خضراء بدل رفع الحد.

### المرحلة 1 — سلامة الأستاذ العام (1–3 أسابيع)

- استبدال كل الحذف الفعلي للقيود المرحَّلة (FA-11، FA-13، FA-15) بقيد عكسي عبر `reverseJournalEntryById` + قيد جديد، وتوحيد إعادة حساب الأرصدة على دالة واحدة تفلتر `is_posted` و`is_deleted` (FA-40).
- قرار بشأن `updateSalesInvoice` لفاتورة مقفلة (FA-14): إما منعه كليًا وإلزام المرتجع، أو إعادة ترحيل القيد تلقائيًا.
- `approveJournalEntry` يفحص الفترة (FA-17)؛ `fiscalYearId` حسب تاريخ القيد (FA-20)؛ `reverseTransaction` بفحص `isPosted` ومفتاح تكرار (FA-19).
- إقفال الوردية (FA-29): إما إعادة transaction شاملة (مع حل مشكلة القفل المتداخل) أو حالة وسيطة `closing_pending_gl` تمنع الإقفال النهائي حتى يُرحَّل الفرق؛ وربط قفل الفواتير بـ`shiftId` (FA-30).
- الشيكات (FA-33، FA-34): آلة حالات صريحة (`allowedTransitions`) مع قيود صحيحة لـ`bounced → redeposited → cashed`، وتحميل قيد التظهير على `endorsedToPartyId`.
- التسوية البنكية (FA-36، FA-37): اشتراط فرق صفري للإكمال (أو إكمال بقيد تسوية)، وقفل البنود المطابقة في تسوية مكتملة.

### المرحلة 2 — الصلاحيات والتدقيق والمزامنة (شهر)

- نقل فرض الصلاحيات إلى طبقة الخدمة/DAO لكل الكتابات المالية (السندات، القيود اليدوية، التسويات) عبر `PermissionEnforcer` (TE-09)، ومراجعة تجاوز المدير في API (TE-10).
- مسار تدقيق موحد يُكتب داخل نفس الـtransaction لكل عملية مالية، مع تفعيل `AuditLogIntegrityService` أو حذفه (FA-42، FA-43).
- المزامنة: طوابع زمنية من الخادم (HLC أو server time)، فحص التعارض قبل تطبيق الحذف الناعم، وعدم تجاهل كتابات مالية محلية بصمت — طابور «تعارضات تحتاج قرارًا» (TE-14، TE-15، TE-16).
- مراجعة الـ216 `catch (_) {}` بدءًا بملفات المزامنة والمال (TE-11)، وتحويل «تخطي القيد لعدم الربط» إلى خطأ صريح أو فحص جاهزية عند الإعداد (TE-12).
- تشفير إعداد PostgreSQL في التخزين الآمن (TE-06)، ومفاتيح HMAC لكل تثبيت (TE-03، TE-04).

### المرحلة 3 — الدقة المالية والتصميم (ربع سنة)

- دراسة الانتقال إلى وحدات صغرى (`int`) أو `Decimal` للمبالغ (FA-04)، مع توحيد دالة التقريب (FA-05) ومصدر واحد لحساب إجماليات الفاتورة وتوزيع الخصم مع إسناد الباقي (FA-07، FA-09، FA-10).
- قرار حول الأسعار شاملة الضريبة (FA-08) واستخدام القيم المخزنة في الفوترة الإلكترونية.
- التكلفة: قرار FIFO حقيقي أو إيقاف الإيحاء به، ومعالجة فروق البيع بالسالب بقيد تسوية (FA-23، FA-25)، وختم مرتجع المشتريات بتكلفته (FA-24).
- الرواتب: استحقاق شهري ومسيّر رواتب، قيد UNIQUE، ومسار عكس (FA-31، FA-32).
- العملات: سياسة فروق الصرف المحققة/إعادة التقييم أو حذف الكود الميت (FA-41).
- أرصدة الأطراف: اشتقاقها من الأستاذ أو جدولة الكاشف ليعمل دوريًا مع تنبيه (FA-39).

### المرحلة 4 — الواجهة والجودة المستمرة

- قرار: هل الإنجليزية/LTR هدف فعلي؟ إن نعم: خطة ترحيل تدريجية لـ3398 نصًا إلى ARB (بدءًا بالأزرار الشائعة)، وتحويل كل `EdgeInsets.only(left/right)` و`Alignment.centerLeft/Right` إلى Directional (UI-05، UI-13).
- مكوّن زر مشترك (`AppButton.primary/danger/warning`) ولوحة ألوان حالة مركزية واعية بالوضع الداكن (UI-11، UI-17).
- دمج/إزالة الشاشات القديمة المكررة مع `*_picpos` (UI-18).
- تشديد `analysis_options.yaml` تدريجيًا (TE-26)، ورفع أرضية التغطية مع اختبارات للفجوات المذكورة في §3.9.
- ترتيب الجذر: نقل ملفات HANDOFF/PLAN/PROMPT إلى `docs/handoff/`، وملفات SQL الجذرية إلى مجلد migrations قديم مع تحديث المرجع في `api_handler_base.dart:83` (TE-29، TE-30).

---

### ملحق: حدود هذا التدقيق

- لم تُشغَّل مجموعة الاختبارات ولا التطبيق؛ بنود الوضع الداكن والفيض والخطوط مبنية على قراءة الكود لا على ملاحظة الشاشة.
- لم تُقرأ سياسات RLS في `supabase/migrations/0002_rls_policies.sql` بالتفصيل، ولا مجلد `windows/`، ولا `web_app/` سوى ملف إعداد Supabase.
- لم تُراجَع الأجسام الداخلية لـ`autoPostSalesReturn`/`autoPostPurchaseReturn` و`recalculateProductWAC`.
- البنود المُعلَّمة «قراءة مساعدة» جُمعت بقارئ آلي قرأ الأسطر المذكورة ولم أُعد التحقق من كل سطر منها بنفسي.

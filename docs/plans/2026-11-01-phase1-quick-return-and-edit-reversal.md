# تقرير المرحلة 1 — المرتجع السريع وعكس تعديل الفاتورة

## (أ) قائمة التحقق
- [✔] اختبارات F03 فاشلة أولاً — `Invoke-FlutterTest -Paths @('test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart')`: فشل النقد؛ `111-00001` المتوقع `-10.0` والفعلي `0.0`.
- [✔] إصلاح F03 — أضيف حلّ صف cash payment من `safe_transactions` ذات `reference_type='sales_invoice'` للمرتجع السريع، مع إبقاء مسار `sales_return` ذي `returnEventId` والاحتياطي كما هو. التشغيل: `Invoke-FlutterTest -Paths @('test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart','--plain-name','F03 quick cash return')` أعاد `00:02 +1: All tests passed!`; تشغيل المجموعة أظهر أن اختبار البطاقة/البنك ضمن الأربعة الناجحة (`+4`) قبل فشل حالة SP-02.
- [✔] اختبارات SP-02 فاشلة أولاً — الأمر نفسه: بعد تعديل النقدي، `4121` المتوقع `-30.0` والفعلي `-20.0`; تعديل ما بعد المرتجع لم يُرفض؛ تعديل الآجل أعطى `1121` المتوقع `30.0` والفعلي `20.0`.
- [✔] بلا وردية مفتوحة — `Invoke-FlutterTest -Paths @('test/integration/no_invoice_return_persist_test.dart')` أعاد `00:15 +9: All tests passed!`, ويشمل التحقق الحي من `ShiftRequiredException` وعدم الحفظ.
- [✔] إصلاح SP-02 بالقيد العكسي — في الفواتير غير المقفلة، اختلاف الرأس/السطور يستدعي `_reverseActiveSaleEntriesForEdit` ثم يرحّل القيم المعدلة؛ مسار المقفلة لم يتغير، والقيد الأصلي باقٍ. المرتجع يمنع التعديل برسالة عربية؛ لا حذف صلب.
- [✔] الحالات الخاصة موثّقة — القيود/الحدود موضحة في §(د)، واختبارات الوضع الطبيعي، المرتجع، no-op، الآجل، الفترة المقفلة، والوردية موثقة.
- [✔] تشغيل الحزم النهائية — الحزم المطلوبة شُغّلت؛ نتائجها الدقيقة (ومنها إخفاقات سابقة خارج النطاق) مسجلة في §(ب)، و§(د).

## (ب) الأوامر ونتائجها
- `. D:\qa\luna_tools.ps1; Backup-ForTask phase1-quick-return-and-edit-reversal ...` — نُفّذت النسخ الأربع المحددة في §(ج) قبل تعديل كل ملف.
- `. D:\qa\luna_tools.ps1; Diff-AgainstBackup phase1-quick-return-and-edit-reversal <المسار النسبي>` — راجعت الفروق من النسخ؛ ظهر في DAO تنسيق أسطر خارج المهمة بسبب `dart format` إضافةً إلى الفروق الوظيفية المدرجة في §(ج)، ولم يظهر تداخل مع تغيير العامل حول 325–350.
- اختبار F03 قبل الإصلاح، `Invoke-FlutterTest -Paths @('test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart')`: `111-00001` متوقع `-10.0`، فعلي `0.0`.
- اختبار F03 بعد الإصلاح، مع `--plain-name 'F03 quick cash return'`: `00:02 +1: All tests passed!`.
- اختبار SP-02 قبل الإصلاح من الملف نفسه: `4121` متوقع `-30.0` فعلي `-20.0`؛ الرفض بعد المرتجع لم يحدث؛ `1121` للآجل متوقع `30.0` فعلي `20.0`.
- بعد الإصلاح الأولي: الملف الجديد `+6: All tests passed!` (نقد/بنك، تعديل نقدي، عدم التغيير، بعد المرتجع، آجل).
- تكافؤ PG: `. D:\qa\luna_tools.ps1; Invoke-FlutterTest -Paths @('test/integration_pg/phase1_quick_return_pg_test.dart') -PgDsn 'postgres://postgres@127.0.0.1:56030/postgres'` ⇒ `00:34 +1: All tests passed!`; الحاوية الخاصة `picpos-phase1-pg-56030` أُنشئت وأُزيلت.
- بعد فصل `updateSalesInvoice` وإضافة مقارنة أرصدة جميع الحسابات بالأستاذ، ثم تشديد assertion لنوع الاستثناء: `Invoke-FlutterTest -Paths @('test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart')` ⇒ `00:11 +6: All tests passed!`.
- فشل تحليلي أولي لاختبار PG: URI نسبي خاطئ؛ صُحح إلى `_support/pg_fixture.dart` وأصبح الاختبار ينجح.
- التحليل الكامل النهائي: `flutter analyze` ⇒ `27 issues found. (ran in 306.6s)` وخرج برمز 1؛ الذيل يعرض تحذيرات/معلومات سابقة منها `use_build_context_synchronously` في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84` و`unused_import` في `f12_mirror_close_fleet_test.dart:1`. بعد آخر مراجعة للاختبارات/التعليق، التحليل المحدد للملفات السبعة أعاد `No issues found! (ran in 45.1s)`. 
- `test/integration/no_invoice_return_persist_test.dart` ⇒ `00:15 +9: All tests passed!`; `shift_closing_aggregates_test.dart` ⇒ `+5: All tests passed!`; `sc_h_shift_test.dart` ⇒ `+5: All tests passed!`.
- كل `test/scenarios/sc_*.dart` شُغّلت كلٌ على حدة: `sc_a` +3، `sc_b` +2، `sc_c2` +1، `sc_c3` +1، `sc_c4` +3، `sc_c_sales_return_void` +16، `sc_d` +4، `sc_f` +6، `sc_h` +5، `sc_j` +5، `sc_k` +10، `sc_l` +5، `sc_n` +2 اجتازت؛ `sc_m_bins_fefo_test.dart` متجاوَز كما هو موسوم في المصدر (`+0 ~1`).
- `shift_close_audit_matrix_test.dart --run-skipped` ⇒ `+14 -6`; الإخفاقات F05/F09/F08/F06/F07/F04 خارج F03، ولم يفشل F03.
- `c_returns_void_edit_audit_test.dart --run-skipped` ⇒ `+18 -6`; إخفاقات NOINV-01/04 وVOID-02 وRCV-02/03/04 خارج النطاق. بعد تشديد assertion إلى `StateError`، `Invoke-FlutterTest -Paths @('test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart','--plain-name','EDIT') -RunSkipped` ⇒ `00:08 +4: All tests passed!`.
- الهيكلي بعد فصل DAO: الأمر حلّق على 120 ملفاً فردياً وانتهى `STRUCTURAL: 119/120 passed; failed: test\structural\file_size_ratchet_test.dart`. فشل الحارس فقط بسبب ثمانية مخالفات خارج الملفات المعدّلة: 4 ملفات جديدة فوق 30KB بلا baseline (`database_seeder_accounts.dart` 30,713؛ `invoice_generator.dart` 30,587؛ `inventory_report_screen.dart` 30,442؛ `add_party_dialog_picpos.dart` 30,231) و4 تجاوزات baseline (`inventory_dao.dart` 80,424/80,300؛ `api_purchase_handler.dart` 76,143/72,909؛ `returns_repository_impl.dart` 49,146/47,048؛ `purchases_repository_impl.dart` 67,483/64,882). لم ألمسها، ومنها ملف العامل الآخر.

## (ج) الملفات المعدّلة وفروقها
- `lib/data/database/daos/accounting_autopost_sales_return_dao.dart`: Resolver النقدية يقرأ حساب الخزنة من صف `sales_invoice` النقدي المرتبط برقم الفاتورة للمرتجع السريع؛ يبقي مسار `sales_return` ذي `returnEventId` والـfallback إلى الحساب الافتراضي.
- `lib/data/database/daos/sales_mutations_dao.dart` و`lib/data/database/daos/sales_invoice_edit_dao.dart`: نُقلت دالة `updateSalesInvoice` من DAO المتضخم إلى extension مستقل لالتزام حارس الحجم؛ الدالة تكشف no-op، ترفض أي تعديل بعد مرتجع، وتعيد استخدام نمط عكس/إعادة ترحيل القيود لغير المقفلة، مع إبقاء مسار المقفلة كما كان.
- `lib/data/database/database.dart`: إضافة `part` للـDAO الجديد.
- `test/phase1/quick_return_and_edit_reversal/quick_return_and_edit_reversal_test.dart`: اختبارات F03 (نقد/بنك) وSP-02 (نقد مع سعر/خصم/كمية، no-op، بعد المرتجع، آجل) ومطابقة رصيد كل حساب مع مجموع قيوده.
- `test/integration_pg/phase1_quick_return_pg_test.dart`: تكافؤ F03 على PostgreSQL خاص.
- `test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart`: EDIT-04 يتحقق من رفض التحرير وبقاء `partial_return` ثم رفض الإلغاء.
- النسخ قبل التعديل: `D:\qa\phase1-quick-return-and-edit-reversal_backup\lib\data\database\daos\sales_mutations_dao.dart`; `D:\qa\phase1-quick-return-and-edit-reversal_backup\lib\data\database\daos\accounting_autopost_sales_return_dao.dart`; `D:\qa\phase1-quick-return-and-edit-reversal_backup\lib\data\database\database.dart`; `D:\qa\phase1-quick-return-and-edit-reversal_backup\test\audit_repro\sales_purchases\c_returns_void_edit_audit_test.dart`.
- حجم LF المطبّع (حارس structural): `sales_mutations_dao.dart` قبل التعديل 73,589 بايت (baseline 73,590)، وبعد نقل الدالة 64,642؛ `sales_invoice_edit_dao.dart` الجديد 11,931 (أقل من حد 30KB)؛ `database.dart` 39,674 (baseline 40,457). لا baseline تغيّر.
- اختلاف قبل/بعد في قيود البيع: قبل تعديل 2×10: قيد واحد بالصافي 20 (مدين درج 20/دائن مبيعات 20، COGS 8/مخزون 8). بعد تعديل 3×12 وخصم 3.6: **الأصلي محفوظ** (1)، قيد عكسي (1)، قيد جديد (1): درج +32.4؛ 4121 دائن 36، 4212 مدين 3.6، COGS مدين 12/مخزون دائن 12. محصلة 4121+4212 = −32.4، الخزنة 32.4، المخزون 2، والأستاذ والخزنة والمخزون متطابقون. قيود قبل/بعد لهذا السيناريو: 1 → 3 (زيادة قيدين: عكس + إعادة ترحيل).
- F03: قبل الإصلاح: حساب الدرج 0 مقابل خزنة −10 و`1111` غير صفر؛ بعد الإصلاح: حساب الدرج −10، خزنة −10، و`1111` صفر. قيود المرتجع: 1 قبل/بعد؛ تغيير الحساب فقط، بلا تغيير مبالغ/مردودات/تكلفة.

## (د) الحالات الخاصة وما لم يُتحقّق منه
1. **فاتورة عليها مرتجع:** تعديلها يُرفض برسالة عربية `لا يمكن تعديل فاتورة عليها مرتجع...` قبل لمس السطور/الخزنة؛ الاختبار يخفض الكمية إلى ما دون المرتجع ويتحقق من بقاء الحالة. السبب: إعادة كتابة أسطر المصدر تمحو مرجع الارتجاع التاريخي، وقد تسمح بإلغاء يعكس المرتجع مرتين؛ رفض آمن لحالة المرتجع وحدها.
2. **آجلة مع تحصيلات:** اختبار الآجل الحالي بلا تحصيل لاحق يمرّ ويطابق رصيد الطرف مع `1121`. تحصيلات لاحقة تبقى أحداث قبض مستقلة وتخصيصاتها لا تُعاد كتابتها في هذا الإصلاح؛ لم أضف اختباراً يثبت تعديل فاتورة عليها تحصيل لاحق، لذا لا أقرر دعمه هنا. ينبغي تدقيق/منع هذا السيناريو إن ظهر فرق قبل تفعيله.
3. **لا تغيير:** مقارنة الرأس والسطور تخرج قبل تعديل المخزون أو القيود؛ اختبار عدد القيود قبل/بعد يثبت عدم الزيادة.
4. **فترة مقفلة:** بقي `validateFinancialPeriod(oldInvoice.invoiceDate)` قبل أي تعديل؛ لم أضف اختباراً جديداً لهذه الحالة، ويُشغّل اختبار `sc_j_fiscal_period_test.dart` ضمن القائمة النهائية.
5. **بلا وردية مفتوحة:** مسار DAO المنخفض لا يطبق الحارس، لذلك اختباراً أولياً خاطئاً عبر DAO أعاد `Future<int>` بدلاً من استثناء. الحارس المطلوب موجود في مسار POS، ويُعاد تشغيل الاختبار الحي `no_invoice_return_persist_test.dart` ضمن التحقق.
6. **حارس الحجم:** `sales_mutations_dao.dart` صار دون baseline بعد نقل الدالة. تشغيل الحارس كشف ملفات أخرى خارج النطاق، منها `database_seeder_accounts.dart` و`invoice_generator.dart` و`inventory_report_screen.dart` و`add_party_dialog_picpos.dart` بلا baseline، و`inventory_dao.dart`, `api_purchase_handler.dart`, `returns_repository_impl.dart`, `purchases_repository_impl.dart` متجاوزة baseline. لم ألمسها؛ و`returns_repository_impl.dart` تحديداً ضمن عمل العامل الآخر.

## (هـ) المخاطر والتراجع
- لم تُحذف القيود الأصلية؛ نمط عكس القيد يضيف `reversal` مرتبطاً بمعرّف القيد الأصلي ثم قيد بيع جديد. قيد البيع قبل/بعد اختبار التعديل: قيد أصلي 20، قيد عكس 20، قيد جديد بالقيم المعدلة 32.4 (سطر 4121 = 36− دائن و4212 = 3.6 مدين)؛ الحسابات النهائية تطابق الخزنة/الذمم والمخزون.
- كل ملف موجود عُدّل له نسخة احتياطية مسبقة مفصلة في §(ج). `dart format` نسّق DAO كاملين (تغيير تنسيق واسع خارج منطق المهمة)، ثم نُقلت دالة تعديل الفاتورة لملف مستقل؛ أحجام LF المطبعة النهائية ضمن baseline كما في §(ج). لا تغيير في `file_size_baseline.txt`.

- [2026-11-01] نقطة تفتيش: نُسخت ملفات DAO والاختبار المتأثرة إلى مسارات المهمة قبل تعديلها. التغيير السابق في DAO حول 325–350 لم يُمسّ دلالياً.

CHECKLIST: 6/6
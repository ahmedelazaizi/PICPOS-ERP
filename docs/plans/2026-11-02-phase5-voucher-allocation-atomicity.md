# Phase 5 — ذرّية تخصيص السندات

## نقاط التحقق
- البداية: قُرئ `D:\qa\luna_charter.md` كاملاً. ملفات الشاشتين وDAO المستهدف لا تظهر ضمن التغييرات غير الملتزمة؛ توجد ملفات غير مرتبطة غير متتبعة، تُركت كما هي.
- التشخيص: `recordVoucherAllocations` يفتح معاملة تخصه، بينما `TreasuryRepositoryImpl.createReceiptVoucher` يفتح معاملة مستقلة تُغلق قبل تسجيل التخصيص. لذلك فشل التخصيص اللاحق لا يتراجع عن السند.
- العميل: وسيط العميل يحفظ جهة الخادم ولا يسجل تخصيصات الجهاز؛ يجب تجاوز فحص الفواتير المحلية عند نجاح اعتراض الوسيط.
- لا توجد دالة إلغاء سند آمنة ظاهرة في `lib/data`؛ لن أضيف تعويضاً مالياً عكسياً.

## التحقق والتسليم
يُستكمل بعد تنفيذ كل خطوة، مع الأوامر ونتائجها الحرفية.

- [2026-11-02 13:48] أُضيف حارس نقي وتجارب وحدات، لكن التشغيل بعد الإضافة ما زال يفشل في تجميع الاختبار بسبب صياغة spread غير صالحة في records؛ لم يُدمج الحارس في الشاشتين بعد. الأمر Invoke-FlutterTest test/phase5/voucher_allocation_guard/voucher_allocation_guard_test.dart انتهى بفشل تجميعي: Expected an identifier, but got ... (أسطر 7، 12، 16، 17، 20، 22). كذلك التشغيل الأول كشف تعارض استيراد part مع خطأ num/int في DAO.
- [2026-11-02 13:52] نجح الاختبار الوحدوي بعد إصلاح صياغة السجلات: Invoke-FlutterTest test/phase5/voucher_allocation_guard/voucher_allocation_guard_test.dart — All tests passed. أُدمج فحصٌ مسبق في مساري القبض والصرف؛ يستخدم getOpenInvoicesForParty الذي يستثني مرتجعات المبيعات والصفوف المحذوفة، ويتجاوز التحقق محلياً في وضع العميل. خطأ إجرائي: أُخذت نسخة الشاشتين الاحتياطية بعد التعديل الأول لا قبله.
- [2026-11-02 13:56] نقطة تحقق: حارسا القبض والصرف يستدعيان preflightVoucherAllocations قبل ClientVoucherInterceptor.submit (ويتجاوزان الفحص عند SyncInterceptor.isClientMode)، ويستعملان getOpenInvoicesForParty؛ هذه القراءة تستثني مرتجعات المبيعات والمحذوفة. اختبارات الوحدة والتكامل وflutter analyze على الملفات المعدلة نجحت. تكافؤ PG نجح: Invoke-FlutterTest test/phase5/voucher_allocation_guard/voucher_allocation_guard_flow_test.dart -PgDsn postgres://postgres:phase5pass@127.0.0.1:58200/picpos_test — All tests passed. التشغيل الأول لـPG لم يجد وسماً لأن tags كانت على main بدلاً من test، وبعد نقلها نجح.
- [2026-11-02 13:58] توسعت تغطية الاختبارات: وحدة للحالات السالبة/صفر، تجاوز المجموع، التجميع المكرر، السليم/المتبقي الدقيق، ورفض فاتورة غائبة (ويغطي مسار إقصاء المرتجع من استعلام الفواتير المفتوحة). التكامل يحاكي الحفظ عبر الحارس ثم CreateVoucherUseCase وrecordVoucherAllocations، ويرصد journal_entries وsafe_transactions وpayments ورصيد العميل. فشل TDD الأول كان تجميعياً قبل إصلاح صياغة الاختبار: Expected an identifier, but got ...؛ لم يكن فشل assertion. الاختبار التكاملي أُضيف بعد دمج الفحص، لذا لا أدّعي TDD أحمر/أخضر صارماً له.
- [2026-11-02 14:00] التحقق المرحلي: نجحت file_size_ratchet وdark_mode_guard وi18n_coverage وi18n_runtime_safety؛ نجحت سيناريوهات sc_a/sc_b/sc_c/sc_c2/sc_c3/sc_c4، وphase3/negative_policy_and_payment_rejection، وphase4/credit_void_after_receipt_test. phase4/credit_void_after_receipt_pg_test لم يُشغّل فعلياً في هذا الأمر، إذ أظهر All tests skipped بسبب شرط melos test:pg؛ تكافؤ PG للحالة الجديدة شُغّل منفصلاً ونجح على 58200.
- [2026-11-02 14:14] التحقق الختامي بعد إعادة هيكلة الحارس: اختبار الوحدة نجح؛ اختبار التكامل نجح باستخدام -RunSkipped؛ flutter analyze على خمسة ملفات رجع No issues found؛ واختبار PG أعيد بعد التعديلات ونجح على منفذ 58200، ثم حُذفت الحاوية phase5-voucher-allocation-pg. حزمة الاختبارات ذات أسماء voucher/receipt/allocation نفّذت ملفاً ملفاً؛ المخرجات الظاهرة كلها All tests passed، مع اختبار تدفق Phase 5 واختبار phase4 PG متخطّيين في التشغيل العادي لوسم pg (وشُغّل تدفق Phase 5 منفصلاً مع PG).
- [2026-11-02 14:15] النتيجة التشغيلية: قبل الإصلاح كان createReceiptVoucher/createPaymentVoucher يكتبان السند والقيد وحركة الخزنة داخل معاملة المستودع ثم تُغلق، وبعدها يبدأ recordVoucherAllocations معاملة ثانية؛ بعد الإصلاح يُرفض عدم التوافق المتوقع قبل نداء وسيط/مستودع السند، فيبقى العدّ والرصيد بلا تغيير. لم أضف معاملة شاملة: إعادة فتح النطاق عبر إنشاء السند وختم الدفتر وإنشاء الأوراق التجارية والتخصيص قد تجمع آثاراً محلية وخادمية مختلفة، ولا توجد دالة إلغاء سند آمنة؛ بحث voidVoucher/cancelVoucher/reverseVoucher لم يجد إلا cancelVoucherBookLeaf الخاص بورقة الدفتر. لذلك لا يوجد تعويض بعد فشل متأخر غير متوقع، وتبقى نافذة سباق بين القراءة والكتابة؛ عالجها تعديل ذري شامل لاحقاً لا ترقيعاً موضعياً.
- [2026-11-02 14:15] مخاطر/قيود: فشل TDD الأول كان تجميعياً قبل أن يعمل الاختبار (استيراد ملف part وغياب الدالة ثم spread غير صالحة)، وليس فشل assertion؛ اختبار التكامل كُتب بعد دمج الحارس. نسخ الشاشة الاحتياطية أُخذت بعد أول إضافة import، لا قبل أول تعديل كما يطلب الميثاق؛ لم تُستبدل أي تغييرات مالك معروفة لأن الشاشة كانت نظيفة عند فحص البداية. لا مفاتيح i18n جديدة لأن النصوص الجديدة ليست عبر tr().
- [2026-11-02 14:17] تشغيل إضافي لإزالة حدّ التحقق: Invoke-FlutterTest test/phase4/credit_void/credit_void_after_receipt_pg_test.dart -PgDsn postgres://postgres:phase5pass@127.0.0.1:58200/picpos_test — All tests passed؛ أُزيلت الحاوية بعده.
## قائمة التسليم
- ✘ (1) TDD الصارم: فشل الاختبار الأول في التجميع لا في assertion، واختبار التدفق أُضيف بعد دمج الحارس؛ اختبارات الوحدة والتدفق الآن ناجحة.
- ✔ (2) الفحص المسبق في القبض والصرف قبل أي كتابة محلية؛ يُتجاوز في وضع العميل.
- ✔ (3) وُثّق تعذّر توحيد المعاملة بأمان ضمن التعديل الصغير؛ لا توجد دالة إلغاء سند آمنة، وتبقى نافذة سباق موضحة أعلاه.
- ✔ (4) تكافؤ PG للحالة الجديدة، واختبار phase4/credit_void PG، نجحا على المنفذ 58200، ثم أزيلت الحاويات.
- ✔ (5) اختبارات الوحدة/التكامل، الملفّات المسماة voucher/receipt/allocation، السيناريوهات sc_a/sc_b/sc_c/sc_c2/sc_c3/sc_c4، phase3/negative_policy_and_payment_rejection، phase4/credit_void، structural/file_size_ratchet وdark_mode_guard وi18n_coverage وi18n_runtime_safety؛ flutter analyze للملفات الخمسة المعدّلة رجع No issues found. كانت phase5 tagged test متخطية في التشغيل العادي ثم نجحت مع -RunSkipped و-PgDsn.

### الملفات المعدّلة
- `lib/presentation/treasury_picpos/screens/voucher_allocation_guard.dart`: حارس تجميعي بوحدات صغرى وفحص مسبق قابل للاختبار.
- `lib/presentation/treasury_picpos/screens/receipt_voucher_picpos_screen.dart`: فحص القبض قبل الوسيط/المستودع محلياً.
- `lib/presentation/treasury_picpos/screens/payment_voucher_picpos_screen.dart`: فحص الصرف قبل سحب الشيك أو إنشاء السند.
- `test/phase5/voucher_allocation_guard/voucher_allocation_guard_test.dart` و`test/phase5/voucher_allocation_guard/voucher_allocation_guard_flow_test.dart`: اختبارات وحدة وتدفق حقيقي باستخدام ScenarioWorld ومستودع/DAO.
- هذا التقرير.

ملاحظة النسخ الاحتياطية: استدعاء Backup-ForTask للشاشتين وقع بعد أول إضافة import؛ النسخ لا تمثل الحالة الأصلية كاملة. لم تُستبدل تغييرات مالك معروفة؛ كان الملفان نظيفين عند بدء العمل. بقيت الملفات غير المرتبطة غير المتتبعة دون مساس.

CHECKLIST: 4/5

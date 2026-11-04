# واجهة ربط القوالب بطابعات محددة

**التاريخ:** 2026-11-03  
**الحالة:** التنفيذ والتحقق المكتبي مكتملان؛ لم تُجرَ طباعة على جهاز فعلي.

## ما كشفه تتبّع المسار

- تُنشأ الرابطات من `TemplateBindingDao.activateBinding` عبر عقد `IInvoiceTemplatesRepository`؛ المكتبة كانت تعرضها وتتيح تفعيل القالب، لكنها لم توفر اختيار طابعة لهذا النوع من المستندات. DAO يزيل رابطات المفتاح نفسه (نوع المستند/الفرع/الطابعة/اللغة) داخل معاملة قبل إدخال الرابط الجديد، فلا تتكرر روابط متعارضة دون تغيير schema.
- خدمة `TemplatedInvoiceService.printWithTemplate` و`TemplateResolver` كانا يقبلان `printerId`، وبعض منادي الإيصال/المطبخ/الوردية يمررونه. أضيف تمرير اختياري للمعرّف إلى منادي الفاتورة A4 والمرتجع والمشتريات وكشف الحساب؛ عند غيابه تستخدم هذه المسارات الطابعة النشطة لغرض `pos_receipt`، مع بقاء التواقيع الحالية صالحة.
- اكتشف اختبار الطابعة المحددة أن المستوى الأول للحسم لم يقبل رابطاً محدداً بطابعة مع `branchId == null` (أي «كل الفروع»). عُدّل المطابق ليستوعب النطاق العام المعلن في عقد الرابطات؛ بقاء `branchId` محدداً يظل يطلب التطابق نفسه.
- `quotation` و`report` معلنان في `TemplateResolver` لكنهما غير موصولين بمسار الطباعة الفعلي؛ يمكن تسجيل رابط لهما، وتظل حالة «بانتظار التوصيل» ظاهرة. لم يُنشأ مسار طباعة لهذين النوعين ضمن هذه المهمة.

## التنفيذ

- شاشة حسم القوالب تعرض مرشح طابعة (مع `paperWidthMm`) إلى جانب مرشحي الفرع واللغة، وتستعمل `printerId` المختار في الحسم والعرض.
- أضيف زر «ربط بطابعة» في كل صف معلن. الحوار يجلب الطابعات والقوالب عبر providers/repositories، يصفّي القوالب حسب نوع/فئة سياق المستند، ويعرض عرض كل طابعة. القوالب الأعرض من الطابعة معطلة ويظهر سبب القص؛ القالب الأضيق يعرض تحذير الملاءمة قبل الحفظ. نجاح الحفظ والإزالة يبطل مزود العرض ويحدّث النتيجة مباشرة.
- إزالة الربط تستهدف المفتاح الفائز كما عُرض، ولا تستورد طبقة العرض قاعدة البيانات مباشرة.
- لم يتغير schema ولم يُشغّل `build_runner`.

## الاختبارات

- أضيف إلى `test/unit/template_binding_reaches_paper_test.dart` تحققٌ لفاتورة البيع ومرتجع البيع يثبت اختلاف القالب المحسوم والمطبوع باختلاف `printerId`، إضافةً إلى تحذير 58/80 مم على طابعة A4 ورفض قالب A4 على طابعة 80 مم برسالة القص.
- أضيف إلى `test/widget/template_resolution_screen_test.dart` اختبار حوار الاختيار وعرض الورق وتعطيل قالب غير متوافق مع سبب واضح.
- لا توجد لقطة PNG منفصلة: التحقق تم عبر Widget tests؛ لم يُضف golden جديد للمشروع.

## نتائج التحقق

شُغّل الاختبار عبر `. D:\qa\luna_tools.ps1; Invoke-FlutterTest ...` (ويشغّل `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos` ويستعمل `Clear-SqliteLock`):

- الاختبارات المركّزة (`template_binding_reaches_paper_test.dart` و`template_resolution_screen_test.dart`): **All tests passed!**
- المجموعة الكاملة المطلوبة: اختبارات `template_resolution*` و`template_library*` و`template_binding*`، و`test/print_audit/setup_path/setup_path_audit_test.dart`، والحراس `file_size_ratchet_test.dart`, `i18n_coverage_test.dart`, `i18n_runtime_safety_test.dart`, `dark_mode_guard_test.dart`, `analytics_parity_test.dart`, `presentation_db_import_guard_test.dart`: **101 اختباراً، All tests passed!**
- `flutter analyze lib`: انتهى بخرج 1 بسبب معلومتين فقط `use_build_context_synchronously` في `lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart:48` و`lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart:84`؛ لا توجد أخطاء تحليل أخرى. لم أعدّل هذين الموضعين غير المتعلقين بالمهمة.

## ملاحظات التسليم

- لا تغيير في قاعدة البيانات أو ملفات `assets/` الخاصة بالقوالب. ترجمات واجهة الربط أضيفت إلى `assets/i18n/en.json`.
- `dart format` لمس عرضاً `lib/presentation/template_resolution_picpos/widgets/resolution_chain_panel.dart` عند تنسيق مجلد الشاشة؛ تغييره تنسيقي فقط، ولا يتضمن سلوكاً مطلوباً للمهمة.
- الطباعة الفعلية على Windows/طابعة موصولة غير منفذة. واجهات A4 التي تفتح حوار النظام لا تكشف الطابعة التي اختارها المستخدم بعد فتح الحوار؛ لذلك يستخدم المنادي الطابعة النشطة الممررة أو `pos_receipt` كوجهة افتراضية للحسم.

# برومت التنفيذ — منظومة نماذج الطباعة في PicPos ERP

انسخ هذا النصّ كاملاً وأعطه للمساعد المنفّذ.

---

## المهمة

نفّذ منظومة نماذج الطباعة في مشروع **PicPos ERP** (Flutter + Drift) حسب خمسة تصاميم
جاهزة وأربع وثائق مواصفة موجودة في مجلد `invoice_templates/`. لا تبدأ بالتصاميم — ابدأ
بالمحرك، فالتصاميم تعرض ما يحسبه المحرك.

## أين الملفات

كل ما تحتاجه في مجلد D:\PICPOS-ERP\invoice_templates
محتواه:

```
invoice_templates/
├─ IMPLEMENTATION-BRIEF.md      ← هذا الملف
├─ EDITOR-ARCHITECTURE.md
├─ BUTTON-CONTRACT.md
├─ EXTENSION-SPEC.md
├─ MIGRATION-PLAN.md
│
├─ designs/                     ← التصاميم الخمسة — افتحها في المتصفح
│  ├─ PicPos Template Editor.dc.html
│  ├─ PicPos Template Library.dc.html
│  ├─ PicPos Template Resolution.dc.html
│  ├─ PicPos Template Print Test.dc.html
│  ├─ PicPos Print Templates.dc.html
│  ├─ support.js                ← لازم بجوارها وإلا لم تعمل
│  └─ assets/picpos-logo.png
│
└─ *.json                       ← أحد عشر قالباً جاهزاً للاستيراد
   a4_sales_tax_invoice · a5_sales_tax_invoice · a4_purchase_invoice
   thermal80_quick_sale · thermal58_quick_sale · a4_sales_return
   thermal80_sales_return · a4_purchase_return
   a4_customer_statement · a4_supplier_statement · a4_report_generic
```

**التصاميم صفحات HTML تفاعلية، ليست صوراً.** افتح كل واحدة في المتصفح مباشرةً
(‏`support.js` و`assets/` لازم يكونا بجوارها). اضغط الأزرار، اسحب العناصر على الورقة،
غيّر عناوين الأعمدة، اضغط حفظ. **سلوكها هو المواصفة** — ما تراه يحدث عند الضغط هو ما
يجب أن يحدث في التطبيق.

ملفات الـJSON الأحد عشر تُنسخ إلى `assets/invoice_templates/` في المشروع.

## اقرأ أولاً — بهذا الترتيب

| # | الملف | ما فيه |
|---|-------|--------|
| ١ | `EDITOR-ARCHITECTURE.md` | العقد المعماري · حدود الملفات · ترتيب التنفيذ · ما يُحذف |
| ٢ | `BUTTON-CONTRACT.md` | ما يفعله كل زر بالضبط · حالات الرفض · فحص القبول |
| ٣ | `EXTENSION-SPEC.md` | امتداد كشف الحساب والتقارير على نمط `shift_closing` |
| ٤ | `MIGRATION-PLAN.md` | هجرة القوالب القائمة بلا تغيير مطبوع واحد |

## الكود الذي يجب أن تقرأه قبل أن تكتب سطراً

```
lib/services/templated_invoice_service.dart          ← الراسم الحالي (٢٠٨٢ سطراً)
lib/services/printing/report_pdf_generator.dart      ← مولِّدات ثابتة لا تقرأ القوالب
lib/data/database/tables/invoice_template_tables.dart
lib/data/database/daos/invoice_template_dao.dart     ← importTemplateFromJson سطر ٢٨٦
lib/presentation/screens/invoice_designer/invoice_section_editor.dart
lib/presentation/screens/invoice_designer/invoice_designer_properties.dart
lib/core/utils/template_json_flags.dart
```

## التصاميم الخمسة ودور كل واحد

| التصميم | يُنفَّذ كـ | ملاحظة |
|---------|-----------|--------|
| `PicPos Template Editor.dc.html` | شاشة المحرر الجديدة | تحلّ محل `invoice_designer_screen.dart` بواجهاته الثلاث |
| `PicPos Template Library.dc.html` | شاشة المكتبة | جديدة — لا مقابل لها اليوم |
| `PicPos Template Resolution.dc.html` | شاشة حسم القوالب والطابعات | جديدة — تعرض جدول `TemplateBindings` |
| `PicPos Template Print Test.dc.html` | شاشة المعاينة التجريبية | جديدة |
| `PicPos Print Templates.dc.html` | مرجع بصري للقوالب الأحد عشر | ليست شاشة تطبيق — دليل شكل |

جميعها في `designs/`. المقاس المصمَّم عليه ١٩٢٠×١٠٨٠، والاتجاه RTL، والخط Cairo للواجهة
و Noto Naskh للورق المطبوع.

## القرار المعماري الذي لا يُناقَش

**نطاقات بإحداثيات داخلية.** المستند نطاقات تتراصّ رأسياً
(`header · info · party · details · totals · footer`)، وداخل كل نطاق العناصر بإحداثيات
مطلقة **بالمليمتر**. نطاق `details` وحده يتمدّد بالبيانات فيدفع ما بعده.

سبب القرار: النظام اليوم فيه نموذجا تخطيط متناقضان — الكانفاس يحفظ `xPosition`/`yPosition`
والراسم يتجاهلهما ويبني تدفّقاً. فالمستخدم يضبط موضعاً ويطبع فيجده في مكان آخر.
والإحداثيات المطلقة على الورقة كلها تنكسر مع جدول بـ٣٠ صنفاً. النطاق يحلّ الاثنين.

## ثلاث قواعد صارمة

**١ · مصدر حقيقة واحد للتخطيط.** `layout_engine` يُنتج `List<PositionedPage>`، ويستهلكها
راسم الـPDF وراسم المعاينة معاً. **لا راسم ثانٍ.** وجود `debugRenderItemsTable` في الكود
اليوم دليلٌ مكتوب على أنهم اكتووا من «المعاينة ≠ الورق».

**٢ · `TemplateDocument` بلا تبعيات.** لا يستورد `package:pdf` ولا `package:flutter`.
هذا ما يجعله قابلاً للاختبار بلا واجهة.

**٣ · المليمتر وحدة القياس.** لا بكسل في التخزين — البكسل يتغيّر بالتكبير.

## ترتيب التنفيذ — كل خطوة تُشحن وحدها

```
١ · TemplateDocument + layout_engine + اختبارات وحدة        ← أطول خطوة، لا واجهة
٢ · وصل pdf_painter بـ PositionedPage                        ← معيار النجاح: كل قالب قائم يطبع كما كان
٣ · عناوين الأعمدة والتسميات قابلة للتعديل                    ← هنا تعمل ثنائية اللغة أول مرة
٤ · condition_evaluator (شروط الإظهار والمعادلات)
٥ · شاشة المحرر الجديدة                                       ← لا تبدأها قبل ١—٤
٦ · template_resolver + شاشة حسم القوالب
٧ · امتداد كشف الحساب والتقارير حسب EXTENSION-SPEC.md
```

## أربعة أعطاب مرصودة — أصلحها في طريقك

**١ · `footer_text` يُطبع حرفياً.** المحرر يخزّن `content = 'footer_text'`، و`_resolveType`
يستبدل نوع عنصر النصّ بمحتواه، فلا تُطابَق حالة ويطبع حارس `default` السلسلة نفسها.

**٢ · القوالب المبذورة الثمانية غير مرئية في محرر الأقسام.** `_fullSyncWithElements` يفهرس
بـ`content`، وملفات `assets/invoice_templates/*.json` تكتب `{"type":"company_name"}` بلا
`content` — فالحقل يُطبع والمحرر يعتبره مخفياً.

**٣ · ألوان رأس الجدول لا تصل الورق.** `headerBgColor`/`headerTextColor` في الجدول وفي
الواجهة، والراسم يتجاهلهما عمداً (الطابعة الحرارية تُسقط تعبئة الخلفية). إمّا تُوصَل
وإمّا تُحذف من الواجهة — الحالي أسوأ الخيارين.

**٤ · `defaultFont` يعد بما لا يفي.** افتراضيته `Cairo` والراسم يحمّل Noto Naskh عمداً
لأن Cairo ينقصه الياء المنفصلة U+FEF1.

## حسم القالب — المفتاح الرباعي

نوع المستند + الفرع + الطابعة + اللغة، تُجرَّب من الأخصّ للأعمّ وأول مطابقة تفوز
(ستة مستويات، انظر §٦ في `EDITOR-ARCHITECTURE.md`). يُنشأ جدول `TemplateBindings` بدل
الاعتماد على عَلَم `isDefault` الذي لا يعرف فرعاً ولا طابعة.

**وأضف فئتين:** `sales_return` و `purchase_return`. بدونهما يتقاسم المرتجع فئة الفاتورة
ويستحيل أن يكون له قالب افتراضي خاص.

## ملفات القوالب الجاهزة

أحد عشر ملف JSON في `invoice_templates/` مكتوبة ببنية `importTemplateFromJson` الصحيحة
وبمفاتيح `content` سليمة. ثمانية تُستورد فوراً، وثلاثة (كشفا الحساب والتقرير) تعمل فور
تنفيذ الخطوة ٧.

## ما لا يجب فعله

- لا تبدأ بالواجهة.
- لا تكتب منطق تخطيط داخل ملف واجهة — إن اضطررت فالمحرك ناقص.
- لا تحذف `_buildItemsTable` قبل هجرة كل القوالب؛ اجعله غلافاً رفيعاً.
- لا مفسّر تعابير كامل للشروط — `field op value` تكفي.
- لا ترقية جماعية للقوالب؛ الهجرة **كسولة عند أول فتح** مع زر تراجع.

## فحص القبول — يُنفَّذ كاملاً بلا تدخل

```
١ · افتح «فاتورة مبيعات ضريبية — A4» من المكتبة
٢ · غيّر عنوان عمود «الصنف» إلى «البيان» وأضف English «Item»
٣ · اسحب «الإجمالي المستحق» ٥مم لأعلى
٤ · فعّل شرط «discount > 0» على عنصر الخصم
٥ · اضغط «حفظ وتفعيل كافتراضي»
٦ · شاشة حسم القوالب ⇒ فاتورة المبيعات تشير لهذا القالب
٧ · اطبع فاتورة حقيقية بلا خصم
   ⇒ رأس العمود «البيان / Item» · الإجمالي في موضعه الجديد · سطر الخصم غائب
٨ · أعد فتح القالب ⇒ كل التعديلات محفوظة كما تُركت
```

فشل أي خطوة يعني أن حلقة «عدّل ← احفظ ← اطبع» مكسورة، وهي الحلقة التي يقوم عليها كل شيء.

## اختبارات تمنع الانتكاس

`layout_overflow_test` · `layout_repeat_test` · `preview_equals_print_test` ·
`column_labels_test` · `empty_field_test` · `paper_width_guard_test` ·
`resolution_chain_test` · `thermal_narrow_test`

والموجود `no_bare_pdf_document_test` يبقى — أمسك عطباً حقيقياً من قبل.

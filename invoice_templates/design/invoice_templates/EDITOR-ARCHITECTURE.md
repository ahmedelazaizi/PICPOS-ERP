# محرر النماذج — الوثيقة المعمارية للمنفّذ

المقروء قبل الكتابة: `templated_invoice_service.dart` · `invoice_template_dao.dart` ·
`invoice_template_tables.dart` · `invoice_section_editor.dart` · `invoice_designer_properties.dart` ·
`report_pdf_generator.dart` · `template_json_flags.dart`.

---

## ٠ · المشكلة الجذرية بجملة واحدة

**نموذجا تخطيط يعملان في نفس الوقت.** الكانفاس يحفظ `xPosition`/`yPosition`، والراسم
(`printWithTemplate` → `layoutSequenceForPrint`) يبني تدفّقاً من `sortOrder` + `flexWidth`
**ويتجاهل الإحداثيات تماماً**. فوقهما ثلاث واجهات تحرير تكتب في نفس الحقول بثلاثة تصوّرات.

أي عمل على الواجهة قبل حسم هذا التناقض يبني كذبة أجمل: المستخدم يضبط موضعاً ويطبع فيجده
في مكان آخر.

## ١ · القرار المعماري — نطاقات بإحداثيات داخلية

المستند **نطاقات** تتراصّ رأسياً. داخل كل نطاق، العناصر **بإحداثيات مطلقة بالمليمتر**
من حافة النطاق. النطاقات تتمدّد؛ العناصر لا تطفو بينها.

```
┌─ header   ─ يتكرر على كل صفحة ─────────┐
│  [company_name]        [logo]          │  ← إحداثيات حرة داخل النطاق
├─ info     ─────────────────────────────┤
│  [invoice_number]   [date]             │
├─ party    ─────────────────────────────┤
│  [customer_name]    [phone]            │
├─ details  ─ يتمدّد بالبيانات ★ ────────┤
│  ▓▓▓ items_table ▓▓▓                   │  ← وحده الذي يدفع ما بعده
├─ totals   ─────────────────────────────┤
│                      [total_amount]    │
├─ footer   ─ يتكرر على كل صفحة ─────────┤
│  [qr] [tax_registration]   [page]      │
└────────────────────────────────────────┘
```

**لماذا لا إحداثيات مطلقة على الورقة كلها:** جدول بـ٣٠ صنفاً بدل ٥ يدهس المجاميع.
**لماذا لا تدفّق خالص:** لأن المستخدم طلب حرية الموضع، والتدفّق يمنعها.
النطاق يحلّ الاثنين: حرية كاملة داخله، وأمان كامل بينها.

هذا نمط قياسي — Crystal Reports و JasperReports و RDLC و FastReport كلها bands.

## ٢ · العقد — مصدر حقيقة واحد

اليوم يوجد ثلاثة رُسّام: الـPDF، ونافذة المعاينة، ومعاينة محرر الأقسام. وجود
`debugRenderItemsTable` كمِقبض اختبار دليلٌ مكتوب على أنهم اكتووا بـ«المعاينة ≠ الورق».

**القاعدة:** بنية واحدة يستهلكها الثلاثة.

```dart
// lib/domain/printing/template_document.dart — بلا أي اعتماد على Flutter أو pdf
class TemplateDocument {
  final PaperSpec paper;          // widthMm, heightMm?, marginsMm
  final List<TemplateBand> bands; // بالترتيب الرأسي
  final TableSpec? table;
}

class TemplateBand {
  final BandId id;                // header | info | party | details | totals | footer
  final double heightMm;
  final bool repeatEachPage;      // header/footer
  final bool growsWithData;       // details وحده
  final bool autoHeight;          // يتقلّص لأصغر ارتفاع يسع عناصره
  final bool visible;
  final List<TemplateElement> elements;
}

class TemplateElement {
  final String id, contentKey;    // ← مفتاح المتغير: هو ما يطابقه المحرر
  final double xMm, yMm, wMm, hMm;// من حافة النطاق (البداية = اليمين في RTL)
  final String? labelAr, labelEn;
  final double fontSize;
  final bool bold, visible;
  final TextAlignSpec align;
  final String? colorHex;
  final String? condition;        // "discount > 0" — فارغ = يظهر دائماً
}

class TableSpec {
  final TableKind kind;           // items | ledger | report
  final List<TableColumn> columns;// بالترتيب المعروض
  final double fontSize, headerFontSize, rowHeightMm;
  final bool bilingualHeaders, repeatHeader, keepRowTogether;
  final int decimalPlaces;
}

class TableColumn {
  final String key;
  final String labelAr, labelEn;  // ← قابلة للتعديل. اليوم حرفية في الكود
  final double flex;              // نسبي لا مليمترات
  final int decimals;
  final ColumnAlign align;
  final bool visible, wrap;
  final String? formula;          // "[total] - [discount]"
}
```

**قاعدة صارمة:** `TemplateDocument` لا يستورد `package:pdf` ولا `package:flutter`.
هذا ما يجعل نفس البنية قابلة للرسم على قماشين مختلفين وللاختبار بلا واجهة.

## ٣ · حدود الملفات

| الملف | المسؤولية | لا يفعل |
|-------|-----------|---------|
| `domain/printing/template_document.dart` | البنية أعلاه فقط | لا رسم ولا قاعدة بيانات |
| `domain/printing/template_mapper.dart` | صفوف الجداول ⇄ `TemplateDocument` | لا رسم |
| `domain/printing/condition_evaluator.dart` | تقييم `condition` و `formula` | لا رسم |
| `services/printing/layout_engine.dart` | نطاقات ⇄ صفحات · التمدّد · التكرار · القطع | لا يعرف pdf ولا Flutter |
| `services/printing/pdf_painter.dart` | `PositionedPage` ⇒ `pw.Widget` | لا منطق تخطيط |
| `presentation/.../editor_canvas_painter.dart` | نفس `PositionedPage` ⇒ ويدجت Flutter | لا منطق تخطيط |
| `data/.../invoice_template_dao.dart` | حفظ واسترجاع واستيراد وتصدير | لا منطق تخطيط |
| `services/printing/template_resolver.dart` | سلسلة حسم القالب | لا رسم |

**المفتاح:** `layout_engine` يُنتج `List<PositionedPage>` — عناصر بمواضع نهائية مطلقة على
الصفحة. الراسمان يأخذانها كما هي. فيستحيل أن تختلف المعاينة عن الورق، لأن التخطيط حُسب
مرة واحدة.

## ٤ · ترتيب التنفيذ — كل خطوة تُشحن وحدها

**١ · البنية والمحرك بلا واجهة** — `TemplateDocument` + `layout_engine` + اختبارات وحدة.
اختبر: ٤٢ صنفاً ينقسم على صفحتين والمجاميع لا تُدهس · الرأس يتكرر · الصف لا ينقسم.
لا شيء يتغيّر للمستخدم بعد. هذه أطول خطوة وأهمها.

**٢ · وصل الراسم** — `pdf_painter` يستهلك `PositionedPage`. يبقى `_buildItemsTable`
الحالي كغلاف حتى تُهاجَر القوالب. **معيار النجاح:** كل قالب قائم يطبع كما كان بالضبط.

**٣ · عناوين الأعمدة والتسميات** — أزل الحرفيات من `_buildItemsTable` (السطور ١٥٩٠—١٦٢٤)
واقرأ `TableColumn.labelAr/labelEn`. أضف حقلي التسمية للوحة الخصائص. **هنا تعمل ثنائية
اللغة في رؤوس الجدول لأول مرة.**

**٤ · الشروط والمعادلات** — `condition_evaluator`. ابدأ بقواعد بسيطة
(`field op value`) لا بمفسّر تعابير كامل.

**٥ · واجهة المحرر الجديدة** — `PicPos Template Editor.dc.html`. لا تبدأها قبل ١—٤:
الواجهة تعرض ما يحسبه المحرك، فإن لم يكن المحرك جاهزاً عرضت وعوداً.

**٦ · سلسلة الحسم** — `template_resolver` + شاشة `PicPos Template Resolution.dc.html`.

**٧ · الامتداد لكشف الحساب والتقارير** — حسب `EXTENSION-SPEC.md`.

## ٥ · ما يُحذف أو يُصلَح — مقيس لا مُخمَّن

| البند | الحالة | القرار |
|------|--------|--------|
| `xPosition`/`yPosition` | يُحفظ ويُتجاهل | **يصير ذا معنى** — إحداثيات داخل النطاق |
| `flexWidth` | يقود التدفّق | يُحذف بعد الهجرة — العرض صار `wMm` |
| `rowIndex` | غير مستعمل عملياً | يُحذف |
| `headerBgColor` · `headerTextColor` | في الجدول والواجهة **ويتجاهلهما الراسم عمداً** | إمّا تُوصَل بحدٍّ أدنى للتباين، وإمّا **تُحذف من الواجهة**. الحالي أسوأ الخيارين: المستخدم يغيّر ولا يحدث شيء |
| `headerBold` | يُخزَّن ولا يُقرأ (تعليق صريح في الكود) | يُحذف — العناوين عريضة دائماً |
| `defaultFont` | افتراضيته `Cairo` والراسم يحمّل Noto Naskh عمداً (Cairo ينقصه U+FEF1) | يُوصَل بقائمة خطوط آمنة، أو يُحذف |
| عناوين الأعمدة الحرفية | ثمانية سطور في `_buildItemsTable` | تُقرأ من `TableColumn` |
| `footer_text` | المحرر يخزّن المفتاح، والراسم يطبعه حرفياً | إمّا يخزّن المحرر النصّ، وإمّا `case 'footer_text'` يقرأ `labelAr` |
| حالة المطبخ الخاصة | `if (category == 'kitchen')` خارج السلسلة | تُضمّ لسلسلة الحسم الموحّدة |

## ٦ · سلسلة الحسم

المفتاح: **نوع المستند + الفرع + الطابعة + اللغة**، تُجرَّب من الأخصّ للأعمّ وأول
مطابقة تفوز:

```
١ · document + branch + printer + lang
٢ · document + branch + *       + lang
٣ · document + *      + *       + lang
٤ · document + *      + *       + *
٥ · category + *      + *       + *      ← السلوك الحالي، يبقى للتوافق
٦ · التصميم المدمج في الكود
```

جدول جديد بدل الاعتماد على `isDefault` وحده:

```dart
class TemplateBindings extends Table {
  IntColumn  get id         => integer().autoIncrement()();
  TextColumn get documentType => text()();          // sales_invoice · sales_return · …
  IntColumn  get branchId   => integer().nullable()();  // null = أي فرع
  IntColumn  get printerId  => integer().nullable()();  // null = أي طابعة
  TextColumn get locale     => text().nullable()();     // null = أي لغة
  IntColumn  get templateId => integer().references(InvoiceTemplates, #id)();
  IntColumn  get copies     => integer().withDefault(const Constant(1))();
  BoolColumn get directPrint=> boolean().withDefault(const Constant(false))();
  IntColumn  get priority   => integer().withDefault(const Constant(0))();
}
```

**حارس مطلوب:** يُرفض الحفظ حين يختلف `template.paperWidth` عن عرض الطابعة المربوطة —
اليوم يُقصّ المطبوع بلا رسالة.

**وفئتان جديدتان على الأقل:** `sales_return` و `purchase_return`. بدونهما يتقاسم المرتجع
فئة الفاتورة ويستحيل أن يكون له قالب افتراضي خاص. (مرصود في شاشة الحسم كـ«تصادم فئة».)

## ٧ · حفظ القالب وتفعيله — المسار الذي سأل عنه المالك

```
تعديل في المحرر
   └→ TemplateDocument في الذاكرة (لا كتابة بعد)
       └→ «حفظ» ⇒ معاملة واحدة:
            ١ · تحديث صف InvoiceTemplates
            ٢ · حذف عناصر القالب وإعادة كتابتها بالترتيب الجديد
            ٣ · تحديث TableSpec والأعمدة
            ٤ · كتابة/تحديث صف TemplateBindings لو ضُغط «تفعيل كافتراضي»
            ٥ · إبطال ذاكرة الحسم المؤقتة
       └→ الطباعة التالية تقرأ الرابطة الجديدة فوراً
```

ثلاث نقاط تُسقَط عادةً فتُنتج «عدّلت ولم يتغيّر شيء»:

1. **الحذف وإعادة الكتابة داخل معاملة واحدة.** الانقطاع في المنتصف يترك قالباً بلا عناصر.
2. **إبطال الذاكرة المؤقتة.** أي `cache` للقالب المحسوم يجب أن يُبطَل عند الحفظ.
3. **«الافتراضي» ليس عَلَماً على القالب بل رابطة.** `isDefault` عَلَم عالمي واحد لا يعرف
   الفرع ولا الطابعة — لذلك الرابطة تحلّ محلّه.

## ٨ · الاختبارات التي تمنع الانتكاس

| الاختبار | يمنع |
|---------|------|
| `layout_overflow_test` | ٤٢ صنفاً ⇒ صفحتان والمجاميع بعد آخر صف لا فوقه |
| `layout_repeat_test` | الرأس والتذييل على كل صفحة ورؤوس الأعمدة معادة |
| `preview_equals_print_test` | نفس `TemplateDocument` ⇒ نفس `PositionedPage` للراسمين |
| `column_labels_test` | تغيير `labelAr` يظهر في المطبوع (يمنع عودة الحرفيات) |
| `empty_field_test` | حقل بلا قيمة لا يطبع تسمية معلَّقة |
| `paper_width_guard_test` | رفض ربط قالب A4 بطابعة 80mm |
| `resolution_chain_test` | كل مستوى من الستة يُجرَّب بالترتيب |
| `thermal_narrow_test` | 58mm بثلاثة أعمدة بلا قصّ للإجمالي |

الموجود `no_bare_pdf_document_test` يبقى — أمسك عطباً حقيقياً من قبل.

## ٩ · ما لا يجب فعله

- **لا تبدأ بالواجهة.** الواجهة تعرض ما يحسبه المحرك.
- **لا راسم ثانٍ للمعاينة.** إن اضطررت لكتابة منطق تخطيط في ملف الواجهة فالمحرك ناقص.
- **لا تحذف `_buildItemsTable` قبل هجرة كل القوالب.** اجعله غلافاً.
- **لا مفسّر تعابير كامل للشروط.** `field op value` تغطي كل الحالات المطلوبة.
- **لا تخزّن الإحداثيات بالبكسل.** المليمتر وحدة الورق، والبكسل يتغيّر بالتكبير.

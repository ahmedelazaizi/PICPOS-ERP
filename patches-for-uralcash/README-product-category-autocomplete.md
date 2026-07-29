# Patch: إظهار التصنيف والمورّد عند تعديل الصنف

`product-category-autocomplete-fix.diff` — **بينتقل بالحرف.** مفيهوش أي إشارة
لثابت `Brand` (متحقَّق منه).

```bash
# من مجلد UralCash
git apply --3way /path/to/product-category-autocomplete-fix.diff
```

## الباج

افتح تعديل أي صنف ليه تصنيف ⇒ خانة «التصنيف *» بتطلع **فاضية**، رغم إن الصنف
مصنَّف فعلاً. نفس الحاجة في خانة «المورد».

الباج **موجود في UralCash بنفس الشكل** — الملفان أصلهما UralCash و PicPos
بيستخدمهم زي ما هم بلا فورك.

## ليه ده أخطر من إنه مجرد حقل فاضي

الحفظ كان **سليم**: `selectedCategoryId` محمَّل صح من أول `initState`، و
`_buildBasicTab` بيكتب `categoryId` الصح عند الحفظ حتى لو المستخدم ملمسش
الحقل. يعني الباج **عرضي بحت** — مفيش بيانات ضاعت.

لكن ده بالظبط اللي بيخلّيه مخادع: المستخدم بيشوف خانة إجبارية (`*`) فاضية،
فبيفتكر إن التصنيف اتمسح، وبيعيد اختياره — أو أسوأ، بيسيبها ويفتكر إنه ضيّع
التصنيف. وعلامة إنه عرضي كانت واضحة قدام العين طول الوقت: زر المسح ✕ بيظهر
(شرطه `selectedCategoryId != null`) في نفس اللحظة اللي الخانة فيها فاضية —
تناقض مستحيل لو الـ id كان فعلاً null.

## السبب الجذري

`Autocomplete` — يعني `RawAutocomplete` تحتها — بتقرا `initialValue` **مرة
واحدة بس** جوه `initState` بتاعها عشان تبني الـ `TextEditingController`
الداخلي، ومبتعيدش قراءتها في أي build بعد كده (وبتـassert لو بعتّله
`initialValue` و`textEditingController` مع بعض).

السلسلة:

1. أول build: `snapshot.connectionState == waiting` و`snapshot.data == null`
   ⇒ `categories == []`
2. `categories.where((c) => c.id == selectedCategoryId).firstOrNull?.name ?? ''`
   ⇒ **نص فاضي**
3. `RawAutocomplete` بيخزّن النص الفاضي ده في الـ controller بتاعه
4. الـ Future بيخلص ⇒ `FutureBuilder` يعيد البناء بالتصنيفات الحقيقية، بس
   عنصر الـ `Autocomplete` بيتعاد استخدامه (نفس النوع ونفس الموضع) ⇒ **مفيش
   `State` جديدة** ⇒ النص الفاضي عايش للأبد

وبيزود الطين بلة إن `future: repository.getCategories()` كان مبني **جوه**
`build` ⇒ Future جديد مع كل rebuild ⇒ الـ `FutureBuilder` بيرجع لحالة
`waiting` (قائمة فاضية) من أول وجديد مع كل `setState` — ومن ضمنها
`setState` بتاعة `_refreshFromDatabase`. يعني الحالة الفاشلة بتتعاد بدل ما
تُحل.

مش المشكلة مقارنة identity مقابل id — المقارنة `c.id == selectedCategoryId`
صح تماماً. ومش `categoryId` ناقص — بيتحمّل مرتين (initState ثم refresh).

## الإصلاح

في `lib/presentation/screens/products/widgets/product_edit_dialog.dart`
و`lib/presentation/widgets/dialogs/add_product_dialog.dart`:

1. **رفع الـ Future لحقل** (`_categoriesFuture` / `_suppliersFuture`) يتبني
   مرة واحدة بـ `??=` بدل إنشائه في كل build — فالـ `FutureBuilder` ميرجعش
   لحالة التحميل مع كل `setState`.
2. **`key: ValueKey('category-${categories.length}-$selectedCategoryId')`**
   على الـ `Autocomplete` — أول ما التصنيفات توصل بيتغير الـ key فتتبني
   `State` جديدة تقرا `initialValue` وهو دلوقتي بيتحل للاسم الصح.

الـ key متعلّق بالـ id كمان مش بالطول بس، عشان لما المستخدم يختار تصنيف أو
يمسحه بالـ ✕ الخانة تعكس الاختيار الجديد فوراً. الكتابة العادية مبتغيّرش
الـ key، فالبحث شغال طبيعي.

## المورّد كمان

`_buildSupplierSelector` فيه **نفس العطل حرفياً** — اتصلح في نفس الكوميت.

## `add_product_dialog` — وقاية

نفس النمط موجود هناك بس **مستخفي**: الإضافة بتبدأ بـ `_selectedCategoryId ==
null` فالنص الفاضي صح بالصدفة. اتصلح برضه عشان النمط ميرجعش يعض لو حد ضاف
لاحقاً «إضافة صنف بتصنيف مبدئي» أو نسخ صنف.

## التحقق

```
flutter analyze lib/presentation/screens/products/widgets/product_edit_dialog.dart \
                lib/presentation/widgets/dialogs/add_product_dialog.dart
⇒ No issues found!
```

يدوياً: افتح تعديل صنف ليه تصنيف ⇒ الاسم ظاهر فوراً · احفظ من غير ما تلمس
الحقل ⇒ التصنيف زي ما هو · اختار تصنيف تاني ⇒ الخانة تتحدّث · امسح بالـ ✕
⇒ تفضى. كرّر نفس الفحص على المورّد.

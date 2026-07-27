# إعادة تصميم شاشات PicPos — مستند التصميم

> **الحالة:** معتمد للتخطيط · **التاريخ:** ٢٠٢٦-٠٧-٢٧ · **الفرع:** `feat/lite-profile-and-pos-ui`
> **المرجع:** `HANDOFF.md` القسم ٥ (أولوية ١) والقسم ٥.٥ (البند ٣).

---

## ١. الهدف

الثيم (`PicPosTheme`) بيغطّي **شكل** كل الشاشات من `ThemeData` واحدة، لكن **تخطيط** الشاشات
لسه بنية UralCash: كل شاشة بتكتب `Scaffold + Padding + Column` + هيدر يدوي + كروت بـ
`elevation`/حواف inline بتتجاوز الثيم. المطلوب: تخطيط **مختلف ومناسب لهوية PicPos**
للشاشات، مع إبقاء **منطق الأزرار وطريقة عملها واحد بالظبط**.

نطاق العيّنة (المرحلة ١): **٣ شاشات** — المشتريات، المخزون، الأصناف — نخلّصها ونراجع
الناتج قبل ما نقرّر باقي شاشات بروفايل lite.

## ٢. القواعد المطلقة (من HANDOFF)

1. **ممنوع لمس أي ملف في `D:\URAL-ERP`**، وممنوع إضافة git remote أو الرفع.
2. **ممنوع تغيير الملاح التشفيرية الأربعة** (قسم ٣.٢).
3. **كل قيمة في `Brand` و`AppColors` تفضل `const`** (قسم ٣.١).
4. **ممنوع إضافة قيمة `AppFlavor` جديدة** (قسم ٣.٥).
5. **أي إصلاح باج منطقي في ملف محرك/خدمة مشتركة** = كوميت منفصل + patch لـ UralCash
   (قسم ٥.٦). تغييرات الهوية/التخطيط **لا تنتقل**.

## ٣. القرار المعماري

**شاشات PicPos منفصلة يختارها `Brand.isPicPos`** — نفس سابقة شاشة الـ POS
(`PicPosPosScreen`)، وليس مكوّنات مشتركة تتفرّع داخل ملفات UralCash.

**السبب:** القاعدة الأقوى في المشروع هي عدم المخاطرة بشكل/سلوك UralCash. الشاشة المنفصلة
**تستورد وتنادي** نفس الـ controllers والخدمات والجداول والحوارات، فـ«المنطق واحد» حرفياً،
وملفات UralCash **لا تُلمس نهائياً**. `Brand.isPicPos` ثابت وقت الترجمة، فبناء UralCash
يأخذ فرع `else` حرف بحرف زي دلوقتي، والـ tree-shaker يسقط فرع PicPos.

**المقايضة المقبولة:** تكوين الصفحة (ترتيب الهيدر/الكارت) يتكرر جزئياً بين النسختين. ده
تخطيط بحت (مش منطق)، ومقبول مقابل صفر مخاطرة على UralCash.

## ٤. تنظيم الملفات

```
lib/presentation/
  picpos_shell/                       ← طقم تخطيط PicPos مشترك (جديد، PicPos فقط)
    picpos_screen_scaffold.dart       ← الإطار: RTL + خلفية canvas + هيدر + محتوى
    picpos_page_header.dart           ← الهيدر الموحّد: عنوان + وصف + أزرار + بحث/فلاتر
    picpos_toolbar.dart               ← صف أزرار/شرايح كبسولية بهوية PicPos
    picpos_content_card.dart          ← كارت مسطّح بحد شعري (بديل elevation:2)
  products_picpos/screens/products_picpos_screen.dart
  inventory_picpos/screens/inventory_picpos_screen.dart
  purchases_picpos/screens/purchases_picpos_screen.dart
```

`picpos_shell/` مكوّنات **PicPos-only** (لا يوجد فرع UralCash داخلها) → صفر مخاطرة على
UralCash، وتضمن اتساق الشاشات الحالية والقادمة من مصدر واحد.

## ٥. طقم تخطيط PicPos (`picpos_shell/`)

| المكوّن | المسؤولية | ملاحظات |
|---|---|---|
| `PicPosScreenScaffold` | `Directionality(rtl)` + `Scaffold` بخلفية canvas + هيدر أعلى + `Expanded` للمحتوى | يستقبل `title`, `subtitle?`, `headerActions?`, `search?`, `body` |
| `PicPosPageHeader` | الهيدر: **فاتح + خط لوني سفلي 2.5px بلون العلامة** (فلسفة الثيم)، عنوان داكن، وصف اختياري، أزرار/بحث | يقرأ التايبوغرافي من الثيم، مش fontSize يدوي |
| `PicPosToolbar` | صف أزرار/شرايح كبسولية بهوية PicPos | يلفّ أي widgets تُمرَّر إليه |
| `PicPosContentCard` | كارت مسطّح بحد شعري (بديل `elevation:2`/`radius:12` الـ inline) | حدود بدل ظلال، زوايا ١٤ |

## ٦. لغة PicPos البصرية

مشتقّة من `PicPosTheme` وشاشة الـ POS:

- **الهيدر:** فاتح، عنوان داكن، خط سفلي `2.5px` بلون العلامة (`AppColors.primary`).
- **المحتوى:** كروت مسطّحة بحدود شعرية، بلا ظلال، زوايا ١٢–١٦.
- **الأزرار/الفلاتر:** شرايح كبسولية (Stadium)، حقول مملوءة بلا حد لحد التركيز.
- **الجداول:** رأس مصمت بلون العلامة ونص أبيض، صفوف أطول (من الثيم بالفعل).
- **التايبوغرافي:** من `Theme.of(context).textTheme` — ممنوع `fontSize` يدوي في الهيدر.

## ٧. خطة كل شاشة

### ٧.١ الأصناف — `ProductsPicposScreen` (نبدأ بيها)
- **يعيد الاستخدام بلا تغيير:** `productsControllerProvider`, `ProductsTable`,
  `ProductsBulkActionBar`, `AddProductDialog`, `excelService`, `LabelScaleService`,
  حوار التصنيفات، منطق `_onScroll`/الباجينيشن.
- **جديد (تخطيط فقط):** هيدر «الأصناف / إدارة المنتجات والتسعير» + بحث، و`PicPosToolbar`
  بأزرار (التصنيفات ▾ · الميزان ▾ · تصدير · استيراد · وحدات · + صنف) تنادي نفس الخدمات،
  و`PicPosContentCard` حاوي الجدول.

### ٧.٢ المخزون — `InventoryPicposScreen` (تبويبات)
- **يعيد الاستخدام:** `inventoryNotifier`/الـ providers, `StockBalancesTable`,
  `StockMovementsTable`, `InventorySummaryRow`, حوارات التسوية, `_loadInventoryPage`.
- **جديد:** هيدر «المخزون» + بطاقات الملخص، `TabBar` بهوية PicPos (الأرصدة / الحركة)،
  صف فلاتر لكل تبويب، الجداول جوّه كارت مسطّح.

### ٧.٣ المشتريات — `PurchasesPicposScreen` (استبدال AppBar)
- **يعيد الاستخدام:** `purchaseInvoicesControllerProvider`, القائمة/الجدول،
  `PurchaseInvoiceForm`, الحوارات والـ mixins عبر نفس الـ controller.
- **جديد:** استبدال `AppBar` بـ `PicPosScreenScaffold` + هيدر «المشتريات» + بحث + «+ فاتورة»،
  وشريط فلاتر (المورد/الحالة/التاريخ) إن وُجد في الأصل.

> **مبدأ «المنطق واحد»:** منطق الأزرار الفعلي يعيش في **خدمات** مشتركة
> (`excelService`, `LabelScaleService`, `AddProductDialog`, الحوارات). الهيدر الجديد
> ينادي نفس الخدمات — توصيل قليل الأسطر لكل زرار في تخطيط مختلف، مش نسخ منطق.

## ٨. الاختيار (wiring)

في `app_main_screen.dart` — نفس نمط الـ POS الموجود:
```dart
// products
builder: (_) => Brand.isPicPos ? const ProductsPicposScreen() : const ProductsScreen(),
// inventory / purchases: نفس SecurityScreenGate، نبدّل الـ child فقط
child: Brand.isPicPos ? const InventoryPicposScreen() : const InventoryScreen(),
child: Brand.isPicPos ? const PurchasesPicposScreen() : const PurchaseInvoicesScreen(),
```
هذا التعديل **إضافي** ونفس السابقة؛ فرع `else` = سلوك UralCash الحالي حرف بحرف.

## ٩. الاختبارات والتحقق

- **widget test لكل شاشة PicPos:** ترسم بنجاح وتنادي نفس الـ providers/الخدمات.
- **اختبار الاختيار:** `Brand.isPicPos == false` لسه يعطي شاشة UralCash الأصلية.
- **بعد كل شاشة:** `flutter analyze` → اختبارات العلامتين.
- **في النهاية:** `build_picpos.bat` + فحص binary بالترميزين (٤ ملاح · UTF-16=٠ ·
  صفر لـ monexia/cashier_market/avalon).
- **الأساس الأخضر:** `+3262 ~12 · 0 فشل` بقيود FK مشغّلة (متحقَّق منه).

## ١٠. خارج النطاق (غير أهداف)

- إعادة تصميم الجداول/النماذج/الحوارات نفسها (تأخذ شكلها من الثيم) — نغيّر **التأطير** فقط.
- باقي شاشات lite الـ١٦ — قرار بعد مراجعة العيّنة.
- أي تغيير في منطق الأعمال، المحاسبة، المخزون، المزامنة.
- توصيل لوحة العرض الجانبية (`picpos_side_panel.dart`) — بند منفصل في HANDOFF.

## ١١. أسئلة مفتوحة

- بعد العيّنة: هل نوسّع الطقم لكل شاشات lite، وبأي ترتيب؟ (يُحسم بعد المراجعة.)

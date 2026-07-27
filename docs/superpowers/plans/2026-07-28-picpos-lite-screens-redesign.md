# خطة تنفيذ — إعادة تصميم باقي شاشات lite بهوية PicPos

> **For agentic workers:** REQUIRED SUB-SKILL: استخدم `superpowers:subagent-driven-development` (موصى به) أو `superpowers:executing-plans` لتنفيذ الخطة مهمة-بمهمة. الخطوات بصيغة checkbox (`- [ ]`) للتتبّع.

**Goal:** إعادة تصميم ١٦ شاشة lite متبقية بهوية PicPos عبر شاشات منفصلة يختارها `Brand.isPicPos`، تعيد استخدام نفس المنطق، فوق طقم `picpos_shell` — دون لمس UralCash.

**Architecture:** لكل شاشة، شاشة PicPos في مجلد `*_picpos/` **تستورد وتنادي** نفس الـ controllers/providers/tables/dialogs الموجودة، وتبدّل طبقة العرض فقط بطقم `picpos_shell`. الاختيار في `app_main_screen.dart` (أو موقع `Navigator.push` للشاشات الفرعية) بـ `Brand.isPicPos ? XPicpos : X` — فرع `else` = سلوك UralCash حرف بحرف. الميزان يُضاف لـ lite بفرع `Brand.isPicPos` في `screen_registry.dart`.

**Tech Stack:** Flutter · Riverpod 3 · drift (SQLite) · phosphor_flutter · google_fonts (Cairo). اسم الحزمة الداخلي `ural_erp` (مقبول، لا يُغيَّر). المرجع: السبيك `docs/superpowers/specs/2026-07-28-picpos-lite-screens-redesign-design.md`.

## Global Constraints

- **UralCash لا يُلمس:** ممنوع فتح/قراءة/تعديل `D:\URAL-ERP`. التعديل الوحيد على ملف مشترك = سطر اختيار بالعلامة (فرع `else` = سلوك UralCash الحالي).
- **ممنوع git remote / push.** الريبو بلا remote عن قصد.
- **الملاح التشفيرية الأربعة** (`api_auth_middleware.dart`, `api_session_token.dart`, `invoice_integrity_service.dart`, `license_service.dart`) لا تُلمس.
- **`Brand` و`AppColors`:** كل قيمة `const`. ممنوع تحويل أي لون لـ getter.
- **ممنوع إضافة قيمة `AppFlavor` جديدة.**
- **قاعدة الـ patch:** أي إصلاح باج **منطقي** في محرك/خدمة/مستودع مشترك = كوميت منفصل + patch في `patches-for-uralcash/`. تغييرات التخطيط/الهوية لا تنتقل. الكود المنسوخ في fork ليس مشتركاً؛ لكن إصلاحه المنطقي يتصلّح في مصدر UralCash أولاً ثم patch — مصيدة النسخ.
- **العربي في الملفات:** استخدم أداة Edit/Write (PowerShell بيخرّب UTF-8).
- **`flutter` مش على PATH:** `D:\Cash\develop\flutter\bin` — أضِفه لكل أمر flutter؛ ولـ `build_picpos.bat` من PowerShell: `$env:PATH = "D:\Cash\develop\flutter\bin;$env:PATH"`.
- **الأساس الأخضر (متحقَّق منه، §٥.٩):** `flutter test --concurrency=1` = `+3289 ~12 · 0 فشل`. الجولة **بالتوازي بتفلك** (موت isolate) — استخدم `--concurrency=1` دائماً للجولة الكاملة.
- **اختبار render لشاشة كاملة بيهنّج** تحت flutter_test (§٥.٨) — اختبر **المكوّنات المعزولة الجديدة** فقط؛ render الشاشة يتحقق بالبناء/التشغيل اليدوي.
- **الترتيب مقصود:** بالقرابة للفورك، مراجعة (batch gate) بعد كل باتش.

---

## Task 0: التحقق من الأساس

- [ ] **الخطوة ١:** أكّد الفرع والشجرة النظيفة.
```bash
git -C D:/PICPOS-ERP branch --show-current   # feat/lite-profile-and-pos-ui
git -C D:/PICPOS-ERP status --short           # نظيف
```
- [ ] **الخطوة ٢:** أكّد طقم `picpos_shell` موجود (لا يُنشأ من جديد).
```bash
ls D:/PICPOS-ERP/lib/presentation/picpos_shell/
# picpos_screen_scaffold.dart · picpos_page_header.dart · picpos_content_card.dart · picpos_toolbar.dart
```
- [ ] **الخطوة ٣:** حليل نظيف كنقطة بداية.
```bash
cd D:/PICPOS-ERP && export PATH="/d/Cash/develop/flutter/bin:$PATH" && flutter analyze lib | tail -3
# Expected: No issues found!
```

---

## مرجع: وصفة الفورك (Fork Recipe) — تُطبَّق في كل مهمة شاشة

كل شاشة PicPos تتبع نفس النمط. **اقرأ ملف الشاشة المصدر أولاً** لتعرف الودجتس/الحوارات التي تُعيد استخدامها، ثم:

**١) أنشئ الفورك** `lib/presentation/<screen>_picpos/screens/<screen>_picpos_screen.dart`:
- شاشة `ConsumerStatefulWidget`/`ConsumerWidget` (طابِق الأصل).
- **استورد وأعد استخدام** نفس الـ providers/controllers/tables/dialogs الموجودة (لا تكرّر منطقاً).
- ابنِ العرض بطقم `picpos_shell`. المثال (نموذج salesInvoices):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../screens/sales_invoices_controller.dart'; // نفس الـ provider

class SalesInvoicesPicposScreen extends ConsumerStatefulWidget {
  const SalesInvoicesPicposScreen({super.key});
  @override
  ConsumerState<SalesInvoicesPicposScreen> createState() => _SalesInvoicesPicposScreenState();
}

class _SalesInvoicesPicposScreenState extends ConsumerState<SalesInvoicesPicposScreen> {
  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: 'فواتير البيع',
      subtitle: 'إدارة فواتير المبيعات ومتابعة التحصيل',
      icon: PhosphorIconsBold.receipt,
      headerActions: [ /* أزرار توصّل لنفس دوال الإنشاء/التصدير */ ],
      body: PicPosContentCard(child: /* نفس الجدول/القائمة الأصلية */),
    );
  }
}
```
- **لو الأصل mixin/`part of`:** انسخ ملفات الـ `part`/mixin حرفياً داخل مجلد الفورك (غيّر `part of` لاسم مكتبة الفورك)، وسجّل في رأس كل ملف منسوخ تعليق «منسوخ من `<الأصل>` — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch» (مصيدة النسخ).

**٢) وصّل الاختيار بالعلامة** في `app_main_screen.dart` عند سطر الشاشة:
```dart
builder: (_) => Brand.isPicPos ? const XPicposScreen() : const XScreen(),
// أو للشاشات المحاطة بـ SecurityScreenGate: بدّل الـ child فقط.
```

**٣) اختباران قياسيان** (المكوّنات المعزولة — مش render الشاشة الكاملة):
- **اختبار المكوّن الجديد:** `test/widget/picpos_<screen>_test.dart` — يبني أي widget عرض جديد PicPos-only معزول (مثل هيدر/كارت مخصّص) ويؤكّد ظهوره تحت `PicPosTheme.lightTheme`.
- **اختبار الاختيار:** يؤكّد أن `Brand.isPicPos == false` يعطي شاشة UralCash (عبر اختبار الراوتر/الـ builder إن أمكن، أو اختبار وحدة على دالة الاختيار).

**٤) بوابة كل مهمة:** `flutter analyze lib` (صفر) ثم commit.

**قالب الـ commit:** `feat(picpos): شاشة <الاسم> بهوية PicPos (fork يعيد استخدام <الـ provider>)`.

---

## Batch أ — فواتير/مرتجعات (≈ فورك المشتريات)

### Task 1: فواتير البيع — `SalesInvoicesPicposScreen`
**Files:**
- Create: `lib/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart`
- Copy (part-of → مكتبة الفورك): `widgets/sales_invoices/sales_summary_cards.dart` · `sales_invoices_table.dart` · `sales_filter_bar.dart` · `sales_invoice_dialogs.dart` · `sales_invoice_save_edit.dart` · `sales_batch_action_bar.dart`
- Modify: `lib/app_main_screen.dart:778-782`
- Test: `test/widget/picpos_sales_invoices_test.dart`

**Reuse:** `salesInvoicesControllerProvider` · `SalesInvoiceForm` (standalone) · `AddProductDialog` · `SearchableUnitSelectionDialog` · `SyncPendingBanner`. تجاهل مجلد `screens/sales_invoices/` الميت.
**Copy-cost:** الـ٦ ملفات `part of _SalesInvoicesScreenState` تُنسخ (نفس مصيدة §٥.٨).
**Header:** «فواتير البيع» / «إدارة فواتير المبيعات ومتابعة التحصيل».

- [ ] **الخطوة ١:** اقرأ `lib/presentation/screens/sales_invoices_screen.dart` + ملفات الـ part لفهم البنية.
- [ ] **الخطوة ٢:** اكتب `test/widget/picpos_sales_invoices_test.dart` (اختبار المكوّن الجديد المعزول — يفشل).
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/picpos_theme.dart';
import 'package:ural_erp/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart';
void main() {
  testWidgets('SalesInvoicesPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const SalesInvoicesPicposScreen(), isA<Widget>());
  });
}
```
- [ ] **الخطوة ٣:** شغّل الاختبار — Expected: FAIL (الملف غير موجود).
- [ ] **الخطوة ٤:** أنشئ الفورك حسب الوصفة (انسخ ملفات الـ part، غيّر `part of`، أضف تعليق مصيدة النسخ، ابنِ العرض بـ `picpos_shell` مع إعادة استخدام `salesInvoicesControllerProvider` والجدول والحوارات).
- [ ] **الخطوة ٥:** عدّل `app_main_screen.dart:778-782`:
```dart
builder: (_) => Brand.isPicPos ? const SalesInvoicesPicposScreen() : const SalesInvoicesScreen(),
```
- [ ] **الخطوة ٦:** `flutter analyze lib` = صفر، والاختبار PASS.
- [ ] **الخطوة ٧:** commit.

### Task 2: مرتجع مبيعات — `SalesReturnsPicposScreen`
**Files:** Create `lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart` · Copy mixins `sales_returns/return_logic.dart` (`_ReturnLogicMixin`) + `sales_returns/return_details_panel.dart` (`_ReturnDetailsPanelMixin`) · Modify `app_main_screen.dart:951-956` · Test `test/widget/picpos_sales_returns_test.dart`.
**Reuse:** `salesReturnProvider` · `thermal_receipt_generator` · `SyncPendingBanner`. القائمة inline (`_buildInvoiceList`) واللوحة (`buildReturnDetailsPanel` من mixin).
**Copy-cost:** الـ mixinان يُنسخان.
**Header:** «مرتجع المبيعات» / «تسجيل ومتابعة مرتجعات البيع».
- [ ] نفس خطوات الوصفة (١–٧) بأسماء هذه الشاشة. سطر الاختيار:
```dart
builder: (_) => Brand.isPicPos ? const SalesReturnsPicposScreen() : const SalesReturnsScreen(),
```

### Task 3: مرتجع مشتريات — `PurchaseReturnsPicposScreen`
**Files:** Create `lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart` · Copy mixins `purchase_returns/return_logic.dart` (`_PurchaseReturnLogicMixin`) + `purchase_returns/return_details_panel.dart` (`_PurchaseReturnDetailsPanelMixin`) · Modify `app_main_screen.dart:957-962` · Test `test/widget/picpos_purchase_returns_test.dart`.
**Reuse:** `purchaseReturnProvider` · `allProductsProvider` · `invoice_generator`. القوائم/الفلاتر inline.
**Copy-cost:** الـ mixinان يُنسخان.
**Header:** «مرتجع المشتريات» / «تسجيل ومتابعة مرتجعات الشراء».
- [ ] نفس الوصفة. سطر الاختيار:
```dart
builder: (_) => Brand.isPicPos ? const PurchaseReturnsPicposScreen() : const PurchaseReturnsScreen(),
```

### Batch أ — بوابة المراجعة
- [ ] `flutter analyze lib` = صفر.
- [ ] `flutter test --concurrency=1 test/unit/brand_isolation_test.dart` (uralcash 12) و`flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart` (picpos 7) — خضرا.
- [ ] `flutter test --concurrency=1` (الجولة الكاملة) — صفر ارتداد.

---

## Batch ب — التصنيفات (≈ فورك الأصناف)

### Task 4: التصنيفات — `CategoriesPicposScreen`
**Files:** Create `lib/presentation/categories_picpos/screens/categories_picpos_screen.dart` · Modify `app_main_screen.dart:683-688` · Test `test/widget/picpos_categories_test.dart`.
**Reuse:** `categoriesControllerProvider` · `CategoryCard` · `CategoryIconPicker` (كما هي).
**Copy-cost:** الشاشة **monolith 1241 سطر** بحوارات inline (`_showAddCategoryDialog`, `_showEditCategoryDialog`, `_showEmptyCategoryDeleteDialog`, `_showBulkMoveDeleteDialog`) ومنطق `_isReorderMode`/`_buildReorderGrid`/`_buildColorPalette` — يُنسخ منطق الـ State داخل الفورك (مع إعادة استخدام `CategoryCard`/`CategoryIconPicker` الخارجية). سجّل تعليق مصيدة النسخ.
**Header:** «التصنيفات» / «تنظيم تصنيفات الأصناف».
- [ ] نفس الوصفة. سطر الاختيار:
```dart
builder: (_) => Brand.isPicPos ? const CategoriesPicposScreen() : const CategoriesScreen(),
```

### Batch ب — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Batch ج — عائلة المخزون (≈ فورك المخزون)

### Task 5: سندات المخزون — `InventoryBondsPicposScreen`
**Files:** Create `lib/presentation/inventory_bonds_picpos/screens/inventory_bonds_picpos_screen.dart` · Modify `app_main_screen.dart:791` · Test `test/widget/picpos_inventory_bonds_test.dart`.
**Reuse:** `inventoryBondsControllerProvider` (`BondItemModel`) · `allWarehousesProvider` · `allProductsProvider` · `searchProductsProvider` · `_ProductSearchDialog` (يُنسخ — كلاس داخلي). الجدول `DataTable` ٨ أعمدة + هيدر الفورم.
**Copy-cost:** monolith ~460 سطر، بلا `part` — يُنسخ منطق الـ State + `_ProductSearchDialog`.
**Header:** «سندات المخزون» / «إدخال وإخراج المخزون بالسندات».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const InventoryBondsPicposScreen() : const InventoryBondsScreen()`.

### Task 6: تحويل مخزني — `StockTransferPicposScreen`
**Files:** Create `lib/presentation/stock_transfer_picpos/screens/stock_transfer_picpos_screen.dart` · Modify `app_main_screen.dart:797` · Test `test/widget/picpos_stock_transfer_test.dart`.
**Reuse:** `stockTransferControllerProvider` (`TransferItemModel`) · نفس مزوّدات المستودعات/الأصناف · `_ProductSearchDialog`. الجدول ٥ أعمدة + هيدر (مصدر/وجهة/ملاحظات).
**Copy-cost:** monolith ~435 سطر — توأم `inventoryBonds`، نفس أسلوب النسخ.
**Header:** «تحويل مخزني» / «نقل الأصناف بين المستودعات».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const StockTransferPicposScreen() : const StockTransferScreen()`.

### Task 7: الجرد الميداني — `CycleCountPicposScreen` (= fieldAudit)
**Files:** Create `lib/presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart` · Copy controller import `cycle_count/cycle_count_controller.dart` (يُعاد استخدامه، لا يُنسخ منطقه) · Modify `app_main_screen.dart:941` (تحت `AppScreen.cycleCounting`) · Test `test/widget/picpos_cycle_count_test.dart`.
**ملاحظة:** `fieldAudit` مرادف لـ `cycleCounting` (index 42) — الشاشة الفعلية `CycleCountScreen`.
**Reuse:** `cycleCountControllerProvider` · `cycleCountRepositoryProvider` · `inventoryRepositoryProvider`. ٣ تبويبات (الخطط/المهام/التحليلات) — دوال بناء داخل الـ State تُنسَخ، والحوارات `_showCreatePlanDialog`/`_showGenerateTaskDialog` تُنسخ.
**Copy-cost:** semi-modular (الكنترولر مفصول ويُعاد استخدامه؛ الـ UI في ملف واحد يُنسخ).
**Header:** «الجرد الميداني» / «خطط ومهام جرد المخزون».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const CycleCountPicposScreen() : const CycleCountScreen()`.

### Batch ج — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Batch د — ميزان PLU (فورك منفصل + ضمّه لـ lite بالعلامة)

### Task 8: ميزان PLU — `ScalePluPicposScreen`
**Files:**
- Create: `lib/presentation/scale_plu_picpos/screens/scale_plu_picpos_screen.dart` (القشرة)
- Copy (`part of` → مكتبة الفورك): `scale_plu/scale_panels.dart` (`_ScalePanelsMixin`, 679س) · `scale_plu/scale_logic.dart` (`_ScaleLogicMixin`, 922س)
- (اختياري لنفس الهوية) fork `plu_manager_screen.dart` + الـ٤ mixins (`plu_table_mixin`/`plu_auto_assign_mixin`/`plu_csv_mixin`/`plu_scale_upload_mixin`) + `plu_manager_controller.dart` — أو أعِد استخدام `PluManagerScreen` كما هي (يأخذ ثيم PicPos تلقائياً). **قرار:** ابدأ بإعادة استخدام `PluManagerScreen` كما هي؛ فورِكها فقط لو ظهر تعارض هوية.
- Modify: `lib/app_main_screen.dart:808-809` · `lib/core/navigation/screen_registry.dart` (فرع lite بالعلامة)
- Test: `test/widget/picpos_scale_plu_test.dart`
**Reuse (كما هي):** `scaleRepositoryProvider` · `settingsRepositoryProvider` · `visibleCategoriesProvider` · `allProductsProvider` · `LabelScaleService.instance` · `ScaleTransport` · `scaleItemIsSoldByWeight(...)`. اللوحات `buildHeader`/`buildCategoryPanel`/`buildItemsGrid`/`buildScalePanel` والحوارات `showScaleDialog`/`_showDataPreview` من الـ mixins المنسوخة.
**Copy-cost + باج ٩:** القشرة + الـ mixinان يُنسخان. الميزان **مرتبط بباج ٩ بشدة**: بناء الباركود `prefix + PLU.padLeft(len,'0')` حيث `prefix = weightPrefix('21')` لأصناف الوزن أو `pricePrefix('20')` للسعر، و`scaleItemIsSoldByWeight` (`weightByPiece → false`). عند النسخ **تحقّق أن إصلاح باج ٩ موجود في المصدر**، وأي إصلاح منطقي في المنسوخ يتصلّح في المصدر أولاً ثم patch.
**ضمّ لـ lite دون لمس UralCash** — في `screen_registry.dart`:
```dart
static const List<ScreenId> litePicpos = [ ...lite, ScreenId.scalePlu ];
// في forProfile:
case BusinessProfile.lite:
  return Brand.isPicPos ? litePicpos : lite; // UralCash-lite تفضل ١٩ حرف بحرف
```
(استورد `Brand` في `screen_registry.dart`.)
**Header:** «ميزان PLU» / «تصدير الأصناف وأكواد PLU للموازين».
- [ ] **الخطوة ١:** اقرأ القشرة + الـ mixinين وفهم تدفّق التصدير + إعدادات الباركود.
- [ ] **الخطوة ٢:** اكتب اختبار المكوّن (يفشل) + اختبار وحدة يؤكّد `Brand.isPicPos ? litePicpos : lite` يحتوي/لا يحتوي `scalePlu`.
- [ ] **الخطوة ٣:** شغّل — FAIL.
- [ ] **الخطوة ٤:** أنشئ الفورك (انسخ الـ mixins، غيّر `part of`، تعليق مصيدة النسخ + باج ٩)، وأضف فرع lite بالعلامة في `screen_registry.dart`، ووصّل الاختيار في `app_main_screen.dart:808`.
- [ ] **الخطوة ٥:** analyze صفر + الاختبارات PASS + **اختبار الهوية `brand_isolation_test`** (يؤكّد lite UralCash = ١٩) لسه أخضر.
- [ ] **الخطوة ٦:** commit.

### Batch د — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين (تأكيد lite UralCash ما زالت ١٩) · جولة كاملة `--concurrency=1`.

---

## Batch هـ — الصناديق

### Task 9: الخزينة — `TreasuryPicposScreen`
**Files:** Create `lib/presentation/treasury_picpos/screens/treasury_picpos_screen.dart` · Modify `app_main_screen.dart:722` (بدّل الـ `child` داخل `SecurityScreenGate` فقط) · Test `test/widget/picpos_treasury_test.dart`.
**Reuse (كما هي — أنظف فورك، modular):** `scopedSafesProvider` · `scopedRecentTransactionsProvider` · `reconciliationServiceProvider` · `getCashFlowStatementUseCaseProvider`. التبويبات/الودجتس من `treasury/widgets/`: `TreasuryMetricsPanel` · `TreasuryCashTab` · `TreasuryBankTab` · `TreasuryClosingTab` · `TreasurySafeCard` · `TreasuryTransactionsList`. الحوارات `ReceiptVoucherDialog`/`PaymentVoucherDialog`/`DailyClosingDialog`/`SafeManagementScreen` كما هي.
**Copy-cost:** ٥ تبويبات، اثنان داخليان (`_TreasuryClickTab`/`_CashFlowTab`) + `_ReconciliationDialog` يُنسخون؛ الباقي إعادة استخدام. حافِظ على `SecurityScreenGate` الملفّ.
**Header:** «الصناديق والخزينة» / «النقدية والبنوك وإغلاق اليوم».
- [ ] نفس الوصفة. الاختيار داخل الـ gate:
```dart
child: Brand.isPicPos ? const TreasuryPicposScreen() : const TreasuryScreen(),
```

### Task 10: إغلاق الوردية — قرار مطلوب ⚠️
**الاكتشاف:** `ScreenId.shiftClose` مُدرَج في قائمة lite لكن **لا يملك `AppScreen` ولا شاشة قابلة للتوجيه** — منطقه في حوارات (`DailyClosingDialog` عبر `TreasuryClosingTab`، و`PosCashierClosingDialog` مدفوع بـ `posClosingControllerProvider`) و`DailyCashClosingDialog`.
**التوصية:** بما أن العمل «إعادة تصميم شاشات موجودة»، والحوارات دي **تأخذ ثيم PicPos تلقائياً**، **لا فورك منفصل مطلوب لـ shiftClose في هذه الجولة**. لو صاحب المشروع أراد **شاشة إغلاق وردية مستقلة** بهوية PicPos، فهي **ميزة جديدة** (شاشة جديدة + إدخال `AppScreen` + راوتر) خارج نطاق «الفورك»، تُخطَّط منفصلة.
- [ ] **الخطوة ١:** أكّد القرار مع صاحب المشروع (حوار متأطّر بالثيم يكفي / أم شاشة مستقلة جديدة).
- [ ] **الخطوة ٢ (إن اكتُفي بالحوار):** لا كود — علّم المهمة مكتملة بقرار «مغطّى بالثيم». (إن طُلبت شاشة جديدة → مهمة منفصلة خارج هذه الخطة.)

### Batch هـ — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Batch و — التقارير

### Task 11: التقارير — `ReportsPicposScreen`
**Files:** Create `lib/presentation/reports_picpos/screens/reports_picpos_screen.dart` · Modify `app_main_screen.dart:732` (بدّل الـ `child` داخل `SecurityScreenGate`) · Test `test/widget/picpos_reports_test.dart`.
**الطبيعة:** الشاشة **مُطلِق تنقّل** (شبكة بطاقات فئات لـ ~٢٥ شاشة تقرير)، monolith ~1871 سطر. الفورك يعيد تأطير **شبكة المُطلِق فقط**؛ شاشات الوجهة تأخذ شكلها من الثيم.
**Reuse:** كلاسات البيانات `_ReportCategory`/`_ReportEntry`/`_ReportShortcut`/`_FlatItem` (تُنسخ) + الودجتس `_PopoverPanel`/`_HoverCard` (تُنسخ أو تُستبدل بـ `PicPosContentCard`) + مفضّلات `SharedPreferences` (`reports_favorites`/`reports_recent`). محاط بـ `PermissionGuard`.
**Copy-cost:** monolith — تُنسخ خرائط الفئات ومنطق البحث/المفضّلات؛ التنقّل لشاشات الوجهة كما هو.
**Header:** «التقارير» / «كل تقارير المبيعات والمخزون والمالية».
- [ ] نفس الوصفة. الاختيار داخل الـ gate: `Brand.isPicPos ? const ReportsPicposScreen() : const ReportsScreen()`.

### Task 12: سجل النشاط — `ActivityLogPicposScreen`
**Files:** Create `lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart` · Copy mixins `activity_log/activity_log_filters.dart` (`_ActivityLogFiltersMixin`) + `activity_log/activity_log_items.dart` (`_ActivityLogItemsMixin`) · Modify `app_main_screen.dart:785` · Test `test/widget/picpos_activity_log_test.dart`.
**Reuse:** `activityLogRepositoryProvider` · `branchRepositoryProvider` · `allUsersProvider` · `ActivityTimeline` · `FieldAuditHistoryWidget` · `EmptyStateWidget`. خرائط التسميات و`buildFiltersBar`/`buildLogItem`/`showLogDetails` من الـ mixins.
**Copy-cost:** الـ mixinان يُنسخان (مصيدة النسخ).
**Header:** «سجل النشاط» / «متابعة عمليات المستخدمين على النظام».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const ActivityLogPicposScreen() : const ActivityLogScreen()`.

### Batch و — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Batch ز — تشغيل

### Task 13: الأطراف — `PartiesPicposScreen`
**Files:** Create `lib/presentation/parties_picpos/screens/parties_picpos_screen.dart` · Modify `app_main_screen.dart:690-691` · Test `test/widget/picpos_parties_test.dart`.
**Reuse:** `allPartiesProvider` (داخل `Consumer` يلفّ الكارت) · `party_groups_controller` · الحوارات من `parties/party_dialogs.dart` (`showAddPartyDialog`/`showEditPartyDialog`/`showDeletePartyDialog`/`showExcelOptionsDialog`) · helpers `parties/party_helpers.dart` (`getPartyTypeLabel`/`Color`/`Icon`) · `ReceiptVoucherDialog`/`PaymentVoucherDialog` · التنقّل لـ `PartyStatementScreen`/`PartyGroupsScreen`. تجاهل `parties_screen.dart` الميت.
**Copy-cost:** State أحادي ~500 سطر — يُنسخ منطق القائمة/الفلاتر (`_buildFilters` بـ `SegmentedButton`, `_buildPartiesList`, `_buildPartyTile`) داخل الفورك؛ الـ helpers/dialogs تُعاد استخدامها كما هي.
**Header:** «العملاء والموردين» / «إدارة الأطراف والأرصدة».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const PartiesPicposScreen() : const UnifiedPartiesScreen()`.

### Task 14: المستخدمون — `UsersManagementPicposScreen`
**الاكتشاف:** `users` **ليست في الراوتر** — تُفتح عبر `Navigator.push` من `settings_screen.dart:582` و`reports_screen.dart:495`. فالاختيار بالعلامة يكون في **مواقع الـ push** (داخل فوركي الإعدادات/التقارير)، لا في `app_main_screen`.
**Files:** Create `lib/presentation/users_picpos/screens/users_management_picpos_screen.dart` · Modify مواقع الـ push في فورك الإعدادات (Task 16) وفورك التقارير (Task 11) · Test `test/widget/picpos_users_test.dart`.
**Reuse:** `allUsersProvider` · `allRolesProvider` · `allUserBranchNamesProvider` · `authProvider`/`authRepositoryProvider` · `currentUserPermissionsProvider` · `activityLoggerProvider` · `ClientWriteInterceptor` · `bootstrap_admin`. اللوحات `SecurityAlertsPanel` + الحوارات من `settings/widgets/` (`AddUserDialog`/`EditUserDialog`/`ResetPasswordDialog`/`SetPinDialog`/`BranchAccessDialog`/`WarehouseAccessDialog`) كما هي.
**Copy-cost:** monolith 869 سطر — يُنسخ منطق الـ State (`_updateUserRole`/`_toggleUserActive`/`_toggleUserLock`/`_deleteUser`/`_getRoleColor`/`_getRoleIcon` و`_buildUsersList` بـ `ExpansionTile`)؛ الحوارات تُعاد استخدامها.
**Header:** «المستخدمون» / «إدارة حسابات المستخدمين والصلاحيات».
- [ ] نفس الوصفة، لكن الاختيار عند مواقع `Navigator.push` (تُنفَّذ ضمن Task 11/16):
```dart
Navigator.push(context, MaterialPageRoute(builder: (_) =>
  Brand.isPicPos ? const UsersManagementPicposScreen() : const UsersManagementScreen()));
```

### Batch ز — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Batch ح — خاصة الطابع (تخطيط مخصّص)

### Task 15: لوحة القيادة — `DashboardPicposScreen`
**Files:**
- Create: `lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart`
- Create: `lib/presentation/dashboard_picpos/widgets/picpos_gauge.dart` (CustomPainter قوس + AnimationController — PicPos-only) · `picpos_donut.dart` (توزيع تفاعلي)
- Modify: `app_main_screen.dart:638-639` (بدّل الـ builder)
- Test: `test/widget/picpos_dashboard_gauge_test.dart` (اختبار `PicPosGauge`/`PicPosDonut` المعزول)

**يعيد استخدام منطق `dashboard_screen.dart` كاملاً (لا منطق جديد):**
- الفلتر `_DashboardFilterBar` → `dashboardFilterProvider` + مؤشر الفترة.
- ٤ كروت KPI: `dashboardKpiProvider` (`.revenue` مع tooltip المعادلة `revenue`+`outputVatNet`=`netRevenueInclVat`؛ `.invoiceCount`؛ `.netProfit`) و**`dashboardCashBalanceProvider`** (صناديق متعددة، عنوان متغيّر «كل الصناديق»/«صناديق الفرع» حسب `dashFilter.branchId`)، مع `PermissionGuard(treasuryBalanceView)` و`PermissionGuard(dashboardProfit)`.
- `lowStockProductsProvider` (بانر التنبيه).
- شبكة الإجراءات السريعة (`_QuickActionCard` مُعاد استخدامه) — إجراءات lite فقط.
- `GettingStartedChecklist` كما هي.
- **يُحذف** قسم «آخر المبيعات» (`todaySales` ListView).

**طبقة PicPos المضافة (عرض فقط):** `PicPosGauge`/`PicPosDonut` تقرأ قيم الـ providers بـ `ref.watch` وترسم منها:
- **هامش الربح** = `kpi.netProfit / kpi.revenue` — ✅ من نفس المزوّد، بلا منطق جديد.
- **نسبة التحصيل / توزيع المدفوعات / تحقيق الهدف** — **قبل الرسم:** تحقّق من مزوّد موجود يعطي المدفوع/طرق الدفع/الهدف. إن لم يوجد → **لا تخترع رقماً**: إمّا اشتقاق من صفوف مجلوبة أصلاً، أو **أجّل المؤشر**، أو أضِف مزوّد حساب صغير **ككوميت محرك منفصل + patch** (§٥.٦). وثّق القرار في رأس الملف.

**Copy-cost:** الشاشة تُعاد كتابة تخطيطها (تخطيط مخصّص) مع إعادة استخدام كل الـ providers/الحوارات/`_QuickActionCard`/`GettingStartedChecklist`. الجيوجات مكوّنات PicPos-only جديدة (لا تنتقل).
**Header:** «لوحة القيادة» (بالفلتر أعلى المحتوى).
- [ ] **الخطوة ١:** اقرأ `dashboard_screen.dart` كاملاً + `dashboardKpiProvider`/`dashboardCashBalanceProvider`.
- [ ] **الخطوة ٢:** اكتب اختبار `PicPosGauge` معزول (يبني بقيمة ٠..١ ويرسم — يفشل).
- [ ] **الخطوة ٣:** شغّل — FAIL.
- [ ] **الخطوة ٤:** نفّذ `PicPosGauge`/`PicPosDonut` (CustomPainter + animation)، ثم `DashboardPicposScreen` بإعادة استخدام كل منطق UralCash + ربط الجيوجات بالـ providers الحقيقية (هامش الربح مؤكّد؛ الباقي «اربط أو أجّل» بلا اختراع).
- [ ] **الخطوة ٥:** وصّل `app_main_screen.dart:638-639`: `builder: (_) => Brand.isPicPos ? DashboardPicposScreen(onNavigate: ...) : DashboardScreen(onNavigate: ...)`.
- [ ] **الخطوة ٦:** analyze صفر + الاختبار PASS.
- [ ] **الخطوة ٧:** commit.

### Task 16: الإعدادات — `SettingsPicposScreen`
**Files:** Create `lib/presentation/settings_picpos/screens/settings_picpos_screen.dart` · Copy الـ٦ `part`: `settings/general_settings_widgets.dart` · `scale_barcode_settings.dart` · `admin_home_settings.dart` · `cfd_settings_card.dart` · `network_mode_settings.dart` · `touch_input_settings.dart` · Modify `app_main_screen.dart:738-739` · Test `test/widget/picpos_settings_test.dart`.
**Reuse (كما هي):** كل الـ providers (`settingsRepositoryProvider`/`themeModeProvider`/`featureFlagsProvider`/…) وودجتس الأقسام المستوردة من `presentation/widgets/settings/*` (`BackupRestoreWidget`/`CompanyInfoWidget`/`HardwareSettingsWidget`/`PosSettingsWidget`/`UserManagementWidget`/…) والحوارات ودوال الفتح (`showCompanyInfoDialog`/…) كما هي. **مواقع `Navigator.push` لـ `UsersManagementScreen` (سطر 582) تأخذ فرع العلامة** لفتح فورك المستخدمين (Task 14).
**Copy-cost:** God-file 1406 سطر مقسّم بـ ٦ `part` — تُنسخ الستة (مصيدة النسخ)، ويُعاد تأطير الأقسام في `PicPosContentCard`ات بدل `_buildSettingsCard`.
**Header:** «الإعدادات» / «تهيئة النظام والأجهزة والصلاحيات».
- [ ] نفس الوصفة. الاختيار: `Brand.isPicPos ? const SettingsPicposScreen() : const SettingsScreen()`. وربط push المستخدمين بالعلامة (Task 14).

### Batch ح — بوابة المراجعة
- [ ] analyze صفر · اختبارات العلامتين · جولة كاملة `--concurrency=1`.

---

## Task 17: التحقق النهائي + التوثيق

- [ ] **الخطوة ١:** `flutter analyze lib` = No issues found!
- [ ] **الخطوة ٢:** `flutter test --concurrency=1` = صفر فشل (تسجيل العدد).
- [ ] **الخطوة ٣:** اختبارات الهوية على العلامتين — uralcash 12 · picpos 7 — خضرا، و`brand_isolation_test` يؤكّد **lite UralCash = ١٩ شاشة** (لم تتأثر بضمّ الميزان).
- [ ] **الخطوة ٤:** البناء:
```powershell
$env:PATH = "D:\Cash\develop\flutter\bin;$env:PATH"
.\build_picpos.bat   # Expected: SUCCESS
```
- [ ] **الخطوة ٥:** فحص binary بالترميزين (§٣.٤ + §٥.٥): ٤ ملاح · UTF-16=٠ · صفر لـ `monexia`/`cashier_market`/`avalon`/`uraljo`.
- [ ] **الخطوة ٦:** حدّث `HANDOFF.md` (قسم جلسة جديد §٥.١٠) بالشاشات المنفَّذة والحالة المتحقَّقة، وحدّث البرومت المدمج.
- [ ] **الخطوة ٧:** commit التوثيق.

---

## Self-Review (مطابقة الخطة للسبيك)

- **تغطية:** كل شاشات §٤ في السبيك لها مهمة (أ:1-3 · ب:4 · ج:5-7 · د:8 · هـ:9-10 · و:11-12 · ز:13-14 · ح:15-16). `shiftClose` (Task 10) مُعلَّم قرار (لا شاشة حالية).
- **مصادر حقيقية:** الداشبورد (Task 15) يربط الجيوجات بـ `dashboardKpiProvider`/`dashboardCashBalanceProvider` الموثّقة (§١١ سبيك)؛ بند «لا اختراع أرقام» صريح.
- **عدم لمس UralCash:** كل مهمة = ملف فورك جديد + سطر اختيار `Brand.isPicPos` (فرع `else` = الأصل). الميزان بفرع lite بالعلامة. الملاح/`Brand`/`AppFlavor` خارج النطاق.
- **مصيدة النسخ:** موسومة في كل مهمة بها نسخ `part`/mixin (1,2,3,8,12,16) وmonolith (4,5,6,13,14).
- **مخاطر مفتوحة (من السبيك §١٢):** مصادر مقاييس الجيوجات (Task 15)، بوابة ميزة الميزان في lite (Task 8)، وقرار `shiftClose` (Task 10) — كلها مُعلَّمة صراحةً.

# خطة تنفيذ إعادة تصميم شاشات PicPos

> **للعامل الوكيل (agentic worker):** المهارة الفرعية المطلوبة: استخدم
> `superpowers:subagent-driven-development` (موصى به) أو `superpowers:executing-plans`
> لتنفيذ الخطة مهمة-بمهمة. الخطوات بصيغة checkbox (`- [ ]`) للتتبّع.

**الهدف:** إعادة تصميم ٣ شاشات (الأصناف، المخزون، المشتريات) بهوية PicPos عبر شاشات
منفصلة يختارها `Brand.isPicPos`، تعيد استخدام نفس المنطق، مع طقم تخطيط `picpos_shell` مشترك.

**المعمار:** شاشة PicPos لكل واحدة في مجلد `*_picpos/`، تُختار في `app_main_screen.dart`
بـ `Brand.isPicPos ? PicPosScreen : UralScreen` (نفس سابقة الـ POS). الشاشة الجديدة
**تستورد وتنادي** نفس الـ controllers/services/tables/dialogs؛ الجديد = التخطيط والهوية فقط.
المكوّنات المشتركة في `picpos_shell/` هي PicPos-only (بلا فرع UralCash) → صفر مخاطرة على UralCash.

**التقنيات:** Flutter · Riverpod 3 · drift (SQLite) · phosphor_flutter · google_fonts · Cairo.
الحزمة الداخلية اسمها `picpos_erp` (اسم مقبول، لا يُغيَّر).

## قيود عامة (تنطبق على كل مهمة)

- **UralCash لا يُلمس:** ممنوع تعديل أي ملف يستعمله بناء UralCash بصرياً. التعديل الوحيد
  المسموح على ملف مشترك = سطر الاختيار بالعلامة في `app_main_screen.dart` (فرع `else` =
  سلوك UralCash الحالي حرف بحرف).
- **الملاح التشفيرية الأربعة** (`api_auth_middleware.dart`، `api_session_token.dart`،
  `invoice_integrity_service.dart`، `license_service.dart`) لا تُلمس.
- **`Brand` و`AppColors`:** كل قيمة تفضل `const`. ممنوع تحويل أي لون لـ getter.
- **`AppFlavor`:** ممنوع إضافة قيمة جديدة.
- **قاعدة الـ patch:** أي إصلاح باج **منطقي** في محرك/خدمة/مستودع مشترك = كوميت منفصل +
  patch في `patches-for-uralcash/` (صفر إشارات `Brand.` وصفر ملفات PicPos في الـ diff).
  تغييرات التخطيط/الهوية تفضل هنا ولا تنتقل. **الكود المنسوخ في fork PicPos ليس مشتركاً**؛
  لكن لو أصلحت باج منطقي فيه، افحص الأصل في UralCash (تكلفة النسخ الموثّقة).
- **العربي في الملفات:** استخدم أداة Edit/Write (PowerShell بيخرّب UTF-8).
- **الأساس الأخضر (متحقَّق منه):** `flutter test` = `+3262 ~12 · 0 فشل` بقيود FK مشغّلة.
- **`flutter` مش على PATH:** `D:\Cash\develop\flutter\bin` — أضِفه لكل أمر flutter.
- **الترتيب مقصود:** الأصناف (أرخص fork) → المخزون → المشتريات (أثقل fork). نراجع بعد كل واحدة.

---

## Task 1: طقم تخطيط PicPos (`picpos_shell/`)

مكوّنات PicPos-only مشتركة بين الشاشات الثلاث (وأي شاشة قادمة). كلها `StatelessWidget`
بسيطة تقرأ الألوان من `AppColors` والتايبوغرافي من `Theme.of(context).textTheme`.

**Files:**
- Create: `lib/presentation/picpos_shell/picpos_page_header.dart`
- Create: `lib/presentation/picpos_shell/picpos_content_card.dart`
- Create: `lib/presentation/picpos_shell/picpos_toolbar.dart`
- Create: `lib/presentation/picpos_shell/picpos_screen_scaffold.dart`
- Test: `test/widget/picpos_shell_test.dart`

**Interfaces (Produces):**
- `PicPosPageHeader({required String title, String? subtitle, IconData? icon, Widget? search, List<Widget> actions})`
- `PicPosContentCard({required Widget child, EdgeInsetsGeometry? padding})`
- `PicPosToolbar({required List<Widget> children, double spacing})`
- `PicPosScreenScaffold({required String title, String? subtitle, IconData? icon, Widget? headerSearch, List<Widget> headerActions, Widget? subHeader, Widget? toolbar, required Widget body, EdgeInsetsGeometry bodyPadding})`

- [ ] **الخطوة ١: اكتب اختبار الطقم (فاشل)**

`test/widget/picpos_shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_page_header.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_content_card.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_screen_scaffold.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: PicPosTheme.lightTheme, home: child);

  group('PicPosPageHeader', () {
    testWidgets('يعرض العنوان والوصف والأزرار', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosPageHeader(
          title: 'الأصناف',
          subtitle: 'إدارة المنتجات والتسعير',
          icon: PhosphorIconsBold.package,
          actions: [Text('زر')],
        ),
      )));
      expect(find.text('الأصناف'), findsOneWidget);
      expect(find.text('إدارة المنتجات والتسعير'), findsOneWidget);
      expect(find.text('زر'), findsOneWidget);
    });

    testWidgets('يرسم شريحة لونية سفلية بلون العلامة', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosPageHeader(title: 'ت'),
      )));
      // الحاوية الجذر فيها Border سفلي بلون AppColors.primary.
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PicPosPageHeader),
          matching: find.byType(Container),
        ).first,
      );
      final deco = container.decoration as BoxDecoration;
      expect(deco.border!.bottom.color, AppColors.primary);
      expect(deco.border!.bottom.width, 2.5);
    });
  });

  group('PicPosContentCard', () {
    testWidgets('مسطّح (elevation صفر) بحد شعري', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(
        body: PicPosContentCard(child: Text('محتوى')),
      )));
      expect(find.text('محتوى'), findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PicPosContentCard),
          matching: find.byType(Container),
        ).first,
      );
      final deco = container.decoration as BoxDecoration;
      expect(deco.border, isA<Border>());
      expect(deco.boxShadow, anyOf(isNull, isEmpty));
    });
  });

  group('PicPosScreenScaffold', () {
    testWidgets('يركّب الهيدر والجسم في RTL', (tester) async {
      await tester.pumpWidget(wrap(const PicPosScreenScaffold(
        title: 'المخزون',
        body: Text('الجسم'),
      )));
      expect(find.text('المخزون'), findsOneWidget);
      expect(find.text('الجسم'), findsOneWidget);
      final dir = tester.widget<Directionality>(
        find.descendant(
          of: find.byType(PicPosScreenScaffold),
          matching: find.byType(Directionality),
        ).first,
      );
      expect(dir.textDirection, TextDirection.rtl);
    });
  });
}
```

- [ ] **الخطوة ٢: شغّل الاختبار وتأكد إنه فاشل**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/picpos_shell_test.dart`
Expected: FAIL — الملفات غير موجودة (`Target of URI doesn't exist`).

- [ ] **الخطوة ٣: نفّذ `picpos_page_header.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// هيدر شاشات PicPos: خلفية فاتحة، عنوان داكن، وخط لوني سفلي 2.5px بلون العلامة
/// (فلسفة PicPosTheme: «شريط علوي فاتح بشريحة لونية سفلية»). التايبوغرافي من الثيم.
class PicPosPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// حقل بحث اختياري يوضع على يسار صف العنوان (بعرض محدود).
  final Widget? search;

  /// أزرار الإجراءات على أول الصف (يمين في RTL).
  final List<Widget> actions;

  const PicPosPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.search,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.primary, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.headlineSmall),
              if (subtitle != null)
                Text(subtitle!, style: text.bodySmall),
            ],
          ),
          const Spacer(),
          if (search != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: search!,
            ),
            const SizedBox(width: 12),
          ],
          ...actions,
        ],
      ),
    );
  }
}
```

- [ ] **الخطوة ٤: نفّذ `picpos_content_card.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// كارت محتوى مسطّح بحد شعري وزوايا 14 — بديل الكروت المرفوعة (`elevation:2`)
/// التي تكتبها الشاشات inline وتتجاوز بها الثيم. بلا ظلال عن قصد.
class PicPosContentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const PicPosContentCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
```

- [ ] **الخطوة ٥: نفّذ `picpos_toolbar.dart`**

```dart
import 'package:flutter/material.dart';

/// صف أدوات PicPos: يلفّ الأزرار/الشرايح الممرَّرة مع تباعد موحّد، ويلتفّ
/// (wrap) على الشاشات الضيّقة بدل ما يفيض أفقياً.
class PicPosToolbar extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const PicPosToolbar({super.key, required this.children, this.spacing = 8});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
```

- [ ] **الخطوة ٦: نفّذ `picpos_screen_scaffold.dart`**

```dart
import 'package:flutter/material.dart';
import 'picpos_page_header.dart';

/// إطار شاشة PicPos: RTL + Scaffold بخلفية canvas + هيدر أعلى + محتوى.
/// slots اختيارية: subHeader (بطاقات ملخص/تبويبات)، toolbar (صف أزرار).
class PicPosScreenScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? headerSearch;
  final List<Widget> headerActions;
  final Widget? subHeader;
  final Widget? toolbar;
  final Widget body;
  final EdgeInsetsGeometry bodyPadding;

  const PicPosScreenScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.headerSearch,
    this.headerActions = const [],
    this.subHeader,
    this.toolbar,
    required this.body,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PicPosPageHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              search: headerSearch,
              actions: headerActions,
            ),
            if (subHeader != null) subHeader!,
            if (toolbar != null) toolbar!,
            Expanded(child: Padding(padding: bodyPadding, child: body)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **الخطوة ٧: شغّل الاختبار وتأكد إنه ناجح**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/picpos_shell_test.dart`
Expected: PASS (كل المجموعات خضرا).

- [ ] **الخطوة ٨: تحليل**

Run: `D:\Cash\develop\flutter\bin\flutter analyze lib/presentation/picpos_shell test/widget/picpos_shell_test.dart`
Expected: `No issues found!`

- [ ] **الخطوة ٩: كوميت**

```bash
git add lib/presentation/picpos_shell test/widget/picpos_shell_test.dart
git commit -m "feat(picpos): طقم تخطيط picpos_shell (هيدر/كارت/شريط/سكافولد)"
```

---

## Task 2: شاشة الأصناف — `ProductsPicposScreen`

fork نظيف: الشاشة الأصلية تكوين رفيع، وكل منطق الأزرار في خدمات عامة. نعيد استخدام
`ProductsTable` و`ProductsBulkActionBar` و`productsControllerProvider` كما هي، ونعيد توصيل
أزرار الهيدر لنفس الخدمات. **حوار التصنيفات في `product_search_header.dart` خاص (`_`)**،
فننسخ منتقي تصنيفات صغيراً داخل fork الأصناف (قائمة بحث بسيطة، ليست منطق أعمال).

**Files:**
- Create: `lib/presentation/products_picpos/screens/products_picpos_screen.dart`
- Create: `lib/presentation/products_picpos/widgets/picpos_category_picker.dart`
- Modify: `lib/app_main_screen.dart` (سطر اختيار الأصناف)
- Test: `test/widget/products_picpos_screen_test.dart`

**Interfaces (Consumes):** `PicPosScreenScaffold`, `PicPosContentCard`, `PicPosToolbar` (Task 1).
**Produces:** `ProductsPicposScreen({Key? key})` — `const`.

- [ ] **الخطوة ١: اكتب اختبار الشاشة (فاشل)**

`test/widget/products_picpos_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/products_picpos/screens/products_picpos_screen.dart';

void main() {
  testWidgets('شاشة أصناف PicPos تركّب وتعرض هيدر العلامة', (tester) async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: PicPosTheme.lightTheme,
          home: const ProductsPicposScreen(),
        ),
      ),
    );
    await tester.pump(); // إطار واحد؛ الهيدر ثابت ويظهر قبل تحميل الداتا
    expect(find.text('الأصناف'), findsOneWidget);
  });
}
```
> **ملاحظة على مسار `database.dart`:** تحقق من مسار استيراد `AppDatabase` الفعلي
> (`grep -rn "class AppDatabase" lib/data/database`) واستخدمه. المتوقّع
> `package:picpos_erp/data/database/database.dart`.

- [ ] **الخطوة ٢: شغّل الاختبار وتأكد إنه فاشل**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/products_picpos_screen_test.dart`
Expected: FAIL — `ProductsPicposScreen` غير موجودة.

- [ ] **الخطوة ٣: نفّذ منتقي التصنيفات `picpos_category_picker.dart`**

انسخ حوار البحث عن تصنيف (منطق عرض بسيط) واجعله عاماً:
```dart
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart' show Category;

/// منتقي تصنيف قابل للبحث — نسخة PicPos العامة من الحوار الخاص في
/// product_search_header.dart. يرجّع Category المختار، أو sentinel «الكل».
class PicPosCategoryPicker {
  /// يرجّع (true, null) لو اختار «كل التصنيفات»، (true, cat) لتصنيف، null لو ألغى.
  static Future<(bool, Category?)?> show(
    BuildContext context, {
    required List<Category> categories,
    required int? selectedId,
  }) {
    return showDialog<(bool, Category?)>(
      context: context,
      builder: (_) => _PicPosCategoryDialog(
        categories: categories,
        selectedId: selectedId,
      ),
    );
  }
}

class _PicPosCategoryDialog extends StatefulWidget {
  final List<Category> categories;
  final int? selectedId;
  const _PicPosCategoryDialog({required this.categories, required this.selectedId});
  @override
  State<_PicPosCategoryDialog> createState() => _PicPosCategoryDialogState();
}

class _PicPosCategoryDialogState extends State<_PicPosCategoryDialog> {
  final _ctrl = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.categories
        : widget.categories.where((c) => c.name.toLowerCase().contains(q)).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختر التصنيف'),
        content: SizedBox(
          width: 420,
          height: 500,
          child: Column(
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ابحث عن تصنيف...',
                  prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(PhosphorIconsBold.listBullets),
                        title: const Text('كل التصنيفات'),
                        selected: widget.selectedId == null,
                        onTap: () => Navigator.pop(context, (true, null)),
                      );
                    }
                    final cat = filtered[i - 1];
                    return ListTile(
                      title: Text(cat.name),
                      selected: cat.id == widget.selectedId,
                      trailing: cat.id == widget.selectedId
                          ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
                          : null,
                      onTap: () => Navigator.pop(context, (true, cat)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
```
> تحقق من مسار تصدير `Category` (المتوقّع عبر `data/providers/providers.dart` أو
> `data/database/database.dart`) بـ `grep -rn "class Category" lib/data`.

- [ ] **الخطوة ٤: نفّذ `products_picpos_screen.dart`**

الشاشة تعيد استخدام: `productsControllerProvider` (+ `.notifier.setSearchQuery`,
`.loadNextPage`)، `ProductsTable(scrollController:)`، `ProductsBulkActionBar()`،
`AddProductDialog.show`، `excelServiceProvider` (`exportProductsTemplate`,
`importProducts`, `exportScaleItemsTemplate`, `importScaleItems`)، `LabelScaleService`،
`UnitsManagementScreen`، `visibleCategoriesProvider`، `PermissionGuard`، `AppToast`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/widgets/app_shortcuts.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/excel_service.dart';
import '../../products/providers/products_controller.dart';
import '../../screens/units_management_screen.dart';
import '../../screens/products/widgets/products_table.dart';
import '../../screens/products/widgets/products_bulk_action_bar.dart';
import '../../widgets/dialogs/add_product_dialog.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_toolbar.dart';
import '../widgets/picpos_category_picker.dart';

/// شاشة الأصناف بهوية PicPos. تُختار بالعلامة في app_main_screen. لا تعيد بناء أي
/// منطق: البحث/الباجينيشن عبر productsControllerProvider، والجدول والإجراءات الجماعية
/// نفس widgets UralCash، وأزرار الهيدر تنادي نفس الخدمات.
class ProductsPicposScreen extends ConsumerStatefulWidget {
  const ProductsPicposScreen({super.key});
  @override
  ConsumerState<ProductsPicposScreen> createState() => _ProductsPicposScreenState();
}

class _ProductsPicposScreenState extends ConsumerState<ProductsPicposScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _loadInFlight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // نفس شرط الباجينيشن في شاشة UralCash (products_screen.dart:92) — نداء نفس الـ notifier.
  void _onScroll() {
    if (_loadInFlight) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    _loadInFlight = true;
    Future(() async {
      try {
        await ref.read(productsControllerProvider.notifier).loadNextPage();
      } finally {
        _loadInFlight = false;
      }
    });
  }

  Future<void> _addProduct() async {
    final result = await AddProductDialog.show(context);
    if (result != null) {
      await ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
    }
  }

  Future<void> _exportProducts() async {
    final path = await ref.read(excelServiceProvider).exportProductsTemplate();
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير النموذج: $path', type: ToastType.success);
    }
  }

  Future<void> _importProducts() async {
    final result = await ref.read(excelServiceProvider).importProducts();
    if (!mounted) return;
    AppToast.show(context, result.message,
        type: result.success ? ToastType.success : ToastType.error);
    if (result.success) {
      ref.invalidate(allProductsProvider);
      ref.invalidate(posGridProductsProvider);
      ref.invalidate(visibleCategoriesProvider);
      ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
    }
  }

  Future<void> _pickCategory() async {
    final cats = ref.read(visibleCategoriesProvider).value ?? const [];
    final selectedId = ref.read(productsControllerProvider).selectedCategoryId;
    final picked = await PicPosCategoryPicker.show(context,
        categories: cats, selectedId: selectedId);
    if (picked != null && mounted) {
      ref.read(productsControllerProvider.notifier).setCategoryFilter(picked.$2?.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategoryId =
        ref.watch(productsControllerProvider.select((s) => s.selectedCategoryId));
    final cats = ref.watch(visibleCategoriesProvider).value ?? const [];
    final categoryLabel = selectedCategoryId == null
        ? 'كل التصنيفات'
        : cats
            .where((c) => c.id == selectedCategoryId)
            .map((c) => c.name)
            .fold<String?>(null, (_, n) => n) ?? 'تصنيف';

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: _addProduct,
      child: PicPosScreenScaffold(
        title: 'الأصناف',
        subtitle: 'إدارة المنتجات والتسعير',
        icon: PhosphorIconsBold.package,
        headerSearch: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (v) =>
              ref.read(productsControllerProvider.notifier).setSearchQuery(v),
          decoration: const InputDecoration(
            hintText: 'البحث عن صنف...',
            prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          ),
        ),
        toolbar: PicPosToolbar(children: [
          OutlinedButton.icon(
            onPressed: _pickCategory,
            icon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
            label: Text(categoryLabel),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsExport,
            allowManagerOverride: true,
            actionName: 'تصدير الأصناف',
            child: OutlinedButton.icon(
              onPressed: _exportProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
              label: const Text('تصدير'),
            ),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsImport,
            allowManagerOverride: true,
            actionName: 'استيراد أصناف',
            child: OutlinedButton.icon(
              onPressed: _importProducts,
              icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
              label: const Text('استيراد'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UnitsManagementScreen())),
            icon: const Icon(PhosphorIconsBold.ruler, size: 18),
            label: const Text('وحدات القياس'),
          ),
          PermissionGuard(
            permission: PermissionCodes.productsAdd,
            allowManagerOverride: true,
            actionName: 'إضافة صنف جديد',
            child: ElevatedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label: const Text('إضافة صنف'),
            ),
          ),
        ]),
        body: Column(
          children: [
            Expanded(
              child: PicPosContentCard(
                child: ProductsTable(scrollController: _scrollController),
              ),
            ),
            const ProductsBulkActionBar(),
          ],
        ),
      ),
    );
  }
}
```
> **تحقق من المسارات والأسماء عند التنفيذ** (قد تختلف بادئات import):
> `AppShortcuts`, `PermissionCodes.productsExport/productsImport/productsAdd`,
> `excelServiceProvider`, `AddProductDialog.show`, `productsControllerProvider.notifier`
> (`setSearchQuery`, `setCategoryFilter`, `loadNextPage(isRefresh:)`),
> `allProductsProvider`, `posGridProductsProvider`, `visibleCategoriesProvider`,
> `UnitsManagementScreen`. كلها موجودة في `product_search_header.dart` و`products_screen.dart`
> — انسخ بادئات الاستيراد الصحيحة منهما. **ملاحظة الميزان:** لو عايز زر «الميزان ▾» أضِفه
> بنفس منطق `_buildScaleActions` في product_search_header.dart (نفس `excelService`/`LabelScaleService`).

- [ ] **الخطوة ٥: وصّل الاختيار في `app_main_screen.dart`**

أضِف الاستيراد أعلى الملف:
```dart
import 'presentation/products_picpos/screens/products_picpos_screen.dart';
```
عدّل بانِي شاشة الأصناف (حالياً `builder: (_) => const ProductsScreen()`):
```dart
builder: (_) => Brand.isPicPos
    ? const ProductsPicposScreen()
    : const ProductsScreen(),
```
(`Brand` مستورد بالفعل في الملف.)

- [ ] **الخطوة ٦: شغّل اختبار الشاشة وتأكد إنه ناجح**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/products_picpos_screen_test.dart`
Expected: PASS.

- [ ] **الخطوة ٧: تحليل + اختبارات الهوية**

```bash
D:\Cash\develop\flutter\bin\flutter analyze lib test
D:\Cash\develop\flutter\bin\flutter test test/unit/brand_isolation_test.dart
D:\Cash\develop\flutter\bin\flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart
```
Expected: `No issues found!` + الاختبارين خضرا.

- [ ] **الخطوة ٨: كوميت**

```bash
git add lib/presentation/products_picpos lib/app_main_screen.dart test/widget/products_picpos_screen_test.dart
git commit -m "feat(picpos): شاشة الأصناف بهوية PicPos (fork يعيد استخدام منطق UralCash)"
```

---

## Task 3: شاشة المخزون — `InventoryPicposScreen`

fork متوسط: يعيد استخدام `InventorySummaryRow`, `StockBalancesTable`, `StockMovementsTable`,
`inventoryNotifierProvider` والـ providers. **يُنقَل تنظيم الصفحات (paging) من `State` كما هو**
لأنه ينادي نفس `productRepositoryProvider.getInventoryProductsPage` — منطق تنظيم واجهة، ليس
منطق أعمال. الهيدر يستبدل `AppBar`، والتبويبات بهوية PicPos.

**Files:**
- Create: `lib/presentation/inventory_picpos/screens/inventory_picpos_screen.dart`
- Modify: `lib/app_main_screen.dart` (سطر اختيار المخزون داخل `SecurityScreenGate`)
- Test: `test/widget/inventory_picpos_screen_test.dart`

**Interfaces (Consumes):** `PicPosScreenScaffold`, `PicPosContentCard` (Task 1).
**Produces:** `InventoryPicposScreen({Key? key})` — `const`.

- [ ] **الخطوة ١: اكتب اختبار الشاشة (فاشل)**

`test/widget/inventory_picpos_screen_test.dart` — نفس بنية اختبار الأصناف، مع:
```dart
import 'package:picpos_erp/presentation/inventory_picpos/screens/inventory_picpos_screen.dart';
// ... نفس imports قاعدة الاختبار (AppDatabase, databaseProvider, PicPosTheme, ProviderScope)
void main() {
  testWidgets('شاشة مخزون PicPos تركّب وتعرض هيدر العلامة', (tester) async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: PicPosTheme.lightTheme,
        home: const InventoryPicposScreen(),
      ),
    ));
    await tester.pump();
    expect(find.text('المخزون'), findsOneWidget);
  });
}
```

- [ ] **الخطوة ٢: شغّل الاختبار وتأكد إنه فاشل**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/inventory_picpos_screen_test.dart`
Expected: FAIL — `InventoryPicposScreen` غير موجودة.

- [ ] **الخطوة ٣: نفّذ `inventory_picpos_screen.dart`**

ابنِ `ConsumerStatefulWidget` بـ `SingleTickerProviderStateMixin` و`TabController(length: 2)`.
**انسخ حرفياً من `inventory_screen.dart` هذه الأعضاء (تنظيم واجهة ينادي نفس المستودع/الـ notifier):**
- حقول الحالة: `_pagedItems`, `_pageLoading`, `_pageHasMore`, `_pagedKey`,
  `_searchController`, `_adjQtyController`, `_adjNotesController`, `_movementSearchController`,
  `_selectedMovementType` (السطور 30–57).
- الدوال: `_argsKey` (59)، `_resolveRestrictIds` (62)، `_loadInventoryPage` (72)،
  `_buildBalancesTab` (301)، `_buildMovementsTab` (406..)، `_showAdjustmentDialog` (المستدعاة
  في `onAdjustStock`)، وأي دالة تسوية أخرى تستدعيها هذه.
- الثوابت/الأنواع المستوردة: `InventoryListArgs`, `kInventoryPageSize`, `warehouseStockMapProvider`,
  `categoryNameMapProvider`, `baseUnitNamesProvider`, `visibleCategoriesProvider`,
  `allWarehousesProvider`, `allProductsProvider`, `BarcodePrintDialog`.

**استبدل `build()` فقط** بالتخطيط التالي (هيدر + بحث + فلاتر + تبويبات + كارت مسطّح). لاحظ إن
`_buildBalancesTab` يعيد `Card(elevation:2, ...)` — استبدل ذلك الغلاف بـ `PicPosContentCard`
داخل النسخة المنسوخة (تغيير تأطير فقط، لا يمسّ محتوى الجدول):

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(inventoryNotifierProvider);
  final categoriesAsync = ref.watch(visibleCategoriesProvider);
  final unitMapAsync = ref.watch(baseUnitNamesProvider);

  return PicPosScreenScaffold(
    title: 'المخزون',
    icon: PhosphorIconsBold.warehouse,
    subHeader: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          const InventorySummaryRow(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildSearchField(context, ref)),
            const SizedBox(width: 12),
            _buildWarehouseFilter(context, ref),
            const SizedBox(width: 12),
            _buildCategoryFilter(context, ref),
            const SizedBox(width: 12),
            _buildLowStockToggle(ref, state),
          ]),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'أرصدة المستودع', icon: Icon(PhosphorIconsBold.package)),
              Tab(text: 'حركة الأصناف', icon: Icon(PhosphorIconsBold.arrowsLeftRight)),
            ],
          ),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabController,
      children: [
        _buildBalancesTab(categoriesAsync, unitMapAsync),
        _buildMovementsTab(),
      ],
    ),
  );
}
```
**انسخ أيضاً حرفياً** الدوال المساعدة `_buildSearchField`, `_buildWarehouseFilter`,
`_buildCategoryFilter`, `_buildLowStockToggle` (السطور 202–298) — تنادي نفس الـ notifier.
داخل `_buildBalancesTab` المنسوخة: بدّل `Card(elevation: 2, shape: ...)` بـ
`PicPosContentCard(child: Column(...))`. **لا تغيّر شيئاً في محتوى الجدول أو منطق الصفحات.**

> **مصيدة `TabController`:** لازم `dispose` له في `dispose()` (انسخ dispose الأصلي 119–130).
> **مصيدة النسخ:** لو أصلحت باج منطقي في المنطق المنسوخ (مثلاً في `_loadInventoryPage`)،
> افحص الأصل في `inventory_screen.dart` — نفس الباج فيه، ويُصلَّح بكوميت منفصل + patch.

- [ ] **الخطوة ٤: وصّل الاختيار في `app_main_screen.dart`**

استيراد:
```dart
import 'presentation/inventory_picpos/screens/inventory_picpos_screen.dart';
```
عدّل `child` داخل `SecurityScreenGate` لشاشة المخزون:
```dart
child: Brand.isPicPos ? const InventoryPicposScreen() : const InventoryScreen(),
```

- [ ] **الخطوة ٥: شغّل اختبار الشاشة وتأكد إنه ناجح**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/inventory_picpos_screen_test.dart`
Expected: PASS.

- [ ] **الخطوة ٦: تحليل + اختبارات الهوية**

```bash
D:\Cash\develop\flutter\bin\flutter analyze lib test
D:\Cash\develop\flutter\bin\flutter test test/unit/brand_isolation_test.dart
D:\Cash\develop\flutter\bin\flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart
```
Expected: `No issues found!` + خضرا.

- [ ] **الخطوة ٧: كوميت**

```bash
git add lib/presentation/inventory_picpos lib/app_main_screen.dart test/widget/inventory_picpos_screen_test.dart
git commit -m "feat(picpos): شاشة المخزون بهوية PicPos (fork يعيد استخدام منطق UralCash)"
```

---

## Task 4: شاشة المشتريات — `PurchasesPicposScreen` (الأثقل)

fork ثقيل: منطق الحفظ (`_handleSavePurchaseSimple` + `createNewInvoice` + `editInvoice`)
في mixin **خاص** (`part of`) في UralCash → **يُنسَخ** في fork PicPos كملف `part`، بنفس نمط
`picpos_pos_operations.dart` (تكلفة نسخ موثّقة ومقبولة). ينادي نفس
`purchasesRepositoryProvider.createInvoice/updateInvoice`، نفس `PurchaseInvoiceForm`، نفس
`AppDataTable`/`AppKpiCard`. الهيدر يستبدل `AppBar`.

**Files:**
- Create: `lib/presentation/purchases_picpos/screens/purchases_picpos_screen.dart`
- Create: `lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart` (نسخة الـ mixin)
- Modify: `lib/app_main_screen.dart` (سطر اختيار المشتريات داخل `SecurityScreenGate`)
- Test: `test/widget/purchases_picpos_screen_test.dart`

**Interfaces (Consumes):** `PicPosScreenScaffold`, `PicPosContentCard` (Task 1).
**Produces:** `PurchasesPicposScreen({Key? key})` — `const`.

- [ ] **الخطوة ١: اكتب اختبار الشاشة (فاشل)**

`test/widget/purchases_picpos_screen_test.dart` — نفس بنية اختبار الأصناف، مع:
```dart
import 'package:picpos_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
// ... نفس imports قاعدة الاختبار
void main() {
  testWidgets('شاشة مشتريات PicPos تركّب وتعرض هيدر العلامة', (tester) async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: PicPosTheme.lightTheme,
        home: const PurchasesPicposScreen(),
      ),
    ));
    await tester.pump();
    expect(find.text('المشتريات'), findsOneWidget);
  });
}
```

- [ ] **الخطوة ٢: شغّل الاختبار وتأكد إنه فاشل**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/purchases_picpos_screen_test.dart`
Expected: FAIL — `PurchasesPicposScreen` غير موجودة.

- [ ] **الخطوة ٣: انسخ mixin الـ CRUD في `purchases_picpos_crud.dart`**

انسخ محتوى `lib/presentation/screens/purchase_invoices/purchase_invoice_crud.dart` بالكامل
(الدوال `createNewInvoice`, `editInvoice`, `_handleSavePurchaseSimple` — السطور 3–229) مع
تغييرين فقط:
- السطر الأول: `part of 'purchases_picpos_screen.dart';`
- اسم الـ mixin وقيد `on`: `mixin _PurchasesPicposCrud on ConsumerState<PurchasesPicposScreen>`.

**لا تغيّر جسم الدوال** — تنادي نفس `purchasesRepositoryProvider`, `printingServiceProvider`,
`activityLogRepositoryProvider`, `PurchaseInvoiceForm`, `PurchaseItemParams`,
`CreatePurchaseInvoiceParams`, `UpdatePurchaseInvoiceParams`.

> **مصيدة النسخ (موثّقة):** أي باج منطقي تصلحه هنا لاحقاً افحص أصله في
> `purchase_invoice_crud.dart` — يُصلَّح بكوميت منفصل + patch لـ UralCash.

- [ ] **الخطوة ٤: نفّذ `purchases_picpos_screen.dart`**

`ConsumerStatefulWidget` بـ `with _PurchasesPicposCrud`. يعيد استخدام
`purchaseInvoicesControllerProvider` (+ `.notifier` methods: `updateSearchQuery`,
`updateBranchFilter`, `updateWarehouseFilter`, `updateCostCenterFilter`, `updateDateRange`,
`updateStatusFilter`, `toggleAllSelection`)، و`AppKpiCard`, `AppDataTable`, `AppStateView`,
`SyncPendingBanner`, `PurchaseOrdersScreen`, `excelServiceProvider`
(`exportPurchaseInvoicesTemplate`, `importPurchaseInvoices`).

**انسخ من `purchase_invoices_screen.dart`:** بطاقات KPI (السطور 231–280)، صف الفلاتر
(283–459)، جسم الجدول `AppDataTable` (485..) — كلها منطق عرض ينادي نفس الـ controller.
**استبدل غلاف `Scaffold + AppBar`** بـ `PicPosScreenScaffold`:

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(purchaseInvoicesControllerProvider);
  final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
  return AppShortcuts(
    searchFocusNode: _searchFocusNode,
    searchController: _searchController,
    onNew: createNewInvoice, // من الـ mixin المنسوخ
    child: PicPosScreenScaffold(
      title: 'المشتريات',
      icon: PhosphorIconsBold.receipt,
      headerActions: [
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(PhosphorIconsBold.arrowClockwise),
          onPressed: () => ref.invalidate(purchaseInvoicesControllerProvider),
        ),
        _buildExcelMenu(context, ref),      // انسخ منطق PopupMenuButton (144–188)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PurchaseOrdersScreen())),
          icon: const Icon(PhosphorIconsBold.clipboardText, size: 16),
          label: const Text('طلبات الشراء'),
        ),
        ElevatedButton.icon(
          onPressed: createNewInvoice,
          icon: const Icon(PhosphorIconsBold.plus, size: 18),
          label: const Text('فاتورة جديدة'),
        ),
      ],
      body: AppStateView(
        isLoading: state.isLoading,
        isEmpty: state.allInvoices.isEmpty && !state.isLoading,
        emptyMessage: 'لا توجد فواتير مشتريات',
        emptyIcon: PhosphorIconsBold.shoppingCart,
        child: Column(children: [
          const SyncPendingBanner(tableName: 'purchase_invoices', label: 'فاتورة مشتريات'),
          _buildKpiCards(context, state),   // انسخ 231–280
          _buildFilters(context, ref, state, controller), // انسخ 283–459
          const SizedBox(height: 16),
          Expanded(
            child: PicPosContentCard(
              child: _buildInvoicesTable(context, ref, state), // انسخ 464..
            ),
          ),
        ]),
      ),
    ),
  );
}
```
> استخرج الكتل المنسوخة كدوال مساعدة خاصة (`_buildExcelMenu`, `_buildKpiCards`,
> `_buildFilters`, `_buildInvoicesTable`) داخل نفس الملف. حافِظ على `_confirmEditInvoice`
> (السطور 63–103) لأنه يستدعي `editInvoice` من الـ mixin. **مصيدة الاستيراد:**
> `purchase_invoices_screen.dart` يستورد `AppToast` عبر
> `package:picpos_erp/core/widgets/app_toast.dart` و`InvoiceStatus` مخفي من `app_constants` —
> انسخ كتلة الاستيراد كما هي وأضِف استيراد `picpos_shell`.

- [ ] **الخطوة ٥: وصّل الاختيار في `app_main_screen.dart`**

استيراد:
```dart
import 'presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
```
عدّل `child` داخل `SecurityScreenGate` لشاشة المشتريات:
```dart
child: Brand.isPicPos ? const PurchasesPicposScreen() : const PurchaseInvoicesScreen(),
```

- [ ] **الخطوة ٦: شغّل اختبار الشاشة وتأكد إنه ناجح**

Run: `D:\Cash\develop\flutter\bin\flutter test test/widget/purchases_picpos_screen_test.dart`
Expected: PASS.

- [ ] **الخطوة ٧: تحليل + اختبارات الهوية**

```bash
D:\Cash\develop\flutter\bin\flutter analyze lib test
D:\Cash\develop\flutter\bin\flutter test test/unit/brand_isolation_test.dart
D:\Cash\develop\flutter\bin\flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart
```
Expected: `No issues found!` + خضرا.

- [ ] **الخطوة ٨: كوميت**

```bash
git add lib/presentation/purchases_picpos lib/app_main_screen.dart test/widget/purchases_picpos_screen_test.dart
git commit -m "feat(picpos): شاشة المشتريات بهوية PicPos (fork ينسخ CRUD mixin كما في POS)"
```

---

## Task 5: بوابة التحقق النهائية

بعد الشاشات الثلاث — تشغيل بوابة الجودة الكاملة على العلامتين + فحص binary.

**Files:** لا شيء (تحقق فقط، وإصلاحات إن ظهرت).

- [ ] **الخطوة ١: تحليل شامل**

Run: `D:\Cash\develop\flutter\bin\flutter analyze lib test`
Expected: `No issues found!`

- [ ] **الخطوة ٢: الجولة الكاملة (العلامة الافتراضية = uralcash)**

Run: `D:\Cash\develop\flutter\bin\flutter test`
Expected: `+3262 ~12 · 0 فشل` أو أكثر (الاختبارات الجديدة تضاف للعدد). **صفر فشل.**
لو ظهر فشل: إصلاح جهة-اختبار أو باج منطقي (الأخير → كوميت منفصل + patch).

- [ ] **الخطوة ٣: اختبارات هوية PicPos**

Run: `D:\Cash\develop\flutter\bin\flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart`
Expected: خضراء (`AppConfig.flavor == unified`, `getDatabaseFileName() == 'picpos_unified.db'`).

- [ ] **الخطوة ٤: بناء PicPos الكامل**

Run: `.\build_picpos.bat` (يحتاج `flutter` على PATH؛ ~٩ دقائق، يمسح `build\windows`)
Expected: `SUCCESS` بلا تسريب هوية.

- [ ] **الخطوة ٥: فحص الـ binary بالترميزين**

```powershell
$bytes = [System.IO.File]::ReadAllBytes("D:\PICPOS-ERP\FlavorBuilds\PicPos\data\app.so")
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
$utf16 = [System.Text.Encoding]::Unicode.GetString($bytes)
[regex]::Matches($ascii, '(?i)ural[A-Za-z0-9 ._\-@]{0,26}') |
  Group-Object Value | Sort-Object Count -Descending |
  ForEach-Object { "x$($_.Count)  $($_.Name)" }
"UTF-16 hits: $(([regex]::Matches($utf16,'(?i)uralcash')).Count)"
foreach ($s in @('monexia','cashier_market','avalon')) {
  "$s : ascii=$(([regex]::Matches($ascii,[regex]::Escape($s),'IgnoreCase')).Count) utf16=$(([regex]::Matches($utf16,[regex]::Escape($s),'IgnoreCase')).Count)"
}
```
**المقبول الوحيد:** الملاح الأربعة فقط (`UralCash-API-v1`, `UralCash-Session-v1`,
`UralCash-ERP-Integrity-v1`, `<REDACTED-SALT>`) + المُعرّفات الداخلية المقبولة
(قسم ٥.٥ في HANDOFF: `picpos_erp`, `URAL_RESET_*`, `ural_api_token`, ...) · **UTF-16 = ٠** ·
**monexia/cashier_market/avalon = ٠** في الترميزين.

- [ ] **الخطوة ٦: كوميت التوثيق (تحديث HANDOFF)**

حدّث `HANDOFF.md` (قسم الحالة + بند «باقي الشاشات») بنتيجة العيّنة، ثم:
```bash
git add HANDOFF.md
git commit -m "docs: عيّنة إعادة تصميم شاشات PicPos (٣ شاشات) — خلصت ومتحقَّق منها"
```

---

## مراجعة ذاتية (تحقق من التغطية)

- **مكوّنات `picpos_shell` الأربعة** → Task 1. ✓
- **الأصناف** → Task 2. ✓ · **المخزون** → Task 3. ✓ · **المشتريات** → Task 4. ✓
- **الاختيار بالعلامة في `app_main_screen`** → مضمَّن في Tasks 2–4. ✓
- **اختبار كل شاشة** → مضمَّن في كل Task. ✓
- **UralCash لا يُلمس** → التعديل الوحيد المشترك = سطر الاختيار (فرع else = سلوك حالي). ✓
- **قاعدة الـ patch** → منصوصة في القيود العامة ومصايد النسخ في Tasks 3–4. ✓
- **فحص binary بالترميزين + العلامات الأخرى** → Task 5. ✓
- **الأساس الأخضر 3262/12/0** → Task 5 خطوة ٢. ✓

> **ملاحظة أمانة:** Tasks 3 و4 تعتمدان على **نسخ منطق تنظيم واجهة موجود** (paging،
> CRUD mixin) من شاشات UralCash إلى fork PicPos — لأنه `part of`/خاص ولا يُستورَد. المُنفِّذ
> يقرأ المقاطع المشار إليها بالأسطر وينسخها بأقل تعديل (الغلاف فقط). هذه تكلفة الـ fork
> المقبولة بوعي (نفس سابقة الـ POS)، وكل منطق الأعمال يبقى في المستودعات/الخدمات المشتركة.

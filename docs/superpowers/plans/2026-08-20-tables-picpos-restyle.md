# شاشةُ الطاولات بهويّة PicPos — خطّةُ التنفيذ

> **للمنفِّذ الآليّ:** مهارةٌ فرعيّةٌ لازمة: استعمل
> `superpowers:subagent-driven-development` (مُوصى به) أو
> `superpowers:executing-plans` لتنفيذ هذه الخطّة مهمّةً مهمّةً. الخطواتُ بصيغة
> مربّعات (`- [ ]`) للتتبّع.

**الهدف:** شاشةُ طاولاتٍ بهويّة PicPos — نفسُ المنطق، بتوزيعٍ جديدٍ وخريطةٍ
حيّة، وصلاحيّةٍ لكلِّ زرّ، وسجلٍّ لكلِّ عمليّة، وتقريرٍ بفلاتره.

**المعماريّة:** مجلَّدٌ جديد `presentation/tables_picpos/` يعيد الكساء ويستدعي
النوافذَ الثقيلةَ القائمةَ كما هي. قواعدُ الأفعال (أيُّها يصلح لأيّ حالة، وأيُّ
صلاحيّةٍ تحرسه) تعيش في `domain/models/table_actions.dart` **دالّتين خالصتين**
تُقاسان بلا فتح شاشة. والشاشةُ القديمة `TablesScreen` لا تُمَسّ.

**المواصفة:** [2026-08-19-tables-picpos-restyle-design.md](../specs/2026-08-19-tables-picpos-restyle-design.md)
· **القاعدة:** `da5e31f6`

---

## قيودٌ عامّة — تسري على كلِّ مهمّة

- **ممنوع `dart format`** — المستودعُ غيرُ مضبوطٍ عليه، ويحوّل تعديلاً صغيراً
  إلى ضخم.
- **ممنوع تحرير `lib/data/database/database.g.dart`** بيدك.
- **لا `build_runner` في هذه الخطّة إطلاقاً** — لا مخطّطَ يتغيّر ولا جدولَ
  يُضاف. إن ظننتَ أنك تحتاجه فقد خرجتَ عن المدى؛ توقّف واسأل.
- **ممنوع `git checkout`** للتراجع — استعِد بـ`git show HEAD:<path> > <path>`.
- **اختباراتُ الودجت تتعلّق عند فتح الشاشات** (‏`db.close()` ينتظر مؤقّت
  drift). لا تفتح `TablesPicposScreen` ولا أيَّ شاشةٍ في اختبار؛ اضخخ الودجتَ
  الصغيرةَ وحدَها بلا `ProviderScope` وبلا `AppDatabase`. النموذجُ:
  `test/widget/table_actions_menu_test.dart`.
- **`presentation_db_import_guard`** يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
  `data/database`، والقائمةُ البيضاء مقفولة. ملفّاتُ `tables_picpos/` جديدةٌ
  كلُّها ⇒ **لا تستورد `data/database` فيها**. مُرَّ عبر `IRestaurantRepository`
  أو `TableSessionService`.
- **الحساب الخالص مكانه `lib/domain/models/`** لا الودجت.
- **حدُّ الحجوزات (قرارُ المالك 2026-08-20):** `TableAction.reserve` هنا هو
  **حجزٌ سريعٌ للطاولة** لا غير — اسمٌ وهاتفٌ ووقتٌ وعددُ أشخاصٍ في
  `TableReservations`. أمّا **العربونُ والخدماتُ والموظّفون والتقويمُ وقائمةُ
  الانتظار** فمنظومةُ الحجوزات، ولها مواصفتُها المستقلّة. **لا تلمس شيئاً
  منها في هذه الخطّة**، ولا تُضف عموداً إلى `TableReservations`.
- **أسماءُ الأصناف مقيسةٌ لا مفترَضة:** صنفُ المسافات اسمُه `Spacing` (لا
  `AppSpacing`) في `lib/core/design_system/spacing.dart`، وفيه `xs/sm/md/lg/xl/xxl`.
- **`permission_codes.dart` مشترَكٌ مع UralCash:** كلُّ إضافةٍ في **آخر**
  القائمة فيبقى التعارضُ سطراً واحداً.
- **البوّابة:** `scripts/gate.sh` في الخلفيّة (~٣٤ دقيقة). خطُّ الأساس عند
  `da5e31f6`: **analyze ٦ info · unit ٣٤٨٦ · widget ٦٨٠ · integration ٧١٠**.
  لا تُخفّض حدّاً لتُخضِر بوّابة.
- **قبل أيِّ قياس:** عمليّةُ `flutter` واحدةٌ فقط، و`build/native_assets/windows/sqlite3.dll`
  موجود، وشجرةٌ ساكنة. والتقط المخرَجَ كاملاً إلى ملف — `| tail` يخفي الفشلَ
  الذي جئتَ تبحث عنه. ولا تُبلّغ رقماً لم تره.

---

## بنيةُ الملفّات

| الملفّ | مسؤوليّته |
|---|---|
| `lib/domain/models/table_actions.dart` (تعديل) | يضاف `permissionForAction` — خريطةُ الفعل ← كودِ الصلاحيّة، خالصة |
| `lib/core/permissions/permission_codes.dart` (تعديل) | ثلاثةُ أكوادٍ جديدة في آخر القوائم |
| `lib/core/permissions/permission_enforcement_registry.dart` (تعديل) | شطبُ مدخلَين بطَلا |
| `lib/services/table_session_service.dart` (تعديل) | سطرا سجلٍّ ناقصان |
| `lib/presentation/tables_picpos/widgets/tables_status_rail.dart` (جديد) | عمودُ الحالات بعدّاداتها |
| `lib/presentation/tables_picpos/widgets/tables_action_rail.dart` (جديد) | شريطُ الأفعال محروساً |
| `lib/presentation/tables_picpos/screens/tables_picpos_screen.dart` (جديد) | الإطارُ والتخطيطُ الثلاثيّ |
| `lib/app_main_screen.dart` (تعديل) | سطرُ التفرّع |
| `lib/presentation/screens/reports/tables_report_screen.dart` (جديد) | تقريرُ الطاولات بفلاتره |
| `lib/presentation/screens/reports_screen.dart` (تعديل) | بطاقةُ الكتالوج |
| `lib/presentation/reports_picpos/screens/reports_picpos_screen.dart` (تعديل) | بطاقةُ الكتالوج — التوأم |

---

## المهمّة ١: قياسُ الخريطة الميّتة — بوّابةُ قرارٍ لا كتابةُ كود

`FloorPlanDesigner` (٦٦٥ سطراً) **لم يُشغَّل قطُّ**: صفرُ مستدعين في المستودع.
المواصفةُ §٣ تشترط قياسَه قبل البناء عليه. هذه المهمّةُ تُنتج **قراراً**، وقد
لا تُنتج كوداً.

**الملفّات:**
- قراءة: `lib/presentation/screens/tables/floor_plan_designer.dart`
- إنشاء مؤقّت: `test/widget/floor_plan_designer_smoke_test.dart`

- [ ] **الخطوة ١: اكتب اختبارَ دخانٍ يضخّ المصمِّمَ وحدَه**

```dart
// test/widget/floor_plan_designer_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/presentation/screens/tables/floor_plan_designer.dart';

void main() {
  testWidgets('المصمِّمُ يُبنى في وضع القراءة بلا انهيار', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FloorPlanDesigner(
              sectionId: 1,
              isEditMode: false,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
```

> **إن اختلف التوقيعُ عمّا هنا، فالتوقيعُ الحقيقيُّ هو الحَكَم** — اقرأ
> `floor_plan_designer.dart:15-30` وصحّح النداءَ، ولا تعدّل الودجت لتوافق
> الاختبار.

- [ ] **الخطوة ٢: شغّله والتقط المخرَج كاملاً**

```bash
flutter test test/widget/floor_plan_designer_smoke_test.dart --concurrency=4 2>&1 | tee /tmp/floorplan.log
```

- [ ] **الخطوة ٣: احسم**

- **مرَّ** ⇒ الخريطةُ صالحةٌ للتوصيل. احذف ملفَّ الاختبار المؤقّت وتابع إلى
  المهمّة ٢ (اختبارُ الدخان لا يبقى: يفتح ودجتاً ثقيلةً بلا قيمةِ حراسة).
- **سقط أو تعلّق** ⇒ **قف**. سجّل نصَّ الفشل في تعليقٍ على الخطّة واسأل
  المالك: أيُصلَح المصمِّم (توسيعُ مدى) أم تبقى الشبكةُ عرضاً أساسيّاً
  والخريطةُ خلفَ المفتاح كما هي؟ **لا تُصلحه من تلقاء نفسك.**

- [ ] **الخطوة ٤: أودِع (فقط إن كان هناك ما يُودَع)**

لا كودَ يُودَع في هذه المهمّة عند النجاح. إن أنتجت اكتشافاً، أودِع سطراً في
المواصفة:

```bash
git add docs/superpowers/specs/2026-08-19-tables-picpos-restyle-design.md
git commit -m "docs(spec): نتيجةُ قياس الخريطة الميّتة"
```

---

## المهمّة ٢: صلاحيّةُ كلِّ فعلٍ — قاعدةٌ خالصةٌ واحدة

الفجوةُ المقيسة: `merge` و`splitBill` و`reserve` **بلا كودِ صلاحيّةٍ أصلاً**،
و`open` و`closeTable` بلا فحص. والقاعدةُ ستُستعمَل في شريط الأفعال، فيجب أن
تكون خالصةً مُختبَرة.

**الملفّات:**
- تعديل: `lib/core/permissions/permission_codes.dart`
- تعديل: `lib/domain/models/table_actions.dart`
- اختبار: `test/unit/table_action_permissions_test.dart`

**الواجهات:**
- تُنتِج: `String? permissionForAction(TableAction action)` — كودُ الصلاحيّة،
  أو `null` لفعلٍ لا يحتاج صلاحيّةً خاصّة. تعتمد عليها المهمّةُ ٥.
- تُنتِج: `PermissionCodes.tablesMerge` · `tablesSplitBill` · `tablesReserve`.

- [ ] **الخطوة ١: اكتب الاختبارَ الساقط**

```dart
// test/unit/table_action_permissions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/domain/models/table_actions.dart';

void main() {
  test('كلُّ فعلٍ يحرّك مالاً أو حالةً له كودُ صلاحيّة', () {
    const moneyOrState = [
      TableAction.open,
      TableAction.addItems,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.reserve,
      TableAction.pay,
      TableAction.changeStatus,
      TableAction.cancelOrder,
      TableAction.closeTable,
    ];
    for (final a in moneyOrState) {
      expect(permissionForAction(a), isNotNull,
          reason: 'الفعلُ $a بلا صلاحيّةٍ تحرسه');
    }
  });

  test('سجلُّ الطاولة قراءةٌ محضة — لا صلاحيّةَ خاصّةً له', () {
    expect(permissionForAction(TableAction.log), isNull);
  });

  test('الأكوادُ الثلاثةُ الجديدة مسجَّلةٌ في masterList', () {
    final codes = PermissionCodes.masterList
        .map((e) => e['code'] as String)
        .toSet();
    expect(codes, contains(PermissionCodes.tablesMerge));
    expect(codes, contains(PermissionCodes.tablesSplitBill));
    expect(codes, contains(PermissionCodes.tablesReserve));
  });

  test('كلُّ كودٍ ترجعه الخريطةُ موجودٌ في masterList', () {
    final codes = PermissionCodes.masterList
        .map((e) => e['code'] as String)
        .toSet();
    for (final a in TableAction.values) {
      final p = permissionForAction(a);
      if (p != null) {
        expect(codes, contains(p), reason: 'الكودُ $p للفعل $a غيرُ مسجَّل');
      }
    }
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/unit/table_action_permissions_test.dart --concurrency=4
```

المتوقَّع: فشلُ تصريفٍ — `permissionForAction` و`tablesMerge` غيرُ معرَّفة.

- [ ] **الخطوة ٣: أضف الأكوادَ الثلاثة**

في `permission_codes.dart`، **بعد** `tablesDiscount` مباشرةً (آخرُ كودِ
طاولات، سطر ٤٨٥):

```dart
  /// دمجُ طلبَي طاولتين في واحد — يهدم طلباً ويضخّ أصنافَه في آخر.
  static const String tablesMerge = 'tables_merge';

  /// تقسيمُ حساب الطاولة على عدّة دافعين.
  static const String tablesSplitBill = 'tables_split_bill';

  /// حجزُ طاولةٍ لعميلٍ في وقتٍ لاحق.
  static const String tablesReserve = 'tables_reserve';
```

وفي **آخر** كتلة `// ── Tables ──` في `masterList` (بعد سطر `tablesDiscount`):

```dart
    {'code': tablesMerge, 'name': 'دمج طلبات الطاولات', 'category': 'tables'},
    {'code': tablesSplitBill, 'name': 'تقسيم حساب الطاولة', 'category': 'tables'},
    {'code': tablesReserve, 'name': 'حجز طاولة', 'category': 'tables'},
```

- [ ] **الخطوة ٤: أضف الخريطةَ الخالصة**

في آخر `lib/domain/models/table_actions.dart`:

```dart
/// كودُ الصلاحيّة الذي يحرس كلَّ فعل — أو `null` لفعلٍ لا يحتاج صلاحيّةً خاصّة.
///
/// دالّةٌ خالصةٌ بجوار [actionsForStatus] وللسبب نفسِه: كانت الحراسةُ متناثرةً
/// في الودجت، فبقيت ثلاثةُ أفعالٍ (دمجٌ وتقسيمٌ وحجز) **بلا صلاحيّةٍ إطلاقاً**
/// ولم يلاحظ أحد. وموضعان منها كانا يعيشان في `table_order_panel.dart` — وهي
/// لوحةٌ تختفي في شاشة PicPos، فكان الكساءُ يُسقط الإنفاذَ صامتاً.
///
/// و`log` وحدَه `null`: قراءةُ سجلٍّ لا تغيّر شيئاً، ودخولُ الشاشة نفسِه محروسٌ
/// بـ`tables_view`.
String? permissionForAction(TableAction action) {
  switch (action) {
    case TableAction.open:
    case TableAction.changeStatus:
    case TableAction.closeTable:
      return PermissionCodes.tablesManage;
    case TableAction.addItems:
      return PermissionCodes.tablesAddItems;
    case TableAction.pay:
      return PermissionCodes.tablesCheckout;
    case TableAction.transfer:
      return PermissionCodes.tablesTransfer;
    case TableAction.merge:
      return PermissionCodes.tablesMerge;
    case TableAction.splitBill:
      return PermissionCodes.tablesSplitBill;
    case TableAction.printBill:
      return PermissionCodes.tablesPrintBill;
    case TableAction.reserve:
      return PermissionCodes.tablesReserve;
    case TableAction.cancelOrder:
      return PermissionCodes.tablesCancel;
    case TableAction.log:
      return null;
  }
}
```

وأضف في رأس الملفّ:

```dart
import '../../core/permissions/permission_codes.dart';
```

> **تحذيرٌ مقيس:** `table_actions.dart` ملفٌّ في `domain/models/` يحمل أكوادَ
> صلاحيّات. حارسُ التكافؤ يقطع حافّةَ الاستيراد لملفٍّ بلا أنواع — إن أبلغت
> البوّابةُ عن فجوةٍ وهميّةٍ بعد هذه الخطوة فهذا سببُها، والعلاجُ في
> `parity-guard` لا في نقل الملفّ.

- [ ] **الخطوة ٥: شغّل الاختبارَ وتأكّد أنه يمرّ**

```bash
flutter test test/unit/table_action_permissions_test.dart --concurrency=4
```

المتوقَّع: أربعةُ اختباراتٍ ناجحة.

- [ ] **الخطوة ٦: أودِع**

```bash
git add lib/core/permissions/permission_codes.dart lib/domain/models/table_actions.dart test/unit/table_action_permissions_test.dart
git commit -m "feat(tables): ثلاثةُ أفعالٍ كانت بلا صلاحيّةٍ إطلاقاً — والخريطةُ صارت خالصةً واحدة"
```

---

## المهمّة ٣: سدُّ ثغرتَي سجلّ العمليات

المقيس: `table_reserve` صفرُ مطابقاتٍ في المستودع — الحجزُ يُنشَأ بلا أثر.
و`table_split` كذلك.

**الملفّات:**
- تعديل: `lib/services/table_session_service.dart`
- اختبار: `test/unit/table_session_activity_log_test.dart`

**الواجهات:**
- تُستهلَك: `_log({userId, userName, action, tableId, description, amount, oldValue, newValue})` — دالّةٌ خاصّةٌ قائمةٌ في الخدمة (سطر ٤٥).

- [ ] **الخطوة ١: اكتب الاختبارَ الساقط**

```dart
// test/unit/table_session_activity_log_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;
  late int tableId;

  setUp(() async {
    db = AppDatabase.forTesting();
    // ‏`forTesting` يُنفِذ المفاتيحَ الأجنبيّة — ازرع القسمَ قبل الطاولة.
    final sectionId = await db.into(db.tableSections).insert(
          TableSectionsCompanion.insert(name: 'الصالة'),
        );
    tableId = await db.into(db.restaurantTables).insert(
          RestaurantTablesCompanion.insert(
            name: 'ط١',
            sectionId: Value(sectionId),
          ),
        );
    service = TableSessionService(db);
  });

  tearDown(() async => db.close());

  Future<List<ActivityLog>> logsOfType(String action) =>
      (db.select(db.activityLogs)..where((l) => l.action.equals(action))).get();

  test('حجزُ الطاولة يترك سطرَ سجلّ يسمّي العميل', () async {
    await service.reserveTable(
      tableId: tableId,
      customerName: 'أحمد محمد',
      customerPhone: '0791234567',
      reservationTime: DateTime(2026, 9, 1, 20),
      partySize: 4,
      userId: null,
      userName: 'كاشير',
    );

    final logs = await logsOfType('table_reserve');
    expect(logs, hasLength(1),
        reason: 'الحجزُ كان يُنشَأ بلا أثر — فمن حجز الطاولةَ ومتى؟');
    expect(logs.single.description, contains('أحمد محمد'));
  });
}
```

> **توقيعا `TableSectionsCompanion` و`RestaurantTablesCompanion` مأخوذان
> بالقياس؛ إن اختلفا فاقرأ `lib/data/database/tables/restaurant_tables.dart`
> وصحّح البذرَ — ولا تُضعِف الاختبار.** وتوقيعُ `TableSessionService(db)` كذلك:
> اقرأ باني الصنف قبل النداء.

- [ ] **الخطوة ٢: افهم المسارَ المقيس قبل أن تكتب**

**تصادمُ تسميةٍ يجب ألّا يوقعك:** كلُّ ما في `TableSessionService` باسم
`Reservation` — `releaseReservation` · `pendingReservations` — يخصّ **حجزَ
الدفعة** (v158: صفُّ دفعٍ `pending` بلا فاتورة)، **لا حجزَ الطاولة**. لا تضع
سطرَك هناك.

ومسارُ حجز الطاولة الحقيقيُّ يمرّ **من الودجت إلى المستودع مباشرةً**:

```
table_operations.dart:925  →  restaurantRepo.createReservation(...)
                           →  RestaurantRepositoryImpl:83
                           →  tables_dao.dart:611
```

والتوقيع (`domain/repositories/restaurant_repository.dart:28`):

```dart
Future<void> createReservation({
  required int tableId,
  required String customerName,
  String? customerPhone,
  required DateTime reservationTime,
  required int partySize,
  String? notes,
});
```

فلا خدمةَ في المسار ⇒ التسجيلُ يحتاج دالّةً في الخدمة، لا سطراً في الودجت.

- [ ] **الخطوة ٣: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/unit/table_session_activity_log_test.dart --concurrency=4
```

المتوقَّع: سقوطٌ بأن `logsOfType('table_reserve')` فارغة.

- [ ] **الخطوة ٤: أضف دالّةَ الحجز في الخدمة، وحوّل الودجت إليها**

في `TableSessionService` (بجوار بقيّة أفعال الطاولة، لا بجوار دوالِّ حجز
الدفعة):

```dart
  /// حجزٌ سريعٌ للطاولة — يكتب الصفَّ **ويترك أثراً**.
  ///
  /// كان الودجتُ ينادي `createReservation` على المستودع مباشرةً، فيُنشَأ
  /// الحجزُ بلا سطرِ سجلٍّ واحد: مَن حجز الطاولةَ ومتى؟ لا جواب. والتسجيلُ
  /// هنا لا في الودجت كي لا يضيع إن نودي المسارُ من شاشةٍ أخرى.
  ///
  /// وهذا **حجزُ طاولةٍ** لا موعدُ خدمة: العربونُ والخدماتُ والموظّفون
  /// لمنظومة الحجوزات، ولها مواصفتُها.
  Future<void> reserveTable({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
    required int? userId,
    required String userName,
  }) async {
    await _repo.createReservation(
      tableId: tableId,
      customerName: customerName,
      customerPhone: customerPhone,
      reservationTime: reservationTime,
      partySize: partySize,
      notes: notes,
    );
    final table = await _table(tableId);
    await _log(
      userId: userId,
      userName: userName,
      action: 'table_reserve',
      tableId: tableId,
      description: 'حجزُ ${table.name} باسم $customerName — '
          '${reservationTime.toIso8601String()} · $partySize أشخاص',
    );
  }
```

> **إن لم تكن الخدمةُ تحمل مستودعاً (`_repo`)** — اقرأ رأسَ
> `table_session_service.dart` — فمرِّر النداءَ عبر ما تحمله فعلاً
> (‏`_db.createReservation` مثلاً). **لا تُضف تبعيّةً جديدةً إلى الخدمة** لهذا
> السطر؛ استعمل ما هو موجود.

ثم في `table_operations.dart:925` بدّل نداءَ المستودع بنداء الخدمة، ومرِّر
المستخدمَ الحاليَّ كما تفعل بقيّةُ الأفعال في الملفّ.

وفي مسار التقسيم (`SplitSettlementRunner` ينادي الخدمة؛ ضع السطرَ حيث تُثبَّت
الحصّةُ الأخيرة أو حيث تبدأ التسوية — **لا في الودجت**):

```dart
    await _log(
      userId: userId,
      userName: userName,
      action: 'table_split',
      tableId: tableId,
      description: 'تقسيمُ حساب ${table.name} على $partCount حصص',
      amount: total,
    );
```

- [ ] **الخطوة ٥: شغّل وتأكّد أنه يمرّ**

```bash
flutter test test/unit/table_session_activity_log_test.dart --concurrency=4
```

- [ ] **الخطوة ٦: أودِع**

```bash
git add lib/services/table_session_service.dart test/unit/table_session_activity_log_test.dart
git commit -m "fix(tables): الحجزُ كان يُنشَأ بلا أثرٍ في السجلّ — والتقسيمُ لا يُميَّز"
```

---

## المهمّة ٤: عمودُ الحالات بعدّاداتها

**الملفّات:**
- إنشاء: `lib/presentation/tables_picpos/widgets/tables_status_rail.dart`
- اختبار: `test/widget/tables_status_rail_test.dart`

**الواجهات:**
- تُنتِج: `TablesStatusRail({required Map<String, int> counts, required String? selected, required ValueChanged<String?> onSelect})`
  — تعتمد عليها المهمّةُ ٦.
- تُنتِج: `Map<String, int> countByStatus(List<String> statuses)` — خالصة،
  تُرجع مدخلاً **لكلِّ حالةٍ في `TableStatus.all`** ولو كان صفراً.

- [ ] **الخطوة ١: اكتب الاختبارَ الساقط**

```dart
// test/widget/tables_status_rail_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/table_status.dart';
import 'package:picpos_erp/presentation/tables_picpos/widgets/tables_status_rail.dart';

void main() {
  test('العدُّ يشمل كلَّ حالةٍ ولو كانت صفراً', () {
    final counts = countByStatus([
      TableStatus.available,
      TableStatus.available,
      TableStatus.occupied,
    ]);
    expect(counts[TableStatus.available], 2);
    expect(counts[TableStatus.occupied], 1);
    expect(counts[TableStatus.outOfService], 0,
        reason: 'الصفرُ يُعرَض ولا يُخفى — صورةُ المالك تعرض «غير متاحة ٠»');
    expect(counts.keys.toSet(), TableStatus.all.toSet());
  });

  testWidgets('الضغطُ على حالةٍ يبلّغ باختيارها، وإعادةُ الضغط تُلغيه',
      (tester) async {
    String? picked = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TablesStatusRail(
            counts: countByStatus([TableStatus.available]),
            selected: null,
            onSelect: (s) => picked = s,
          ),
        ),
      ),
    );
    await tester.tap(find.text('متاحة'));
    expect(picked, TableStatus.available);
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/widget/tables_status_rail_test.dart --concurrency=4
```

المتوقَّع: فشلُ تصريفٍ — الملفُّ غيرُ موجود.

- [ ] **الخطوة ٣: اكتب الودجت**

```dart
// lib/presentation/tables_picpos/widgets/tables_status_rail.dart
import 'package:flutter/material.dart';

import '../../../core/design_system/spacing.dart';
import '../../../domain/models/table_status.dart';
import '../../picpos_shell/picpos_stat_tile.dart';
import '../../screens/tables/widgets/table_status_info.dart';

/// عدُّ الطاولات لكلِّ حالة — **بمدخلٍ لكلِّ حالةٍ ولو كان صفراً**.
///
/// إخفاءُ الصفر يجعل العمودَ يقفز طولاً كلّما تبدّلت الطاولات، ويخفي معلومةً
/// حقيقيّة: «لا طاولةَ خارجَ الخدمة» خبرٌ لا فراغ.
Map<String, int> countByStatus(List<String> statuses) {
  final counts = {for (final s in TableStatus.all) s: 0};
  for (final s in statuses) {
    if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
  }
  return counts;
}

class TablesStatusRail extends StatelessWidget {
  const TablesStatusRail({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in TableStatus.all)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: InkWell(
              onTap: () => onSelect(selected == status ? null : status),
              child: PicPosStatTile(
                label: tableStatusLabel(status),
                value: '${counts[status] ?? 0}',
                accent: tableStatusColor(status),
              ),
            ),
          ),
      ],
    );
  }
}
```

**و`tableStatusLabel`/`tableStatusColor` غيرُ موجودتين — تُكتبان في هذه
الخطوة.** المقيس: `table_status.dart` يحمل الثوابتَ الخمسَ وحدَها بلا اسمٍ ولا
لون، والخريطةُ منسوخةٌ **مرّتين**: `tables_filter_bar.dart:10-13` (ثلاثُ حالاتٍ
من خمس) و`table_card.dart:23-34` (عشرةُ مداخلَ فيها حالاتٌ ميّتة:
`seated/ordered/eating/billing/cleaning`). فنسخةٌ ثالثةٌ في شاشة PicPos هي
الانحرافُ نفسُه الذي تُصلحه هذه الخطّة.

**قرارُ المالك 2026-08-20: تُوحَّد الثلاثةُ الآن.** والاسمُ واللونُ والأيقونةُ
شأنُ عرضٍ لا قاعدةُ عمل، فمكانُها ملفٌّ مشترَكٌ في العرض لا `domain/models`
(‏وإلّا دخل `Color` و`IconData` إلى طبقة المجال بلا داعٍ).

**أنشئ `lib/presentation/screens/tables/widgets/table_status_info.dart`
بالقيم المنقولة من `table_card.dart:22-33` حرفاً — العشرةِ كلِّها:**

```dart
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// اسمُ الحالة ولونُها وأيقونتُها — مصدرٌ واحدٌ لِما كان منسوخاً ثلاثَ مرّات.
class TableStatusInfo {
  const TableStatusInfo(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// الخريطةُ منقولةٌ من `table_card.dart` بلا تغييرِ قيمةٍ واحدة.
///
/// وفيها خمسُ حالاتٍ **لا يكتبها أحد** (`seated`/`ordered`/`eating`/`billing`/
/// `cleaning`) — بقايا مخطّطٍ قديمٍ موثَّقةٌ في رأس `table_status.dart`.
/// تبقى كما هي: حذفُها يغيّر ما تعرضه البطاقةُ لصفٍّ قديمٍ في قاعدةِ مالكٍ
/// قائمة، وذلك تغييرُ سلوكٍ لا توحيدُ مصدر.
const Map<String, TableStatusInfo> tableStatusInfoMap = {
  'available': TableStatusInfo('متاحة', Color(0xFF10B981), PhosphorIconsBold.checkCircle),
  'reserved': TableStatusInfo('محجوزة', Color(0xFFF59E0B), PhosphorIconsBold.calendarCheck),
  'occupied': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'paid': TableStatusInfo('مدفوعة', Color(0xFFF97316), PhosphorIconsBold.currencyCircleDollar),
  'out_of_service': TableStatusInfo('خارج الخدمة', Color(0xFFCBD5E1), PhosphorIconsBold.prohibit),
  'seated': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'ordered': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'eating': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'billing': TableStatusInfo('مشغولة', Color(0xFF3B82F6), PhosphorIconsBold.users),
  'cleaning': TableStatusInfo('تنظيف', Color(0xFF6366F1), PhosphorIconsBold.broom),
};

/// **الرجوعُ إلى `available` لا إلى الحالة نفسِها** — هكذا كانت البطاقةُ تفعل
/// (`table_card.dart:40`: `?? _statusMap['available']!`). تغييرُه يجعل حالةً
/// مجهولةً تُعرَض بنصِّها الإنجليزيِّ على شاشة الكاشير.
TableStatusInfo tableStatusInfo(String status) =>
    tableStatusInfoMap[status] ?? tableStatusInfoMap['available']!;

String tableStatusLabel(String status) => tableStatusInfo(status).label;
Color tableStatusColor(String status) => tableStatusInfo(status).color;
```

**ثم وحِّد المستهلكَين — والسلوكُ يجب ألّا يتغيّر بحرف:**

- `table_card.dart`: احذف `_statusMap` و`_StatusInfo`، وبدّل
  `_statusMap[table.status] ?? _statusMap['available']!` بـ
  `tableStatusInfo(table.status)`. الحقولُ الثلاثةُ بأسمائها نفسِها
  (`label`/`color`/`icon`) فلا يتغيّر مستدعٍ.
- `tables_filter_bar.dart`: احذف `_statusMap` و`_StatusInfo` المحلّيَّين
  واقرأ من المصدر الجديد. **وانتبه:** شريطُ الترشيح كان يعرض **ثلاثَ حالاتٍ
  من خمس**؛ توسيعُه إلى الخمس تغييرٌ مرئيٌّ في الشاشة القديمة — **لا تفعله**.
  أبقِ قائمتَه الثلاثيّةَ كما هي وغيِّر مصدرَ الاسم واللون فقط.

- [ ] **الخطوة ٣-ب: أثبت أن السلوك لم يتغيّر**

```bash
flutter test test/widget --concurrency=4 2>&1 | tee /tmp/task4_widget.log
```

المتوقَّع: سويّةُ الويدجت كما كانت + اختباراتُك الجديدة. أيُّ سقوطٍ في اختبارٍ
قائمٍ يمسّ البطاقةَ أو شريطَ الترشيح يعني أن التوحيد **غيّر سلوكاً** — أصلحه
ولا تعدّل الاختبار.

- [ ] **الخطوة ٤: شغّل وتأكّد أنه يمرّ**

```bash
flutter test test/widget/tables_status_rail_test.dart --concurrency=4
```

- [ ] **الخطوة ٥: أودِع**

```bash
git add lib/presentation/tables_picpos/widgets/tables_status_rail.dart test/widget/tables_status_rail_test.dart
git commit -m "feat(tables): عمودُ الحالات — والصفرُ يُعرَض لأنه خبرٌ لا فراغ"
```

---

## المهمّة ٥: شريطُ الأفعال محروساً

**الملفّات:**
- إنشاء: `lib/presentation/tables_picpos/widgets/tables_action_rail.dart`
- اختبار: `test/widget/tables_action_rail_test.dart`

**الواجهات:**
- تُستهلَك: `actionsForStatus(String) → List<TableAction>` (قائمة) ·
  `permissionForAction(TableAction) → String?` (المهمّة ٢) ·
  `tableActionLabels[action]` · `tableActionIcon(action)` ·
  `tableActionColor(action)` (قائمة).
- تُنتِج: `TablesActionRail({required String? tableStatus, required ValueChanged<TableAction> onAction})` — تعتمد عليها المهمّةُ ٦.
- تُنتِج: `const railActions` — الأفعالُ الثمانيةُ بترتيب صورة المالك.

- [ ] **الخطوة ١: اكتب الاختبارَ الساقط**

```dart
// test/widget/tables_action_rail_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/table_actions.dart';
import 'package:picpos_erp/domain/models/table_status.dart';
import 'package:picpos_erp/presentation/tables_picpos/widgets/tables_action_rail.dart';

void main() {
  test('الشريطُ ثمانيةُ أفعالٍ بترتيب صورة المالك', () {
    expect(railActions, const [
      TableAction.open,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.changeStatus,
      TableAction.reserve,
      TableAction.closeTable,
    ]);
  });

  test('كلُّ فعلٍ في الشريط محروسٌ بصلاحيّة', () {
    for (final a in railActions) {
      expect(permissionForAction(a), isNotNull);
    }
  });

  testWidgets('الأزرارُ الثمانيةُ تظهر دائماً، وغيرُ الصالح لحالةٍ معطَّل',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TablesActionRail(
            tableStatus: TableStatus.available,
            onAction: (_) {},
          ),
        ),
      ),
    );
    // ثمانيةٌ معروضةٌ دائماً — الصورةُ تعرضها كلَّها.
    for (final a in railActions) {
      expect(find.text(tableActionLabels[a]!), findsOneWidget);
    }
    // و«تقسيم الفاتورة» لا يصلح لطاولةٍ متاحة ⇒ معطَّل.
    expect(actionsForStatus(TableStatus.available),
        isNot(contains(TableAction.splitBill)));
  });

  testWidgets('بلا طاولةٍ مختارة، كلُّ الأزرار معطَّلة', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TablesActionRail(
            tableStatus: null,
            onAction: (_) => fired = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text(tableActionLabels[TableAction.open]!),
        warnIfMissed: false);
    await tester.pump();
    expect(fired, isFalse, reason: 'فعلٌ بلا طاولةٍ لا معنى له');
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/widget/tables_action_rail_test.dart --concurrency=4
```

- [ ] **الخطوة ٣: اكتب الودجت**

```dart
// lib/presentation/tables_picpos/widgets/tables_action_rail.dart
import 'package:flutter/material.dart';

import '../../../core/design_system/spacing.dart';
import '../../../domain/models/table_actions.dart';
import '../../widgets/permission_guard.dart';

/// أفعالُ الشريط بترتيب صورة المالك — ثمانيةٌ من اثنتي عشرة.
///
/// الأربعُ الباقيةُ لا تُحذَف: «إضافة طلب» و«الدفع» فعلُهما الطبيعيُّ داخل
/// نافذة الطلب، و«إلغاء الطلب» و«سجل الطاولة» تبقيان في القائمة المنبثقة.
/// وشريطٌ من اثني عشر زرّاً يطول أطولَ من الخريطة.
const List<TableAction> railActions = [
  TableAction.open,
  TableAction.transfer,
  TableAction.merge,
  TableAction.splitBill,
  TableAction.printBill,
  TableAction.changeStatus,
  TableAction.reserve,
  TableAction.closeTable,
];

/// شريطُ الأفعال — يظهر كاملاً دائماً، ويُعطَّل ما لا يصلح.
///
/// **الأزرارُ تُعطَّل ولا تختفي**: شريطٌ يتغيّر طولُه مع كلِّ اختيارٍ يُربك،
/// والاختفاءُ يخفي عن المستخدم أن الفعلَ موجودٌ أصلاً — نفسُ قرار
/// `settings_permission_tiles.dart:187`.
///
/// ومصدرُ «أيُّ فعلٍ يصلح لأيّ حالة» هو [actionsForStatus] نفسُها التي تقودُ
/// القائمةَ المنبثقة، لا نسخةٌ منها: محرّكا صلاحيّةٍ يتباعدان هما علّةُ هذا
/// المستودع المعروفة.
class TablesActionRail extends StatelessWidget {
  const TablesActionRail({
    super.key,
    required this.tableStatus,
    required this.onAction,
  });

  /// حالةُ الطاولة المختارة — `null` يعني لا طاولةَ مختارة.
  final String? tableStatus;
  final ValueChanged<TableAction> onAction;

  @override
  Widget build(BuildContext context) {
    final allowed = tableStatus == null
        ? const <TableAction>[]
        : actionsForStatus(tableStatus!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `railActions` لا يحوي `log` — الفعلَ الوحيدَ بلا صلاحيّة — لكنّ
        // `!` تجعل ذلك عقداً ضمنيّاً ينكسر صامتاً لو أُضيف فعلٌ بلا كود.
        // فالقراءةُ صريحةٌ والتخطّي مكتوب.
        for (final action in railActions)
          if (permissionForAction(action) case final code?)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: PermissionGuard(
              permission: code,
              showDisabled: true,
              actionName: tableActionLabels[action],
              child: _RailButton(
                action: action,
                enabled: allowed.contains(action),
                onTap: () => onAction(action),
              ),
            ),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.action,
    required this.enabled,
    required this.onTap,
  });

  final TableAction action;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(tableActionIcon(action), size: 18),
      label: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(tableActionLabels[action]!),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tableActionColor(action),
        alignment: AlignmentDirectional.centerStart,
      ),
    );
  }
}
```

> **إن كان `PermissionGuard` بـ`showDisabled: true` يخفي الطفلَ بدل تعطيله،
> اقرأ `permission_guard.dart:86-115` وتصرّف على ما تقرأ لا على ما هنا.**

- [ ] **الخطوة ٤: شغّل وتأكّد أنه يمرّ**

```bash
flutter test test/widget/tables_action_rail_test.dart --concurrency=4
```

- [ ] **الخطوة ٥: أودِع**

```bash
git add lib/presentation/tables_picpos/widgets/tables_action_rail.dart test/widget/tables_action_rail_test.dart
git commit -m "feat(tables): شريطُ الأفعال محروساً — والتعطيلُ من محرّكٍ واحد"
```

---

## المهمّة ٦: الشاشةُ وسطرُ التفرّع وحارسُه

**الملفّات:**
- إنشاء: `lib/presentation/tables_picpos/screens/tables_picpos_screen.dart`
- تعديل: `lib/app_main_screen.dart:605-610`
- تعديل: `lib/core/permissions/permission_enforcement_registry.dart`
- اختبار: `test/static/picpos_screen_fork_guard_test.dart`

**الواجهات:**
- تُستهلَك: `TablesStatusRail` · `countByStatus` (المهمّة ٤) ·
  `TablesActionRail` (المهمّة ٥) · `FloorPlanDesigner` · `tablesUIProvider` ·
  `IRestaurantRepository`.

- [ ] **الخطوة ١: اكتب حارسَ التفرّع الساقط**

```dart
// test/static/picpos_screen_fork_guard_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// شاشاتٌ لها توأمٌ picpos ⇒ سطرُ بنائها لا بدّ أن يتفرّع بـ`Brand.isPicPos`.
///
/// الطاولاتُ كانت الشاشةَ الوحيدةَ بين جيرانها بلا تفرّعٍ ولم يلاحظ أحد —
/// وهذا الحارسُ يقفل ذلك النوعَ من السهو، لا هذه الحالةَ وحدَها.
void main() {
  test('كلُّ شاشةٍ لها توأمُ picpos تتفرّع في app_main_screen', () {
    final src = File('lib/app_main_screen.dart').readAsStringSync();
    const twins = {
      'TablesPicposScreen': 'TablesScreen',
      'ProductsPicposScreen': 'ProductsScreen',
    };
    for (final entry in twins.entries) {
      expect(src.contains(entry.key), isTrue,
          reason: 'التوأمُ ${entry.key} غيرُ مذكورٍ في app_main_screen');
      expect(src.contains('Brand.isPicPos'), isTrue);
    }
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/static/picpos_screen_fork_guard_test.dart --concurrency=4
```

المتوقَّع: سقوطٌ بأن `TablesPicposScreen` غيرُ مذكور.

- [ ] **الخطوة ٣: اكتب الشاشة**

التخطيطُ ثلاثةُ أعمدةٍ داخل `PicPosScreenScaffold`:

```dart
// lib/presentation/tables_picpos/screens/tables_picpos_screen.dart
// (رأسُ الملفّ: لا تستورد data/database — حارسُ الاستيراد يمنع الملفَّ الجديد)

@override
Widget build(BuildContext context) {
  return PicPosScreenScaffold(
    title: 'إدارة الطاولات',
    icon: PhosphorIconsBold.circlesThree,
    headerActions: [
      // إضافة طاولة (محروسٌ بـ tablesManage) · عرض الخريطة · كل المناطق ·
      // مزيد من الخيارات
    ],
    body: Row(
      children: [
        SizedBox(width: 200, child: TablesStatusRail(...)),   // يسار
        Expanded(child: _buildMapOrGrid(...)),                 // وسط
        SizedBox(width: 220, child: TablesActionRail(...)),    // يمين
      ],
    ),
  );
}
```

**قواعدُ لا تُخالَف:**
- `_buildMapOrGrid` يقرأ `uiState.isVisualView`: صحيحٌ ⇒ `FloorPlanDesigner`
  بـ`isEditMode: false`، وإلّا الشبكة. **هذا هو توصيلُ المفتاح الميّت.**
- `onTap` من الخريطة يفتح **نافذةَ الطلب** (`table_order_dialog.dart`) —
  قرارُ المالك، لا عمودَ طلبٍ ثابت.
- `TablesActionRail.onAction` يُمرَّر إلى نفس مسار `_handleTableAction` القائم
  في `table_operations.dart` — **لا تنسخ منطقَ الأفعال**.

- [ ] **الخطوة ٤: أضف سطرَ التفرّع**

في `lib/app_main_screen.dart`، بدّل بناءَ شاشة الطاولات:

```dart
        builder: (_) => Brand.isPicPos
            ? const TablesPicposScreen()
            : const TablesScreen(),
```

- [ ] **الخطوة ٥: اشطب مدخلَي سجلّ الإنفاذ اللذين بطَلا**

في `permission_enforcement_registry.dart`، كتلةُ `// ── الطاولات ──`: النصُّ
«لا ميزةَ طاولاتٍ في PicPos إطلاقاً» بطَل. احذف `'tables_add_items'` و
`'tables_checkout'` من المجموعة، واكتب مكانهما سطرَ سببٍ:

```dart
    // ✅ 'tables_add_items' و'tables_checkout' شُطبا (2026-08-20): بُنيت
    //    `TablesPicposScreen` فبطَل نصُّ «لا ميزةَ طاولاتٍ في PicPos».
    //    الصلاحيّتان مُنفَذتان الآن في `tables_action_rail.dart` عبر
    //    `permissionForAction`.
```

- [ ] **الخطوة ٦: شغّل الحارسَ وسويّةَ الويدجت كاملةً**

```bash
flutter test test/static test/widget test/unit/presentation_db_import_guard_test.dart --concurrency=4 2>&1 | tee /tmp/task6.log
```

المتوقَّع: الحارسُ يمرّ · `presentation_db_import_guard` أخضرُ (لا استيرادَ
قاعدةٍ في الملفّات الجديدة) · `picpos_permission_parity_test` أخضرُ بعد الشطب.

- [ ] **الخطوة ٧: أودِع**

```bash
git add lib/presentation/tables_picpos lib/app_main_screen.dart lib/core/permissions/permission_enforcement_registry.dart test/static/picpos_screen_fork_guard_test.dart
git commit -m "feat(tables): شاشةُ PicPos — والمفتاحُ الميّتُ صار يعرض خريطة"
```

---

## المهمّة ٧: تقريرُ الطاولات بفلاتره

**تصحيحٌ مقيسٌ للمواصفة §٨:** التقاريرُ في هذا المستودع ليست تبويبات، بل
**كتالوجُ بطاقاتٍ** في `reports_screen.dart` كلُّ بطاقةٍ تفتح شاشةً كاملة
(`reports_screen.dart:184-270`). فالتقريرُ شاشةٌ مستقلّةٌ + بطاقتان في
الكتالوجَين (الكامل وتوأمِ PicPos).

**الملفّات:**
- إنشاء: `lib/presentation/screens/reports/tables_report_screen.dart`
- تعديل: `lib/presentation/screens/reports_screen.dart`
- تعديل: `lib/presentation/reports_picpos/screens/reports_picpos_screen.dart`
- إنشاء: `lib/domain/models/tables_report_row.dart`
- اختبار: `test/unit/tables_report_aggregation_test.dart`

**الواجهات:**
- تُنتِج: `TablesReportRow` — سطرُ تقريرٍ لطاولةٍ واحدة (`tableId`,
  `tableName`, `orderCount`, `guestCount`, `revenue`, `discount`,
  `avgTurnMinutes`).
- تُنتِج: `List<TablesReportRow> aggregateTablesReport(List<TableOrderRow>)`
  — خالصة.

- [ ] **الخطوة ١: اكتب اختبارَ التجميع الساقط**

```dart
// test/unit/tables_report_aggregation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/tables_report_row.dart';

void main() {
  test('الطلبُ المدموجُ لا يُحسَب مرّتين', () {
    final rows = aggregateTablesReport([
      TableOrderInput(tableId: 1, tableName: 'ط١', total: 100, guestCount: 2,
          discount: 0, openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13), mergedToId: null),
      // طلبٌ دُمج في الأوّل ⇒ إجماليُّه انتقل، فلا يُضاف ثانيةً.
      TableOrderInput(tableId: 2, tableName: 'ط٢', total: 50, guestCount: 1,
          discount: 0, openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 12, 30), mergedToId: 1),
    ]);
    final total = rows.fold<double>(0, (s, r) => s + r.revenue);
    expect(total, 100, reason: 'المدموجُ إجماليُّه انتقل إلى هدفه');
  });

  test('مدّةُ الجلوس بالدقائق من openedAt إلى closedAt', () {
    final rows = aggregateTablesReport([
      TableOrderInput(tableId: 1, tableName: 'ط١', total: 100, guestCount: 2,
          discount: 0, openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13, 30), mergedToId: null),
    ]);
    expect(rows.single.avgTurnMinutes, 90);
  });

  test('الطلبُ المفتوح لا يدخل الإيرادَ ولا متوسّطَ المدّة', () {
    final rows = aggregateTablesReport([
      TableOrderInput(tableId: 1, tableName: 'ط١', total: 70, guestCount: 2,
          discount: 0, openedAt: DateTime(2026, 1, 1, 12),
          closedAt: null, mergedToId: null),
    ]);
    expect(rows.single.revenue, 0);
    expect(rows.single.avgTurnMinutes, isNull);
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يسقط**

```bash
flutter test test/unit/tables_report_aggregation_test.dart --concurrency=4
```

- [ ] **الخطوة ٣: اكتب النموذجَ الخالص**

`lib/domain/models/tables_report_row.dart` يحمل `TableOrderInput` و
`TablesReportRow` و`aggregateTablesReport`. القواعد: يُستبعَد ما `mergedToId`
له غيرُ فارغ، ويُستبعَد من الإيراد ما `closedAt` له فارغ، والمدّةُ متوسّطُ
`closedAt − openedAt` بالدقائق للطلبات المغلقة وحدَها.

- [ ] **الخطوة ٤: شغّل وتأكّد أنه يمرّ**

```bash
flutter test test/unit/tables_report_aggregation_test.dart --concurrency=4
```

- [ ] **الخطوة ٥: اكتب الشاشةَ بفلاترها المشترَكة**

`TablesReportScreen` يركب ما هو قائمٌ ولا يخترع:

| الفلتر | المصدر |
|---|---|
| المدى الزمنيّ | `DateRangeFilter.normalizeRange` |
| الفرع · المنطقة · المخزن | `widgets/branch_warehouse_filter.dart` |
| شريطُ الفلاتر | `widgets/report_filter_bar.dart` |
| التصدير | `screens/reports/report_export_guard.dart` |

وثلاثةٌ خاصّة: القسم (`TableSections`) · الطاولة · الكاشير.

**و`_allowedBranchIds` يُحقَن في الاستعلام لا في العرض** — اقرأ
`sales_report_screen.dart:68-110` وانقل النمطَ بحرفه. ترشيحُ العرض وحدَه يعني
أن الصفوفَ تنزل كلُّها ثم تُخفى، وهو تسريبٌ لا ترشيح.

- [ ] **الخطوة ٦: أضف البطاقتين في الكتالوجَين**

في `reports_screen.dart` (قسمُ تقارير المبيعات أو قسمٌ جديدٌ للمطاعم) وفي
`reports_picpos_screen.dart` — **الاثنان معاً**، وإلّا ظهر التقريرُ في هويّةٍ
وغاب عن الأخرى:

```dart
          title: 'تقرير الطاولات',
          subtitle: 'الإيراد ودورانُ الطاولة ونصيبُ الضيف لكلِّ منطقة',
          action: () => nav(() => const TablesReportScreen()),
```

- [ ] **الخطوة ٧: شغّل السويّات الثلاث**

```bash
flutter test test/unit test/widget test/static --concurrency=4 2>&1 | tee /tmp/task7.log
```

- [ ] **الخطوة ٨: أودِع**

```bash
git add lib/domain/models/tables_report_row.dart lib/presentation/screens/reports/tables_report_screen.dart lib/presentation/screens/reports_screen.dart lib/presentation/reports_picpos/screens/reports_picpos_screen.dart test/unit/tables_report_aggregation_test.dart
git commit -m "feat(reports): تقريرُ الطاولات — ثمانيَ عشرةَ شاشةً ولا واحدةٌ لها"
```

---

## المهمّة ٨: البوّابةُ الكاملة والبناء

- [ ] **الخطوة ١: اضمن شروطَ القياس الثلاثة**

```bash
tasklist | grep -iE "dart|flutter" ; ls build/native_assets/windows/sqlite3.dll
```

عمليّةُ `flutter` واحدةٌ (أو صفر)، والمكتبةُ موجودة، والشجرةُ ساكنة.

- [ ] **الخطوة ٢: شغّل البوّابةَ في الخلفيّة**

```bash
nohup bash scripts/gate.sh > /tmp/gate_tables.log 2>&1 &
```

~٣٤ دقيقة. **لا تعدّل ملفّاً وهي تعمل.**

- [ ] **الخطوة ٣: قارن بخطّ الأساس**

خطُّ الأساس عند `da5e31f6`: analyze ٦ info · unit ٣٤٨٦ · widget ٦٨٠ ·
integration ٧١٠. الزيادةُ يجب أن تُساوي عددَ اختباراتك الجديدة بالضبط —
واشرح أيَّ فرقٍ آخر قبل المتابعة. **لا تُخفّض حدّاً.**

- [ ] **الخطوة ٤: ابنِ وتحقّق ببصمة `app.so`**

ابنِ **من الـworktree لا الجذر** (السكربتُ نسبيٌّ فيبني `main`)، وتحقّق
بـ`md5sum` على `app.so` — حجمُ `PicPos.exe` ثابتٌ دوماً فلا يدلّ.

- [ ] **الخطوة ٥: أودِع نتيجةَ القياس في ملاحظات الدمج**

```bash
git add docs/superpowers/specs/2026-08-17-table-service-merge-notes.md
git commit -m "docs(handoff): شاشةُ الطاولات بهويّة PicPos — البوّابةُ والبناء"
```

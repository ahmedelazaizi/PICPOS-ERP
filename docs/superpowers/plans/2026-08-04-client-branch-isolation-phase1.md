# المرحلة ١ — حصر الفروع على أجهزة العملاء · خطة التنفيذ

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** إغلاق حدّ البيانات الأساسية على جهاز العميل — `/api/sync/pull`
يقصّ `branches`/`warehouses`/`safes`/`cost_centers` على فرع الجهاز، ولا يُلغي
دخولُ أدمن هذا القصّ.

**Architecture:** كل التغييرات على **جانب الخادم ومسار المزامنة** — لا شاشات
ولا سكيما. مُنشئ شرط `WHERE` في `_getSyncPull` **يدعم `OR IS NULL` أصلاً**
(`api_handler.dart:2242`)، لذا ثلاثة من الجداول الأربعة تحتاج **مدخلاً في
خريطة واحدة فقط**. `cost_centers` وحده يحتاج منطقاً جديداً (مجموعة مشتقّة).
G2 يُغلَق باستبدال المطابقة النصّية على اسم الدور بعلَم `isSystemRole` حقيقي.

**Tech Stack:** Dart · Flutter · drift 2.32.1 · shelf · PostgreSQL 18.4 ·
`flutter_test`

**المواصفة المعتمدة:**
`docs/superpowers/specs/2026-08-03-client-branch-isolation-phase1-design.md`
(بعد تصحيحات §٧ — كوميت `626c3964`).

---

## Global Constraints

- **الفرع:** `claude/postgres-go-handoff-b8bbe4`. تحقّق قبل أي شغل:
  `git rev-list --left-right --count HEAD...origin/claude/postgres-go-handoff-b8bbe4`
- **`build_runner` متجمّد في جلسات الوكيل** — ممنوع أي تغيير سكيما، وممنوع
  تعديل `database.g.dart` يدوياً.
- **`flutter test` ينهار عند التوازي** — `--concurrency=1` دائماً.
- **أمر سويّة PG** (استبدل `<pw>` بكلمة سر الخادم المحلي):
  ```bash
  PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1
  ```
- ⚠️ `bootPgTestSchema()` ينفّذ `DROP SCHEMA public CASCADE`. **قاعدة
  `picpos` فقط** — لا `uralcash` ولا `Avalon`، فكلاهما على نفس الخادم وفيه
  بيانات.
- **خط الأساس الحاكم** — طابِقه بعد كل جولة:

  | السويّة | العدد |
  |---|---|
  | `unit`+`data`+`structural`+`services` | ٢٥٢٥ · صفر فاشل |
  | `test/integration` | ٦٤١ · صفر فاشل |
  | `test/integration_pg` | ١٩ · صفر فاشل (يرتفع مع كل مهمة) |
  | `flutter analyze lib test` | ٦ `info` |

- **قاعدة الأحمر أولاً — بلا استثناء.** بعد كتابة كل اختبار، شغّله **قبل**
  الإصلاح وتأكّد أنه أحمر **للسبب المقصود** (اقرأ نصّ الفشل، لا مجرد
  لونه). في جلسة 2026-08-03 مرّ تأكيدان بدون الإصلاح وكادا يُشحنان.
- **«صفر سطر في السجل» ليس دليلاً** بلا ضبط موجب. `debugPrint` يُخنق تحت
  الحمل.
- عربي مصري في الردود ورسائل الكوميت؛ الكود والأسماء إنجليزي. التعليقات
  تشرح **لماذا** لا **ماذا**.
- كوميت منفصل لكل مهمة، ورسالته تشرح الأثر **بالأرقام**.
- ⚠️ **تحقّق من توقيع كل `*Companion.insert` قبل تشغيله.** المراجعة الذاتية
  لهذه الخطة أمسكت خطأين كانا سيمنعان التصريف: `SalesInvoicesCompanion`
  يتطلّب `warehouseId` و`userId` و`invoiceDate` ولا يملك `totalAmount`
  إطلاقاً (الاسم `total` وله default)، و`CostCenters.code` مطلوب بلا قيمة
  افتراضية. جلسة 2026-08-03 شحنت وصفة **لم تكن لتتكمبايل أصلاً**
  (`col.defaultConstraints`). افتح ملف الجدول في
  `lib/data/database/tables/` واقرأ الأعمدة، لا تخمّنها من الاسم.

---

## File Structure

| الملف | المسؤولية | المهام |
|---|---|---|
| `lib/services/api/api_handler.dart` | خريطة الحصر + الاشتقاق العكسي + العدّاد | ١·٢·٣ |
| `lib/data/database/sync_interceptor.dart` | علَم `isSystemRole` بدل المطابقة النصّية | ٤ |
| `lib/services/server_proxy.dart` | `_branchScopeQueryParam` يفشل مقفولاً | ٤ |
| `lib/data/database/extensions/branch_scope_cleanup_extension.dart` | إصلاح التنظيف المرتدّ | ٥ |
| `test/integration_pg/sync_pull_master_scope_pg_test.dart` | **جديد** — الحالات ١·٢·٣·٧ | ١·٢·٣ |
| `test/integration_pg/client_branch_scope_g2_pg_test.dart` | **جديد** — الحالات ٤·٥·٦ | ٤ |
| `test/unit/branch_scope_cleanup_test.dart` | **جديد** — الحالتان ٨·٩ | ٥ |

**ترتيب المهام مقصود:** ١→٣ تبني الحصر، ٤ تمنع إلغاءه، ٥ مستقلّة تماماً
(يمكن تنفيذها بالتوازي).

---

## Task 1: حصر `warehouses` و`safes`

**Files:**
- Modify: `lib/services/api/api_handler.dart:2107-2113`
- Test: `test/integration_pg/sync_pull_master_scope_pg_test.dart` (Create)

**Interfaces:**
- Consumes: `bootPgTestSchema()` من `_support/pg_fixture.dart` · `ApiHandler(db)`
- Produces: مدخلان في `_syncPullBranchColumn` · دالة الاختبار المساعدة
  `pull(String table, {int? branchId, int? userId})` تُعاد في المهام ٢ و٣

**السياق الحاسم — اقرأه قبل أن تكتب سطراً:**

مُنشئ الشرط في `api_handler.dart:2241-2244` **موجود بالفعل** وهو:

```dart
if (branchFilterActive) {
  conditions.add('($branchCol = ? OR $branchCol IS NULL)');
  vars.add(Variable.withInt(branchId));
}
```

⇒ `OR IS NULL` الذي قرّره المالك **منفَّذ مسبقاً**. المطلوب هنا **مدخلان
فقط**، لا منطق جديد. المواصفة (§٣-١) قالت «لا يكفي إضافة أربعة أسطر» — ذلك
صحيح لـ`cost_centers` وحده (المهمة ٣).

⚠️ **الخطر الوحيد:** إضافة جدول بلا عمود `branch_id` إلى هذه الخريطة تقتل
DeltaPull بـ`column "branch_id" does not exist` كل دقيقة، متنكّراً في صورة
بطء الشاشات (حادثة 2026-05-05، موثّقة في `api_handler.dart:2087-2089`).
تحقّق: `Warehouses.branchId` (`inventory_tables.dart:48`) و`Safes.branchId`
(`treasury_settings_tables.dart:16`) — **كلاهما موجود و`nullable()`**.

- [ ] **Step 1: اكتب ملف الاختبار الفاشل**

Create `test/integration_pg/sync_pull_master_scope_pg_test.dart`:

```dart
// المرحلة ١ / G1 — حصر البيانات الأساسية على `/api/sync/pull`.
//
// قبل الإصلاح: `_syncPullBranchColumn` يحتوي خمسة جداول تعاملية فقط، فسحب
// `warehouses` بـ`branch_id=1` يعيد مخازن كل الفروع. DeltaPull يعمل كل
// دورة ⇒ يعيد ملء قاعدة العميل ببيانات الشركة كاملة، مُلغياً حصر المزامنة
// الكاملة الذي يعمل بشكل صحيح.
@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get(); // اطبع أخطاء الترحيل مبكراً
  });

  tearDownAll(() async => fx.tearDown());

  setUp(() async {
    await fx.db.delete(fx.db.warehouses).go();
    await fx.db.delete(fx.db.safes).go();
    await fx.db.delete(fx.db.userBranchAccess).go();
    await fx.db.delete(fx.db.users).go();
    await fx.db.delete(fx.db.roles).go();
    await fx.db.delete(fx.db.branches).go();

    // فرعان حقيقيان — PostgreSQL ينفّذ الـFK الذي كان SQLite يتجاهله.
    await fx.db.customStatement(
      "INSERT INTO branches (id, name) VALUES (1,'فرع أ'),(2,'فرع ب') "
      'ON CONFLICT (id) DO NOTHING',
    );
    handler = ApiHandler(fx.db);
  });

  /// يستدعي `/api/sync/pull` كمستخدم مُعرَّف. حقن الهوية عبر
  /// `request.change(context: ...)` هو ما يفعله `api_auth_middleware:139`
  /// بعد التحقّق من التوكن — بدونه `_extractBranchId` يرى مستدعياً بلا
  /// هوية ويسلك مساراً مختلفاً تماماً، فيصير الاختبار بلا معنى.
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    int? branchId,
    int? userId,
  }) async {
    final qs = branchId == null ? '' : '&branch_id=$branchId';
    var request = shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/sync/pull?table=$table$qs'),
    );
    if (userId != null) {
      request = request.change(context: {ApiUserCtx.userIdKey: userId});
    }
    final response = await handler.buildRouter().call(request);
    final body = jsonDecode(await response.readAsString())
        as Map<String, dynamic>;
    return (body['rows'] as List).cast<Map<String, dynamic>>();
  }

  /// مستخدم مقيَّد على [branchId] — يحتاج صف `userBranchAccess` وإلا
  /// عاملَه `_extractBranchId` كـ«مُساء التزويد» وقصّه على السنتينل.
  Future<void> seedScopedUser(int userId, int branchId) async {
    await fx.db.into(fx.db.roles).insert(
          RolesCompanion.insert(name: 'كاشير')
              .copyWith(id: const d.Value(9)),
        );
    await fx.db.into(fx.db.users).insert(
          UsersCompanion.insert(
            username: 'u$userId',
            passwordHash: 'h',
            displayName: 'u$userId',
            roleId: const d.Value(9),
          ).copyWith(id: d.Value(userId)),
        );
    await fx.db.into(fx.db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(
            userId: userId,
            branchId: branchId,
          ),
        );
  }

  group('G1 — الجداول الأساسية تُحصَر على الفرع', () {
    test('warehouses: الفرع ١ لا يرى مخزن الفرع ٢', () async {
      await seedScopedUser(10, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 10);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(
        names,
        isNot(contains('مخزن ب')),
        reason: 'مخزن الفرع ٢ تسرّب لجهاز مربوط بالفرع ١ — هذا هو G1',
      );
    });

    test('safes: الفرع ١ لا يرى خزنة الفرع ٢', () async {
      await seedScopedUser(11, 1);
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('safes', branchId: 1, userId: 11);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('خزنة أ'));
      expect(names, isNot(contains('خزنة ب')));
    });

    test('الصفوف بلا فرع تظل ظاهرة (قرار المالك §٢-ب)', () async {
      await seedScopedUser(12, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن يتيم'),
          ); // branchId يبقى NULL
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 12);
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        contains('مخزن يتيم'),
        reason: 'الحصر الصارم يُخفي مخازن مشروعة من أجهزة قائمة',
      );
      expect(names, isNot(contains('مخزن ب')));
    });
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه أحمر للسبب المقصود**

```bash
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/sync_pull_master_scope_pg_test.dart --tags pg --run-skipped --concurrency=1
```

المتوقَّع: أول اختبارين **يفشلان** بـ`Expected: not contains 'مخزن ب'`.
الثالث **ينجح من الآن** — لا يوجد حصر أصلاً فكل شيء ظاهر؛ قيمته تظهر كحارس
ارتداد بعد الإصلاح، وهذا مقصود ومُوثَّق.

⚠️ لو فشل الاختبار بـ`rows` فارغة تماماً، فالسبب هوية مفقودة لا حصراً
شغّالاً — راجع حقن `ApiUserCtx.userIdKey`.

- [ ] **Step 3: أضف المدخلين**

في `api_handler.dart:2107`:

```dart
  static const _syncPullBranchColumn = <String, String>{
    'sales_invoices': 'branch_id',
    'purchase_invoices': 'branch_id',
    'journal_entries': 'branch_id',
    'stock_movements': 'branch_id',
    'activity_logs': 'branch_id',
    // المرحلة ١ / G1 — البيانات الأساسية. بلا هذين المدخلين كان
    // `/api/sync/pull` يعيد كل الصفوف، وDeltaPull يعيد ملء قاعدة العميل
    // ببيانات الشركة كل دورة، مُلغياً حصر المزامنة الكاملة الذي يعمل
    // بشكل صحيح في `sync_service.dart:594-601`.
    //
    // ⚠️ العمود موجود ومتحقَّق منه في drift — `Warehouses.branchId`
    // (inventory_tables.dart:48) و`Safes.branchId`
    // (treasury_settings_tables.dart:16). لا تُضف جدولاً هنا بلا التحقّق:
    // عمود مفقود يقتل DeltaPull كل دقيقة بـ`column "branch_id" does not
    // exist` متنكّراً في صورة بطء الشاشات (حادثة 2026-05-05 أعلاه).
    'warehouses': 'branch_id',
    'safes': 'branch_id',
  };
```

- [ ] **Step 4: شغّل الاختبار وتأكّد أنه أخضر**

نفس الأمر. المتوقَّع: **٣ ناجح · صفر فاشل**.

- [ ] **Step 5: شغّل سويّة PG كاملة — لا ارتداد**

```bash
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1
```

المتوقَّع: **٢٢ ناجح · صفر فاشل** (١٩ + ٣ جديدة). أي رقم آخر = جولة ملوّثة،
أوقِف وشخّص قبل المتابعة.

- [ ] **Step 6: كوميت**

```bash
git add lib/services/api/api_handler.dart test/integration_pg/sync_pull_master_scope_pg_test.dart
git commit -m "fix(branch-scope): حصر warehouses وsafes على فرع الجهاز

مدخلان في _syncPullBranchColumn. قبلهما كان /api/sync/pull يعيد مخازن
وخزائن كل الفروع، وDeltaPull يعيد ملء قاعدة العميل كل دورة.
سويّة PG: ١٩ ⇒ ٢٢ ناجح · صفر فاشل."
```

---

## Task 2: حصر `branches` على `id`

**Files:**
- Modify: `lib/services/api/api_handler.dart` (الخريطة نفسها)
- Test: `test/integration_pg/sync_pull_master_scope_pg_test.dart` (Modify)

**Interfaces:**
- Consumes: `pull(...)` و`seedScopedUser(...)` من المهمة ١
- Produces: مدخل `'branches': 'id'`

**لماذا مهمة منفصلة:** الحصر هنا على **المفتاح الأساسي** لا على `branch_id`.
الشرط العام يصير `(id = ? OR id IS NULL)` — والذراع الثانية **ميتة** لأن
`id` مفتاح أساسي لا يكون NULL. هذا صحيح وظيفياً وبلا تكلفة، لكنه يستحق
تعليقاً صريحاً وإلا بدا خطأً لمن يقرأه لاحقاً.

- [ ] **Step 1: أضف الاختبار الفاشل**

أضف داخل `group('G1 ...')` في نفس الملف:

```dart
    test('branches: الجهاز يرى فرعه فقط', () async {
      await seedScopedUser(13, 1);

      final rows = await pull('branches', branchId: 1, userId: 13);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('فرع أ'));
      expect(
        names,
        isNot(contains('فرع ب')),
        reason: 'قائمة الفروع كاملة تصل لجهاز مربوط بفرع واحد',
      );
    });
```

- [ ] **Step 2: شغّل وتأكّد أنه أحمر**

```bash
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/sync_pull_master_scope_pg_test.dart --tags pg --run-skipped --concurrency=1
```

المتوقَّع: فشل بـ`Expected: not contains 'فرع ب'`.

- [ ] **Step 3: أضف المدخل**

بعد `'safes': 'branch_id',` في نفس الخريطة:

```dart
    // `branches` يرتبط بالفرع بمفتاحه الأساسي، لا بعمود `branch_id`.
    // الشرط العام (`api_handler.dart:2242`) ينتج
    // `(id = ? OR id IS NULL)` — والذراع الثانية ميتة لأن `id` مفتاح
    // أساسي. مقصود ومتروك: تخصيص المُنشئ لجدول واحد يكلّف أكثر مما
    // يوفّر، والذراع الميتة بلا أثر على الخطة التنفيذية.
    'branches': 'id',
```

- [ ] **Step 4: شغّل وتأكّد أنه أخضر**

نفس أمر Step 2. المتوقَّع: **٤ ناجح · صفر فاشل**.

- [ ] **Step 5: السويّة الكاملة**

المتوقَّع: **٢٣ ناجح · صفر فاشل**.

- [ ] **Step 6: كوميت**

```bash
git add lib/services/api/api_handler.dart test/integration_pg/sync_pull_master_scope_pg_test.dart
git commit -m "fix(branch-scope): حصر branches على مفتاحها الأساسي

الحصر بـ`id` لا `branch_id`. سويّة PG: ٢٢ ⇒ ٢٣ ناجح · صفر فاشل."
```

---

## Task 3: `cost_centers` — الاشتقاق العكسي

**Files:**
- Modify: `lib/services/api/api_handler.dart:2192-2199` (منطق الحصر) و
  `:2234-2244` (بناء الشرط)
- Test: `test/integration_pg/sync_pull_master_scope_pg_test.dart` (Modify)

**Interfaces:**
- Consumes: `pull(...)` و`seedScopedUser(...)` من المهمة ١
- Produces: `Future<List<int>> _resolveBranchCostCenterIds(int branchId)` —
  تُعيد معرّفات مراكز تكلفة الفرع (فرعه + مخازنه + خزائنه)، بلا تكرار.

**التصميم:** `CostCenters` **لا تملك `branchId`** (`accounting_tables.dart:107`)
وتعديل السكيما يتطلّب `build_runner` المتجمّد. لكن الربط العكسي موجود:
`Branches.costCenterId` · `Warehouses.costCenterId` · `Safes.costCenterId`.
⇒ مراكز تكلفة الفرع = مركز الفرع ∪ مراكز مخازنه ∪ مراكز خزائنه. هذا نفس ما
يحسبه `clientScopeProvider:47-56`.

⚠️ **الشرط هنا `IN (...)` لا `= ?`** — فلا يمكن التعبير عنه بمدخل في
الخريطة. وإذا كانت المجموعة فارغة، **يجب ألّا يتحوّل ذلك إلى «بلا حصر»**؛
استخدم `IN (-1)` تماشياً مع سنتينل `_kNoBranchAccess` القائم (`:1902`).

- [ ] **Step 1: أضف الاختبار الفاشل**

```dart
    test('cost_centers: مشتقّة عكسياً من الفرع ومخازنه وخزائنه', () async {
      await seedScopedUser(14, 1);

      // ⚠️ `CostCenters.code` مطلوب وبلا قيمة افتراضية
      // (accounting_tables.dart:109) — إغفاله يفشل بـNOT NULL لا بمنطق
      // الحصر، فيبدو الاختبار أحمر للسبب الخطأ.
      await fx.db.customStatement(
        'INSERT INTO cost_centers (id, code, name) VALUES '
        "(101,'CC101','مركز الفرع أ'),(102,'CC102','مركز مخزن أ'),"
        "(103,'CC103','مركز خزنة أ'),(201,'CC201','مركز الفرع ب') "
        'ON CONFLICT (id) DO NOTHING',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 101 WHERE id = 1',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 201 WHERE id = 2',
      );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(102),
            ),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(103),
            ),
          );

      final rows = await pull('cost_centers', branchId: 1, userId: 14);
      final ids = rows.map((r) => r['id']).toSet();

      expect(ids, containsAll(<int>[101, 102, 103]));
      expect(
        ids,
        isNot(contains(201)),
        reason: 'مركز تكلفة الفرع ٢ تسرّب — الاشتقاق العكسي لا يعمل',
      );
    });

    test('cost_centers: فرع بلا أي ارتباط ⇒ صفر صفوف لا كل الصفوف', () async {
      await seedScopedUser(15, 1);
      await fx.db.customStatement(
        "INSERT INTO cost_centers (id, code, name) VALUES "
        "(301,'CC301','مركز غريب') ON CONFLICT (id) DO NOTHING",
      );

      final rows = await pull('cost_centers', branchId: 1, userId: 15);

      expect(
        rows,
        isEmpty,
        reason: 'مجموعة فارغة انقلبت إلى «بلا حصر» — نفس فئة الفشل المفتوح '
            'التي أغلقها سنتينل _kNoBranchAccess',
      );
    });
```

- [ ] **Step 2: شغّل وتأكّد أنه أحمر**

المتوقَّع: الأول يفشل بـ`not contains 201`، والثاني بـ`rows` غير فارغة.

- [ ] **Step 3: أضف دالة الاشتقاق**

بعد `_resolveBranchWarehouseIds` (`api_handler.dart:1975`):

```dart
  /// المرحلة ١ / G1 — مراكز تكلفة الفرع، مشتقّة **عكسياً**.
  ///
  /// `CostCenters` لا تملك `branchId` (accounting_tables.dart:107) وإضافته
  /// تتطلّب `build_runner` المتجمّد في بيئة الوكيل. لكن الربط العكسي قائم:
  /// الفرع ومخازنه وخزائنه يشير كلٌّ منها إلى مركز تكلفته. هذا نفس ما
  /// يحسبه `clientScopeProvider:47-56` على الواجهة.
  ///
  /// تُعيد مجموعة فارغة عندما لا يرتبط الفرع بأي مركز — والمستدعي يترجم
  /// ذلك إلى سنتينل «صفر صفوف»، لا إلى «بلا حصر».
  Future<List<int>> _resolveBranchCostCenterIds(int branchId) async {
    final ids = <int>{};

    final branch = await (_db.select(_db.branches)
          ..where((b) => b.id.equals(branchId)))
        .getSingleOrNull();
    if (branch?.costCenterId != null) ids.add(branch!.costCenterId!);

    final warehouses = await (_db.select(_db.warehouses)
          ..where((w) => w.branchId.equals(branchId)))
        .get();
    for (final w in warehouses) {
      if (w.costCenterId != null) ids.add(w.costCenterId!);
    }

    final safes = await (_db.select(_db.safes)
          ..where((s) => s.branchId.equals(branchId)))
        .get();
    for (final s in safes) {
      if (s.costCenterId != null) ids.add(s.costCenterId!);
    }

    return ids.toList();
  }
```

- [ ] **Step 4: اربطها ببناء الشرط**

في `_getSyncPull`، بعد سطر `final bool branchFilterActive = ...` (`:2199`):

```dart
      // المرحلة ١ / G1 — `cost_centers` يُحصَر بمجموعة مشتقّة لا بعمود،
      // فلا يمكن التعبير عنه بمدخل في `_syncPullBranchColumn`.
      final bool costCenterScopeActive =
          table == 'cost_centers' && branchId != null;
      final List<int> scopedCostCenterIds = costCenterScopeActive
          ? await _resolveBranchCostCenterIds(branchId)
          : const <int>[];
```

ثم داخل قائمة الشروط، بعد كتلة `if (branchFilterActive)` (`:2244`):

```dart
      if (costCenterScopeActive) {
        if (scopedCostCenterIds.isEmpty) {
          // فرع بلا أي ارتباط. مجموعة فارغة يجب ألّا تنقلب إلى «بلا
          // حصر» — نفس فئة الفشل المفتوح التي أغلقها `_kNoBranchAccess`.
          conditions.add('id = ?');
          vars.add(Variable.withInt(_kNoBranchAccess));
        } else {
          final placeholders =
              List.filled(scopedCostCenterIds.length, '?').join(',');
          conditions.add('id IN ($placeholders)');
          vars.addAll(scopedCostCenterIds.map(Variable.withInt));
        }
      }
```

- [ ] **Step 5: شغّل وتأكّد أنه أخضر**

المتوقَّع: **٦ ناجح · صفر فاشل** في هذا الملف.

- [ ] **Step 6: السويّة الكاملة**

المتوقَّع: **٢٥ ناجح · صفر فاشل**.

- [ ] **Step 7: كوميت**

```bash
git add lib/services/api/api_handler.dart test/integration_pg/sync_pull_master_scope_pg_test.dart
git commit -m "fix(branch-scope): حصر cost_centers بالاشتقاق العكسي

مركز الفرع ∪ مراكز مخازنه ∪ مراكز خزائنه — بلا تغيير سكيما (build_runner
متجمّد). المجموعة الفارغة تُترجم لسنتينل صفر صفوف لا لـ«بلا حصر».
سويّة PG: ٢٣ ⇒ ٢٥ ناجح · صفر فاشل."
```

---

## Task 4: G2 — إغلاق تجاوز الأدمن على جهاز العميل

**Files:**
- Modify: `lib/data/database/sync_interceptor.dart:44-56`
- Modify: `lib/services/server_proxy.dart:1717-1724`
- Test: `test/integration_pg/client_branch_scope_g2_pg_test.dart` (Create)

**Interfaces:**
- Consumes: `SyncInterceptor.currentUserId` (`sync_interceptor.dart:44`)
- Produces: `static bool? currentUserIsSystemRole` — يضبطه متحكّم المصادقة
  عند الدخول من `roles.isSystemRole`، ويُمسَح عند الخروج.

**العطل:** `_branchScopeQueryParam` يُرجع `''` (بلا أي `branch_id`) في
حالتين، وكلتاهما تسريب:

1. `isCurrentUserAdmin` مطابقة **نصّية** على اسم الدور. المُطابِقات الخمس
   الفعلية (`sync_interceptor.dart:48-56`): `'admin'` · `'مدير النظام'` ·
   `'مسؤول'` · `'manager'` · `'مدير مالي'`. ⇒ **«مسؤول مبيعات» يُعامَل
   كأدمن كامل الصلاحية.**
2. `client_branch_id == null` ⇒ يُرجع `''` **يفشل مفتوحاً**. قرار المالك:
   يفشل مقفولاً.

> 🔴 **لا تستخدم «مدير مخزن» في الاختبار.** لا يطابق أياً من الخمس، فالاختبار
> يمرّ أخضر **بالإصلاح وبدونه**. هذا الخطأ كان في النسخة الأولى من المواصفة
> وصُحِّح في §٧-١.

- [ ] **Step 1: اكتب الاختبار الفاشل**

Create `test/integration_pg/client_branch_scope_g2_pg_test.dart`:

```dart
// المرحلة ١ / G2 — دخول «أدمن» على جهاز عميل كان يزيل `branch_id` من كل
// عمليات السحب. المطابقة النصّية على اسم الدور ليست صلاحية.
@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/services/server_proxy.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;

  setUpAll(() async {
    fx = await bootPgTestSchema();
  });

  tearDownAll(() async => fx.tearDown());

  setUp(() async {
    SharedPreferences.setMockInitialValues({'client_branch_id': 7});
    SyncInterceptor.currentUserId = null;
    SyncInterceptor.currentUserRole = null;
    SyncInterceptor.currentUserIsSystemRole = null;
  });

  group('G2 — تجاوز الأدمن مُغلق', () {
    test('«مسؤول مبيعات» لا يحصل على سحب غير مقيّد', () async {
      SyncInterceptor.currentUserId = 5;
      SyncInterceptor.currentUserRole = 'مسؤول مبيعات';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=7',
        reason: 'المطابقة النصّية على «مسؤول» منحت صلاحية كاملة لدور مبيعات',
      );
    });

    test('«مدير مالي» يتحصر (قرار المالك §٢)', () async {
      SyncInterceptor.currentUserId = 6;
      SyncInterceptor.currentUserRole = 'مدير مالي';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=7',
      );
    });

    test('مدير النظام وحده يُعفى — لإعداد البدء', () async {
      SyncInterceptor.currentUserId = 1;
      SyncInterceptor.currentUserRole = 'مدير النظام';
      SyncInterceptor.currentUserIsSystemRole = true;

      expect(await ServerProxy.instance.debugBranchScopeQueryParam(), '');
    });

    test('جهاز عميل بلا client_branch_id يفشل مقفولاً', () async {
      SharedPreferences.setMockInitialValues(const {}); // بلا ربط
      SyncInterceptor.currentUserId = 5;
      SyncInterceptor.currentUserRole = 'كاشير';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=-1',
        reason: 'جهاز غير مربوط سحب بلا قيد — هذا هو التسريب',
      );
    });
  });
}
```

- [ ] **Step 2: شغّل وتأكّد أنه أحمر**

```bash
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/client_branch_scope_g2_pg_test.dart --tags pg --run-skipped --concurrency=1
```

المتوقَّع: فشل تصريف على `currentUserIsSystemRole` و
`debugBranchScopeQueryParam` — كلاهما غير موجود بعد. **هذا أحمر مقبول
للخطوة الأولى فقط**؛ بعد Step 3 يجب أن يصير الأحمر **تأكيدياً** (`''` بدل
`'&branch_id=7'`) لا فشل تصريف. لا تتجاوز حتى ترى الشكل الثاني.

- [ ] **Step 3: أضف العلَم إلى `SyncInterceptor`**

بعد `static int? currentUserId;` (`sync_interceptor.dart:44`):

```dart
  /// المرحلة ١ / G2 — علَم `roles.isSystemRole` للمستخدم الحالي، يضبطه
  /// متحكّم المصادقة عند الدخول ويمسحه عند الخروج (نفس نمط
  /// [currentUserRole] و[currentUserId]).
  ///
  /// يحلّ محلّ [isCurrentUserAdmin] في مسار حصر المزامنة تحديداً.
  /// المطابقة النصّية على اسم الدور **ليست صلاحية**: «مسؤول مبيعات»
  /// يطابق `contains('مسؤول')` فيُعامَل كأدمن كامل الصلاحية. العلَم يقرأ
  /// السمة المقصودة من قاعدة البيانات بدل تخمينها من اسم يكتبه المستخدم.
  ///
  /// `null` قبل الدخول ⇒ يُعامَل كـ«ليس مدير نظام» (يفشل مقفولاً).
  static bool? currentUserIsSystemRole;
```

⚠️ اترك `isCurrentUserAdmin` كما هي — لها مستدعون آخرون خارج نطاق المرحلة ١.

- [ ] **Step 4: أعد كتابة `_branchScopeQueryParam`**

في `server_proxy.dart:1717`:

```dart
  /// المرحلة ١ / G2 — يبني `&branch_id=<id>` لنداءات المزامنة المحصورة.
  ///
  /// **يُرجع `''` (بلا حصر) لمدير النظام وحده**، لأن إعداد البدء يحتاج
  /// قراءة البيانات الأساسية كاملة قبل ربط الجهاز بفرع.
  ///
  /// كان يستعمل [SyncInterceptor.isCurrentUserAdmin] — مطابقة نصّية على
  /// اسم الدور تمنح «مسؤول مبيعات» صلاحية كاملة. وكان يُرجع `''` أيضاً
  /// عندما لا يكون الجهاز مربوطاً بفرع، أي **يفشل مفتوحاً**: جهاز غير
  /// مُعَدّ كان يسحب بيانات الشركة كاملة. كلاهما مُغلق الآن.
  Future<String> _branchScopeQueryParam() async {
    if (SyncInterceptor.currentUserIsSystemRole == true) return '';

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('client_branch_id');
    if (id == null) {
      // يفشل مقفولاً. السنتينل يطابق `ApiHandler._kNoBranchAccess` فيقصّ
      // الخادمُ الصفوفَ إلى صفر بدل أن يعيدها كلها.
      return '&branch_id=-1';
    }
    return '&branch_id=$id';
  }

  /// منفذ اختبار لـ[_branchScopeQueryParam]. المنطق أعلاه هو حدّ أمني،
  /// واختباره عبر نداء HTTP كامل يخلط فشله بفشل الشبكة.
  @visibleForTesting
  Future<String> debugBranchScopeQueryParam() => _branchScopeQueryParam();
```

تأكّد من وجود `import 'package:flutter/foundation.dart';` في الملف (لـ
`@visibleForTesting`)؛ أضفه إن غاب.

- [ ] **Step 5: اضبط العلَم عند الدخول والخروج**

ابحث عن مواضع ضبط `SyncInterceptor.currentUserRole`:

```bash
grep -rn "SyncInterceptor.currentUserRole = " lib/
```

في **كل** موضع ضبط، أضف بجواره ضبط `currentUserIsSystemRole` من
`roles.isSystemRole` للدور المُحمَّل؛ وفي كل موضع مسح (`= null`) امسحه
أيضاً. **لا تترك موضعاً** — موضع منسي يعني مستخدماً يُعامَل كغير مدير نظام
(آمن) أو يحتفظ بعلَم جلسة سابقة (**غير آمن**).

- [ ] **Step 6: شغّل وتأكّد أنه أخضر**

المتوقَّع: **٤ ناجح · صفر فاشل**.

- [ ] **Step 7: تحقّق إزالة الإصلاح**

أعِد `if (SyncInterceptor.isCurrentUserAdmin) return '';` مؤقتاً مكان السطر
الأول، وشغّل. **يجب أن يحمرّ اختبارا «مسؤول مبيعات» و«مدير مالي».** إن بقيا
أخضرين فالاختبار بلا أسنان — أصلحه قبل المتابعة. أعِد الإصلاح بعدها.

- [ ] **Step 8: السويّة الكاملة + التحليل**

المتوقَّع: `integration_pg` **٢٩ ناجح · صفر فاشل**؛
`flutter analyze lib test` **٦ `info`**.

- [ ] **Step 9: كوميت**

```bash
git add lib/data/database/sync_interceptor.dart lib/services/server_proxy.dart test/integration_pg/client_branch_scope_g2_pg_test.dart
git commit -m "fix(branch-scope): إغلاق تجاوز الأدمن على جهاز العميل (G2)

المطابقة النصّية على اسم الدور استُبدلت بعلَم roles.isSystemRole: «مسؤول
مبيعات» كان يطابق contains('مسؤول') فيسحب بلا قيد. وجهاز بلا
client_branch_id كان يفشل مفتوحاً — صار يفشل مقفولاً بسنتينل -1.
سويّة PG: ٢٥ ⇒ ٢٩ ناجح · صفر فاشل."
```

---

## Task 5: إصلاح آلية التنظيف المرتدّة

**Files:**
- Modify: `lib/data/database/extensions/branch_scope_cleanup_extension.dart:35-84`
- Test: `test/unit/branch_scope_cleanup_test.dart` (Create)

**Interfaces:**
- Consumes: `AppDatabase` (ذاكرة — لا يحتاج PG)
- Produces: `_scopedTables` بخمسة مداخل · `dryRunForeignBranchCounts` لا
  يبلع فشل جدول

**العطل المقيس:** `_scopedTables` يعلن أنه «يطابق `_syncPullBranchColumn`
بالضبط» وفيه **عشرة** جداول مقابل **خمسة**. الخمسة الزائدة بلا `branchId`
في drift:

| الجدول | تعريف drift |
|---|---|
| `sales_orders` | `sales_purchase_tables.dart:380` |
| `purchase_orders` | `sales_purchase_tables.dart:329` |
| `held_orders` | `sales_purchase_tables.dart:286` |
| `quotations` | `quotation_tables.dart:6` |
| `commercial_papers` | `commercial_finance_tables.dart:11` |

- `dryRunForeignBranchCounts:74` — الـ`catch` يطبع فقط ⇒ فشل **صامت** وعدّ
  **ناقص** يسبق حذفاً وافق عليه المستخدم بناءً عليه.
- `wipeForeignBranchData:126` — الـ`catch` يعمل **`rethrow`** داخل
  `transaction`، وترتيب `Map` هو ترتيب الإدخال ⇒ ثالث مدخل `sales_orders`
  يرمي ⇒ **ارتداد دائم**. الزر في `branch_scope_admin_dialog.dart:346`
  لم يحذف صفاً قط.

⚠️ **خارج النطاق عمداً:** توسيع التنظيف للجداول الأساسية الأربعة — حذف مخزن
محلياً قد يكسر FK لصفوف تعاملية تشير إليه. قرار منفصل (§٥ من المواصفة).

- [ ] **Step 1: اكتب الاختبار الفاشل**

Create `test/unit/branch_scope_cleanup_test.dart`:

```dart
// المرحلة ١ / §٣-٥ — آلية تنظيف البيانات المتسرّبة كانت مرتدّة دائماً.
//
// `_scopedTables` أعلن أنه يطابق `_syncPullBranchColumn` وفيه ١٠ جداول
// مقابل ٥؛ الخمسة الزائدة بلا عمود `branch_id` في drift. الاستعلام عليها
// يرمي، و`wipeForeignBranchData` يعمل rethrow داخل transaction ⇒ الزر في
// شاشة الإعدادات لم يحذف صفاً قط.

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/branch_scope_cleanup_extension.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    // فرعان + مخزن + مستخدم: `SalesInvoices.warehouseId` و`.userId`
    // **مطلوبان وغير nullable** (sales_purchase_tables.dart:181,186)،
    // فبدونهما لا يتصرّف الإدخال أصلاً.
    await db.customStatement(
      "INSERT INTO branches (id, name) VALUES (1,'فرع أ'),(2,'فرع ب')",
    );
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن الاختبار')
              .copyWith(id: const d.Value(1), branchId: const d.Value(1)),
        );
    await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير').copyWith(id: const d.Value(1)),
        );
    await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'u1',
            passwordHash: 'h',
            displayName: 'u1',
            roleId: const d.Value(1),
          ).copyWith(id: const d.Value(1)),
        );
  });

  tearDown(() async => db.close());

  /// فاتورة مبيعات على [branchId] — `sales_invoices` أول مدخل في الخريطة
  /// ولها عمود `branch_id` فعلاً، فهي المسار السليم الذي يثبت أن الحذف
  /// يعمل حين لا يرتدّ.
  ///
  /// ⚠️ الحقول المطلوبة أربعة: `invoiceNumber` · `warehouseId` · `userId` ·
  /// `invoiceDate`. **لا يوجد عمود `totalAmount`** — الاسم `total` وله
  /// قيمة افتراضية، فلا يُمرَّر في `insert`.
  Future<void> seedInvoice(int id, int branchId) async {
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-$id',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 4),
          ).copyWith(id: d.Value(id), branchId: d.Value(branchId)),
        );
  }

  test('wipeForeignBranchData يحذف فعلاً صفوف الفروع الأخرى', () async {
    await seedInvoice(1, 1);
    await seedInvoice(2, 2);

    final deleted = await db.wipeForeignBranchData({1});

    expect(
      deleted['sales_invoices'],
      1,
      reason: 'الترانزاكشن ارتدّت — sales_orders بلا عمود branch_id يرمي '
          'داخلها فيُلغى الحذف كله',
    );

    final remaining = await db.select(db.salesInvoices).get();
    expect(remaining.map((r) => r.id), [1]);
  });

  test('dryRunForeignBranchCounts لا يبلع فشل جدول', () async {
    await seedInvoice(1, 1);
    await seedInvoice(2, 2);

    final counts = await db.dryRunForeignBranchCounts({1});

    expect(counts['sales_invoices'], 1);
    expect(
      counts.keys,
      everyElement(isNot(anyOf(
        'sales_orders',
        'purchase_orders',
        'held_orders',
        'quotations',
        'commercial_papers',
      ))),
      reason: 'جدول بلا عمود branch_id ما زال في القائمة',
    );
  });
}
```

- [ ] **Step 2: شغّل وتأكّد أنه أحمر للسبب المقصود**

```bash
flutter test test/unit/branch_scope_cleanup_test.dart --concurrency=1
```

المتوقَّع: الاختبار الأول يفشل بـ`SqliteException ... no such column:
branch_id` من `sales_orders`. **اقرأ نصّ الفشل حرفياً** — فشل بسبب آخر
يعني أن التشخيص خاطئ، فحدّث التقرير قبل أي إصلاح.

- [ ] **Step 3: صحّح `_scopedTables`**

استبدل الخريطة (`:35-46`) بـ:

```dart
  /// خريطة الجدول → عمود الفرع. **يجب أن تطابق
  /// `api_handler._syncPullBranchColumn` بالضبط** — أي جدول يقصّه الخادم
  /// يُنظَّف هنا أيضاً.
  ///
  /// كانت تحوي `sales_orders` · `purchase_orders` · `held_orders` ·
  /// `quotations` · `commercial_papers` بناءً على ترحيل مُخطَّط لم يحدث
  /// قط: هذه الجداول **بلا `branchId` في drift**
  /// (sales_purchase_tables.dart:286,329,380 · quotation_tables.dart:6 ·
  /// commercial_finance_tables.dart:11). الاستعلام عليها يرمي، و
  /// [wipeForeignBranchData] يعمل rethrow داخل `transaction` ⇒ **ارتداد
  /// دائم**؛ الزر في `branch_scope_admin_dialog.dart:346` لم يحذف صفاً قط.
  ///
  /// الجداول بلا عمود فرع (`sales_invoice_items`, `journal_lines`,
  /// `safe_transactions`) غائبة عمداً — تُحصَر عبر سجلّها الأب ويتتالى
  /// حذفها عبر سلسلة الـFK.
  static const _scopedTables = <String, String>{
    'sales_invoices': 'branch_id',
    'purchase_invoices': 'branch_id',
    'journal_entries': 'branch_id',
    'stock_movements': 'branch_id',
    'activity_logs': 'branch_id',
  };
```

⚠️ الخريطة الآن نسخة من خريطة الخادم بعد المهام ١-٣ **باستثناء الجداول
الأساسية** — تلك خارج النطاق عمداً (مخاطرة FK).

- [ ] **Step 4: اجعل الدراي-رن لا يبلع الفشل**

استبدل الـ`catch` في `dryRunForeignBranchCounts` (`:74-76`) بـ:

```dart
      } catch (e) {
        // لا تبلع. عدّ ناقص هنا يسبق **حذفاً** يوافق عليه المستخدم بناءً
        // عليه، فالصمت أخطر من الفشل: الشاشة تقول «لا صفوف غريبة» بينما
        // الجدول لم يُستعلَم أصلاً.
        debugPrint('[BRANCH-CLEANUP-DRYRUN] $table failed: $e');
        rethrow;
      }
```

- [ ] **Step 5: شغّل وتأكّد أنه أخضر**

المتوقَّع: **٢ ناجح · صفر فاشل**.

- [ ] **Step 6: راجع المستدعي**

`branch_scope_admin_dialog.dart:291` صار يمكن أن يرمي من الدراي-رن. تأكّد
أنه يعرض رسالة خطأ للمستخدم بدل أن يتعطّل بصمت أو يُظهر «نظيف». عدّله إن
لزم، وأدرج التعديل في نفس الكوميت.

- [ ] **Step 7: البوابة الكاملة**

```bash
flutter test test/unit test/data test/structural test/services --concurrency=1
flutter test test/integration --concurrency=1
flutter analyze lib test
```

المتوقَّع: **٢٥٢٧** (٢٥٢٥ + ٢ جديدة) · **٦٤١** · **٦ `info`**.

- [ ] **Step 8: كوميت**

```bash
git add lib/data/database/extensions/branch_scope_cleanup_extension.dart lib/presentation/widgets/settings/branch_scope_admin_dialog.dart test/unit/branch_scope_cleanup_test.dart
git commit -m "fix(branch-scope): آلية تنظيف البيانات المتسرّبة كانت مرتدّة دائماً

_scopedTables فيها ١٠ جداول مقابل ٥ في خريطة الخادم؛ الخمسة الزائدة بلا
عمود branch_id في drift. wipeForeignBranchData يعمل rethrow داخل
transaction عند ثالث مدخل ⇒ الزر في شاشة الإعدادات لم يحذف صفاً قط.
والدراي-رن كان يبلع الفشل فيُظهر عدداً ناقصاً يسبق الحذف.
اختبارات الوحدة: ٢٥٢٥ ⇒ ٢٥٢٧ ناجح · صفر فاشل."
```

---

## Task 6: العدّاد التشخيصي + توثيق البنود المفتوحة

**Files:**
- Modify: `lib/services/api/api_handler.dart` (داخل `_getSyncPull`)
- Modify: `RELEASE_NOTES_2026-08-03.md`
- Test: `test/integration_pg/sync_pull_master_scope_pg_test.dart` (Modify)

**Interfaces:**
- Consumes: `rows` و`branchCol` من `_getSyncPull`
- Produces: سطر سجلّ `[BRANCH-SCOPE-NULL] table=<t> branch=<b> nullRows=<n>`

**لماذا:** `Warehouses.branchId` و`Safes.branchId` كلاهما `nullable()`، فالصف
بلا فرع **حالة مدعومة مستمرة** لا بقية قديمة تنقرض: أي مخزن يُنشَأ اليوم بلا
فرع يبقى مرئياً على كل الأجهزة للأبد. العدّاد يجعل التعرّض **مقيساً** بدل أن
يكون افتراضاً، قبل أي قرار تشديد لاحق.

⚠️ **ضبط موجب إلزامي.** لا تستنتج شيئاً من «صفر». أثبت أولاً أن العدّاد
يلتقط على مسار فيه صفوف يتيمة معروفة العدد — «صفر سطر في السجل» كان
استنتاجاً خاطئاً مرتين في جلسة 2026-08-03 قبل الضبط الموجب.

- [ ] **Step 1: اكتب الاختبار الفاشل (ضبط موجب أولاً)**

أضف إلى `sync_pull_master_scope_pg_test.dart`:

```dart
    test('العدّاد يحصي صفوف IS NULL — ضبط موجب', () async {
      await seedScopedUser(16, 1);
      // صفّان يتيمان معروفان بالعدد + واحد على الفرع. الضبط الموجب: لو
      // أعاد العدّاد صفراً هنا فالأداة لا تلتقط، فأي «صفر» لاحق بلا قيمة.
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'يتيم ١'),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'يتيم ٢'),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );

      await pull('warehouses', branchId: 1, userId: 16);

      expect(
        ApiHandler.debugLastNullBranchRowCount,
        2,
        reason: 'العدّاد لا يلتقط — أي «صفر» منه بلا قيمة',
      );
    });
```

- [ ] **Step 2: شغّل وتأكّد أنه أحمر**

المتوقَّع: فشل تصريف على `debugLastNullBranchRowCount`، ثم بعد Step 3 يجب
أن يصير الأحمر تأكيدياً لو كان المنطق خاطئاً.

- [ ] **Step 3: أضف العدّاد**

في `_getSyncPull`، بعد `final rows = hasMore ? ... : fetched;` (`:2264`):

```dart
      // المرحلة ١ / §٣-١ — قياس التعرّض الناتج عن ذراع `OR IS NULL`.
      //
      // `Warehouses.branchId` و`Safes.branchId` كلاهما `nullable()`، فالصف
      // بلا فرع حالة مدعومة مستمرة لا بقية قديمة: أي مخزن يُنشَأ اليوم بلا
      // فرع يبقى مرئياً على كل الأجهزة للأبد. نقيس الحجم قبل أي قرار
      // تشديد بدل أن نفترضه.
      if (branchFilterActive) {
        final nullRows =
            rows.where((r) => r.data[branchCol] == null).length;
        debugLastNullBranchRowCount = nullRows;
        if (nullRows > 0) {
          debugPrint('[BRANCH-SCOPE-NULL] table=$table '
              'branch=$branchId nullRows=$nullRows');
        }
      }
```

وأضف بجوار `_kNoBranchAccess` (`:1902`):

```dart
  /// عدد صفوف `IS NULL` في آخر سحب محصور — منفذ قياس للاختبار.
  /// `debugPrint` وحده لا يكفي: يُخنق تحت الحمل، فـ«صفر سطر في السجل»
  /// ليس دليلاً بلا هذا العدّاد.
  @visibleForTesting
  static int debugLastNullBranchRowCount = 0;
```

- [ ] **Step 4: شغّل وتأكّد أنه أخضر**

المتوقَّع: **٧ ناجح · صفر فاشل** في هذا الملف؛ `integration_pg` **٣٠**.

- [ ] **Step 5: وثّق البنود المفتوحة**

أضف إلى `RELEASE_NOTES_2026-08-03.md` تحت «يحتاج إجراءً منك»:

```markdown
### حصر الفروع على أجهزة العملاء — المرحلة ١

أُغلق حدّ البيانات الأساسية: `branches`/`warehouses`/`safes`/`cost_centers`
تُقصّ الآن على فرع الجهاز، ودخول أدمن لم يعد يلغي القصّ.

**باقٍ ويحتاج قراراً منك:**

- **البيانات المتسرّبة الموجودة لا تُحذف تلقائياً.** أجهزة عمل عليها أدمن
  قبل هذا الإصدار تحتفظ بصفوف فروع أخرى محلياً. آلية التنظيف كانت مرتدّة
  دائماً وأُصلحت — شغّلها من شاشة الإعدادات (تُظهر عدّاً قبل الحذف).
- **الجداول الأساسية غير مشمولة بالتنظيف** — حذف مخزن أو فرع محلياً قد
  يكسر FK لصفوف تعاملية تشير إليه. قرار منفصل.
- **صفوف `warehouses`/`safes` بلا فرع تبقى مرئية للجميع** بقرار واعٍ.
  السجلّ `[BRANCH-SCOPE-NULL]` يقيس حجمها؛ راجعه بعد أسبوع تشغيل.
- **المطابقة النصّية على اسم الدور** ما زالت في مواضعها الأخرى خارج مسار
  المزامنة. خارج نطاق المرحلة ١.

**المرحلتان ٢-٤ لم تبدآ:** الشاشات وفلاتر التقارير ما زالت تعرض بيانات
خارج الفرع. أخطرها **شاشة التحويل المخزني** — تُظهر المصدر والوجهة بلا حصر.
```

- [ ] **Step 6: البوابة الكاملة النهائية**

```bash
flutter test test/unit test/data test/structural test/services --concurrency=1
flutter test test/integration --concurrency=1
PG_TEST_DSN="postgres://postgres:<pw>@127.0.0.1:5432/picpos" flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1
flutter analyze lib test
git status --short
```

المتوقَّع: **٢٥٢٧** · **٦٤١** · **٣٠** · **٦ `info`** · الشجرة نظيفة.

- [ ] **Step 7: كوميت**

```bash
git add lib/services/api/api_handler.dart test/integration_pg/sync_pull_master_scope_pg_test.dart RELEASE_NOTES_2026-08-03.md
git commit -m "feat(branch-scope): عدّاد تعرّض صفوف بلا فرع + توثيق البنود المفتوحة

ذراع OR IS NULL قرار واعٍ من المالك، والعمودان nullable() فالصف بلا فرع
حالة مستمرة لا بقية قديمة. العدّاد يقيس الحجم بضبط موجب (صفّان يتيمان
معروفان) بدل الاستنتاج من «صفر سطر في السجل».
سويّة PG: ٢٩ ⇒ ٣٠ ناجح · صفر فاشل."
```

---

## بعد المهام الستّ

- [ ] **إعادة التصديق.** شغّل الوكيل `release-certification` وأعطه البنود
  المفتوحة **بصراحة**: البيانات المتسرّبة الباقية · الجداول الأساسية خارج
  التنظيف · المراحل ٢-٤ لم تبدأ · المطابقة النصّية في مواضعها الأخرى ·
  `clientScopeProvider` ما زال يفشل مفتوحاً وصارماً. **اطلب منه ألّا
  يجاملك.**
- [ ] **لا تبدأ المرحلة ٢** قبل أن تُقفل هذه وتُتحقّق. طول ما DeltaPull
  يملأ قاعدة العميل ببيانات الشركة، أي إصلاح شاشة تجميل.

### بنود المرحلة ٢ المسجَّلة من هذه المراجعة (لا تُغلَق بدونها)

- `clientScopeProvider:38,44` يستخدم `equals` **صارماً** بينما الخادم يمرّر
  `OR IS NULL` ⇒ الطرفان سيختلفان على «ما مخازن هذا الفرع» لحظة توصيل
  المزوّد.
- `clientScopeProvider:23-26` يُرجع `ClientScope.unrestricted` عند
  `branchId == null` ⇒ **يفشل مفتوحاً**، نقيض قرار المالك.
- `clientScopeProvider` **بلا أي مُنادٍ** — الآلية كُتبت ولم تُوصَّل.
- الذراع ٤ في `branchScopeProvider:150-173` **بلا أي اختبار**، و
  `branch_scope_mirror_test.dart:168-189` اسمه يوحي بتغطيتها وينجح عبر ذراع
  أخرى.

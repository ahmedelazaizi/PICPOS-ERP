# الخطةُ الأولى — المرتجع السريع والأساسُ المشترك

> **للعاملين الوكلاء:** مهارةٌ فرعيةٌ إلزامية: استعمل
> `superpowers:subagent-driven-development` (موصى به) أو
> `superpowers:executing-plans` لتنفيذ هذه الخطة مهمّةً مهمّة. الخطواتُ
> بصيغة صناديق التأشير (`- [ ]`) للتتبّع.

**الهدف:** زرٌّ في سلة نقطة البيع يحوّلها إلى مردود مبيعاتٍ حقيقيٍّ مربوطٍ
بفاتورةٍ أصلية، ويُصرف نقدُه من درج الوردية لا من خزنةٍ عامّة.

**المعمار:** ثلاثُ طبقات. (١) دالّةٌ خالصةٌ تُنتزع من إغلاق الوردية تحدّد
«درجَ الوردية»، تستعملها المرتجعاتُ والإقفالُ معاً. (٢) نموذجٌ خالصٌ يحسب
المتاحَ للإرجاع لكلّ سطر. (٣) وضعُ مرتجعٍ في سلة PicPos يقفل السعرَ والكميةَ
ومصدرَ الأصناف، ويحفظ عبر `returnsRepository.processSalesReturn` — نفسِ مسار
شاشة المردودات.

**التقنيات:** Flutter · Riverpod · Drift (SQLite) · flutter_test.

## القيودُ العامّة

كلُّ مهمّةٍ محكومةٌ بهذه ضمناً. مقيسةٌ في هذا المستودع لا مفترَضة:

- **`rm -rf build/native_assets` قبل كلّ `flutter test`** — وإلا انهار المشغّل
  بـ`errno 183` على `sqlite3.dll` وعلّق كلَّ ملفٍّ تالٍ ١٢ دقيقة.
- **ممنوع `dart format`** — المستودعُ غير مضبوطٍ عليه؛ الاستعادةُ
  بـ`git show HEAD:<path> > <path>` لا بـ`git checkout`.
- **لا تغييرَ في المخطَّط في هذه الخطة إطلاقاً** — لا جداولَ ولا أعمدة. أيُّ
  مساسٍ بالمخطَّط يستدعي `build_runner` (~٤١ دقيقة، ٤٠ منها تحليلٌ صامت) وممنوع
  تعديلُ `database.g.dart` يدوياً.
- **الحسابُ الخالصُ مكانه `lib/domain/models/`** — وحارسُ
  `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
  `data/database`.
- **الاختبارُ يُشاهَد أحمرَ أوّلاً** — والحُمرةُ تُثبَت بتشغيلٍ فعليّ، لا بالثقة.
- **حدودُ `scripts/gate.sh` تُضبط على المقيس في نفس كوميت آخر مهمّة.** الحالية:
  `unit 3397 · widget 664 · integration 710 · pg 45 · analyze 6 info`.
- **البوابةُ في الخلفية** (`nohup`) — ~٢٥–٣٥ دقيقة وسقفُ الأداة ١٠.
- **لا يُربط أيُّ عملٍ بـUralCash** (قرارُ المالك 2026-08-16)، و`D:\URAL-ERP`
  لا يُعدَّل أبداً.

---

## بنيةُ الملفّات

| الملفّ | المسؤولية |
|---|---|
| `lib/domain/models/shift_drawer_resolver.dart` **(جديد)** | دالّةٌ خالصةٌ: من قائمة خزائنَ وحركاتٍ ⇒ معرّفُ الدرج |
| `lib/domain/models/returnable_line.dart` **(جديد)** | حسابُ المتاح للإرجاع لكلّ سطر |
| `lib/data/database/daos/treasury_dao.dart` | يستدعي الحاسبَ الخالصَ بدل المنطق المضمَّن |
| `lib/data/repositories/returns_repository_impl.dart` | الصرفُ إلى الدرج بدل الخزنة العامّة |
| `lib/domain/usecases/returns/process_sales_return_usecase.dart` | نفسُ التوجيه |
| `lib/presentation/pos_picpos/screens/picpos_pos_screen.dart` | حالةُ وضع المرتجع |
| `lib/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart` **(جديد)** | الترويسةُ الحمراء |

---

## المهمّةُ ١: حاسبُ درج الوردية — دالّةٌ خالصة

**الملفّات:**
- إنشاء: `lib/domain/models/shift_drawer_resolver.dart`
- اختبار: `test/unit/shift_drawer_resolver_test.dart`

**الواجهات:**
- تُنتج: `int? resolveShiftDrawer({required Set<int> cashSafeIdsInBranch, required Map<int, double> movedBySafeId})`
  — تُرجع معرّفَ الدرج، و`null` حين لا خزنةَ نقديةً في النطاق.

**لماذا خالصة:** المنطقُ اليومَ مدفونٌ داخل معاملةِ قاعدةٍ في
`treasury_dao.dart:560-645` فلا يُختبر إلا بقاعدةٍ كاملة. وانتزاعُه يجعل
القاعدةَ الواحدةَ مختبَرةً في مللي ثانية، ويمنع تعريفَين للدرج.

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/shift_drawer_resolver.dart';

void main() {
  group('resolveShiftDrawer', () {
    test('يختار الدرجَ الأكثرَ حركةً', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {1, 2, 3},
          movedBySafeId: {1: 50.0, 2: 300.0, 3: 20.0},
        ),
        2,
      );
    });

    test('بلا حركةٍ يختار أوّلَ خزائن الفرع', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {7, 9},
          movedBySafeId: const {},
        ),
        7,
      );
    });

    test('بلا خزنةٍ نقديةٍ يرجع null', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: const {},
          movedBySafeId: const {},
        ),
        isNull,
      );
    });

    test('يتجاهل حركةً على خزنةٍ خارجَ النطاق', () {
      // خزنةٌ من فرعٍ آخرَ تحرّكت أكثر — ولا يجوز أن تُختار درجاً.
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {4},
          movedBySafeId: {4: 10.0, 99: 5000.0},
        ),
        4,
      );
    });
  });
}
```

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/shift_drawer_resolver_test.dart
```

المتوقَّع: فشلٌ بـ`Target of URI doesn't exist: 'package:ural_erp/domain/models/shift_drawer_resolver.dart'`.

- [ ] **خطوة ٣: اكتب أقلَّ تنفيذٍ يُنجحه**

> 🔴 **تصحيحٌ بعد المراجعة (2026-08-16):** الكودُ أدناه **ناقص**، وقد صُحِّح في
> `68d3e055`. عيبُه أنه يدور على `cashSafeIdsInBranch` ويعامل الغائبَ كصفر،
> فيخالف الأصلَ في موضعَين: الأصلُ (‏`treasury_dao.dart` كتلةُ `primaryDrawer`)
> يختزل على مداخل `moved` **وحدَها** — فخزنةٌ لم تُلمَس ليست مرشَّحةً ما دامت
> غيرُها تحرّكت — ويرجّح التعادلَ بترتيب **إدراج الخريطة** لا بترتيب مجموعة
> الخزائن. والصوابُ: إن كانت الخريطةُ فارغةً ⇒ أوّلُ عناصر النطاق، وإلا
> ⇒ الاختزالُ على مداخل الخريطة المحصورةِ في النطاق. اقرأ الملفَّ المُودَع
> لا هذه الكتلة، وأضِف حالتَي التعادل و«غيرِ الملموسة».

```dart
/// يحدّد «درجَ الوردية»: الخزنةَ النقديةَ التي تُنسب إليها حركاتُ الوردية.
///
/// انتُزع من `TreasuryDao._settleShift` (كان مضمَّناً في معاملةِ قاعدةٍ فلا
/// يُختبر إلا بقاعدةٍ كاملة). وانتزاعُه يمنع تعريفَين للدرج: الإقفالُ يسوّي
/// درجاً والمرتجعُ يصرف من آخر.
///
/// [cashSafeIdsInBranch] الخزائنُ النقدية في نطاق فرع الوردية.
/// [movedBySafeId] مجموعُ ما تحرّك على كلّ خزنة (قد يحوي خزائنَ خارجَ النطاق
/// فتُتجاهَل).
int? resolveShiftDrawer({
  required Set<int> cashSafeIdsInBranch,
  required Map<int, double> movedBySafeId,
}) {
  if (cashSafeIdsInBranch.isEmpty) return null;

  double best = -1;
  int? bestId;
  for (final id in cashSafeIdsInBranch) {
    final moved = movedBySafeId[id] ?? 0;
    if (moved > best) {
      best = moved;
      bestId = id;
    }
  }
  // كلُّها أصفار ⇒ `best == 0` و`bestId` أوّلُ عنصرٍ في ترتيب المجموعة،
  // وهو بعينه سلوكُ `drawerSafeIds.first` القائم.
  return bestId;
}
```

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/unit/shift_drawer_resolver_test.dart
```

المتوقَّع: `All tests passed!` (‏٤ حالات).

- [ ] **خطوة ٥: أودِع**

```bash
git add lib/domain/models/shift_drawer_resolver.dart test/unit/shift_drawer_resolver_test.dart
git commit -m "feat(treasury): حاسبُ درج الوردية دالّةً خالصةً مختبَرة"
```

---

## المهمّةُ ٢: الإقفالُ يستعمل الحاسبَ الخالص

**الملفّات:**
- تعديل: `lib/data/database/daos/treasury_dao.dart:630-645`

**الواجهات:**
- يستهلك: `resolveShiftDrawer` من المهمّة ١.

**الغرض:** موضعٌ واحدٌ لتعريف الدرج. بلا هذه المهمّة يبقى تعريفان يتباعدان.

- [ ] **خطوة ١: تأكّد من الخطّ الأساس قبل المساس**

```bash
rm -rf build/native_assets && flutter test test/unit/post_open_shift_duplicate_guard_test.dart
```

سجّل عددَ الناجح. أيُّ نقصٍ بعد التعديل انحدار.

- [ ] **خطوة ٢: استبدل المنطقَ المضمَّن بالنداء**

في `treasury_dao.dart`، استبدل كتلةَ `int? primaryDrawer; if (...) {...}`
(‏الأسطر ٦٣٢-٦٤٤ تقريباً — أثبِت الموضعَ بالقراءة لا بالرقم) بـ:

```dart
      // موضعٌ واحدٌ لتعريف الدرج — راجع `domain/models/shift_drawer_resolver.dart`.
      final moved = <int, double>{};
      for (final t in drawerTxs) {
        moved[t.safeId] = (moved[t.safeId] ?? 0) + t.amount.abs();
      }
      final primaryDrawer = resolveShiftDrawer(
        cashSafeIdsInBranch: drawerSafeIds,
        movedBySafeId: moved,
      );
```

وأضف الاستيرادَ أعلى الملفّ:

```dart
import '../../../domain/models/shift_drawer_resolver.dart';
```

- [ ] **خطوة ٣: شغّل سويّةَ الوردية كاملةً**

```bash
rm -rf build/native_assets && flutter test test/unit/post_open_shift_duplicate_guard_test.dart test/integration
```

المتوقَّع: نفسُ العدد الذي سجّلتَه في خطوة ١، و`integration` ٧١٠.

- [ ] **خطوة ٤: أودِع**

```bash
git add lib/data/database/daos/treasury_dao.dart
git commit -m "refactor(treasury): الإقفالُ يستعمل حاسبَ الدرج بدل منطقٍ مضمَّن"
```

---

## المهمّةُ ٣: الصرفُ إلى درج الوردية لا إلى خزنةٍ عامّة

**الملفّات:**
- تعديل: `lib/data/repositories/returns_repository_impl.dart` (مواضعُ
  `getDefaultSafeByType('cash')` — قِسها بـ`grep -n`، كانت `441` و`504`)
- تعديل: `lib/domain/usecases/returns/process_sales_return_usecase.dart:132`
- اختبار: `test/unit/return_refund_hits_shift_drawer_test.dart`

**الواجهات:**
- يستهلك: `getCurrentOpenShift(int userId) → Future<Shift?>` ·
  `getCashSafesForBranch(int? branchId)` · `resolveShiftDrawer` (المهمّة ١).
- يُنتج: `Future<Safe?> resolveRefundSafe({required int userId})` على
  `TreasuryDao` — يستعملها كلُّ مسارات المرتجع.

**العطبُ المقيس:** المرتجعُ يضرب `getDefaultSafeByType('cash')` — خزنةً عامّةً
تتجاهل الفرع — بينما البيعُ والإقفالُ ينسبان للفرع. فمرتجعٌ في الفرع «ب»
يُنقص خزنةَ الفرع «أ».

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  test('المرتجعُ يُصرف من درج فرع الوردية لا من الخزنة العامّة', () async {
    // فرعان، ولكلٍّ خزنتُه النقدية.
    final branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع أ'),
        );
    final branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع ب'),
        );
    final safeA = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج أ',
            safeType: 'cash',
            branchId: Value(branchA),
          ),
        );
    final safeB = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج ب',
            safeType: 'cash',
            branchId: Value(branchB),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    final userB = await db.createUser(
      username: 'cashier_b',
      password: 'x',
      displayName: 'كاشير ب',
      roleId: roleId,
      branchId: branchB,
    );

    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userB,
            status: 'open',
            branchId: Value(branchB),
          ),
        );

    final resolved = await db.resolveRefundSafe(userId: userB);

    expect(resolved, isNotNull);
    expect(resolved!.id, safeB,
        reason: 'كاشيرُ الفرع ب يجب أن يصرف من درج فرعه لا من $safeA');
  });
}
```

> ⚠️ أسماءُ أعمدة `SafesCompanion` و`BranchesCompanion` و`createUser`
> **أثبِتها بالقراءة** قبل التشغيل (‏`lib/data/database/tables/`)؛ لا تعتمد
> على ما هنا. الغرضُ من الاختبار ثابتٌ حتى لو اختلف الاسم.

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/return_refund_hits_shift_drawer_test.dart
```

المتوقَّع: فشلٌ لأن `resolveRefundSafe` غيرُ موجودة.

- [ ] **خطوة ٣: أضف `resolveRefundSafe` إلى `TreasuryDao`**

```dart
  /// خزنةُ صرف المرتجع: درجُ وردية المستخدم المفتوحة.
  ///
  /// كان المرتجعُ يضرب `getDefaultSafeByType('cash')` — خزنةً **عامّةً**
  /// تتجاهل الفرع — بينما البيعَ والإقفالَ ينسبان للفرع. فمرتجعٌ في فرعٍ
  /// كان يُنقص خزنةَ فرعٍ آخر (مقيسٌ 2026-08-16).
  ///
  /// وعند غياب ورديةٍ مفتوحة يسقط إلى الخزنة الافتراضية — والمستدعي يسجّل
  /// السقوطَ في وصف الحركة كي يظهر لمراجع.
  Future<Safe?> resolveRefundSafe({required int userId}) async {
    final shift = await getCurrentOpenShift(userId);
    if (shift == null) return getDefaultSafeByType('cash');

    final branchSafes = await getCashSafesForBranch(shift.branchId);
    if (branchSafes.isEmpty) return getDefaultSafeByType('cash');

    final ids = {for (final s in branchSafes) s.id};
    final txs = await (select(safeTransactions)
          ..where((t) => t.safeId.isIn(ids))
          ..where((t) => t.createdAt.isBiggerOrEqualValue(shift.startTime)))
        .get();
    final moved = <int, double>{};
    for (final t in txs) {
      moved[t.safeId] = (moved[t.safeId] ?? 0) + t.amount.abs();
    }

    final drawerId =
        resolveShiftDrawer(cashSafeIdsInBranch: ids, movedBySafeId: moved);
    if (drawerId == null) return getDefaultSafeByType('cash');
    return branchSafes.firstWhere((s) => s.id == drawerId);
  }
```

> ⚠️ اسمُ عمود الوقت في `safeTransactions` (‏`createdAt` أم غيرُه) **يُقاس**
> من `lib/data/database/tables/` قبل الكتابة.

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/unit/return_refund_hits_shift_drawer_test.dart
```

- [ ] **خطوة ٥: وجّه مواضعَ الصرف الثلاثة**

استبدل في `returns_repository_impl.dart` و`process_sales_return_usecase.dart`
كلَّ `await _db.getDefaultSafeByType('cash')` **في مسار ردّ المرتجع** بـ
`await _db.resolveRefundSafe(userId: <معرّفُ المستخدم في السياق>)`.

⚠️ **لا تلمس** مواضعَ `getDefaultSafeByType('bank')` — الصرفُ البنكيُّ ليس
درجاً. ولا تلمس أيَّ موضعٍ خارجَ مسار المرتجع.

- [ ] **خطوة ٦: شغّل سويّتَي الوحدة والتكامل كاملتَين**

```bash
rm -rf build/native_assets && flutter test test/unit test/integration
```

المتوقَّع: لا انحدار. أيُّ اختبارٍ يؤكّد الخزنةَ العامّةَ للمرتجع كان **يوثّق
العطب** — أصلِح توقُّعَه ووثّق السبب في التعليق.

- [ ] **خطوة ٧: أودِع**

```bash
git add lib/data/database/daos/treasury_dao.dart lib/data/repositories/returns_repository_impl.dart lib/domain/usecases/returns/process_sales_return_usecase.dart test/unit/return_refund_hits_shift_drawer_test.dart
git commit -m "fix(returns): الصرفُ من درج وردية الفرع لا من خزنةٍ عامّة"
```

---

## المهمّةُ ٤: نموذجُ المتاح للإرجاع

**الملفّات:**
- إنشاء: `lib/domain/models/returnable_line.dart`
- اختبار: `test/unit/returnable_line_test.dart`

**الواجهات:**
- تُنتج: `class ReturnableLine { int invoiceItemId; int productId; String productName; double soldQty; double alreadyReturnedQty; double unitPrice; double get availableQty; }`
  و`bool isReturnRequestValid(double requested)`.

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';

ReturnableLine line({double sold = 10, double returned = 0}) => ReturnableLine(
      invoiceItemId: 1,
      productId: 1,
      productName: 'صنف',
      soldQty: sold,
      alreadyReturnedQty: returned,
      unitPrice: 5,
    );

void main() {
  test('المتاح = المباع − المرتجع سلفاً', () {
    expect(line(sold: 10, returned: 3).availableQty, 7);
  });

  test('المتاح لا ينزل تحت الصفر', () {
    // إرجاعٌ زائدٌ تاريخيٌّ لا يجعل المتاحَ سالباً فيُقلب لرصيدٍ وهميّ.
    expect(line(sold: 10, returned: 12).availableQty, 0);
  });

  test('طلبٌ يساوي المتاحَ مقبول', () {
    expect(line(sold: 10, returned: 3).isReturnRequestValid(7), isTrue);
  });

  test('طلبٌ يتجاوز المتاحَ مرفوض', () {
    expect(line(sold: 10, returned: 3).isReturnRequestValid(7.5), isFalse);
  });

  test('طلبٌ بصفرٍ أو أقلَّ مرفوض', () {
    expect(line().isReturnRequestValid(0), isFalse);
    expect(line().isReturnRequestValid(-1), isFalse);
  });

  test('يحتمل فرقَ الفاصلة العائمة', () {
    // ٠٫١+٠٫٢ = ٠٫٣٠٠٠٠٠٠٠٠٠٠٠٠٠٠٤ — ولا يجوز أن يُرفض إرجاعُ الكامل.
    final l = ReturnableLine(
      invoiceItemId: 1, productId: 1, productName: 'ص',
      soldQty: 0.3, alreadyReturnedQty: 0.1 + 0.2 - 0.3, unitPrice: 1,
    );
    expect(l.isReturnRequestValid(0.3), isTrue);
  });
}
```

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/returnable_line_test.dart
```

- [ ] **خطوة ٣: اكتب التنفيذ**

```dart
/// سطرٌ من فاتورةٍ أصلية بحدّ إرجاعه.
///
/// خالصٌ عمداً: القاعدةُ «المرتجع ≤ المباع − المرتجع سلفاً» كانت مدفونةً في
/// `returns_repository_impl.dart:105` داخلَ حلقةٍ تضرب القاعدة، فلا تُختبر
/// إلا بقاعدةٍ كاملة — ولا يراها بناءُ الواجهة أصلاً فيسمح بإدخالٍ يُرفض
/// عند الحفظ.
class ReturnableLine {
  final int invoiceItemId;
  final int productId;
  final String productName;
  final double soldQty;
  final double alreadyReturnedQty;
  final double unitPrice;

  const ReturnableLine({
    required this.invoiceItemId,
    required this.productId,
    required this.productName,
    required this.soldQty,
    required this.alreadyReturnedQty,
    required this.unitPrice,
  });

  /// نفسُ سماحِ `returns_repository_impl.dart` — الفاصلةُ العائمة تجعل
  /// إرجاعَ الكامل يبدو تجاوزاً بمقدارٍ لا يُرى.
  static const double _epsilon = 0.001;

  double get availableQty {
    final remaining = soldQty - alreadyReturnedQty;
    return remaining > 0 ? remaining : 0;
  }

  bool isReturnRequestValid(double requested) {
    if (requested <= 0) return false;
    return requested <= availableQty + _epsilon;
  }
}
```

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/unit/returnable_line_test.dart
```

المتوقَّع: `All tests passed!` (‏٦ حالات).

- [ ] **خطوة ٥: أودِع**

```bash
git add lib/domain/models/returnable_line.dart test/unit/returnable_line_test.dart
git commit -m "feat(returns): نموذجُ المتاح للإرجاع خالصاً ومختبَراً"
```

---

## المهمّةُ ٥: رفعُ السقف الزمنيّ لبحث الفواتير

**الملفّات:**
- تعديل: `lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart:309`
- اختبار: `test/widget/return_invoice_search_has_no_date_cap_test.dart`

**قرارُ المالك ٢:** الاستعراضُ بلا سقفٍ زمنيّ — الارتجاعُ جائزٌ بعد فترة.

- [ ] **خطوة ١: أثبِت السقفَ القائم**

```bash
grep -n "365" lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart
```

المتوقَّع: سطرٌ فيه `subtract(const Duration(days: 365))`.

- [ ] **خطوة ٢: اكتب الاختبارَ الفاشل**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('بحثُ فواتير المرتجع بلا سقفٍ زمنيّ', () {
    final src = File(
      'lib/presentation/sales_returns_picpos/screens/'
      'sales_returns_picpos_logic.dart',
    ).readAsStringSync();

    // جرّد التعليقاتِ أوّلاً — التعليقُ ليس كوداً، وقياسُ النصّ الخام
    // يلتقط شرحاً تاريخياً فيُرجع أخضرَ كاذباً أو أحمرَ كاذباً.
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    expect(
      code.contains('Duration(days: 365)'),
      isFalse,
      reason: 'قرارُ المالك 2026-08-16: الارتجاعُ جائزٌ بعد فترةٍ لا في نفس اليوم',
    );
  });
}
```

- [ ] **خطوة ٣: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/widget/return_invoice_search_has_no_date_cap_test.dart
```

المتوقَّع: فشلٌ — الشرطُ ما زال في الملفّ.

- [ ] **خطوة ٤: ارفع السقف**

استبدل `historyFrom` بتاريخٍ لا يحجب شيئاً عملياً، مع تعليقٍ يذكر القرار:

```dart
    // قرارُ المالك 2026-08-16: بلا سقفٍ زمنيّ — الارتجاعُ جائزٌ بعد فترةٍ
    // وليس في نفس اليوم. وكان السقفُ ٣٦٥ يوماً فيُخفي فاتورةً أقدمَ من سنة.
    final historyFrom = DateTime(2000);
```

- [ ] **خطوة ٥: شغّل وتأكّد من النجاح، ثم سويّةَ الودجت كاملةً**

```bash
rm -rf build/native_assets && flutter test test/widget
```

- [ ] **خطوة ٦: أودِع**

```bash
git add lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart test/widget/return_invoice_search_has_no_date_cap_test.dart
git commit -m "feat(returns): بحثُ الفواتير بلا سقفٍ زمنيّ — قرارُ المالك"
```

---

## المهمّةُ ٦: وضعُ المرتجع في سلة PicPos — الحالةُ والأقفال

**الملفّات:**
- إنشاء: `lib/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart`
- تعديل: `lib/presentation/pos_picpos/screens/picpos_pos_screen.dart`
- اختبار: `test/widget/picpos_return_mode_test.dart`

**الواجهات:**
- يستهلك: `ReturnableLine` (المهمّة ٤).
- يُنتج: `class PosReturnMode { final SalesInvoiceData invoice; final List<ReturnableLine> lines; }`
  و`posReturnModeProvider` (‏`StateProvider<PosReturnMode?>`) — `null` يعني وضعَ البيع.

**الأقفالُ الأربعة (§٥ من المواصفة):** السعرُ مقفول · الكميةُ مسقوفة · لا
أصنافَ خارجَ الفاتورة · ترويسةٌ حمراءُ ظاهرة.

- [ ] **خطوة ١: اكتب اختبارَ الأقفال الفاشل**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/presentation/pos_picpos/state/pos_return_mode.dart';

void main() {
  final l = ReturnableLine(
    invoiceItemId: 5, productId: 9, productName: 'لوز',
    soldQty: 4, alreadyReturnedQty: 1, unitPrice: 12.5,
  );

  group('PosReturnMode', () {
    test('الكميّاتُ تبدأ صفراً — قرارُ المالك', () {
      // البدءُ بالكامل يُغري بحفظٍ سريعٍ يُرجع ما لم يُحضره العميل.
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.requestedQty[l.invoiceItemId], 0);
    });

    test('لا يقبل صنفاً خارجَ الفاتورة', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.canAcceptProduct(9), isTrue);
      expect(mode.canAcceptProduct(404), isFalse);
    });

    test('لا يقبل كميةً تتجاوز المتاح', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.setQty(l.invoiceItemId, 3), isTrue);   // المتاح ٣
      expect(mode.setQty(l.invoiceItemId, 3.5), isFalse);
    });

    test('السعرُ من الفاتورة لا من شاشة الأصناف', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.unitPriceOf(l.invoiceItemId), 12.5);
    });
  });
}
```

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/widget/picpos_return_mode_test.dart
```

المتوقَّع: فشلٌ — الملفُّ غيرُ موجود.

- [ ] **خطوة ٣: اكتب `pos_return_mode.dart`**

أنشئ `lib/presentation/pos_picpos/state/pos_return_mode.dart` بصنفٍ يحمل
`invoiceId` و`Map<int, ReturnableLine> linesByItemId` و
`Map<int, double> requestedQty` (‏كلُّها أصفارٌ عند الإنشاء)، ودوالَّ
`canAcceptProduct(int productId)` و`setQty(int itemId, double qty)` (‏ترجع
`false` وتُبقي القيمةَ القديمةَ عند التجاوز، عبر `isReturnRequestValid`) و
`unitPriceOf(int itemId)`.

⚠️ الملفُّ في `presentation/` فلا يستورد `data/database` (حارسُ
`presentation_db_import_guard`). يستورد `domain/models/returnable_line.dart`
فقط، و`invoiceId` رقمٌ لا كائنُ صفّ.

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/widget/picpos_return_mode_test.dart
```

- [ ] **خطوة ٥: أودِع الحالةَ قبل الواجهة**

```bash
git add lib/presentation/pos_picpos/state/pos_return_mode.dart test/widget/picpos_return_mode_test.dart
git commit -m "feat(pos): حالةُ وضع المرتجع بأقفالها الأربعة"
```

---

## المهمّةُ ٧: الترويسةُ والزرُّ والحفظ

**الملفّات:**
- إنشاء: `lib/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart`
- تعديل: `lib/presentation/pos_picpos/widgets/picpos_payment_panel.dart`
  (‏زرُّ «مرتجع سريع» بجوار `_Action` القائمة)
- تعديل: `lib/presentation/pos_picpos/screens/picpos_pos_operations.dart` (الحفظ)
- اختبار: `test/widget/picpos_return_mode_banner_test.dart`

**الواجهات:**
- يستهلك: `PosReturnMode` · `posReturnModeProvider` (المهمّة ٦) ·
  `returnsRepository.processSalesReturn({required SalesInvoiceData invoice, required Map<int,double> returnQuantities, required Map<int,ProductEntity> productCache, String? reason, required int userId, required String userName, bool isFullReturn, bool isDamaged})`.

⚠️ **المسارُ إلزاميّ**: `returnsRepository.processSalesReturn` — **لا**
`ProcessSalesReturnUseCase`، فالأخيرُ بلا سقفِ كمية في `_validate` (مقيس).

- [ ] **خطوة ١: اكتب اختبارَ الترويسة الفاشل**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart';

void main() {
  testWidgets('الترويسةُ تُظهر رقمَ الفاتورة وتُميَّز بلونٍ تحذيريّ',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PicPosReturnModeBanner(invoiceNumber: 'SINV-4'),
      ),
    ));

    expect(find.textContaining('وضع المرتجع'), findsOneWidget);
    expect(find.textContaining('SINV-4'), findsOneWidget,
        reason: 'رقمُ الفاتورة يبقى ظاهراً — سلةٌ تبدو كسلّة بيعٍ وتفعل عكسَها '
            'هي وصفةُ خطأٍ يوميّ');
  });
}
```

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/widget/picpos_return_mode_banner_test.dart
```

- [ ] **خطوة ٣: اكتب الترويسة**

ودجتٌ عديمُ الحالة يعرض صفّاً بخلفية `AppColors.error` بشفافية، أيقونةَ
`PhosphorIconsBold.arrowUUpLeft`، ونصَّي «وضع المرتجع» و`invoiceNumber`
بنمط `PicPosText.v(...)`.

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/widget/picpos_return_mode_banner_test.dart
```

- [ ] **خطوة ٥: صِل الزرَّ والحفظ**

أضف `_Action(label: 'مرتجع سريع', ...)` يفتح مُحدِّدَ الفاتورة ثم يضبط
`posReturnModeProvider`. وفي مسار الحفظ: إن كان الوضعُ غيرَ `null` فنادِ
`processSalesReturn` بـ`returnQuantities` من `PosReturnMode.requestedQty`
(‏بعد إسقاط الأصفار)، ثم أفرغ الوضعَ والسلة.

- [ ] **خطوة ٦: شغّل البوابةَ كاملةً في الخلفية**

```bash
nohup bash scripts/gate.sh --pg > /tmp/gate.log 2>&1 &
```

المتوقَّع: `✓ البوابة كلها خضراء` وخروجٌ صفريٌّ طبيعيٌّ لا مقتول.

- [ ] **خطوة ٧: اضبط الحدودَ على المقيس وأودِع**

حدِّث `unit` و`widget` في `scripts/gate.sh` بالمقيس، وسوِّ الزيادةَ بالضبط في
رسالة الكوميت.

```bash
git add -A
git commit -m "feat(pos): زرُّ المرتجع السريع — السلةُ تصير مردوداً مربوطاً بفاتورته"
```

---

## المراجعةُ الذاتية للخطة

- **تغطيةُ المواصفة:** §٤-١ ⇒ المهمّة ٥ · §٤-٢ ⇒ المهمّة ٤ · §٤-٣ ⇒ المهامّ
  ١-٣ · §٥ الأقفالُ الأربعة ⇒ المهمّتان ٦ و٧ · قرارُ ٤ (الشاشةُ القائمة) ⇒
  المهمّة ٣ خطوة ٥.
- **بلا عناصرَ نائبة:** كلُّ خطوةِ كودٍ فيها كودُها. والموضعان اللذان تركتُهما
  للقياس (أسماءُ أعمدة الجداول، وموضعُ `primaryDrawer`) **مُعلَّمان صراحةً**
  بأمر القياس لأن الاعتمادَ على رقم سطرٍ في مستندٍ هو بعينه ما يبطُل.
- **اتّساقُ الأنواع:** `resolveShiftDrawer` بنفس التوقيع في المهامّ ١ و٢ و٣ ·
  `ReturnableLine` بنفس الحقول في ٤ و٦ · `PosReturnMode` بنفس الدوالّ في ٦ و٧.

**خارجَ هذه الخطة:** الاستبدالُ كلُّه (الخطةُ الثانية) · إعادةُ تسمية القائمة
الجانبية (مهمّةٌ مؤجَّلة).

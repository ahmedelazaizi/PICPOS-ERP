# خطة تنفيذ منطق خدمة الطاولات

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** فصلُ «الدفع» عن «الإغلاق» بحالةٍ ثالثةٍ للطاولة، وبناءُ تقسيمِ فاتورةٍ حقيقيّ، ودمجٍ يحفظ مصدرَ كلّ بند — بمنطقٍ يعيش في طبقة خدمةٍ قابلةٍ للاختبار بلا واجهة.

**Architecture:** `SplitPlan` كائنُ قيمةٍ خالصٌ في `domain/models` يحسب الحصص بلا قاعدة. `TableSessionService` في `lib/services/` تملك انتقالات الطاولة وتكتب سطرَ السجل لكلٍّ منها، وتستعمل `tables_dao` وصولاً للبيانات فحسب. إنشاءُ الفاتورة يبقى حيث هو (`checkoutController.processPayment` المقترنُ بالسلة)، وتُسجَّل نتيجتُه في `TableOrderPayments` عبر الخدمة.

**Tech Stack:** Flutter · Drift (SQLite + PostgreSQL) · Riverpod · `flutter_test`

---

## Global Constraints

هذه القيود تنطبق على **كلّ** مهمّةٍ أدناه بلا استثناء.

### قيودُ الأداة

- **`build_runner` يُشغَّل مرّةً واحدةً في هذه الخطة كلِّها — في المهمّة ٢ وحدها.** يحتاج ~٤١ دقيقة في هذه البيئة، منها ~٤٠ تحليلٌ صامتٌ بلا نموٍّ في الكاش. **لا يُقتَل.** أيُّ مهمّةٍ تالية تحتاج عموداً جديداً = عطلٌ في التخطيط، لا سببٌ لتمريرةٍ ثانية.
- **ممنوعٌ منعاً باتّاً تحريرُ `lib/data/database/database.g.dart` يدوياً.** يَنقُص ~٤٠٪ بصمتٍ رغم نجاح `flutter analyze` والاختبارات.
- **ممنوع `dart format`.** المستودع غير مضبوطٍ عليه؛ تشغيلُه حوّل تعديلاً من ١٥٥ سطراً إلى ٤٢٠ في ملفٍ مشترك.
- **ممنوع `git checkout` أثناء التعديل.** يمحو الشغل غير المكوَّم في الملف نفسه. للاستعادة استعمل `git show HEAD:<path> > <path>`.
- **البوّابة تُشغَّل في الخلفية.** `scripts/gate.sh` يحتاج ~٣٤ دقيقة وسقفُ أداة الصدفة ١٠. ولإيقافها ابدأ بقتل عملية `gate.sh` نفسها وإلّا كمّلت للسويّة التالية.

### قيودُ الدمج مع الجلسة الأخرى

الجلسةُ الأخرى لا تمسّ الطاولات ولا الحجوزات، لكنّ ثلاثةَ ملفّاتٍ مولَّدةٍ أو مشترَكةٍ تتصادم على أيّ حال:

- **`database.g.dart` — لا يُحلُّ تعارضُه يدوياً أبداً.** عند الدمج: اقبل أيَّ جانبٍ منه بلا قراءة (`git checkout --ours -- lib/data/database/database.g.dart`)، ثم شغّل `build_runner` **مرّةً واحدةً على المصدر المدموج** وأودِع الناتج. الملفُّ مشتقٌّ لا مصدر.
- **`schemaVersion` — هذا الفرع يأخذ ١٥٤** (الحاليّ ١٥٣). إن أخذت الجلسةُ الأخرى ١٥٤ أيضاً، فالفرعُ **الثاني** في الدمج يُعيد ترقيم كتلته إلى ١٥٥ ويُحرّكها بعد الأولى. ولهذا يُكتب تغييرُ المخطّط كلُّه في **كتلة `if (from < 154)` واحدة في ذيل `epoch_3.dart`** — فإعادةُ الترقيم تصير تغييرَ رقمٍ وتحريكَ كتلةٍ واحدة، لا جراحة.
- **`permission_codes.dart` مشترَك.** التعديلات **إضافيّةٌ فقط** وتُلحَق في **آخر** القوائم، لا في وسطها — فيبقى التعارضُ سطراً واحداً بدل كتلة.

### قيودُ الاختبار

- **الثقلُ على الخدمة والنموذج الخالص، لا على الويدجت.** اختباراتُ الويدجت هنا تتعلّق عند فتح الشاشات لأن `db.close()` ينتظر مؤقّت drift في المنطقة الوهميّة. أيُّ اختبارِ واجهةٍ يجب أن يُفكّك الشجرة ويدفع إطاراً و**لا يُغلق القاعدة**.
- **قاعدةُ الاختبار:** `AppDatabase.forTesting()` — في الذاكرة، غيرُ مفردة ([database.dart:567](../../../lib/data/database/database.dart)).
- **حارس `presentation_db_import_guard`:** أيُّ ملفِ عرضٍ **جديد** ممنوعٌ من استيراد `data/database`، والقائمةُ البيضاء مقفولة. الشاشاتُ الجديدة تمرّ عبر مستودع/خدمة.

### قيمٌ ثابتة

- اسم الحزمة في الاستيراد: `ural_erp`
- `AppConstants.decimalPlaces == 3` ⇒ معاملُ التدوير `1000`
- خطُّ أساس `flutter analyze lib test` = **٦ info**. أيُّ زيادةٍ فشل.

---

## بنيةُ الملفات

**جديدة**

| الملف | المسؤوليّة الواحدة |
|---|---|
| `lib/domain/models/table_status.dart` | ثوابتُ حالات الطاولة الخمس — تُنهي السلاسل السحريّة |
| `lib/domain/models/split_plan.dart` | حسابُ الحصص بلا قاعدةٍ ولا واجهة |
| `lib/services/table_session_service.dart` | انتقالاتُ الطاولة + كتابةُ السجل |
| `lib/presentation/screens/tables/table_log_sheet.dart` | عرضُ سجلّ الطاولة |
| `test/unit/split_plan_test.dart` | وحدةٌ صِرفة |
| `test/unit/table_session_service_test.dart` | آلةُ الحالات على قاعدةٍ في الذاكرة |
| `test/unit/table_service_schema_test.dart` | إثباتُ وصول أعمدة المهمّة ٢ |

**معدَّلة**

| الملف | التغيير |
|---|---|
| `lib/data/database/tables/restaurant_tables.dart` | ٧ أعمدة + `TableOrderPayments` |
| `lib/data/database/database.dart` | تسجيلُ الجدول + `schemaVersion` ١٥٤ |
| `lib/data/database/migrations/epoch_3.dart` | كتلةُ `from < 154` |
| `lib/data/database/daos/tables_dao.dart` | إيقافُ تجميع الكميّات في الدمج + دوالُّ الدفعات |
| `lib/core/permissions/permission_codes.dart` | `tables_discount` + رفعُ وسم `tables_print_bill` |
| `lib/presentation/screens/tables/table_operations.dart` | الكبساتُ تُشتقّ من الحالة |
| `lib/presentation/screens/tables/table_card_widget.dart` | 🟠 و⚪ و«دُفع س من ص» |
| `lib/presentation/screens/tables/split_table_dialog.dart` | يُعاد بناؤه تقسيمَ فاتورة |
| `lib/presentation/pos/screens/table_pos_operations.dart` | يُسلّم التسجيلَ للخدمة |

---

## Task 1: `SplitPlan` — حسابُ الحصص

يبدأ الترتيب هنا لا بالمخطّط: هذا نموذجٌ خالصٌ لا يحتاج عموداً واحداً، فيُنجز ويُودَع أخضرَ قبل أن نحرق ٤١ دقيقةً في `build_runner`.

**Files:**
- Create: `lib/domain/models/split_plan.dart`
- Test: `test/unit/split_plan_test.dart`

**Interfaces:**
- Consumes: `AppConstants.decimalPlaces` من `lib/core/constants/app_constants.dart`
- Produces: `SplitPlan`, `SplitPart`, `SplitItem`, `SplitMode`, `SplitPlanException`. تستهلكها المهامّ ٧ و١٠.

- [ ] **Step 1: اكتب الاختبار الفاشل**

`test/unit/split_plan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/split_plan.dart';

void main() {
  group('SplitPlan.equal', () {
    test('مجموعُ الحصص يساوي الإجمالي بالضبط عند ١٠٠ ÷ ٣', () {
      final plan = SplitPlan.equal(total: 100, ways: 3);
      expect(plan.parts.map((p) => p.amount).toList(),
          [33.333, 33.333, 33.334]);
      final sum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
      expect((sum * 1000).round(), (100 * 1000).round());
    });

    test('الفرقُ الكسريُّ يقع على الحصّة الأخيرة عند ١٠٠ ÷ ٧', () {
      final plan = SplitPlan.equal(total: 100, ways: 7);
      final sum = plan.parts.fold<double>(0, (s, p) => s + p.amount);
      expect((sum * 1000).round(), 100000);
      expect(plan.parts.last.amount, greaterThan(plan.parts.first.amount));
    });

    test('القسمةُ المضبوطة لا تترك بواقي', () {
      final plan = SplitPlan.equal(total: 100, ways: 4);
      expect(plan.parts.every((p) => p.amount == 25.0), isTrue);
    });

    test('دافعٌ واحدٌ يُرفض', () {
      expect(() => SplitPlan.equal(total: 100, ways: 1),
          throwsA(isA<SplitPlanException>()));
    });

    test('إجماليٌّ غيرُ موجبٍ يُرفض', () {
      expect(() => SplitPlan.equal(total: 0, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('لا تُصدر فواتيرَ منفصلة', () {
      expect(SplitPlan.equal(total: 100, ways: 2).producesSeparateInvoices,
          isFalse);
    });
  });

  group('SplitPlan.byAmounts', () {
    test('المجموعُ المطابق يُقبل', () {
      final plan = SplitPlan.byAmounts(total: 100, amounts: [40, 35, 25]);
      expect(plan.parts.length, 3);
      expect(plan.parts[0].amount, 40);
    });

    test('المجموعُ المخالف يُرفض', () {
      expect(() => SplitPlan.byAmounts(total: 100, amounts: [40, 35, 20]),
          throwsA(isA<SplitPlanException>()));
    });

    test('حصّةٌ غيرُ موجبةٍ تُرفض', () {
      expect(() => SplitPlan.byAmounts(total: 100, amounts: [100, 0]),
          throwsA(isA<SplitPlanException>()));
    });
  });

  group('SplitPlan.byItems', () {
    final items = const [
      SplitItem(itemId: 1, quantity: 2, lineTotal: 60),
      SplitItem(itemId: 2, quantity: 1, lineTotal: 40),
    ];

    test('كلُّ بندٍ يذهب لصاحبه ويُجمع مبلغُه', () {
      final plan = SplitPlan.byItems(
        items: items,
        assignment: {1: 0, 2: 1},
        ways: 2,
      );
      expect(plan.parts[0].amount, 60);
      expect(plan.parts[1].amount, 40);
      expect(plan.parts[0].itemQuantities, {1: 2.0});
    });

    test('بندٌ بلا صاحبٍ يُرفض', () {
      expect(
          () => SplitPlan.byItems(
              items: items, assignment: {1: 0}, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('صاحبٌ خارج النطاق يُرفض', () {
      expect(
          () => SplitPlan.byItems(
              items: items, assignment: {1: 0, 2: 5}, ways: 2),
          throwsA(isA<SplitPlanException>()));
    });

    test('تُصدر فواتيرَ منفصلة', () {
      final plan = SplitPlan.byItems(
          items: items, assignment: {1: 0, 2: 1}, ways: 2);
      expect(plan.producesSeparateInvoices, isTrue);
    });
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/split_plan_test.dart
```

المتوقَّع: فشلٌ في التحميل — `Target of URI doesn't exist: 'package:ural_erp/domain/models/split_plan.dart'`.

- [ ] **Step 3: اكتب أقلَّ تنفيذٍ يُنجح الاختبار**

`lib/domain/models/split_plan.dart`:

```dart
import 'dart:math' as math;

import '../../core/constants/app_constants.dart';

/// خطأُ خطّةِ تقسيمٍ غيرِ صالحة. رسالتُه تُعرَض للمستخدم كما هي.
class SplitPlanException implements Exception {
  const SplitPlanException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum SplitMode { equal, byAmounts, byItems }

/// بندُ طلبٍ كما يراه الحساب — بلا أيّ ارتباطٍ بـDrift.
class SplitItem {
  const SplitItem({
    required this.itemId,
    required this.quantity,
    required this.lineTotal,
  });

  final int itemId;
  final double quantity;
  final double lineTotal;
}

/// حصّةُ دافعٍ واحد.
class SplitPart {
  const SplitPart({
    required this.amount,
    required this.label,
    this.itemQuantities = const {},
  });

  final double amount;
  final String label;

  /// `itemId → quantity`. فارغةٌ في التقسيم بالتساوي وبمبلغ، إذ لا حدودَ
  /// صنفيّةً هناك.
  final Map<int, double> itemQuantities;
}

/// خطّةُ تقسيمِ حسابٍ على عدّة دافعين.
///
/// ثابتٌ لا يُستثنى: مجموعُ حصص أيّ خطّةٍ يساوي الإجماليَّ بالضبط بدقّة
/// [AppConstants.decimalPlaces]. الحسابُ كلُّه يجري بوحداتٍ صحيحةٍ مقيسة
/// (×١٠٠٠) لأن جمع `double` يُنتج ٩٩٫٩٩٩٩٩٩٩٩٩٩٩ في القسمة على ٣.
class SplitPlan {
  const SplitPlan._(this.mode, this.parts);

  final SplitMode mode;
  final List<SplitPart> parts;

  static int get _factor =>
      math.pow(10, AppConstants.decimalPlaces).toInt();

  static int _units(double value) => (value * _factor).round();

  /// التقسيمُ بالتساوي — والفرقُ الكسريُّ يُحمَّل على الحصّة الأخيرة.
  factory SplitPlan.equal({required double total, required int ways}) {
    if (ways < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    if (total <= 0) {
      throw const SplitPlanException('لا يمكن تقسيمُ إجماليٍّ غيرِ موجب');
    }
    final totalUnits = _units(total);
    final base = totalUnits ~/ ways;
    final remainder = totalUnits - base * ways;
    final parts = <SplitPart>[
      for (var i = 0; i < ways; i++)
        SplitPart(
          amount: (i == ways - 1 ? base + remainder : base) / _factor,
          label: 'ضيف ${i + 1}',
        ),
    ];
    return SplitPlan._(SplitMode.equal, parts);
  }

  /// التقسيمُ بمبالغَ يحدّدها الكاشير — يجب أن تجمع الإجماليَّ بالضبط.
  factory SplitPlan.byAmounts({
    required double total,
    required List<double> amounts,
  }) {
    if (amounts.length < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    if (amounts.any((a) => a <= 0)) {
      throw const SplitPlanException('كلُّ حصّةٍ يجب أن تكون موجبة');
    }
    final sum = amounts.fold<int>(0, (s, a) => s + _units(a));
    if (sum != _units(total)) {
      throw SplitPlanException(
          'مجموعُ الحصص ${sum / _factor} لا يساوي الإجماليَّ $total');
    }
    final parts = <SplitPart>[
      for (var i = 0; i < amounts.length; i++)
        SplitPart(amount: amounts[i], label: 'ضيف ${i + 1}'),
    ];
    return SplitPlan._(SplitMode.byAmounts, parts);
  }

  /// التقسيمُ بالأصناف — كلُّ بندٍ يُسنَد إلى دافع، ولا يُترك بندٌ بلا صاحب.
  factory SplitPlan.byItems({
    required List<SplitItem> items,
    required Map<int, int> assignment,
    required int ways,
  }) {
    if (ways < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    final amounts = List<int>.filled(ways, 0);
    final quantities = List<Map<int, double>>.generate(ways, (_) => {});
    for (final item in items) {
      final owner = assignment[item.itemId];
      if (owner == null) {
        throw SplitPlanException('البندُ ${item.itemId} بلا صاحب');
      }
      if (owner < 0 || owner >= ways) {
        throw SplitPlanException('صاحبُ البند ${item.itemId} خارج النطاق');
      }
      amounts[owner] += _units(item.lineTotal);
      quantities[owner][item.itemId] = item.quantity;
    }
    final parts = <SplitPart>[
      for (var i = 0; i < ways; i++)
        SplitPart(
          amount: amounts[i] / _factor,
          label: 'ضيف ${i + 1}',
          itemQuantities: quantities[i],
        ),
    ];
    return SplitPlan._(SplitMode.byItems, parts);
  }

  /// هل تُصدر هذه الخطّةُ فاتورةً لكلّ دافع؟
  ///
  /// نعم في التقسيم بالأصناف وحده — هناك حدودٌ صنفيّةٌ فلكلّ فاتورةٍ أصنافُها.
  /// أمّا بالتساوي وبمبلغ فلا حدودَ صنفيّة، وإصدارُ فواتيرَ منفصلةٍ يعني
  /// كميّاتٍ كسريّةً على إيصال الزبون («٠٫٢٥ بطاطا») تبدو عطلاً — فالمبيعةُ
  /// واحدةٌ والدافعون عدّة.
  bool get producesSeparateInvoices => mode == SplitMode.byItems;
}
```

- [ ] **Step 4: شغّل الاختبار وتأكّد أنه ينجح**

```bash
flutter test test/unit/split_plan_test.dart
```

المتوقَّع: `+13: All tests passed!`

- [ ] **Step 5: تأكّد أن التحليل نظيف**

```bash
flutter analyze lib/domain/models/split_plan.dart test/unit/split_plan_test.dart
```

المتوقَّع: `No issues found!`

- [ ] **Step 6: أودِع**

```bash
git add lib/domain/models/split_plan.dart test/unit/split_plan_test.dart
git commit -m "feat(tables): حسابُ الحصص يجمع الإجماليَّ بالضبط لا تقريباً"
```

---

## Task 2: المخطّط والهجرة — تمريرةُ `build_runner` الوحيدة

**Files:**
- Modify: `lib/data/database/tables/restaurant_tables.dart`
- Modify: `lib/data/database/database.dart` (سطر ٣٦٨ لتسجيل الجدول، وسطر ٦٩٦ لرقم المخطّط)
- Modify: `lib/data/database/migrations/epoch_3.dart` (الذيل)
- Test: `test/unit/table_service_schema_test.dart`

**Interfaces:**
- Produces: أعمدة `TableOrders.guestCount/notes/discountType/discountValue/paidAmount`، وأعمدة `TableOrderItems.notes/sourceTableOrderId`، وجدول `TableOrderPayments`. تستهلكها المهامّ ٣ إلى ٧.

- [ ] **Step 1: أضف الأعمدة والجدول**

في `lib/data/database/tables/restaurant_tables.dart`، داخل `class TableOrders` وقبل `openedAt`:

```dart
  /// عددُ الأشخاص — يُسأل عند فتح الطاولة، وهو مقامُ التقسيم بالتساوي.
  IntColumn get guestCount => integer().withDefault(const Constant(1))();

  /// ملاحظةُ الطلب — تنتقل مع الطلب عند النقل.
  TextColumn get notes => text().nullable()();

  /// نوعُ خصم الطلب: `percent` أو `amount`.
  TextColumn get discountType => text().nullable()();

  /// قيمةُ الخصم بحسب نوعه. يُثبَّت قبل الدفع فينتقل ويُطبع.
  RealColumn get discountValue => real().withDefault(const Constant(0))();

  /// مجموعُ ما حُصِّل. تُشتقّ منه حالةُ الطاولة: `occupied` حتى يبلغ
  /// `total`، ثم `paid`. لا حالةَ سادسةً للدفع الجزئي.
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
```

داخل `class TableOrderItems` وقبل `addedAt`:

```dart
  /// ملاحظةُ البند («بلا بصل») — تصل المطبخ وتُطبع.
  TextColumn get notes => text().nullable()();

  /// الطلبُ الذي جاء منه هذا البند بعد الدمج. فارغٌ للأصناف الأصلية.
  /// وجودُه هو ما يجعل الطباعةَ مجمَّعةً وفكَّ الدمج ممكناً.
  IntColumn get sourceTableOrderId =>
      integer().nullable().references(TableOrders, #id)();
```

وفي آخر الملف:

```dart
/// دفعةٌ واحدةٌ على طلبِ طاولة — صفٌّ لكلّ دافع.
///
/// هو ما يجعل «عدّةَ فواتيرَ لطلبٍ واحد» ممكناً (التقسيم بالأصناف)، ويحتمل
/// في الوقت نفسه «فاتورةً واحدةً بعدّة دفعات» (التقسيم بالتساوي/بمبلغ) إذ
/// يتكرّر `invoiceId`. ولذلك لم يُضَف عمودٌ إلى `SalesInvoices`: هي جدولٌ
/// مشترَكٌ مع UralCash يُنقل بـpatch، ولا يعرف الطاولات.
class TableOrderPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tableOrderId => integer().references(TableOrders, #id)();
  IntColumn get invoiceId => integer().references(SalesInvoices, #id)();
  RealColumn get amount => real()();
  TextColumn get splitLabel => text().nullable()(); // «ضيف ١»
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
}
```

- [ ] **Step 2: سجّل الجدول وارفع رقم المخطّط**

في `lib/data/database/database.dart` بعد السطر ٣٦٨ (`TableReservations, // NEW: Table reservations`):

```dart
    TableOrderPayments, // v154: دفعةٌ لكلّ دافعٍ على طلب الطاولة
```

وفي السطر ٦٩٦:

```dart
  int get schemaVersion => 154;
```

> **تنبيهُ دمج:** إن كانت الجلسةُ الأخرى أخذت ١٥٤ أيضاً، فالفرعُ الثاني في الدمج يجعلها ١٥٥ ويُحرّك كتلةَ الهجرة أدناه بعد كتلتها. لا شيءَ آخرَ يتغيّر.

- [ ] **Step 3: أضف كتلةَ الهجرة**

في ذيل `lib/data/database/migrations/epoch_3.dart`، بعد كتلة `if (from < 153)` مباشرةً وقبل قوسَي الإغلاق:

```dart
    // ── v154: خدمةُ الطاولات — الحالةُ المدفوعة والخصمُ والدفعاتُ المتعدّدة ──
    if (from < 154) {
      await _safeMigrate('v154 table service columns + table_order_payments',
          () async {
        await m.addColumn(tableOrders, tableOrders.guestCount);
        await m.addColumn(tableOrders, tableOrders.notes);
        await m.addColumn(tableOrders, tableOrders.discountType);
        await m.addColumn(tableOrders, tableOrders.discountValue);
        await m.addColumn(tableOrders, tableOrders.paidAmount);
        await m.addColumn(tableOrderItems, tableOrderItems.notes);
        await m.addColumn(
            tableOrderItems, tableOrderItems.sourceTableOrderId);
        await m.createTable(tableOrderPayments);
        debugPrint('[Migration] v154 table service OK');
      });
    }
```

الهجرةُ إضافيّةٌ بحتة: كلُّ عمودٍ له قيمةٌ افتراضيّة أو يقبل العدم، ولا ترحيلَ بيانات.

- [ ] **Step 4: شغّل `build_runner` — مرّةً واحدة، ولا تقتله**

```bash
dart run build_runner build --delete-conflicting-outputs
```

المتوقَّع: ~٤١ دقيقة، منها ~٤٠ صامتةٌ بلا نموٍّ في الكاش. **هذا سلوكٌ طبيعيٌّ مقيسٌ في هذه البيئة، لا تعليق.** شغّله في الخلفية.

- [ ] **Step 5: أثبت أن الأعمدة وصلت فعلاً**

`test/unit/table_service_schema_test.dart`:

```dart
// إثباتُ وصولِ مخطّط v154. `build_runner` قد ينجح ظاهرياً ويُنقص المولَّد
// بصمتٍ، و`flutter analyze` لا يكشفها. هذا الاختبار يكشفها.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('أعمدةُ TableOrders الجديدة تُكتب وتُقرأ', () async {
    final tableId = await db.createTable(name: 'ط١');
    final orderId = await db.into(db.tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: tableId,
            guestCount: const Value(4),
            notes: const Value('بجانب النافذة'),
            discountType: const Value('percent'),
            discountValue: const Value(10),
            paidAmount: const Value(25.5),
          ),
        );

    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();

    expect(order.guestCount, 4);
    expect(order.notes, 'بجانب النافذة');
    expect(order.discountType, 'percent');
    expect(order.discountValue, 10);
    expect(order.paidAmount, 25.5);
  });

  test('عددُ الأشخاص الافتراضيُّ واحد ولا يكون عدماً', () async {
    final tableId = await db.createTable(name: 'ط٢');
    final orderId = await db.createTableOrder(tableId);
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.guestCount, 1);
    expect(order.paidAmount, 0);
  });

  test('جدولُ TableOrderPayments موجودٌ ويقبل صفّاً', () async {
    final tableId = await db.createTable(name: 'ط٣');
    final orderId = await db.createTableOrder(tableId);

    final paymentId = await db.into(db.tableOrderPayments).insert(
          TableOrderPaymentsCompanion.insert(
            tableOrderId: orderId,
            invoiceId: 1,
            amount: 33.334,
            splitLabel: const Value('ضيف ٣'),
          ),
        );

    final row = await (db.select(db.tableOrderPayments)
          ..where((p) => p.id.equals(paymentId)))
        .getSingle();
    expect(row.amount, 33.334);
    expect(row.splitLabel, 'ضيف ٣');
  });

  test('مصدرُ البند يُحفَظ على بند الطلب', () async {
    final tableId = await db.createTable(name: 'ط٤');
    final orderId = await db.createTableOrder(tableId);
    final itemId = await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 1,
            quantity: 1,
            unitPrice: 10,
            total: 10,
            notes: const Value('بلا بصل'),
            sourceTableOrderId: Value(orderId),
          ),
        );
    final item = await (db.select(db.tableOrderItems)
          ..where((i) => i.id.equals(itemId)))
        .getSingle();
    expect(item.notes, 'بلا بصل');
    expect(item.sourceTableOrderId, orderId);
  });
}
```

- [ ] **Step 6: شغّل الاختبار**

```bash
flutter test test/unit/table_service_schema_test.dart
```

المتوقَّع: `+4: All tests passed!`. لو فشل بـ`no such column` فالمولَّدُ ناقص — أعِد `build_runner`، **ولا تُصلح `database.g.dart` بيدك**.

- [ ] **Step 7: أودِع**

```bash
git add lib/data/database/ test/unit/table_service_schema_test.dart
git commit -m "feat(db): v154 — الطلبُ يحمل ضيوفَه وخصمَه ومدفوعَه، والدفعةُ تصير صفّاً"
```

---

## Task 3: `TableSessionService` — الفتحُ والإغلاقُ والإلغاءُ وتغييرُ الحالة

**Files:**
- Create: `lib/domain/models/table_status.dart`
- Create: `lib/services/table_session_service.dart`
- Test: `test/unit/table_session_service_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` وامتداداتِ `TablesDao` و`ActivityLogsDao`
- Produces: `TableStatus`، `TableTransitionException`، و`TableSessionService` بالدوالّ: `openTable`، `closeTable`، `cancelOrder`، `setTableStatus`. تُوسَّع الفئةُ نفسُها في المهامّ ٤ إلى ٧.

- [ ] **Step 1: اكتب الاختبار الفاشل**

`test/unit/table_session_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
  });
  tearDown(() => db.close());

  Future<int> newTable(String name) => db.createTable(name: name);

  Future<RestaurantTable> readTable(int id) =>
      (db.select(db.restaurantTables)..where((t) => t.id.equals(id)))
          .getSingle();

  group('openTable', () {
    test('يفتح طاولةً متاحةً ويثبّت عددَ الأشخاص', () async {
      final t = await newTable('ط٧');
      final orderId = await service.openTable(
          tableId: t, guestCount: 4, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.occupied);
      final order = await db.getActiveOrderForTable(t);
      expect(order!.id, orderId);
      expect(order.guestCount, 4);
    });

    test('يكتب سطراً في السجل', () async {
      final t = await newTable('ط٨');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.entityType.equals('table')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.action, 'table_open');
      expect(logs.single.entityId, t);
    });

    test('يرفض طاولةً مشغولة', () async {
      final t = await newTable('ط٩');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.openTable(
            tableId: t, guestCount: 2, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض عددَ أشخاصٍ أقلَّ من واحد', () async {
      final t = await newTable('ط١٠');
      expect(
        () => service.openTable(
            tableId: t, guestCount: 0, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('closeTable', () {
    test('يرفض الإغلاقَ قبل اكتمال الدفع', () async {
      final t = await newTable('ط١١');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(60)));

      expect(
        () => service.closeTable(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
      expect((await readTable(t)).status, TableStatus.occupied);
    });

    test('يُغلق ويُحرّر الطاولة عند اكتمال الدفع', () async {
      final t = await newTable('ط١٢');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(100)));

      await service.closeTable(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);
      expect(await db.getActiveOrderForTable(t), isNull);
    });
  });

  group('cancelOrder', () {
    test('يرفض إلغاءَ طلبٍ دُفع منه شيء', () async {
      final t = await newTable('ط١٣');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(40)));

      expect(
        () => service.cancelOrder(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يُلغي طلباً بكراً ويُحرّر الطاولة', () async {
      final t = await newTable('ط١٤');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await service.cancelOrder(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);
    });
  });

  group('setTableStatus', () {
    test('يُخرج طاولةً متاحةً من الخدمة ويُعيدها', () async {
      final t = await newTable('ط١٥');
      await service.setTableStatus(
          tableId: t,
          status: TableStatus.outOfService,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.outOfService);

      await service.setTableStatus(
          tableId: t,
          status: TableStatus.available,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.available);
    });

    test('يرفض إخراجَ طاولةٍ عليها طلبٌ من الخدمة', () async {
      final t = await newTable('ط١٦');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.setTableStatus(
            tableId: t,
            status: TableStatus.outOfService,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: فشلُ تحميلٍ — `Target of URI doesn't exist: 'package:ural_erp/services/table_session_service.dart'`.

- [ ] **Step 3: اكتب `TableStatus`**

`lib/domain/models/table_status.dart`:

```dart
/// حالاتُ الطاولة الخمس.
///
/// المخطّطُ كان يذكر ثمانيَ حالاتٍ في تعليق (`seated, ordered, eating,
/// billing, cleaning`) أكثرُها غيرُ مستعمَل. و`billing` تحديداً صفةٌ للطلب
/// (`TableOrders.status = 'bill_requested'`) لا للطاولة.
abstract final class TableStatus {
  /// 🟢 لا طلبَ عليها.
  static const available = 'available';

  /// 🔵 طلبٌ مفتوح — ولو دُفع منه جزء.
  static const occupied = 'occupied';

  /// 🟠 سُدِّد كاملاً ولم يُغلَق بعد.
  static const paid = 'paid';

  /// 🔴 حجزٌ مسبق.
  static const reserved = 'reserved';

  /// ⚪ خارج الخدمة.
  static const outOfService = 'out_of_service';

  static const all = [available, occupied, paid, reserved, outOfService];
}
```

- [ ] **Step 4: اكتب الخدمة**

`lib/services/table_session_service.dart`:

```dart
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/constants/app_constants.dart';
import '../data/database/database.dart';
import '../domain/models/table_status.dart';

/// انتقالٌ ممنوعٌ في آلة حالات الطاولة. رسالتُه تُعرَض للمستخدم كما هي.
class TableTransitionException implements Exception {
  const TableTransitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// مالكُ انتقالات الطاولة.
///
/// كلُّ انتقالٍ هنا يفعل شيئين لا واحداً: يُغيّر الحالة، ويكتب سطرَه في
/// `ActivityLogs`. السجلُّ مسلسَلٌ بالهاش (ICR-03) فيصير أثرُ الطاولة
/// غيرَ قابلٍ للتزوير بلا جدولٍ خاصٍّ به.
class TableSessionService {
  TableSessionService(this._db);

  final AppDatabase _db;

  static int get _factor =>
      math.pow(10, AppConstants.decimalPlaces).toInt();

  /// المقارنةُ بوحداتٍ صحيحةٍ لا بـ`double`: ‏٣٣٫٣٣٣×٣ لا يساوي ١٠٠ في
  /// حسابِ الفاصلة العائمة، فمقارنةُ `>=` المباشرة تُبقي طاولةً مدفوعةً
  /// بالكامل عالقةً على 🔵 إلى الأبد.
  static int _units(double value) => (value * _factor).round();

  static bool _isFullyPaid(TableOrder order) =>
      _units(order.paidAmount) >= _units(order.total);

  Future<RestaurantTable> _table(int tableId) => (_db.select(
        _db.restaurantTables,
      )..where((t) => t.id.equals(tableId)))
          .getSingle();

  Future<void> _log({
    required int? userId,
    required String userName,
    required String action,
    required int tableId,
    required String description,
    double? amount,
    String? oldValue,
    String? newValue,
  }) =>
      _db.logActivity(
        userId: userId,
        userName: userName,
        action: action,
        entityType: 'table',
        entityId: tableId,
        description: description,
        amount: amount,
        oldValue: oldValue,
        newValue: newValue,
      );

  /// فتحُ طاولةٍ متاحةٍ أو محجوزةٍ (حضورُ الحجز) بعدد أشخاصٍ محدَّد.
  Future<int> openTable({
    required int tableId,
    required int guestCount,
    required int? userId,
    required String userName,
  }) async {
    if (guestCount < 1) {
      throw const TableTransitionException(
          'عددُ الأشخاص يجب أن يكون واحداً فأكثر');
    }
    return _db.transaction(() async {
      final table = await _table(tableId);
      if (table.status != TableStatus.available &&
          table.status != TableStatus.reserved) {
        throw TableTransitionException(
            'لا يمكن فتحُ ${table.name} — حالتُها الآن ${table.status}');
      }

      final orderId = await _db.into(_db.tableOrders).insert(
            TableOrdersCompanion.insert(
              tableId: tableId,
              userId: Value(userId),
              guestCount: Value(guestCount),
              openedAt: Value(DateTime.now()),
            ),
          );
      await _db.updateTableStatus(tableId, TableStatus.occupied);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_open',
        tableId: tableId,
        description: 'فتح ${table.name} — $guestCount أشخاص',
      );
      return orderId;
    });
  }

  /// إغلاقُ طاولةٍ سُدِّد حسابُها كاملاً — روتينٌ بلا خطر.
  Future<void> closeTable({
    required int tableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final table = await _table(tableId);
      final order = await _db.getActiveOrderForTable(tableId);
      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${table.name}');
      }
      if (!_isFullyPaid(order)) {
        throw TableTransitionException(
            'لا يمكن الإغلاق قبل اكتمال الدفع — دُفع ${order.paidAmount} '
            'من ${order.total}');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(order.id)))
          .write(TableOrdersCompanion(
        status: const Value('closed'),
        closedAt: Value(DateTime.now()),
      ));
      await _db.updateTableStatus(tableId, TableStatus.available);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_close',
        tableId: tableId,
        description: 'إغلاق ${table.name}',
        amount: order.total,
      );
    });
  }

  /// إلغاءُ طلبٍ حيٍّ — هدمٌ. تُشترط له صلاحيةُ `tables_cancel` عند
  /// الاستدعاء، ويُشترط هنا ألّا يكون دُفع منه شيء.
  Future<void> cancelOrder({
    required int tableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final table = await _table(tableId);
      final order = await _db.getActiveOrderForTable(tableId);
      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${table.name}');
      }
      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن إلغاءُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(order.id)))
          .write(TableOrdersCompanion(
        status: const Value('cancelled'),
        closedAt: Value(DateTime.now()),
      ));
      await _db.updateTableStatus(tableId, TableStatus.available);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_order_cancel',
        tableId: tableId,
        description: 'إلغاءُ طلبِ ${table.name}',
        amount: order.total,
      );
    });
  }

  /// إخراجُ الطاولة من الخدمة أو إعادتُها — بين 🟢 و⚪ فقط.
  Future<void> setTableStatus({
    required int tableId,
    required String status,
    required int? userId,
    required String userName,
  }) async {
    if (status != TableStatus.available &&
        status != TableStatus.outOfService) {
      throw TableTransitionException(
          'تغييرُ الحالة اليدويُّ بين المتاحة وغير المتاحة فقط، لا إلى $status');
    }
    await _db.transaction(() async {
      final table = await _table(tableId);
      final order = await _db.getActiveOrderForTable(tableId);
      if (order != null) {
        throw TableTransitionException(
            'على ${table.name} طلبٌ مفتوح — أغلقه أوّلاً');
      }

      await _db.updateTableStatus(tableId, status);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_status_change',
        tableId: tableId,
        description: 'تغييرُ حالة ${table.name}',
        oldValue: table.status,
        newValue: status,
      );
    });
  }
}
```

- [ ] **Step 5: شغّل الاختبار وتأكّد أنه ينجح**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `+11: All tests passed!`

- [ ] **Step 6: أودِع**

```bash
git add lib/domain/models/table_status.dart lib/services/table_session_service.dart test/unit/table_session_service_test.dart
git commit -m "feat(tables): آلةُ الحالات تصير كوداً — الانتقالُ الممنوع يُرمى لا يُتجاهل"
```

---

## Task 4: النقلُ والدمج — الحارسان ووسمُ المصدر

**Files:**
- Modify: `lib/services/table_session_service.dart`
- Modify: `lib/data/database/daos/tables_dao.dart` (`mergeTableOrders`، السطور ٤٨٨–٥٥٣)
- Test: `test/unit/table_session_service_test.dart` (يُضاف)

**Interfaces:**
- Consumes: `TableSessionService`, `TableStatus`, `TableTransitionException` من المهمّة ٣
- Produces: `TableSessionService.transferOrder`, `TableSessionService.mergeOrders` بإرجاع `MergeOutcome`

- [ ] **Step 1: اكتب الاختبارات الفاشلة**

أضِف إلى `test/unit/table_session_service_test.dart` قبل قوس الإغلاق الأخير:

```dart
  group('transferOrder', () {
    test('ينقل الطلبَ بكلّ حقوله ويُحرّر المصدر', () async {
      final from = await newTable('ط٢٠');
      final to = await newTable('ط٢١');
      final orderId = await service.openTable(
          tableId: from, guestCount: 4, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        notes: Value('بجانب النافذة'),
        discountType: Value('percent'),
        discountValue: Value(10),
      ));

      await service.transferOrder(
          fromTableId: from,
          toTableId: to,
          userId: null,
          userName: 'أحمد');

      expect((await readTable(from)).status, TableStatus.available);
      expect((await readTable(to)).status, TableStatus.occupied);

      final moved = await db.getActiveOrderForTable(to);
      expect(moved!.id, orderId, reason: 'رقمُ الطلب نفسُه ينتقل');
      expect(moved.guestCount, 4);
      expect(moved.notes, 'بجانب النافذة');
      expect(moved.discountValue, 10);
    });

    test('يرفض نقلَ طلبٍ دُفع منه شيء', () async {
      final from = await newTable('ط٢٢');
      final to = await newTable('ط٢٣');
      final orderId = await service.openTable(
          tableId: from, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(40)));

      expect(
        () => service.transferOrder(
            fromTableId: from,
            toTableId: to,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض هدفاً غيرَ متاح', () async {
      final from = await newTable('ط٢٤');
      final to = await newTable('ط٢٥');
      await service.openTable(
          tableId: from, guestCount: 2, userId: null, userName: 'أحمد');
      await service.openTable(
          tableId: to, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.transferOrder(
            fromTableId: from,
            toTableId: to,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('mergeOrders', () {
    Future<void> addItem(int orderId, int productId, double qty,
            double price) =>
        db.into(db.tableOrderItems).insert(
              TableOrderItemsCompanion.insert(
                tableOrderId: orderId,
                productId: productId,
                quantity: qty,
                unitPrice: price,
                total: qty * price,
              ),
            );

    test('لا يجمع كميّاتِ المتشابه ويوسم كلَّ بندٍ بمصدره', () async {
      final t5 = await newTable('ط٥');
      final t6 = await newTable('ط٦');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 3, userId: null, userName: 'أحمد');
      await addItem(o5, 1, 2, 10); // نفسُ المنتج على الطاولتين
      await addItem(o6, 1, 1, 10);

      await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      final items = await db.getTableOrderItems(o5);
      expect(items, hasLength(2),
          reason: 'بندان منفصلان لا بندٌ واحدٌ بكميّة ٣');
      final fromSix =
          items.firstWhere((i) => i.sourceTableOrderId == o6);
      expect(fromSix.quantity, 1);
      expect(items.where((i) => i.sourceTableOrderId == null), hasLength(1));
    });

    test('يجمع عددَ الضيوف ويُحرّر المصدر', () async {
      final t5 = await newTable('ط٣٠');
      final t6 = await newTable('ط٣١');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 3, userId: null, userName: 'أحمد');
      await addItem(o6, 1, 1, 10);

      await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      final merged = await db.getActiveOrderForTable(t5);
      expect(merged!.guestCount, 5);
      expect((await readTable(t6)).status, TableStatus.available);
      final source = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(o6)))
          .getSingle();
      expect(source.mergedToId, o5);
    });

    test('خصمُ المدموجة يسقط ويُبلَّغ عنه', () async {
      final t5 = await newTable('ط٣٢');
      final t6 = await newTable('ط٣٣');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      final o6 = await service.openTable(
          tableId: t6, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o5)))
          .write(const TableOrdersCompanion(
              discountType: Value('percent'), discountValue: Value(10)));
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o6)))
          .write(const TableOrdersCompanion(
              discountType: Value('amount'), discountValue: Value(5)));
      await addItem(o6, 1, 1, 10);

      final outcome = await service.mergeOrders(
          sourceTableId: t6,
          targetTableId: t5,
          userId: null,
          userName: 'أحمد');

      expect(outcome.droppedDiscount, isTrue);
      final merged = await db.getActiveOrderForTable(t5);
      expect(merged!.discountType, 'percent');
      expect(merged.discountValue, 10, reason: 'خصمُ الرئيسية يبقى وحده');
    });

    test('يرفض الدمجَ إن دُفع من أيٍّ منهما شيء', () async {
      final t5 = await newTable('ط٣٤');
      final t6 = await newTable('ط٣٥');
      final o5 = await service.openTable(
          tableId: t5, guestCount: 2, userId: null, userName: 'أحمد');
      await service.openTable(
          tableId: t6, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(o5)))
          .write(const TableOrdersCompanion(
              total: Value(50), paidAmount: Value(20)));

      expect(
        () => service.mergeOrders(
            sourceTableId: t6,
            targetTableId: t5,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });
```

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: فشلُ تصريفٍ — `The method 'transferOrder' isn't defined for the type 'TableSessionService'`.

- [ ] **Step 3: أوقف تجميعَ الكميّات في الـDAO**

في `lib/data/database/daos/tables_dao.dart`، استبدل جسمَ حلقة `for (final item in sourceItems)` داخل `mergeTableOrders` (السطور ٥٠٢–٥٣٣) بهذا:

```dart
      for (final item in sourceItems) {
        // لا بحثَ عن متشابهٍ في الهدف ولا جمعَ كميّات: البندُ يُنقل كما هو
        // موسوماً بمصدره. جمعُ الكميّات يمحو أصلَ الصنف فيسقط فكُّ الدمج
        // والطباعةُ المجمَّعة ونسبةُ الصنف إلى نادله.
        await (update(tableOrderItems)..where((i) => i.id.equals(item.id)))
            .write(TableOrderItemsCompanion(
          tableOrderId: Value(targetOrder.id),
          sourceTableOrderId: Value(item.sourceTableOrderId ?? sourceOrder.id),
        ));
      }
```

`item.sourceTableOrderId ?? sourceOrder.id` يحفظ المصدرَ **الأصلي** عند دمجِ مدموجٍ سابقاً، فلا يُعاد وسمُه بالوسيط.

- [ ] **Step 4: أضف الدالّتين إلى الخدمة**

في `lib/services/table_session_service.dart`، أضِف قبل قوس إغلاق الفئة:

```dart
  /// نتيجةُ دمجٍ — تُبلِّغ الواجهةَ بما سقط ليُعرَض في التأكيد.
  Future<MergeOutcome> mergeOrders({
    required int sourceTableId,
    required int targetTableId,
    required int? userId,
    required String userName,
  }) async {
    return _db.transaction(() async {
      final source = await _table(sourceTableId);
      final target = await _table(targetTableId);
      final sourceOrder = await _db.getActiveOrderForTable(sourceTableId);
      final targetOrder = await _db.getActiveOrderForTable(targetTableId);

      if (sourceOrder == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${source.name}');
      }
      if (targetOrder == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${target.name}');
      }
      if (_units(sourceOrder.paidAmount) > 0 ||
          _units(targetOrder.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن دمجُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }

      final droppedDiscount = _units(sourceOrder.discountValue) > 0;

      await _db.mergeTableOrders(sourceTableId, targetTableId);

      // الضيوفُ يُجمعون: صاروا على طاولةٍ واحدة.
      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(targetOrder.id)))
          .write(TableOrdersCompanion(
        guestCount:
            Value(targetOrder.guestCount + sourceOrder.guestCount),
      ));

      await _log(
        userId: userId,
        userName: userName,
        action: 'table_merge',
        tableId: targetTableId,
        description: 'دمجُ ${source.name} في ${target.name}'
            '${droppedDiscount ? ' — أُسقط خصمُ ${source.name}' : ''}',
        amount: sourceOrder.total,
      );

      return MergeOutcome(
        droppedDiscount: droppedDiscount,
        droppedDiscountLabel: droppedDiscount
            ? '${sourceOrder.discountValue}'
                '${sourceOrder.discountType == 'percent' ? '٪' : ''}'
            : null,
      );
    });
  }

  /// نقلُ الطلبِ كاملاً إلى طاولةٍ متاحة.
  ///
  /// كلُّ ما تُعدّده المواصفة — رقمُ الطلب والأصناف والكميّات والملاحظات
  /// والخصومات والضرائب والموظف والإجمالي والحالة — حقولٌ في صفِّ الطلب
  /// الواحد. فالنقلُ تحديثُ `tableId` لا غير، وينتقل كلُّ ذلك بلا احتمالِ
  /// ضياع.
  Future<void> transferOrder({
    required int fromTableId,
    required int toTableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final from = await _table(fromTableId);
      final to = await _table(toTableId);
      final order = await _db.getActiveOrderForTable(fromTableId);

      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${from.name}');
      }
      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن نقلُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }
      if (to.status != TableStatus.available) {
        throw TableTransitionException('${to.name} غيرُ متاحة');
      }

      await _db.transferTableOrder(fromTableId, toTableId);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_transfer',
        tableId: toTableId,
        description:
            'نقلُ الطلب #${order.id} من ${from.name} إلى ${to.name}',
        amount: order.total,
        oldValue: from.name,
        newValue: to.name,
      );
    });
  }
```

وفي آخر الملف، خارج الفئة:

```dart
/// ما سقط في الدمج — تعرضه الواجهةُ في نافذة التأكيد.
class MergeOutcome {
  const MergeOutcome({
    required this.droppedDiscount,
    this.droppedDiscountLabel,
  });

  /// هل كان على الطاولة المدموجة خصمٌ أُسقط؟
  ///
  /// خصمُ الرئيسية يبقى وحدَه. جمعُ الخصمين يعني أن خصماً مُنح لأربعةٍ صار
  /// يُطبَّق على ثمانية — تسريبُ مالٍ صامت.
  final bool droppedDiscount;
  final String? droppedDiscountLabel;
}
```

- [ ] **Step 5: شغّل الاختبار**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `+18: All tests passed!`

- [ ] **Step 6: تأكّد أنك لم تكسر ما كان يعتمد على الدمج القديم**

```bash
flutter test test/unit test/data test/structural test/services --concurrency=4
```

المتوقَّع: صفرُ فشل. لو فشل اختبارٌ قائمٌ يؤكّد جمعَ الكميّات، فهو يوثّق السلوكَ القديم — حدّثه ليؤكّد الجديد، ولا تُرجع الدمج.

- [ ] **Step 7: أودِع**

```bash
git add lib/services/table_session_service.dart lib/data/database/daos/tables_dao.dart test/unit/table_session_service_test.dart
git commit -m "feat(tables): الدمجُ يحفظ أصلَ البند، والنقلُ يقف عند أوّل دينارٍ مدفوع"
```

---

## Task 5: الخصمُ وملاحظاتُ البند

**Files:**
- Modify: `lib/services/table_session_service.dart`
- Test: `test/unit/table_session_service_test.dart` (يُضاف)

**Interfaces:**
- Produces: `TableSessionService.setOrderDiscount`, `TableSessionService.setItemNotes`, `TableSessionService.effectiveTotal`

- [ ] **Step 1: اكتب الاختبارات الفاشلة**

```dart
  group('setOrderDiscount', () {
    test('خصمٌ نسبيٌّ يُثبَّت ويُسجَّل بقيمته القديمة والجديدة', () async {
      final t = await newTable('ط٤٠');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await service.setOrderDiscount(
          orderId: orderId,
          type: 'percent',
          value: 10,
          userId: null,
          userName: 'أحمد');

      final order = await db.getActiveOrderForTable(t);
      expect(order!.discountType, 'percent');
      expect(order.discountValue, 10);

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.action.equals('table_discount')))
          .get();
      expect(logs.single.newValue, 'percent:10.0');
    });

    test('نسبةٌ فوق ١٠٠٪ تُرفض', () async {
      final t = await newTable('ط٤١');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'percent',
            value: 120,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('خصمٌ يتجاوز الإجماليَّ يُرفض', () async {
      final t = await newTable('ط٤٢');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(total: Value(50)));

      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'amount',
            value: 60,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض تعديلَ خصمِ طلبٍ دُفع منه شيء', () async {
      final t = await newTable('ط٤٣');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(30)));

      expect(
        () => service.setOrderDiscount(
            orderId: orderId,
            type: 'percent',
            value: 10,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('effectiveTotal', () {
    test('النسبةُ تُطبَّق على الإجمالي', () async {
      final t = await newTable('ط٤٤');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        total: Value(100),
        discountType: Value('percent'),
        discountValue: Value(10),
      ));
      expect(await service.effectiveTotal(orderId), 90);
    });

    test('المبلغُ يُطرح كما هو', () async {
      final t = await newTable('ط٤٥');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
        total: Value(100),
        discountType: Value('amount'),
        discountValue: Value(15),
      ));
      expect(await service.effectiveTotal(orderId), 85);
    });
  });

  group('setItemNotes', () {
    test('الملاحظةُ تُحفظ على البند', () async {
      final t = await newTable('ط٤٦');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      final itemId = await db.into(db.tableOrderItems).insert(
            TableOrderItemsCompanion.insert(
              tableOrderId: orderId,
              productId: 1,
              quantity: 1,
              unitPrice: 10,
              total: 10,
            ),
          );

      await service.setItemNotes(orderItemId: itemId, notes: 'بلا بصل');

      final item = await (db.select(db.tableOrderItems)
            ..where((i) => i.id.equals(itemId)))
          .getSingle();
      expect(item.notes, 'بلا بصل');
    });
  });
```

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `The method 'setOrderDiscount' isn't defined`.

- [ ] **Step 3: نفّذ**

أضِف إلى `TableSessionService`:

```dart
  /// الإجماليُّ بعد الخصم — وهو ما يُقسَّم ويُدفع ويُطبع.
  Future<double> effectiveTotal(int orderId) async {
    final order = await (_db.select(_db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    return _effectiveTotalOf(order);
  }

  static double _effectiveTotalOf(TableOrder order) {
    if (order.discountType == null || order.discountValue <= 0) {
      return order.total;
    }
    final discount = order.discountType == 'percent'
        ? order.total * order.discountValue / 100
        : order.discountValue;
    final net = _units(order.total) - _units(discount);
    return (net < 0 ? 0 : net) / _factor;
  }

  /// تثبيتُ خصمٍ على الطلب قبل الدفع.
  ///
  /// تُشترط صلاحيةُ `tables_discount` عند الاستدعاء. وتثبيتُه على الطلب —
  /// لا في السلة لحظةَ الدفع — هو ما يجعله ينتقل مع الطلب ويظهر في فاتورة
  /// ما قبل الدفع.
  Future<void> setOrderDiscount({
    required int orderId,
    required String? type,
    required double value,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final order = await (_db.select(_db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();

      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن تعديلُ خصمِ طلبٍ دُفع منه شيء');
      }
      if (type != null && type != 'percent' && type != 'amount') {
        throw TableTransitionException('نوعُ خصمٍ غيرُ معروف: $type');
      }
      if (value < 0) {
        throw const TableTransitionException('الخصمُ لا يكون سالباً');
      }
      if (type == 'percent' && value > 100) {
        throw const TableTransitionException('النسبةُ لا تتجاوز ١٠٠٪');
      }
      if (type == 'amount' && _units(value) > _units(order.total)) {
        throw TableTransitionException(
            'الخصمُ $value يتجاوز إجماليَّ الطلب ${order.total}');
      }

      await (_db.update(_db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(
        discountType: Value(type),
        discountValue: Value(type == null ? 0 : value),
      ));

      await _log(
        userId: userId,
        userName: userName,
        action: 'table_discount',
        tableId: order.tableId,
        description: 'تعديلُ خصمِ الطلب #$orderId',
        oldValue: '${order.discountType}:${order.discountValue}',
        newValue: type == null ? 'none' : '$type:$value',
      );
    });
  }

  /// ملاحظةُ بندٍ («بلا بصل») — تصل المطبخ وتُطبع.
  Future<void> setItemNotes({
    required int orderItemId,
    required String? notes,
  }) async {
    await (_db.update(_db.tableOrderItems)
          ..where((i) => i.id.equals(orderItemId)))
        .write(TableOrderItemsCompanion(notes: Value(notes)));
  }
```

- [ ] **Step 4: شغّل الاختبار**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `+26: All tests passed!`

- [ ] **Step 5: أودِع**

```bash
git add lib/services/table_session_service.dart test/unit/table_session_service_test.dart
git commit -m "feat(tables): الخصمُ يعيش على الطلب فينتقل معه بدل أن يموت في السلة"
```

---

## Task 6: الدفعاتُ والحالةُ المدفوعة

**Files:**
- Modify: `lib/services/table_session_service.dart`
- Test: `test/unit/table_session_service_test.dart` (يُضاف)

**Interfaces:**
- Produces: `TableSessionService.recordPayment`, `TableSessionService.paymentsFor`. تستهلكها المهامّ ٧ و١٢.

- [ ] **Step 1: اكتب الاختبارات الفاشلة**

```dart
  group('recordPayment', () {
    Future<int> orderWithTotal(int tableId, double total) async {
      final orderId = await service.openTable(
          tableId: tableId, guestCount: 4, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(total: Value(total)));
      return orderId;
    }

    test('دفعةٌ جزئيّةٌ تُبقي الطاولة مشغولة', () async {
      final t = await newTable('ط٥٠');
      final orderId = await orderWithTotal(t, 100);

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40, splitLabel: 'ضيف ١');

      expect((await readTable(t)).status, TableStatus.occupied);
      final order = await db.getActiveOrderForTable(t);
      expect(order!.paidAmount, 40);
    });

    test('اكتمالُ المبلغ يقلب الطاولة إلى مدفوعة', () async {
      final t = await newTable('ط٥١');
      final orderId = await orderWithTotal(t, 100);

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 40, splitLabel: 'ضيف ١');
      await service.recordPayment(
          orderId: orderId, invoiceId: 2, amount: 60, splitLabel: 'ضيف ٢');

      expect((await readTable(t)).status, TableStatus.paid);
    });

    test('ثلاثُ حصصٍ من ١٠٠÷٣ تُكمل المبلغ ولا تترك مليماً', () async {
      final t = await newTable('ط٥٢');
      final orderId = await orderWithTotal(t, 100);

      for (final amount in [33.333, 33.333, 33.334]) {
        await service.recordPayment(
            orderId: orderId, invoiceId: 1, amount: amount);
      }

      expect((await readTable(t)).status, TableStatus.paid,
          reason: 'المقارنةُ بالوحدات لا بـdouble');
    });

    test('الخصمُ يخفض المبلغَ الواجب', () async {
      final t = await newTable('ط٥٣');
      final orderId = await orderWithTotal(t, 100);
      await service.setOrderDiscount(
          orderId: orderId,
          type: 'percent',
          value: 10,
          userId: null,
          userName: 'أحمد');

      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 90);

      expect((await readTable(t)).status, TableStatus.paid);
    });

    test('دفعةٌ تتجاوز المتبقّي تُرفض', () async {
      final t = await newTable('ط٥٤');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 60);

      expect(
        () => service.recordPayment(
            orderId: orderId, invoiceId: 2, amount: 50),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('الدفعاتُ تُقرأ مرتّبةً بحصصها', () async {
      final t = await newTable('ط٥٥');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 7, amount: 40, splitLabel: 'ضيف ١');
      await service.recordPayment(
          orderId: orderId, invoiceId: 8, amount: 60, splitLabel: 'ضيف ٢');

      final payments = await service.paymentsFor(orderId);
      expect(payments, hasLength(2));
      expect(payments.first.invoiceId, 7);
      expect(payments.last.splitLabel, 'ضيف ٢');
    });

    test('الإغلاقُ يصير مسموحاً بعد اكتمال الدفع', () async {
      final t = await newTable('ط٥٦');
      final orderId = await orderWithTotal(t, 100);
      await service.recordPayment(
          orderId: orderId, invoiceId: 1, amount: 100);

      await service.closeTable(tableId: t, userId: null, userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.available);
    });
  });
```

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `The method 'recordPayment' isn't defined`.

- [ ] **Step 3: عدّل `_isFullyPaid` ليحترم الخصم**

في `TableSessionService`، استبدل `_isFullyPaid` بـ:

```dart
  static bool _isFullyPaid(TableOrder order) =>
      _units(order.paidAmount) >= _units(_effectiveTotalOf(order));
```

- [ ] **Step 4: أضف الدالّتين**

```dart
  /// تسجيلُ دفعةٍ على الطلب بعد صدور فاتورتها.
  ///
  /// الحالةُ مشتقّةٌ لا مخزَّنةٌ مرّتين: تبقى الطاولة 🔵 حتى يبلغ
  /// `paidAmount` الإجماليَّ بعد الخصم، فتصير 🟠. ويترتّب على ذلك أثرٌ
  /// مقصود — إن أُضيف صنفٌ بعد دفعةٍ جزئيّة، ارتفع الإجماليُّ فوق المدفوع
  /// فعادت الطاولة 🔵 من تلقائها بلا قاعدةٍ خاصّة.
  Future<void> recordPayment({
    required int orderId,
    required int invoiceId,
    required double amount,
    String? splitLabel,
  }) async {
    if (amount <= 0) {
      throw const TableTransitionException('الدفعةُ يجب أن تكون موجبة');
    }
    await _db.transaction(() async {
      final order = await (_db.select(_db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();

      final due = _units(_effectiveTotalOf(order));
      final already = _units(order.paidAmount);
      if (already + _units(amount) > due) {
        throw TableTransitionException(
            'الدفعةُ $amount تتجاوز المتبقّي ${(due - already) / _factor}');
      }

      await _db.into(_db.tableOrderPayments).insert(
            TableOrderPaymentsCompanion.insert(
              tableOrderId: orderId,
              invoiceId: invoiceId,
              amount: amount,
              splitLabel: Value(splitLabel),
              paidAt: Value(DateTime.now()),
            ),
          );

      final newPaid = (already + _units(amount)) / _factor;
      await (_db.update(_db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(paidAmount: Value(newPaid)));

      if (already + _units(amount) >= due) {
        await _db.updateTableStatus(order.tableId, TableStatus.paid);
      }
    });
  }

  /// دفعاتُ الطلب مرتّبةً بترتيب حدوثها.
  Future<List<TableOrderPayment>> paymentsFor(int orderId) =>
      (_db.select(_db.tableOrderPayments)
            ..where((p) => p.tableOrderId.equals(orderId))
            ..orderBy([(p) => OrderingTerm.asc(p.id)]))
          .get();
```

- [ ] **Step 5: شغّل الاختبار**

```bash
flutter test test/unit/table_session_service_test.dart
```

المتوقَّع: `+33: All tests passed!`

- [ ] **Step 6: أودِع**

```bash
git add lib/services/table_session_service.dart test/unit/table_session_service_test.dart
git commit -m "feat(tables): الدفعُ الجزئيُّ حالةٌ طبيعيّةٌ لا استثناء — والمدفوعةُ تنتظر إغلاقها"
```

---

## Task 7: منسّقُ التقسيم

**Files:**
- Create: `lib/presentation/pos/providers/table_checkout_coordinator.dart`
- Test: `test/unit/table_checkout_coordinator_test.dart`

**Interfaces:**
- Consumes: `SplitPlan` (المهمّة ١)، `TableSessionService.recordPayment` و`effectiveTotal` (المهامّ ٥ و٦)
- Produces: `TableCheckoutCoordinator.buildSplitPlan`, `TableCheckoutCoordinator.settlePart`

**حدٌّ يجب أن يُقال صراحةً:** `checkoutController.processPayment` يقرأ السلّة من Riverpod ([checkout_controller.dart:69](../../../lib/presentation/pos/providers/checkout_controller.dart))، فإنشاءُ الفاتورة مقترنٌ بالسلة بنيوياً ولن يُنقل إلى الخدمة في هذه المهمّة. المنسّقُ هنا رقيق: يحوّل خطّةَ التقسيم إلى تتابعِ «املأ السلّة بحصّةٍ ← ادفع ← سجّل الدفعة». الجزءُ الذي يُختبَر بلا واجهةٍ هو الحساب (`SplitPlan`) والتسجيل (`recordPayment`) — وهما موضعُ الخطر المحاسبيّ. إنشاءُ الفاتورة نفسُه مُختبَرٌ أصلاً في سويّة المبيعات.

- [ ] **Step 1: اكتب الاختبار الفاشل**

`test/unit/table_checkout_coordinator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/split_plan.dart';
import 'package:ural_erp/presentation/pos/providers/table_checkout_coordinator.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;
  late TableCheckoutCoordinator coordinator;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
    coordinator = TableCheckoutCoordinator(db: db, session: service);
  });
  tearDown(() => db.close());

  Future<int> orderOf(double total, {int guests = 4}) async {
    final t = await db.createTable(name: 'ط');
    final orderId = await service.openTable(
        tableId: t, guestCount: guests, userId: null, userName: 'أحمد');
    await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
        .write(TableOrdersCompanion(total: Value(total)));
    return orderId;
  }

  test('التقسيمُ بالتساوي يستعمل عددَ الضيوف مقاماً', () async {
    final orderId = await orderOf(100, guests: 4);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);
    expect(plan.parts, hasLength(4));
    expect(plan.parts.every((p) => p.amount == 25), isTrue);
  });

  test('التقسيمُ بالتساوي يحترم الخصم', () async {
    final orderId = await orderOf(100);
    await service.setOrderDiscount(
        orderId: orderId,
        type: 'percent',
        value: 20,
        userId: null,
        userName: 'أحمد');
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);
    expect(plan.parts.fold<double>(0, (s, p) => s + p.amount), 80);
  });

  test('تسويةُ حصّةٍ تسجّل الدفعةَ وتُقدّم المدفوع', () async {
    final orderId = await orderOf(100);
    final plan = await coordinator.buildSplitPlan(
        orderId: orderId, mode: SplitMode.equal);

    await coordinator.settlePart(
        orderId: orderId, part: plan.parts.first, invoiceId: 11);

    final payments = await service.paymentsFor(orderId);
    expect(payments, hasLength(1));
    expect(payments.single.amount, 25);
    expect(payments.single.invoiceId, 11);
    final order = await (db.select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.paidAmount, 25);
  });

  test('التقسيمُ بالأصناف يُصدر فواتيرَ منفصلة', () async {
    final orderId = await orderOf(100);
    await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 1,
            quantity: 1,
            unitPrice: 60,
            total: 60,
          ),
        );
    await db.into(db.tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: 2,
            quantity: 1,
            unitPrice: 40,
            total: 40,
          ),
        );
    final items = await db.getTableOrderItems(orderId);

    final plan = await coordinator.buildSplitPlan(
      orderId: orderId,
      mode: SplitMode.byItems,
      assignment: {items[0].id: 0, items[1].id: 1},
      ways: 2,
    );

    expect(plan.producesSeparateInvoices, isTrue);
    expect(plan.parts[0].amount, 60);
    expect(plan.parts[1].itemQuantities[items[1].id], 1);
  });
}
```

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_checkout_coordinator_test.dart
```

المتوقَّع: `Target of URI doesn't exist`.

- [ ] **Step 3: نفّذ المنسّق**

`lib/presentation/pos/providers/table_checkout_coordinator.dart`:

```dart
import '../../../data/database/database.dart';
import '../../../domain/models/split_plan.dart';
import '../../../services/table_session_service.dart';

/// يحوّل طلبَ طاولةٍ إلى خطّةِ تقسيمٍ، ويُسوّي حصّةً بعد صدور فاتورتها.
///
/// إنشاءُ الفاتورة نفسُه يبقى في `checkoutController.processPayment` لأنه
/// يقرأ السلّة من Riverpod. هذا المنسّقُ يملك ما يمكن اختبارُه بلا واجهة:
/// بناءُ الخطّة من حالة الطلب، وتسجيلُ الدفعة بعدها.
class TableCheckoutCoordinator {
  TableCheckoutCoordinator({
    required AppDatabase db,
    required TableSessionService session,
  })  : _db = db,
        _session = session;

  final AppDatabase _db;
  final TableSessionService _session;

  /// يبني خطّةَ تقسيمٍ من حالة الطلب.
  ///
  /// [ways] و[assignment] لازمان في `byItems` فقط. وفي `equal` يكون المقام
  /// `ways` إن مُرّر، وإلّا `guestCount` — فعددُ الأشخاص المسؤولُ سُئل عنه
  /// عند فتح الطاولة لهذا الغرض بالذات.
  Future<SplitPlan> buildSplitPlan({
    required int orderId,
    required SplitMode mode,
    int? ways,
    Map<int, int>? assignment,
    List<double>? amounts,
  }) async {
    final order = await (_db.select(_db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    final total = await _session.effectiveTotal(orderId);

    switch (mode) {
      case SplitMode.equal:
        return SplitPlan.equal(
            total: total, ways: ways ?? order.guestCount);
      case SplitMode.byAmounts:
        return SplitPlan.byAmounts(total: total, amounts: amounts ?? const []);
      case SplitMode.byItems:
        final items = await _db.getTableOrderItems(orderId);
        return SplitPlan.byItems(
          items: [
            for (final i in items)
              SplitItem(
                  itemId: i.id, quantity: i.quantity, lineTotal: i.total),
          ],
          assignment: assignment ?? const {},
          ways: ways ?? order.guestCount,
        );
    }
  }

  /// تسجيلُ حصّةٍ بعد صدور فاتورتها.
  Future<void> settlePart({
    required int orderId,
    required SplitPart part,
    required int invoiceId,
  }) =>
      _session.recordPayment(
        orderId: orderId,
        invoiceId: invoiceId,
        amount: part.amount,
        splitLabel: part.label,
      );
}
```

- [ ] **Step 4: شغّل الاختبار**

```bash
flutter test test/unit/table_checkout_coordinator_test.dart
```

المتوقَّع: `+4: All tests passed!`

- [ ] **Step 5: أودِع**

```bash
git add lib/presentation/pos/providers/table_checkout_coordinator.dart test/unit/table_checkout_coordinator_test.dart
git commit -m "feat(tables): خطّةُ التقسيم تُبنى من حالة الطلب، والحصّةُ تُسجَّل بفاتورتها"
```

---

## Task 8: الصلاحيات

**Files:**
- Modify: `lib/core/permissions/permission_codes.dart`
- Test: `test/unit/table_permissions_test.dart`

**Interfaces:**
- Produces: `PermissionCodes.tablesDiscount == 'tables_discount'`

- [ ] **Step 1: اكتب الاختبار الفاشل**

`test/unit/table_permissions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';

void main() {
  test('صلاحيةُ خصم الطاولة مسجَّلةٌ في تصنيف الطاولات', () {
    final entry = PermissionCodes.masterList
        .firstWhere((p) => p['code'] == PermissionCodes.tablesDiscount);
    expect(entry['category'], 'tables');
    expect(entry['name'], isNotEmpty);
  });

  test('طباعةُ فاتورة الطاولة لم تعد محجوزة', () {
    expect(
        PermissionCodes.nonToggleable
            .containsKey(PermissionCodes.tablesPrintBill),
        isFalse);
  });
}
```

> الأسماءُ الفعليّةُ مقيسةٌ من الملف، لا مفترَضة: قائمةُ الصلاحيات اسمُها `masterList` ([permission_codes.dart:911](../../../lib/core/permissions/permission_codes.dart))، وخريطةُ غيرِ القابلة للتفعيل اسمُها `nonToggleable` ([permission_codes.dart:848](../../../lib/core/permissions/permission_codes.dart)).

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_permissions_test.dart
```

- [ ] **Step 3: نفّذ — إضافةً في آخر القوائم لا في وسطها**

بجوار `tablesPrintBill` (السطر ٤٨٢):

```dart
  static const String tablesDiscount = 'tables_discount';
```

في **آخر** قائمة `allPermissions` الخاصّة بتصنيف `tables` (بعد السطر ١٢٢٩):

```dart
    {'code': tablesDiscount, 'name': 'خصمٌ على طلب الطاولة', 'category': 'tables'},
```

واحذف السطر ٨٩١ كاملاً:

```dart
    'tables_print_bill': 'محجوز — الخاصية ما اتبنتش',
```

> الإلحاقُ في الآخر مقصود: `permission_codes.dart` مشترَكٌ مع الجلسة الأخرى، والإضافةُ في الذيل تُبقي أيَّ تعارضٍ سطراً واحداً.

- [ ] **Step 4: شغّل الاختبار وسويّةَ الصلاحيات**

```bash
flutter test test/unit/table_permissions_test.dart test/security
```

المتوقَّع: صفرُ فشل. لو سقط حارسُ إنفاذٍ يطالب بربط الصلاحية الجديدة بنقطةِ إنفاذ، سجّلها في `permission_enforcement_registry.dart` على نمط `tablesTransfer`.

- [ ] **Step 5: أودِع**

```bash
git add lib/core/permissions/ test/unit/table_permissions_test.dart
git commit -m "feat(perms): صلاحيةُ خصم الطاولة، وطباعةُ الفاتورة تخرج من الحجز"
```

---

## Task 9: الكبساتُ تُشتقّ من الحالة

**Files:**
- Create: `lib/domain/models/table_actions.dart`
- Modify: `lib/presentation/screens/tables/table_operations.dart`
- Modify: `lib/presentation/screens/tables/table_card_widget.dart`
- Test: `test/unit/table_actions_test.dart`

**Interfaces:**
- Consumes: `TableStatus` (المهمّة ٣)
- Produces: `TableAction` (enum)، `actionsForStatus(String status)`

القرارُ هنا أن جدولَ الكبسات يصير **دالّةً خالصةً مُختبَرة**، لا شروطاً متناثرةً في `build`. وإلّا عاد الخللُ الذي نُصلحه.

- [ ] **Step 1: اكتب الاختبار الفاشل**

`test/unit/table_actions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_actions.dart';
import 'package:ural_erp/domain/models/table_status.dart';

void main() {
  test('المتاحةُ لا تُظهر دفعاً ولا نقلاً', () {
    final a = actionsForStatus(TableStatus.available);
    expect(a, contains(TableAction.open));
    expect(a, contains(TableAction.reserve));
    expect(a, isNot(contains(TableAction.pay)));
    expect(a, isNot(contains(TableAction.transfer)));
    expect(a, isNot(contains(TableAction.closeTable)));
  });

  test('المشغولةُ تُظهر الإلغاء لا الإغلاق', () {
    final a = actionsForStatus(TableStatus.occupied);
    expect(a, contains(TableAction.cancelOrder));
    expect(a, isNot(contains(TableAction.closeTable)));
    expect(a, containsAll([
      TableAction.addItems,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.pay,
    ]));
  });

  test('المدفوعةُ تُظهر الإغلاق لا الإلغاء ولا الدفع', () {
    final a = actionsForStatus(TableStatus.paid);
    expect(a, contains(TableAction.closeTable));
    expect(a, isNot(contains(TableAction.cancelOrder)));
    expect(a, isNot(contains(TableAction.pay)));
    expect(a, contains(TableAction.addItems),
        reason: 'الإضافةُ بعد الدفع تفتح طلباً جديداً');
    expect(a, contains(TableAction.printBill));
  });

  test('غيرُ المتاحة لا تقبل إلا تغييرَ الحالة والسجل', () {
    final a = actionsForStatus(TableStatus.outOfService);
    expect(a, containsAll([TableAction.changeStatus, TableAction.log]));
    expect(a, hasLength(2));
  });

  test('السجلُّ يظهر في كلّ الحالات', () {
    for (final s in TableStatus.all) {
      expect(actionsForStatus(s), contains(TableAction.log), reason: s);
    }
  });
}
```

- [ ] **Step 2: شغّل وتأكّد من الفشل**

```bash
flutter test test/unit/table_actions_test.dart
```

- [ ] **Step 3: نفّذ الدالّة الخالصة**

`lib/domain/models/table_actions.dart`:

```dart
import 'table_status.dart';

enum TableAction {
  open,
  addItems,
  transfer,
  merge,
  splitBill,
  printBill,
  reserve,
  pay,
  changeStatus,
  cancelOrder,
  closeTable,
  log,
}

/// الكبساتُ المسموحةُ لحالةٍ ما.
///
/// دالّةٌ خالصةٌ مُختبَرة لا شروطٌ متناثرةٌ في `build`: عرضُ «دفع» لطاولةٍ
/// فارغةٍ أو «نقل» لطاولةٍ بلا طلبٍ كان أحدَ العيوب التي نُصلحها، وشرطٌ
/// منسيٌّ في ودجتٍ واحدةٍ يُعيده.
List<TableAction> actionsForStatus(String status) {
  switch (status) {
    case TableStatus.available:
      return const [
        TableAction.open,
        TableAction.reserve,
        TableAction.changeStatus,
        TableAction.log,
      ];
    case TableStatus.occupied:
      return const [
        TableAction.addItems,
        TableAction.transfer,
        TableAction.merge,
        TableAction.splitBill,
        TableAction.printBill,
        TableAction.pay,
        TableAction.cancelOrder,
        TableAction.log,
      ];
    case TableStatus.paid:
      // الإضافةُ هنا تفتح طلباً جديداً وتُعيد الطاولة 🔵 — لا تُعدّل فاتورةً
      // رُحِّلت. والإغلاقُ روتينٌ، بخلاف الإلغاء الذي لا معنى له بعد الدفع.
      return const [
        TableAction.addItems,
        TableAction.printBill,
        TableAction.closeTable,
        TableAction.log,
      ];
    case TableStatus.reserved:
      return const [
        TableAction.open,
        TableAction.changeStatus,
        TableAction.log,
      ];
    case TableStatus.outOfService:
      return const [TableAction.changeStatus, TableAction.log];
    default:
      return const [TableAction.log];
  }
}
```

- [ ] **Step 4: شغّل الاختبار**

```bash
flutter test test/unit/table_actions_test.dart
```

المتوقَّع: `+5: All tests passed!`

- [ ] **Step 5: اربط الواجهة بالدالّة**

في `lib/presentation/screens/tables/table_operations.dart`، ابنِ قائمةَ الكبسات من `actionsForStatus(table.status)` بدل الشروط المتناثرة. لكلّ `TableAction` صفٌّ واحد؛ استعمل نصوصَ المواصفة: فتح طاولة، إضافة طلب، نقل الطلب، دمج الطاولات، تقسيم الفاتورة، طباعة الفاتورة، حجز طاولة، الدفع، تغيير الحالة، **إلغاء الطلب** (بلون الخطر)، **إغلاق الطاولة**، سجل الطاولة.

في `lib/presentation/screens/tables/table_card_widget.dart`:
- أضِف لونَي 🟠 `TableStatus.paid` و⚪ `TableStatus.outOfService` إلى خريطة الألوان الموجودة.
- أظهِر «دُفع {paidAmount} من {effectiveTotal}» على البطاقة حين `paidAmount > 0 && status == occupied`.

- [ ] **Step 6: تأكّد أن التحليل نظيفٌ وأن الويدجت لم تنكسر**

```bash
flutter analyze lib test
```

المتوقَّع: **٦ info** بالضبط — خطُّ الأساس. أيُّ زيادةٍ فشل.

```bash
flutter test test/widget test/presentation --concurrency=4
```

- [ ] **Step 7: أودِع**

```bash
git add lib/domain/models/table_actions.dart lib/presentation/screens/tables/ test/unit/table_actions_test.dart
git commit -m "feat(tables): الكبسةُ تُشتقّ من الحالة — لا دفعَ لطاولةٍ فارغة"
```

---

## Task 10: شاشةُ تقسيم الفاتورة

**Files:**
- Modify: `lib/presentation/screens/tables/split_table_dialog.dart`

الحاليُّ ينقل أصنافاً إلى طاولةٍ أخرى — وهي وظيفةُ «نقلٍ جزئي» لا تقسيمُ فاتورة. يُعاد بناؤه بثلاث ألسنة.

- [ ] **Step 1: اكتب الشاشة على `TableCheckoutCoordinator`**

ثلاثةُ ألسنة، وكلٌّ يبني `SplitPlan` عبر `coordinator.buildSplitPlan`:

- **بالتساوي:** حقلُ عددِ الحصص، مبدئيّاً `order.guestCount`. يعرض الحصصَ الناتجة.
- **بمبلغ:** حقلٌ لكلّ حصّة، ويعرض «المتبقّي» حيّاً. زرُّ التأكيد معطَّلٌ حتى يصير المتبقّي صفراً — والتحقّقُ النهائيّ في `SplitPlan.byAmounts` على أيّ حال.
- **بالأصناف:** قائمةُ البنود، ولكلّ بندٍ منتقي «لمن؟». زرُّ التأكيد معطَّلٌ حتى يُسنَد كلُّ بند.

عند تأكيد حصّة: املأ السلّة بمحتواها ← `checkoutController.processPayment` ← `coordinator.settlePart(orderId:, part:, invoiceId:)`. وأظهِر شريطَ تقدّم «دُفع ٥٠ من ١٠٠».

**التمييزُ الجوهريّ في العرض:** إن كان `plan.producesSeparateInvoices` صحيحاً فكلُّ حصّةٍ تُصدر فاتورةً كاملة؛ وإلّا فالفاتورةُ واحدةٌ للأصناف كلِّها ولكلّ دافعٍ إيصالُ حصّة. اعرض هذا الفرق للكاشير نصّاً قبل التأكيد حتى لا يظنّ أنه أصدر أربعَ فواتيرَ وهو أصدر واحدة.

- [ ] **Step 2: أصلح `requestTableBill` — لا تُعِد حالةً ميتة**

`requestTableBill` القائمة ([tables_dao.dart:291](../../../lib/data/database/daos/tables_dao.dart)) تضع الطاولةَ على `'billing'` — وهي إحدى الحالات الثمانِ التي شطبناها في v154. تركُها يُعيد حالةً ميتةً إلى الجدول من باب الطباعة.

احذف السطر:

```dart
      await updateTableStatus(tableId, 'billing');
```

فتبقى الطاولةُ على حالتها (🔵) ويتغيّر **الطلبُ** وحدَه إلى `bill_requested` — وهو الموضعُ الصحيح: طلبُ الفاتورة صفةٌ للطلب لا للطاولة. وبما أن `updateTableStatus` كان النداءَ الوحيدَ الذي يحتاج `tableId`، احذف الوسيطَ إن لم يبقَ له مستعمِلٌ في الدالّة، وحدّث نداءاتِها.

أضِف اختباراً في `test/unit/table_session_service_test.dart`:

```dart
  test('طلبُ الفاتورة يغيّر الطلبَ لا الطاولة', () async {
    final t = await newTable('ط٦٠');
    final orderId = await service.openTable(
        tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

    await db.requestTableBill(orderId, t);

    expect((await readTable(t)).status, TableStatus.occupied,
        reason: 'billing حالةٌ مشطوبةٌ من الطاولة');
    final order = await db.getActiveOrderForTable(t);
    expect(order!.status, 'bill_requested');
  });
```

- [ ] **Step 3: أخرِج أيَّ استيرادٍ مباشرٍ للقاعدة**

الملفُّ موجودٌ في القائمة البيضاء لحارس `presentation_db_import_guard` بصفته ملفاً قائماً؛ لا تُوسّع اعتمادَه على `data/database`. مرِّر ما تحتاجه عبر `TableCheckoutCoordinator`.

- [ ] **Step 4: تحقّق**

```bash
flutter analyze lib test
```

المتوقَّع: ٦ info.

```bash
flutter test test/structural test/static
```

المتوقَّع: صفرُ فشل — حارسُ الاستيراد ضمنها.

- [ ] **Step 5: أودِع**

```bash
git add lib/presentation/screens/tables/split_table_dialog.dart lib/data/database/daos/tables_dao.dart test/unit/table_session_service_test.dart
git commit -m "feat(tables): التقسيمُ يصير تقسيمَ فاتورةٍ لا نقلَ أصناف"
```

---

## Task 11: سجلُّ الطاولة

**Files:**
- Create: `lib/presentation/screens/tables/table_log_sheet.dart`
- Modify: `lib/domain/repositories/activity_log_repository.dart` (إن لزم استعلامُ كيان)

- [ ] **Step 1: أضف قراءةَ سجلّ كيانٍ إلى المستودع**

إن لم توجد، أضِف إلى `IActivityLogRepository`:

```dart
  /// سجلُّ كيانٍ واحدٍ مرتّباً من الأحدث.
  Future<List<ActivityLog>> logsForEntity({
    required String entityType,
    required int entityId,
    int limit = 100,
  });
```

ونفّذها في `activity_logs_dao.dart` باستعلامٍ على `entityType` و`entityId` مرتّبٍ `OrderingTerm.desc(createdAt)`.

- [ ] **Step 2: اكتب الورقة**

تعرض `logsForEntity(entityType: 'table', entityId: tableId)` سطراً لكلّ حدث: الوقت `HH:mm`، والوصف، والمستخدم، والمبلغ إن وُجد — على نحو ما في المواصفة (٧:٣٠ فتح، ٧:٤٢ إرسال للمطبخ، ٨:٢٠ نقل، ٨:٤٧ الدفع، ٨:٤٨ إغلاق).

**لا تستورد `data/database` مباشرةً** — الملفُّ جديدٌ وحارسُ الاستيراد يرفضه وقائمتُه البيضاء مقفولة. مرّ عبر المستودع.

- [ ] **Step 3: تحقّق**

```bash
flutter analyze lib test
flutter test test/structural test/static
```

- [ ] **Step 4: أودِع**

```bash
git add lib/presentation/screens/tables/table_log_sheet.dart lib/domain/repositories/ lib/data/database/daos/activity_logs_dao.dart
git commit -m "feat(tables): سجلُّ الطاولة يُقرأ من سجلٍّ مسلسَلٍ بالهاش لا من جدولٍ جديد"
```

---

## Task 12: توصيلُ مسار التحصيل بالخدمة

**Files:**
- Modify: `lib/presentation/pos/screens/table_pos_operations.dart` (`_checkoutTable`، السطور ٢٥١–٣٦٠)

- [ ] **Step 1: استبدل `finalizeTableOrder` بتسجيلِ دفعةٍ عبر الخدمة**

في `_checkoutTable`، بعد نجاح الدفع والحصول على `invoiceId`، استبدل السطر ٣٣٤:

```dart
    await restaurantRepo.finalizeTableOrder(orderId, widget.tableId);
```

بـ:

```dart
    // الطاولةُ تصير 🟠 لا 🟢: الدفعُ لا يُغلق، والإغلاقُ خطوةٌ صريحةٌ
    // يقوم بها الموظف بعد تجهيز الطاولة.
    await ref.read(tableSessionServiceProvider).recordPayment(
          orderId: orderId,
          invoiceId: invoiceId!,
          amount: total,
        );
```

واحذف نداءَ `activityLogRepo.logActivity` اليدويَّ التالي له (السطور ٣٣٦–٣٤٩): الخدمةُ تكتب سطرَها، وإبقاءُ الاثنين يُنتج سطرين لحدثٍ واحد.

عدّل رسالةَ النجاح لتقول إن الطاولة صارت **مدفوعةً بانتظار الإغلاق**، لا أنها تحرّرت.

- [ ] **Step 2: أضف مزوّدَ الخدمة**

في ملفِّ المزوّدات المناسب (بجوار `restaurantRepositoryProvider`):

في `lib/data/providers/repository_providers.dart`، بجوار `restaurantRepositoryProvider` (السطر ١٥٥):

```dart
final tableSessionServiceProvider = Provider<TableSessionService>(
  (ref) => TableSessionService(ref.read(databaseProvider)),
);
```

اسمُ مزوّد القاعدة `databaseProvider` مقيسٌ من [providers.dart:47](../../../lib/data/providers/providers.dart) — لا `appDatabaseProvider`.

- [ ] **Step 3: احذف `finalizeTableOrder` الميتة**

بعد أن يخلوَ المستودعُ من نداءاتها، احذفها من `tables_dao.dart` (السطور ٣٠٢–٣١٧) ومن `restaurant_repository.dart` ومن `database_stub.dart` و`database_web.dart`. كانت تُرجع الطاولة `available` فوراً — وهو العطلُ الأصليّ.

```bash
grep -rn "finalizeTableOrder" lib test
```

المتوقَّع: صفرُ نتائج.

- [ ] **Step 4: تحقّق**

```bash
flutter analyze lib test
flutter test test/unit test/data test/structural test/services --concurrency=4
```

- [ ] **Step 5: أودِع**

```bash
git add lib/presentation/pos/ lib/data/ lib/domain/
git commit -m "fix(tables): الدفعُ يترك الطاولةَ مدفوعةً لا متاحةً — الإغلاقُ فعلٌ لا أثرٌ جانبيّ"
```

---

## Task 13: البوّابةُ وجاهزيّةُ الدمج

- [ ] **Step 1: شغّل البوّابة كاملةً في الخلفية**

```bash
scripts/gate.sh
```

~٣٤ دقيقة. شغّلها في الخلفية — سقفُ أداة الصدفة ١٠ دقائق. ولإيقافها اقتل عمليةَ `gate.sh` نفسَها أوّلاً وإلّا كمّلت للسويّة التالية.

المتوقَّع: `analyze` ٦ info، وصفرُ فشلٍ في `unit` و`widget` و`integration`. قارِن أعدادَ الاختبارات بخطّ الأساس الذي قسته قبل المهمّة ١ — النقصانُ الصامت في العدد عطلٌ كالفشل.

- [ ] **Step 2: اقِس خطَّ الأساس بنفسك لا من مستند**

أرقامُ مستندات التسليم في هذا المستودع تَبطُل. شغّل السويّة على `main` وقارن، ولا تثق برقمٍ مكتوب.

- [ ] **Step 3: ابنِ من الـworktree وتحقّق ببصمة `app.so`**

```bash
./build_picpos.bat
```

**ابنِ من هذا الـworktree لا من الجذر** — السكربتُ نسبيٌّ فيبني `main` من الجذر. و`PicPos.exe` حجمُه ثابتٌ دوماً وحجمُ `app.so` قد يتطابق، فـ`md5sum` وحدَه دليلُ أن البناء التقط التغيير:

```bash
md5sum build/windows/x64/runner/Release/data/app.so
```

- [ ] **Step 4: جهّز الدمج مع الجلسة الأخرى**

```bash
git fetch origin && git log --oneline main..HEAD
```

عند الدمج:
1. إن تعارض `lib/data/database/database.g.dart`: `git checkout --ours -- lib/data/database/database.g.dart`، ثم `dart run build_runner build --delete-conflicting-outputs` **مرّةً واحدة** على المصدر المدموج، وأودِع الناتج. **لا تقرأ الملفَّ ولا تُحرّره.**
2. إن تعارض `schemaVersion`: خذ الأكبر، وأعِد ترقيم كتلة `if (from < 154)` إلى الرقم الحرّ التالي، وحرّكها بعد كتلة الجلسة الأخرى.
3. إن تعارض `permission_codes.dart`: التغييران إضافيّان — احتفظ بالسطرين معاً.
4. بعد الدمج شغّل `scripts/gate.sh` مرّةً أخرى في الخلفية، ثم ابنِ وتحقّق ببصمة `app.so`. البناءُ الناجحُ وحدَه ليس دليلاً على الدمج السليم؛ السويّةُ الخضراء بعده هي الدليل.

- [ ] **Step 5: أودِع نتيجةَ البوّابة**

```bash
git commit --allow-empty -m "chore(gate): الحدُّ على المقيس — سويّة الطاولات"
```

---

## المراجعةُ الذاتيّة

**تغطيةُ المواصفة:** §٣ آلةُ الحالات ← المهامّ ٣ و٩ · §٤ نموذجُ البيانات ← المهمّة ٢ · الصلاحيات ← المهمّة ٨ · السجل ← المهامّ ٣–٦ (كتابة) و١١ (عرض) · §٥ العمليات: الفتح/الإغلاق/الإلغاء/تغيير الحالة ← ٣، النقل/الدمج ← ٤، الخصم/الملاحظات ← ٥، الدفع ← ٦ و١٢، طباعةُ الفاتورة ← ٨ (الصلاحية) و١٠ · §٦ التقسيم ← ١ و٧ و١٠ · §٧ الاختبار ← منسوجٌ في كلّ مهمّة، والبوّابة في ١٣ · §٨ الملفات ← مغطّاة.

**فجوةٌ عولجت:** `requestTableBill` كانت تضع الطاولةَ على `billing` — حالةٌ شطبناها في v154 — فكانت الطباعةُ تُعيد حالةً ميتةً إلى الجدول. صارت **الخطوةَ ٢ في المهمّة ١٠** بنصِّها واختبارِها، لا ملاحظةً في ذيل الخطة لا يراها منفِّذُ المهمّة.

**حدٌّ مُعلَن:** `checkoutController.processPayment` مقترنٌ بالسلّة بنيوياً، فإنشاءُ الفاتورة لا يُنقل إلى الخدمة. المُختبَرُ بلا واجهةٍ هو الحساب (`SplitPlan`) والتسجيل (`recordPayment`) — وهما موضعُ الخطر المحاسبيّ. مكتوبٌ في رأس المهمّة ٧.

**اتّساقُ الأنواع:** `SplitPart.amount` مستعمَلةٌ في ٧ و١٠ كما عُرِّفت في ١ · `TableSessionService.recordPayment` بالتوقيع نفسِه في ٦ و٧ و١٢ · `TableStatus` من ٣ مستعمَلٌ في ٤ و٦ و٩ · `MergeOutcome.droppedDiscount` من ٤ تستهلكه واجهةُ الدمج · `effectiveTotal` عُرِّفت في ٥ وتستهلكها ٦ و٧.

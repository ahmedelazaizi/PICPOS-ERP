# إلغاء الإغلاق الإجباري للوردية — وردية لكل كاشير

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** الوردية تفضل مفتوحة عند تسجيل الخروج وعند تبديل المستخدم، وكل كاشير له ورديته المستقلة، ومين عنده `pos_shift_close` يقدر يشوف الورديات المتروكة ويقفلها.

**Architecture:** نموذج البيانات **بالفعل** وردية-لكل-كاشير — `shifts.userId` عمود موجود و`getCurrentOpenShift(userId)` مفهرسة بيه، والفواتير بتتنسب لوردية بايعها. فمفيش تغيير اسكيما، ومفيش مفهوم «وردية معلّقة» جديد: وردية «أ» بتفضل `status='open'` وخلاص، و«ب» بيفتح ورديته. الشغل الحقيقي تلات حاجات: شيل البوابة الإجبارية، اضمن إن الكاشير الجاي يتسأل يفتح ورديته (دي الفخ)، واعمل شاشة الورديات المتروكة.

**Tech Stack:** Flutter · Riverpod · drift · `flutter_test`

## Global Constraints

- **ده عكس قرار تصميمي موثَّق.** التعليق في [open_shift_gate.dart:34](lib/presentation/pos/logic/open_shift_gate.dart:34) بيقول: وردية متسابة مفتوحة هي وردية معاملاتها ما بتترصّدش، فالبوابة مالهاش تجاوز ولا حتى لمدير النظام. المستخدم راجع ده وطلب الإلغاء صراحة، واختار «وردية لكل كاشير» كقاعدة النسبة. الخطة بتنفّذ قراره وبتعوّض الانضباط المفقود بشاشة الورديات المتروكة (مهمة ٣) بدل المنع.
- **ملفات مشتركة:** `lib/presentation/pos/logic/open_shift_gate.dart` و`lib/presentation/shell/app_shell.dart` و`lib/app_main_screen.dart` مشتركة مع UralCash. التغيير هنا تغيير سلوك مقصود للبراندين (المستخدم طلبه للمنتج، والبوابة مالهاش معنى مختلف في Ural). كوميت منفصل + patch. راجع `[[engine-fixes-backport-to-uralcash]]`.
- **`main.dart:1217`**: `MaterialApp(key: ValueKey('app_auth_$isAuthenticated'))` — أي لحظة `isAuthenticated == false` بتهدم الشجرة كلها. عشان كده `switchUser()` ما بتفضّيش `state` أبداً. أي شغل هنا لازم يحترم ده.
- **`_ensureShiftOpen` بتتخطى مدير النظام عن قصد** (Spec 135 NOTE 2) — المدير بيدخل على وردية الكاشير المفتوحة عشان يرصّدها مش بيفتح وردية باسمه. **مايتغيرش.**
- **ممنوع `build_runner`** وممنوع تعديل `database.g.dart` يدوياً. الخطة ما بتغيّرش الاسكيما. راجع `[[build-runner-hangs-in-this-env]]`.
- الاختبارات بـ `--concurrency=1`.
- عربي مصري في التعليقات، إنجليزي في الكود. كوميت منفصل لكل مهمة.

---

## خلفية: ليه ده أبسط بكتير مما تخيّلنا

السؤال اللي كان مطروح — «مبيعات ب هتقع في وردية أ؟» — إجابته **لأ، ومن الأول**:

- `Shifts` في [audit_tables.dart:23](lib/data/database/tables/audit_tables.dart:23) فيها `userId` و`branchId` و`status`
- `getCurrentOpenShift(userId)` في [treasury_dao.dart:205](lib/data/database/daos/treasury_dao.dart:205) بتفلتر بـ `userId` **و** `status='open'`
- `_enforceShiftForCashier` في [app_main_screen.dart:260](lib/app_main_screen.dart:260) بتسأل كل كاشير يفتح ورديته هو
- `getOpenShiftsForBranch({int? branchId})` في [treasury_dao.dart:218](lib/data/database/daos/treasury_dao.dart:218) **موجودة خلاص** — بترجّع كل الورديات المفتوحة على الفرع مهما كان اللي فتحها، متعملة أصلاً (Spec 135 NOTE 2) عشان المدير يدخل على وردية كاشير سابق ويقفلها

يعني البوابة الإجبارية ما كانتش بتحلّ مشكلة نسبة — النسبة صح من غيرها. كانت **سياسة انضباط**: تضمن إن مفيش وردية بتتساب بلا ترصيد.

### الفخ الحقيقي

`_enforceShiftForCashier` بتتنادى من **مكان واحد بس**: [app_main_screen.dart:140](lib/app_main_screen.dart:140) جوه `initState`.

و`switchUser()` **مقصود** إنها ما تهدّش الشجرة (عشان ديالوج التبديل ما يموتش) — فـ`initState` ما بتتنفّذش تاني، و`_enforceShiftForCashier` **ما بتشتغلش للكاشير الجاي**.

النهارده ده متغطّى بالصدفة: البوابة بتجبر «أ» يقفل، وديالوج الإغلاق بيسجّل الخروج بنفسه، فالشجرة بتتهد، و«ب» بيدخل من الأول فـ`initState` بتشتغل. **نشيل البوابة من غير ما نعالج ده، يبقى «ب» بيبيع بلا وردية مفتوحة خالص** — وساعتها فواتيره ما تتنسبش لأي وردية وتقرير الإغلاق يضيّعها. ده أخطر انحدار في الشغلانة دي والمهمة ٢ مخصصة ليه.

---

## بنية الملفات

| الملف | المسؤولية بعد التغيير |
|---|---|
| `lib/presentation/pos/logic/open_shift_gate.dart` | من بوابة مانعة → إشعار غير مانع (`notifyOpenShift`) |
| `lib/presentation/shell/app_shell.dart:223` | الخروج يكمّل، مع إشعار لو فيه وردية مفتوحة |
| `lib/presentation/pos_picpos/widgets/picpos_switch_user_dialog.dart:31` | التبديل يكمّل بلا إغلاق |
| `lib/app_main_screen.dart` | `_enforceShiftForCashier` تبقى قابلة للنداء عند تبديل المستخدم مش بس عند `initState` |
| `lib/presentation/screens/open_shifts_screen.dart` | **جديد** — الورديات المتروكة، مبوّبة بـ`posShiftClose` |
| `test/widget/open_shift_gate_test.dart` | تتعدّل للسلوك الجديد |
| `test/widget/switch_user_shift_test.dart` | **جديد** — الكاشير الجاي بيتسأل يفتح ورديته |

---

## Task 1: البوابة تبقى إشعاراً مش مانعاً

**Files:**
- Modify: `lib/presentation/pos/logic/open_shift_gate.dart` (كامل)
- Modify: `lib/presentation/shell/app_shell.dart:215-235`
- Modify: `lib/presentation/pos_picpos/widgets/picpos_switch_user_dialog.dart:31`
- Test: `test/widget/open_shift_gate_test.dart` (تعديل الستة اختبارات)

**Interfaces:**
- Produces: `Future<void> notifyOpenShift({required BuildContext context, required WidgetRef ref, required String reason})` — بتعرض إشعاراً غير مانع لو فيه وردية مفتوحة، وبترجّع دايماً. `ShiftGateResult` و`ensureShiftClosed` **بيتشالوا**.
- المستدعيين مابقاش عندهم قرار يتفرّع عليه — بيكمّلوا دايماً.

- [ ] **Step 1: عدّل الاختبارات الموجودة للسلوك الجديد**

الستة اختبارات في `test/widget/open_shift_gate_test.dart` بتثبّت المنع. استبدلهم:

```dart
// test/widget/open_shift_gate_test.dart
//
// الوردية المفتوحة بقت تتبلّغ مش تمنع.
//
// ── ليه اتغير ────────────────────────────────────────────────────────────
// البوابة كانت بتجبر الكاشير يقفل ورديته قبل الخروج أو التبديل، والتعليق
// كان بيقول صراحة إنها مالهاش تجاوز ولا لمدير النظام. المستخدم راجع القرار
// وطلب إن الوردية تفضل مفتوحة ويكمّلها صاحبها لما يرجع.
//
// النسبة مش في خطر: `shifts.userId` موجود من الأول و`getCurrentOpenShift`
// مفلترة بيه، فمبيعات «ب» بتروح لوردية «ب» مهما كانت وردية «أ» مفتوحة.
// الانضباط المفقود اتعوّض بشاشة الورديات المتروكة.

  testWidgets('وردية مفتوحة → الإشعار بيظهر والمستدعي بيكمّل', (tester) async {
    // ... جهّز مستخدم بوردية مفتوحة عبر نفس الـ harness الموجود في الملف
    var proceeded = false;
    await notifyOpenShift(
      context: ctx, ref: ref, reason: 'قبل تسجيل الخروج',
    );
    proceeded = true;
    await tester.pumpAndSettle();

    expect(proceeded, isTrue,
        reason: 'الإشعار ما يمنعش — دي كل نقطة التغيير');
    expect(find.textContaining('وردية مفتوحة'), findsOneWidget);
  });

  testWidgets('مفيش وردية مفتوحة → مفيش إشعار', (tester) async {
    await notifyOpenShift(context: ctx, ref: ref, reason: 'قبل تسجيل الخروج');
    await tester.pumpAndSettle();
    expect(find.textContaining('وردية مفتوحة'), findsNothing);
  });

  testWidgets('مش مسجّل دخول → مفيش إشعار ولا استعلام', (tester) async {
    // نفس harness «not signed in → clear» القديم، بس التوقّع بقى مفيش إشعار.
  });

  testWidgets('فشل الاستعلام ما يوقفش المستدعي', (tester) async {
    // الفشل الآمن اتقلب: قبل كده «مقدرناش نتأكد → امنع». دلوقتي الخروج
    // مايتعطّلش على إشعار.
  });
```

> **للمنفّذ:** الملف الحالي فيه harness جاهز (mock للـ`treasuryRepositoryProvider`). اقراه بالكامل قبل التعديل وأعد استعماله بدل ما تخترع واحد جديد.

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/widget/open_shift_gate_test.dart --concurrency=1
```

Expected: FAIL — `The function 'notifyOpenShift' isn't defined`

- [ ] **Step 3: استبدل محتوى `open_shift_gate.dart`**

```dart
/// إشعار غير مانع بوجود وردية مفتوحة عند مغادرة الجلسة — خروج أو تبديل.
///
/// ── ليه بقى إشعاراً بعد ما كان بوابة ─────────────────────────────────────
/// كان اسمه `ensureShiftClosed` وكان بيجبر الترصيد قبل المغادرة، بلا تجاوز
/// ولا لمدير النظام. المستخدم راجع القرار وطلب إن الوردية تفضل مفتوحة
/// ويكمّلها صاحبها لما يرجع، أو يقفلها اللي عنده `pos_shift_close`.
///
/// ── ليه ده مش بيكسر نسبة المبيعات ────────────────────────────────────────
/// `shifts.userId` عمود موجود من الأول، و`getCurrentOpenShift(userId)`
/// مفلترة بيه وبـ`status='open'`. يعني وردية كل كاشير مستقلة أصلاً: «ب»
/// بيبيع على ورديته هو مهما كانت وردية «أ» لسه مفتوحة. البوابة ما كانتش
/// بتحمي النسبة — كانت بتفرض انضباط الترصيد، وده اتنقل لشاشة الورديات
/// المتروكة (`open_shifts_screen.dart`).
///
/// بترجّع `void` عن قصد: مفيش قرار للمستدعي يتفرّع عليه، فمفيش قيمة ترجع.
/// أي مستدعي جديد بيكمّل غصب عنه — ما ينفعش يتحول لبوابة تاني بالغلط.
Future<void> notifyOpenShift({
  required BuildContext context,
  required WidgetRef ref,
  /// بيوضّح للمستخدم السياق ("قبل تسجيل الخروج" / "قبل تحويل المستخدم").
  required String reason,
}) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return;

  ShiftData? openShift;
  try {
    openShift =
        await ref.read(treasuryRepositoryProvider).getCurrentOpenShift(userId);
  } catch (_) {
    // فشل الاستعلام مايعطّلش الخروج. قبل كده كان الفشل الآمن «امنع»، وده
    // كان صح وقت ما كان منع؛ دلوقتي التعطيل على إشعار هو الضرر الأكبر.
    return;
  }
  if (openShift == null || !context.mounted) return;

  AppToast.show(
    context,
    'ورديتك (#${openShift.id}) لسه مفتوحة $reason — تقدر تكمّلها لما ترجع.',
    type: ToastType.warning,
  );
}
```

- [ ] **Step 4: بدّل المستدعيين**

في [app_shell.dart:223](lib/presentation/shell/app_shell.dart:223) — شيل `final gate = await ensureShiftClosed(...)` و`if (gate != ShiftGateResult.clear) return;` وحطّ:

```dart
    // الوردية بتتبلّغ مش بتتمنع: تفضل مفتوحة والكاشير يكمّلها لما يرجع، أو
    // اللي عنده `pos_shift_close` يقفلها من شاشة الورديات المفتوحة.
    await notifyOpenShift(
      context: context,
      ref: ref,
      reason: 'قبل تسجيل الخروج',
    );
    if (!mounted) return;
```

وفي [picpos_switch_user_dialog.dart:31](lib/presentation/pos_picpos/widgets/picpos_switch_user_dialog.dart:31) — نفس الاستبدال بـ `reason: 'قبل تحويل المستخدم'`. **خلي بالك:** التبديل لازم يكمّل لحد `switchUser` مهما حصل.

- [ ] **Step 5: تأكد إن مفيش استعمال فاضل للبوابة القديمة**

```bash
grep -rn "ensureShiftClosed\|ShiftGateResult" lib test --include=*.dart
```

Expected: صفر نتايج.

- [ ] **Step 6: شغّل الحزمة**

```bash
flutter analyze lib test && flutter test --concurrency=1
```

- [ ] **Step 7: كوميت**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(shift): الوردية تفضل مفتوحة عند الخروج والتبديل بدل الإغلاق الإجباري

البوابة كانت بتجبر الكاشير يرصّد ورديته قبل الخروج أو تبديل المستخدم،
والتعليق كان بيقول صراحة إنها مالهاش تجاوز ولا لمدير النظام. المستخدم
راجع القرار وطلب إن الوردية تفضل مفتوحة ويكمّلها صاحبها لما يرجع.

النسبة مش في خطر ومكانتش أصلاً: `shifts.userId` عمود موجود من الأول
و`getCurrentOpenShift` مفلترة بيه وبـ`status='open'`، فمبيعات «ب» بتروح
لوردية «ب» مهما كانت وردية «أ» مفتوحة. البوابة ما كانتش بتحمي النسبة —
كانت بتفرض انضباط الترصيد، وده بينتقل لشاشة الورديات المتروكة.

`ensureShiftClosed` بقت `notifyOpenShift` وبترجّع void عن قصد: مفيش قرار
للمستدعي يتفرّع عليه، فما ينفعش تتحول لبوابة تاني بالغلط.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: الكاشير الجاي لازم يتسأل يفتح ورديته

⚠️ **دي أخطر مهمة في الخطة.** من غيرها، المهمة ١ بتخلّي الكاشير الجاي يبيع بلا وردية مفتوحة خالص.

**Files:**
- Modify: `lib/app_main_screen.dart:140` و `:260` (تعريض `_enforceShiftForCashier`)
- Modify: `lib/presentation/pos_picpos/widgets/picpos_switch_user_dialog.dart` (النداء بعد `switchUser`)
- Test: `test/widget/switch_user_shift_test.dart` (جديد)

**Interfaces:**
- Consumes: `notifyOpenShift` من Task 1.
- Produces: مزوّد/دالة عليا `Future<void> enforceShiftForUser(BuildContext, WidgetRef)` تستخرج منطق `_enforceShiftForCashier` عشان مسار التبديل يقدر يناديها. `AppMainScreen.initState` بيناديها زي ما هو.

**ليه الاستخراج:** `_enforceShiftForCashier` دالة خاصة جوه `State` وبتتنادى من `initState` بس. و`switchUser()` **مقصود** إنها ما تهدّش الشجرة (عشان ديالوج التبديل ما يموتش مع `MaterialApp` key)، فـ`initState` ما بتشتغلش تاني. النهارده ده متغطّى بالصدفة لأن ديالوج الإغلاق كان بيسجّل الخروج فالشجرة كانت بتتهد.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/widget/switch_user_shift_test.dart
//
// بعد تبديل المستخدم، الكاشير الجاي لازم يتسأل يفتح ورديته.
//
// `switchUser()` مقصود إنها ما تهدّش شجرة الودجت (عشان ديالوج التبديل ما
// يموتش مع مفتاح MaterialApp في main.dart:1217)، فـ`initState` — المكان
// الوحيد اللي كان بينادي `_enforceShiftForCashier` — ما بتتنفّذش تاني.
//
// قبل إلغاء الإغلاق الإجباري ده كان متغطّى بالصدفة: ديالوج الإغلاق كان
// بيسجّل الخروج فالشجرة تتهد و«ب» يدخل من الأول. بعد الإلغاء، «ب» كان
// هيبيع بلا وردية مفتوحة وفواتيره ما تتنسبش لأي وردية.
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('التبديل لكاشير بلا وردية مفتوحة → ديالوج فتح الوردية بيظهر',
      (tester) async {
    // جهّز: «أ» بوردية مفتوحة، «ب» بلا وردية.
    // نفّذ: مسار تبديل المستخدم لـ«ب».
    // توقّع: find.textContaining('فتح وردية') findsOneWidget
  });

  testWidgets('التبديل لكاشير عنده وردية مفتوحة → مفيش ديالوج',
      (tester) async {
    // «ب» راجع لورديته اللي سابها مفتوحة — ما يتسألش تاني.
  });

  testWidgets('وردية «أ» بتفضل مفتوحة بعد التبديل', (tester) async {
    // جوهر «وردية لكل كاشير»: فتح وردية «ب» ما بيقفلش وردية «أ».
  });
}
```

> **للمنفّذ:** استعمل نفس أسلوب الـ harness في `test/widget/open_shift_gate_test.dart`. لو الاختبار الودجت الكامل اتضح إنه أغلى من فايدته، حوّله لاختبار وحدة على `enforceShiftForUser` بـ mock للـ`treasuryRepositoryProvider` — **بس ما تسيبش المهمة بلا اختبار**، دي أخطر نقطة انحدار في الخطة.

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/widget/switch_user_shift_test.dart --concurrency=1
```

- [ ] **Step 3: استخرج المنطق لدالة عليا قابلة للنداء**

في `app_main_screen.dart`، حوّل جسم `_enforceShiftForCashier` لدالة عليا:

```dart
/// بتضمن إن المستخدم الحالي عنده وردية مفتوحة، وبتسأله يفتح واحدة لو لأ.
///
/// ── ليه دالة عليا مش دالة خاصة في `State` ────────────────────────────────
/// كانت بتتنادى من `initState` وبس، وده كان كفاية وقت ما كل دخول مستخدم
/// جديد كان بيمرّ بإعادة بناء الشجرة. بعد إلغاء الإغلاق الإجباري بقى فيه
/// مسار تاني: `switchUser()` بتغيّر المستخدم **من غير** ما تهدّ الشجرة —
/// مقصود، عشان ديالوج التبديل ما يموتش مع مفتاح `MaterialApp`. فـ
/// `initState` ما بتشتغلش، والكاشير الجاي كان هيبيع بلا وردية.
Future<void> enforceShiftForUser(BuildContext context, WidgetRef ref) async {
  // ... نفس جسم `_enforceShiftForCashier` بالحرف، مع استبدال `mounted` بـ
  // `context.mounted` و`ref.read` بدل الوصول لحالة الودجت.
}
```

و`_enforceShiftForCashier` تبقى غلاف: `=> enforceShiftForUser(context, ref)`.

⚠️ **سيب `authState.isAdmin || authState.isManager` في السطر ٢٦٣ زي ما هو في المهمة دي.** ده تخطّي Spec 135 NOTE 2 المتعمَّد (المدير بيرصّد وردية الكاشير مش بيفتح واحدة باسمه). خطة الصلاحيات بتلمس السطر ده — نسّق بينهم: تضييق التخطّي لمدير النظام بس معناه إن «مدير فرع» هيتسأل يفتح وردية، وده تغيير سلوك يستاهل كوميت وقرار لوحده.

- [ ] **Step 4: نادي الدالة بعد `switchUser`**

في `picpos_switch_user_dialog.dart`، بعد `ref.read(authProvider.notifier).switchUser(authenticated);` وبعد قفل الديالوج:

```dart
      if (mounted) Navigator.of(context).pop(true);

      // الكاشير الجاي لازم يتسأل يفتح ورديته. `switchUser` ما بتهدّش الشجرة
      // عن قصد، فـ`initState` — المكان الوحيد اللي كان بينادي ده — ما بتشتغلش.
      // من غير النداء ده هيبيع بلا وردية مفتوحة وفواتيره ما تتنسبش لأي وردية.
      //
      // بعد الـ pop عشان الديالوج ما يكونش لسه فوق ديالوج فتح الوردية.
      if (context.mounted) {
        await enforceShiftForUser(context, ref);
      }
```

- [ ] **Step 5: اتأكد إن `clearShiftDialogPromptedUsers` بتخلّي «ب» يتسأل**

`switchUser()` بتنادي `clearShiftDialogPromptedUsers()`، اللي بتفضّي `shiftDialogPromptedUserIds` كلها — فحارس «اتسأل قبل كده» مش هيخنق سؤال «ب». اتأكد من ده لما تكتب الاختبار التاني (رجوع «ب» لورديته المفتوحة) — دي بتعدّي بسبب `openShift != null` مش بسبب الحارس.

- [ ] **Step 6: شغّل الحزمة**

```bash
flutter analyze lib test && flutter test --concurrency=1
```

- [ ] **Step 7: كوميت**

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix(shift): الكاشير الجاي بعد التبديل كان هيبيع بلا وردية مفتوحة

`_enforceShiftForCashier` كانت بتتنادى من `initState` وبس. و`switchUser()`
مقصود إنها ما تهدّش شجرة الودجت — عشان ديالوج التبديل ما يموتش مع مفتاح
`MaterialApp` في main.dart:1217 — فـ`initState` ما بتشتغلش تاني.

قبل إلغاء الإغلاق الإجباري ده كان متغطّى بالصدفة: ديالوج الإغلاق بيسجّل
الخروج، فالشجرة تتهد و«ب» يدخل من الأول. بعد الإلغاء الغطا ده اتشال.

اتحوّلت لدالة عليا `enforceShiftForUser` بينادوها المسارين. تخطّي المدير
(Spec 135 NOTE 2) ما اتغيرش.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: شاشة الورديات المتروكة

دي اللي بتعوّض الانضباط اللي البوابة كانت بتفرضه.

**Files:**
- Create: `lib/presentation/screens/open_shifts_screen.dart`
- Modify: `lib/data/providers/auth_providers.dart` (`screenPermissionMap` + عنصر قائمة)
- Modify: `lib/core/navigation/screen_ids.dart` (`ScreenId.openShifts`)
- Test: `test/widget/open_shifts_screen_test.dart` (جديد)

**Interfaces:**
- Consumes: `AppDatabase.getOpenShiftsForBranch({int? branchId})` — **موجودة خلاص** في [treasury_dao.dart:218](lib/data/database/daos/treasury_dao.dart:218)، بترجّع `Future<List<Shift>>` لكل الورديات المفتوحة على الفرع مهما كان اللي فتحها، الأحدث الأول. `branchId` بـ`null` بترجّع كل الفروع.
- Produces: `ScreenId.openShifts` مربوطة بـ`PermissionCodes.posShiftClose` في `screenPermissionMap`.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/widget/open_shifts_screen_test.dart
//
// الشاشة اللي بتعوّض الإغلاق الإجباري: مين عنده `pos_shift_close` بيشوف
// الورديات المتروكة مفتوحة ويقفلها. من غيرها، إلغاء البوابة بيسيب
// الورديات المتروكة بلا أي طريقة يتشافوا بيها.
void main() {
  testWidgets('بتعرض كل الوردية المفتوحة باسم صاحبها', (tester) async {
    // جهّز: ورديتين مفتوحتين لمستخدمين مختلفين.
    // توقّع: الاتنين ظاهرين، وكل واحدة عليها اسم صاحبها ووقت فتحها.
  });

  testWidgets('بلا pos_shift_close → زرار الإغلاق مش متاح', (tester) async {
    // الشاشة نفسها مبوّبة بالصلاحية في screenPermissionMap، وزرار الإغلاق
    // مبوّب تاني جوه الشاشة — دفاع في العمق زي باقي المسارات الحساسة.
  });

  testWidgets('مفيش ورديات مفتوحة → حالة فاضية واضحة', (tester) async {});
}
```

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/widget/open_shifts_screen_test.dart --concurrency=1
```

- [ ] **Step 3: اعمل الشاشة**

قايمة من `getOpenShiftsForBranch`، كل سطر فيه: رقم الوردية، اسم صاحبها، وقت الفتح، مدة الفتح، الرصيد الافتتاحي. وزرار «إغلاق الوردية» ملفوف في:

```dart
PermissionGuard(
  permission: PermissionCodes.posShiftClose,
  allowManagerOverride: true,
  actionName: 'إغلاق وردية ${shift.id}',
  // صريحة: الحارس بيمسك الضغطة، ولو ما عرفش يشغّل إيه بعد الموافقة بيفكّ
  // القفل وبس. راجع f8d3fa9.
  onGranted: () => _closeShift(shift),
  child: ElevatedButton.icon(
    onPressed: () => _closeShift(shift),
    icon: const Icon(PhosphorIconsBold.lockKey),
    label: const Text('إغلاق الوردية'),
  ),
)
```

`_closeShift` بتعيد استعمال ديالوج الإغلاق الموجود (`PosCashierClosingDialog` / نظيره في PicPos) — **ما تكتبش منطق إغلاق تاني**، نسخة تانية بتبطّل تطابق أول تعديل.

- [ ] **Step 4: وصّل الشاشة**

ضيف `ScreenId.openShifts`، ومدخل في `screenPermissionMap`:

```dart
  ScreenId.openShifts: PermissionCodes.posShiftClose,
```

وعنصر قائمة تحت مجموعة الخزينة بنفس الصلاحية.

- [ ] **Step 5: شغّل الحزمة**

```bash
flutter analyze lib test && flutter test --concurrency=1
```

- [ ] **Step 6: كوميت**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(shift): شاشة الورديات المفتوحة — تعويض الإغلاق الإجباري

إلغاء البوابة شال الآلية اللي كانت بتضمن إن مفيش وردية تتساب بلا ترصيد.
الشاشة دي بتحطّ المسؤولية على المشرف بدل ما تمنع الكاشير: بتعرض كل وردية
مفتوحة على الفرع باسم صاحبها ووقت فتحها ومدتها، وتقفلها.

مبوّبة بـ`pos_shift_close` مرتين — على مستوى الشاشة في `screenPermissionMap`
وعلى زرار الإغلاق نفسه.

بتستعمل `getOpenShiftsForBranch` الموجودة (Spec 135 NOTE 2) وديالوج الإغلاق
الموجود — مفيش منطق إغلاق تاني يبطّل يطابق.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: نقل الإصلاحات لـ UralCash

- [ ] **Step 1: طلّع الـ patches** — `git format-patch` للكوميتات التلاتة
- [ ] **Step 2:** وثّق في `docs/superpowers/backports/2026-08-01-shift.md` إن `picpos_switch_user_dialog.dart` و`shift_close_picpos/` خاصين بـ PicPos وبيتشالوا من النقل، وإن UralCash محتاج نداء مكافئ لـ`enforceShiftForUser` في أي مسار تبديل عنده
- [ ] **Step 3: كوميت التوثيق**

---

## المراجعة الذاتية

**تغطية الطلب:** «مش عايز إغلاق إجباري عند التبديل ولا عند الخروج» → Task 1 بتشيل الاتنين. «الوردية تفضل مفتوحة ويكمّلها صاحبها» → مضمونة بـ`getCurrentOpenShift(userId)` القائمة + Task 2 اللي بتضمن إن الرجوع ما يفتحش وردية تانية. «أو يقفلها اللي عنده صلاحية الإغلاق» → Task 3 بـ`posShiftClose`. قاعدة النسبة اللي اختارها المستخدم (وردية لكل كاشير) **قائمة في الاسكيما خلاص** — موثّق في قسم الخلفية.

**فراغات:** أجسام الاختبارات في Task 2 و3 موصوفة بالتوقّعات مش مكتوبة بالكامل، لأن الـ harness موجود في `open_shift_gate_test.dart` والنسخ منه بلا قراءته هيطلّع كود مش بيكمپايل. الخطوة الأولى في كل مهمة بتقول اقرا الملف الموجود الأول. الأنماط والتوقّعات محددة.

**اتساق الأنواع:** `notifyOpenShift` (Task 1) `Future<void>` — المستدعيين في نفس المهمة ما بيتفرّعوش على قيمة. `enforceShiftForUser(BuildContext, WidgetRef)` (Task 2) بينادوها `initState` وديالوج التبديل. `getOpenShiftsForBranch({int? branchId}) → Future<List<Shift>>` (Task 3) موجودة ومش بتتغير.

**تعارض مع خطة الصلاحيات:** الخطتين الاتنين بيلمسوا `app_main_screen.dart:263` (`isAdmin || isManager`). الخطة دي بتسيبه؛ خطة الصلاحيات Task 2 بتقول اقرا السياق. **نفّذ خطة الصلاحيات الأول**، وساعتها قرار السطر ده بيتاخد مرة واحدة وموثّق.

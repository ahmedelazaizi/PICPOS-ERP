# إنفاذ الصلاحيات — خطة التنفيذ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** خلّي كل صلاحية معروضة للمدير في شاشة الصلاحيات تسري فعلاً على المستخدم — بإصلاح التجاوزات اللي بتلغيها، وربط الشاشات بأكوادها الصحيحة، وإضافة الإنفاذ الناقص لـ ٨٨ كود.

**Architecture:** ثلاث مراحل مرتّبة بالأثر/التكلفة. المرحلة ١ بتشيل تجاوزين بيلغوا الصلاحيات على مستوى النظام كله (سطرين ونص) — دي بتصلّح أكبر جزء من البلاغ. المرحلة ٢ بتصحّح خريطة `screenPermissionMap` اللي بتربط شاشات بأكواد غلط. المرحلة ٣ بتضيف نقاط الإنفاذ الناقصة للـ ٨٨ كود على دفعات حسب الملف الهدف. كل مرحلة بتقفل باختبار حارس يمنع الرجوع.

**Tech Stack:** Flutter · Riverpod · drift · `PermissionGuard` · `flutter_test`

## Global Constraints

- **المشكلة مشتركة بين البراندين.** اتأكدت: `permission_codes.dart` و`permissions_dao.dart` و`permission_categories.dart` **متطابقة بالحرف** بين `D:\PICPOS-ERP` و`D:\URAL-ERP`، وسويب الأكواد الميتة بيدّي نفس النتيجة (٨٩ في Ural مقابل ٨٨ في PicPos، الفرق `pos_edit_invoice` بس). و`auth_providers.dart` بيختلف **فقط** بدالة `switchUser` المضافة في PicPos — `isAdmin`/`isManager`/`screenPermissionMap` متطابقين. فمفيش نسخة صحيحة نستنسخها؛ الإصلاح بيتعمل هنا في ملفات المحرك المشتركة.
- **ممنوع لمس `D:\URAL-ERP`.** كل كوميت في الخطة دي على ملف أصله UralCash يتعمل منفصل ويتنقل بـ `git format-patch`. راجع `[[engine-fixes-backport-to-uralcash]]`.
- **الودجتات المشتركة تحت `lib/presentation/pos/widgets/`** بين البراندين. أي تعديل هناك يبقى إما إصلاح صحيح للاتنين، أو إضافة ببارامتر له قيمة افتراضية تعيد سلوك اليوم بالحرف. ممنوع `Brand.isPicPos` جوه ودجت مشتركة.
- **ممنوع تشغيل `build_runner`** وممنوع تعديل `database.g.dart` يدوياً. الخطة دي ما بتغيّرش الاسكيما فمش محتاجة توليد. راجع `[[build-runner-hangs-in-this-env]]`.
- **الاختبارات تتشغّل بـ `--concurrency=1`** — التوازي بيرفرف بموت الأيزوليت.
- **إيقاع الاختبار (قرار 2026-08-01):** الحزمة الكاملة بتاخد ~٢٠ دقيقة، فمش بتتشغّل كل مهمة. كل مهمة بتشغّل **اختباراتها المركّزة بس** (ملف الاختبار بتاعها + أي ملف اختبار بيلمس نفس الكود)، والحزمة الكاملة بتتشغّل **مرة واحدة آخر كل مرحلة** كبوابة. `flutter analyze lib test` بيفضل على كل مهمة — رخيص.
  المقايضة المقبولة: لو الحزمة رجعت حمرا آخر مرحلة، المهمة المسؤولة مش هتبقى واضحة فوراً. مخفّفة بإن كل مهمة ليها كوميت منفصل، فـ`git bisect` أو رجوع كوميت واحد بيحدّدها بسرعة.
  بوابات المراحل: آخر Task 2 (مرحلة ١) · آخر Task 3 (مرحلة ٢) · آخر Task 13 (مرحلة ٣، قبل النقل لـ UralCash).
- خط الأساس قبل البدء: `flutter analyze lib test` صفر أخطاء · `flutter test --concurrency=1` ٣٤٠٠ ناجحة / ١٢ متخطّاة / صفر فشل.
- التعليقات بالعربي المصري وبتشرح **ليه** مش **إيه**. الكود والأسماء إنجليزي.
- كوميت منفصل لكل مهمة، رسالته بالعربي بأسلوب `git log --oneline -6`.

---

## خلفية: الأدلة اللي الخطة مبنية عليها

ثلاث آليات مستقلة بتنتج نفس العرض («بغيّر صلاحية ومش بيحصل حاجة»):

**١. تجاوز الدور بالاسم** — `AuthState.isAdmin`/`isManager` في [auth_providers.dart:141](lib/data/providers/auth_providers.dart:141) بيتحددوا بمطابقة **نص اسم الدور**:

```dart
bool get isManager {
  final roleName = effectiveRole?.name.toLowerCase() ?? '';
  return isAdmin || roleName.contains('مدير') || roleName.contains('manager');
}
```

الأدوار المزروعة اللي اسمها فيه «مدير»: **مدير النظام، مدير مالي، مدير فرع، مدير مخزون** — أربعة من تسعة. كلهم `isManager == true`، وفيه **٨ مواضع** بتستعمل `isAdmin || isManager` كتجاوز كامل للصلاحيات (عناصر القائمة، الشاشات المسموحة، لوحة الدفع، إضافة صنف في البيع، ديالوجات الإغلاق، الفواتير السابقة). فالمدير يسحب صلاحية من «مدير فرع» وما يحصلش حاجة.

وده كمان **متناقض مع طبقة قاعدة البيانات**: `_isAdminRole` في [permissions_dao.dart:187](lib/data/database/daos/permissions_dao.dart:187) صارمة — `isSystemRole && name == 'مدير النظام'` وبس. يعني الـ DAO بتعتبر «مدير فرع» دور عادي بصلاحياته الصريحة، وطبقة الواجهة بتعتبره متجاوز لكل حاجة.

**٢. خريطة شاشات بأكواد غلط** — `screenPermissionMap` في [auth_providers.dart:718](lib/data/providers/auth_providers.dart:718) بتربط شاشات بأكواد عامة بدل أكوادها:

| الشاشة | مربوطة بـ | المفروض |
|---|---|---|
| `dashboard` | `pos_access` | `dashboard_access` |
| `offers` | `pos_access` | `offers_view` |
| `tables` | `pos_access` | `tables_view` |
| `kitchen` | `pos_access` | `kitchen_view` |
| `salesReturns` | `sales_view` | `sales_return_view` |
| `purchaseReturns` | `purchases_create` | `purchases_return_view` |
| `manufacturing` | `inventory_view` | `manufacturing_view` |
| `fixedAssets` | `settings_view` | `assets_view` |

وكمان [auth_providers.dart:817](lib/data/providers/auth_providers.dart:817) بيحقن `dashboard` في المسموح قسراً لو مش موجود — فـ`dashboard_access` مستحيل يمنع حاجة.

**٣. ٨٨ كود بلا أي نقطة إنفاذ** — سويب على `lib/` كله (مستبعداً السجل والسيدر والمصفوفة والكتالوج) طلّع ٨٨ من ٢١٩ كود بصفر مراجع. والشاشة اللي PicPos بيفتحها (`showPermissionsManagementDialog` → `PermissionsManagementWidget`) بتعرض الـ٢١٩ كلهم من قاعدة البيانات مباشرة.

الحلقات السليمة اللي اتأكدت منها ومش محتاجة تغيير: الكتابة (`setRolePermissions` ترانزاكشن replace-all)، وإبطال الكاش (`ref.invalidate(currentUserPermissionsProvider)` موجود في كل موضع تعديل).

---

## بنية الملفات

| الملف | المسؤولية بعد التغيير |
|---|---|
| `lib/data/providers/auth_providers.dart` | يضيف `hasSystemAdminBypass` كمصدر وحيد لقرار التجاوز، ويصحّح `screenPermissionMap` |
| `lib/core/permissions/permission_enforcement_registry.dart` | **جديد** — قائمة الأكواد المعروفة إنها غير منفَّذة بعد، بتتقلّص كل دفعة. مصدر بيانات اختبار الحارس |
| `test/unit/permission_enforcement_coverage_test.dart` | **جديد** — الحارس: كل كود في `masterList` إما ليه مرجع إنفاذ أو مذكور صراحة في السجل |
| `test/unit/role_name_bypass_test.dart` | **جديد** — «مدير فرع» مايتجاوزش الصلاحيات |
| `test/unit/screen_permission_map_test.dart` | **جديد** — كل شاشة مربوطة بكودها هي |
| ملفات الشاشات/الودجتات في المرحلة ٣ | تلفّ الأفعال في `PermissionGuard` أو تفحص الكود قبل التنفيذ |

---

## المرحلة ١ — تجاوز الدور بالاسم

### Task 1: قرار التجاوز يتبني على صلاحية `system_admin` مش على اسم الدور

**Files:**
- Modify: `lib/data/providers/auth_providers.dart:141-151` (إضافة `hasSystemAdminBypass`)
- Modify: `lib/data/providers/auth_providers.dart:708-712` و `:812` (مواضع التجاوز)
- Test: `test/unit/role_name_bypass_test.dart` (جديد)

**Interfaces:**
- Produces: `extension AuthStateBypass on AuthState { bool get hasSystemAdminBypass; }` — بترجّع `true` **فقط** لما الدور الفعّال يكون `isSystemRole == true` واسمه `'مدير النظام'` بالظبط. ده بيطابق `_isAdminRole` في `permissions_dao.dart` بالحرف.
- `isAdmin` و`isManager` **بيفضلوا زي ما هم** — فيه ٢٢ و١١ استعمال، كتير منهم تجميلي (عناوين، أيقونات). التغيير مقصور على مواضع الصلاحيات.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/role_name_bypass_test.dart
//
// دور اسمه فيه «مدير» ما يتجاوزش الصلاحيات.
//
// `isManager` بتتحدد بمطابقة نص اسم الدور، وأربعة أدوار مزروعة اسمها فيه
// «مدير» (مدير النظام/مالي/فرع/مخزون). ٨ مواضع كانت بتستعمل
// `isAdmin || isManager` كتجاوز كامل — فسحب صلاحية من «مدير فرع» ما كانش
// بيعمل حاجة. ده اللي البلاغ كان عنه.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/database/database.dart';

AuthState _stateWithRole(String name, {required bool isSystemRole}) {
  final role = Role(
    id: 2,
    name: name,
    description: null,
    isSystemRole: isSystemRole,
    globalId: null,
    createdAt: DateTime(2026, 1, 1),
  );
  final user = User(
    id: 5,
    username: 'u',
    displayName: 'u',
    passwordHash: 'h',
    passwordSalt: 's',
    roleId: 2,
    isActive: true,
    isLocked: false,
    pin: null,
    createdAt: DateTime(2026, 1, 1),
  );
  return AuthState(userWithRole: UserWithRole(user: user, role: role));
}

void main() {
  group('hasSystemAdminBypass', () {
    test('«مدير فرع» لا يتجاوز — ده جوهر البلاغ', () {
      final s = _stateWithRole('مدير فرع', isSystemRole: true);
      expect(s.isManager, isTrue, reason: 'isManager التجميلية زي ما هي');
      expect(s.hasSystemAdminBypass, isFalse,
          reason: 'التجاوز لازم يبقى على مدير النظام وبس');
    });

    test('«مدير مالي» و«مدير مخزون» لا يتجاوزوا', () {
      expect(_stateWithRole('مدير مالي', isSystemRole: true)
          .hasSystemAdminBypass, isFalse);
      expect(_stateWithRole('مدير مخزون', isSystemRole: true)
          .hasSystemAdminBypass, isFalse);
    });

    test('«مدير النظام» يتجاوز', () {
      expect(_stateWithRole('مدير النظام', isSystemRole: true)
          .hasSystemAdminBypass, isTrue);
    });

    test('دور مخصص اسمه «مدير النظام» لكنه مش دور نظام لا يتجاوز', () {
      // من غير الشرط ده، أي مشغّل يقدر يخترع دور بالاسم ده ويتجاوز كل حاجة.
      expect(_stateWithRole('مدير النظام', isSystemRole: false)
          .hasSystemAdminBypass, isFalse);
    });

    test('بلا دور لا يتجاوز', () {
      expect(const AuthState().hasSystemAdminBypass, isFalse);
    });
  });
}
```

- [ ] **Step 2: شغّل الاختبار وتأكد إنه بيفشل**

```bash
flutter test test/unit/role_name_bypass_test.dart --concurrency=1
```

Expected: FAIL — `The getter 'hasSystemAdminBypass' isn't defined for the type 'AuthState'`

- [ ] **Step 3: ضيف الامتداد في `auth_providers.dart` بعد تعريف `AuthState`**

```dart
/// قرار «ده مدير نظام فيتجاوز الصلاحيات؟» — المصدر الوحيد.
///
/// ── ليه مش `isAdmin || isManager` ────────────────────────────────────────
/// الاتنين دول بيتحددوا بمطابقة **نص اسم الدور**: `isManager` بترجّع `true`
/// لأي دور اسمه فيه «مدير». الأدوار المزروعة «مدير مالي» و«مدير فرع»
/// و«مدير مخزون» كلهم كانوا بيتجاوزوا كل صلاحيات الشاشات والقائمة، فسحب
/// صلاحية منهم ما كانش بيسري — وده كان البلاغ.
///
/// وكمان كان بيخالف طبقة قاعدة البيانات: `_isAdminRole` في
/// `permissions_dao.dart` صارمة (`isSystemRole && name == 'مدير النظام'`).
/// الطبقتين لازم يتفقوا على مين المدير، فده بيطابقها بالحرف.
///
/// شرط `isSystemRole` مقصود: من غيره أي مشغّل يخترع دور مخصص بالاسم ده
/// ويتجاوز كل حاجة.
extension AuthStateBypass on AuthState {
  bool get hasSystemAdminBypass {
    final role = effectiveRole;
    return role != null && role.isSystemRole && role.name == 'مدير النظام';
  }
}
```

- [ ] **Step 4: شغّل الاختبار وتأكد إنه نجح**

```bash
flutter test test/unit/role_name_bypass_test.dart --concurrency=1
```

Expected: PASS (٥ اختبارات)

- [ ] **Step 5: بدّل موضعَي التجاوز في مزوّدات القائمة والشاشات**

في `userNavItemsProvider` — [auth_providers.dart:708](lib/data/providers/auth_providers.dart:708):

```dart
    if (item.permission == null ||
        authState.hasSystemAdminBypass ||
        userPermissions.contains(item.permission)) {
      allowedItems.add(item);
    }
```

وفي `userAllowedScreensProvider` — [auth_providers.dart:812](lib/data/providers/auth_providers.dart:812):

```dart
    if (authState.hasSystemAdminBypass ||
        userPermissions.contains(entry.value)) {
      allowedScreens.add(entry.key.navigationIndex);
    }
```

- [ ] **Step 6: شغّل الحزمة كلها**

```bash
flutter analyze lib test && flutter test --concurrency=1
```

Expected: صفر أخطاء تحليل. الاختبارات: أي فشل هنا معناه اختبار قديم كان بيعتمد على تجاوز «مدير فرع» — اقراه وقرّر: لو بيثبّت السلوك الغلط عدّله ووثّق ليه؛ لو بيكشف انحدار حقيقي ارجع للخطوة ٥.

- [ ] **Step 7: كوميت**

```bash
git add lib/data/providers/auth_providers.dart test/unit/role_name_bypass_test.dart
git commit -m "$(cat <<'EOF'
fix(perms): أي دور اسمه فيه «مدير» كان بيتجاوز كل الصلاحيات

المدير يسحب صلاحية من «مدير فرع» والتغيير ما يسريش. السبب إن `isManager`
بتتحدد بمطابقة نص اسم الدور — `roleName.contains('مدير')` — وأربعة أدوار
مزروعة من تسعة اسمها فيه «مدير»: مدير النظام، مدير مالي، مدير فرع، مدير
مخزون. وفيه ٨ مواضع بتستعمل `isAdmin || isManager` كتجاوز كامل.

وكان متناقض مع طبقة قاعدة البيانات: `_isAdminRole` في `permissions_dao`
صارمة (`isSystemRole && name == 'مدير النظام'`). الطبقتين كانوا بيختلفوا
على مين المدير أصلاً.

`hasSystemAdminBypass` بقت المصدر الوحيد وبتطابق الـ DAO بالحرف. المرحلة
دي بتبدّل موضعَي القائمة والشاشات؛ الستة الباقيين في الكوميت اللي بعده.
`isAdmin`/`isManager` سايبينهم زي ما هم للاستعمالات التجميلية.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: باقي مواضع التجاوز الستة

**Files:**
- Modify: `lib/app_main_screen.dart:263` و `:588`
- Modify: `lib/presentation/pos/providers/pos_closing_controller.dart:413`
- Modify: `lib/presentation/pos/screens/pos_main_operations.dart:352`
- Modify: `lib/presentation/pos/widgets/payment_sheet.dart:60`
- Modify: `lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart:96`
- Modify: `lib/presentation/pos/widgets/pos_previous_invoices_dialog.dart:225`
- Modify: `lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart:129`
- Test: `test/unit/payment_permission_test.dart` (جديد)

**Interfaces:**
- Consumes: `AuthStateBypass.hasSystemAdminBypass` من Task 1.

⚠️ **`payment_sheet.dart` و`pos_cashier_closing_dialog.dart` و`pos_previous_invoices_dialog.dart` مشتركة بين البراندين** — التغيير هنا إصلاح صحيح للاتنين (بيسري نفس السلوك على UralCash)، مش سلوك خاص بـ PicPos، فمش محتاج بارامتر.

**عيب تاني في نفس الدالة:** `_hasPermission` في [payment_sheet.dart:58](lib/presentation/pos/widgets/payment_sheet.dart:58) بتنتهي بـ `|| permissions.isEmpty` — يعني **مستخدم بصفر صلاحيات بيعدّي كل فحوص الدفع**. الفشل مفتوح. المدير يسحب كل صلاحيات الدفع من كاشير فيبقى عنده كلها. الاتنين بيتصلّحوا في نفس المهمة لأنهم في نفس السطرين.

- [ ] **Step 1: اكتب الاختبار الفاشل على دالة حقيقية**

`_hasPermission` دالة خاصة جوه `State` فمش قابلة للاختبار. استخرجها لدالة عليا في نفس الملف — نفس اللي اتعمل مع `extractChildAction` في `f8d3fa9` وللسبب ده بالظبط:

```dart
// test/unit/payment_permission_test.dart
//
// فحص صلاحية طريقة الدفع في لوحة الدفع.
//
// ── عيبين كانوا هنا ───────────────────────────────────────────────────────
// ١. `if (auth.isAdmin || auth.isManager) return true;` — والاتنين دول
//    بيتحددوا بمطابقة اسم الدور، فأي دور اسمه فيه «مدير» كان بيعدّي بلا
//    صلاحية دفع. الأدوار المزروعة «مدير فرع» و«مدير مالي» و«مدير مخزون».
// ٢. `|| permissions.isEmpty` — مستخدم بصفر صلاحيات كان بيعدّي كل الفحوص.
//    يعني سحب كل صلاحيات الدفع من كاشير كان بيديله كلها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos/widgets/payment_sheet.dart';

void main() {
  group('hasPaymentPermission', () {
    test('«مدير فرع» بلا صلاحية دفع لا يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const ['pos_access'],
          permCode: 'pos_payment_cash',
        ),
        isFalse,
      );
    });

    test('قائمة صلاحيات فاضية لا تعدّي — الفشل مقفول', () {
      // كان `|| permissions.isEmpty` بيرجّع true هنا.
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const [],
          permCode: 'pos_payment_cash',
        ),
        isFalse,
      );
    });

    test('مدير النظام يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: true,
          permissions: const [],
          permCode: 'pos_payment_cash',
        ),
        isTrue,
      );
    });

    test('كاشير عنده الصلاحية يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const ['pos_payment_cash'],
          permCode: 'pos_payment_cash',
        ),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/unit/payment_permission_test.dart --concurrency=1
```

Expected: FAIL — `The function 'hasPaymentPermission' isn't defined`

- [ ] **Step 3: استخرج الدالة وصلّح العيبين**

في `payment_sheet.dart` كدالة عليا:

```dart
/// هل المستخدم يقدر يستعمل طريقة الدفع دي؟
///
/// ── ليه دالة عليا مكشوفة للاختبار ────────────────────────────────────────
/// كانت دالة خاصة جوه `State` فما كانش ينفع تتغطّى، وعاشت فيها غلطتين
/// لحد ما اتكشفوا ميدانياً. نفس السبب اللي خلّى `extractChildAction` تتكشف
/// في `f8d3fa9`.
///
/// ── الغلطتين ─────────────────────────────────────────────────────────────
/// `auth.isAdmin || auth.isManager` بيتحددوا بمطابقة **اسم الدور**، فأي دور
/// اسمه فيه «مدير» كان بيعدّي — ودول أربعة من تسعة أدوار مزروعة.
///
/// و`|| permissions.isEmpty` كان فشلاً مفتوحاً: سحب كل صلاحيات الدفع من
/// كاشير كان بيديله كلها. القايمة الفاضية معناها «مالوش صلاحية»، مش «متأكدش».
/// حالة «لسه بيحمّل» بتتفرّق بـ`asData == null` عند المستدعي مش هنا.
@visibleForTesting
bool hasPaymentPermission({
  required bool isSystemAdmin,
  required List<String> permissions,
  required String permCode,
}) {
  if (isSystemAdmin) return true;
  return permissions.contains(permCode);
}
```

و`_hasPermission` تبقى:

```dart
  bool _hasPermission(String permCode) {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final data = permsAsync.asData;
    // لسه بيحمّل ومفيش نسخة مخبّية — ما نمنعش على شك، بس ما نفتحش الباب
    // كمان: بنسيب الطريقة الافتراضية بس لحد ما البيانات توصل.
    if (data == null) return permCode == PermissionCodes.posPaymentCash;
    return hasPaymentPermission(
      isSystemAdmin: ref.read(authProvider).hasSystemAdminBypass,
      permissions: data.value,
      permCode: permCode,
    );
  }
```

- [ ] **Step 4: شغّل الاختبار وتأكد إنه نجح**

```bash
flutter test test/unit/payment_permission_test.dart --concurrency=1
```

Expected: PASS (٤ اختبارات)

- [ ] **Step 5: بدّل الخمسة مواضع الباقية**

في كل موضع، `authState.isAdmin || authState.isManager` تبقى `authState.hasSystemAdminBypass`. مثال — [payment_sheet.dart:60](lib/presentation/pos/widgets/payment_sheet.dart:60):

```dart
    // مدير النظام بس هو اللي بيتجاوز. قبل كده كانت `isAdmin || isManager`،
    // وهي بتمطبق اسم الدور — فـ«مدير فرع» كان بيعدّي بلا صلاحية دفع.
    if (auth.hasSystemAdminBypass) return true;
```

`app_main_screen.dart:263` (تخطّي المدراء) و`:588` — اقرا السياق الأول: لو الاستعمال تجميلي (إخفاء تلميح، تخطّي جولة تعريفية) سيبه `isManager` ووثّق ليه في تعليق سطر واحد. التبديل للمواضع اللي **بتقرر صلاحية** بس.

- [ ] **Step 6: تأكد إن مفيش تجاوز صلاحية فاضل**

```bash
grep -rn "isAdmin || .*isManager\|isManager || .*isAdmin" lib --include=*.dart
```

Expected: كل نتيجة فاضلة لازم يبقى فوقها تعليق بيقول ليه دي تجميلية مش قرار صلاحية.

- [ ] **Step 7: شغّل الحزمة**

```bash
flutter analyze lib test && flutter test --concurrency=1
```

- [ ] **Step 8: كوميت**

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix(perms): باقي مواضع تجاوز «مدير» + فشل مفتوح في لوحة الدفع

استكمال للكوميت اللي قبله: لوحة الدفع، إضافة صنف في البيع، ديالوجات
الإغلاق (نقطة البيع و PicPos)، الفواتير السابقة، متحكّم الإقفال — كلهم
كانوا بيعدّوا أي دور اسمه فيه «مدير» بلا فحص صلاحية.

وفي لوحة الدفع غلطة تانية أخطر: `_hasPermission` كانت بتنتهي بـ
`|| permissions.isEmpty` — يعني مستخدم بصفر صلاحيات بيعدّي كل فحوص الدفع.
سحب كل صلاحيات الدفع من كاشير كان بيديله كلها. القايمة الفاضية معناها
«مالوش صلاحية» مش «متأكدش»؛ حالة التحميل بتتفرّق بـ`asData == null`.

الدالة اتحوّلت لـ`hasPaymentPermission` عليا ومكشوفة للاختبار — كانت خاصة
جوه `State` فعاشت فيها الغلطتين لحد ما اتكشفوا ميدانياً. نفس السبب اللي
خلّى `extractChildAction` تتكشف في f8d3fa9.

`app_main_screen` اتساب على `isManager` في المواضع التجميلية بتعليق يوضّح
إنها مش قرار صلاحية.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2b: كلمة سر غلق البرنامج بيتخطاها أي دور نظام

مهمة اتولدت من مراجعة Task 2. باج **قديم** مش انحدار — المراجع تأكد إن التعبير القديم كان تلات فروع و Task 2 لمس الأولين بس.

**Files:**
- Modify: `lib/app_main_screen.dart` (حوالي سطر ٥٨٨)
- Test: `test/unit/close_app_gate_test.dart` (جديد)

**Interfaces:**
- Consumes: `AuthStateBypass.hasSystemAdminBypass` من Task 1.
- Produces: `@visibleForTesting bool canCloseAppWithoutPassword(AuthState auth)` كدالة عليا في `app_main_screen.dart`.

**المشكلة:** الشرط الحالي

```dart
    final isAdminOrManager =
        authState.hasSystemAdminBypass ||
        (authState.role?.isSystemRole ?? false);
```

الفرع التاني بيسمح لأي **دور نظام مزروع** يتخطى كلمة السر. و`isSystemRole` **مش إشارة أقدمية**: الأدوار المزروعة بـ`isSystemRole: true` هي مدير النظام و**كاشير** ومخزني ومحاسب ومدير مالي. يعني الكاشير العادي بيقفل البرنامج من غير كلمة سر مدير. البوابة دي موجودة عشان تمنع بالظبط ده.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/close_app_gate_test.dart
//
// مين يقدر يقفل البرنامج من غير كلمة سر مدير؟
//
// ── الباج ─────────────────────────────────────────────────────────────────
// الشرط كان بيسيب فرع `(role?.isSystemRole ?? false)` — و`isSystemRole` مش
// إشارة أقدمية. الأدوار المزروعة كنظام: مدير النظام، **كاشير**، مخزني،
// محاسب، مدير مالي. فالكاشير كان بيقفل البرنامج بلا كلمة سر، وهي بالظبط
// الحالة اللي البوابة موجودة عشانها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/app_main_screen.dart';

void main() {
  group('canCloseAppWithoutPassword', () {
    test('كاشير — دور نظام لكنه مش مدير — لا يعدّي', () {
      expect(canCloseAppWithoutPassword(
          authStateForRole('كاشير', isSystemRole: true)), isFalse);
    });

    test('مخزني ومحاسب ومدير مالي لا يعدّوا', () {
      for (final name in ['مخزني', 'محاسب', 'مدير مالي']) {
        expect(
          canCloseAppWithoutPassword(
              authStateForRole(name, isSystemRole: true)),
          isFalse,
          reason: '$name دور نظام بس مش مدير النظام',
        );
      }
    });

    test('مدير النظام يعدّي', () {
      expect(canCloseAppWithoutPassword(
          authStateForRole('مدير النظام', isSystemRole: true)), isTrue);
    });

    test('بلا دور لا يعدّي', () {
      expect(canCloseAppWithoutPassword(const AuthState()), isFalse);
    });
  });
}
```

> **للمنفّذ:** `authStateForRole` مش موجودة — أعد استعمال نفس مُساعِد بناء `AuthState` اللي في `test/unit/role_name_bypass_test.dart` (اتكتب في Task 1 وبيتعامل مع مُنشئات drift المولَّدة). انسخه أو اطلّعه لمُساعِد مشترك، وما تخترعش واحد جديد.

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/unit/close_app_gate_test.dart --concurrency=1
```

Expected: FAIL — `The function 'canCloseAppWithoutPassword' isn't defined`

- [ ] **Step 3: استخرج الشرط وشيل الفرع الغلط**

```dart
/// هل المستخدم يقفل البرنامج من غير ما يتطلب كلمة سر المدير؟
///
/// ── ليه الفرع الأصلي كان غلط ──────────────────────────────────────────────
/// كان فيه `|| (role?.isSystemRole ?? false)`، و`isSystemRole` بيوصف إن الدور
/// **مزروع وغير قابل للحذف**، مش إنه دور عالي الصلاحية. الأدوار المزروعة
/// كنظام هي مدير النظام و**كاشير** ومخزني ومحاسب ومدير مالي — فالكاشير كان
/// بيتخطى البوابة اللي موجودة عشانه هو تحديداً.
///
/// البوابة دي سؤالها «يتطلب كلمة سر مدير؟»، فالمدير وحده هو اللي يعفى منها.
@visibleForTesting
bool canCloseAppWithoutPassword(AuthState auth) => auth.hasSystemAdminBypass;
```

ومكان الاستدعاء يبقى `final isAdminOrManager = canCloseAppWithoutPassword(authState);` — سيب اسم المتغير المحلي لو مستعمل تحت، أو غيّره لـ`canSkipPassword` لو ده بيوضّح أكتر.

⚠️ **أثر مقصود:** «محاسب» و«مدير مالي» هيتطلبوا كلمة سر دلوقتي وما كانوش بيتطلبوها. ده الغرض من البوابة، مش أثر جانبي.

- [ ] **Step 4: شغّل الاختبار + analyze**

```bash
flutter test test/unit/close_app_gate_test.dart --concurrency=1 && flutter analyze lib test
```

Expected: ٤ اختبارات PASS، صفر أخطاء تحليل.

- [ ] **Step 5: كوميت**

```bash
git add lib/app_main_screen.dart test/unit/close_app_gate_test.dart
git commit -m "$(cat <<'EOF'
fix(perms): الكاشير كان بيقفل البرنامج من غير كلمة سر مدير

بوابة غلق البرنامج كانت بتعفي أي دور بـ`isSystemRole == true`، و`isSystemRole`
بيوصف إن الدور مزروع وغير قابل للحذف — مش إنه عالي الصلاحية. الأدوار
المزروعة كنظام هي مدير النظام و**كاشير** ومخزني ومحاسب ومدير مالي، فالكاشير
كان بيتخطى البوابة اللي موجودة عشانه هو بالذات.

الباج قديم ومش انحدار من كوميت تجاوز «مدير»: التعبير كان تلات فروع وده
كان تالتهم. كشفته مراجعة الكوميت اللي قبله.

أثر مقصود: «محاسب» و«مدير مالي» بقوا يتطلبوا كلمة السر.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## المرحلة ٢ — خريطة الشاشات

### Task 3: كل شاشة تتربط بكودها هي

**Files:**
- Modify: `lib/data/providers/auth_providers.dart:718-766` (`screenPermissionMap`)
- Modify: `lib/data/providers/auth_providers.dart:817-819` (حقن `dashboard` القسري)
- Modify: `lib/data/providers/auth_providers.dart:574` و `:583` (عناصر القائمة)
- Modify: `lib/core/permissions/permission_codes.dart` (تسجيل `salesOrdersView` و`purchaseOrdersView`)
- Test: `test/unit/screen_permission_map_test.dart` (جديد)

**Interfaces:**
- Produces: `PermissionCodes.salesOrdersView = 'sales_orders_view'` و`PermissionCodes.purchaseOrdersView = 'purchase_orders_view'` + مدخلاتهم في `masterList` تحت الفئتين `sales` و`purchases`.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/screen_permission_map_test.dart
//
// كل شاشة لازم تتربط بكود صلاحيتها هي.
//
// الخريطة كانت بتربط شاشات بأكواد عامة: العروض والطاولات والمطبخ ولوحة
// التحكم كلهم على `pos_access`، ومردودات البيع على `sales_view`. فالمدير
// يسحب `offers_view` وشاشة العروض تفضل ظاهرة لأنها مش مربوطة بيه أصلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/core/navigation/screen_ids.dart';

void main() {
  test('كل كود في الخريطة مسجّل في masterList', () {
    final master = PermissionCodes.masterList.map((m) => m['code']!).toSet();
    for (final entry in screenPermissionMap.entries) {
      expect(master.contains(entry.value), isTrue,
          reason: '${entry.key} مربوطة بكود غير مسجّل: ${entry.value}');
    }
  });

  test('الشاشات اللي ليها كود خاص متربطة بيه مش بكود عام', () {
    const expected = <ScreenId, String>{
      ScreenId.dashboard: 'dashboard_access',
      ScreenId.offers: 'offers_view',
      ScreenId.tables: 'tables_view',
      ScreenId.kitchen: 'kitchen_view',
      ScreenId.salesReturns: 'sales_return_view',
      ScreenId.purchaseReturns: 'purchases_return_view',
      ScreenId.manufacturing: 'manufacturing_view',
      ScreenId.fixedAssets: 'assets_view',
      ScreenId.loyalty: 'loyalty_view',
      ScreenId.distribution: 'distribution_view',
    };
    expected.forEach((screen, code) {
      expect(screenPermissionMap[screen], code,
          reason: '$screen لازم تتحكم بـ $code');
    });
  });
}
```

> **ملحوظة للمنفّذ:** اتأكد من مسار `screen_ids.dart` الفعلي قبل الاستيراد — `grep -rn "enum ScreenId" lib`.

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/unit/screen_permission_map_test.dart --concurrency=1
```

Expected: FAIL — `ScreenId.dashboard لازم تتحكم بـ dashboard_access` (وباقي المدخلات)

- [ ] **Step 3: صحّح الخريطة**

بدّل المدخلات العشرة في `screenPermissionMap` للأكواد الصحيحة، وضيف تعليق فوق الخريطة:

```dart
/// ربط الشاشة ← كود الصلاحية اللي بيتحكم في ظهورها.
///
/// ── القاعدة ──────────────────────────────────────────────────────────────
/// الشاشة اللي ليها كود خاص في `PermissionCodes` تتربط بيه، مش بكود عام.
/// كانت العروض والطاولات والمطبخ ولوحة التحكم كلهم على `pos_access`،
/// ومردودات البيع على `sales_view` — فسحب `offers_view` ما كانش بيخفي شاشة
/// العروض، لأن الكود ده ما كانش متوصّل بحاجة أصلاً.
///
/// الشاشات المحاسبية اللي لسه على `settings_view` مقصودة: مالهاش أكواد
/// خاصة في `masterList` لحد دلوقتي.
const screenPermissionMap = <ScreenId, String>{
```

- [ ] **Step 4: شيل حقن `dashboard` القسري**

[auth_providers.dart:817](lib/data/providers/auth_providers.dart:817) بيحط لوحة التحكم في المسموح حتى لو الصلاحية مسحوبة، فـ`dashboard_access` مستحيل يمنع حاجة. بدّله بضمانة «مايبقاش من غير أي شاشة»:

```dart
  // مايبقاش المستخدم من غير أي شاشة يفتحها — بيقع في واجهة فاضية بلا مخرج.
  // قبل كده كانت لوحة التحكم بتتحقن قسراً وده كان بيلغي `dashboard_access`
  // تماماً؛ دلوقتي بتتحقن فقط لما مايبقاش فيه بديل خالص.
  if (allowedScreens.isEmpty &&
      flavorAllowedScreenIds.contains(ScreenId.dashboard)) {
    allowedScreens.add(ScreenId.dashboard.navigationIndex);
  }
```

- [ ] **Step 5: سجّل الكودين الناقصين**

`sales_orders_view` و`purchase_orders_view` بيتفحصوا في القائمة والخريطة لكن مش موجودين في `PermissionCodes` ولا `masterList` — موجودين في السيدر بس. فعلى قاعدة اتعمرت بـ`syncAllPermissions` وحدها، الشاشتين مخفيين لأي حد غير مدير النظام للأبد.

ضيف في `permission_codes.dart` جنب أخواتهم:

```dart
  /// عرض طلبات البيع
  static const String salesOrdersView = 'sales_orders_view';

  /// عرض أوامر الشراء
  static const String purchaseOrdersView = 'purchase_orders_view';
```

وفي `masterList`:

```dart
    {'code': salesOrdersView, 'name': 'عرض طلبات البيع', 'category': 'sales'},
    {
      'code': purchaseOrdersView,
      'name': 'عرض أوامر الشراء',
      'category': 'purchases',
    },
```

- [ ] **Step 6: شغّل الاختبار والحزمة**

```bash
flutter test test/unit/screen_permission_map_test.dart --concurrency=1 && flutter analyze lib test && flutter test --concurrency=1
```

Expected: الاختبار الجديد PASS. لو اختبار قديم فشل بسبب عدد `masterList` (كان ٢١٩ وبقى ٢٢١) عدّل الرقم المتوقع فيه.

- [ ] **Step 7: كوميت**

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix(perms): شاشات مربوطة بأكواد عامة بدل أكوادها

العروض والطاولات والمطبخ ولوحة التحكم كانوا كلهم على `pos_access`،
ومردودات البيع على `sales_view`، ومردودات الشراء على `purchases_create`،
والتصنيع على `inventory_view`، والأصول على `settings_view`. فالمدير يسحب
`offers_view` وشاشة العروض تفضل ظاهرة — الكود ما كانش موصّل بحاجة.

وكمان لوحة التحكم كانت بتتحقن في المسموح قسراً لو مش موجودة، فـ
`dashboard_access` كان مستحيل يمنع حاجة. الحقن بقى بس لما مايبقاش فيه أي
شاشة تانية، عشان المستخدم مايقعش في واجهة فاضية.

و`sales_orders_view` و`purchase_orders_view` كانوا بيتفحصوا في القائمة
والخريطة لكن مش مسجّلين في `PermissionCodes.masterList` — موجودين في
السيدر بس. يعني على قاعدة اتعمرت بـ`syncAllPermissions` وحدها الشاشتين
مخفيين للأبد لأي حد غير مدير النظام.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3c: `dashboard_access` لازم يتمنح للأدوار اللي بتشوف الرئيسية النهارده

مهمة اتولدت من تحفّظ رفعه منفّذ Task 3 واتأكد بالفحص.

**المشكلة:** بعد ما بقت «الرئيسية» متبوّبة بـ`dashboard_access` (في الخريطة وفي عنصر القائمة)، الكود ده مش ممنوح غير لدورين من تسعة:

| المصدر | مين بياخد `dashboard_access` |
|---|---|
| `RoleGrantMatrix.defaultGrants` | محاسب · مدير مالي |
| السيدر (`database_seeder_permissions.dart:767`) | محاسب · مدير مالي |

يعني **كاشير، مخزني، كاشير متقدم، مدير فرع، محاسب متقدم، مدير مخزون** هيفقدوا شاشة الرئيسية. ده أثر جانبي مش هدف: لوحة التحكم كانت بتتحقن قسراً للكل، فمحدش قصد يسحبها من ٦ أدوار. هدف الخطة إن المدير **يقدر** يسحبها ويسري — مش إنها تتسحب من نفسها عند الترقية.

**Files:**
- Modify: `lib/core/permissions/role_grant_matrix.dart` (الأدوار الستة)
- Modify: `lib/data/database/database_seeder_permissions.dart` (منح `dashboard_access` لنفس الأدوار)
- Test: `test/unit/dashboard_access_default_grant_test.dart` (جديد)

**التركيبات الموجودة المستهلَكة:** `RoleGrantMatrix.defaultGrants` — `Map<String, Set<String>>`. و`RoleGrantPreflightService.grantMissingDefaults()` موجودة وبتمنح أكواد المصفوفة الناقصة — **فالتركيبات القديمة بتتعالج من غير مايجريشن**: المشغّل يضغط زرار «منح الصلاحيات الناقصة» في ديالوج فحص الصلاحيات. اذكر ده في رسالة الكوميت.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/dashboard_access_default_grant_test.dart
//
// كل دور تشغيلي لازم ياخد `dashboard_access` افتراضياً.
//
// ── ليه ───────────────────────────────────────────────────────────────────
// قبل ما الشاشة تتبوّب بالكود ده، لوحة التحكم كانت بتتحقن في المسموح قسراً
// فالكل بيشوفها. لما بقت متبوّبة فعلاً، الأدوار اللي مالهاش الكود فقدت
// الشاشة — وده أثر جانبي مش قرار. الهدف إن المدير يقدر يسحبها، مش إنها
// تتسحب لوحدها عند الترقية.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/role_grant_matrix.dart';

void main() {
  test('كل دور في المصفوفة عنده dashboard_access', () {
    final missing = <String>[];
    RoleGrantMatrix.defaultGrants.forEach((role, codes) {
      if (!codes.contains('dashboard_access')) missing.add(role);
    });
    expect(missing, isEmpty,
        reason: 'الأدوار دي هتفقد شاشة الرئيسية عند الترقية: $missing');
  });
}
```

- [ ] **Step 2: شغّل وتأكد من الفشل**

```bash
flutter test test/unit/dashboard_access_default_grant_test.dart --concurrency=1
```

Expected: FAIL — القايمة فيها كاشير، مخزني، كاشير متقدم، مدير فرع، محاسب متقدم، مدير مخزون (ومدير النظام لو مش موجود عنده).

- [ ] **Step 3: ضيف الكود للأدوار الناقصة في المصفوفة وفي السيدر**

في `role_grant_matrix.dart` ضيف `'dashboard_access',` لكل دور ناقصه، وفوق أول واحد حط:

```dart
      // الرئيسية بقت متبوّبة بـ`dashboard_access` بدل `pos_access`. الكود ده
      // بيتمنح لكل دور تشغيلي عشان الترقية ما تسحبش الشاشة من حد — السحب
      // قرار المدير، مش أثر جانبي للإصلاح.
      'dashboard_access',
```

وفي السيدر، ضيف نفس المنحة لنفس الأدوار بنفس النمط الموجود.

- [ ] **Step 4: شغّل الاختبار + analyze**

```bash
flutter test test/unit/dashboard_access_default_grant_test.dart --concurrency=1 && flutter analyze lib test
```

- [ ] **Step 5: كوميت**

```bash
git add lib/core/permissions/role_grant_matrix.dart lib/data/database/database_seeder_permissions.dart test/unit/dashboard_access_default_grant_test.dart
git commit -m "$(cat <<'EOF'
fix(perms): منح dashboard_access للأدوار اللي بتشوف الرئيسية النهارده

بعد ما «الرئيسية» بقت متبوّبة بـ`dashboard_access` فعلاً، الكود ده كان
ممنوح لدورين بس من تسعة (محاسب ومدير مالي). يعني كاشير ومخزني وكاشير متقدم
ومدير فرع ومحاسب متقدم ومدير مخزون كانوا هيفقدوا الشاشة عند الترقية.

ده أثر جانبي مش هدف: لوحة التحكم كانت بتتحقن قسراً للكل، فمحدش قصد يسحبها
من حد. هدف الإصلاح إن المدير **يقدر** يسحبها ويسري.

التركيبات القديمة بتتعالج من غير مايجريشن: `grantMissingDefaults()` موجودة
وبتمنح أكواد المصفوفة الناقصة — المشغّل يضغط «منح الصلاحيات الناقصة» في
ديالوج فحص الصلاحيات.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3d: تعميم اختبارات الاتفاق — قفل عائلة الاختلاف

مهمة اتولدت من ملاحظات مراجعتَي Task 3 و 3c. الفكرة الحاكمة: **الاختلاف الصامت بين مصدرين بيوصفوا نفس الحقيقة** هو نمط الباج المتكرر في المنظومة دي كلها — الخريطة ضد القائمة، والمصفوفة ضد السيدر. الاختبارات الحالية بتغطي عيّنات، فبتسيب الباقي يعدّي.

**Files:**
- Modify: `test/unit/screen_permission_map_test.dart` (تعميم اختبار الاتفاق + تصحيح تعليق)
- Modify: `test/unit/dashboard_access_default_grant_test.dart` → يترقّى لاختبار اتفاق عام
- Modify: `lib/data/providers/auth_providers.dart` (مدخل «التحليلات» في القائمة)

**Interfaces:** `kAllNavItemDefs` (`List<NavItemDef>` عليا، من Task 3) · `screenPermissionMap` · `RoleGrantMatrix.defaultGrants`.

**البند ١ — اختلاف «التحليلات».** `screenPermissionMap[ScreenId.analytics] == 'analytics_view'` بس مدخل القائمة لسه `permission: 'reports_view'`. يعني اللي عنده `reports_view` بيشوف المدخل وما يقدرش يفتح الشاشة. اختلاف قديم من نفس عائلة اللي اتصلح في Task 3.

**البند ٢ — تعميم اختبار الاتفاق.** الاختبار الحالي بيغطي الشمانية اللي اتغيروا. عمّمه على **كل** مدخل قائمة له `ScreenId` مقابل:

```dart
  test('كل مدخل قائمة متفق مع خريطة الشاشات', () {
    // ── ليه التعميم ──────────────────────────────────────────────────────
    // النسخة الأولى غطّت الشاشات اللي اتصلّحت بس، فسابت اختلاف «التحليلات»
    // يعدّي — ودي نفس العائلة بالظبط. الاختبار اللي بيغطي عيّنة بيثبّت
    // العيّنة، مش القاعدة.
    //
    // أي مدخل مالوش `ScreenId` مقابل بيتستثنى صراحة بسببه تحت — الاستثناء
    // المكتوب أحسن من اختبار بيعدّي على الفاضي.
    final mismatches = <String>[];
    for (final item in kAllNavItemDefs) {
      final screen = _screenForNavItem(item);
      if (screen == null) continue; // مستثنى بسبب مكتوب في _screenForNavItem
      final mapped = screenPermissionMap[screen];
      if (mapped == null) continue;
      if (item.permission != mapped) {
        mismatches.add('${item.label}: القائمة=${item.permission} '
            'الخريطة=$mapped');
      }
    }
    expect(mismatches, isEmpty,
        reason: 'مدخل بيظهر لناس ما يقدروش يفتحوا شاشته (أو العكس):\n'
            '${mismatches.join('\n')}');
  });
```

`_screenForNavItem` تتكتب في الاختبار: بتربط `item.index` أو `item.label` بـ`ScreenId`، وبترجّع `null` للمداخل اللي مالهاش شاشة مقابلة **مع تعليق بيقول ليه** لكل استثناء.

**البند ٣ — اتفاق المصفوفة والسيدر.** مراجعة Task 3c رفعت إن `dashboard_access_default_grant_test` بيفحص المصفوفة بس، فلو السيدر سقّط الكود الاختبار هيفضل أخضر. التغطية الحقيقية موجودة بالصدفة في `role_grant_preflight_service_test` (بيزرع قاعدة ويقارن). اعمل الاعتماد ده صريح: وسّع الاختبار ليقارن **كل** كود في `RoleGrantMatrix.defaultGrants` بما بيمنحه السيدر فعلاً لنفس الدور، مش `dashboard_access` وحده.

> **للمنفّذ:** لو مقارنة السيدر محتاجة زرع قاعدة بيانات، **ما تكررش** منطق `role_grant_preflight_service_test` — استعمل نفس الـ harness بتاعه أو وسّعه. نسخة تانية من منطق الزرع هي بالظبط نوع الازدواج اللي بيبطّل يطابق.

**البند ٤ — تصحيح تعليق.** التعليق في `screen_permission_map_test.dart` بيقول «الشاشات العشرة» وهو بيغطي تمانية. صحّحه (أو هيتحل تلقائياً بالبند ٢).

- [ ] **Step 1: اكتب الاختبار المعمّم وشوفه بيفشل على «التحليلات»**

```bash
flutter test test/unit/screen_permission_map_test.dart --concurrency=1
```

Expected: FAIL — `التحليلات: القائمة=reports_view الخريطة=analytics_view`

- [ ] **Step 2: صلّح مدخل «التحليلات»**

خلّي `permission: PermissionCodes.analyticsView` في `kAllNavItemDefs`.

⚠️ `analytics_view` ممنوح لمين؟ افحص `RoleGrantMatrix.defaultGrants` والسيدر **قبل** ما تغيّر. لو الأدوار اللي بتشوف التحليلات النهارده مالهاش الكود، امنحه ليها في نفس الكوميت — نفس منطق Task 3c بالظبط: الهدف إن المدير يقدر يسحبها، مش إنها تتسحب لوحدها.

- [ ] **Step 3: وسّع اختبار المصفوفة/السيدر (البند ٣)**

- [ ] **Step 4: شغّل المركّزة + analyze**

```bash
flutter test test/unit/screen_permission_map_test.dart test/unit/dashboard_access_default_grant_test.dart test/unit/role_grant_preflight_service_test.dart --concurrency=1 && flutter analyze lib test
```

- [ ] **Step 5: كوميت**

```bash
git add lib/data/providers/auth_providers.dart test/unit/screen_permission_map_test.dart test/unit/dashboard_access_default_grant_test.dart
git commit -m "$(cat <<'EOF'
test(perms): تعميم اختبارات الاتفاق + إصلاح اختلاف «التحليلات»

الاختلاف الصامت بين مصدرين بيوصفوا نفس الحقيقة هو نمط الباج المتكرر في
المنظومة دي: الخريطة ضد القائمة، والمصفوفة ضد السيدر. الاختبارات كانت
بتغطي عيّنات، فالعيّنة بتتثبّت والقاعدة لأ.

«التحليلات» كانت المثال الحي: الخريطة على `analytics_view` والقائمة على
`reports_view`، فاللي عنده `reports_view` بيشوف المدخل وما يقدرش يفتح
الشاشة. الاختبار المعمّم مسكها؛ النسخة اللي بتغطي الشاشات المتغيّرة بس
عدّت عليها.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## المرحلة ٣ — الـ ٨٨ كود بلا إنفاذ

### Task 4: سجل التغطية + اختبار الحارس

ده **الأساس** للدفعات اللي بعده: بيسجّل الـ٨٨ صراحة، وبيمنع أي كود جديد يتولد ميت، وكل دفعة جاية بتشيل أسطر من السجل فالتقدّم بيبقى مقاس.

**Files:**
- Create: `lib/core/permissions/permission_enforcement_registry.dart`
- Create: `test/unit/permission_enforcement_coverage_test.dart`

**Interfaces:**
- Produces: `PermissionEnforcementRegistry.knownUnenforced` — `Set<String>` فيه الـ٨٨ كود. الدفعات الجاية بتشيل منه.

- [ ] **Step 1: اعمل السجل**

```dart
// lib/core/permissions/permission_enforcement_registry.dart
//
// الأكواد اللي معروفة إنها لسه بلا نقطة إنفاذ في التطبيق.
//
// ── ليه الملف ده موجود ────────────────────────────────────────────────────
// سويب على `lib/` كله (2026-08-01) طلّع ٨٨ كود من ٢١٩ بصفر مراجع خارج
// السجل والسيدر والمصفوفة والكتالوج. وشاشة الصلاحيات بتعرض الـ٢١٩ كلهم من
// قاعدة البيانات مباشرة — فالمدير بيقلّب ٤٠٪ من المفاتيح على الفاضي. ده كان
// بلاغ «بغيّر صلاحية ومش بيحصل حاجة».
//
// نفس الـ٨٨ موجودين في UralCash بالحرف (٨٩ هناك، الزيادة `pos_edit_invoice`)
// — مشكلة محرك مشتركة، مش انحراف في براند.
//
// القايمة دي **بتتقلّص وما تكبرش**. `permission_enforcement_coverage_test`
// بيفشل لو كود جديد اتضاف لـ`masterList` من غير إنفاذ ومن غير ما يتكتب هنا
// بسبب صريح.
class PermissionEnforcementRegistry {
  PermissionEnforcementRegistry._();

  static const Set<String> knownUnenforced = {
    // ── نقطة البيع (دفعة ٥) ──
    'pos_work_order', 'pos_expense_description', 'pos_daily_closing',
    'pos_cancel_invoice', 'pos_payment_methods', 'pos_split_payment',
    'pos_customer_add', 'pos_view_cost', 'pos_view_profit', 'pos_note_add',
    'pos_weight_dialog', 'pos_grid_toggle', 'pos_notifications',
    'pos_low_stock_alert',
    // ── لوحة التحكم (دفعة ٦) ──
    'dashboard_access', 'dashboard_sales_today', 'dashboard_sales_total',
    'dashboard_customers', 'dashboard_chart', 'dashboard_top_products',
    'dashboard_alerts', 'dashboard_pending_orders',
    // ── الأصناف والتصنيفات (دفعة ٧) ──
    'products_image', 'products_expiry', 'products_lock',
    'products_price_view', 'products_cost_view', 'products_stock_view',
    'products_scale_upload', 'categories_view', 'categories_scale_upload',
    // ── المستندات: طباعة/تعديل/حذف (دفعة ٨) ──
    'suppliers_view', 'purchases_print', 'purchases_return_view',
    'purchases_return_delete', 'purchases_return_print', 'sales_print',
    'sales_amounts_view', 'sales_return_view', 'sales_return_edit',
    'sales_return_delete', 'sales_return_print',
    // ── العروض والتوصيل والطاولات والمطبخ (دفعة ٩) ──
    'offers_view', 'offers_create', 'offers_edit', 'offers_delete',
    'delivery_view', 'tables_view', 'tables_manage', 'tables_print_bill',
    'kitchen_view', 'kitchen_manage', 'treasury_transactions_view',
    // ── التقارير (دفعة ١٠) ──
    'reports_export', 'reports_purchases', 'reports_inventory',
    'reports_customers', 'reports_suppliers', 'reports_profit',
    'reports_products', 'reports_shifts', 'reports_delivery_recon',
    // ── الإعدادات والنظام (دفعة ١١) ──
    'settings_company', 'settings_receipt', 'settings_restore',
    'settings_tax', 'settings_currency', 'settings_pos_edit',
    'system_audit_log', 'system_database', 'system_license',
    'system_updates',
    // ── وحدات فرعية (دفعة ١٢) ──
    'loyalty_manage', 'distribution_manage', 'einvoice_submit',
    'einvoice_cancel', 'manufacturing_view', 'manufacturing_manage',
    'assets_view', 'assets_manage', 'assets_depreciation',
    'modifiers_manage',
    // ── حرجة ماليّاً — أولوية أمنية (دفعة ١٣) ──
    'audit_shift_blind', 'audit_invoice_unlock',
    'parties_credit_limit_bypass', 'delete_posted_journal',
    'delete_fiscal_year', 'modify_closed_period',
  };
}
```

- [ ] **Step 2: اكتب اختبار الحارس**

```dart
// test/unit/permission_enforcement_coverage_test.dart
//
// كل كود صلاحية إما ليه نقطة إنفاذ في `lib/`، أو مذكور صراحة في
// `PermissionEnforcementRegistry.knownUnenforced`.
//
// من غير الحارس ده، كود جديد يتضاف لـ`masterList` ويظهر للمدير في شاشة
// الصلاحيات وهو مالوش مستقبل — وما حدش يكتشف غير من الميدان.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/core/permissions/permission_enforcement_registry.dart';

/// الملفات اللي بتعرّف الصلاحية مش اللي بتفحصها — وجود الكود فيها مش إنفاذ.
const _definitionFiles = [
  'lib/core/permissions/permission_codes.dart',
  'lib/core/permissions/role_grant_matrix.dart',
  'lib/core/permissions/permission_enforcement_registry.dart',
  'lib/presentation/screens/role_management/data/permission_categories.dart',
];

bool _isDefinitionFile(String path) {
  final p = path.replaceAll(r'\', '/');
  return _definitionFiles.any(p.endsWith) ||
      p.contains('lib/data/database/database_seeder');
}

/// خريطة «كود الصلاحية ← اسم الثابت» المستخرجة من `permission_codes.dart`.
///
/// ── ليه دي لازمة ─────────────────────────────────────────────────────────
/// نقاط الإنفاذ بتستدعي الصلاحية بشكلين: النص الخام `'pos_save'`، أو الثابت
/// `PermissionCodes.posSave`. والشكل التاني هو الغالب — حتى مدخلات
/// `masterList` نفسها مكتوبة بالثوابت. فالبحث عن النص الخام وحده بيقول عن
/// ٨٥ كود منفَّذ فعلاً إنهم ميتين، وده بيخلي الحارس بلا قيمة.
Map<String, String> _constantNameByCode() {
  final src =
      File('lib/core/permissions/permission_codes.dart').readAsStringSync();
  final re = RegExp(r"static const String (\w+) = '([a-z0-9_]+)';");
  return {for (final m in re.allMatches(src)) m.group(2)!: m.group(1)!};
}

bool _isEnforced(String sources, String code, String? constName) {
  if (sources.contains("'$code'") || sources.contains('"$code"')) return true;
  if (constName == null) return false;
  return RegExp('PermissionCodes\\.$constName\\b').hasMatch(sources);
}

void main() {
  test('مفيش كود صلاحية بلا إنفاذ ومش مسجّل', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_isDefinitionFile(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final constByCode = _constantNameByCode();
    final unenforced = <String>[];
    for (final entry in PermissionCodes.masterList) {
      final code = entry['code']!;
      if (!_isEnforced(sources, code, constByCode[code])) {
        unenforced.add(code);
      }
    }

    final unregistered = unenforced
        .where((c) => !PermissionEnforcementRegistry.knownUnenforced.contains(c))
        .toList()
      ..sort();

    expect(unregistered, isEmpty,
        reason: 'أكواد بلا إنفاذ ومش مسجّلة — إما نفّذها أو سجّلها بسبب:\n'
            '${unregistered.join('\n')}');
  });

  test('السجل ما فيهوش كود بقى منفَّذ (يتقلّص ما يكبرش)', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_isDefinitionFile(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final constByCode = _constantNameByCode();
    final staleEntries = PermissionEnforcementRegistry.knownUnenforced
        .where((c) => _isEnforced(sources, c, constByCode[c]))
        .toList()
      ..sort();

    expect(staleEntries, isEmpty,
        reason: 'الأكواد دي بقت منفَّذة — شيلها من knownUnenforced:\n'
            '${staleEntries.join('\n')}');
  });
}
```

- [ ] **Step 3: شغّل الاختبار**

```bash
flutter test test/unit/permission_enforcement_coverage_test.dart --concurrency=1
```

Expected: PASS. لو الاختبار التاني فشل، معناه كود في السجل بقى منفَّذ فعلاً بعد المرحلة ٢ (`offers_view`, `tables_view`, `kitchen_view`, `dashboard_access`, `sales_return_view`, `purchases_return_view`, `manufacturing_view`, `assets_view` — دول اتوصلوا في Task 3) — **شيلهم من السجل** ودي أول قطعة تقدّم مقاسة.

- [ ] **Step 4: كوميت**

```bash
git add lib/core/permissions/permission_enforcement_registry.dart test/unit/permission_enforcement_coverage_test.dart
git commit -m "$(cat <<'EOF'
test(perms): حارس يمنع توليد أكواد صلاحيات ميتة

سويب على lib/ طلّع ٨٨ كود من ٢١٩ بصفر مراجع خارج ملفات التعريف. وشاشة
الصلاحيات بتعرض الـ٢١٩ كلهم، فالمدير بيقلّب ٤٠٪ من المفاتيح على الفاضي.

`PermissionEnforcementRegistry.knownUnenforced` بيسجّلهم صراحة مقسّمين على
الدفعات، والاختبار بيفشل في اتجاهين: كود جديد بلا إنفاذ ومش مسجّل، وكود
مسجّل بقى منفَّذ (فالقايمة تتقلّص ما تكبرش).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Tasks 5-13: دفعات الإنفاذ

كل دفعة **نفس الشكل**، فالمنفّذ بيتعلم النمط مرة واحدة:

1. اكتب اختبار ودجت/وحدة بيثبّت إن الفعل ممنوع بلا الصلاحية ومسموح بيها
2. شغّله وتأكد إنه بيفشل
3. لفّ الفعل في `PermissionGuard` **مع تمرير `onGranted` صراحة** — التخمين من نوع الودجت هو اللي كان وراء الباج في `f8d3fa9`
4. شيل أكواد الدفعة من `knownUnenforced`
5. `flutter analyze lib test && flutter test --concurrency=1`
6. كوميت

**النمط المرجعي** — الفعل اللي له زرار أو مدخل قائمة:

```dart
PermissionGuard(
  permission: PermissionCodes.salesPrint,
  allowManagerOverride: true,
  actionName: 'طباعة فاتورة المبيعات',
  // صريحة عن قصد: الحارس بيلفّ الابن في AbsorbPointer وبيمسك الضغطة، ولو
  // ما عرفش يشغّل إيه بعد الموافقة بيفكّ القفل وبس. راجع f8d3fa9.
  onGranted: () => _printInvoice(invoice),
  child: IconButton(
    icon: const Icon(PhosphorIconsBold.printer),
    tooltip: 'طباعة',
    onPressed: () => _printInvoice(invoice),
  ),
)
```

**النمط المرجعي** — إخفاء بيانات (عرض تكلفة/ربح)، من غير تجاوز:

```dart
PermissionGuard(
  permission: PermissionCodes.posViewCost,
  fallback: const Text('—'),
  child: Text(formatCurrency(item.cost)),
)
```

**النمط المرجعي** — فحص قبل تنفيذ في منطق مش ودجت:

```dart
final perms = ref.read(currentUserPermissionsProvider).asData?.value ?? const [];
if (!perms.contains(PermissionCodes.deletePostedJournal)) {
  AppToast.show(context, 'ليس لديك صلاحية حذف قيد مرحّل', type: ToastType.error);
  return;
}
```

| # | الدفعة | الأكواد | الملفات الهدف |
|---|---|---|---|
| 5 | نقطة البيع | ١٤ | `pos_expense_dialog.dart` · `payment_sheet.dart` · `pos_previous_invoices_dialog.dart` · `pos_customer_selection_dialog.dart` · `cart_item_tile.dart` · `pos_scale_input.dart` · `product_grid.dart` · `pos_notification_handler.dart` · `picpos_payment_panel.dart` · `picpos_items_table.dart` |
| 6 | لوحة التحكم | ٨ | `lib/presentation/screens/dashboard_screen.dart` (بطاقة لكل كود) |
| 7 | الأصناف والتصنيفات | ٩ | `lib/presentation/screens/products/` · `products_screen.dart` · `categories_screen.dart` · `scale_plu_export_screen.dart` |
| 8 | المستندات | ١١ | `sales_invoices_screen.dart` · `sales_returns_screen.dart` · `purchase_invoices_screen.dart` · `purchase_returns_screen.dart` · `suppliers_screen.dart` |
| 9 | العروض/التوصيل/الطاولات/المطبخ/الخزينة | ١١ | `offers_screen.dart` · `delivery_management_screen.dart` · `tables_screen.dart` · `treasury_screen.dart` · `lib/presentation/screens/kitchen*` |
| 10 | التقارير | ٩ | `lib/presentation/screens/reports/*_report_screen.dart` (١:١ تقريباً) + زرار التصدير المشترك لـ`reports_export` |
| 11 | الإعدادات والنظام | ١٠ | `company_info_widget.dart` · `receipt_settings_widget.dart` · `backup_restore_widget.dart` · `pos_settings_widget.dart` · `database_settings_widget.dart` · `activity_log_screen.dart` · `activation_dialog.dart` |
| 12 | وحدات فرعية | ١٠ | `loyalty_screen.dart` · `distribution_screen.dart` · `e_invoice_dashboard_screen.dart` · `manufacturing_screen.dart` · `fixed_assets_screen.dart` · `modifier_management_widget.dart` |
| 13 | **حرجة ماليّاً** | ٦ | `journal_entries_screen.dart` · `fiscal_year_screen.dart` · `shift_close_screen.dart` · `parties_screen.dart` · `sales_invoices_screen.dart` |

⚠️ **دفعة ١٣ أولوية أمنية.** `delete_posted_journal` و`delete_fiscal_year` و`modify_closed_period` و`audit_invoice_unlock` و`parties_credit_limit_bypass` معرّفين في `PermissionCodes.criticalFinancialOps` كأكواد **فصل مهام** — يعني حتى مدير النظام المفروض ما يعملهاش من غير منح صريح. الآلية دي مبنية في `permission_guard.dart` و`permissions_dao.dart` وشغّالة، بس **مفيش ولا نقطة بتستدعيها**. لو الوقت ضاق، الدفعة دي تتقدّم على ٥-١٢.

⚠️ **دفعة ٥ و٩ فيهم ملفات مشتركة** (`lib/presentation/pos/widgets/`). أي تعديل هناك يبقى إصلاح صحيح للبراندين، أو بارامتر بقيمة افتراضية تعيد سلوك اليوم.

---

### Task 14: نقل الإصلاحات لـ UralCash

**Files:** patches بس — **ممنوع لمس `D:\URAL-ERP`**

- [ ] **Step 1: طلّع الـ patches**

```bash
git format-patch main..HEAD --output-directory /tmp/perm-patches
```

- [ ] **Step 2: اكتب ملخص النقل**

اعمل `docs/superpowers/backports/2026-08-01-permissions.md` فيه: قايمة الكوميتات، وأي ملف فيها مش موجود في UralCash (مسارات `pos_picpos/` و`settings_picpos/` و`shift_close_picpos/` خاصة بـ PicPos وبتتشال من النقل)، وأمر التطبيق:

```bash
git am --3way /tmp/perm-patches/*.patch
```

- [ ] **Step 3: كوميت التوثيق**

```bash
git add docs/superpowers/backports/2026-08-01-permissions.md
git commit -m "docs(backport): ملخص نقل إصلاحات الصلاحيات لـ UralCash"
```

---

## المراجعة الذاتية

**تغطية البلاغ:** «صلاحيات بلغي تفعيلها أو بفعّلها ومش بيتم الأمر» — الآليات الثلاثة اللي بتنتج العرض ده مغطّاة: تجاوز الدور بالاسم (Task 1-2)، خريطة أكواد غلط (Task 3)، غياب الإنفاذ (Task 4-13). الحلقات السليمة (الكتابة، إبطال الكاش) اتأكدت ومش في الخطة عن قصد.

**فراغات:** الدفعات ٥-١٣ فيها الأكواد والملفات الهدف والأنماط المرجعية بكود حقيقي، لكن **مش فيها كود نهائي لكل موضع من الـ٨٨** — الموضع الدقيق جوه كل ملف بيتحدد وقت التنفيذ. ده مقصود ومُصرَّح بيه: تحديد ٨٨ موضع سطراً بسطر مقدماً هيبقى تخمين أكتر منه تخطيط. كل دفعة قايمة بذاتها ومقاسة بانكماش `knownUnenforced`.

**اتساق الأنواع:** `hasSystemAdminBypass` (Task 1) بتستُهلك في Task 2 بنفس الاسم. `PermissionEnforcementRegistry.knownUnenforced` (Task 4) بتتقلّص في ٥-١٣ بنفس الاسم. `salesOrdersView`/`purchaseOrdersView` (Task 3) بيتسجّلوا قبل ما اختبار Task 4 يفحص `masterList`.

**خطر معروف:** Task 1 و2 بيسحبوا تجاوزاً كان قائم من زمان. متوقع إن اختبارات موجودة تفشل — دي إشارة مطلوبة مش عطل، وكل واحد يتقرأ ويتقرر: بيثبّت السلوك الغلط ولا بيكشف انحدار.

# تقرير تنفيذ المرحلة 0 — PicPos (2026-11-01)

نُفّذت تغييرات التسميات والعرض والعملة ومعالجة نتيجة رفض الإقفال فقط. لم يُغيّر أي حساب مالي أو عتبة فرق أو قيد، ولم يُحذف منطق أعمال. الاستثناء الوصفي في 0.2 هو تبديل مسار الواجهة عند إرجاع المتحكّم `false`: تبقى النافذة مفتوحة ولا يقع تسجيل الخروج أو إعلان النجاح.

## التغييرات، مواضعها وسببها

| الملف والسطر | قبل ← بعد | السبب | هل يمس منطقاً؟ | التراجع الآمن |
|---|---|---|---|---|
| `lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart:579`، والنسخة القديمة `lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart:498` | `إجمالى الخصم` ← `إجمالي المدفوعات من الصندوق` | الصف يجمع مدفوعات/صرف الصندوق لا «خصماً». | لا؛ بقيت قيم `totalOutflow*` كما هي. | أعد نص التسمية وحده إلى قيمته السابقة بعد قراءة الملف؛ لا تمس بنية الصف. |
| ملفا حوار الإغلاق أعلاه (`picpos...:685–695`، `pos...:604–614`) | بطاقة `إجمالى فواتير: salesCount + returnsCount` ← `فواتير بيع: salesCount · مرتجعات: returnsCount`، مع إزالة شارة المرتجع المكررة | بيان نوعي المبيعات والمرتجعات كما هما؛ لم تُعدّل طريقة العدّ ولا حقول التجميع. | لا؛ العرض يستخدم العدّادين الموجودين (`salesCount` و`returnsCount`) فقط. | أعد شارة «إجمالى فواتير» القديمة وأعد شارة المرتجعات المنفصلة، دون تعديل التجميعات. |
| ملفا حوار الإغلاق (`picpos...:783–856, 938`؛ `pos...:686–741, 824`) | حُجبت قيم الفرق في صفوف النقد/البنك/كليك وملخص الفرق حتى يكون نص حقل النقدي الفعلي غير فارغ؛ `نقص/زيادة` ← `عجز/فائض` | الفراغ يظل صفراً في الحالة والحساب، لكنه لا يُعرض كقيمة جرد أدخلها المستخدم. | لا؛ شرط العرض فقط، ولا تغيير لما يُحسب أو يُخزّن عند الإقفال. | احذف شرط `cashActualEntered` من العرض وأعد نصوص labels السابقة وحدها. |
| `lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart:1109–1123` | عنوان سبب الفرق عند فراغ النقدي الفعلي يصبح `فرق يتجاوز الحد المسموح` بدلاً من كشف «عجز/فائض» قبل الجرد. | توحيد حجب ألفاظ الفرق قبل إدخال النقدي الفعلي، مع بقاء طلب السبب نفسه كما هو. | لا؛ العتبة والفرق وطلب السبب لم تتغير. | أعد عنوان الشرط السابق فقط وأزل `titleOverride` من توقيع الدالة والاستدعاء. |
| `lib/presentation/reports_picpos/screens/reports_picpos_cards.dart:283,290` | `مبيعات اليوم` ← `صافي مبيعات اليوم (بعد المرتجعات)`؛ `المرتجعات` ← `المرتجعات (للعلم فقط — مطروحة بالفعل)` | توضيح أن صافي المبيعات يتضمن طرح المرتجعات وأن البطاقة المجاورة معلوماتية فقط. | لا؛ بقيت `k.revenue.today` و`k.salesReturns.today` كما هما. | أعد مفتاحي `tr()` السابقين فقط. |
| `lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart:58` | `كل الصناديق` ← `إجمالي الصناديق والبنوك` | الكود يستخدم `dashboardCashBalanceProvider` الذي يجمع رصيد كل خزائن `scopedSafesProvider`، لا النقد وحده؛ يشمل البنك والإلكتروني/كليك. | لا؛ لم يتغير المزوّد أو الجمع. | أعد مفتاح العرض السابق. |
| `lib/data/providers/providers.dart:418–423`؛ `lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart:133`؛ `lib/presentation/pos/widgets/pos_opening_balance_dialog.dart:114` | إضافة `systemCurrencySettingProvider` لقراءة `system_currency` المحفوظ؛ suffix الثابت `JOD` ← الرمز المحمّل، أو فراغ أثناء التحميل/غياب الإعداد. | منع الافتراض المرئي `JOD` قبل توفر إعداد النظام، مع تحديث الواجهتين من مزوّد العملة. | لا؛ قراءة إعداد عرض فقط، بلا تغيير قيم/حسابات. | أعد suffix الثابت واحذف المزوّد الجديد وأعد الواجهتين من `ConsumerStatefulWidget` إلى `StatefulWidget`، مع إبقاء تعديلات المظهر السابقة. |
| `lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart:1256–1266` | حفظ نتيجة `handleClosing`; عند `false` يظهر سبب عربي، ثم يعود قبل التحذير/إغلاق الحوار/الخروج/Toast النجاح. | إصلاح AUD-F01: رفض الإقفال بسبب تجاوز حد المتحكّم لا يُعلن نجاحاً كاذباً ولا يسجّل خروجاً. | لا في الحساب/القبول؛ **تغيّر مسار الواجهة عند الرفض فقط**. لم تُغيّر العتبة أو منطق القبول/الرفض. | أعد استدعاء `handleClosing` كما كان واحذف فرع `!closed` وحده؛ لا تعدّل المتحكّم أو المستودع. |
| `assets/i18n/en.json:825–827, 3308, 6302, 6983–6984, 7756, 8508` | إضافة الترجمات الجديدة للتسميات/سبب الرفض/عناوين الحالة. | تغطية كل مفاتيح `tr()` الجديدة؛ أُبقيت ترجمة `فواتير بيع` الموجودة مسبقاً ولم أكرر المفتاح. | لا. | احذف مفاتيح المرحلة 0 المضافة فقط؛ اترك المفاتيح السابقة و`فواتير بيع` الموجودة. |
| `test/phase0/shift_close_rejection_test.dart:12–81` | اختبار widget لنتيجتي المتحكّم `false/true`. | يثبت بقاء الحوار والإشعار دون خروج عند الرفض، ويثبت الإغلاق/النجاح/الخروج عند القبول. | اختبار فقط. | احذف ملف الاختبار الجديد فقط. |

وُجدت عبارة `إجمالي الخصم` في `lib/presentation/invoice_form_picpos/picpos_invoice_layout.dart:234` داخل قالب الفاتورة، لكنها تعني خصم الفاتورة الفعلي لا صرف الصندوق؛ لذلك تُركت كما هي. لم يُعدّل مولّد/قالب طباعة الوردية: `lib/services/templated_invoice_service/template_values.dart:132–134` ما زال يعرض `عجز/زيادة` في حالة الإغلاق المطبوعة؛ عولجت تسميات شاشة الإقفال فقط، وبقيت فجوات تقرير الطباعة AUD-F13 خارج نطاق 0.1. في ملخص الإغلاق بقي العدّاد كما هو في المصدر، لكن عُرضت مكوّناته المنفصلة التي كانت متاحة أصلاً. للحفاظ على سقف `file_size_baseline` ضُغطت تعليقات تفسيرية داخل دالة سبب الفرق ومسار `diffmax` فقط؛ بقي الكود التنفيذي كما هو.

## إثبات AUD-F01 والاختبارات

- إثبات ما قبل الإصلاح: شُغّل اختبار الـwidget نفسه مؤقتاً بعد جعل شرط الرفض مستحيلاً (`if (closed && !closed)`) لمحاكاة المسار السابق؛ فشل كما ينبغي لأن حوار الرفض أُغلق بدلاً من بقائه مفتوحاً. أُعيد الشرط فوراً بتحرير موضعي.
- بعد الإصلاح: الأمر نفسه نجح: `+2: All tests passed!`. يضبط السيناريو الرافض رصيداً افتتاحياً متوقعاً 100 والنقدي الفعلي الافتراضي 0 (فرق 100)، والسيناريو المقبول فرقاً صفرياً. الاختبار يتحقق من بقاء الحوار، رسالة الرفض، غياب الخروج؛ وفي القبول من إزالة الحوار وإشعار النجاح والخروج.
- `flutter analyze lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart lib/presentation/pos/widgets/pos_opening_balance_dialog.dart lib/presentation/reports_picpos/screens/reports_picpos_cards.dart lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart lib/data/providers/providers.dart test/phase0/shift_close_rejection_test.dart`: `No issues found!`.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural/i18n_coverage_test.dart`: نجح standalone أولاً؛ وبعد إزالة المفتاح المكرر اجتاز الاختبار نفسه داخل `test/structural` النهائي.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural/file_size_ratchet_test.dart`: `+1: All tests passed!` بعد ضغط تعليقات موضعية في ملف حوار PicPos؛ حجمه الحالي 60148 بايت مقابل سقف مسجل 60665، ولم يُرفع baseline.
- اختبارات الوردية/الإقفال/الرصيد الافتتاحي شُغّلت بالأمر:
  `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/scenarios/sc_h_shift_test.dart test/integration/pir_shift_closing_variance_test.dart test/integration/shift_close_balance_test.dart test/integration/shift_close_branch_safes_test.dart test/integration/shift_close_central_safe_test.dart test/integration/shift_close_no_negbal_test.dart test/integration/shift_closing_aggregates_test.dart test/integration/shift_closing_test.dart test/unit/shift_close_global_id_test.dart test/unit/shift_close_permission_category_test.dart test/unit/shift_close_totals_include_click_test.dart test/unit/shift_closing_aggregates_shift_end_test.dart test/unit/shift_closing_dedup_test.dart test/unit/shift_closing_template_channel_backfill_test.dart test/unit/opening_balance_bond_capital_test.dart test/unit/shift_open_gate_test.dart test/widget/picpos_shift_close_test.dart test/widget/switch_user_shift_test.dart` — `+89: All tests passed!` (exit 0). ظهرت رسائل اختبارية عن `path_provider`/`ServicesBinding` في محاولات النسخ الاحتياطي/السجل، بلا فشل للاختبارات.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural` نجح بعد ضغط التعليقات: `+724: All tests passed!` (exit 0). شمل `dark_mode_guard_test` و`brand_artifact_guard_test` و`file_size_ratchet_test` وكلها اجتازت؛ التشغيل الأول أخفق في حارس الحجم فقط قبل الإصلاح. ظهرت في مخرجات بدء بعض الاختبارات تحذيرات binding/محاولات مؤجلة بعد إغلاق قاعدة الاختبار، دون فشل.
- المحاولة الأولى لجمع phase0 وi18n اصطدمت بـ`PathExistsException` على `build/native_assets/windows/sqlite3.dll` أثناء اختبار Dart من جلسة أخرى؛ لم أوقف عمليته. بعد انتهائه فحصت المجلد، وكان الملف المطابق الوحيد `sqlite3.dll`، لكن محاولة حذفه تحديداً رُفضت بـ`Access denied`، فلم أستخدم بديلاً. بعد التحقق من انتهاء العملية المنافسة أُعيد تشغيل `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/phase0/shift_close_rejection_test.dart test/structural/i18n_coverage_test.dart` ونجح `+3: All tests passed!`. وبعد تعديل توقيع عنوان السبب شُغّل الأمر النهائي `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/phase0/shift_close_rejection_test.dart test/structural/i18n_coverage_test.dart test/structural/file_size_ratchet_test.dart` ونجح `+4: All tests passed!`. كتب Flutter سجل التعطل `flutter_02.log` وتركته دون حذف.
- لم يُشغّل `flutter analyze` للمستودع كله ولا كامل مجموعة `test/`؛ شُغّلت المجموعات المذكورة أعلاه. لم تُشغّل واجهة PicPos ولم تُلمس PostgreSQL/الحاويات المحظورة.

## مقتطفات `git diff -U2` الخاصة بهذه المرحلة

المقتطفات أدناه تخص أسطر المرحلة 0 وحدها. الملفات تحمل تغييرات سابقة غير مرتبطة من جلسات/جولات سابقة (ومنها تنسيق الوضع الداكن)، لذلك لم أقتبس hunks تلك التغييرات ولم أزلها. `@@` في المقتطفات علامة اختصار لسياق/نطاق محذوف وليست سطراً حرفياً؛ الإضافات والحذوفات المعروضة مقتبسة من فرق `-U2`.

```diff
--- a/lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart
+++ b/lib/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart
@@
-                _dataRow(tr('إجمالى الخصم'),
+                _dataRow(tr('إجمالي المدفوعات من الصندوق'),
@@
-                    tr('إجمالى فواتير'),
-                    '${a.salesCount + a.returnsCount}',
+                    tr('فواتير بيع'),
+                    '${a.salesCount} · ${tr('مرتجعات')}: ${a.returnsCount}',
@@
-            if (revealed) _buildTotalVarianceStatus(state.totalVariance),
+            if (revealed && cashActualEntered)
+              _buildTotalVarianceStatus(state.totalVariance),
@@
-                : (totalVar < 0 ? tr('نقص: {p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}) : tr('زيادة: +{p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
+                : (totalVar < 0 ? tr('عجز: {p0} {p1}', {'p0': totalVar.abs().toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}) : tr('فائض: +{p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
@@
-      await ref.read(posClosingControllerProvider.notifier).handleClosing(
+      final closed = await ref.read(posClosingControllerProvider.notifier).handleClosing(
@@
+      if (!closed) {
+        if (mounted) {
+          showPosToast(
+            context,
+            ref,
+            tr('رُفض إغلاق الوردية لأن فرق النقد يتجاوز الحد المسموح. عدّل النقدي الفعلي ثم أعد المحاولة.'),
+            type: PosNotificationType.error,
+          );
+        }
+        return;
+      }
```

```diff
--- a/lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart
+++ b/lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart
@@
-                _dataRow(tr('إجمالى الخصم'),
+                _dataRow(tr('إجمالي المدفوعات من الصندوق'),
@@
-                    tr('إجمالى فواتير'),
-                    '${a.salesCount + a.returnsCount}',
+                    tr('فواتير بيع'),
+                    '${a.salesCount} · ${tr('مرتجعات')}: ${a.returnsCount}',
@@
-            if (state.isRevealed) _buildTotalVarianceStatus(state.totalVariance),
+            if (state.isRevealed && cashActualEntered)
+              _buildTotalVarianceStatus(state.totalVariance),
@@ -725,9 +724,9 @@
-            _buildReconciliationRow(tr('النقدى الفعلى'), _actualCashController, state.cashVariance, PhosphorIconsBold.money, AppColors.primary, state.isRevealed),
+            _buildReconciliationRow(tr('النقدى الفعلى'), _actualCashController, state.cashVariance, PhosphorIconsBold.money, AppColors.primary, state.isRevealed && cashActualEntered),
@@
-            _buildReconciliationRow(tr('البنك الفعلى'), _actualCardController, state.bankVariance, PhosphorIconsBold.creditCard, AppColors.info, state.isRevealed),
+            _buildReconciliationRow(tr('البنك الفعلى'), _actualCardController, state.bankVariance, PhosphorIconsBold.creditCard, AppColors.info, state.isRevealed && cashActualEntered),
@@
-            _buildReconciliationRow(tr('كليك الفعلى'), _actualClickController, state.clickVariance, PhosphorIconsBold.deviceMobile, AppColors.warning, state.isRevealed),
+            _buildReconciliationRow(tr('كليك الفعلى'), _actualClickController, state.clickVariance, PhosphorIconsBold.deviceMobile, AppColors.warning, state.isRevealed && cashActualEntered),
@@
-                : (totalVar < 0 ? tr('نقص: {p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}) : tr('زيادة: +{p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
+                : (totalVar < 0 ? tr('عجز: {p0} {p1}', {'p0': totalVar.abs().toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}) : tr('فائض: +{p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
```

```diff
--- a/lib/presentation/reports_picpos/screens/reports_picpos_cards.dart
+++ b/lib/presentation/reports_picpos/screens/reports_picpos_cards.dart
@@
-          _kpiCard(PhosphorIconsBold.currencyCircleDollar, tr('مبيعات اليوم'),
+          _kpiCard(PhosphorIconsBold.currencyCircleDollar, tr('صافي مبيعات اليوم (بعد المرتجعات)'),
@@
-          _kpiCard(PhosphorIconsBold.arrowUUpLeft, tr('المرتجعات'),
+          _kpiCard(PhosphorIconsBold.arrowUUpLeft, tr('المرتجعات (للعلم فقط — مطروحة بالفعل)'),
```

```diff
--- a/lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart
+++ b/lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart
@@
-        dashFilter.branchId == null ? tr('كل الصناديق') : tr('صناديق الفرع');
+        dashFilter.branchId == null ? tr('إجمالي الصناديق والبنوك') : tr('صناديق الفرع');
```

```diff
--- a/lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart
+++ b/lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart
@@
-                  suffixText: 'JOD',
+                  suffixText: ref.watch(systemCurrencySettingProvider).asData?.value ?? '',
--- a/lib/presentation/pos/widgets/pos_opening_balance_dialog.dart
+++ b/lib/presentation/pos/widgets/pos_opening_balance_dialog.dart
@@
-                  suffixText: 'JOD',
+                  suffixText: ref.watch(systemCurrencySettingProvider).asData?.value ?? '',
```

```diff
--- a/lib/data/providers/providers.dart
+++ b/lib/data/providers/providers.dart
@@
+final systemCurrencySettingProvider = FutureProvider<String?>((ref) async {
+  ref.watch(systemCurrencyProvider);
+  final saved = await ref.read(databaseProvider).getSettingValue('system_currency');
+  if (saved == null || saved.isEmpty) return null;
+  return CurrencyInfo.fromCode(saved).code;
+});
```

```diff
--- a/assets/i18n/en.json
+++ b/assets/i18n/en.json
@@
+  "إجمالي المدفوعات من الصندوق": "Total cash paid out",
+  "عجز: {p0} {p1}": "Deficit: {p0} {p1}",
+  "فائض: +{p0} {p1}": "Surplus: +{p0} {p1}",
@@
+  "المرتجعات (للعلم فقط — مطروحة بالفعل)": "Returns (informational only — already deducted)",
+  "رُفض إغلاق الوردية لأن فرق النقد يتجاوز الحد المسموح. عدّل النقدي الفعلي ثم أعد المحاولة.": "Shift closing was rejected because the cash variance exceeds the allowed limit. Adjust the actual cash amount and try again.",
+  "فائضٌ في الدرج": "Drawer Surplus",
+  "فرق يتجاوز الحد المسموح": "Variance exceeds the allowed limit",
+  "إجمالي الصناديق والبنوك": "Total cash boxes and banks",
+  "صافي مبيعات اليوم (بعد المرتجعات)": "Today's net sales (after returns)",
```

`test/phase0/shift_close_rejection_test.dart` ملف اختبار جديد؛ لأنه غير متتبع لا يظهر في `git diff` الاعتيادي. مقتطف الإضافة:

```diff
--- /dev/null
+++ b/test/phase0/shift_close_rejection_test.dart
@@
+        if (accepted) {
+          expect(find.byType(PicposCashierClosingDialog), findsNothing);
+          expect(notifications.any((entry) => entry.message.contains('تم إغلاق الوردية')), isTrue);
+          expect(auth.signedOut, isTrue);
+        } else {
+          expect(find.byType(PicposCashierClosingDialog), findsOneWidget);
+          expect(find.text('رُفض إغلاق الوردية لأن فرق النقد يتجاوز الحد المسموح. عدّل النقدي الفعلي ثم أعد المحاولة.'), findsOneWidget);
+          expect(auth.signedOut, isFalse);
+        }
```



## ملحق المراجِع (2026-11-01): تعليقات ضُغطت وقيود معروفة

### أ) أسباب أعمال كانت مكتوبة تعليقاً وضُغطت لإرضاء حارس الحجم (`file_size_ratchet`)
لم يُحذف أي سطر منطق، لكن تعليقات توثّق *لماذا* كُتب المنطق على هذا النحو اختُصرت في
`picpos_cashier_closing_dialog.dart`. هذا نصّها الأصلي (من النسخة الاحتياطية قبل المرحلة 0) كي لا يضيع:

1. **سبب الفرق حقل حر لا قائمة جاهزة** (`_promptVarianceReason`): قائمة قصيرة تدفع الكاشير لاختيار أقرب بند لا لوصف
   ما حدث، فتُنتج بيانات مرتّبة بلا معنى.
2. **الحدّ بالقيمة المطلقة** (§٤ `diffmax`): العجز ٢٥ يحتاج سبباً كما تحتاجه الزيادة ٢٥؛ إهمال الإشارة يُعفي العجز
   وهو الأخطر محاسبياً (المال الناقص يمرّ بلا تفسير). المنطق في `quickSaleShiftDiffNeedsReason`.
3. **`await` لا قراءة باردة** للسياسة (`quickSalePolicyProvider.future`): الدالة غير متزامنة أصلاً، والقراءة
   الباردة ترجع `null` قبل أن يسخن المزوِّد فيمرّ الفرق بلا سبب.
4. **أكبر القنوات لا مجموعها** (`quickSaleGoverningShiftDiff`): المجموع يُقاصّ؛ عجز نقدي −٣٠٠ وفائض بنك +٣٠٠
   يعطيان صفراً فيمرّ الإغلاق بلا سبب، بينما `closeShiftWithAudit` ترحّل **النقدي وحده** فتخرج ٣٠٠ من الدرج ومن
   الدفاتر بلا تفسير (بلاغ التدقيق المحاسبي 2026-08-30).

**توصية:** إعادة هذه التعليقات الأربعة حرفياً في ملف مجاور (مثلاً `picpos_cashier_closing_rationale.dart` بتعليقات فقط
أو نقل منطق مساعد إلى ملف جديد) عندما يُسمح بتوسيع الملفات، دون رفع سقف الحجم.

### ب) قيد معروف في العرض (لم يُعالَج)
شرط إظهار الفرق `revealed && cashActualEntered` يربط صفّي **البنك** و**كليك** بإدخال **النقدي الفعلي** فقط.
فإن أدخل الكاشير فعلي البنك وحده فلن يظهر فرق البنك حتى يُدخل النقدي. المطلوب لاحقاً: ربط كل صف بحقله هو.
هذا عرض فقط ولا يغيّر ما يُحسب أو يُرحَّل.

### ج) تحقق حيّ (مدقق الواجهة، قاعدة اختبار معزولة)
قبل الإصلاح وعلى النسخة غير المعدَّلة: إغلاق الوردية بفعلي 0.00 (متوقع 83.88) وبفعلي 500 أعاد التطبيق إلى شاشة
الدخول والوردية ما زالت `open` و`end_time` فارغ، وبالقيمة المطابقة 83.88 ظهر «المطابقة تامة». أي أن AUD-F01
**ثبت حياً**. لم تُعَد التجربة الحية بعد الإصلاح (يحتاج بناءً جديداً عبر `build_picpos.bat`).
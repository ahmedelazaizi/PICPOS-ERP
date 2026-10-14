# حالة M-0 — «PicPos كاشير»

> **الحالة الحالية:** تطبيق `mobile_pos` معاينة لهيكل أولي، وليس نقطة بيع متصلة أو غير متصلة جاهزة للاستخدام التشغيلي. هذه الملاحظات تصف التنفيذ الموجود اليوم، لا السلوك المخطط للمراحل التالية.

## ما يعمل الآن

- يتيح التطبيق معاينة قشرة الواجهة من شاشة التهيئة؛ شاشة الربط نفسها واجهة فقط، وحقول العنوان والرمز وزرا المسح والربط معطّلة. يوضح ذلك [شاشة التهيئة](../../mobile_pos/lib/screens/onboarding_screen.dart) ومسار العرض في [app.dart](../../mobile_pos/lib/app.dart).
- الواجهة تدعم العربية والإنجليزية، والمظهرين الفاتح والداكن. إعداد اللغة والمظهر موجود في [إعدادات الواجهة المشتركة](../../packages/picpos_ui/lib/src/widgets/picpos_app.dart) و[عناصر اختيار اللغة والمظهر](../../packages/picpos_ui/lib/src/widgets/settings_controls.dart)، ونصوص التطبيق الثنائية في [strings.dart](../../mobile_pos/lib/l10n/strings.dart).
- يتكيف التنقل بين شريط سفلي للهاتف و`NavigationRail` للأحجام الأوسع، وفق [adaptive_scaffold.dart](../../packages/picpos_ui/lib/src/widgets/adaptive_scaffold.dart). تعرض القشرة تبويبات البيع والمعلّقة والوردية والمرتجعات والإعدادات في [pos_shell.dart](../../mobile_pos/lib/shell/pos_shell.dart).
- مؤشر «معاينة فقط» ونصوص توضح تعطّل الميزات موجودة بالفعل في شاشة البيع والصفحات النائبة والإعدادات، كما في [sale_page.dart](../../mobile_pos/lib/screens/sale_page.dart)، و[placeholder_page.dart](../../mobile_pos/lib/screens/placeholder_page.dart)، و[settings_page.dart](../../mobile_pos/lib/screens/settings_page.dart)، و[strings.dart](../../mobile_pos/lib/l10n/strings.dart).

## ما لم يُنفّذ

لا يوجد اتصال شبكي بخادم المكتب، ولا كتالوج أصناف محلي، ولا دورة بيع/وردية للكاشير، ولا تكامل طابعة، ولا صندوق صادر (`outbox`) أو مزامنة دون اتصال. شاشة البيع تعرض حالة فارغة، وحقل المسح/البحث وزر الدفع معطّلان ([sale_page.dart](../../mobile_pos/lib/screens/sale_page.dart))، بينما تعرض صفحات الوردية والمرتجعات رسائل معاينة ([pos_shell.dart](../../mobile_pos/lib/shell/pos_shell.dart)، [strings.dart](../../mobile_pos/lib/l10n/strings.dart)). ويصرّح اختبار E2E بعدم وجود عميل شبكة أو مخزن محلي، ويحدد التدفقات غير المنفذة على أنها متجاوزة عمدًا ([pos_app_e2e_test.dart](../../mobile_pos/test/e2e/pos_app_e2e_test.dart)).

## المراحل التالية

الربط وPOS المتصل موصوفان كخطة **M-5**، والعمل دون اتصال والمرتجعات والصادر والإغلاق بعد تفريغ الطابور موصوفة كخطة **M-6**؛ راجع [معمارية المرحلة M، §4.1 — Phases](ARCHITECTURE-M.md#41-phases). هذه عناصر مخطط لها وليست خصائص منفّذة في `mobile_pos` حاليًا.

## التحقق الحالي

الأوامر التالية شُغّلت من مجلد `mobile_pos`:

```text
flutter analyze
```

نجح التحليل دون ملاحظات.

```text
flutter test test/structural_test.dart test/golden_test.dart test/shell_test.dart
```

نجحت الاختبارات كلها.

```text
flutter test test/e2e/pos_app_e2e_test.dart
```

نجح الاختباران القابلان للتشغيل، وتُركت ستة تدفقات M-5/M-6 متجاوزة عمدًا كما يبين [اختبار E2E](../../mobile_pos/test/e2e/pos_app_e2e_test.dart). هذه النتائج تتحقق من الواجهة والاختبارات المحددة فقط، ولا تثبت جاهزية إصدار تشغيلي.

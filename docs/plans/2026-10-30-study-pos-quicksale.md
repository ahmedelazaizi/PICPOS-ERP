# دراسة: شاشة البيع السريع (PicPos) — سبعة بنود

> **النوع:** دراسة فقط. لم يُعدَّل أي ملف كود، ولم تُشغَّل اختبارات أو `flutter analyze`.
> **المصدر:** قراءة موجّهة (grep وقراءات جزئية). المراجع بصيغة `ملف:سطر` بحسب الشجرة الحالية بتاريخ 2026-10-30.
> **الشاشة:** `lib/presentation/pos_picpos/screens/picpos_pos_screen.dart` وملفات الـ`part` التابعة لها في المجلد نفسه، مع الحالة المشتركة في `lib/presentation/pos/providers/cart_controller.dart`.
>
> ملاحظة: في الشجرة تغييرات للمستخدم لم تُلمَس، منها `cycle_count_*` و`installer/*` و`pubspec.yaml`. لا يتقاطع أيٌّ منها مع ملفات هذه الدراسة.

---

## 1) إخفاء شريط التابات + سلة غير فارغة ⇒ تنبيه عند التنقل أو الإغلاق أو الخروج

### الوضع الحالي
- **مفتاح الإعداد:** `app_show_top_bar`، وقيمته الافتراضية `true`. يقرؤه `showTopBarProvider` في `lib/data/providers/settings_providers.dart:302-306`، وتعرضه واجهة الإعداد في `lib/presentation/widgets/settings/pos_settings_widget_main_section.dart:25`.
- **مستهلكه الوحيد** `lib/presentation/shell/app_shell.dart:1468-1485`، وهو يخفي `ScreenTabsBar` و`ScreenBreadcrumbs` فقط. لا يقرؤه أي حارس تنقل.
- **آلية التنقل:**
  - كل الشاشات المفتوحة حيّة داخل `IndexedStack` (`_openScreensStack` في `lib/app_main_screen_navigation.dart` قرابة السطر 140-162).
  - المعبر الوحيد للتبديل هو `_activateScreenImpl` في `lib/app_main_screen_navigation.dart:49`. يمرّ به الشريط الجانبي والبحث العام (`:557-560`) ولوحة التحكم (`lib/app_main_screen_catalog.dart:10-12`) و`screenNavigationProvider`.
  - عند بلوغ السقف `kMaxScreenTabs` يُغلق تاب أقدم بصمت، مع snackbar فقط (`:63-67`). قد يكون هذا التاب هو تاب البيع نفسه.
- **الحرّاس الموجودة:**
  - إغلاق تاب البيع: `_closeTabImpl` (`:188-236`) يطلب تأكيداً إذا كانت السلة عامرة (`:196-228`). لكنه لا يُستدعى إلا من زر ✕ في الشريط، فإذا أُخفي الشريط لا يُطلب التأكيد أبداً.
  - إغلاق النافذة: `setPreventClose(true)` في `lib/main_desktop.dart:34`، ثم `onWindowClose` في `lib/app_main_screen_lifecycle.dart:354-360`، ثم `shouldBlockAppCloseForCart` في `lib/domain/models/app_close_cart_gate.dart:30`. **يعمل سواء ظهر الشريط أم أُخفي.** والاستثناء المقصود هو وضع الخادم (إخفاء النافذة لا إغلاقها، `:344`).
  - زر «إغلاق البرنامج»: `runCloseAppAction` في `lib/presentation/shell/app_shell_close_action.dart:24`، وهو يمنع الإغلاق أيضاً.
  - `PopScope` في `lib/app_main_screen_navigation.dart:357-390` يمنع الخروج إذا كانت السلة عامرة.
  - **تسجيل الخروج:** `_showLogoutConfirmation` في `lib/presentation/shell/app_shell.dart:252-316` يعرض سؤالاً عامّاً ثم **يفرّغ السلة بصمت** (`clearCart()` في `:299`). ولا يوجد أي فحص للسلة في مسارات الخروج الأخرى: `inactivity_detector.dart:198` و`session_timeout_wrapper.dart:182` و`no_screens_available_view.dart:45` و`picpos_cashier_closing_dialog.dart:1298` و`pos_cashier_closing_dialog.dart:1059`.

### السبب الجذري
التعليق في `lib/app_main_screen_navigation.dart:435-439` يوضح أن حارس «السلة غير فارغة» عند التنقل **أُزيل عمداً** حين أُضيفت التابات. الافتراض كان أن التاب يبقى حيّاً فلا تضيع السلة، وأن الشريط الظاهر يذكّر الكاشير بها. مع `app_show_top_bar=false` يختفي التذكير وتختفي معه نقطة الدخول الوحيدة إلى تأكيد إغلاق التاب، ولا يفحص `_activateScreenImpl` الإعداد ولا السلة. أما الخروج فلا يحذّر من السلة أصلاً، سواء ظهر الشريط أم أُخفي.

### الإصلاح المقترح
1. **دالة قرار خالصة** بجوار `shouldBlockAppCloseForCart`، إما في `lib/domain/models/app_close_cart_gate.dart` أو في ملف جديد `lib/domain/models/pos_navigate_away_gate.dart`:
   `bool shouldWarnLeavingPos({required bool tabsBarVisible, required bool activeIsPos, required int cartCount, required bool returnOrExchangeActive})`.
2. **`_activateScreenImpl`** (`app_main_screen_navigation.dart:49`): إذا كان الشريط مخفياً والتاب النشط هو البيع والسلة عامرة (أو كان وضع مرتجع/استبدال فعّالاً)، يُعرض `AppConfirmDialog` بخيارين: «البقاء» و«الانتقال مع إبقاء السلة». السلة لا تُفرَّغ لأن التاب حيّ. الدالة متزامنة الآن، فإما تُحوَّل إلى `Future<void>` أو يُضاف غلاف `_guardedActivate` يتولى السؤال ثم يستدعيها. ويطبَّق الفحص نفسه على الإخلاء بالسقف (`:63`): يُستثنى تاب البيع من `evictionCandidate` إذا كانت سلته عامرة.
3. **تسجيل الخروج** (`app_shell.dart:252`): إذا كانت السلة عامرة، يُعرض تحذير صريح بعدد الأصناف قبل `clearCart`، مثل «في السلة N أصناف ستُحذف». مقترح مكمّل في المهمة نفسها: تصفير `posReturnModeProvider` و`posExchangeModeProvider` عند الخروج (راجع البند 5)، فلا يجري ذلك الآن إلا في `picpos_switch_user_dialog.dart:132`.
4. الخروج القسري (الخمول أو انتهاء الجلسة) يبقى بلا سؤال لأنه أمني، لكن يُسجَّل في `activity log` حذف سلة عامرة. هذه نقطة مفتوحة.
5. إغلاق النافذة لا يحتاج تغييراً.

### المخاطر
- تحويل `_activateScreenImpl` إلى async قد يُحدث سباقاً مع `popUntil` والنقرات المتتالية، فيلزم علم `_navigating` يمنع إعادة الدخول.
- يجب ألا يظهر التنبيه في كل تنقل حين يكون الشريط ظاهراً، فالسلوك الحالي مقصود هناك.
- في وضع الخادم يُستدعى `_activateScreen` من مسارات آلية (`app_main_screen_lifecycle.dart:95`)، فلا ينبغي أن يظهر ديالوج في مسار لا يقف خلفه مستخدم.

### الاختبارات
- اختبار unit جديد لـ`shouldWarnLeavingPos` يغطي كل التوافيق، على نمط `test/unit/app_close_cart_gate_test.dart`.
- تحديث أو توسيع `test/unit/screen_tabs_test.dart` و`test/widget/screen_tabs_bar_test.dart` و`test/widget/picpos_shell_test.dart` و`test/structural/screen_tabs_are_wired_test.dart`، بإضافة حالة «الشريط مخفي + تنقل».
- `test/widget/app_shell_close_action_test.dart`: حالة الخروج مع سلة عامرة.
- انحدار: `test/unit/close_app_gate_test.dart` و`test/unit/picpos_close_permissions_test.dart`.

---

## 2) زر «حفظ» (F2) لا يفتح درج النقود

### الوضع الحالي
- الزرّان يمرّان بـ`_processPaymentAndSave` (`lib/presentation/pos_picpos/screens/picpos_pos_checkout.dart:30`)، فكلاهما يعرف `method`:
  - «دفع» F4: `_handleCheckout` (`:6`) يمرّر `printAfter: true`.
  - «حفظ» F2: `_saveOnly` (`:9`) يمرّر `printAfter: false`. ارتباطه في `picpos_pos_screen.dart:165` و`:524`.
- **منطق الدرج كله داخل فرع الطباعة:** يبدأ عند `if (printAfter && autoPrint)` في `picpos_pos_checkout.dart:368`، ثم يُحسب `openDrawer = isOn('drawer') && method == 'cash'` في `:376-378`، ثم تُرسل الركلة بالتوازي مع الطباعة عبر `_openCashDrawerQuietly()` (`:379-380`) ويُنتظر انتهاؤها في `:396`. أما فرع `else` في `:405-408` فلا يعرض إلا toast.
- **قرار سابق موثَّق:** التعليق في `picpos_pos_checkout.dart:28-29` يقول إن الحفظ لا يفتح الدرج «كي لا يتعوّد الكاشير تجاهل الركلة»، واختبار `test/widget/picpos_pos_keys_test.dart:50` يثبّت هذا: `'F2 stays a plain save — no print, no drawer'`.
- **إعدادات الدرج:**
  - `pos_open_drawer_on_print`: صفّ `drawer` في `lib/domain/models/quick_sale_policy.dart:568-576`، مفعَّل افتراضياً، ونصّه الفرعي «يفتح في الدفع النقدي فقط». إعداد خاص بكل جهاز ومستثنى من المزامنة (`lib/services/sync/strategies/setting_sync_strategy.dart:141-146`).
  - `auto_print_receipt` (صفّ `autoprint`، `:365`): إطفاؤه يوقف الدرج أيضاً، لأن الدرج محشور داخل فرع الطباعة. **هذا عيب ثانٍ.**
  - `cash_drawer_printer`، وإلا `receipt_printer`، وإلا `'Default'`: يختارها `_drawerPrinterName` في `lib/presentation/pos_picpos/screens/picpos_pos_drawer.dart:9-19`.
  - `show_drawer_button_pos`: يتحكم في إظهار الزر اليدوي فقط.
- **الركلة نفسها:** `CashDrawerService.openDrawer` (`lib/services/cash_drawer_service.dart:11`). البايتات `ESC p 0 25 250` و`ESC p 1 25 250` (`lib/services/cash_drawer_service_io.dart:14-16`) تُرسل **مهمةً خاماً مستقلة** إلى الـspooler، وليست جزءاً من بايتات الإيصال، لأن الإيصال يُطبع PDF عبر `Printing.directPrintPdf`.
- **ركلة ثانية محتملة:** `lib/services/generators/thermal_receipt_generator.dart:173` و`:185` يستدعيان `openDrawer` بعد الطباعة دون اعتبار للإعداد ولا لطريقة الدفع. **لم يُتحقَّق** هل يصل `printInvoice` (`picpos_pos_checkout_support.dart:89`) إلى هذا المولّد. إن كان يصل، فـF4 يركل الدرج مرتين، ويركله حتى في دفع البطاقة.
- **الزر اليدوي:** `_openDrawer` (`picpos_pos_drawer.dart:22-44`) محروس بـ`pos_open_drawer` (`picpos_cart_permissions.dart:127-143`) ومسجَّل في السجل. الركلة التلقائية `_openCashDrawerQuietly` (`:53-60`) غير محروسة عمداً (`permission_enforcement_registry.dart:175-177`).

### السبب الجذري
قرار تصميم سابق جعل فتح الدرج تابعاً لـ«الطباعة» لا لـ«قبض النقد». بحسب منطق الربط الذي اتُّفق عليه، الدرج يُفتح عبر الطابعة لأنه موصول بها كهربائياً، **لا لأن إيصالاً طُبع**، والركلة أصلاً مهمة مستقلة. فلا يوجد مانع تقني من فتحه في الحفظ.

### الفرضيات
- ف1: الحفظ النقدي يعني قبض نقد يدخل الدرج، فالدرج يجب أن يُفتح.
- ف2: يكفي أن تكون الطابعة الموصول بها الدرج (`cash_drawer_printer`) متاحة، ولا يلزم أن يُطبع إيصال.
- ف3: الدفع بالبطاقة أو الآجل لا يفتح الدرج. والدفع المختلط (نقد + بطاقة) يفتحه إذا كان الجزء النقدي أكبر من صفر. **يلزم التحقق** من القيمة التي يحملها `method` في الدفع المختلط.

### الإصلاح المقترح
داخل `_processPaymentAndSave` (`picpos_pos_checkout.dart`):
1. يُنقل حساب `openDrawer` إلى **ما قبل** `if (printAfter && autoPrint)` ليصبح قراراً مستقلاً. ويُستخرج في دالة خالصة داخل `picpos_pos_decisions.dart`، مثل `shouldKickDrawer(policy, method, {required bool printing})`، كي تسهل كتابة اختبار له.
2. فرع الطباعة يبقى كما هو، مع الركلة الموازية.
3. فرع `else`، أي الحفظ F2 أو `autoprint` مطفأ: إذا كان `openDrawer` صحيحاً يُستدعى `await _openCashDrawerQuietly()`، الدالة والطابعة نفسيهما. هذا لا يكسر الربط بالطابعة، فالمسار نفسه والمنفذ نفسه.
4. خيار أكثر تحفّظاً: صفّ جديد في `quick_sale_policy.dart`، مثل `drawer_on_save` أو تعديل نص صف `drawer` ليصبح «فتح الدرج عند قبض النقد». ومعه منع الركلة المزدوجة: إذا ثبت أن `ThermalReceiptGenerator` يركل الدرج، يُمرَّر له علم `kickDrawer: false` من مسار البيع السريع حتى تبقى سياسة البيع السريع وحدها صاحبة القرار.

### المخاطر
- يتعارض مع قرار مالك موثَّق (التعليق في `:28-29`)، فيلزم تأكيد صريح.
- ركلة مزدوجة إذا لم يُحسم أمر `thermal_receipt_generator.dart`.
- إذا كانت الطابعة غير متصلة أثناء الحفظ، تفشل `_openCashDrawerQuietly` بصمت. يجب أن تبقى صامتة وألا تعطّل الحفظ.
- اختبارات الحراسة البنيوية تراقب أسلوب قراءة السياسة (`quick_sale_policy_read_style_guard_test.dart`).

### الاختبارات
- تحديث `test/widget/picpos_pos_keys_test.dart:50` باسم ونية جديدين: «F2 نقدي يفتح الدرج حسب الإعداد، وF2 بطاقة لا يفتحه».
- توسيع `test/unit/quick_sale_policy_effect_test.dart:253` و`:263` بحالات مسار الحفظ، وبحالة `autoprint` مطفأ مع `drawer` مفعَّل في الدفع النقدي، والمتوقع أن يُفتح الدرج.
- انحدار: `test/unit/quick_sale_policy_test.dart` و`test/structural/quick_sale_reaches_picpos_engine_test.dart` و`test/structural/quick_sale_policy_read_style_guard_test.dart` و`test/structural/per_device_pos_settings_guard_test.dart` و`test/unit/picpos_cart_permissions_test.dart`.

---

## 3) إعداد إخفاء زرّي «استبدال» و«مرتجع» لا يعمل

### الوضع الحالي
- **المفاتيح:** `show_return_button_pos` و`show_exchange_button_pos`. يبدّلهما `pos_settings_widget_main_section.dart:261-272`، ويحفظهما `pos_settings_widget_storage.dart:499-501` و`hardware_settings_widget.dart:356-358`، مع إبطال الـproviders بعد الحفظ (`storage:590-592` و`hardware:390-392`).
- **الـproviders:** `showReturnButtonInPOSProvider` و`showExchangeButtonInPOSProvider` في `lib/data/providers/settings_providers.dart:120-138`. سليمان وتفاعليان.

### السبب الجذري
المستهلك الوحيد لهما هو `lib/presentation/pos/widgets/pos_header.dart:187-189`، أي شاشة البيع القديمة. أما في PicPos فـ`_ActionButtons.build` (`lib/presentation/pos_picpos/widgets/picpos_payment_panel.dart:771-775`) يراقب `showDrawer` و`showExpense` و`showSaveOnly` و`showHold` فقط، ويبني «مرتجع سريع» (`:871-882`) و«استبدال» (`:886-897`) **بلا شرط**.

### الإصلاح المقترح (في ملف واحد: `picpos_payment_panel.dart`)
```dart
final showReturn = ref.watch(showReturnButtonInPOSProvider).value ?? true;
final showExchange = ref.watch(showExchangeButtonInPOSProvider).value ?? true;
...
if (showReturn) ...[ SizedBox(width: 5 * scale), Expanded(child: _Action(label: tr('مرتجع سريع'), ...)) ],
if (showExchange) ...[ SizedBox(width: 5 * scale), Expanded(child: _Action(label: tr('استبدال'), ...)) ],
```
على نمط `showSaveOnly` نفسه (`:834`).

### المخاطر
- إخفاء الزر لا يمنع الوظيفة من الاختصارات إن وُجدت. يلزم التحقق من `picpos_pos_shortcuts.dart`: هل فيها مفتاح للمرتجع أو الاستبدال؟ وهل ينبغي أن يحترم الإعداد نفسه؟ هذه نقطة مفتوحة.
- قد يتغيّر تخطيط الصف، و`picpos_payment_panel_layout_test.dart` يقيس العروض.

### الاختبارات
- `test/widget/pos_picpos/picpos_payment_panel_layout_test.dart`: حالات «مخفي/ظاهر» لكل زر مع override للـproviders.
- انحدار: `test/widget/picpos_return_mode_test.dart` و`test/widget/picpos_exchange_mode_test.dart`.

---

## 4) مرتجع سريع لصنف بلا فاتورة داخل شاشة البيع السريع (تصميم)

### البنية الحالية
- **مرتجع PicPos الحالي مرتبط بفاتورة:** `PosReturnMode` (`lib/presentation/pos_picpos/state/pos_return_mode.dart`) يحمل `invoiceId` و`ReturnableLine` لكل سطر أصلي و`requestedQty` بحسب `invoiceItemId`. **لا يكتب في `cartController` إطلاقاً.** وحفظه عبر `returnsRepository.processSalesReturn` (`lib/data/repositories/returns_repository_impl.dart:131`) يتطلب `SalesInvoiceData` ويحسب على أساسها:
  - سقف الكمية (`:151-167`).
  - الضريبة النسبية والتكلفة المجمّدة `item.costPrice`.
  - `adjustStock(+qty)` عند `trackInventory` (`:402-421`).
  - التالف (`:445-468`).
  - تقسيم الاسترداد AR/نقد/بنك (`:476`).
  - `autoPostSalesReturn` (`:650`)، ثم ختم الفاتورة الأصلية.
  - يُشترط وردية مفتوحة للنقد (`ShiftRequiredException`، `:186-192`).
- **مسار قائم للمرتجع بلا فاتورة (الشاشة القديمة):** `CartItemType.returned` بكميات موجبة (`cart_controller.dart:875-887`، `convertToQuickReturn`)، ثم `checkout_controller.dart:240-241` يضبط `isReturn`/`saleType='return'`، ثم `sales_transaction_orchestrator.dart` يولّد مستند `RET-` (`:203` و`:376` و`:933`). أثر المخزون والخزنة والطرف في `lib/data/database/daos/sales_mutations_dao.dart:372-588`. والقيد يُرحَّل داخل `createSalesInvoice` بـ`referenceType='sales_return'`، و`accounting_autopost_cash_sale_dao.dart:26` يتخطاه عمداً كي لا يتكرر. وتجميعات الوردية تعرفه (`treasury_shift_aggregates_dao.dart:182`).
- **الصلاحيات المتاحة:** `pos_return` (`permission_codes.dart:23`) و`sales_return_create` (`:427`) و`sales_return_approve` (`:439`). لا يوجد كود لـ«مرتجع بلا فاتورة».

### التصميم المقترح (الخيار أ: سطور مرتجع داخل السلة)
1. **النموذج:** يُعاد استخدام `CartItemType.returned` الموجود في `CartItemEntity`، بكمية موجبة وعلم نوع، بلا أرقام سالبة. والمعتمد هو نهج السلة القديمة نفسه.
2. **الدخول:** زر أو اختصار «إضافة كمرتجع» (مثل `Shift+F?` أو تبديل «وضع إدخال: مرتجع» بجوار حقل الباركود). بعده يُضاف الصنف التالي بالمسح أو البحث بنوع `returned`. يمرّ ذلك عبر `picpos_pos_product_entry.dart` و`picpos_pos_barcode_scan.dart` بعلم `_entryAsReturn`، مع إضافة دالة `addReturnItem(product, qty)` في `cart_controller.dart`.
3. **السعر:** سعر البيع الحالي بحسب قائمة الأسعار، والتكلفة WAC الحالي، لأنه لا توجد فاتورة مرجعية. ويحتمل أن يُسمح بتعديل السعر بصلاحية مستقلة.
4. **سلة مختلطة (بيع + مرتجع)** تمثّل استبدالاً بلا فاتورة. **المقترح للمرحلة الأولى: منع الخلط.** السلة إما كلها بيع أو كلها مرتجع، لأن المسار الحالي يجعل `saleType='return'` إذا وُجد سطر مرتجع واحد (`checkout_controller.dart:241`)، وهذا سيقلب البيع كله مرتجعاً. يوضع الحارس في دالة قرار خالصة داخل `picpos_pos_decisions.dart`.
5. **الحفظ:** في `_processPaymentAndSave`، إذا كانت كل السطور `returned`، تُستخدم بوابة `CompleteSaleRequest(isReturn: true, saleType: 'return')`، ويُعرض ديالوج «طريقة الاسترداد»: نقد من الوردية، أو رصيد عميل إن كان عميلاً مسجّلاً. **ولا تُستخدم `processSalesReturn`** لأنها لا تعمل بلا فاتورة.
6. **المخزون:** `+qty` بحسب `trackInventory` عبر المسار القائم في `sales_mutations_dao`. يلزم التحقق من حالة الصنف التالف، فالمسار المرتبط بفاتورة يدعمها ومسار `RET-` قد لا يدعمها.
7. **الحسابات:** قيد `sales_return` من المسار القائم، وحركة خزنة سالبة في وردية مفتوحة. يُشترط فحص `ShiftRequired` المماثل.
8. **الصلاحيات:** صلاحية جديدة `pos_return_no_invoice` في `permission_codes.dart` مع موافقة مدير احتياطية، على نمط `picpos_pos_return.dart:40-48`، إضافة إلى سقف قيمة اختياري في `quick_sale_policy`. ويلزم تحديث `test/structural/picpos_permission_parity_test.dart` وسجل التطبيق `permission_enforcement_registry.dart`.
9. **التمييز البصري:** سطر المرتجع بالأحمر وبعلامة «مرتجع» في `cart_item_tile`/جدول PicPos، والإجمالي سالب في العرض.

### المخاطر
- **مالية:** مرتجع بلا فاتورة باب للاحتيال (إرجاع صنف لم يُشترَ من الفرع)، فتلزم صلاحية مستقلة وسجل نشاط.
- `blocksCartMutation` (`picpos_pos_decisions.dart:166`) يمنع الإضافة في وضع المرتجع المرتبط بفاتورة. يجب ألا يُفعَّل الوضعان معاً.
- `app_close_cart_gate.dart:27` يتجاهل وضع المرتجع عمداً، وسطور المرتجع الجديدة ستكون في `cartController` فيشملها الحارس تلقائياً. هذا سلوك مرغوب، لكنه يُثبَّت باختبار.
- التقارير (الضريبة، الوردية، `distribution_rep_ops_dao.dart:232`) تعرف `saleType=='return'`، فالأثر متسق، لكن يلزم اختبار تكامل.
- وضع client/mirror: يلزم التحقق من أن `api_sales_handler` يعامل `RET-` صحيحاً (التعليق في `accounting_autopost_cash_sale_dao.dart:23-25` يشير إلى خلل سابق هنا).

### الاختبارات
- unit: `addReturnItem` ومنع الخلط و`shouldBlockMixedCart`، بجوار `test/unit/picpos_quick_add_test.dart` و`test/unit/cart_stock_guard_test.dart`.
- integration: مرتجع بلا فاتورة ثم مخزون +qty وقيد `sales_return` وحركة خزنة في الوردية، على نمط `test/unit/pos_return_refund_total_matches_spent_test.dart` و`test/unit/exchange_atomicity_test.dart`.
- structural: `picpos_permission_parity_test.dart` و`return_refund_required_fields_test.dart`.
- انتباه: `test/unit/exchange_mode_removed_test.dart` يخص `convertToQuickReturn` في الشاشة القديمة. قد يمنع إعادة استخدامه بالاسم، فتلزم مراجعته قبل البدء.

---

## 5) وضع المرتجع يُعلِّق الشاشة (لا إضافة ولا تعديل)

### الوضع الحالي
- يُضبط الوضع بعد تأكيد محرّر السطور: `picpos_pos_return.dart:158-162`، و`posReturnModeProvider` هو `StateProvider` عام (`providers/pos_return_mode_provider.dart:21`).
- **القفل:** `blocksCartMutation(mode) => mode != null` (`picpos_pos_decisions.dart:166`) يمنع إدخال الأصناف (`picpos_pos_product_entry.dart:26`)، والمسح (`picpos_pos_barcode_scan.dart:15` و`:44`)، والمعلَّقات (`picpos_pos_invoice_actions.dart:93`). كما يعطّل أزرار المرتجع والاستبدال (`picpos_payment_panel.dart:876` و`:891`) والمعلَّقات (`picpos_pos_screen.dart:260`).
- **الترويسة** `lib/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart:17-52` عديمة الحالة، **بلا زر إلغاء وبلا callback**. تُبنى في `picpos_pos_screen.dart:479-482`.
- **سلة المرتجع لا تُعرض:** الوضع لا يكتب في `cartController`، فيرى الكاشير سلة فارغة وترويسة حمراء، بلا أسطر وبلا إجمالي وبلا وسيلة لإعادة فتح المحرر.
- **مخارج الوضع الحالية:**
  - حفظ ناجح (`picpos_pos_return.dart:243`).
  - `_cancelInvoice` (`picpos_pos_invoice_actions.dart:27-39`) عبر **ESC فقط** (`picpos_pos_screen.dart:170`). زر «مسح الكل» `_ClearCartButton` (`picpos_pos_screen.dart:662-674`) **معطّل لأن السلة فارغة**، فلا يصل إلى `_cancelInvoice` في وضع المرتجع.
  - تبديل المستخدم (`picpos_switch_user_dialog.dart:132`).
- **في الإخفاق يبقى الوضع قائماً:** في `ShiftRequiredException` والاستثناءات و`success == false` والكميات الصفرية (`picpos_pos_return.dart:203-240`). وتسجيل الخروج (`app_shell.dart:252-316`) لا يصفّر `posReturnModeProvider`، و**لم يُتحقَّق** هل يُعاد إنشاء الـProviderScope بعد الدخول من جديد.

### السبب الجذري
القفل مقصود، لكن **لا مخرج ظاهر منه**. الترويسة بلا زر، و«مسح الكل» معطّل لأن سلة البيع فارغة، والمخرج الوحيد هو ESC (غير مكتشَف) أو «دفع/حفظ». وإذا فشل الحفظ، كأن لا تكون هناك وردية مفتوحة، يبقى الوضع معلَّقاً. وتزيد الحيرة أن الشاشة لا تعرض ما اختير للإرجاع.

### الإصلاح المقترح
1. `picpos_return_mode_banner.dart`: إضافة `final VoidCallback? onCancel` وزر ✕ «إلغاء المرتجع»، وإضافة `VoidCallback? onEdit` لزر «تعديل الكميات»، مع سطر يعرض عدد الأسطر وإجمالي الاسترداد (`refundTotal`) وتلميح «اضغط دفع/حفظ لتأكيد المرتجع». الترويسة تبقى خالصة بلا Riverpod، التزاماً بحارس `presentation_db_import_guard`.
2. `picpos_pos_screen.dart:480`: تمرير `onCancel: _cancelInvoice` (يحمل ديالوج التأكيد القائم) و`onEdit: _reopenQuickReturnEditor`.
3. `_ClearCartButton` (`picpos_pos_screen.dart:669`): التفعيل إذا كانت السلة عامرة **أو** كان وضع مرتجع/استبدال فعّالاً.
4. دالة `_reopenQuickReturnEditor` تعيد فتح `_QuickReturnLinesEditorDialog(mode: current, invoiceNumber: ...)` ثم تكتب الناتج في الـprovider. هذا في `picpos_pos_return.dart`، فيُنسَّق مع البند 7 (انظر خطة التقسيم).
5. تصفير `posReturnModeProvider` و`posExchangeModeProvider` عند تسجيل الخروج (ضمن مهمة البند 1).

### المخاطر
- الإلغاء يجب أن يفرّغ `_returnInvoice` و`_returnProductCache` معاً، و`_cancelQuickReturn` يفعل ذلك.
- `picpos_return_mode_banner_test.dart` يفترض البنية الحالية فيلزم تحديثه. والتوقيع الجديد اختياري (nullable) للحفاظ على التوافق.

### الاختبارات
- `test/widget/picpos_return_mode_banner_test.dart`: وجود الزر واستدعاء `onCancel`.
- `test/widget/picpos_return_mode_test.dart`: الدخول في الوضع ثم الضغط على ✕ ثم التأكيد، فيُتوقع أن يصبح الـprovider `null` وأن يعمل المسح من جديد. ومعه حالة: حفظ فاشل لا يعلّق الشاشة، والإلغاء متاح.
- انحدار: `test/unit/picpos_quick_add_test.dart` (`blocksCartMutation`) و`test/widget/picpos_exchange_mode_test.dart`.

---

## 6) خصم على الفاتورة بالقيمة بجانب النسبة

### الوضع الحالي
- الإدخال في PicPos: شريحة الخصم (`picpos_payment_panel.dart:401-405`) تستدعي `onEditDiscount: _editInvoiceDiscount` (`picpos_pos_screen.dart:526`)، وهي `AlertDialog` مضمَّن في `lib/presentation/pos_picpos/screens/picpos_pos_cart_edit.dart:251-319`، بحقل واحد «نسبة الخصم %» (`:274`) ومدى من 0 إلى 100 (`:295`).
- الحراسة:
  - `ensureCartDiscountPermission(scope: 'invoice_discount')` (`:255`).
  - `ensureDiscountWithinPolicy` (`picpos_cart_permissions.dart:246-274`)، وهي تعمل **بالنسبة** عبر `quickSaleDiscountCap` ومعها موافقة مدير `posDiscount` عند `discappr`.
  - ثم `setDiscount(percent)` (`:316`).
- الحالة: `CartState.discountPercent` فقط (`cart_controller.dart:100`، و`setDiscount` في `:996-998`). التعليق والاسترجاع يحفظان النسبة فقط (`:1219` و`:1241`).
- الحساب: `CalculateInvoiceTotalsUseCase` (`lib/domain/usecases/sales/calculate_invoice_totals_usecase.dart:23-31`) بمعادلة `round((subtotal − Σ line discounts) × percent/100)`.
- **`CartDiscountDialog` يدعم القيمة أصلاً** (`lib/presentation/pos/widgets/cart/cart_discount_dialog.dart`): `_isPercentMode` (`:28`)، والتحويل `value/subtotal×100`، والتحقق من السقف (`:233-245`). الشاشة القديمة تستخدمه (`cart_view.dart:453`)، وناتجه دائماً نسبة.
- الحفظ: عمود `discount` في `SalesInvoices` (`sales_purchase_tables.dart:310`) يخزّن **مبلغاً**. يلزم التحقق من أن `finalDiscount` في `sales_transaction_orchestrator.dart:1171` هو مجموع خصم الأسطر والفاتورة.

### الإصلاح المقترح
- **المرحلة أ (بلا تغيير مخطط ولا حالة):** استبدال الـ`AlertDialog` في `_editInvoiceDiscount` بتبديل «نسبة / قيمة»، أو إعادة استخدام `CartDiscountDialog` بتمرير `subtotal` = **قاعدة خصم الفاتورة** (`subtotal − Σ خصم الأسطر`، كما في `calculate_invoice_totals_usecase.dart:28`). في وضع القيمة: `percent = value / base × 100`، ثم يُستدعى `ensureDiscountWithinPolicy(percent)` دون تغيير، ثم `setDiscount(percent)`.
- **المرحلة ب (عند الحاجة إلى قيمة دقيقة):** التحويل بالنسبة قد يُرجع 9.99 بدل 10.00 بسبب التقريب. الحل إضافة `invoiceDiscountAmount?` إلى `CartState` وتمريره إلى `CalculateInvoiceTotalsUseCase(invoiceDiscountAmount:)` مقدَّماً على النسبة، مع تحديث التعليق والاسترجاع و`CompleteSaleRequest`. لا يتغير مخطط قاعدة البيانات لأن العمود مبلغ.
- مقترح عملي: المرحلة أ، مع **تقريب عكسي** يتحقق من أن المبلغ الناتج يساوي المُدخل، وتعديل النسبة بدقة عالية (6 خانات) حتى يتطابق المبلغ بعد `round`.

### المخاطر
- تغيّر الأصناف بعد إدخال القيمة: النسبة ثابتة فيتغير المبلغ. هل المتوقع ثبات المبلغ؟ نقطة مفتوحة، ولو كان الجواب نعم فالمرحلة ب لازمة.
- السقف والموافقة نسبيّان، والمستخدم قد يكون له `discountLimitIsPercent=false` (`auth_tables.dart:81`)، أي حدّ بالقيمة. يلزم التحقق من أن `quickSaleDiscountCap` يحترمه.
- قاعدة الخصم إذا كانت صفراً (سلة فارغة أو خصم أسطر كامل) تُنتج قسمة على صفر.

### الاختبارات
- `test/widget/quick_sale_discount_doors_test.dart`: وضع القيمة وتحويله والسقف.
- unit للتحويل القيمة إلى نسبة إلى مبلغ مع حالات التقريب والقاعدة الصفرية، بجوار اختبارات `calculate_invoice_totals`. يلزم البحث عن الملف القائم قبل إنشاء جديد.
- انحدار: `test/unit/return_line_prorates_discount_test.dart`، فالمرتجع يوزّع خصم الفاتورة على الأسطر.

---

## 7) زر «مرتجع» في ديالوج الفواتير السابقة

### الوضع الحالي
- الديالوج `PosPreviousInvoicesDialog` (`lib/presentation/pos/widgets/pos_previous_invoices_dialog.dart:12-39`) يأخذ `onEdit` و`onReprint` و`onPrintKitchen`، وأزرار الصف هي: التفاصيل/المعاينة (`:351`، والتنفيذ في `:479`) والتعديل (`:362`) والمطبخ (`:372`) وإعادة الطباعة (`:377`). يشترك فيه البيع القديم (`pos_main_dialogs.dart:223`).
- مُشغّله في PicPos هو `_showPreviousInvoices` (`picpos_pos_invoice_actions.dart:190-217`).
- مسار المرتجع: `_showQuickReturn()` (`picpos_pos_return.dart:15-164`)، وخطواته:
  1. حارس الوضع (`:20`).
  2. `ensureQuickReturnPermission` (`:33`).
  3. `salesReturnCreate` مع موافقة احتياطية (`:40-48`).
  4. تحذير إن كانت السلة عامرة (`:56-66`).
  5. المنتقي `_QuickReturnInvoicePickerDialog()` بلا معاملات (`:68-72`).
  6. تحميل الأسطر داخلياً (`:74-139`).
  7. المحرر `_QuickReturnLinesEditorDialog(mode:, invoiceNumber:)` (`:141-148`).

### المقترح الأنسب
**فتح محرّر اختيار الأصناف مباشرة** (أي المسار القائم مع تخطي المنتقي)، لا ملء السلة. الأسباب:
- يعيد استخدام كل البوابات والسقف والحساب المحاسبي في `processSalesReturn` دون أي مسار جديد.
- ملء السلة يحتاج تمثيلاً لسطور المرتجع المرتبطة بفاتورة داخل `cartController`، وهذا غير موجود ومتعارض مع تصميم `PosReturnMode`.

التنفيذ:
1. `picpos_pos_return.dart`: `_showQuickReturn({SalesInvoiceData? preselected})`، وفي `:68` تصبح `final invoice = preselected ?? await showDialog(...)`.
2. `pos_previous_invoices_dialog.dart`: معامل اختياري `final void Function(SalesInvoiceData)? onReturn`، والزر يظهر فقط إذا لم يكن `null`، فالشاشة القديمة لا تتأثر. ويُخفى أيضاً إذا كانت `invoice.saleType == 'return'` أو الحالة `returned`.
3. `picpos_pos_invoice_actions.dart` (`_showPreviousInvoices`): `onReturn: (inv) { Navigator.pop(dialogCtx); _showQuickReturn(preselected: inv); }`. يُغلق ديالوج القائمة أولاً.
4. يُحترم إعداد `show_return_button_pos` (البند 3) في هذا الزر أيضاً.

### المخاطر
- الفاتورة المختارة سلفاً تتخطى فلتر `getInvoicesForReturn`. ويبقى الحارس الدفاعي `items.isEmpty` وسقف الكمية في `processSalesReturn`، لكن الأفضل التحقق صراحة من أهلية الفاتورة: ليست مرتجعاً، ولا مرتجعة كلياً، ولا محذوفة، وضمن مهلة الإرجاع إن وُجدت سياسة.
- الديالوج مشترك مع الشاشة القديمة، والمعامل الاختياري يحمي التوافق.

### الاختبارات
- widget: ظهور الزر مع `onReturn` وغيابه بدونه، وغيابه لفاتورة مرتجع.
- `test/widget/picpos_return_mode_test.dart`: مسار «من الفواتير السابقة» يفتح المحرر مباشرة ثم يُضبط الوضع.
- انحدار: `test/unit/picpos_quick_return_lines_test.dart`. لا يوجد اختبار باسم `previous_invoices`.

---

## أسئلة مفتوحة (لا يحسمها الكود)
1. **(بند 2)** قرار المالك السابق «الحفظ لا يفتح الدرج» (`picpos_pos_checkout.dart:28-29`) هل يُلغى؟ وهل يُضاف صف إعداد مستقل `drawer_on_save`، أم يُعمَّم صف `drawer` ليصبح «عند قبض النقد»؟
2. **(بند 2)** في الدفع المختلط (نقد + بطاقة) هل يُفتح الدرج؟ وما قيمة `method` حينها؟
3. **(بند 2)** هل يركل `ThermalReceiptGenerator` الدرج في مسار PicPos فعلاً (ركلة مزدوجة)؟ يُحسم بالتجربة على جهاز أو بتتبع `posControllerProvider.printInvoice`.
4. **(بند 1)** عند التنقل والشريط مخفي: «تنبيه فقط مع إبقاء السلة» أم «منع حتى تُفرَّغ أو تُعلَّق»؟ وهل يُعرض خيار «تعليق الفاتورة ثم الانتقال»؟
5. **(بند 1)** الخروج القسري (الخمول أو انتهاء الجلسة) مع سلة عامرة: تعليق تلقائي للفاتورة أم حذف مع تسجيل؟
6. **(بند 4)** هل يُسمح بسلة مختلطة (بيع + مرتجع بلا فاتورة) في المرحلة الأولى؟ وما طريقة الاسترداد المسموح بها (نقد فقط أم رصيد عميل)؟ وهل يوجد سقف قيمة؟
7. **(بند 4)** سعر المرتجع بلا فاتورة: سعر البيع الحالي، أم آخر سعر بيع للعميل، أم إدخال يدوي بصلاحية؟
8. **(بند 6)** إذا تغيّرت الأصناف بعد خصم بالقيمة، هل يثبت المبلغ أم تثبت النسبة؟
9. **(بند 3)** هل يجب أن تحترم الاختصارات (إن وُجدت) إعداد إخفاء الزر؟

---

## خطة التنفيذ (بالأولوية والاعتماديات)

| الأولوية | البند | الحجم | الاعتمادية |
|---|---|---|---|
| P0 | 5: مخرج من وضع المرتجع | صغير | لا شيء |
| P0 | 3: إخفاء الزرّين | صغير جداً | لا شيء |
| P1 | 1: تنبيه التنقل والخروج | متوسط | السؤالان 4 و5 |
| P1 | 2: الدرج عند الحفظ | صغير | الأسئلة 1-3 |
| P1 | 7: مرتجع من الفواتير السابقة | صغير | يُفضَّل بعد 5 (التجربة نفسها) |
| P2 | 6: خصم بالقيمة | صغير، والمرحلة ب متوسطة | السؤال 8 |
| P3 | 4: مرتجع بلا فاتورة | كبير | 5 و7 و2 (تلمس الملفات نفسها) والأسئلة 6-7 |

### تقسيم إلى مهام متوازية (لا تتقاطع ملفاتها)

| المهمة | البنود | الملفات (حصرياً) | الاختبارات |
|---|---|---|---|
| **T-A** | 1 + تصفير أوضاع المرتجع والاستبدال عند الخروج | `lib/app_main_screen_navigation.dart`، `lib/presentation/shell/app_shell.dart`، `lib/domain/models/app_close_cart_gate.dart` (أو ملف جديد `pos_navigate_away_gate.dart`) | `test/unit/app_close_cart_gate_test.dart`، `test/unit/screen_tabs_test.dart`، `test/widget/app_shell_close_action_test.dart`، `test/widget/picpos_shell_test.dart` |
| **T-B** | 2 | `lib/presentation/pos_picpos/screens/picpos_pos_checkout.dart`، `lib/domain/models/quick_sale_policy.dart`، (عند الحاجة) `lib/services/generators/thermal_receipt_generator.dart` | `test/widget/picpos_pos_keys_test.dart`، `test/unit/quick_sale_policy_effect_test.dart`، `test/unit/quick_sale_policy_test.dart` |
| **T-C** | 3 | `lib/presentation/pos_picpos/widgets/picpos_payment_panel.dart` | `test/widget/pos_picpos/picpos_payment_panel_layout_test.dart` |
| **T-D** | 5 (الترويسة والشاشة) | `lib/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart`، `lib/presentation/pos_picpos/screens/picpos_pos_screen.dart` | `test/widget/picpos_return_mode_banner_test.dart`، `test/widget/picpos_return_mode_test.dart` |
| **T-E** | 7 + `_reopenQuickReturnEditor` من البند 5 | `lib/presentation/pos_picpos/screens/picpos_pos_return.dart`، `lib/presentation/pos_picpos/screens/picpos_pos_invoice_actions.dart`، `lib/presentation/pos/widgets/pos_previous_invoices_dialog.dart` | ملف widget جديد لديالوج الفواتير، `test/unit/picpos_quick_return_lines_test.dart` |
| **T-F** | 6 | `lib/presentation/pos_picpos/screens/picpos_pos_cart_edit.dart` (المرحلة أ). في المرحلة ب أيضاً: `cart_controller.dart` و`calculate_invoice_totals_usecase.dart` | `test/widget/quick_sale_discount_doors_test.dart` |
| **T-G** | 4 | بعد دمج T-B وT-D وT-E: `cart_controller.dart`، `picpos_pos_product_entry.dart`، `picpos_pos_barcode_scan.dart`، `picpos_pos_decisions.dart`، `picpos_pos_checkout.dart`، `permission_codes.dart`، `permission_enforcement_registry.dart` | انظر البند 4 |

**نقاط تماس بين المهام:**
- T-D تستدعي من `picpos_pos_screen.dart` دالة `_reopenQuickReturnEditor` التي تعرّفها T-E في `picpos_pos_return.dart`. وكلاهما `part` للمكتبة نفسها، فيُتفق مسبقاً على التوقيع `void _reopenQuickReturnEditor()`، أو تبدأ T-D بتمرير `onCancel` فقط وتُضاف `onEdit` بعد دمج T-E.
- T-C وT-E: زر «مرتجع» في ديالوج الفواتير يحترم `showReturnButtonInPOSProvider` من `pos_previous_invoices_dialog.dart` أو من المستدعي، داخل ملفات T-E دون تقاطع.
- T-F المرحلة ب تلمس `cart_controller.dart`، وT-G تلمسه أيضاً، فلا تُنفَّذان بالتوازي.
- T-G تُنفَّذ أخيراً ووحدها، فهي تلمس `picpos_pos_checkout.dart` (ملف T-B) وملفات الإدخال.

**التحقق بعد كل مهمة:** `flutter analyze` على الملفات المعدَّلة، ثم `flutter test` على الاختبارات المذكورة، ثم الاختبارات البنيوية العامة `test/structural/` (خصوصاً `picpos_permission_parity_test.dart` و`quick_sale_policy_read_style_guard_test.dart` و`presentation_db_import_guard`).

---

## حدود هذه الدراسة
- لم يُشغَّل التطبيق ولا الاختبارات.
- لم يُتحقَّق من: وصول `printInvoice` إلى `ThermalReceiptGenerator` (ركلة مزدوجة)، وقيمة `finalDiscount` في `sales_transaction_orchestrator.dart:1171`، وما إذا كان الـProviderScope يُعاد إنشاؤه بعد الخروج، ووجود اختصار للمرتجع أو الاستبدال في `picpos_pos_shortcuts.dart`، ومحتوى `exchange_mode_removed_test.dart`.
- المراجع جُمعت بقراءة موجّهة، والسطور قابلة للانزياح إذا عُدِّلت الملفات بعد 2026-10-30.

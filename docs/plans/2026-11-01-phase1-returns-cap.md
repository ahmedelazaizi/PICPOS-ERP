# المرحلة 1 — سقف المرتجعات التراكمي

## (أ) قائمة التحقق والأدلة
- [x] أُضيفت 10 سيناريوهات محلية للسقف التراكمي، القيم مع الخصم/الضريبة، الإلغاء، UOM، التزامن، المشتريات وAPI؛ شُغّلت الحزمة الحالية ومرّت (`00:17 +10: All tests passed!`). اختبار قرار الأسطر المكررة مرّ أيضاً (`00:00 +16: All tests passed!`). توجد حالة PG منفصلة لم تُشغّل بعد.
- [x] أُصلح تجميع حركات المبيعات والمشتريات النشطة، ونُقل فحص الحدّ داخل المعاملة مع قفل محلي و`FOR UPDATE` للمستودعات المحلية/PG، وأضيف تحقق API المشتريات داخل المعاملة.
- [ ] تزامن الشراء المحلي مرّ ضمن `+10`؛ تزامن PG عبر عزلين/اتصالين وتكافؤ PG لم يُتحققا بعد. اختبار تزامن API المبيعات السابق مرّ (`+4`).
- [x] تغطية API المشتريات شُغّلت ضمن `+10`؛ شاشتا الإرجاع والاستبدال عُدّلتا، ولم تُشغّل الواجهة. قفل API المبيعات المتاح أحادي العملية فقط.
- [x] روجعت مواضع التجميع ومفاتيح الحركات ونتائج البحث المرتبطة، ولم تُمسّ `NOINV` أو الترحيلات المحاسبية أو قيود `UNIQUE`.
- [x] أُجريت الاختبارات والتحليلات المحلية المطلوبة، ووُثّقت إخفاقات التدقيق والبنية غير المتعلقة بالمهمة في §د؛ يبقى تحقق PG بنداً مستقلاً.

## (ب) أوامر وخرجها الحرفي
- `& 'D:\qa\luna_tools.ps1'` — محاولةُ تشغيلٍ أولى أظهرت `ParserError` عند السطر 14؛ dot-source الموثّق نجح لاحقاً. تشغيلُ `Invoke-FlutterTest` انتهى، لكن خرجَه اشتمل خطأً على مجموعةٍ واسعة من الملفات (`38:14 +0 -78: Some tests failed.`) رغم تمرير مسار ملف واحد؛ لا أعدّه نتيجةً صالحةً للحزمة المركّزة.
- التحليل الموجّه بعد حذف المالك الملف الجذري الشاذ:
  ```text
  flutter analyze lib/data/database/daos/inventory_dao.dart lib/data/database/daos/purchase_return_reads_dao.dart lib/data/database/daos/sales_actions_dao.dart lib/data/repositories/exchange_repository_impl.dart lib/data/repositories/purchases_repository_impl.dart lib/data/repositories/returns_repository_impl.dart lib/presentation/pos_picpos/screens/picpos_pos_decisions.dart lib/presentation/pos_picpos/screens/picpos_pos_exchange.dart lib/presentation/pos_picpos/screens/picpos_pos_return.dart lib/presentation/providers/sales_return_provider.dart lib/services/api/api_purchase_handler.dart test/phase1/returns_cap/cumulative_returns_cap_test.dart test/phase1/returns_cap/returns_cap_pg_test.dart test/unit/picpos_quick_return_lines_test.dart
  No issues found! (ran in 52.6s)
  ```
- الاستدعاء الموضعي بالوسيط المسمّى لأن الصيغة الموضعية أعادت `Cannot process command because of one or more missing mandatory parameters: Paths.`:
  ```text
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths test/unit/picpos_quick_return_lines_test.dart
  00:00 +16: All tests passed!
  ```
  ```text
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths test/phase1/returns_cap/cumulative_returns_cap_test.dart
  00:18 +10: All tests passed!
  ```
- تشغيل الملف الكامل للمبيعات: `. 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart -RunSkipped` أعاد في آخر تشغيل `00:37 +18 -6: Some tests failed.`؛ الإخفاقات الستة كانت `NOINV-01`, `NOINV-04`, `VOID-02`, `RCV-02`, `RCV-03`, `RCV-04` (قيمها الظاهرة بالخرج: رصيد مخزون 2 بدلاً من ≤0؛ خزنة -50 متوقعة/0 فعلية؛ ثم ثلاثة إخفاقات تحصيل). لم تكن `RET-02/03/08` من الإخفاقات.
- الحالات المطلوبة منفردة عبر المساعد (لكلّ منها `00:02 +1: All tests passed!`):
  ```text
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths @('test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart','--plain-name','RET-02') -RunSkipped
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths @('test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart','--plain-name','RET-03') -RunSkipped
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths @('test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart','--plain-name','RET-08') -RunSkipped
  ```
  خرج RET-02 رفض المرتجع الثاني بعد 5، وRET-03 أوقف الثالث عند المتاح 1، وRET-08 قبل واحداً فقط من سباق 2+2 على 3.
- تشغيل الملف الكامل للمشتريات: `. 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths test/audit_repro/sales_purchases/d_purchases_cost_audit_test.dart -RunSkipped` أعاد في آخر تشغيل `00:21 +8 -5: Some tests failed.`؛ الإخفاقات كانت `PUR-04`, `PUR-05`, `PUR-07`, `PUR-08`, `PUR-09b`. `PUR-06b` لم يظهر بين الإخفاقات في هذا التشغيل.
- محاولة `PUR-06b` المنفردة الأولى لم تصل إلى الاختبار بسبب أخطاء تجميع متزامنة في أجزاء أخرى (`manufacturing_dao.dart:1105` و`sales_transaction_orchestrator.dart:415`؛ لم أعدّلها). بعد أن عادت الملفات إلى حالة قابلة للتحليل، أُعيدت عبر المساعد ومرّت:
  ```text
  . 'D:\qa\luna_tools.ps1'; Invoke-FlutterTest -Paths @('test/audit_repro/sales_purchases/d_purchases_cost_audit_test.dart','--plain-name','PUR-06b') -RunSkipped
  00:03 +1: All tests passed!
  [AUDIT-PUR] PUR-06b first=360.0 second=EXC: Exception: كمية الإرجاع (6.0) تتجاوز الكمية المتاحة للإرجاع (4.0) للصنف رقم 1 stock=24.0 ...
  ```
- دليل الإحالة المنفصلة لـ`PUR-09b`: الاختبار يتوقع أن إلغاء فاتورة بعد مرتجع 4 لا يخرج إلا الصافي 6؛ `purchase_void_dao.dart:40-52` يخصم `item.quantity` كاملاً، و`getPurchaseReturnedQtyByProduct` لا يُستدعى من مسار الإلغاء. لم أغيّر DAO الإلغاء ولا دوال الترحيل المحاسبي؛ تُحال إخفاقات الفوترة/التسويات المتبقية لمهمة مستقلة.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/audit_repro/sales_purchases/c_returns_void_edit_audit_test.dart --run-skipped --plain-name 'RET-03'` — فشل قبل الإصلاح:
  ```text
  [AUDIT-RET] RET-03 results=[true, true, true] status=partial_return stock=51.0 safe=-100.0
  Expected: not <true>
  Actual: <true>
  Some tests failed.
  ```
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/audit_repro/sales_purchases/d_purchases_cost_audit_test.dart --run-skipped --plain-name 'PUR-06b'` — فشل قبل الإصلاح:
  ```text
  [AUDIT-PUR] PUR-06b first=360.0 second=360.0 stock=18.0 wac=60.0 value=1080.0 whBal=[{q: 18.0, c: 60.0}] gl1136=1080.0 gl2111=-1080.0 gl5211=0.0 supplier=1080.0 safe=0.0
  Expected: true
  Actual: <false>
  Some tests failed.
  ```
- أول تشغيل لحزمة الانحدار الجديدة مرّ بـ`All tests passed!` (6 اختبارات). بعد إضافة فحص API للمشتريات، تشغيل الحزمة الموسعة واجه تصادم أصول Flutter:
  ```text
  Invalid argument(s): Couldn't resolve native function 'sqlite3_initialize' ...
  PathExistsException: Cannot copy file to 'D:\\PICPOS-ERP\\build\\native_assets\\windows\\sqlite3.dll' ... errno = 183
  ```
  فحصت الحالة: الملف كان موجوداً ثم ظهر تصادم النسخ؛ لم أحذف DLL ولم أقتل أي عملية. محاولة PG الأولى بلا `--tags pg` كانت `All tests skipped.`؛ صُحح الاستدعاء لاحقاً، لكن تشغيل PG الحالي متوقف بسبب استثناء Windows للمنفذ `56020` (التفصيل في §د).


## نقطة تحقق
- سبب العطب السابق: `getAlreadyReturnedQty` كان يفلتر `reference_type='sales_invoice'` مع أن المرتجع الاعتيادي يكتب `reference_type='sales_return'`؛ نُقل الفحص الآن إلى داخل معاملة الإرجاع.
- حُدد سبب المشتريات من التشغيل: كل عملية تقارن بـ`originalQuantity` فقط ولا تجمع المرتجعات السابقة.
- عُدِّلت حساباتُ عرض الكمية في مزوّد المبيعات وشاشتي الإرجاع/الاستبدال لتحويل وحدة الأساس إلى وحدة البيع وتوزيع السابق على الأسطر. لم تُشغَّل الواجهة، امتثالاً للتوجيه.

## (ج) الملفات المعدلة وفروق أسطري
- `lib/data/database/daos/sales_actions_dao.dart` و`lib/data/database/daos/sales_return_cap_dao.dart`: صافي حركات الإرجاع النشطة `sales_return`/`sales_invoice` وطرح `return_cancel` بوحدة الأساس؛ نُقلت استعلامات العرض من `inventory_dao.dart` إلى part مستقل للالتزام بسقف الحجم.
- `lib/data/database/daos/purchase_return_reads_dao.dart`: صافي `purchase_return` و`purchase_return_reverse` للحركات النشطة.
- `lib/data/repositories/returns_repository_impl.dart` و`lib/data/repositories/returns_repository_cap.dart`: تجميع الطلبات حسب المنتج وتحويل وحدات البيع إلى الأساس، والفحص داخل المعاملة مع قفل محلي وصفّ PG.
- `lib/data/repositories/purchases_repository_impl.dart` و`lib/data/repositories/purchases_repository_return_cap.dart`، و`lib/services/api/api_purchase_handler.dart` مع `lib/services/api/api_purchase_return_cap.dart`: حدّ تراكمي للمشتريات داخل المعاملة، مع تسوية العكس وقفل الصف في PostgreSQL.
- `lib/services/api/api_purchase_handler_helpers.dart`: نقلٌ بلا تغيير سلوكي لدالة `_resolveWarehouseId` لتبقى ملفات الواجهات الكبيرة تحت حدّ الحجم.
- `lib/presentation/providers/sales_return_provider.dart`، وشاشتا `lib/presentation/pos_picpos/screens/picpos_pos_return.dart` و`lib/presentation/pos_picpos/screens/picpos_pos_exchange.dart`: تحويل المجاميع الأساسية إلى وحدات البيع عبر `distributeReturnedBaseQtyToSaleLines` المشترك وتوزيع السابق على أسطر المنتج بالتتابع؛ `lib/presentation/pos_picpos/screens/picpos_pos_decisions.dart` لا يرفض ختم المرتجع الكامل لمجرد تكرر المنتج.
- `lib/data/repositories/exchange_repository_impl.dart`: تحديث تعليق قديم عن التجميع.
- أضيفت `test/phase1/returns_cap/cumulative_returns_cap_test.dart` و`test/phase1/returns_cap/returns_cap_pg_test.dart`، ووُسّع `test/unit/picpos_quick_return_lines_test.dart` لحالة المنتج على سطرين.
- أُنشئ هذا التقرير. توجد لقطات أساس في `D:\qa\phase1_returns_cap_backup\`؛ تغييرات الشاشات التابعة لزميلٍ حُفظت كما كانت قبل تعديل أسطرها المنفصلة.

## تغيير منطق قائم: ختم «المرتجع الكامل» للمنتج المكرر
كان `computeIsFullReturn` يرفض الختم الكامل كلما تكرر `productId`، لأن `alreadyReturnedQty` كان مجموعاً بمفتاح المنتج ويُنسَب إلى كل سطر على حدة:

```dart
bool computeIsFullReturn(PosReturnMode mode) {
  final linesPerProduct = <int, int>{};
  for (final line in mode.linesByItemId.values) {
    linesPerProduct[line.productId] =
        (linesPerProduct[line.productId] ?? 0) + 1;
  }
  if (linesPerProduct.values.any((count) => count > 1)) return false;

  return mode.linesByItemId.values.every((line) {
    final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
    return (requested - line.availableQty).abs() < 0.001;
  });
}
```

أصبح فحص الختم الحالي يقارن المطلوب بالمتاح الموزّع لكل سطر:

```dart
bool computeIsFullReturn(PosReturnMode mode) =>
    mode.linesByItemId.values.every((line) {
      final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
      return (requested - line.availableQty).abs() < 0.001;
    });
```

لم يعد الرفض بحسب تكرار المنتج لازماً لأن `distributeReturnedBaseQtyToSaleLines` يوزع المجاميع المخزّنة بوحدة الأساس بترتيب أسطر الفاتورة، ثم يحول نصيب كل سطر إلى وحدة البيع. في حالة 5+4 ومرتجع سابق 3، يصبح السابق لكل سطر 3 و0، والمتاح 2+4=6؛ اختبار الانحدار الجديد يتحقق من أن «تحديد الكل» (6) يختم كاملاً، بينما طلب 3 لا يختم.

**التراجع الموضعي:** أعد شرط عدّ `linesPerProduct` أعلاه إلى `computeIsFullReturn`، واستبدل استدعاءَي `distributeReturnedBaseQtyToSaleLines` بحلقي التوزيع السابقَتين داخل الشاشتين، ثم احذف الدالة والاختبار الجديد. هذا يعيد السلوك المحافظ السابق دون أوامر Git مدمّرة أو استعادة ملفات كاملة.

## (د) نتائج التحقق وما تعذّر
- لم يُشغّل سيناريو PG بعد: إنشاء `postgres:18-alpine` على `127.0.0.1:56020` فشل لأن Windows يستثني TCP `56001–56100` (`netsh interface ipv4 show excludedportrange protocol=tcp`)؛ Docker أعاد `ports are not available ... access permissions`. أُزيلت الحاوية الفاشلة. المنفذ `56120` متاح، لكن لم أبدّل المنفذ المطلوب دون تفويض؛ يلزم تحرير `56020` أو تفويض منفذ بديل قبل `Invoke-FlutterTest -PgDsn ...`.
- تشغيل `flutter analyze` الكامل السابق انتهى بـ`[exit code: 1]` و`35 issues found` بسبب ملف اختبار غير متعقّب معطوب باسم `screens_theme_contrast_round5c_test.dart` (أسطر 3 و19–20)؛ مساره الجذري الذي ظهر في ذلك التشغيل لم يعد موجوداً، والبحث الحالي يجد نسخة تحت `test/widget/`. التحليل الموجّه الأول للملفات الأربعة عشر مرّ (`52.6s`)، وملف PG منفرداً مرّ بعد تهذيبه (`14.7s`)؛ التحليل الأحدث بعد تقسيم الأجزاء شمل 20 هدفاً ومرّ (التفصيل أدناه).
- حدود التزامن: `ReturnInvoiceLock` في حارس API يحمي الطلبات المتزامنة للفواتير نفسها داخل عملية/عزل خادم واحد، ولا ينسّق بين عمليات خوادم متعددة. لا أضيف `FOR UPDATE` للحارس: مسار المستودع المحلي يملك فحصاً داخل معاملة وقفل صف PostgreSQL لحماية الاتصالات المستقلة؛ اختبار العزلين أُعدّ لإثبات ذلك، لكن لم يُشغّل بسبب المنفذ المحجوز.

### نتائج التحقق بعد تقسيم ملفات الحدّ
- التحليل الموجّه للملفات المعدلة وأجزاء `part` واختبارات الانحدار: `flutter analyze` على 20 هدفاً انتهى بـ`No issues found! (ran in 62.2s)`؛ يشمل `database.dart`، مستودعي الإرجاع وأجزاءهما، معالِج API وأجزاءه، شاشات POS، واختباري Phase 1.
- اختبارات Phase 1 المحلية والواجهات: `cumulative_returns_cap_test.dart` ‏`00:17 +10: All tests passed!`؛ شدّدت تأكيد رفض السباق على رسالة حدّ الكمية وأضفت مقارنة المخزون/المجموع قبل وبعد رفض مرتجع الشراء. `picpos_quick_return_lines_test.dart` مرّ `00:00 +16: All tests passed!`. اختبارات `RET-02`, `RET-03`, `RET-08` شُغّلت منفردةً عبر المساعد، ونجح كل منها `+1`. شُغّل `PUR-06b` منفرداً عبر المساعد ونجح `+1`؛ سجلّه يثبت قبول أول مرتجع 6 ورفض الثاني 6 عند بقاء 4.
- اجتازت الاختبارات المستقلة ذات الصلة: `return_quantity_validation_test.dart` ‏`+11`، `returns_accuracy_b9_test.dart` ‏`+2` بعد إعادة المحاولة، `purchase_return_over_return_guard_test.dart` ‏`+6`، `return_refund_hits_shift_drawer_test.dart` ‏`+8`، `spec_151_return_key_test.dart` ‏`+4`، `sales_returns_history_parity_test.dart` ‏`+5`، `pos_return_refund_total_matches_spent_test.dart` ‏`+2`، `return_line_prorates_discount_test.dart` ‏`+8`، `returnable_line_test.dart` ‏`+8`، `purchase_return_settlement_test.dart` ‏`+7`، `no_invoice_return_unit_test.dart` ‏`+29`، `standalone_returns_visibility_test.dart` ‏`+9`، `sales_return_refund_split_test.dart` ‏`+20`، `exchange_atomicity_test.dart` ‏`+13`، و`cart_return_lines_controller_test.dart` ‏`+12`.
- اجتازت اختبارات التكامل منفردةً: `api_return_concurrency_test.dart` ‏`+4`، `api_return_exchange_price_guard_test.dart` ‏`+9`، `picpos_sales_return_cancel_stock_test.dart` ‏`+6`، `purchase_return_edit_test.dart` ‏`+4`، `return_drafts_lifecycle_j2_test.dart` ‏`+8`، `sales_returns_history_e2e_test.dart` ‏`+2`، `sales_return_wac_gl_drift_test.dart` ‏`+2`، `sales_return_shift_and_branch_safe_test.dart` ‏`+25`، `sales_revenue_account_c2_test.dart` ‏`+8`، `tax_exempt_item_b3_test.dart` ‏`+9`، `no_invoice_return_persist_test.dart` ‏`+9`، `purchase_return_cash_refund_owner_scenario_test.dart` ‏`+2`، و`return_e2e_test.dart` ‏`+3` عند تشغيله منفرداً مباشرةً.
- اجتازت السيناريوهات `sc_c_sales_return_void_test.dart` ‏`+16`، `sc_c2_cancel_sales_return_test.dart` ‏`+1`، `sc_c3_return_link_by_gid_test.dart` ‏`+1`، `sc_c4_voided_after_return_report_test.dart` ‏`+1`، `sc_d_purchase_cycle_test.dart` ‏`+4`، و`sc_k_trial_balance_test.dart` ‏`+10`. تشغيلٌ مجمّع لثلاثة ملفات API/إلغاء أظهر إخفاقات في ملف الإلغاء؛ إعادة تشغيل الملفات كلٌّ على حدة مرّت (`+4`, `+9`, `+6`). كما فشل تشغيل مساعد أول لملف `return_e2e_test.dart` عند فتح قاعدة Drift، ثم مرّ الأمر المباشر المنفرد `+3`.
- حزم التدقيق الكامل ليست خضراء: `c_returns_void_edit_audit_test.dart -RunSkipped` انتهى `+18 -6` بسبب `NOINV-01/04` (المخزون الفعلي 2 والمتوقع ≤0)، `VOID-02` (الرصيد المتوقع -50 والفعلي 0)، و`RCV-02/03/04` (قبول تحصيل زائد/سالب وقيمة مدفوعة 20 بدلاً من 150). `d_purchases_cost_audit_test.dart -RunSkipped` انتهى `+8 -5`: `PUR-04` WAC 14 بدلاً من 12، `PUR-05` ذمة -180، `PUR-07` حساب المورد 0 بدلاً من 100، `PUR-08` قيد واحد بدلاً من 3، و`PUR-09b` إلغاء يحرك كمية المرتجع السابقة أيضاً. هذه مسارات إلغاء/تحصيل/تكلفة/قيود أخرى ولم أعدلها؛ `PUR-06b` الخاص بسقف الكمية ينجح منفرداً.
- حواجز البنية: `dark_mode_guard_test.dart` مرّ `+3`. `file_size_ratchet_test.dart` بعد نقل منطق الحدّ إلى أجزاء مستقلة ما زال يفشل فقط في ملفي واجهة منتجات غير متعلقين بهذه المهمة: `product_edit_dialog.dart` ‏72968 مقابل 72640، و`add_product_dialog.dart` ‏92380 مقابل 92199 بايت. `i18n_coverage_test.dart` يفشل لأن المفتاح `لا يمكن أن يكون السعر سالباً` غير موجود في `assets/i18n/en.json`؛ مصدر المفتاح في `quick_add_product_dialog.dart:60` و`product_form_helpers.dart:47`، ولم أعدل هذه الملفات.

## (هـ) المخاطر والتراجع
- لا تعديل لترحيل القيود ولا لقيد UNIQUE. التراجع يكون بإعادة أسطر الملفات المعدلة يدوياً بالاعتماد على النسخ الاحتياطية، دون أوامر استعادة جماعية أو مسح تغييرات الغير.

- [2026-11-01 10:34] حُدّث التحقق المحلي ليقارن الكميات بوحدات الأساس، وتُسوّى كميات المرتجع السابقة على أسطر واجهات المبيعات حسب معامل الوحدة؛ الاختبارات النهائية معلّقة على قفل SQLite من عمليات أخرى.
- [2026-11-01 11:12] أُضيف اختبار UOM وتزامن شراء، وأُزيل رفض المرتجع الكامل عند الأسطر المكررة بعد توزيع الرصيد. خرج اختبار المساعد لم يعزل الملف المستهدف وذكر 78 إخفاقاً؛ لا تُعتمد نتيجة للحزمة. التحليل الكامل كشف ملفاً جذرياً غير متعقّب غير صالح؛ لم أعدّل ملفات العامل الآخر ولم أوقف اختباره الجاري.
- Checkpoint (متابعة المراجعة): أُضيف `distributeReturnedBaseQtyToSaleLines` كدالة مشتركة بين شاشتي الإرجاع والاستبدال، واختبار مستقل يعيد حالة 5+4 مع سابق 3 ويثبت 6 كاملةً و3 جزئيةً. التحليل الموجّه للملفات المعدلة مرّ بـ`No issues found! (ran in 52.6s)`.
- Checkpoint (PG): فشل ربط Docker بالمنفذ المطلوب بسبب نطاق استثناء Windows `56001–56100`، وحُذفت الحاوية الفاشلة. لم أستبدل المنفذ؛ `56120` متاح لكنه يحتاج تفويضاً.
- Checkpoint (التحقق النهائي): أُخرجت منطقُ السقف من الملفات التي تجاوزت ratchet إلى أجزاء مستقلة؛ التحليل الموجّه واختبارات المرتجع المحلية/التكاملية المختارة مرّت. بقي PG وحده غير مشغّل، بينما إخفاقات audit/ratchet/i18n غير المرتبطة موثقة أعلاه.

CHECKLIST: 5/6
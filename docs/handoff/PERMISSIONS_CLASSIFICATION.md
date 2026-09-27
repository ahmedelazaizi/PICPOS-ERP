# تصنيفُ الـ٢٢١ كوداً — كودٌ · صنف · موضعُ الإنفاذ · الدليل

**مقيسٌ 2026-08-13 بعد كوميت `a52325f9`.** بند ٥ من معيار Go.

## الأصناف

| الرمز | المعنى |
|---|---|
| **أ** | **منعُ فعل** — الفعلُ لا يقع بلا صلاحية، والفحصُ **قبل** التنفيذ لا بعده |
| **ب** | **إخفاءُ عرض** — العنصرُ لا يُعرض أصلاً، أو يُعرض مموّهاً |
| **ج** | **لا ميزة** — لا زرَّ يُلَفّ على مسار PicPos |
| **د** | **ثقب** — الفعلُ يقع بلا فحص، أو الفحصُ بعد الطفرة، أو الحارسُ في ملفٍّ لا تبلغه PicPos |

## الإحصاء

| الصنف | قبل إصلاحات اليوم | **الآن** |
|---|---|---|
| أ — منعُ فعل | ٤٥ | **٥٢** |
| ب — إخفاءُ عرض | ٣٩ | ٣٩ |
| ج — لا ميزة | ٧٦ | ٧٦ |
| د — ثقب | ٦١ | **٥٤** |
| المجموع | ٢٢١ | ٢٢١ |

سبعةٌ انتقلت من **د** إلى **أ**: `pos_discount` · `pos_hold_order` ·
`pos_expense` · `pos_delivery` · `pos_previous_invoices` · `users_manage` ·
`audit_view`.

> ### ⚠️ حدُّ الثقة في هذا الجدول
>
> الصفوفُ التي **قِستُها بنفسي** من الكود: كلُّ نطاق البيع (`pos_*`)، و
> `users_manage`/`roles_manage`/`audit_view`، وبنيةُ `PermissionGuard`، ورايةُ
> الـAPI، والـ١٥ المسجَّلةَ في `picposParityGaps`.
>
> وبقيّةُ الصفوف (‏تقاريرُ · محاسبةٌ · تصنيعٌ · أصولٌ · ولاءٌ · توزيعٌ …) من
> تدقيقٍ آليٍّ **لم أتحقّق من كلّ صفٍّ فيها يدوياً**. المجموعُ يجمع، وهذا لا
> يُثبت صحّةَ كلّ سطر. عاملها دليلاً للبحث لا شهادةَ اعتماد.

---

## نقطةُ البيع (٥٧)

| الكود | صنف | موضعُ الإنفاذ | الدليل |
|---|---|---|---|
| `pos_access` | ب | `data/providers/auth_providers.dart:790` | بوّابةُ تنقّلٍ تفشل مقفولة |
| `pos_discount` | **أ** ✅ | `picpos_items_table.dart` · `picpos_pos_operations.dart` ×٢ | **كان د** — ثلاثةُ أبوابٍ حُرست 2026-08-13 |
| `pos_return` | ج | — | لا زرَّ مرتجعٍ في شاشة بيع PicPos؛ مسجَّلٌ بشاهدِ غياب |
| `pos_exchange` | ج | — | مسجَّلٌ بشاهدِ غياب |
| `pos_hold_order` | **أ** ✅ | `picpos_pos_operations.dart` `_holdOrder` | **كان د** — بلا فحصٍ إطلاقاً |
| `pos_restore_held` | أ | `pos/widgets/held_orders_dialog.dart:254` | الحوارُ مستوردٌ في `picpos_pos_screen.dart:33` |
| `pos_delete_held` | ب | `pos/widgets/held_orders_dialog.dart:269` | نفسُ الحوار |
| `pos_closing_view_details` | ب | `picpos_cashier_closing_dialog.dart:133` | يموّه الإجماليات |
| `pos_work_order` | ب | `pos/widgets/held_orders_dialog.dart:22` | زرُّ أمر الشغل محروس |
| `pos_open_drawer` | أ | `picpos_cart_permissions.dart` ← `_openDrawer` | قبل `CashDrawerService().openDrawer` |
| `pos_save` | أ | `picpos_pos_operations.dart:1012` | قبل `processPayment` |
| `pos_print` | **د** | جزئيّ: `picpos_last_invoice_dialog.dart:125` | بابٌ ثانٍ بلا فحص: `onReprint` ← `pos_previous_invoices_dialog.dart:376,501` |
| `pos_price_edit` | أ | `picpos_pos_operations.dart` · `picpos_items_table.dart` | البابان معاً + تعطيلٌ بصريّ |
| `pos_tax_toggle` | أ | `picpos_payment_panel.dart:335` | قبل `toggleTax` |
| `pos_expense` | **أ** ✅ | `picpos_pos_operations.dart` `_showExpenses` | **كان د** — سندُ صرفٍ نقديٍّ بلا فحص |
| `pos_expense_type_select` | ب | `pos/widgets/pos_expense_dialog.dart:110` | الحقلُ معطَّل |
| `pos_expense_description` | ب | `pos/widgets/pos_expense_dialog.dart:114` | الحقلُ معطَّل |
| `pos_expense_delete` | ب | `pos_previous_expenses_dialog.dart:52,179` | زرُّ الحذف مخفيّ |
| `pos_deleted_items` | ج | — | مسجَّلٌ بشاهدِ غياب |
| `pos_previous_invoices` | **أ** ✅ | `picpos_pos_operations.dart` ×٢ | **كان د** — البابُ الثاني `_showLastInvoice` (الزرُّ الكبير · F3 · الترويسة) |
| `pos_daily_closing` | ج | — | `nonToggleable`: يغطّيه `pos_shift_close` |
| `view_daily_closing_details` | أ | `treasury/widgets/daily_closing_dialog.dart:138,276` | يبلغه `treasury_picpos_screen.dart:309` |
| `pos_edit_invoice` | أ | `picpos_pos_operations.dart:1519` | قبل `PosEditInvoiceDialog.show` |
| `pos_cancel_invoice` | ج | — | `nonToggleable`: يغطّيه `void_paid_invoice` |
| `pos_delivery` | **أ** ✅ | `picpos_payment_panel.dart` شريحةُ «توصيل» | **كان د** — حسمه المالك 2026-08-13 |
| `pos_payment_methods` | ج | — | `nonToggleable` |
| `pos_split_payment` | ج | — | `nonToggleable` |
| `pos_customer_add` | أ | `pos/widgets/customer_selector_v2.dart:148` | بلوغٌ متعدٍّ عبر `pos_customer_selection_dialog` |
| `pos_customer_select` | أ | `picpos_pos_operations.dart:1427` | قبل الحوار |
| `pos_view_cost` | ج | — | `nonToggleable`، الميزةُ غيرُ مبنيّة |
| `pos_view_profit` | ج | — | `nonToggleable`، الميزةُ غيرُ مبنيّة |
| `pos_note_add` | أ | `pos/widgets/modifier_selection_dialog.dart:109` | عبر `picpos_items_table.dart:331` |
| `pos_quantity_edit` | أ | `picpos_pos_operations.dart` · `picpos_items_table.dart` | البابان + تعطيلٌ بصريّ |
| `pos_remove_item` | أ | `picpos_pos_operations.dart:757` | قِمعٌ واحد (زرُّ الصفّ + F8) |
| `pos_weight_dialog` | أ | `picpos_pos_operations.dart:355` | قبل `showWeightInput` |
| `pos_shift_open` | **د** | `services/api/api_data_handler.dart:457` فقط | الفتحُ المحليُّ `picpos_pos_operations.dart:217` بلا فحص |
| `pos_shift_close` | أ | `picpos_top_bar.dart:99` · `shift_close_picpos_screen.dart:128` | المدخلان معاً |
| `pos_clear_cart` | أ | `picpos_pos_operations.dart:1408` | يغطّي ESC والزرّ |
| `pos_search` | **د** | `pos_product_selection_panel.dart:36` | `AbsorbPointer` لا يمنع التركيزَ البرمجيّ ولا الماسح |
| `pos_quick_pay` | ج | — | لا زرَّ دفعٍ سريعٍ في PicPos |
| `pos_item_plus` | ج | (`cart_item_tile.dart:381` قديم) | لا مِسطرةَ ‎+/−‎ في جدول PicPos؛ شاهدُ غيابٍ فعّال |
| `pos_item_minus` | ج | (`cart_item_tile.dart:302` قديم) | نفسُه |
| `pos_payment_cash` | أ | `picpos_pos_operations.dart:1239` | `_allowedPaymentMethods` يرشّح قبل الكتابة |
| `pos_payment_card` | أ | `:1240` | نفسُه |
| `pos_payment_credit` | أ | `:1242` | نفسُه |
| `pos_payment_transfer` | أ | `:1241` | نفسُه |
| `pos_payment_multiple` | أ | `:1243` | نفسُه |
| `pos_table_select` | ج | — | لا طاولاتٍ في PicPos؛ شاهدُ غيابٍ فعّال |
| `pos_grid_toggle` | ب | `pos/widgets/product_grid.dart:29` | يُرسَم عبر `PosProductSelectionPanel` |
| `pos_booking` | ج | — | شاهدُ غيابٍ فعّال |
| `pos_offers` | ج | (`pos_header.dart:232` قديم) | لا زرَّ عروض؛ تُطبَّق تلقائياً على مسار الباركود |
| `pos_table_bill` | ج | — | شاهدُ غيابٍ فعّال |
| `pos_keyboard` | ج | — | شاهدُ غيابٍ فعّال |
| `pos_notifications` | ج ⚠️ | — | **غيرُ محسوم** — يحتاج لقطةَ شاشة |
| `pos_low_stock_alert` | ج ⚠️ | — | **غيرُ محسوم** — يحتاج لقطةَ شاشة |
| `pos_barcode_scan` | **د** | — | مسارُ الماسح بلا فحصٍ إطلاقاً |
| `pos_add_product` | أ | `pos_product_selection_panel.dart:55` | ⚠️ موافقةُ المدير تفتح الشبكةَ لعمر الودجت لا لفعلٍ واحد |

## لوحةُ التحكم (٩)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `dashboard_access` | ب | `auth_providers.dart:789` |
| `dashboard_sales_today` | ب | `dashboard_picpos_screen.dart:441` |
| `dashboard_sales_total` | ج | `nonToggleable` — نفسُ الكارت بالفلتر |
| `dashboard_profit` | ب | `dashboard_picpos_screen.dart:511` |
| `dashboard_customers` | ج | `nonToggleable` |
| `dashboard_chart` | ب | `dashboard_picpos_screen.dart:190,195` |
| `dashboard_top_products` | ج | `nonToggleable` |
| `dashboard_alerts` | ب | `dashboard_picpos_screen.dart:127` |
| `dashboard_pending_orders` | ج | `nonToggleable`، غيرُ مبنيّة |

## المخزونُ والأصناف (٢٠)

| الكود | صنف | موضعُ الإنفاذ | ملاحظة |
|---|---|---|---|
| `inventory_view` | ب | `auth_providers.dart:796` | |
| `inventory_edit` | **د** | `api_data_handler.dart:713` فقط | `inventory_picpos_screen` بصفر فحوص |
| `inventory_transfer` | ب | `auth_providers.dart:808` | `_saveTransfer` نفسُه بلا فحص |
| `warehouses_manage` | **د** | API فقط | |
| `products_view` | **د** | ملفٌّ ميّت | `role_based_sidebar_service.dart` بصفر مستوردين |
| `products_add` | **د** | `products_picpos_screen.dart:171` | بابٌ ثانٍ: **F5** `:124` |
| `products_edit` | **د** | `api_product_handler.dart:435` فقط | صفُّ الجدول بلا فحص |
| `products_delete` | **د** | `api_product_handler.dart:604` فقط | شريطُ الإجراءات الجماعية بلا فحص |
| `products_import` | أ | `products_picpos_screen.dart:155` | |
| `products_export` | أ | `products_picpos_screen.dart:145` | |
| `products_barcode` | **د** | API فقط | |
| `products_image` | ب | `product_edit_dialog.dart:52` | |
| `products_units` | **د** | API فقط | ودفعُ `UnitsManagementScreen` بلا حراسة |
| `products_expiry` | ب | `product_edit_dialog.dart:39` | |
| `products_lock` | أ | `products_table.dart:202` | |
| `products_price_view` | ب | `products_table.dart:100` | عمودٌ مموّه |
| `products_cost_view` | ب | `products_table.dart:117,140` | |
| `products_stock_view` | ب | `products_table.dart:167` | |
| `products_scale_upload` | ج | `nonToggleable` | `scale_plu_picpos` بصفر فحوص |
| `price_lists_manage` | **د** | API فقط | |

## التصنيفات (٥)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `categories_view` | ج | `nonToggleable` |
| `categories_add` | **د** | API فقط — `categories_picpos_screen.dart:872` بلا فحص |
| `categories_edit` | **د** | API فقط |
| `categories_delete` | **د** | API فقط — `_runDelete` بلا فحص |
| `categories_scale_upload` | ج | `nonToggleable` |

## العملاءُ والموردون (٨)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `customers_view` | ب | `auth_providers.dart:795` |
| `customers_add` | **د** | `api_party_handler.dart:33` فقط |
| `customers_edit` | **د** | API فقط |
| `customers_delete` | **د** | API فقط |
| `suppliers_view` | ج | `nonToggleable` |
| `suppliers_add` | **د** | API فقط |
| `suppliers_edit` | **د** | API فقط |
| `suppliers_delete` | **د** | API فقط |

> `parties_picpos_screen` فيه استيرادُ وتصديرُ ملفّ الأطراف كاملاً بلا فحص.

## المشتريات (١١)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `purchases_view` | **د** | ملفٌّ ميّت + بذرة |
| `purchases_create` | **د** | بوّابةُ تنقّلٍ فقط — الزرُّ و**F5** بلا فحص |
| `purchases_edit` | ب | `purchases_picpos_screen.dart:126` |
| `purchases_delete` | **د** | API فقط |
| `purchases_print` | أ | `purchases_picpos_screen.dart:762` |
| `purchases_return_view` | ب | `auth_providers.dart:833` |
| `purchases_return_create` | **د** | API فقط |
| `purchases_return_edit` | أ | `purchase_returns_picpos_logic.dart:393` |
| `purchases_return_delete` | ج | `nonToggleable` |
| `purchases_return_print` | أ | `purchase_returns_picpos_logic.dart:368` |
| `purchase_orders_view` | **د** | بوّابةُ تنقّلٍ يتخطّاها دفعٌ مباشر |

## المبيعات (١٢)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `sales_view` | ب | `auth_providers.dart:805` |
| `sales_create` | **د** | API فقط — الزرُّ و**F5** بلا فحص |
| `sales_edit` | **د** | API فقط — `sales_invoices_table.dart:340` زرٌّ عارٍ |
| `sales_delete` | **د** | API فقط — `:353` زرٌّ عارٍ |
| `sales_print` | أ | `sales_invoices_table.dart:11` |
| `sales_amounts_view` | ب | `sales_invoices_table.dart:206,213,221` |
| `sales_return_view` | ب | `auth_providers.dart:832` |
| `sales_return_create` | **د** | API فقط |
| `sales_return_edit` | ج | `nonToggleable`، غيرُ مبنيّة |
| `sales_return_delete` | أ | `sales_returns_picpos_logic.dart:20` |
| `sales_return_print` | أ | `sales_returns_picpos_logic.dart:36` |
| `sales_orders_view` | **د** | بوّابةُ تنقّلٍ يتخطّاها دفعٌ مباشر |

## عروضٌ · توصيلٌ · طاولاتٌ · مطبخ (١٨)

كلُّها **ج** على مسار PicPos: شاشاتُها خارجَ تشكيلة `litePicpos`
(`core/navigation/screen_registry.dart:235`). حراستُها قائمةٌ للتشكيلات الأخرى.

`offers_view` · `offers_create` · `offers_edit` · `offers_delete` ·
`delivery_view` · `delivery_courier_manage` · `tables_view` · `tables_manage` ·
`tables_pos_access` · `tables_add_items` · `tables_checkout` ·
`tables_transfer` · `tables_cancel` · `tables_print_bill` · `kitchen_view` ·
`kitchen_manage`

واثنان **ب** لأن تايلَيهما في إعدادات PicPos فعلاً:
`delivery_manage` (`settings_picpos_screen.dart:876`) ·
`kds_settings` (`:902`)

## الخزينة (٩)

| الكود | صنف | موضعُ الإنفاذ | ملاحظة |
|---|---|---|---|
| `treasury_view` | ب | `auth_providers.dart:798` | |
| `treasury_manage` | **د** | API فقط | دفعُ `SafeManagementScreen` بلا حراسة |
| `treasury_receipts_create` | **د** | `treasury_metrics_panel.dart:100` | 🔴 بابٌ ثانٍ **على نفس الشاشة**: زرُّ «سند قبض» في الترويسة `treasury_picpos_screen.dart:134` بلا حراسة، وجارُه «سند صرف» محروس |
| `treasury_payments_create` | أ | `treasury_picpos_screen.dart:153` + `treasury_metrics_panel.dart:115` | البابان معاً |
| `treasury_transfer` | **د** | API فقط | |
| `treasury_balance_view` | ب | `dashboard_picpos_screen.dart:485` | |
| `treasury_transactions_view` | ج | `nonToggleable` | |
| `treasury_commission` | ب | `receipt_voucher_dialog.dart:581` | الحوارُ مستوردٌ في التوأم |
| `commercial_papers_manage` | **د** | API فقط | الشاشةُ خارج lite |

## الموارد البشرية (٤)

`hr_view` ج · `hr_manage` **ب** (تايلُ «عطلات العمل» في إعدادات PicPos) ·
`hr_advance_record` ج · `hr_payroll_process` ج

## التقارير (١٥)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `reports_view` | ب | `auth_providers.dart:799` |
| `reports_export` | أ | `screens/reports/report_export_guard.dart:36` — دالّةٌ مشتركةٌ لـ١٤ شاشة |
| `reports_sales` | ب | `reports_picpos_screen.dart:212,219,479,632` |
| `reports_treasury` | ب | `reports_picpos_screen.dart:472` |
| `reports_suppliers` | ب | `reports_picpos_screen.dart:443,451` |
| `reports_taxes` | ب | `reports_picpos_screen.dart:561,568` |
| `reports_category_profit` | ب | `reports_picpos_screen.dart:247,254` |
| `reports_delivery_recon` | أ | `delivery_report_screen.dart:444` |
| `reports_order_type` | ب | `sales_by_classification_report.dart:397` |
| `reports_purchases` · `reports_inventory` · `reports_customers` · `reports_profit` · `reports_products` · `reports_shifts` | ج | `nonToggleable` |

## الإعداداتُ والمستخدمونَ والنظام (١٧)

| الكود | صنف | موضعُ الإنفاذ | ملاحظة |
|---|---|---|---|
| `settings_view` | ب | `auth_providers.dart:800` | |
| `settings_edit` | **د** | API فقط | لا بوّابةَ كتابةٍ محليّة |
| `settings_company` | أ | `settings_permission_tiles.dart:68` | |
| `settings_receipt` | ج | `nonToggleable` | |
| `settings_printer` | أ | `settings_picpos_screen.dart:539,556,578` | |
| `settings_scale` | ب | `auth_providers.dart:809` | |
| `settings_backup` | أ | `settings_picpos_screen.dart:778,853` | |
| `settings_restore` | ج | `nonToggleable` | |
| `settings_tax` | ب | `settings_permission_tiles.dart:192` | |
| `settings_currency` | أ | `general_settings_widgets_picpos.dart:140` | |
| `settings_pos_edit` | أ | `settings_picpos_screen.dart:632` | |
| `users_manage` | **أ** ✅ | `settings_picpos_screen.dart:655` · `reports_picpos_screen.dart` · **الشاشةُ نفسُها** | **كان د** — أُغلق البابُ الثاني وأُضيفت بوّابةٌ داخلية 2026-08-13 |
| `roles_manage` | أ | `settings_picpos_screen.dart:674,696` + `_updateUserRole` | ✅ أُضيف فحصُ إسناد الدور 2026-08-13 |
| `users_manage_cross_branch` | ب | `add_user_dialog.dart:303` · `edit_user_dialog.dart:119` | |
| `system_audit_log` | ج | `nonToggleable` | |
| `system_database` | أ | `settings_permission_tiles.dart:115` | |
| `system_license` | أ | `settings_permission_tiles.dart:164` | |
| `system_updates` | ج | `nonToggleable`، غيرُ مبنيّة | |

## التدقيق (٤)

| الكود | صنف | موضعُ الإنفاذ |
|---|---|---|
| `audit_view` | **أ** ✅ | `auth_providers.dart:806` + مدخلا التقارير | **كان د** — المدخلان كانا بلا `permission:` |
| `audit_shift_blind` · `audit_invoice_unlock` · `parties_credit_limit_bypass` | ج | `nonToggleable` |

## وحداتٌ خارجَ lite (١٧)

كلُّها **ج** — شاشاتُها ليست في تشكيلة `litePicpos`:
`loyalty_view` · `loyalty_manage` · `distribution_view` · `distribution_manage` ·
`einvoice_view` · `einvoice_submit` · `einvoice_cancel` · `accounting_manage` ·
`accounting_journal` · `manufacturing_view` · `manufacturing_manage` ·
`assets_view` · `assets_manage` · `assets_depreciation` · `analytics_view` ·
`branches_manage`

و`accounting_view` **د** — مرجعُه الوحيدُ ملفٌّ ميّت.

## أكوادُ الشريط الجانبيّ (٨) — كلُّها **د**

مرجعُها الوحيدُ `services/role_based_sidebar_service.dart` وهو **بصفر
مستوردين** في `lib/` و`test/` و`tool/`:

`quotes_view` · `returns_view` · `warehouses_view` · `stock_view` ·
`stock_audit` · `parties_view` · `settings_access` · `products_view`

> مفاتيحُ تُقلَّب ولا تفعل شيئاً. تحتاج قراراً: تُوصَل أو تُحذف.

و`modifiers_manage` **أ** — `settings_picpos_screen.dart:909` + CRUD في
`modifier_management_widget.dart`.

## العملياتُ الماليةُ الحرجة (٦)

| الكود | صنف | موضعُ الإنفاذ | ملاحظة |
|---|---|---|---|
| `delete_posted_journal` | ج | — | `nonToggleable`: أثرٌ داخليٌّ في عمليةٍ أخرى |
| `void_paid_invoice` | أ | `sales_actions_dao.dart:41` · `purchase_dao.dart:1854` | على مستوى الـDAO، يرمي استثناءً، **بلا تجاوزِ مدير** |
| `modify_locked_invoice` | أ | `sales_mutations_dao.dart:884` | نفسُه |
| `delete_fiscal_year` | ج | — | `nonToggleable`، غيرُ مبنيّة |
| `modify_closed_period` | أ | `fiscal_year_screen.dart:22` | الشاشةُ خارج lite |
| `override_credit_limit` | أ | `sales_mutations_dao.dart:105` وثلاثةُ مواضعَ أخرى | على مستوى الـDAO، بلا تجاوز |

> هذه الستّةُ وحدَها في `PermissionCodes.criticalFinancialOps`، ولا يتخطّاها
> تجاوزُ مدير النظام. وأربعتُها المنفَّذةُ على مستوى الـDAO — أقوى موضعِ إنفاذٍ
> في النظام كلِّه، لأنه لا يُتخطّى بشاشةٍ جديدة.

---

## الجذورُ الثلاثةُ للـ٥٤ ثقباً

ليست ٥٤ عطباً مستقلاًّ:

1. **~٢٧ إنفاذُها الوحيدُ في `lib/services/api/`** — خلف راية
   `server_per_user_perms_enabled` **افتراضُها `false`**
   (`api_user_context.dart:66`)، وعلى تنصيبةٍ مستقلّةٍ لا مسارَ HTTP أصلاً.
   **بالتصميم لا عطباً**: سبيك 060 يوثّق أن المرحلةَ الأولى وصّلت ٦ نقاطٍ
   والثانيةَ تكنس ٨٥. ⇒ قرارُ تشغيلٍ لا كود.
2. **٨ مرجعُها ملفٌّ ميّت** — `role_based_sidebar_service.dart` بصفر مستوردين.
3. **توائمُ PicPos خارجَ الحارس** — `_twins` تغطي أربعةَ مجلداتٍ فقط. وهذا
   طريقُ شاشةِ المستخدمين ذاتِ الـ٨٩٤ سطراً والصفرِ فحوص.
   ⚠️ **ولا يُصلَح بتوسيع الخريطة**: قِيس 2026-08-13 — التوسيعُ إلى ١٥ زوجاً
   يُنزل الفجوات ١٥ ← ١٣، أي **يُخفي فجوتَين حقيقيتَين**، لأن مدى البلوغ
   اتّحادٌ فكلُّ توأمٍ يُضاف يُبرّئ أكثر. يحتاج إعادةَ تصميمٍ لا توسيعاً.

## أعلى ما يستحقّ التالي

1. **`treasury_receipts_create`** — بابان على **نفس الشاشة**، أحدُهما محروسٌ
   والآخرُ لا، وجارُه «سند صرف» محروس. أرخصُ إصلاحٍ وأوضحُ سهو.
2. **`products_add` عبر F5** — الزرُّ محروسٌ والاختصارُ لا. ونفسُ النمط في
   `purchases_picpos` و`sales_invoices_picpos`.
3. **`pos_print`** — `onReprint` يطبع بلا فحص.
4. **الأكوادُ الثمانيةُ ذاتُ الملفّ الميّت** — تُوصَل أو تُحذف؛ بقاؤها يجعل
   شاشةَ الصلاحيات تكذب.

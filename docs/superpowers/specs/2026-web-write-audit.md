# تدقيق الكتابات المباشرة — شاشات نسخة الويب (م3-9)

**النطاق:** كل ملفات `lib/presentation/**` و`lib/web/**` الواصلة من `lib/main_web_entry.dart`
(الإغلاق الاستيرادي بعد الاستيراد الشرطي `dart.library.js_interop`؛ ≈289 ملفاً في presentation/web).
التدقيق مسحٌ نصّي لأنماط الكتابة (`db.into/insert/update/delete/customStatement/transaction/batch`،
`*Companion.insert`، ودوال `AppDatabase` الكاتبة المستدعاة من `ref.read(databaseProvider)`).

## كيف تعمل الكتابة على الويب

- **القراءة:** قناة `/webdb` (drift/remote) مقيّدة بـ`SELECT` فقط (`WebReadPolicyInterceptor`).
  أي `insert/update/delete/customStatement/transaction` عليها تُرفض بـ`WebReadPolicyViolation` (خطأ تقني إنجليزي).
- **الكتابة المدعومة:** تمرّ عبر `ClientWriteInterceptor` → `ServerProxy` → HTTP بـ`X-Session-Token` (aud:`web`)
  إلى مسارات `ApiAuthMiddleware.webWritePrefixes` (تُفتح فقط عند «تفعيل الوصول من المتصفح»).
  المثبَت end-to-end في `test/integration/web_write_path_test.dart` (سند قبض) فقط.
- **الكتابة غير المدعومة:** دوال `AppDatabase` التي تكتب مباشرةً ولا يعترضها `ClientWriteInterceptor`
  (لا مسار HTTP لها). تُحجب الآن بـ`WebWriteGuard` (`lib/web/web_write_guard.dart`) برسالة عربية:
  «هذه العملية غير مدعومة في نسخة الويب بعد — استخدم تطبيق سطح المكتب.» (على الديسكتوب: لا أثر).

## التصنيف

| الحالة | المعنى |
|---|---|
| **مدعومة** | عبر مستودع/معترِض → HTTP (`*Companion.insert` هنا مجرّد حمولة تُمرَّر للمستودع، لا كتابة مباشرة) |
| **محجوبة** | كتابة مباشرة على AppDatabase غير مدعومة — تُحجب بـ`WebWriteGuard` |
| **قراءة فقط** | لا كتابة |
| **خارج النطاق** | شاشة POS/وردية/أجهزة — مستبعدة عن الويب أصلاً |

## الجدول

| الشاشة (ScreenId) | الملف | الكتابات | الحالة |
|---|---|---|---|
| العروض `offers` | `offers_picpos/offer_dialogs_picpos.dart` | `OffersCompanion.insert`، `OfferItemsCompanion.insert` (حمولة للمستودع) | مدعومة (مسار `/api/offers*` ضمن webWritePrefixes — **غير مُثبتة end-to-end**) |
| الأطراف `parties/customers/suppliers` | `parties_picpos/dialogs/add_party_dialog_picpos.dart`، `screens/parties/party_dialogs.dart` | `PartiesCompanion.insert` عبر مستودع | مدعومة (غير مُثبتة e2e) |
| مجموعات الأطراف | `screens/parties/providers/party_groups_controller.dart` + `party_groups_tab.dart` | `createPartyGroup/updatePartyGroup/deletePartyGroup` (معترَضة في `SyncInterceptor`) | مدعومة |
| | | `setPartyGroupActive` (زر التفعيل)، `assignPartyToGroup` (إزالة عضو) | **محجوبة** (`WebWriteGuard` في `party_groups_tab.dart`) |
| المنتجات `products/categories` | `products/providers/products_controller.dart`، `add_product_dialog.dart`، `product_edit_dialog.dart`، `unit_edit_dialog.dart` | `ProductsCompanion/ProductUnitsCompanion/UnitsCompanion.insert` عبر مستودع | مدعومة (غير مُثبتة e2e) |
| أوامر البيع/الشراء `salesOrders/purchaseOrders` | `sales_orders_screen.dart`، `purchase_orders_screen.dart` | `*OrderItemsCompanion.insert` عبر مستودع | مدعومة (غير مُثبتة e2e) |
| بنود المخزون `inventoryBonds` | `inventory/providers/inventory_bonds_controller.dart` | `InventoryBondItemsCompanion.insert` عبر مستودع | مدعومة (غير مُثبتة e2e) |
| الفروع `branches` | `warehouse_edit_dialog.dart` | `WarehousesCompanion.insert` عبر مستودع | مدعومة (غير مُثبتة e2e) |
| | `warehouse_locations_screen.dart` | `saveWarehouseLocation`، `editWarehouseLocation`، `moveStockBetweenBins`، `enableWarehouseBins`، `setSetting` | **محجوبة** (حارس في `change()`) |
| سندا القبض/الدفع `receiptVoucher/paymentVoucher` | `treasury_picpos/screens/*_voucher_picpos_screen.dart` | إنشاء السند عبر `ClientVoucherInterceptor` | مدعومة (مُثبتة: `web_write_path_test`) |
| | | `recordVoucherAllocations` | تُتخطّى أصلاً عند الاعتراض (`interceptedByServer`) ويظهر toast |
| | `treasury_picpos/voucher_sources.dart` | `assignVoucherBookLeaf` (ختم ورقة الدفتر) | **محجوبة قبل أي كتابة**: `preValidateVoucherBookLeaf` يرمي `VoucherBookException` على الويب إن اختير دفتر (كي لا يُحفظ السند ثم يفشل الختم) |
| | `treasury_picpos/screens/voucher_books_panel.dart` | `createVoucherBook`، `setVoucherBookStatus`، `cancelVoucherBookLeaf` | **محجوبة** |
| فواتير المبيعات `salesInvoices` | `sales_invoices_picpos/screens/sales_invoice_cash_customer.dart` | `createPermanentCustomerFromCashSale` (حفظ كعميل دائم) | **محجوبة** |
| مرتجعات المبيعات/المشتريات | `sales_returns_picpos/*`، `purchase_returns_picpos/*` | حفظ المرتجع عبر المستودع؛ حوار الوردية مستبدل بشرح (`shift_unavailable_dialog_web.dart`) | مدعومة بعد فتح وردية من الكاشير؛ بلا وردية: رسالة عربية ولا أثر |
| إدارة التوزيع (مناطق/مسارات) | `distribution_picpos/screens/dm_areas_tab.dart`، `dm_routes_tab.dart` | `saveDistributionArea`، `deleteDistributionArea`، `saveDistributionRoute`، `assignCustomerToRoute` | **محجوبة** |
| الإعدادات `settings` (نسخة الويب المصغّرة) | `lib/web/web_settings_screen.dart` | لا كتابة (تنقّل للمستخدمين/الفروع + مصفوفة الصلاحيات) | قراءة فقط |
| | `screens/settings/widgets/security_alerts_panel.dart` | `markNotificationAsRead` (زر «إخفاء») | **محجوبة** |
| المستخدمون `users` | `users_picpos/screens/users_management_picpos_screen.dart` | عبر مستودع المستخدمين (`/api/users*`، `/api/roles*`) | مدعومة (غير مُثبتة e2e) |
| الفروع — تبويب «نقاط البيع» | `settings_picpos/widgets/terminals_body_web.dart` | بديل نصّي؛ `/api/pos-terminals` خارج webWritePrefixes عمداً | خارج النطاق |
| لوحة التحكم، التقارير، الأستاذ، الميزان، الأصول، إلخ | بقية الملفات | `insert/update/delete` المرصودة في البقية هي دوال قوائم/خرائط (`List.insert`, `Map.update`, `Excel.delete`, `Overlay.insert`, `dashboardFilter.update`) | قراءة فقط |

## ما لم يُدقَّق (حدود صريحة)

- طبقة `lib/data/repositories/**` و`lib/services/**`: لم تُراجَع واحداً واحداً. ما يمرّ عبرها يفترض أن `ClientWriteInterceptor`
  يغطيه، لكن **التغطية الفعلية لكل مستودع لم تُختبر** — المختبَر فعلياً سند القبض فقط. أي مستودع يكتب مباشرة بلا اعتراض
  سيفشل بـ`WebReadPolicyViolation` من المضيف (لا كتابة صامتة، لكن الرسالة تقنية).
- مسح الأنماط نصّي: دالة كاتبة بتسمية غير معتادة قد تفوت. القائمة أعلاه مصدرها استدعاءات `databaseProvider`/`db.<method>` في الإغلاق.
- `SecurityScreenGate` لا يُضمَّن في `web_shell` عمداً (انظر رأس `lib/web/web_shell.dart`): كلمات مرور الأقسام تُفرَّغ من قناة القراءة
  فتفتح البوّابة دائماً (واجهة مضلّلة)، والأمان الفعلي على الخادم: صلاحيات المستخدم في كل معالج + سياسة القراءة (دور ← جداول).

## ملاحظات تشغيلية

- «تفعيل الوصول من المتصفح» (الإعدادات ← الشبكة) مطفأ افتراضياً؛ يسري بعد إعادة تشغيل السيرفر:
  يفتح `ApiAuthMiddleware.enableWebSessionWrites()`، يضبط `WebOriginPolicy`، ويقدّم `build/web` (أو المجلد المضبوط) من نفس الأصل.
  عند التعطيل: `/webdb` و`/api/web/*` بـ404، ومسارات الكتابة لرمز الويب مغلقة.
- `/api/sales/held` و`/api/sales/held-items` (POS) مستثناة من بادئة `/api/sales` لرمز الويب (`webWriteDeniedPrefixes`).
- ملفات `build/web` غير متعقَّبة في git (`build/` مُتجاهَل).

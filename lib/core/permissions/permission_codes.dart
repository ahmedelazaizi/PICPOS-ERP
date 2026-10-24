import 'package:picpos_erp/core/i18n/tr.dart';
import 'mirror_permission_codes.dart';
import 'warehouse_permission_codes.dart';
// Permission Codes Registry
//
// Contains all permission codes used throughout the application.
// These codes are stored in the database and checked against user roles.

class PermissionCodes {
  PermissionCodes._();

  // ═══════════════════════════════════════════════════════════════════════════
  // POS PERMISSIONS (البيع السريع)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الوصول للبيع السريع
  static const String posAccess = 'pos_access';

  /// تطبيق خصم
  static const String posDiscount = 'pos_discount';

  /// مرتجعات المبيعات
  static const String posReturn = 'pos_return';

  /// استبدال المنتجات
  static const String posExchange = 'pos_exchange';

  /// تعليق الفواتير
  static const String posHoldOrder = 'pos_hold_order';

  /// استرجاع فاتورة معلقة
  static const String posRestoreHeld = 'pos_restore_held';

  /// حذف من الفواتير المعلقة
  static const String posDeleteHeld = 'pos_delete_held';

  /// عرض تفاصيل الإغلاق المالية
  static const String posClosingViewDetails = 'pos_closing_view_details';

  /// طباعة أوامر الشغل
  static const String posWorkOrder = 'pos_work_order';

  /// فتح درج النقدية
  static const String posOpenDrawer = 'pos_open_drawer';

  /// حفظ البيع
  static const String posSave = 'pos_save';

  /// طباعة الفاتورة
  static const String posPrint = 'pos_print';

  /// تعديل سعر الصنف
  static const String posPriceEdit = 'pos_price_edit';

  /// تغيير حالة الضريبة
  static const String posTaxToggle = 'pos_tax_toggle';

  // ─────────────────────────────────────────────────────────────────────────
  // POS Additional Permissions (صلاحيات POS الإضافية)
  // ─────────────────────────────────────────────────────────────────────────

  /// إضافة مصروف سريع
  static const String posExpense = 'pos_expense';

  /// اختيار نوع المصروف
  static const String posExpenseTypeSelect = 'pos_expense_type_select';

  /// كتابة بيان المصروف
  static const String posExpenseDescription = 'pos_expense_description';

  /// حذف مصروف سابق
  static const String posExpenseDelete = 'pos_expense_delete';

  /// عرض الأصناف المحذوفة
  static const String posDeletedItems = 'pos_deleted_items';

  /// عرض الفواتير السابقة
  static const String posPreviousInvoices = 'pos_previous_invoices';

  /// الوصول للإقفال اليومي
  static const String posDailyClosing = 'pos_daily_closing';

  /// عرض تفاصيل الإقفال اليومي
  static const String viewDailyClosingDetails = 'view_daily_closing_details';

  /// تعديل فاتورة سابقة
  static const String posEditInvoice = 'pos_edit_invoice';

  /// إلغاء فاتورة
  static const String posCancelInvoice = 'pos_cancel_invoice';

  /// طلبات التوصيل
  static const String posDelivery = 'pos_delivery';

  /// تغيير طريقة الدفع
  static const String posPaymentMethods = 'pos_payment_methods';

  /// الدفع المقسم
  static const String posSplitPayment = 'pos_split_payment';

  /// إضافة عميل من البيع
  static const String posCustomerAdd = 'pos_customer_add';

  /// اختيار عميل
  static const String posCustomerSelect = 'pos_customer_select';

  /// عرض سعر التكلفة
  static const String posViewCost = 'pos_view_cost';

  /// عرض الربح
  static const String posViewProfit = 'pos_view_profit';

  /// إضافة ملاحظة للصنف
  static const String posNoteAdd = 'pos_note_add';

  /// تعديل الكمية
  static const String posQuantityEdit = 'pos_quantity_edit';

  /// حذف صنف من السلة
  static const String posRemoveItem = 'pos_remove_item';

  /// استخدام الميزان
  static const String posWeightDialog = 'pos_weight_dialog';

  /// فتح الوردية (Spec 077 — symmetric pair with posShiftClose; gates
  /// `POST /api/shifts/open` server-side)
  static const String posShiftOpen = 'pos_shift_open';

  /// إغلاق الوردية
  static const String posShiftClose = 'pos_shift_close';

  /// مسح السلة بالكامل
  static const String posClearCart = 'pos_clear_cart';

  /// البحث اليدوي والباركود
  static const String posSearch = 'pos_search';

  /// الدفع السريع (Quick Pay)
  static const String posQuickPay = 'pos_quick_pay';

  /// زيادة كمية الصنف
  static const String posItemPlus = 'pos_item_plus';

  /// نقص كمية الصنف
  static const String posItemMinus = 'pos_item_minus';

  // ─────────────────────────────────────────────────────────────────────────
  // POS Specific Payment Permissions
  // ─────────────────────────────────────────────────────────────────────────

  /// الدفع النقدي
  static const String posPaymentCash = 'pos_payment_cash';

  /// الدفع بالبطاقة
  static const String posPaymentCard = 'pos_payment_card';

  /// الدفع الآجل
  static const String posPaymentCredit = 'pos_payment_credit';

  /// الدفع بالتحويل
  static const String posPaymentTransfer = 'pos_payment_transfer';

  /// الدفع المتعدد
  static const String posPaymentMultiple = 'pos_payment_multiple';

  // ─────────────────────────────────────────────────────────────────────────
  // POS Header & Screen Permissions (صلاحيات شريط POS والشاشة)
  // ─────────────────────────────────────────────────────────────────────────

  /// اختيار طاولة
  static const String posTableSelect = 'pos_table_select';

  /// تكبير/تصغير السلة
  static const String posGridToggle = 'pos_grid_toggle';

  /// حجز مسبق
  static const String posBooking = 'pos_booking';

  /// عرض العروض
  static const String posOffers = 'pos_offers';

  /// طلب حساب الطاولة
  static const String posTableBill = 'pos_table_bill';

  /// فتح لوحة المفاتيح
  static const String posKeyboard = 'pos_keyboard';

  /// عرض الإشعارات
  static const String posNotifications = 'pos_notifications';

  /// تنبيه نقص المخزون
  static const String posLowStockAlert = 'pos_low_stock_alert';

  /// البحث بالباركود
  static const String posBarcodeScan = 'pos_barcode_scan';

  /// إضافة صنف للسلة
  static const String posAddProduct = 'pos_add_product';

  // ═══════════════════════════════════════════════════════════════════════════
  // DASHBOARD PERMISSIONS (لوحة التحكم)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الوصول للوحة التحكم
  static const String dashboardAccess = 'dashboard_access';

  /// الوصول لتطبيق الإدارة السحابي بعد تفعيله للمستخدم
  static const String mobileAdminAccess = 'mobile_admin_access';

  /// عرض مبيعات اليوم
  static const String dashboardSalesToday = 'dashboard_sales_today';

  /// عرض إجمالي المبيعات
  static const String dashboardSalesTotal = 'dashboard_sales_total';

  /// عرض الأرباح
  static const String dashboardProfit = 'dashboard_profit';

  /// عرض عدد العملاء
  static const String dashboardCustomers = 'dashboard_customers';

  /// عرض الرسوم البيانية
  static const String dashboardChart = 'dashboard_chart';

  /// أفضل المنتجات مبيعاً
  static const String dashboardTopProducts = 'dashboard_top_products';

  /// تنبيهات المخزون
  static const String dashboardAlerts = 'dashboard_alerts';

  /// الطلبات المعلقة
  static const String dashboardPendingOrders = 'dashboard_pending_orders';

  // ═══════════════════════════════════════════════════════════════════════════
  // INVENTORY PERMISSIONS (المخزون)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض المخزون
  static const String inventoryView = 'inventory_view';

  /// تعديل المخزون
  static const String inventoryEdit = 'inventory_edit';

  /// عمليات تحويل المخزون
  static const String inventoryTransfer = 'inventory_transfer';

  /// إدارة المستودعات (Spec 077 — gates warehouses CRUD endpoints)
  static const String warehousesManage = 'warehouses_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCT PERMISSIONS (المنتجات)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض المنتجات
  static const String productsView = 'products_view';

  /// إضافة منتجات
  static const String productsAdd = 'products_add';

  /// تعديل منتجات
  static const String productsEdit = 'products_edit';

  /// حذف منتجات
  static const String productsDelete = 'products_delete';

  /// استيراد من Excel
  static const String productsImport = 'products_import';

  /// تصدير إلى Excel
  static const String productsExport = 'products_export';

  /// إدارة الباركود
  static const String productsBarcode = 'products_barcode';

  /// إضافة/تعديل الصورة
  static const String productsImage = 'products_image';

  /// إدارة الوحدات
  static const String productsUnits = 'products_units';

  /// إدارة الصلاحية
  static const String productsExpiry = 'products_expiry';

  /// قفل/فتح المنتج
  static const String productsLock = 'products_lock';

  /// عرض الأسعار
  static const String productsPriceView = 'products_price_view';

  /// عرض التكلفة
  static const String productsCostView = 'products_cost_view';

  /// عرض المخزون
  static const String productsStockView = 'products_stock_view';

  /// ترحيل المنتجات للميزان
  static const String productsScaleUpload = 'products_scale_upload';

  /// إدارة قوائم الأسعار (Spec 077 — gates the 3 /api/price-lists*
  /// endpoints; admin-only default-grant)
  static const String priceListsManage = 'price_lists_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY PERMISSIONS (التصنيفات)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض التصنيفات
  static const String categoriesView = 'categories_view';

  /// إضافة تصنيفات
  static const String categoriesAdd = 'categories_add';

  /// تعديل تصنيفات
  static const String categoriesEdit = 'categories_edit';

  /// حذف تصنيفات
  static const String categoriesDelete = 'categories_delete';

  /// ترحيل تصنيف للميزان
  static const String categoriesScaleUpload = 'categories_scale_upload';

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOMER PERMISSIONS (العملاء)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض العملاء
  static const String customersView = 'customers_view';

  /// إضافة عملاء
  static const String customersAdd = 'customers_add';

  /// تعديل العملاء
  static const String customersEdit = 'customers_edit';

  /// حذف عملاء
  static const String customersDelete = 'customers_delete';

  /// إرسال مستندات العميل على واتساب (فاتورة · كشف حساب · مطالبة)
  ///
  /// كودٌ مستقلٌّ عن `customers_view` عن قصد: القراءةُ داخل النظام شيء،
  /// ومخاطبةُ الزبون باسم المحلّ شيءٌ آخر. وطلبُ المالك 2026-09-12 نصَّ
  /// على أنّ الإرسال «بيفرق من مستخدم لاخر».
  static const String customerMessageSend = 'customer_message_send';

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPPLIER PERMISSIONS (الموردين)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الموردين
  static const String suppliersView = 'suppliers_view';

  /// إضافة موردين
  static const String suppliersAdd = 'suppliers_add';

  /// تعديل الموردين
  static const String suppliersEdit = 'suppliers_edit';

  /// حذف موردين
  static const String suppliersDelete = 'suppliers_delete';

  // ═══════════════════════════════════════════════════════════════════════════
  // PURCHASE PERMISSIONS (المشتريات)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض فواتير الشراء
  static const String purchasesView = 'purchases_view';

  /// إنشاء فواتير شراء
  static const String purchasesCreate = 'purchases_create';

  /// تعديل فواتير شراء
  static const String purchasesEdit = 'purchases_edit';

  /// حذف فواتير شراء
  static const String purchasesDelete = 'purchases_delete';

  /// طباعة فواتير الشراء
  static const String purchasesPrint = 'purchases_print';

  /// عرض مرتجعات المشتريات
  static const String purchasesReturnView = 'purchases_return_view';

  /// إنشاء مرتجع مشتريات
  static const String purchasesReturnCreate = 'purchases_return_create';

  /// تعديل مرتجع مشتريات
  static const String purchasesReturnEdit = 'purchases_return_edit';

  /// حذف مرتجع مشتريات
  static const String purchasesReturnDelete = 'purchases_return_delete';

  /// طباعة مرتجع مشتريات
  static const String purchasesReturnPrint = 'purchases_return_print';

  /// J2 — مراجعة واعتماد مرتجع مشتريات (ترحيلُ المسودة: مخزونٌ وقيدٌ وخزينة).
  static const String purchasesReturnApprove = 'purchases_return_approve';

  /// عرض أوامر الشراء
  static const String purchaseOrdersView = 'purchase_orders_view';

  // ═══════════════════════════════════════════════════════════════════════════
  // SALES PERMISSIONS (فواتير البيع)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض فواتير البيع
  static const String salesView = 'sales_view';

  /// إنشاء فاتورة مبيعات
  static const String salesCreate = 'sales_create';

  /// تعديل فواتير البيع
  static const String salesEdit = 'sales_edit';

  /// حذف فواتير البيع
  static const String salesDelete = 'sales_delete';

  /// طباعة فواتير البيع
  static const String salesPrint = 'sales_print';

  /// عرض المبالغ
  static const String salesAmountsView = 'sales_amounts_view';

  /// عرض فواتير المرتجعات
  static const String salesReturnView = 'sales_return_view';

  /// إنشاء مرتجع مبيعات
  static const String salesReturnCreate = 'sales_return_create';

  /// تعديل فواتير المرتجعات
  static const String salesReturnEdit = 'sales_return_edit';

  /// حذف فواتير المرتجعات
  static const String salesReturnDelete = 'sales_return_delete';

  /// طباعة فواتير المرتجعات
  static const String salesReturnPrint = 'sales_return_print';

  /// J2 — مراجعة واعتماد مرتجع مبيعات (ترحيلُ المسودة: مخزونٌ وقيدٌ وخزينة).
  static const String salesReturnApprove = 'sales_return_approve';

  /// عرض طلبات البيع
  static const String salesOrdersView = 'sales_orders_view';

  // ═══════════════════════════════════════════════════════════════════════════
  // OFFERS PERMISSIONS (العروض)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض العروض
  static const String offersView = 'offers_view';

  /// إنشاء عروض
  static const String offersCreate = 'offers_create';

  /// تعديل العروض
  static const String offersEdit = 'offers_edit';

  /// حذف العروض
  static const String offersDelete = 'offers_delete';

  // ═══════════════════════════════════════════════════════════════════════════
  // DELIVERY PERMISSIONS (التوصيل)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض التوصيل
  static const String deliveryView = 'delivery_view';

  /// إدارة التوصيل
  static const String deliveryManage = 'delivery_manage';

  /// إدارة المناديب
  static const String deliveryCourierManage = 'delivery_courier_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLES PERMISSIONS (الطاولات - مطاعم)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الطاولات
  static const String tablesView = 'tables_view';

  /// إدارة الطاولات
  static const String tablesManage = 'tables_manage';

  // #12: Granular Table POS Permissions

  /// الوصول لنقطة بيع الطاولات
  static const String tablesPosAccess = 'tables_pos_access';

  /// إضافة أصناف للطاولة
  static const String tablesAddItems = 'tables_add_items';

  /// تسوية حساب الطاولة
  static const String tablesCheckout = 'tables_checkout';

  /// نقل طلب بين الطاولات
  static const String tablesTransfer = 'tables_transfer';

  /// إلغاء/مسح طلب الطاولة
  static const String tablesCancel = 'tables_cancel';

  /// طباعة فاتورة الطاولة
  static const String tablesPrintBill = 'tables_print_bill';

  /// خصمٌ على طلب الطاولة
  static const String tablesDiscount = 'tables_discount';

  /// دمجُ طلبَي طاولتين في واحد — يهدم طلباً ويضخّ أصنافَه في آخر.
  static const String tablesMerge = 'tables_merge';

  /// تقسيمُ حساب الطاولة على عدّة دافعين.
  static const String tablesSplitBill = 'tables_split_bill';

  /// حجزُ طاولةٍ لعميلٍ في وقتٍ لاحق.
  static const String tablesReserve = 'tables_reserve';

  // ═══════════════════════════════════════════════════════════════════════════
  // KITCHEN PERMISSIONS (المطبخ)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض شاشة المطبخ
  static const String kitchenView = 'kitchen_view';

  /// إدارة طلبات المطبخ (تحديث الحالات، إعادة الاستدعاء)
  static const String kitchenManage = 'kitchen_manage';

  /// إعدادات شاشة المطبخ (المحطات وربط التصنيفات)
  static const String kdsSettings = 'kds_settings';

  // ═══════════════════════════════════════════════════════════════════════════
  // TREASURY PERMISSIONS (الخزينة)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الخزينة
  static const String treasuryView = 'treasury_view';

  /// إدارة الخزينة
  static const String treasuryManage = 'treasury_manage';

  /// إنشاء سند قبض
  static const String treasuryReceiptsCreate = 'treasury_receipts_create';

  /// إنشاء سند صرف
  static const String treasuryPaymentsCreate = 'treasury_payments_create';

  /// تحويل بين الخزائن
  static const String treasuryTransfer = 'treasury_transfer';

  /// عرض الأرصدة
  static const String treasuryBalanceView = 'treasury_balance_view';

  /// عرض الحركات
  static const String treasuryTransactionsView = 'treasury_transactions_view';

  /// تعيين نسبة عمولة التحصيل
  static const String treasuryCommission = 'treasury_commission';

  /// إدارة الأوراق التجارية (Spec 077 — gates the 6 commercial-papers
  /// endpoints; default-grant to admin + financial manager)
  static const String commercialPapersManage = 'commercial_papers_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // HR PERMISSIONS (الموظفين)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تم عرض الموظفين (Access HR Screen)
  static const String hrView = 'hr_view';

  /// إدارة بيانات الموظفين (إضافة، تعديل وحذف)
  static const String hrManage = 'hr_manage';

  /// تسجيل السلف للموظفين
  static const String hrAdvanceRecord = 'hr_advance_record';

  /// إصدار مسيرات الرواتب والمكافآت
  static const String hrPayrollProcess = 'hr_payroll_process';

  /// J4 (الجزء ٢) — عرض الحضور والورديات والعطلات
  static const String hrAttendanceView = 'hr_attendance_view';

  /// J4 — إدخال الحضور وتصحيحه يدوياً واستيراد البصمة والعطلات
  static const String hrAttendanceEdit = 'hr_attendance_edit';

  /// J4 — تقديم طلبات الإجازة
  static const String hrLeaveRequest = 'hr_leave_request';

  /// J4 — اعتماد طلبات الإجازة ورفضها لأي موظف وإدارة أنواعها وأرصدتها
  static const String hrLeaveApprove = 'hr_leave_approve';

  /// J4 — تعريف الورديات وإسنادها
  static const String hrShiftsManage = 'hr_shifts_manage';

  /// J4 (الجزء ٣) — عرض المسيرات والقسائم والسلف والعمولات
  static const String hrPayrollView = 'hr_payroll_view';

  /// J4 — إنشاء المسير واحتسابه وتسويته ومراجعته وإعدادات الرواتب
  static const String hrPayrollEdit = 'hr_payroll_edit';

  /// J4 — اعتماد المسير والمكافآت والجزاءات
  static const String hrPayrollApprove = 'hr_payroll_approve';

  /// J4 — ترحيل المسير بقيده وصرفه وعكسه
  static const String hrPayrollPost = 'hr_payroll_post';

  /// J4 — صرف السلف والقروض وتسديدها
  static const String hrAdvancesManage = 'hr_advances_manage';

  /// J4 — خطط عمولات المندوبين
  static const String hrCommissionsManage = 'hr_commissions_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORTS PERMISSIONS (التقارير)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض التقارير
  static const String reportsView = 'reports_view';

  /// تصدير التقارير
  static const String reportsExport = 'reports_export';

  /// تقرير المبيعات
  static const String reportsSales = 'reports_sales';

  /// تقرير المشتريات
  static const String reportsPurchases = 'reports_purchases';

  /// تقرير المخزون
  static const String reportsInventory = 'reports_inventory';

  /// تقرير الخزينة
  static const String reportsTreasury = 'reports_treasury';

  /// تقرير العملاء
  static const String reportsCustomers = 'reports_customers';

  /// تقرير الموردين
  static const String reportsSuppliers = 'reports_suppliers';

  /// تقرير الأرباح
  static const String reportsProfit = 'reports_profit';

  /// تقرير المنتجات
  static const String reportsProducts = 'reports_products';

  /// تقرير الورديات
  static const String reportsShifts = 'reports_shifts';

  /// تقرير الضرائب
  static const String reportsTaxes = 'reports_taxes';

  /// تقرير أرباح التصنيفات
  static const String reportsCategoryProfit = 'reports_category_profit';

  /// مطابقة حسابات شركات التوصيل
  static const String reportsDeliveryRecon = 'reports_delivery_recon';

  /// تقرير المبيعات حسب نوع الطلب
  static const String reportsOrderType = 'reports_order_type';

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS PERMISSIONS (الإعدادات)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الإعدادات
  static const String settingsView = 'settings_view';

  /// تعديل الإعدادات
  static const String settingsEdit = 'settings_edit';

  /// إعدادات الشركة
  static const String settingsCompany = 'settings_company';

  /// إعدادات الإيصال
  static const String settingsReceipt = 'settings_receipt';

  /// إعدادات الطابعة
  static const String settingsPrinter = 'settings_printer';

  /// إعدادات الميزان
  static const String settingsScale = 'settings_scale';

  /// النسخ الاحتياطي
  static const String settingsBackup = 'settings_backup';

  /// الاستعادة
  static const String settingsRestore = 'settings_restore';

  /// إعدادات الضريبة
  static const String settingsTax = 'settings_tax';

  /// إعدادات العملة
  static const String settingsCurrency = 'settings_currency';

  /// الوصول لشاشة الإعدادات
  static const String settingsAccess = 'settings_access';

  /// تعديل إعدادات البيع السريع
  static const String settingsPosEdit = 'settings_pos_edit';

  // ═══════════════════════════════════════════════════════════════════════════
  // USER MANAGEMENT PERMISSIONS (إدارة المستخدمين)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدارة المستخدمين
  static const String usersManage = 'users_manage';

  /// إدارة الأدوار
  static const String rolesManage = 'roles_manage';

  /// إنشاء/تعديل المستخدمين من جهاز عميل مقترن (إدارة عبر-فروع).
  /// بدون هذه الصلاحية، شاشة "إضافة مستخدم" تكون للقراءة فقط على
  /// أجهزة العملاء — يضمن أن المستخدمين الجدد يُنشأون فى المقر الرئيسى
  /// أو من حساب موثوق فقط.
  static const String usersManageCrossBranch = 'users_manage_cross_branch';

  // ═══════════════════════════════════════════════════════════════════════════
  // SYSTEM PERMISSIONS (النظام)
  // ═══════════════════════════════════════════════════════════════════════════

  /// سجل المراجعة
  static const String systemAuditLog = 'system_audit_log';

  /// إدارة قاعدة البيانات
  static const String systemDatabase = 'system_database';

  /// إدارة الترخيص
  static const String systemLicense = 'system_license';

  /// تحديث النظام
  static const String systemUpdates = 'system_updates';

  /// فتحُ القائمة الجانبية بلا كلمة مرور المدير.
  ///
  /// ⚠️ **إعفاءٌ لا منع.** الزرُّ العائمُ في `AppShell` محروسٌ منذ #12 بحوار
  /// كلمة مرور المدير، ويُعفى منه من كان **أصلاً** مديراً أو مشرفاً. وهذا
  /// الكودُ يجعل الإعفاءَ صلاحيةً تُمنح لمن يشاء المالك بدل أن يكون صفةً
  /// ملازمةً للمنصب — وهو طلبُه في §٤.
  ///
  /// ومن **لا** يملكه يبقى أمامه الحوارُ كما اليوم فلا يُحبس أحد: زرُّ
  /// «تسجيل الخروج» يعيش داخلَ القائمة الجانبية، فمنعُها منعاً تامّاً كان
  /// سيترك الكاشيرَ بلا مخرجٍ من النظام. (قرارُ المالك 2026-08-15.)
  static const String systemSidebarOpen = 'system_sidebar_open';

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIT PERMISSIONS (المراجعة والتدقيق)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض سجل العمليات (sidebar gating)
  static const String auditView = 'audit_view';

  /// إغلاق وردية (عد نقدي أعمى)
  static const String auditShiftBlind = 'audit_shift_blind';

  /// إلغاء قفل الفواتير
  static const String auditInvoiceUnlock = 'audit_invoice_unlock';

  /// تجاوز الحد الائتماني
  static const String partiesCreditLimitBypass = 'parties_credit_limit_bypass';

  // ═══════════════════════════════════════════════════════════════════════════
  // LOYALTY PERMISSIONS (نقاط الولاء)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض نقاط الولاء
  static const String loyaltyView = 'loyalty_view';

  /// إدارة برامج الولاء
  static const String loyaltyManage = 'loyalty_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // DISTRIBUTION PERMISSIONS (التوزيع)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض التوزيع والمندوبين
  static const String distributionView = 'distribution_view';

  /// إدارة التوزيع والمسارات
  static const String distributionManage = 'distribution_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // E-INVOICING PERMISSIONS (الفوترة الإلكترونية)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الفوترة الإلكترونية
  static const String einvoiceView = 'einvoice_view';

  /// إرسال فاتورة إلكترونية
  static const String einvoiceSubmit = 'einvoice_submit';

  /// إلغاء فاتورة إلكترونية
  static const String einvoiceCancel = 'einvoice_cancel';

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCOUNTING PERMISSIONS (المحاسبة)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الحسابات والقيود
  static const String accountingView = 'accounting_view';

  /// إدارة القيود المحاسبية
  static const String accountingManage = 'accounting_manage';

  /// إنشاء قيود يومية
  static const String accountingJournal = 'accounting_journal';

  /// اعتماد القيود المنشأة من مستخدمٍ آخر (Maker-Checker)
  static const String accountingJournalApprove = 'approve_journal';

  // ═══════════════════════════════════════════════════════════════════════════
  // MANUFACTURING PERMISSIONS (التصنيع)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض أوامر التصنيع
  static const String manufacturingView = 'manufacturing_view';

  /// إدارة التصنيع والمكونات
  static const String manufacturingManage = 'manufacturing_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // FIXED ASSETS PERMISSIONS (الأصول الثابتة)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض الأصول الثابتة
  static const String assetsView = 'assets_view';

  /// إدارة الأصول الثابتة
  static const String assetsManage = 'assets_manage';

  /// تشغيل الإهلاك
  static const String assetsDepreciation = 'assets_depreciation';

  // ═══════════════════════════════════════════════════════════════════════════
  // OPERATIONAL EXPENSES PERMISSIONS (المصروفات التشغيلية)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تسجيل مصروفٍ تشغيليٍّ وتعديل فئاته وتحميله على أوامر التصنيع
  ///
  /// ⚠️ **فعلُ كتابةٍ ماليٌّ لا عرض.** `recordAndPostOperationalExpense`
  /// تفعل ثلاثةً دفعةً واحدة: ترحّل قيدَ يوميّةٍ متوازناً (‏مدين المصروف /
  /// دائن النقديّة أو البنك)، وتُنشئ سندَ صرفٍ في `safe_transactions`،
  /// وتخصم رصيدَ الخزنة.
  ///
  /// 🔴 **وشاشةُ المصروفات كانت محصورةً بالنطاق وحدَه** — `ScreenId
  /// .operationalExpenses` في `screen_registry.dart` بلا أيّ كودِ صلاحيّة.
  /// فحصرُ التنقّل يفتحها للقراءة لأيّ دورٍ في النطاق، وزرُّ كتابةٍ بلا
  /// حارسٍ يجعل الترحيلَ وخصمَ الخزنة مبلوغَين لمن يملك القراءةَ وحدَها.
  static const String expensesManage = 'expenses_manage';

  /// اعتماد المصروف وتسجيل سداده
  ///
  /// ⚠️ **درجةٌ أعلى من [expensesManage]** — نفسُ تفريق [assetsView] عن
  /// [assetsDepreciation]: مَن يسجّل المصروفَ ليس بالضرورة مَن يعتمده.
  /// وفصلُ الأدوار (‏segregation of duties) هو غرضُ دورة الاعتماد كلِّها،
  /// فجمعُهما تحت كودٍ واحدٍ يُبطلها.
  ///
  /// ⚠️ **ولا يحرّك قيداً**: القيدُ يُرحَّل عند التسجيل لا عند الاعتماد —
  /// راجع `updateExpenseStatus` في `operational_expenses_dao.dart`.
  static const String expensesApprove = 'expenses_approve';

  // ═══════════════════════════════════════════════════════════════════════════
  // LANDED COST PERMISSIONS (التكاليف المحمَّلة)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تطبيق ورقة التكاليف المحمَّلة على المخزون
  ///
  /// ⚠️ **فعلُ كتابةٍ ماليٌّ لا عرض.** `applyLandedCost` تفعل أربعةً دفعةً
  /// واحدة: تمزج `products.costPrice` بالمتوسّط المرجَّح، وتمزج
  /// `inventory_balances.average_cost`، وترحّل قيدَ يوميّةٍ متوازناً (‏مدين
  /// المخزون / دائن ذمم المورد أو النقديّة)، وتختم الورقةَ `applied`.
  ///
  /// وفتحُ الشاشة محكومٌ بـ`purchases_create` (‏`ScreenId.landedCost` في
  /// `auth_providers.dart`) — وهو إذنُ **قراءةٍ** للورقة لا إذنُ ترحيلِ
  /// قيدٍ وتحريكِ تكلفة. فالتطبيقُ درجةٌ أعلى، بكودِه هو — نفسُ تفريق
  /// [assetsView] عن [assetsDepreciation] فوق حرفاً بحرف.
  static const String landedCostApply = 'landed_cost_apply';

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYTICS PERMISSIONS (التحليلات)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض لوحة التحليلات
  static const String analyticsView = 'analytics_view';

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCHES PERMISSIONS (الفروع)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدارة الفروع
  static const String branchesManage = 'branches_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION & SIDEBAR PERMISSIONS (الشريط الجانبي)
  // ═══════════════════════════════════════════════════════════════════════════

  /// عرض عروض الأسعار
  static const String quotesView = 'quotes_view';

  /// عرض المرتجعات
  static const String returnsView = 'returns_view';

  /// عرض المستودعات
  static const String warehousesView = 'warehouses_view';

  /// عرض حركة المخزون
  static const String stockView = 'stock_view';

  /// الجرد الدوري
  static const String stockAudit = 'stock_audit';

  /// عرض الأطراف (العملاء والموردين)
  static const String partiesView = 'parties_view';

  /// إدارة الإضافات والمعدلات
  static const String modifiersManage = 'modifiers_manage';

  // ═══════════════════════════════════════════════════════════════════════════
  // CRITICAL FINANCIAL OPERATIONS (عمليات مالية حرجة)
  // These operations require explicit permission even for admin/system roles.
  // The admin bypass is NOT applied for these — segregation of duties.
  // ═══════════════════════════════════════════════════════════════════════════

  /// حذف قيد يومية مرحّل
  static const String deletePostedJournal = 'delete_posted_journal';

  /// إلغاء فاتورة مدفوعة بالكامل
  static const String voidPaidInvoice = 'void_paid_invoice';

  /// تعديل فاتورة مقفلة/مرحّلة
  static const String modifyLockedInvoice = 'modify_locked_invoice';

  /// حذف سنة مالية
  static const String deleteFiscalYear = 'delete_fiscal_year';

  /// تعديل فترة محاسبية مغلقة
  static const String modifyClosedPeriod = 'modify_closed_period';

  /// تجاوز حد الائتمان للعميل
  static const String overrideCreditLimit = 'override_credit_limit';

  // ── الحجوزات — مواعيدُ الخدمة (مستقلّةٌ عن حجز الطاولات) ──────────────
  static const String bookingsView = 'bookings_view';
  static const String bookingsAdd = 'bookings_add';
  static const String bookingsEdit = 'bookings_edit';
  static const String bookingsCancel = 'bookings_cancel';
  static const String bookingsStatus = 'bookings_status';

  /// منفصلٌ عن `bookingsEdit` عمداً: الإسنادُ والنقلُ عند الغياب عملُ مضيفٍ
  /// يُمارَس عشراتِ المرّات يوميّاً، بينما تعديلُ الوقتِ والعربونِ أضيق.
  /// دمجُهما يفرض إعطاءَ الأوسعِ لمن يحتاج الأضيق.
  static const String bookingsAssign = 'bookings_assign';

  static const String bookingsDeposit = 'bookings_deposit';
  static const String bookingsServicesManage = 'bookings_services_manage';
  static const String bookingsResourcesManage = 'bookings_resources_manage';
  static const String bookingsReports = 'bookings_reports';
  static const String bookingsSettings = 'bookings_settings';

  /// Set of critical financial operations that bypass NO role — even admin
  /// must have the explicit permission assigned.
  // ── نمطُ منح الصلاحية ───────────────────────────────────────────────────

  /// منحٌ بلا شرط — الافتراض.
  static const String grantAllow = 'allow';

  /// منحٌ **مشروط**: الصلاحيةُ ممنوحةٌ ويمرّ تنفيذُها بموافقة مسؤولٍ في كلّ
  /// مرّة. عمودُها `role_permissions.grant_mode` (‏هجرة v163).
  static const String grantConditional = 'conditional';

  /// بادئةُ علامةِ «مشروط» داخلَ قائمة أكواد المستخدم.
  ///
  /// ═══ لماذا علامةٌ في نفس القائمة لا مزوِّدٌ ثانٍ ═══
  ///
  /// `currentUserPermissionsProvider` يُبطَل في مواضعَ كثيرةٍ متفرّقة — بعد
  /// كلّ حفظِ فاتورةٍ وكلّ تعديلِ صلاحيةٍ وكلّ تبديلِ دور. ومزوِّدٌ ثانٍ
  /// للمشروطة يعني موضعَ إبطالٍ ثانياً في **كلٍّ** منها؛ يُنسى واحدٌ فتبقى
  /// القائمةُ المشروطةُ بائدةً بينما الأكوادُ محدَّثة — أي صلاحيةٌ مشروطةٌ
  /// تُنفَّذ بلا موافقة. والعلامةُ في نفس القائمة تجعلها تحميلاً واحداً
  /// وإبطالاً واحداً، فلا موضعَ يُنسى أصلاً.
  ///
  /// والسابقةُ قائمةٌ في هذا الكود: القائمةُ تحمل `'system_admin'` علامةً
  /// اصطناعيّةً لا كودَ صلاحية.
  ///
  /// ⚠️ **ومقيسٌ أنّ ذلك مأمون**: لا مستهلكَ واحدٌ في `lib/` يمرّ على القائمة
  /// (`.map`/`.length`/`for`) — كلُّهم `.contains`. فمن يُضيف مستهلكاً يعدّ
  /// عناصرَها عليه أن يرشّح هذه البادئة.
  static const String conditionalPrefix = 'cond:';

  /// علامةُ الكود المشروط كما تُوضَع في قائمة أكواد المستخدم.
  static String conditionalMarker(String code) => '$conditionalPrefix$code';

  /// هل [code] ممنوحٌ **مشروطاً** لهذا المستخدم؟
  static bool isConditionalIn(List<String> codes, String code) =>
      codes.contains('$conditionalPrefix$code');

  static const Set<String> criticalFinancialOps = {
    deletePostedJournal,
    voidPaidInvoice,
    modifyLockedInvoice,
    deleteFiscalYear,
    modifyClosedPeriod,
    overrideCreditLimit,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // NON-TOGGLEABLE CODES (أكواد مالهاش إنفاذ ممكن)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ٣٣ كود من الـ٨٠ اللي كانت مسجّلة في
  /// `PermissionEnforcementRegistry.knownUnenforced` بلا نقطة إنفاذ في
  /// الكود — لكن على عكس باقي الـ٤٧، دول **مستحيل يتحلّوا بإضافة إنفاذ**.
  /// السبب واحد من التلاتة:
  ///  • الفعل موجود فعلاً بس محمي بكود/آلية تانية (تكرار اسمي، مش ثغرة).
  ///  • الفعل ده أصلاً مش موجود في الكود — الميزة ما اتبنتش.
  ///  • الفعل موجود كأثر جانبي داخلي جوه عملية تانية، مش حاجة المستخدم
  ///    بيضغط عليها بنفسه.
  ///
  /// البلاغ اللي بدأ السويب (2026-08-01) كان «المدير بيغيّر صلاحية ومفيش
  /// حاجة بتحصل» — والـ٣٣ دول جزء أساسي من السبب: كانوا ظاهرين في شاشة
  /// الصلاحيات زي أي كود تاني، فالمدير يقلّبهم ويفتكر إنه بيتحكم في حاجة،
  /// ومفيش أي مستقبل بياخد القرار ده أصلاً مهما فعّله أو ألغاه. المصفوفة دي
  /// بتوثّق سبب كل كود، و`PermissionsManagementWidget` بيستخدمها عشان
  /// يخفيهم افتراضياً من قائمة التبديل بدل ما يكدب على اللي بيستخدم الشاشة.
  ///
  /// ممنوع حذف كود من هنا من غير ما يتنقل لإنفاذ حقيقي أو لـ`knownUnenforced`
  /// الأول — اختبار ثبات المجموعتين بيتأكد إن مفيش كود يقع بين الاتنين
  /// (`permission_nontoggleable_registry_test.dart`).
  static Map<String, String> get nonToggleable => {
    // ── عشرةٌ كان مرجعُها الوحيدُ ملفاً ميّتاً (2026-08-13) ──────────────────
    // `lib/services/role_based_sidebar_service.dart` (٢١٢ سطراً) كان يبني
    // شريطاً جانبياً حسب الدور، وله **صفرُ مستوردين** في `lib/` و`test/` و
    // `tool/` — مقيسٌ لا مفترَض. فحُذف الملفّ.
    //
    // وكان وجودُه يجعل `permission_enforcement_coverage_test` يعدّ هذه
    // العشرةَ «منفَّذة»، فتظهر للمدير في شاشة الصلاحيات بمربّعِ اختيارٍ
    // يقلّبه بلا أثر. وهو بعينه بلاغُ «بغيّر صلاحية ومش بيحصل حاجة».
    //
    // ولا واحدٌ منها ثغرةٌ حقيقية: شاشاتُها **مبوّبةٌ بكودٍ آخرَ فعلاً** في
    // `screenPermissionMap`. فالنقلُ هنا يُخفي المربّعَ (`nonToggleable`
    // بلا شيك بوكس) ويُبقي السببَ مكتوباً.
    'products_view': tr('الشاشة كلها مبوّبة بـ products_add'),
    'parties_view': tr('الشاشة كلها مبوّبة بـ customers_view'),
    'purchases_view': tr('الشاشة كلها مبوّبة بـ purchases_create'),
    'returns_view': tr('شاشة المرتجعات مبوّبة بـ sales_return_view'),
    'stock_view': tr('حركة المخزون مبوّبة بـ inventory_view'),
    'stock_audit': tr('الجرد الدوري مبوّب بـ inventory_view'),
    'settings_access': tr('الشاشة كلها مبوّبة بـ settings_view'),
    'accounting_view': tr('شاشات المحاسبة كلها مبوّبة بـ settings_view'),
    // ⚠️ وهذا وحدَه ليس تكراراً بل **ميزةٌ غائبة**: لا `ScreenId.warehouses`
    // في `screen_registry` ولا مدخلَ له في `screenPermissionMap` — لا شاشةَ
    // مخازنَ في التطبيق أصلاً. ولو أُضيفت فتُبوَّب ويُشطب هذا السطر.
    'warehouses_view': tr('لا شاشة مخازن في التطبيق — لا سطح يُحرَس'),

    // ── مغطّى بكود/آلية تانية (تكرار اسمي، مش ثغرة) ──
    'audit_invoice_unlock': tr('مغطّى بـ modify_locked_invoice'),
    'audit_shift_blind': tr('مغطّى بـ pos_closing_view_details'),
    'categories_scale_upload': tr('الشاشة كلها مبوّبة بـ products_add'),
    'categories_view': tr('الشاشة كلها مبوّبة بـ products_add'),
    'dashboard_customers': tr('مغطّى بـ analytics_view'),
    // دفعة ١١ — مفيش كارت «إجمالي مبيعات» منفصل في أي فورك: الكارت الوحيد
    // (`صافي الإيراد` → `kpi.revenue`) بيتفلتر بـ`dashboardFilterProvider`
    // اللي افتراضه اليوم الحالي والمستخدم بيوسّعه من نفس الشريط. يعني الفرق
    // بين «اليوم» و«الإجمالي» حالة فلتر وقت التشغيل مش ودجت تانية، والكارت
    // اتبوّب بـ`dashboard_sales_today`. تشغيل الكود ده كان هيتطلّب اختراع
    // كارت جديد — ميزة مش إنفاذ صلاحية.
    'dashboard_sales_total':
        tr('نفس كارت dashboard_sales_today — الفرق فلتر فترة مش سطح منفصل'),
    'dashboard_top_products': tr('مغطّى بـ analytics_view'),
    'delivery_view': tr('مغطّى بـ delivery_manage'),
    'parties_credit_limit_bypass': tr('مغطّى بـ override_credit_limit'),
    'pos_cancel_invoice': tr('مغطّى بـ void_paid_invoice'),
    'pos_daily_closing': tr('مغطّى بـ pos_shift_close'),
    'pos_payment_methods':
        tr('مغطّى بالخمس pos_payment_cash/pos_payment_card/pos_payment_transfer/pos_payment_credit/pos_payment_multiple'),
    'pos_split_payment': tr('مغطّى بـ pos_payment_multiple'),
    'products_scale_upload': tr('مغطّى بـ products_export'),
    'reports_customers': tr('الشاشة كلها مبوّبة بـ reports_view'),
    'reports_inventory': tr('الشاشة كلها مبوّبة بـ reports_view'),
    'reports_products': tr('الشاشة كلها مبوّبة بـ reports_view'),
    'reports_profit':
        tr('مغطّى بـ reports_view (وبعض البطاقات بـ reports_category_profit)'),
    'reports_purchases': tr('الشاشة كلها مبوّبة بـ reports_view'),
    'reports_shifts': tr('مغطّى بـ reports_sales'),
    'settings_restore': tr('مغطّى بـ settings_backup'),
    'suppliers_view': tr('مغطّى بـ customers_view'),
    'system_audit_log': tr('مغطّى بـ audit_view'),
    'treasury_transactions_view': tr('مغطّى بـ treasury_view'),
    // ── محجوز — الخاصية ما اتبنتش أصلاً ──
    'dashboard_pending_orders': tr('محجوز — الخاصية ما اتبنتش'),
    'delete_fiscal_year': tr('محجوز — الخاصية ما اتبنتش'),
    'pos_view_cost': tr('محجوز — الخاصية ما اتبنتش'),
    'pos_view_profit': tr('محجوز — الخاصية ما اتبنتش'),
    'sales_return_edit': tr('محجوز — الخاصية ما اتبنتش'),
    'settings_receipt': tr('محجوز — الخاصية ما اتبنتش'),
    'system_updates': tr('محجوز — الخاصية ما اتبنتش'),
    // ── أثر داخلي جوه عملية تانية، مش فعل يقدر المستخدم يستدعيه لوحده ──
    'delete_posted_journal':
        tr('أثر داخلي جوه عكس قيد اليومية القديم عند تعديل أو إلغاء فاتورة مرحّلة (_reverseOldXJournalEntry)، مش فعل للمستخدم'),
    'purchases_return_delete':
        tr('أثر داخلي جوه تعديل مرتجع الشراء (editPurchaseReturn عبر _reversePurchaseReturn)، مش فعل للمستخدم'),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // MASTER PERMISSION LIST (Single Source of Truth for Runtime Sync)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Complete master list of ALL permissions with their codes, names, and categories.
  /// Used by `syncAllPermissions()` to ensure full DB coverage at app startup.
  static List<Map<String, String>> get masterList => [
    // ── POS ──
    {'code': posAccess, 'name': tr('الوصول للبيع السريع'), 'category': 'pos'},
    {'code': posDiscount, 'name': tr('تطبيق خصم'), 'category': 'pos'},
    {'code': posReturn, 'name': tr('مرتجعات المبيعات'), 'category': 'pos'},
    {'code': posExchange, 'name': tr('استبدال المنتجات'), 'category': 'pos'},
    {'code': posHoldOrder, 'name': tr('تعليق الفواتير'), 'category': 'pos'},
    {'code': posRestoreHeld, 'name': tr('استرجاع فاتورة معلقة'), 'category': 'pos'},
    {
      'code': posDeleteHeld,
      'name': tr('حذف من الفواتير المعلقة'),
      'category': 'pos',
    },
    {
      'code': posClosingViewDetails,
      'name': tr('عرض تفاصيل الإغلاق المالية'),
      'category': 'pos',
    },
    {'code': posWorkOrder, 'name': tr('طباعة أوامر الشغل'), 'category': 'pos'},
    {'code': posOpenDrawer, 'name': tr('فتح درج النقدية'), 'category': 'pos'},
    {'code': posSave, 'name': tr('حفظ البيع'), 'category': 'pos'},
    {'code': posPrint, 'name': tr('طباعة الفاتورة'), 'category': 'pos'},
    {'code': posPriceEdit, 'name': tr('تعديل سعر الصنف'), 'category': 'pos'},
    {'code': posTaxToggle, 'name': tr('تغيير حالة الضريبة'), 'category': 'pos'},
    {'code': posExpense, 'name': tr('إضافة مصروف سريع'), 'category': 'pos'},
    {
      'code': posExpenseTypeSelect,
      'name': tr('اختيار نوع المصروف'),
      'category': 'pos',
    },
    {
      'code': posExpenseDescription,
      'name': tr('كتابة بيان المصروف'),
      'category': 'pos',
    },
    {'code': posExpenseDelete, 'name': tr('حذف مصروف سابق'), 'category': 'pos'},
    {
      'code': posDeletedItems,
      'name': tr('عرض الأصناف المحذوفة'),
      'category': 'pos',
    },
    {
      'code': posPreviousInvoices,
      'name': tr('عرض الفواتير السابقة'),
      'category': 'pos',
    },
    {'code': posDailyClosing, 'name': tr('الإقفال اليومي'), 'category': 'pos'},
    {
      'code': viewDailyClosingDetails,
      'name': tr('عرض تفاصيل الإقفال اليومي'),
      'category': 'pos',
    },
    {'code': posEditInvoice, 'name': tr('تعديل فاتورة سابقة'), 'category': 'pos'},
    {'code': posCancelInvoice, 'name': tr('إلغاء فاتورة'), 'category': 'pos'},
    {'code': posDelivery, 'name': tr('طلبات التوصيل'), 'category': 'pos'},
    {'code': posPaymentMethods, 'name': tr('تغيير طريقة الدفع'), 'category': 'pos'},
    {'code': posSplitPayment, 'name': tr('الدفع المقسم'), 'category': 'pos'},
    {'code': posCustomerAdd, 'name': tr('إضافة عميل من البيع'), 'category': 'pos'},
    {'code': posCustomerSelect, 'name': tr('اختيار عميل'), 'category': 'pos'},
    {'code': posViewCost, 'name': tr('عرض سعر التكلفة'), 'category': 'pos'},
    {'code': posViewProfit, 'name': tr('عرض الربح'), 'category': 'pos'},
    {'code': posNoteAdd, 'name': tr('إضافة ملاحظة للصنف'), 'category': 'pos'},
    {'code': posQuantityEdit, 'name': tr('تعديل الكمية'), 'category': 'pos'},
    {'code': posRemoveItem, 'name': tr('حذف صنف من السلة'), 'category': 'pos'},
    {'code': posWeightDialog, 'name': tr('استخدام الميزان'), 'category': 'pos'},
    {'code': posShiftOpen, 'name': tr('فتح الوردية'), 'category': 'pos'},
    // ⚠️ الإغلاقُ في «الخزينة» لا في «البيع السريع» — قرارُ المالك 2026-08-14:
    // «الإغلاقُ له صلاحيةٌ خارجَ إعداد صلاحيات نقطة البيع، بحيث يكون المديرُ
    // هو من يجرد». والفتحُ يبقى فوقُ لأنه فعلُ كاشيرٍ يوميّ، والإغلاقُ جردٌ.
    // والكودُ نفسُه لم يتغيّر ⇒ لا يفقد دورٌ صلاحيةً يملكها. والقواعدُ
    // القائمةُ تُنقَل بهجرة v154 لأن `syncAllPermissions` يتخطّى الموجودَ.
    {'code': posShiftClose, 'name': tr('إغلاق الوردية'), 'category': 'treasury'},
    {'code': posClearCart, 'name': tr('مسح السلة بالكامل'), 'category': 'pos'},
    {'code': posSearch, 'name': tr('البحث اليدوي والباركود'), 'category': 'pos'},
    {'code': posQuickPay, 'name': tr('الدفع السريع'), 'category': 'pos'},
    {'code': posItemPlus, 'name': tr('زيادة كمية الصنف'), 'category': 'pos'},
    {'code': posItemMinus, 'name': tr('نقص كمية الصنف'), 'category': 'pos'},
    // POS Payment
    {'code': posPaymentCash, 'name': tr('الدفع النقدي'), 'category': 'pos'},
    {'code': posPaymentCard, 'name': tr('الدفع بالبطاقة'), 'category': 'pos'},
    {'code': posPaymentCredit, 'name': tr('الدفع الآجل'), 'category': 'pos'},
    {'code': posPaymentTransfer, 'name': tr('الدفع بالتحويل'), 'category': 'pos'},
    {'code': posPaymentMultiple, 'name': tr('الدفع المتعدد'), 'category': 'pos'},
    // POS Header
    {'code': posTableSelect, 'name': tr('اختيار طاولة'), 'category': 'pos'},
    {'code': posGridToggle, 'name': tr('تكبير/تصغير السلة'), 'category': 'pos'},
    {'code': posBooking, 'name': tr('حجز مسبق'), 'category': 'pos'},
    {'code': posOffers, 'name': tr('عرض العروض'), 'category': 'pos'},
    {'code': posTableBill, 'name': tr('طلب حساب الطاولة'), 'category': 'pos'},
    {'code': posKeyboard, 'name': tr('فتح لوحة المفاتيح'), 'category': 'pos'},
    {'code': posNotifications, 'name': tr('عرض الإشعارات'), 'category': 'pos'},
    {'code': posLowStockAlert, 'name': tr('تنبيه نقص المخزون'), 'category': 'pos'},
    {'code': posBarcodeScan, 'name': tr('البحث بالباركود'), 'category': 'pos'},
    {'code': posAddProduct, 'name': tr('إضافة صنف للسلة'), 'category': 'pos'},

    // ── Dashboard ──
    {
      'code': dashboardAccess,
      'name': tr('الوصول للوحة التحكم'),
      'category': 'dashboard',
    },
    {
      'code': mobileAdminAccess,
      'name': tr('الوصول لتطبيق الإدارة'),
      'category': 'dashboard',
    },
    {
      'code': dashboardSalesToday,
      'name': tr('عرض مبيعات اليوم'),
      'category': 'dashboard',
    },
    {
      'code': dashboardSalesTotal,
      'name': tr('عرض إجمالي المبيعات'),
      'category': 'dashboard',
    },
    {'code': dashboardProfit, 'name': tr('عرض الأرباح'), 'category': 'dashboard'},
    {
      'code': dashboardCustomers,
      'name': tr('عرض عدد العملاء'),
      'category': 'dashboard',
    },
    {
      'code': dashboardChart,
      'name': tr('عرض الرسوم البيانية'),
      'category': 'dashboard',
    },
    {
      'code': dashboardTopProducts,
      'name': tr('أفضل المنتجات مبيعاً'),
      'category': 'dashboard',
    },
    {
      'code': dashboardAlerts,
      'name': tr('تنبيهات المخزون'),
      'category': 'dashboard',
    },
    {
      'code': dashboardPendingOrders,
      'name': tr('الطلبات المعلقة'),
      'category': 'dashboard',
    },

    // ── Inventory ──
    {'code': inventoryView, 'name': tr('عرض المخزون'), 'category': 'inventory'},
    {'code': inventoryEdit, 'name': tr('تعديل المخزون'), 'category': 'inventory'},
    {
      'code': inventoryTransfer,
      'name': tr('تحويل بين المخازن'),
      'category': 'inventory',
    },
    {
      'code': warehousesManage,
      'name': tr('إدارة المستودعات'),
      'category': 'inventory',
    },

    // ── Products ──
    {'code': productsView, 'name': tr('عرض المنتجات'), 'category': 'products'},
    {'code': productsAdd, 'name': tr('إضافة منتجات'), 'category': 'products'},
    {'code': productsEdit, 'name': tr('تعديل منتجات'), 'category': 'products'},
    {'code': productsDelete, 'name': tr('حذف منتجات'), 'category': 'products'},
    {
      'code': productsImport,
      'name': tr('استيراد من Excel'),
      'category': 'products',
    },
    {'code': productsExport, 'name': tr('تصدير إلى Excel'), 'category': 'products'},
    {'code': productsBarcode, 'name': tr('إدارة الباركود'), 'category': 'products'},
    {
      'code': productsImage,
      'name': tr('إضافة/تعديل الصورة'),
      'category': 'products',
    },
    {'code': productsUnits, 'name': tr('إدارة الوحدات'), 'category': 'products'},
    {'code': productsExpiry, 'name': tr('إدارة الصلاحية'), 'category': 'products'},
    {'code': productsLock, 'name': tr('قفل/فتح المنتج'), 'category': 'products'},
    {'code': productsPriceView, 'name': tr('عرض الأسعار'), 'category': 'products'},
    {'code': productsCostView, 'name': tr('عرض التكلفة'), 'category': 'products'},
    {'code': productsStockView, 'name': tr('عرض المخزون'), 'category': 'products'},
    {
      'code': productsScaleUpload,
      'name': tr('ترحيل المنتجات للميزان'),
      'category': 'products',
    },
    {
      'code': priceListsManage,
      'name': tr('إدارة قوائم الأسعار'),
      'category': 'products',
    },

    // ── Categories ──
    {'code': categoriesView, 'name': tr('عرض التصنيفات'), 'category': 'categories'},
    {'code': categoriesAdd, 'name': tr('إضافة تصنيفات'), 'category': 'categories'},
    {'code': categoriesEdit, 'name': tr('تعديل تصنيفات'), 'category': 'categories'},
    {'code': categoriesDelete, 'name': tr('حذف تصنيفات'), 'category': 'categories'},
    {
      'code': categoriesScaleUpload,
      'name': tr('ترحيل تصنيف للميزان'),
      'category': 'categories',
    },

    // ── Customers ──
    {'code': customersView, 'name': tr('عرض العملاء'), 'category': 'customers'},
    {'code': customersAdd, 'name': tr('إضافة عملاء'), 'category': 'customers'},
    {'code': customersEdit, 'name': tr('تعديل العملاء'), 'category': 'customers'},
    {'code': customersDelete, 'name': tr('حذف عملاء'), 'category': 'customers'},
    {
      'code': customerMessageSend,
      'name': tr('إرسال مستندات العميل على واتساب'),
      'category': 'customers',
    },

    // ── Suppliers ──
    {'code': suppliersView, 'name': tr('عرض الموردين'), 'category': 'suppliers'},
    {'code': suppliersAdd, 'name': tr('إضافة موردين'), 'category': 'suppliers'},
    {'code': suppliersEdit, 'name': tr('تعديل الموردين'), 'category': 'suppliers'},
    {'code': suppliersDelete, 'name': tr('حذف موردين'), 'category': 'suppliers'},

    // ── Purchases ──
    {
      'code': purchasesView,
      'name': tr('عرض فواتير الشراء'),
      'category': 'purchases',
    },
    {
      'code': purchasesCreate,
      'name': tr('إنشاء فواتير شراء'),
      'category': 'purchases',
    },
    {
      'code': purchasesEdit,
      'name': tr('تعديل فواتير شراء'),
      'category': 'purchases',
    },
    {
      'code': purchasesDelete,
      'name': tr('حذف فواتير شراء'),
      'category': 'purchases',
    },
    {
      'code': purchasesPrint,
      'name': tr('طباعة فواتير الشراء'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnView,
      'name': tr('عرض مرتجعات المشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnCreate,
      'name': tr('إنشاء مرتجع مشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnEdit,
      'name': tr('تعديل مرتجع مشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnDelete,
      'name': tr('حذف مرتجع مشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnPrint,
      'name': tr('طباعة مرتجع مشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchasesReturnApprove,
      'name': tr('مراجعة واعتماد مرتجع مشتريات'),
      'category': 'purchases',
    },
    {
      'code': purchaseOrdersView,
      'name': tr('عرض أوامر الشراء'),
      'category': 'purchases',
    },

    // ── Sales ──
    {'code': salesView, 'name': tr('عرض فواتير البيع'), 'category': 'sales'},
    {'code': salesCreate, 'name': tr('إنشاء فاتورة مبيعات'), 'category': 'sales'},
    {'code': salesEdit, 'name': tr('تعديل فواتير البيع'), 'category': 'sales'},
    {'code': salesDelete, 'name': tr('حذف فواتير البيع'), 'category': 'sales'},
    {'code': salesPrint, 'name': tr('طباعة فواتير البيع'), 'category': 'sales'},
    {
      'code': salesAmountsView,
      'name': tr('عرض المبالغ المالية'),
      'category': 'sales',
    },
    {
      'code': salesReturnView,
      'name': tr('عرض فواتير المرتجعات'),
      'category': 'sales',
    },
    {
      'code': salesReturnCreate,
      'name': tr('إنشاء مرتجع مبيعات'),
      'category': 'sales',
    },
    {
      'code': salesReturnEdit,
      'name': tr('تعديل فواتير المرتجعات'),
      'category': 'sales',
    },
    {
      'code': salesReturnDelete,
      'name': tr('حذف فواتير المرتجعات'),
      'category': 'sales',
    },
    {
      'code': salesReturnPrint,
      'name': tr('طباعة فواتير المرتجعات'),
      'category': 'sales',
    },
    {
      'code': salesReturnApprove,
      'name': tr('مراجعة واعتماد مرتجع مبيعات'),
      'category': 'sales',
    },
    {'code': salesOrdersView, 'name': tr('عرض طلبات البيع'), 'category': 'sales'},

    // ── Offers ──
    {'code': offersView, 'name': tr('عرض العروض'), 'category': 'offers'},
    {'code': offersCreate, 'name': tr('إنشاء عروض'), 'category': 'offers'},
    {'code': offersEdit, 'name': tr('تعديل العروض'), 'category': 'offers'},
    {'code': offersDelete, 'name': tr('حذف العروض'), 'category': 'offers'},

    // ── Delivery ──
    {'code': deliveryView, 'name': tr('عرض التوصيل'), 'category': 'delivery'},
    {'code': deliveryManage, 'name': tr('إدارة التوصيل'), 'category': 'delivery'},
    {'code': deliveryCourierManage, 'name': tr('إدارة المناديب'), 'category': 'delivery'},

    // ── Tables ──
    {'code': tablesView, 'name': tr('عرض الطاولات'), 'category': 'tables'},
    {'code': tablesManage, 'name': tr('إدارة الطاولات'), 'category': 'tables'},
    {'code': tablesPosAccess, 'name': tr('الوصول لنقطة بيع الطاولات'), 'category': 'tables'},
    {'code': tablesAddItems, 'name': tr('إضافة أصناف للطاولة'), 'category': 'tables'},
    {'code': tablesCheckout, 'name': tr('تسوية حساب الطاولة'), 'category': 'tables'},
    {'code': tablesTransfer, 'name': tr('نقل طلب بين الطاولات'), 'category': 'tables'},
    {'code': tablesCancel, 'name': tr('إلغاء/مسح طلب الطاولة'), 'category': 'tables'},
    {'code': tablesPrintBill, 'name': tr('طباعة فاتورة الطاولة'), 'category': 'tables'},
    {'code': tablesDiscount, 'name': tr('خصمٌ على طلب الطاولة'), 'category': 'tables'},
    {'code': tablesMerge, 'name': tr('دمج طلبات الطاولات'), 'category': 'tables'},
    {'code': tablesSplitBill, 'name': tr('تقسيم حساب الطاولة'), 'category': 'tables'},
    {'code': tablesReserve, 'name': tr('حجز طاولة'), 'category': 'tables'},

    // ── Kitchen ──
    {'code': kitchenView, 'name': tr('عرض شاشة المطبخ'), 'category': 'kitchen'},
    {'code': kitchenManage, 'name': tr('إدارة طلبات المطبخ'), 'category': 'kitchen'},
    {'code': kdsSettings, 'name': tr('إعدادات شاشة المطبخ (KDS)'), 'category': 'kitchen'},

    // ── Treasury ──
    {'code': treasuryView, 'name': tr('عرض الخزينة'), 'category': 'treasury'},
    {'code': treasuryManage, 'name': tr('إدارة الخزينة'), 'category': 'treasury'},
    {
      'code': treasuryReceiptsCreate,
      'name': tr('إنشاء سند قبض'),
      'category': 'treasury',
    },
    {
      'code': treasuryPaymentsCreate,
      'name': tr('إنشاء سند صرف'),
      'category': 'treasury',
    },
    {
      'code': treasuryTransfer,
      'name': tr('تحويل بين الخزائن'),
      'category': 'treasury',
    },
    {
      'code': treasuryBalanceView,
      'name': tr('عرض الأرصدة'),
      'category': 'treasury',
    },
    {
      'code': treasuryTransactionsView,
      'name': tr('عرض الحركات'),
      'category': 'treasury',
    },
    {
      'code': treasuryCommission,
      'name': tr('تعيين نسبة عمولة التحصيل'),
      'category': 'treasury',
    },
    {
      'code': commercialPapersManage,
      'name': tr('إدارة الأوراق التجارية'),
      'category': 'treasury',
    },

    // ── HR ──
    {'code': hrView, 'name': tr('الوصول لشاشة الموظفين'), 'category': 'hr'},
    {'code': hrManage, 'name': tr('إدارة بيانات الموظفين'), 'category': 'hr'},
    {'code': hrAdvanceRecord, 'name': tr('تسجيل السلف'), 'category': 'hr'},
    {'code': hrPayrollProcess, 'name': tr('إصدار مسيرات الرواتب'), 'category': 'hr'},
    {'code': hrAttendanceView, 'name': tr('عرض الحضور والورديات'), 'category': 'hr'},
    {'code': hrAttendanceEdit, 'name': tr('إدخال الحضور وتصحيحه'), 'category': 'hr'},
    {'code': hrLeaveRequest, 'name': tr('تقديم طلبات الإجازة'), 'category': 'hr'},
    {'code': hrLeaveApprove, 'name': tr('اعتماد طلبات الإجازة'), 'category': 'hr'},
    {'code': hrShiftsManage, 'name': tr('إدارة الورديات'), 'category': 'hr'},
    {'code': hrPayrollView, 'name': tr('عرض الرواتب'), 'category': 'hr'},
    {'code': hrPayrollEdit, 'name': tr('إعداد المسيرات وتسويتها'), 'category': 'hr'},
    {'code': hrPayrollApprove, 'name': tr('اعتماد المسيرات'), 'category': 'hr'},
    {'code': hrPayrollPost, 'name': tr('ترحيل المسيرات وصرفها وعكسها'), 'category': 'hr'},
    {'code': hrAdvancesManage, 'name': tr('إدارة السلف والقروض'), 'category': 'hr'},
    {'code': hrCommissionsManage, 'name': tr('إدارة خطط العمولات'), 'category': 'hr'},

    // ── Reports ──
    {'code': reportsView, 'name': tr('عرض التقارير'), 'category': 'reports'},
    {'code': reportsExport, 'name': tr('تصدير التقارير'), 'category': 'reports'},
    {'code': reportsSales, 'name': tr('تقرير المبيعات'), 'category': 'reports'},
    {
      'code': reportsPurchases,
      'name': tr('تقرير المشتريات'),
      'category': 'reports',
    },
    {'code': reportsInventory, 'name': tr('تقرير المخزون'), 'category': 'reports'},
    {'code': reportsTreasury, 'name': tr('تقرير الخزينة'), 'category': 'reports'},
    {'code': reportsCustomers, 'name': tr('تقرير العملاء'), 'category': 'reports'},
    {'code': reportsSuppliers, 'name': tr('تقرير الموردين'), 'category': 'reports'},
    {'code': reportsProfit, 'name': tr('تقرير الأرباح'), 'category': 'reports'},
    {'code': reportsProducts, 'name': tr('تقرير المنتجات'), 'category': 'reports'},
    {'code': reportsShifts, 'name': tr('تقرير الورديات'), 'category': 'reports'},
    {'code': reportsTaxes, 'name': tr('تقرير الضرائب'), 'category': 'reports'},
    {
      'code': reportsCategoryProfit,
      'name': tr('تقرير أرباح التصنيفات'),
      'category': 'reports',
    },
    {
      'code': reportsDeliveryRecon,
      'name': tr('مطابقة حسابات شركات التوصيل'),
      'category': 'reports',
    },
    {
      'code': reportsOrderType,
      'name': tr('تقرير المبيعات حسب نوع الطلب'),
      'category': 'reports',
    },

    // ── Settings ──
    {'code': settingsView, 'name': tr('عرض الإعدادات'), 'category': 'settings'},
    {'code': settingsEdit, 'name': tr('تعديل الإعدادات'), 'category': 'settings'},
    {'code': settingsCompany, 'name': tr('إعدادات الشركة'), 'category': 'settings'},
    {
      'code': settingsReceipt,
      'name': tr('إعدادات الإيصال'),
      'category': 'settings',
    },
    {
      'code': settingsPrinter,
      'name': tr('إعدادات الطابعة والأجهزة'),
      'category': 'settings',
    },
    {'code': settingsScale, 'name': tr('إعدادات الميزان'), 'category': 'settings'},
    {'code': settingsBackup, 'name': tr('النسخ الاحتياطي'), 'category': 'settings'},
    {'code': settingsRestore, 'name': tr('الاستعادة'), 'category': 'settings'},
    {'code': settingsTax, 'name': tr('إعدادات الضريبة'), 'category': 'settings'},
    {
      'code': settingsCurrency,
      'name': tr('إعدادات العملة'),
      'category': 'settings',
    },

    // ── Users ──
    {'code': usersManage, 'name': tr('إدارة المستخدمين'), 'category': 'users'},
    {
      'code': rolesManage,
      'name': tr('إدارة الأدوار والصلاحيات'),
      'category': 'users',
    },
    {
      'code': usersManageCrossBranch,
      'name': tr('إنشاء/تعديل المستخدمين من جهاز عميل (عبر-فروع)'),
      'category': 'users',
    },

    // ── System ──
    {'code': systemAuditLog, 'name': tr('سجل المراجعة'), 'category': 'system'},
    {
      'code': systemDatabase,
      'name': tr('إدارة قاعدة البيانات'),
      'category': 'system',
    },
    {'code': systemLicense, 'name': tr('إدارة الترخيص'), 'category': 'system'},
    {'code': systemUpdates, 'name': tr('تحديث النظام'), 'category': 'system'},
    {
      'code': systemSidebarOpen,
      'name': tr('فتح القائمة الجانبية بلا كلمة مرور'),
      'category': 'system',
    },

    // ── Audit ──
    {'code': auditView, 'name': tr('عرض سجل العمليات'), 'category': 'audit'},
    {
      'code': auditShiftBlind,
      'name': tr('إغلاق وردية (عد نقدي أعمى)'),
      'category': 'audit',
    },
    {
      'code': auditInvoiceUnlock,
      'name': tr('إلغاء قفل الفواتير'),
      'category': 'audit',
    },
    {
      'code': partiesCreditLimitBypass,
      'name': tr('تجاوز الحد الائتماني'),
      'category': 'audit',
    },

    // ── Loyalty ──
    {'code': loyaltyView, 'name': tr('عرض نقاط الولاء'), 'category': 'loyalty'},
    {
      'code': loyaltyManage,
      'name': tr('إدارة برامج الولاء'),
      'category': 'loyalty',
    },

    // ── Distribution ──
    {
      'code': distributionView,
      'name': tr('عرض التوزيع والمندوبين'),
      'category': 'distribution',
    },
    {
      'code': distributionManage,
      'name': tr('إدارة التوزيع والمسارات'),
      'category': 'distribution',
    },

    // ── E-Invoicing ──
    {
      'code': einvoiceView,
      'name': tr('عرض الفوترة الإلكترونية'),
      'category': 'einvoice',
    },
    {
      'code': einvoiceSubmit,
      'name': tr('إرسال فاتورة إلكترونية'),
      'category': 'einvoice',
    },
    {
      'code': einvoiceCancel,
      'name': tr('إلغاء فاتورة إلكترونية'),
      'category': 'einvoice',
    },

    // ── Accounting ──
    {
      'code': accountingView,
      'name': tr('عرض الحسابات والقيود'),
      'category': 'accounting',
    },
    {
      'code': accountingManage,
      'name': tr('إدارة القيود المحاسبية'),
      'category': 'accounting',
    },
    {
      'code': accountingJournal,
      'name': tr('إنشاء قيود يومية'),
      'category': 'accounting',
    },
    {
      'code': accountingJournalApprove,
      'name': tr('اعتماد القيود اليومية'),
      'category': 'accounting',
    },

    // ── Manufacturing ──
    {
      'code': manufacturingView,
      'name': tr('عرض أوامر التصنيع'),
      'category': 'manufacturing',
    },
    {
      'code': manufacturingManage,
      'name': tr('إدارة التصنيع والمكونات'),
      'category': 'manufacturing',
    },

    // ── Fixed Assets ──
    {'code': assetsView, 'name': tr('عرض الأصول الثابتة'), 'category': 'assets'},
    {
      'code': assetsManage,
      'name': tr('إدارة الأصول الثابتة'),
      'category': 'assets',
    },
    {'code': assetsDepreciation, 'name': tr('تشغيل الإهلاك'), 'category': 'assets'},

    // ── Operational Expenses ──
    // فئةُ «المحاسبة»: تسجيلُ المصروف يرحّل قيدَ يوميّةٍ ويخصم من الخزنة،
    // والاعتمادُ فصلُ أدوارٍ لا فعلٌ محاسبيّ.
    {
      'code': expensesManage,
      'name': tr('تسجيل المصروفات التشغيلية'),
      'category': 'accounting',
    },
    {
      'code': expensesApprove,
      'name': tr('اعتماد وسداد المصروفات'),
      'category': 'accounting',
    },

    // ── Landed Cost ──
    // فئةُ «المشتريات» لا «المخزون»: الورقةُ تتبع فاتورةَ شراءٍ بعينها،
    // وفتحُ الشاشة نفسِه محكومٌ بـ`purchases_create`.
    {
      'code': landedCostApply,
      'name': tr('تطبيق ورقة التكاليف المحمَّلة'),
      'category': 'purchases',
    },

    // ── Analytics ──
    {
      'code': analyticsView,
      'name': tr('عرض لوحة التحليلات'),
      'category': 'analytics',
    },

    // ── Branches ──
    {'code': branchesManage, 'name': tr('إدارة الفروع'), 'category': 'branches'},

    // ── Navigation & Sidebar ──
    {'code': quotesView, 'name': tr('عرض عروض الأسعار'), 'category': 'sales'},
    {'code': returnsView, 'name': tr('عرض المرتجعات'), 'category': 'sales'},
    {'code': warehousesView, 'name': tr('عرض المستودعات'), 'category': 'inventory'},
    {'code': stockView, 'name': tr('عرض حركة المخزون'), 'category': 'inventory'},
    {'code': stockAudit, 'name': tr('الجرد الدوري'), 'category': 'inventory'},
    {'code': partiesView, 'name': tr('عرض الأطراف'), 'category': 'customers'},
    {'code': settingsAccess, 'name': tr('الوصول لشاشة الإعدادات'), 'category': 'settings'},
    {'code': settingsPosEdit, 'name': tr('تعديل إعدادات البيع السريع'), 'category': 'settings'},
    {'code': modifiersManage, 'name': tr('إدارة الإضافات والمعدلات'), 'category': 'settings'},

    // QA D1-008 (2026-05-15): the duplicate HR block that was here is
    // removed. The earlier block at L1156-1160 is the canonical source
    // (hrView/hrManage/hrAdvanceRecord/hrPayrollProcess). syncAllPermissions
    // dedupes by code anyway, but keeping two entries with slightly
    // different display names obscured the master-list audit and let the
    // second name silently override the first via code-key uniqueness.

    // ── Critical Financial Operations (عمليات مالية حرجة) ──
    {'code': deletePostedJournal, 'name': tr('حذف قيد يومية مرحّل'), 'category': 'critical_financial'},
    {'code': voidPaidInvoice, 'name': tr('إلغاء فاتورة مدفوعة بالكامل'), 'category': 'critical_financial'},
    {'code': modifyLockedInvoice, 'name': tr('تعديل فاتورة مقفلة/مرحّلة'), 'category': 'critical_financial'},
    {'code': deleteFiscalYear, 'name': tr('حذف سنة مالية'), 'category': 'critical_financial'},
    {'code': modifyClosedPeriod, 'name': tr('تعديل فترة محاسبية مغلقة'), 'category': 'critical_financial'},
    {'code': overrideCreditLimit, 'name': tr('تجاوز حد الائتمان للعميل'), 'category': 'critical_financial'},

    // ── Bookings (الحجوزات) — مواعيدُ الخدمة ──
    {'code': bookingsView, 'name': tr('عرض الحجوزات'), 'category': 'bookings'},
    {'code': bookingsAdd, 'name': tr('إضافة حجز'), 'category': 'bookings'},
    {'code': bookingsEdit, 'name': tr('تعديل بيانات الحجز'), 'category': 'bookings'},
    {'code': bookingsCancel, 'name': tr('إلغاء حجز'), 'category': 'bookings'},
    {'code': bookingsStatus, 'name': tr('تغيير حالة الحجز'), 'category': 'bookings'},
    {'code': bookingsAssign, 'name': tr('إسناد/نقل الحجز بين الموظفين'), 'category': 'bookings'},
    {'code': bookingsDeposit, 'name': tr('تحصيل ورد العربون'), 'category': 'bookings'},
    {'code': bookingsServicesManage, 'name': tr('إدارة الخدمات'), 'category': 'bookings'},
    {'code': bookingsResourcesManage, 'name': tr('إدارة الموظفين / الموارد'), 'category': 'bookings'},
    {'code': bookingsReports, 'name': tr('تقارير الحجوزات'), 'category': 'bookings'},
    {'code': bookingsSettings, 'name': tr('إعدادات الحجوزات'), 'category': 'bookings'},
    ...warehouseMobilePermissionEntries,
    ...mirrorConsolePermissionEntries,
  ];

  /// All category names in Arabic
  static Map<String, String> get categoryNames => {
    'pos': tr('البيع السريع'),
    'dashboard': tr('لوحة التحكم'),
    'inventory': tr('المخزون'),
    'products': tr('المنتجات'),
    'categories': tr('التصنيفات'),
    'customers': tr('العملاء'),
    'suppliers': tr('الموردين'),
    'purchases': tr('المشتريات'),
    'sales': tr('فواتير البيع'),
    'offers': tr('العروض'),
    'delivery': tr('التوصيل'),
    'tables': tr('الطاولات'),
    'kitchen': tr('المطبخ'),
    'treasury': tr('الخزينة'),
    'hr': tr('الموظفين'),
    'reports': tr('التقارير'),
    'settings': tr('الإعدادات'),
    'users': tr('المستخدمين'),
    'system': tr('النظام'),
    'audit': tr('المراجعة والتدقيق'),
    'loyalty': tr('نقاط الولاء'),
    'distribution': tr('التوزيع'),
    'einvoice': tr('الفوترة الإلكترونية'),
    'accounting': tr('المحاسبة'),
    'manufacturing': tr('التصنيع'),
    'assets': tr('الأصول الثابتة'),
    'analytics': tr('التحليلات'),
    'branches': tr('الفروع'),
    'critical_financial': tr('عمليات مالية حرجة'),
    'bookings': tr('الحجوزات'),
    'warehouse_mobile': tr('تطبيق المخازن والأجهزة'),
  };
}

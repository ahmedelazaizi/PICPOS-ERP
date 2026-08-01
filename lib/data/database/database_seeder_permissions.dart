// =======================================================================
// DATABASE SEEDER - PERMISSIONS
// Extracted from database_seeder.dart - Sprint 13 God File Splitting
// =======================================================================

part of 'database.dart';

/// Extension for Roles and Permissions seeding operations
extension DatabaseSeederPermissions on AppDatabase {
  /// Seed default roles and permissions
  Future<void> seedRolesAndPermissions() async {
    final List<Map<String, String>> permissionsList = [
      // POS
      {'code': 'pos_access', 'name': 'الوصول لنقطة البيع', 'category': 'pos'},
      {'code': 'pos_discount', 'name': 'تطبيق خصم', 'category': 'pos'},
      {'code': 'pos_return', 'name': 'مرتجعات المبيعات', 'category': 'pos'},
      {'code': 'pos_exchange', 'name': 'استبدال المنتجات', 'category': 'pos'},
      {'code': 'pos_hold_order', 'name': 'تعليق الفواتير', 'category': 'pos'},
      {
        'code': 'pos_work_order',
        'name': 'طباعة أوامر الشغل',
        'category': 'pos',
      },
      {'code': 'pos_open_drawer', 'name': 'فتح درج النقدية', 'category': 'pos'},
      {'code': 'pos_save', 'name': 'حفظ البيع', 'category': 'pos'},
      {'code': 'pos_print', 'name': 'طباعة الفاتورة', 'category': 'pos'},
      {'code': 'pos_price_edit', 'name': 'تعديل سعر الصنف', 'category': 'pos'},
      {
        'code': 'pos_tax_toggle',
        'name': 'تغيير حالة الضريبة',
        'category': 'pos',
      },
      {'code': 'pos_expense', 'name': 'إضافة مصروف سريع', 'category': 'pos'},
      {
        'code': 'pos_expense_type_select',
        'name': 'اختيار نوع المصروف',
        'category': 'pos',
      },
      {
        'code': 'pos_expense_description',
        'name': 'كتابة بيان المصروف',
        'category': 'pos',
      },
      {
        'code': 'pos_expense_delete',
        'name': 'حذف مصروف سابق',
        'category': 'pos',
      },
      {
        'code': 'pos_deleted_items',
        'name': 'عرض الأصناف المحذوفة',
        'category': 'pos',
      },
      {
        'code': 'pos_previous_invoices',
        'name': 'عرض الفواتير السابقة',
        'category': 'pos',
      },
      {
        'code': 'pos_edit_invoice',
        'name': 'تعديل فاتورة سابقة',
        'category': 'pos',
      },
      {'code': 'pos_cancel_invoice', 'name': 'إلغاء فاتورة', 'category': 'pos'},
      {'code': 'pos_delivery', 'name': 'طلبات التوصيل', 'category': 'pos'},
      {
        'code': 'pos_payment_methods',
        'name': 'تغيير طريقة الدفع',
        'category': 'pos',
      },
      {
        'code': 'pos_customer_add',
        'name': 'إضافة عميل من البيع',
        'category': 'pos',
      },
      {'code': 'pos_view_cost', 'name': 'عرض سعر التكلفة', 'category': 'pos'},
      {'code': 'pos_view_profit', 'name': 'عرض الربح', 'category': 'pos'},
      {'code': 'pos_quantity_edit', 'name': 'تعديل الكمية', 'category': 'pos'},
      {'code': 'pos_shift_close', 'name': 'إغلاق الوردية', 'category': 'pos'},

      // POS Header \u0026 Screen (v35)
      {'code': 'pos_table_select', 'name': 'اختيار طاولة', 'category': 'pos'},
      {
        'code': 'pos_grid_toggle',
        'name': 'تكبير/تصغير السلة',
        'category': 'pos',
      },
      {'code': 'pos_booking', 'name': 'حجز مسبق', 'category': 'pos'},
      {'code': 'pos_offers', 'name': 'عرض العروض', 'category': 'pos'},
      {'code': 'pos_table_bill', 'name': 'طلب حساب الطاولة', 'category': 'pos'},
      {'code': 'pos_keyboard', 'name': 'فتح لوحة المفاتيح', 'category': 'pos'},
      {'code': 'pos_notifications', 'name': 'عرض الإشعارات', 'category': 'pos'},
      {
        'code': 'pos_low_stock_alert',
        'name': 'تنبيه نقص المخزون',
        'category': 'pos',
      },
      {
        'code': 'pos_barcode_scan',
        'name': 'البحث بالباركود',
        'category': 'pos',
      },
      {'code': 'pos_add_product', 'name': 'إضافة صنف للسلة', 'category': 'pos'},
      {'code': 'pos_clear_cart', 'name': 'مسح السلة', 'category': 'pos'},
      {
        'code': 'pos_remove_item',
        'name': 'حذف صنف من السلة',
        'category': 'pos',
      },
      {'code': 'pos_note_add', 'name': 'إضافة ملاحظة للصنف', 'category': 'pos'},
      {
        'code': 'pos_weight_dialog',
        'name': 'استخدام الميزان',
        'category': 'pos',
      },
      {
        'code': 'pos_deleted_items',
        'name': 'عرض الأصناف المحذوفة',
        'category': 'pos',
      },
      // v36 permissions
      {
        'code': 'pos_restore_held',
        'name': 'استرجاع فاتورة معلقة',
        'category': 'pos',
      },
      {
        'code': 'pos_delete_held',
        'name': 'حذف من الفواتير المعلقة',
        'category': 'pos',
      },
      {
        'code': 'pos_closing_view_details',
        'name': 'عرض تفاصيل الإغلاق المالية',
        'category': 'pos',
      },
      // v37+ — cart item actions & search
      {'code': 'pos_search', 'name': 'البحث عن منتج', 'category': 'pos'},
      {'code': 'pos_customer_select', 'name': 'اختيار عميل', 'category': 'pos'},
      {'code': 'pos_item_minus', 'name': 'نقص كمية صنف', 'category': 'pos'},
      {'code': 'pos_item_plus', 'name': 'زيادة كمية صنف', 'category': 'pos'},

      // DASHBOARD
      {
        'code': 'dashboard_access',
        'name': 'الوصول للوحة التحكم',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_sales_today',
        'name': 'عرض مبيعات اليوم',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_sales_total',
        'name': 'عرض إجمالي المبيعات',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_profit',
        'name': 'عرض الأرباح',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_customers',
        'name': 'عرض عدد العملاء',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_chart',
        'name': 'عرض الرسوم البيانية',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_top_products',
        'name': 'أفضل المنتجات مبيعاً',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_alerts',
        'name': 'تنبيهات المخزون',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_pending_orders',
        'name': 'الطلبات المعلقة',
        'category': 'dashboard',
      },

      // INVENTORY \u0026 PRODUCTS
      {
        'code': 'inventory_view',
        'name': 'عرض المخزون',
        'category': 'inventory',
      },
      {
        'code': 'inventory_edit',
        'name': 'تعديل المخزون',
        'category': 'inventory',
      },
      {'code': 'products_view', 'name': 'عرض المنتجات', 'category': 'products'},
      {'code': 'products_add', 'name': 'إضافة منتجات', 'category': 'products'},
      {'code': 'products_edit', 'name': 'تعديل منتجات', 'category': 'products'},
      {'code': 'products_delete', 'name': 'حذف منتجات', 'category': 'products'},
      {
        'code': 'products_import',
        'name': 'استيراد من Excel',
        'category': 'products',
      },
      {
        'code': 'products_export',
        'name': 'تصدير إلى Excel',
        'category': 'products',
      },
      {
        'code': 'products_barcode',
        'name': 'إدارة الباركود',
        'category': 'products',
      },
      {'code': 'products_image', 'name': 'إدارة الصور', 'category': 'products'},
      {
        'code': 'products_price_view',
        'name': 'عرض الأسعار',
        'category': 'products',
      },
      {
        'code': 'products_cost_view',
        'name': 'عرض التكلفة',
        'category': 'products',
      },
      {
        'code': 'products_stock_view',
        'name': 'عرض المخزون',
        'category': 'products',
      },
      {
        'code': 'products_units',
        'name': 'إدارة الوحدات',
        'category': 'products',
      },
      {
        'code': 'products_expiry',
        'name': 'إدارة الصلاحية',
        'category': 'products',
      },
      {
        'code': 'products_lock',
        'name': 'قفل/فتح المنتج',
        'category': 'products',
      },
      {
        'code': 'products_scale_upload',
        'name': 'ترحيل المنتجات للميزان',
        'category': 'products',
      },
      {
        'code': 'categories_view',
        'name': 'عرض التصنيفات',
        'category': 'categories',
      },
      {
        'code': 'categories_add',
        'name': 'إضافة تصنيفات',
        'category': 'categories',
      },
      {
        'code': 'categories_edit',
        'name': 'تعديل تصنيفات',
        'category': 'categories',
      },
      {
        'code': 'categories_delete',
        'name': 'حذف تصنيفات',
        'category': 'categories',
      },
      {
        'code': 'categories_scale_upload',
        'name': 'ترحيل تصنيف للميزان',
        'category': 'categories',
      },

      // PARTIES
      {
        'code': 'customers_view',
        'name': 'عرض العملاء',
        'category': 'customers',
      },
      {'code': 'customers_add', 'name': 'إضافة عملاء', 'category': 'customers'},
      {
        'code': 'customers_edit',
        'name': 'تعديل العملاء',
        'category': 'customers',
      },
      {
        'code': 'customers_delete',
        'name': 'حذف عملاء',
        'category': 'customers',
      },
      {
        'code': 'suppliers_view',
        'name': 'عرض الموردين',
        'category': 'suppliers',
      },
      {
        'code': 'suppliers_add',
        'name': 'إضافة موردين',
        'category': 'suppliers',
      },
      {
        'code': 'suppliers_edit',
        'name': 'تعديل الموردين',
        'category': 'suppliers',
      },
      {
        'code': 'suppliers_delete',
        'name': 'حذف موردين',
        'category': 'suppliers',
      },

      // PURCHASES \u0026 SALES
      {
        'code': 'purchases_view',
        'name': 'عرض فواتير الشراء',
        'category': 'purchases',
      },
      {
        'code': 'purchases_create',
        'name': 'إنشاء فواتير شراء',
        'category': 'purchases',
      },
      {
        'code': 'purchases_edit',
        'name': 'تعديل فواتير شراء',
        'category': 'purchases',
      },
      {
        'code': 'purchases_delete',
        'name': 'حذف فواتير شراء',
        'category': 'purchases',
      },
      // Spec 084 — the seeder previously omitted `sales_create` from the
      // permission rows. Even though `cashierPermsIndices` referenced it,
      // the role-grant loop's `if (permMap.containsKey(code))` silently
      // skipped it because the perm row didn't exist yet. The catch-all
      // syncAllPermissions step inserted the perm later, but by then the
      // role-grant pass had already finished — so fresh installs ended
      // up with cashiers who couldn't sell under Spec 077. Seeding the
      // row HERE closes the gap.
      {'code': 'sales_create', 'name': 'إنشاء فاتورة مبيعات', 'category': 'sales'},
      {'code': 'sales_view', 'name': 'عرض فواتير البيع', 'category': 'sales'},
      {'code': 'sales_edit', 'name': 'تعديل فواتير البيع', 'category': 'sales'},
      {'code': 'sales_delete', 'name': 'حذف فواتير البيع', 'category': 'sales'},
      {
        'code': 'sales_print',
        'name': 'طباعة فواتير البيع',
        'category': 'sales',
      },
      {
        'code': 'sales_amounts_view',
        'name': 'عرض المبالغ المالية',
        'category': 'sales',
      },

      // TREASURY
      {'code': 'treasury_view', 'name': 'عرض الخزينة', 'category': 'treasury'},
      {
        'code': 'treasury_manage',
        'name': 'إدارة الخزينة',
        'category': 'treasury',
      },
      {
        'code': 'treasury_receipts_create',
        'name': 'إنشاء سند قبض',
        'category': 'treasury',
      },
      {
        'code': 'treasury_payments_create',
        'name': 'إنشاء سند صرف',
        'category': 'treasury',
      },
      {
        'code': 'treasury_transfer',
        'name': 'تحويل بين الخزائن',
        'category': 'treasury',
      },
      {
        'code': 'treasury_balance_view',
        'name': 'عرض الأرصدة',
        'category': 'treasury',
      },
      {
        'code': 'treasury_transactions_view',
        'name': 'عرض الحركات',
        'category': 'treasury',
      },

      // OFFERS
      {'code': 'offers_view', 'name': 'عرض العروض', 'category': 'offers'},
      {'code': 'offers_create', 'name': 'إنشاء عروض', 'category': 'offers'},
      {'code': 'offers_edit', 'name': 'تعديل العروض', 'category': 'offers'},
      {'code': 'offers_delete', 'name': 'حذف العروض', 'category': 'offers'},

      // DELIVERY
      {'code': 'delivery_view', 'name': 'عرض التوصيل', 'category': 'delivery'},
      {
        'code': 'delivery_manage',
        'name': 'إدارة التوصيل',
        'category': 'delivery',
      },

      // TABLES
      {'code': 'tables_view', 'name': 'عرض الطاولات', 'category': 'tables'},
      {'code': 'tables_manage', 'name': 'إدارة الطاولات', 'category': 'tables'},

      // KITCHEN
      {
        'code': 'kitchen_view',
        'name': 'عرض شاشة المطبخ',
        'category': 'kitchen',
      },

      // HR
      {'code': 'hr_view', 'name': 'عرض الموظفين', 'category': 'hr'},
      {'code': 'hr_manage', 'name': 'إدارة الموظفين', 'category': 'hr'},

      // REPORTS
      {'code': 'reports_view', 'name': 'عرض التقارير', 'category': 'reports'},
      {
        'code': 'reports_export',
        'name': 'تصدير التقارير',
        'category': 'reports',
      },
      {
        'code': 'reports_sales',
        'name': 'تقرير المبيعات',
        'category': 'reports',
      },
      {
        'code': 'reports_purchases',
        'name': 'تقرير المشتريات',
        'category': 'reports',
      },
      {
        'code': 'reports_inventory',
        'name': 'تقرير المخزون',
        'category': 'reports',
      },
      {
        'code': 'reports_treasury',
        'name': 'تقرير الخزينة',
        'category': 'reports',
      },
      {
        'code': 'reports_customers',
        'name': 'تقرير العملاء',
        'category': 'reports',
      },
      {
        'code': 'reports_suppliers',
        'name': 'تقرير الموردين',
        'category': 'reports',
      },
      {
        'code': 'reports_profit',
        'name': 'تقرير الأرباح',
        'category': 'reports',
      },
      {
        'code': 'reports_products',
        'name': 'تقرير المنتجات',
        'category': 'reports',
      },
      {
        'code': 'reports_shifts',
        'name': 'تقرير الورديات',
        'category': 'reports',
      },
      {'code': 'reports_taxes', 'name': 'تقرير الضرائب', 'category': 'reports'},

      // SETTINGS
      {
        'code': 'settings_view',
        'name': 'عرض الإعدادات',
        'category': 'settings',
      },
      {
        'code': 'settings_edit',
        'name': 'تعديل الإعدادات',
        'category': 'settings',
      },
      {
        'code': 'settings_company',
        'name': 'إعدادات الشركة',
        'category': 'settings',
      },
      {
        'code': 'settings_receipt',
        'name': 'إعدادات الفاتورة',
        'category': 'settings',
      },
      {
        'code': 'settings_printer',
        'name': 'إعدادات الطابعة والأجهزة',
        'category': 'settings',
      },
      {
        'code': 'settings_scale',
        'name': 'إعدادات الميزان',
        'category': 'settings',
      },
      {
        'code': 'settings_backup',
        'name': 'النسخ الاحتياطي',
        'category': 'settings',
      },
      {'code': 'settings_restore', 'name': 'الاستعادة', 'category': 'settings'},
      {
        'code': 'settings_tax',
        'name': 'إعدادات الضريبة',
        'category': 'settings',
      },
      {
        'code': 'settings_currency',
        'name': 'إعدادات العملة',
        'category': 'settings',
      },

      // USERS & SYSTEM
      {'code': 'users_manage', 'name': 'إدارة المستخدمين', 'category': 'users'},
      {
        'code': 'roles_manage',
        'name': 'إدارة الأدوار والصلاحيات',
        'category': 'users',
      },
      {
        'code': 'system_audit_log',
        'name': 'سجل المراجعة',
        'category': 'system',
      },
      {'code': 'audit_view', 'name': 'عرض سجل العمليات', 'category': 'audit'},
      {
        'code': 'system_database',
        'name': 'إدارة قاعدة البيانات',
        'category': 'system',
      },
      {'code': 'system_license', 'name': 'إدارة الترخيص', 'category': 'system'},
      {'code': 'system_updates', 'name': 'تحديث النظام', 'category': 'system'},

      // BRANCHES & ANALYTICS
      {'code': 'branches_manage', 'name': 'إدارة الفروع', 'category': 'settings'},
      {'code': 'analytics_view', 'name': 'عرض التحليلات', 'category': 'reports'},

      // Spec 077 Batch 0.5 — 4 new codes gating server endpoints.
      // Source of truth: specs/077-server-perms-endpoint-sweep/contracts/endpoint-permission-map.md §8.
      {'code': 'pos_shift_open', 'name': 'فتح الوردية', 'category': 'pos'},
      {'code': 'warehouses_manage', 'name': 'إدارة المستودعات', 'category': 'inventory'},
      {'code': 'commercial_papers_manage', 'name': 'إدارة الأوراق التجارية', 'category': 'treasury'},
      {'code': 'price_lists_manage', 'name': 'إدارة قوائم الأسعار', 'category': 'products'},
    ];

    for (final perm in permissionsList) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // ROLES — insert with insertOrIgnore, then LOOKUP actual IDs
    // (PostgreSQL ON CONFLICT DO NOTHING returns 0 instead of rowid)
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'مدير النظام',
        description: const Value('صلاحيات كاملة للنظام'),
        isSystemRole: const Value(true),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'كاشير',
        description: const Value('نقطة البيع فقط'),
        isSystemRole: const Value(true),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'مخزني',
        description: const Value('إدارة المخزون والمنتجات'),
        isSystemRole: const Value(true),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'محاسب',
        description: const Value('التقارير والخزينة'),
        isSystemRole: const Value(true),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'مدير مالي',
        description: const Value('طبقة وصول غير مقيدة مالياً'),
        isSystemRole: const Value(true),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    // ── Editable default roles (isSystemRole: false) ──────────────────────
    // These can be customized by the user, unlike the system roles above.
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'كاشير متقدم',
        description: const Value('كاشير مع صلاحيات متقدمة للدفع والخصم والمرتجعات'),
        isSystemRole: const Value(false),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'مدير فرع',
        description: const Value('إدارة فرع كاملة مع صلاحيات مبيعات ومخزون وتقارير'),
        isSystemRole: const Value(false),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'محاسب متقدم',
        description: const Value('صلاحيات محاسبية متقدمة مع تحليلات وتقارير'),
        isSystemRole: const Value(false),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(roles).insert(
      RolesCompanion.insert(
        name: 'مدير مخزون',
        description: const Value('إدارة المخزون والتحويلات والمشتريات'),
        isSystemRole: const Value(false),
        globalId: Value(UuidV7.generate()),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    // Lookup actual IDs by name (works on both SQLite and PostgreSQL)
    final adminRole = await (select(roles)..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    final cashierRole = await (select(roles)..where((r) => r.name.equals('كاشير'))).getSingleOrNull();
    final stockKeeperRole = await (select(roles)..where((r) => r.name.equals('مخزني'))).getSingleOrNull();
    final accountantRole = await (select(roles)..where((r) => r.name.equals('محاسب'))).getSingleOrNull();
    final financialManagerRole = await (select(roles)..where((r) => r.name.equals('مدير مالي'))).getSingleOrNull();
    final advancedCashierRole = await (select(roles)..where((r) => r.name.equals('كاشير متقدم'))).getSingleOrNull();
    final branchManagerRole = await (select(roles)..where((r) => r.name.equals('مدير فرع'))).getSingleOrNull();
    final advancedAccountantRole = await (select(roles)..where((r) => r.name.equals('محاسب متقدم'))).getSingleOrNull();
    final inventoryManagerRole = await (select(roles)..where((r) => r.name.equals('مدير مخزون'))).getSingleOrNull();

    final adminRoleId = adminRole?.id ?? 0;
    final cashierRoleId = cashierRole?.id ?? 0;
    final stockKeeperRoleId = stockKeeperRole?.id ?? 0;
    final accountantRoleId = accountantRole?.id ?? 0;
    final financialManagerRoleId = financialManagerRole?.id ?? 0;
    final advancedCashierRoleId = advancedCashierRole?.id ?? 0;
    final branchManagerRoleId = branchManagerRole?.id ?? 0;
    final advancedAccountantRoleId = advancedAccountantRole?.id ?? 0;
    final inventoryManagerRoleId = inventoryManagerRole?.id ?? 0;

    // MAPPINGS
    final allPerms = await select(permissions).get();
    final permMap = {for (var p in allPerms) p.code: p.id};

    // Admin gets everything — EXCEPT criticalFinancialOps (Spec 062 / D1-004).
    // Segregation of duties: void-paid-invoice / modify-locked-invoice /
    // override-credit-limit / delete-posted-journal / delete-fiscal-year /
    // modify-closed-period must be explicitly assigned by an operator,
    // even to the system admin role. The runtime check at
    // permissions_dao.userHasPermission already exempts these codes from
    // the admin auto-bypass; this seeder change makes that exemption
    // bite at first-install time. Existing installs are unaffected
    // (rolePermissions rows already exist; insertOrIgnore is a no-op).
    if (adminRoleId > 0) {
      for (final p in allPerms) {
        if (PermissionCodes.criticalFinancialOps.contains(p.code)) {
          continue;
        }
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRoleId,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }

    // Cashier basic perms
    final cashierPermsIndices = [
      'pos_access',
      'pos_hold_order',
      'pos_save',
      'pos_print',
      // Spec 077 Batch 0.5 — cashier opens AND closes shifts; new symmetric pair.
      'pos_shift_open',
      'pos_shift_close',
      // Spec 084 — Spec 077 gates /api/sales POST on `sales_create`;
      // without it the entire POS save path 403s. `sales_view` is bundled
      // so the cashier can also list their previous invoices.
      'sales_create',
      'sales_view',
      // Spec 3c — الرئيسية بقت متبوّبة بـ`dashboard_access`؛ الكود ده
      // بيتمنح لكل دور تشغيلي عشان الترقية ما تسحبش الشاشة من حد.
      'dashboard_access',
    ];
    for (final code in cashierPermsIndices) {
      if (permMap.containsKey(code)) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: cashierRoleId,
            permissionId: permMap[code]!,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }

    // Stock keeper perms
    final stockPermsIndices = [
      'inventory_view',
      'inventory_edit',
      'products_view',
      'products_add',
      'products_edit',
      'suppliers_view',
      'purchases_create',
      'categories_view',
      // Spec 3c — نفس منحة dashboard_access للأدوار التشغيلية.
      'dashboard_access',
      // دفعة ٨ — الستة دول كانوا أكواد بلا إنفاذ، يعني الأعمدة والأقسام
      // اللي بيوصفوها كانت بتترسم لأي دور يقدر يفتح شاشة الأصناف. دلوقتي
      // بقى ليهم حرّاس حقيقيين، فلازم يتمنحوا للأدوار اللي بتعمل الشغل ده
      // النهارده — من غيرهم أمين المخزن هيلاقي عمود الرصيد مموّه بعد
      // الترقية، وده كسر شغل مش تأمين. السحب بعد كده قرار المدير من شاشة
      // «الأدوار والصلاحيات» — والمفاتيح بقت شغّالة فعلاً.
      'products_price_view',
      'products_cost_view',
      'products_stock_view',
      'products_lock',
      'products_expiry',
      'products_image',
    ];
    for (final code in stockPermsIndices) {
      if (permMap.containsKey(code)) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: stockKeeperRoleId,
            permissionId: permMap[code]!,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }

    // Accountant perms
    final accountantPermsIndices = [
      'reports_view',
      'reports_export',
      'treasury_view',
      'customers_view',
      'suppliers_view',
      'sales_view',
      'purchases_view',
      'dashboard_access',
      // Task 3d — عنصر قائمة «التحليلات» اتربط بكوده الخاص analytics_view
      // بدل reports_view العام (كان بيسيب رابط ميت لمين معاه reports_view
      // بس). محاسب والمدير المالي (اللي بيورّث المنحة دي تحت) كانوا
      // بيشوفوا الرابط فعلاً، فلازم ياخدوا الكود الحقيقي بدل ما يتسحب منهم.
      'analytics_view',
    ];
    for (final code in accountantPermsIndices) {
      if (permMap.containsKey(code)) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: accountantRoleId,
            permissionId: permMap[code]!,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        // Financial Manager gets all Accountant permissions plus inherently bypasses branches
        if (financialManagerRoleId > 0) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: financialManagerRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    // Spec 077 Batch 0.5 — Financial Manager-only extras beyond the
    // accountant base. Today only commercial-papers; add to this list
    // for any future FM-specific permissions.
    final financialManagerExtraPerms = [
      'commercial_papers_manage',
    ];
    if (financialManagerRoleId > 0) {
      for (final code in financialManagerExtraPerms) {
        if (permMap.containsKey(code)) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: financialManagerRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    // ── كاشير متقدم (Advanced Cashier) permissions ──
    // Spec 077 Batch 0.5: includes pos_shift_open; branchManager inherits
    // via spread below.
    final advancedCashierPerms = [
      'pos_access', 'pos_discount', 'pos_return', 'pos_payment_cash',
      'pos_payment_card', 'pos_hold_order', 'customers_view',
      'pos_shift_open', 'pos_shift_close',
      // Spec 084 — same gap as basic cashier; spreads into branchManagerPerms below.
      'sales_create', 'sales_view',
      // Spec 3c — dashboard_access؛ يورّث لمدير الفرع عبر الـ spread تحت.
      'dashboard_access',
    ];
    if (advancedCashierRoleId > 0) {
      for (final code in advancedCashierPerms) {
        if (permMap.containsKey(code)) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: advancedCashierRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    // ── مدير فرع (Branch Manager) permissions ──
    // All cashier permissions + management permissions
    final branchManagerPerms = [
      ...advancedCashierPerms,
      'inventory_view', 'reports_view', 'treasury_view',
      'pos_closing_view_details', 'products_add', 'branches_manage',
      'users_manage', 'sales_view', 'purchases_create', 'settings_view',
      // Task 3d — نفس منطق analytics_view في accountantPermsIndices فوق.
      'analytics_view',
      // دفعة ٨ — نفس سبب منحة أمين المخزن فوق: الدور ده عنده `products_add`
      // فبيفتح شاشة الأصناف ويشوف الأعمدة دي النهارده.
      'products_price_view', 'products_cost_view', 'products_stock_view',
      'products_lock', 'products_expiry', 'products_image',
    ];
    if (branchManagerRoleId > 0) {
      for (final code in branchManagerPerms) {
        if (permMap.containsKey(code)) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: branchManagerRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    // ── محاسب متقدم (Advanced Accountant) permissions ──
    final advancedAccountantPerms = [
      'treasury_view', 'reports_view', 'settings_view',
      'pos_closing_view_details', 'sales_view', 'purchases_create',
      'inventory_view', 'analytics_view',
      // Spec 3c — نفس منحة dashboard_access للأدوار التشغيلية.
      'dashboard_access',
      // Task 3d — عنصر قائمة «الفروع» اتربط بكوده الخاص branches_manage
      // بدل settings_view العام. الدور ده عنده settings_view فكان بيشوف
      // الرابط فعلاً، فلازم ياخد الكود الحقيقي بدل ما يتسحب منه.
      'branches_manage',
    ];
    if (advancedAccountantRoleId > 0) {
      for (final code in advancedAccountantPerms) {
        if (permMap.containsKey(code)) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: advancedAccountantRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    // ── مدير مخزون (Inventory Manager) permissions ──
    final inventoryManagerPerms = [
      'inventory_view', 'inventory_transfer', 'products_add',
      'purchases_create', 'reports_view', 'sales_view',
      // Spec 3c — نفس منحة dashboard_access للأدوار التشغيلية.
      'dashboard_access',
      // Task 3d — نفس منطق analytics_view في accountantPermsIndices فوق.
      'analytics_view',
      // دفعة ٨ — نفس سبب منحة أمين المخزن فوق (`products_add` بيفتح الشاشة).
      'products_price_view', 'products_cost_view', 'products_stock_view',
      'products_lock', 'products_expiry', 'products_image',
    ];
    if (inventoryManagerRoleId > 0) {
      for (final code in inventoryManagerPerms) {
        if (permMap.containsKey(code)) {
          await into(rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: inventoryManagerRoleId,
              permissionId: permMap[code]!,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    }

    await (update(users)..where((u) => u.username.equals('admin'))).write(
      UsersCompanion(roleId: Value(adminRoleId)),
    );
  }

  /// Seed v35 permissions for existing databases
  Future<void> seedV35Permissions() async {
    final List<Map<String, String>> newPerms = [
      // POS Header \u0026 Screen
      {'code': 'pos_table_select', 'name': 'اختيار طاولة', 'category': 'pos'},
      {
        'code': 'pos_grid_toggle',
        'name': 'تكبير/تصغير السلة',
        'category': 'pos',
      },
      {'code': 'pos_booking', 'name': 'حجز مسبق', 'category': 'pos'},
      {'code': 'pos_offers', 'name': 'عرض العروض', 'category': 'pos'},
      {'code': 'pos_table_bill', 'name': 'طلب حساب الطاولة', 'category': 'pos'},
      {'code': 'pos_keyboard', 'name': 'فتح لوحة المفاتيح', 'category': 'pos'},
      {'code': 'pos_notifications', 'name': 'عرض الإشعارات', 'category': 'pos'},
      {
        'code': 'pos_low_stock_alert',
        'name': 'تنبيه نقص المخزون',
        'category': 'pos',
      },
      {
        'code': 'pos_barcode_scan',
        'name': 'البحث بالباركود',
        'category': 'pos',
      },
      {'code': 'pos_add_product', 'name': 'إضافة صنف للسلة', 'category': 'pos'},
      {'code': 'pos_clear_cart', 'name': 'مسح السلة', 'category': 'pos'},
      {
        'code': 'pos_remove_item',
        'name': 'حذف صنف من السلة',
        'category': 'pos',
      },
      {'code': 'pos_note_add', 'name': 'إضافة ملاحظة للصنف', 'category': 'pos'},
      {
        'code': 'pos_weight_dialog',
        'name': 'استخدام الميزان',
        'category': 'pos',
      },
      {
        'code': 'pos_deleted_items',
        'name': 'عرض الأصناف المحذوفة',
        'category': 'pos',
      },
      // Scale Upload
      {
        'code': 'products_scale_upload',
        'name': 'ترحيل المنتجات للميزان',
        'category': 'products',
      },
      {
        'code': 'categories_scale_upload',
        'name': 'ترحيل تصنيف للميزان',
        'category': 'categories',
      },
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add all new permissions to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// v36: Seed held order granular permissions & closing blind mode
  Future<void> seedV36Permissions() async {
    final newPerms = [
      {
        'code': 'pos_restore_held',
        'name': 'استرجاع فاتورة معلقة',
        'category': 'pos',
      },
      {
        'code': 'pos_delete_held',
        'name': 'حذف من الفواتير المعلقة',
        'category': 'pos',
      },
      {
        'code': 'pos_closing_view_details',
        'name': 'عرض تفاصيل الإغلاق المالية',
        'category': 'pos',
      },
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add all new permissions to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// v37: Seed granular POS permissions (search, payments, item adjustments)
  Future<void> seedV37Permissions() async {
    final newPerms = [
      {
        'code': 'pos_search',
        'name': 'البحث اليدوي والباركود',
        'category': 'pos',
      },
      {
        'code': 'pos_quick_pay',
        'name': 'الدفع السريع (Quick Pay)',
        'category': 'pos',
      },
      {'code': 'pos_item_plus', 'name': 'زيادة كمية الصنف', 'category': 'pos'},
      {'code': 'pos_item_minus', 'name': 'نقص كمية الصنف', 'category': 'pos'},
      {'code': 'pos_payment_cash', 'name': 'الدفع النقدي', 'category': 'pos'},
      {'code': 'pos_payment_card', 'name': 'الدفع بالبطاقة', 'category': 'pos'},
      {'code': 'pos_payment_credit', 'name': 'الدفع الآجل', 'category': 'pos'},
      {
        'code': 'pos_payment_transfer',
        'name': 'الدفع بالتحويل',
        'category': 'pos',
      },
      {
        'code': 'pos_payment_multiple',
        'name': 'الدفع المتعدد',
        'category': 'pos',
      },
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add all new permissions to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// v39: Phase 4 - Fiscal Control & Auditing permissions
  Future<void> seedV39Permissions() async {
    final List<Map<String, String>> newPerms = [
      {
        'code': 'audit_shift_blind',
        'name': 'إغلاق وردية (عد نقدي أعمى)',
        'category': 'audit',
      },
      {
        'code': 'audit_invoice_unlock',
        'name': 'إلغاء قفل الفواتير',
        'category': 'audit',
      },
      {
        'code': 'parties_credit_limit_bypass',
        'name': 'تجاوز الحد الائتماني',
        'category': 'customers',
      },
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// seed multi-warehouse transfer permissions and profit reporting
  Future<void> seedV38Permissions() async {
    final newPerms = [
      {
        'code': 'inventory_transfer',
        'name': 'عمليات تحويل المخزون',
        'category': 'inventory',
      },
      {
        'code': 'reports_category_profit',
        'name': 'تقرير أرباح التصنيفات',
        'category': 'reports',
      },
      {
        'code': 'reports_delivery_recon',
        'name': 'مطابقة حسابات شركات التوصيل',
        'category': 'reports',
      },
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add all new permissions to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// v41: Comprehensive permission seeding — all PermissionCodes not yet in DB
  Future<void> seedV41Permissions() async {
    final newPerms = [
      // ── POS (missing) ──
      {
        'code': 'pos_daily_closing',
        'name': 'الإقفال اليومي',
        'category': 'pos',
      },
      {
        'code': 'view_daily_closing_details',
        'name': 'عرض تفاصيل الإقفال اليومي',
        'category': 'pos',
      },
      {'code': 'pos_split_payment', 'name': 'الدفع المقسم', 'category': 'pos'},
      {'code': 'pos_customer_select', 'name': 'اختيار عميل', 'category': 'pos'},

      // ── Dashboard (missing) ──
      {
        'code': 'dashboard_sales_total',
        'name': 'عرض إجمالي المبيعات',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_customers',
        'name': 'عرض عدد العملاء',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_chart',
        'name': 'عرض الرسوم البيانية',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_top_products',
        'name': 'أفضل المنتجات مبيعاً',
        'category': 'dashboard',
      },
      {
        'code': 'dashboard_pending_orders',
        'name': 'الطلبات المعلقة',
        'category': 'dashboard',
      },

      // ── Products (missing) ──
      {
        'code': 'products_units',
        'name': 'إدارة الوحدات',
        'category': 'products',
      },
      {
        'code': 'products_expiry',
        'name': 'إدارة الصلاحية',
        'category': 'products',
      },
      {
        'code': 'products_lock',
        'name': 'قفل/فتح المنتج',
        'category': 'products',
      },
      {
        'code': 'products_stock_view',
        'name': 'عرض المخزون',
        'category': 'products',
      },

      // ── Purchases (missing) ──
      {
        'code': 'purchases_delete',
        'name': 'حذف فواتير شراء',
        'category': 'purchases',
      },

      // ── Sales (missing) ──
      {
        'code': 'sales_print',
        'name': 'طباعة فواتير البيع',
        'category': 'sales',
      },

      // ── Offers ──
      {'code': 'offers_view', 'name': 'عرض العروض', 'category': 'offers'},
      {'code': 'offers_create', 'name': 'إنشاء عروض', 'category': 'offers'},
      {'code': 'offers_edit', 'name': 'تعديل العروض', 'category': 'offers'},
      {'code': 'offers_delete', 'name': 'حذف العروض', 'category': 'offers'},

      // ── Delivery ──
      {'code': 'delivery_view', 'name': 'عرض التوصيل', 'category': 'delivery'},
      {
        'code': 'delivery_manage',
        'name': 'إدارة التوصيل',
        'category': 'delivery',
      },

      // ── Tables ──
      {'code': 'tables_view', 'name': 'عرض الطاولات', 'category': 'tables'},
      {'code': 'tables_manage', 'name': 'إدارة الطاولات', 'category': 'tables'},

      // ── Kitchen ──
      {
        'code': 'kitchen_view',
        'name': 'عرض شاشة المطبخ',
        'category': 'kitchen',
      },

      // ── Treasury (missing) ──
      {
        'code': 'treasury_transfer',
        'name': 'تحويل بين الخزائن',
        'category': 'treasury',
      },
      {
        'code': 'treasury_balance_view',
        'name': 'عرض الأرصدة',
        'category': 'treasury',
      },
      {
        'code': 'treasury_transactions_view',
        'name': 'عرض الحركات',
        'category': 'treasury',
      },

      // ── HR ──
      {'code': 'hr_view', 'name': 'عرض الموظفين', 'category': 'hr'},
      {'code': 'hr_manage', 'name': 'إدارة الموظفين', 'category': 'hr'},

      // ── Reports (missing) ──
      {
        'code': 'reports_sales',
        'name': 'تقرير المبيعات',
        'category': 'reports',
      },
      {
        'code': 'reports_purchases',
        'name': 'تقرير المشتريات',
        'category': 'reports',
      },
      {
        'code': 'reports_inventory',
        'name': 'تقرير المخزون',
        'category': 'reports',
      },
      {
        'code': 'reports_treasury',
        'name': 'تقرير الخزينة',
        'category': 'reports',
      },
      {
        'code': 'reports_customers',
        'name': 'تقرير العملاء',
        'category': 'reports',
      },
      {
        'code': 'reports_suppliers',
        'name': 'تقرير الموردين',
        'category': 'reports',
      },
      {
        'code': 'reports_profit',
        'name': 'تقرير الأرباح',
        'category': 'reports',
      },
      {
        'code': 'reports_products',
        'name': 'تقرير المنتجات',
        'category': 'reports',
      },
      {
        'code': 'reports_shifts',
        'name': 'تقرير الورديات',
        'category': 'reports',
      },
      {'code': 'reports_taxes', 'name': 'تقرير الضرائب', 'category': 'reports'},

      // ── Settings (missing) ──
      {
        'code': 'settings_scale',
        'name': 'إعدادات الميزان',
        'category': 'settings',
      },
      {'code': 'settings_restore', 'name': 'الاستعادة', 'category': 'settings'},
      {
        'code': 'settings_tax',
        'name': 'إعدادات الضريبة',
        'category': 'settings',
      },
      {
        'code': 'settings_currency',
        'name': 'إعدادات العملة',
        'category': 'settings',
      },

      // ── Audit (missing) ──
      {'code': 'audit_view', 'name': 'عرض سجل العمليات', 'category': 'audit'},

      // ── System (missing) ──
      {
        'code': 'system_database',
        'name': 'إدارة قاعدة البيانات',
        'category': 'system',
      },
      {'code': 'system_updates', 'name': 'تحديث النظام', 'category': 'system'},
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add ALL permissions to admin role
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  /// v77: Seed sales/purchase order permissions
  Future<void> seedV77Permissions() async {
    final newPerms = [
      // ── Sales Orders ──
      {'code': 'sales_orders_view', 'name': 'عرض طلبات البيع', 'category': 'sales'},
      {'code': 'sales_orders_create', 'name': 'إنشاء طلب بيع', 'category': 'sales'},
      {'code': 'sales_orders_edit', 'name': 'تعديل طلب بيع', 'category': 'sales'},
      {'code': 'sales_orders_delete', 'name': 'حذف طلب بيع', 'category': 'sales'},
      {'code': 'sales_orders_convert', 'name': 'تحويل طلب بيع لفاتورة', 'category': 'sales'},

      // ── Purchase Orders ──
      {'code': 'purchase_orders_view', 'name': 'عرض أوامر الشراء', 'category': 'purchases'},
      {'code': 'purchase_orders_create', 'name': 'إنشاء أمر شراء', 'category': 'purchases'},
      {'code': 'purchase_orders_edit', 'name': 'تعديل أمر شراء', 'category': 'purchases'},
      {'code': 'purchase_orders_delete', 'name': 'حذف أمر شراء', 'category': 'purchases'},
      {'code': 'purchase_orders_convert', 'name': 'تحويل أمر شراء لفاتورة', 'category': 'purchases'},

      // ── Treasury Management ──
      {'code': 'treasury_safes_manage', 'name': 'إدارة الصناديق والبنوك', 'category': 'treasury'},

      // ── Critical Financial Operations (عمليات مالية حرجة) ──
      // These require explicit assignment — admin bypass is NOT applied
      {'code': 'delete_posted_journal', 'name': 'حذف قيد يومية مرحّل', 'category': 'critical_financial'},
      {'code': 'void_paid_invoice', 'name': 'إلغاء فاتورة مدفوعة بالكامل', 'category': 'critical_financial'},
      {'code': 'modify_locked_invoice', 'name': 'تعديل فاتورة مقفلة/مرحّلة', 'category': 'critical_financial'},
      {'code': 'delete_fiscal_year', 'name': 'حذف سنة مالية', 'category': 'critical_financial'},
      {'code': 'modify_closed_period', 'name': 'تعديل فترة محاسبية مغلقة', 'category': 'critical_financial'},
      {'code': 'override_credit_limit', 'name': 'تجاوز حد الائتمان للعميل', 'category': 'critical_financial'},
    ];

    for (final perm in newPerms) {
      await into(permissions).insert(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          category: perm['category']!,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // Add all new permissions to admin role — EXCEPT criticalFinancialOps
    // (Spec 062 / D1-004: segregation of duties). ده كان باج حقيقي: التعليق
    // فوق بالظبط بيقول "these require explicit assignment — admin bypass is
    // NOT applied"، لكن اللوب ده كان بيمنح كل الصلاحيات لمدير النظام من غير
    // استثناء — يعني `modify_closed_period` (وباقي الأكواد الحرجة زي
    // `delete_fiscal_year` و`void_paid_invoice`) كانت بتتمنح تلقائياً لمدير
    // النظام لأي حد بيرقّي قاعدة بياناته لإصدار V77. syncAllPermissions
    // (permissions_dao.dart) وseedRolesAndPermissions فوق كانوا بيستثنوا
    // الأكواد دي صح؛ اللوب ده كان الاستثناء المنسي.
    final adminRole = await (select(
      roles,
    )..where((r) => r.name.equals('مدير النظام'))).getSingleOrNull();
    if (adminRole != null) {
      final allPerms = await select(permissions).get();
      for (final p in allPerms) {
        if (PermissionCodes.criticalFinancialOps.contains(p.code)) {
          continue;
        }
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: adminRole.id,
            permissionId: p.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }
}

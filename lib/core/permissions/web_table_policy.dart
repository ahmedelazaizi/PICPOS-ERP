// سياسة جداول قراءة الويب: أيّ جدولٍ يقرؤه أيّ مستخدم.
//
// كلُّ جدولٍ في `AppDatabase.allTables` مصنَّف هنا في أحد ثلاثة:
//   * [WebTableRule.always]    — مرجعيّ يقرؤه كلُّ مستخدمٍ مصادَق.
//   * [WebTableRule.anyOf]     — يكفي **أيٌّ** من الأكواد المذكورة.
//   * [WebTableRule.forbidden] — لا يُقرأ من الويب أبداً (POS/مطبخ/طاولات/
//     ميزان/طباعة حرارية/ورديات/مزامنة/مرفقات ثنائيّة).
//
// جدولٌ جديدٌ بلا تصنيف يُفشل اختبار التغطية
// (test/core/permissions/web_table_policy_test.dart) — الرفضُ هو الأصل.
//
// أكواد المستخدم تأتي من `PermissionsDao.getUserPermissionCodes`، وقد تحمل:
//   * `system_admin`  — علامة تجاوز المدير؛ وهو يحمل صراحةً كلَّ الأكواد غير
//     الحرجة فلا تُعامَل علامةً خاصّة هنا.
//   * `cond:<code>`   — منحٌ **مشروط** (يحتاج موافقةً وقتَ الاستعمال)؛ لا
//     يُحسَب منحاً كافياً للقراءة على الويب حيث لا حوار موافقة.

/// نوع قاعدة الوصول إلى جدول.
enum WebTableAccess { always, byPermission, forbidden }

class WebTableRule {
  const WebTableRule.always()
    : access = WebTableAccess.always,
      anyOf = const {};

  const WebTableRule.anyOf(this.anyOf) : access = WebTableAccess.byPermission;

  const WebTableRule.forbidden()
    : access = WebTableAccess.forbidden,
      anyOf = const {};

  final WebTableAccess access;

  /// للنوع [WebTableAccess.byPermission]: يكفي أحدُها.
  final Set<String> anyOf;
}

class WebTablePolicy {
  WebTablePolicy._();

  static const WebTableRule _always = WebTableRule.always();
  static const WebTableRule _no = WebTableRule.forbidden();

  // ─── مجموعات الأكواد ──────────────────────────────────────────────────
  static const _accounting = WebTableRule.anyOf({
    'accounting_view',
    'accounting_manage',
    'accounting_journal',
    'reports_view',
  });
  static const _accountingStrict = WebTableRule.anyOf({
    'accounting_view',
    'accounting_manage',
    'accounting_journal',
  });
  static const _approvals = WebTableRule.anyOf({
    'accounting_manage',
    'approve_journal',
    'expenses_approve',
  });
  static const _sales = WebTableRule.anyOf({
    'sales_view',
    'sales_return_view',
    'sales_orders_view',
    'returns_view',
    'reports_sales',
  });
  static const _quotes = WebTableRule.anyOf({'quotes_view', 'sales_view'});
  static const _purchases = WebTableRule.anyOf({
    'purchases_view',
    'purchases_return_view',
    'purchase_orders_view',
    'reports_purchases',
  });
  static const _parties = WebTableRule.anyOf({
    'customers_view',
    'suppliers_view',
    'parties_view',
    'reports_customers',
    'reports_suppliers',
  });
  static const _products = WebTableRule.anyOf({
    'products_view',
    'categories_view',
    'inventory_view',
    'stock_view',
    'sales_view',
    'purchases_view',
    'reports_products',
    'reports_inventory',
  });
  static const _inventory = WebTableRule.anyOf({
    'inventory_view',
    'inventory_edit',
    'inventory_transfer',
    'stock_view',
    'stock_audit',
    'warehouses_view',
    'warehouses_manage',
    'reports_inventory',
  });
  static const _treasury = WebTableRule.anyOf({
    'treasury_view',
    'treasury_manage',
    'treasury_transactions_view',
    'treasury_balance_view',
    'commercial_papers_manage',
    'reports_treasury',
  });
  static const _hr = WebTableRule.anyOf({'hr_payroll_view'});
  static const _expenses = WebTableRule.anyOf({
    'expenses_manage',
    'expenses_approve',
    'accounting_view',
  });
  static const _mfg = WebTableRule.anyOf({
    'manufacturing_view',
    'manufacturing_manage',
  });
  static const _assets = WebTableRule.anyOf({
    'assets_view',
    'assets_manage',
    'assets_depreciation',
  });
  static const _einvoice = WebTableRule.anyOf({
    'einvoice_view',
    'einvoice_submit',
    'einvoice_cancel',
  });
  static const _loyalty = WebTableRule.anyOf({
    'loyalty_view',
    'loyalty_manage',
  });
  static const _distribution = WebTableRule.anyOf({
    'distribution_view',
    'distribution_manage',
  });
  static const _delivery = WebTableRule.anyOf({
    'delivery_view',
    'delivery_manage',
    'delivery_courier_manage',
  });
  static const _bookings = WebTableRule.anyOf({
    'bookings_view',
    'bookings_add',
    'bookings_edit',
    'bookings_reports',
  });
  static const _offers = WebTableRule.anyOf({
    'offers_view',
    'offers_create',
    'offers_edit',
  });
  static const _users = WebTableRule.anyOf({'users_manage', 'roles_manage'});
  static const _audit = WebTableRule.anyOf({'audit_view', 'system_audit_log'});
  static const _settings = WebTableRule.anyOf({
    'settings_view',
    'settings_edit',
  });
  static const _reports = WebTableRule.anyOf({
    'reports_view',
    'reports_export',
  });

  /// اسمُ الجدول في SQL (`actualTableName`) → قاعدته.
  static const Map<String, WebTableRule> rules = {
    // ── مرجعيّ لكلّ مستخدم ──
    'units': _always,
    'currencies': _always,
    'exchange_rate_history': _always,
    'tax_types': _always,
    'tax_subtypes': _always,
    'branches': _always,
    'regions': _always,
    // الإعدادات: مفاتيح كلمات المرور/الأسرار تُفرَّغ في الاعتراض البرمجيّ.
    'settings': _always,

    // ── ممنوع على الويب: POS/مطبخ/طاولات/ميزان/طباعة حرارية/ورديات ──
    'held_orders': _no,
    'held_order_items': _no,
    'work_orders': _no,
    'work_order_items': _no,
    'kitchen_stations': _no,
    'category_station_mappings': _no,
    'table_sections': _no,
    'restaurant_tables': _no,
    'table_orders': _no,
    'table_order_items': _no,
    'floor_plan_items': _no,
    'table_reservations': _no,
    'table_order_payments': _no,
    'label_scales': _no,
    'printers': _no,
    'receipt_settings': _no,
    'pos_terminals': _no,
    'shifts': _no,
    // ── ممنوع: مزامنة/صيانة داخليّة وبيانات ثنائيّة وإشعارات شخصيّة ──
    'sync_outbox': _no,
    'sync_conflict_log': _no,
    'remote_id_mappings': _no,
    'processed_messages': _no,
    'failed_autoposts': _no,
    'attachment_blobs': _no,
    'attachments': _no,
    'notifications': _no,

    // ── مستخدمون وصلاحيات (الأعمدة الحسّاسة تُفرَّغ في الاعتراض) ──
    'users': _users,
    'roles': _users,
    'permissions': _users,
    'role_permissions': _users,
    'user_branch_access': _users,
    'user_warehouse_access': _users,
    'user_region_access': _users,
    'api_keys': _users,
    'activity_logs': _audit,
    'field_audit_logs': _audit,
    'sod_conflicts': WebTableRule.anyOf({'roles_manage', 'audit_view'}),
    'sod_violations': WebTableRule.anyOf({'roles_manage', 'audit_view'}),

    // ── محاسبة ──
    'accounts': _accounting,
    'journal_entries': _accounting,
    'journal_entry_lines': _accounting,
    'cost_centers': _accounting,
    'fiscal_years': _accounting,
    'accounting_periods': _accounting,
    'activity_profiles': _accountingStrict,
    'account_mappings': _accountingStrict,
    'journal_entry_templates': _accountingStrict,
    'journal_entry_template_lines': _accountingStrict,
    'budgets': _accountingStrict,
    'budget_lines': _accountingStrict,
    'deferred_schedules': _accountingStrict,
    'deferred_entries': _accountingStrict,
    'approval_workflows': _approvals,
    'approval_steps': _approvals,
    'approval_requests': _approvals,
    'approval_decisions': _approvals,
    'entities': _accountingStrict,
    'entity_mappings': _accountingStrict,
    'intercompany_transactions': _accountingStrict,
    'restatements': _accountingStrict,
    'restatement_lines': _accountingStrict,
    'compliance_checks': _accountingStrict,
    'document_sequences': _settings,

    // ── مبيعات ──
    'sales_invoices': _sales,
    'sales_invoice_items': _sales,
    'sales_orders': _sales,
    'sales_order_items': _sales,
    'sale_bom_consumptions': _sales,
    'quotations': _quotes,
    'quotation_items': _quotes,
    'offers': _offers,
    'offer_items': _offers,

    // ── مشتريات ──
    'purchase_invoices': _purchases,
    'purchase_invoice_items': _purchases,
    'import_purchase_details': _purchases,
    'purchase_returns': _purchases,
    'purchase_orders': _purchases,
    'purchase_order_items': _purchases,
    'landed_cost_sheets': WebTableRule.anyOf({
      'purchases_view',
      'landed_cost_apply',
    }),
    'landed_cost_items': WebTableRule.anyOf({
      'purchases_view',
      'landed_cost_apply',
    }),
    'landed_cost_allocations': WebTableRule.anyOf({
      'purchases_view',
      'landed_cost_apply',
    }),
    'supplier_claims': WebTableRule.anyOf({'suppliers_view', 'purchases_view'}),

    // ── أطراف ──
    'parties': _parties,
    'party_groups': _parties,
    'party_follow_ups': _parties,
    'customer_loyalty_points': _loyalty,
    'loyalty_programs': _loyalty,
    'loyalty_transactions': _loyalty,

    // ── أصناف ومخزون ──
    'products': _products,
    'product_barcodes': _products,
    'product_units': _products,
    'product_batches': _products,
    'categories': _products,
    'category_branches': _products,
    'warehouse_prices': _products,
    'price_lists': WebTableRule.anyOf({'price_lists_manage', 'products_view'}),
    'price_list_items': WebTableRule.anyOf({
      'price_lists_manage',
      'products_view',
    }),
    'warehouses': _inventory,
    'stock_movements': _inventory,
    'inventory_balances': _inventory,
    'stock_audits': _inventory,
    'stock_audit_items': _inventory,
    'inventory_bonds': _inventory,
    'inventory_bond_items': _inventory,
    'stock_requisitions': _inventory,
    'stock_requisition_items': _inventory,
    'cycle_count_plans': _inventory,
    'cycle_count_tasks': _inventory,
    'cycle_count_items': _inventory,

    // ── خزينة وأوراق تجارية ──
    'safes': _treasury,
    'safe_transactions': _treasury,
    'commercial_papers': _treasury,
    'paper_status_history': _treasury,
    'cheque_books': _treasury,
    'bank_statement_lines': _treasury,
    'bank_reconciliations': _treasury,
    'payments': _treasury,
    'payment_allocations': _treasury,

    // ── موارد بشرية ورواتب: لا يقرؤها إلا من يملك hr_payroll_view ──
    'employees': _hr,
    'employee_leaves': _hr,
    'leave_balances': _hr,
    'overtime_records': _hr,
    'work_holidays': _hr,
    'fingerprint_devices': _hr,
    'employee_attendance': _hr,
    'salary_payments': _hr,
    'employee_transactions': _hr,
    'performance_reviews': _hr,
    'performance_goals': _hr,
    'employee_contracts': _hr,

    // ── تصنيع وأصول ومصروفات ──
    'bill_of_materials': _mfg,
    'bom_components': _mfg,
    'manufacturing_orders': _mfg,
    'mfg_order_costs': _mfg,
    'asset_categories': _assets,
    'fixed_assets': _assets,
    'asset_disposals': _assets,
    'asset_depreciations': _assets,
    'op_expense_categories': _expenses,
    'op_expenses': _expenses,

    // ── فوترة إلكترونية (clientSecret يُفرَّغ في الاعتراض) ──
    'e_invoice_configs': _einvoice,
    'e_invoice_submissions': _einvoice,
    'e_invoice_status_log': _einvoice,

    // ── توزيع وتوصيل وحجوزات ──
    'sales_routes': _distribution,
    'route_visits': _distribution,
    'sales_rep_targets': _distribution,
    'sales_rep_collections': _distribution,
    'delivery_companies': _delivery,
    'couriers': _delivery,
    'booking_resources': _bookings,
    'booking_services': _bookings,
    'bookings': _bookings,
    'booking_reminders': _bookings,

    // ── قوالب وتقارير ──
    'invoice_templates': _settings,
    'invoice_template_elements': _settings,
    'invoice_table_settings': _settings,
    'template_bindings': _settings,
    'custom_reports': _reports,
    'saved_report_runs': _reports,
  };

  /// هل [table] مصنَّف؟
  static bool isClassified(String table) => rules.containsKey(table);

  /// الجداول الممنوعة دائماً على الويب.
  static Set<String> get forbiddenTables => {
    for (final e in rules.entries)
      if (e.value.access == WebTableAccess.forbidden) e.key,
  };

  /// مجموعة الجداول التي يقرؤها مستخدمٌ بهذه [permissionCodes]
  /// (ناتج `getUserPermissionCodes`). جدولٌ غير مصنَّف لا يدخل أبداً.
  static Set<String> allowedTables(Iterable<String> permissionCodes) {
    final codes = permissionCodes.toSet();
    // المنحُ المشروط لا يكفي على الويب.
    final granted = {
      for (final c in codes)
        if (!c.startsWith('cond:') && !codes.contains('cond:$c')) c,
    };
    return {
      for (final e in rules.entries)
        if (switch (e.value.access) {
          WebTableAccess.always => true,
          WebTableAccess.forbidden => false,
          WebTableAccess.byPermission => e.value.anyOf.any(granted.contains),
        })
          e.key,
    };
  }
}

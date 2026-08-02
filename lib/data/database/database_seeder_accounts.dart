// =======================================================================
// DATABASE SEEDER - CHART OF ACCOUNTS & TEMPLATES
// Extracted from database_seeder.dart - Sprint 13 God File Splitting
// Enhanced: v110 — Full Chart of Accounts (170+ accounts, 7 groups, 5 levels)
// =======================================================================

part of 'database.dart';

/// Extension for Chart of Accounts and Template seeding operations  
extension DatabaseSeederAccounts on AppDatabase {
  /// Helper to insert an account using raw SQL with parent resolution by code.
  ///
  /// Dialect-safe on both SQLite 3.24+ and PostgreSQL:
  ///   • `accounts.code` has NO UNIQUE constraint (only a non-unique
  ///     `@TableIndex('idx_accounts_code')`), so we CANNOT use
  ///     `ON CONFLICT (code)` — PG would raise 42P10 ("no unique or
  ///     exclusion constraint matching the ON CONFLICT specification").
  ///     Instead we guard the INSERT with a `WHERE NOT EXISTS (...)` clause,
  ///     which works on every dialect and on tables with any constraint set.
  ///   • Uses boolean literals (`TRUE`/`FALSE`) for the boolean columns rather
  ///     than `0/1` integers — PostgreSQL is strict about boolean columns and
  ///     rejects bigint expressions with 42804. SQLite accepts `TRUE`/`FALSE`
  ///     since 3.23 (mapped to 1/0).
  Future<void> _acct(String code, String name, String nameEn, String type,
      String nature, String balance, int level, String? parentCode,
      {bool system = true}) async {
    await customStatement(
      '''INSERT INTO accounts (code, name, account_type, account_nature,
         normal_balance, level, parent_id, balance, is_system, is_active, is_hidden_from_entries)
         SELECT ?, ?, ?, ?, ?, ?,
           ${parentCode != null ? "(SELECT id FROM accounts WHERE code = '$parentCode')" : "NULL"},
           0, ${system ? 'TRUE' : 'FALSE'}, TRUE, FALSE
         WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = ?)''',
      [code, name, type, nature, balance, level, code],
    );
  }

  Future<void> seedChartOfAccounts() async {
    // ═══════════════════════════════════════════════════════════════════
    // 1. ASSETS (الأصول) — code 1
    // ═══════════════════════════════════════════════════════════════════
    await _acct('1', 'الأصول', 'Assets', 'asset', 'view', 'debit', 1, null);

    // 11 — Current Assets
    await _acct('11', 'الأصول المتداولة', 'Current Assets', 'asset', 'view', 'debit', 2, '1');

    // 111 — Cash & Cash Equivalents
    await _acct('111', 'النقدية وما في حكمها', 'Cash & Cash Equivalents', 'asset', 'view', 'debit', 3, '11');
    await _acct('1111', 'الصندوق الرئيسي', 'Main Cash', 'asset', 'detail', 'debit', 4, '111');
    await _acct('1112', 'صندوق العهد والمصروفات', 'Petty Cash', 'asset', 'detail', 'debit', 4, '111');
    await _acct('1113', 'البنك الأهلي - حساب جاري', 'National Bank - Current Acct', 'asset', 'detail', 'debit', 4, '111');
    await _acct('1114', 'بنك القاهرة - حساب جاري', 'Cairo Bank - Current Acct', 'asset', 'detail', 'debit', 4, '111');
    await _acct('1115', 'البنك التجاري - ودائع', 'Commercial Bank - Deposits', 'asset', 'detail', 'debit', 4, '111');
    await _acct('1116', 'حساب Click', 'Click Account', 'asset', 'detail', 'debit', 4, '111');

    // 112 — Accounts Receivable
    await _acct('112', 'الذمم المدينة - العملاء', 'Accounts Receivable - Customers', 'asset', 'view', 'debit', 3, '11');
    await _acct('1121', 'ذمم عملاء محليون', 'Local Customers Receivable', 'asset', 'detail', 'debit', 4, '112');
    await _acct('1122', 'ذمم عملاء خارجيون', 'Foreign Customers Receivable', 'asset', 'detail', 'debit', 4, '112');
    await _acct('1123', 'أوراق القبض', 'Notes Receivable', 'asset', 'detail', 'debit', 4, '112');
    await _acct('1124', 'مخصص ديون مشكوك فيها', 'Allowance for Doubtful Debts', 'asset', 'detail', 'credit', 4, '112');

    // 113 — Inventory
    await _acct('113', 'المخزون', 'Inventory', 'asset', 'view', 'debit', 3, '11');
    await _acct('1131', 'مخزون المواد الخام', 'Raw Materials Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1132', 'مخزون مواد التغليف', 'Packaging Materials Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1133', 'مخزون تحت التشغيل', 'Work-in-Progress Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1134', 'مخزون البضاعة التامة الصنع', 'Finished Goods Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1135', 'مخزون قطع الغيار', 'Spare Parts Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1136', 'مخزون البضاعة للبيع', 'Trading Goods Inventory', 'asset', 'detail', 'debit', 4, '113');
    await _acct('1137', 'مخصص هبوط أسعار المخزون', 'Inventory Obsolescence Allowance', 'asset', 'detail', 'credit', 4, '113');

    // 114 — Other Receivables
    await _acct('114', 'الذمم المدينة الأخرى', 'Other Receivables', 'asset', 'view', 'debit', 3, '11');
    await _acct('1141', 'ضريبة القيمة المضافة - مدفوعة', 'VAT Paid (Input Tax)', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1142', 'ضريبة المبيعات المدفوعة مقدماً', 'Prepaid Sales Tax', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1143', 'المصروفات المدفوعة مقدماً', 'Prepaid Expenses', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1144', 'الإيرادات المستحقة', 'Accrued Income', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1145', 'دائنو السلف والعهد', 'Advances to Suppliers', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1146', 'سلف الموظفين', 'Employee Advances', 'asset', 'detail', 'debit', 4, '114');
    await _acct('1147', 'حسابات جارية - مدينة', 'Current Accounts - Debit', 'asset', 'detail', 'debit', 4, '114');

    // 12 — Non-Current Assets
    await _acct('12', 'الأصول غير المتداولة', 'Non-Current Assets', 'asset', 'view', 'debit', 2, '1');

    // 121 — Property, Plant & Equipment
    await _acct('121', 'الأصول الثابتة الملموسة', 'Property, Plant & Equipment', 'asset', 'view', 'debit', 3, '12');
    await _acct('1211', 'الأراضي', 'Land', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1212', 'المباني والإنشاءات', 'Buildings & Constructions', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1213', 'الآلات والمعدات الصناعية', 'Industrial Machinery & Equipment', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1214', 'السيارات والمركبات', 'Vehicles & Transportation', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1215', 'الأثاث والتجهيزات', 'Furniture & Fixtures', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1216', 'أجهزة الحاسب والبرمجيات', 'IT Equipment & Software', 'asset', 'detail', 'debit', 4, '121');
    await _acct('1217', 'معدات وأدوات المصنع', 'Factory Tools & Equipment', 'asset', 'detail', 'debit', 4, '121');
    // Accumulated Depreciation
    await _acct('1218', 'مجمع إهلاك المباني', 'Accum. Depr. - Buildings', 'asset', 'detail', 'credit', 4, '121');
    await _acct('1219', 'مجمع إهلاك الآلات', 'Accum. Depr. - Machinery', 'asset', 'detail', 'credit', 4, '121');
    await _acct('1220', 'مجمع إهلاك المركبات', 'Accum. Depr. - Vehicles', 'asset', 'detail', 'credit', 4, '121');
    await _acct('1221', 'مجمع إهلاك الأثاث', 'Accum. Depr. - Furniture', 'asset', 'detail', 'credit', 4, '121');
    await _acct('1222', 'مجمع إهلاك الحاسب', 'Accum. Depr. - IT', 'asset', 'detail', 'credit', 4, '121');

    // 122 — Intangible Assets
    await _acct('122', 'الأصول غير الملموسة', 'Intangible Assets', 'asset', 'view', 'debit', 3, '12');
    await _acct('1221A', 'الشهرة', 'Goodwill', 'asset', 'detail', 'debit', 4, '122');
    await _acct('1222A', 'براءات الاختراع والعلامات التجارية', 'Patents & Trademarks', 'asset', 'detail', 'debit', 4, '122');
    await _acct('1223', 'حقوق الامتياز', 'Franchise Rights', 'asset', 'detail', 'debit', 4, '122');

    // 123 — Long-term Investments
    await _acct('123', 'الاستثمارات طويلة الأجل', 'Long-term Investments', 'asset', 'view', 'debit', 3, '12');
    await _acct('1231', 'استثمارات في شركات شقيقة', 'Investments in Associates', 'asset', 'detail', 'debit', 4, '123');
    await _acct('1232', 'استثمارات في أوراق مالية', 'Investment Securities', 'asset', 'detail', 'debit', 4, '123');

    // ═══════════════════════════════════════════════════════════════════
    // 2. LIABILITIES (الالتزامات) — code 2
    // ═══════════════════════════════════════════════════════════════════
    await _acct('2', 'الالتزامات', 'Liabilities', 'liability', 'view', 'credit', 1, null);

    // 21 — Current Liabilities
    await _acct('21', 'الالتزامات المتداولة', 'Current Liabilities', 'liability', 'view', 'credit', 2, '2');

    await _acct('211', 'الذمم الدائنة - الموردون', 'Accounts Payable - Suppliers', 'liability', 'view', 'credit', 3, '21');
    await _acct('2111', 'ذمم موردون محليون', 'Local Suppliers Payable', 'liability', 'detail', 'credit', 4, '211');
    await _acct('2112', 'ذمم موردون خارجيون', 'Foreign Suppliers Payable', 'liability', 'detail', 'credit', 4, '211');
    await _acct('2113', 'أوراق الدفع', 'Notes Payable', 'liability', 'detail', 'credit', 4, '211');

    await _acct('212', 'الالتزامات الضريبية', 'Tax Liabilities', 'liability', 'view', 'credit', 3, '21');
    await _acct('2121', 'ضريبة القيمة المضافة - محصلة', 'VAT Collected (Output Tax)', 'liability', 'detail', 'credit', 4, '212');
    await _acct('2122', 'ضريبة الدخل المستحقة', 'Income Tax Payable', 'liability', 'detail', 'credit', 4, '212');
    await _acct('2123', 'ضريبة الرواتب المستحقة', 'Payroll Tax Payable', 'liability', 'detail', 'credit', 4, '212');
    await _acct('2124', 'ضريبة الجمارك المستحقة', 'Customs Duty Payable', 'liability', 'detail', 'credit', 4, '212');

    await _acct('213', 'المستحقات والالتزامات الأخرى', 'Accrued Liabilities & Others', 'liability', 'view', 'credit', 3, '21');
    await _acct('2131', 'رواتب ومزايا مستحقة', 'Accrued Salaries & Benefits', 'liability', 'detail', 'credit', 4, '213');
    await _acct('2132', 'مصروفات مستحقة الدفع', 'Accrued Expenses', 'liability', 'detail', 'credit', 4, '213');
    await _acct('2133', 'إيرادات مقدمة', 'Deferred Revenue', 'liability', 'detail', 'credit', 4, '213');
    await _acct('2134', 'عملاء - دفعات مقدمة', 'Customer Advances', 'liability', 'detail', 'credit', 4, '213');
    await _acct('2135', 'حسابات جارية - دائنة', 'Current Accounts - Credit', 'liability', 'detail', 'credit', 4, '213');

    await _acct('214', 'القروض قصيرة الأجل', 'Short-term Loans', 'liability', 'view', 'credit', 3, '21');
    await _acct('2141', 'قروض بنكية قصيرة الأجل', 'Short-term Bank Loans', 'liability', 'detail', 'credit', 4, '214');
    await _acct('2142', 'تسهيلات ائتمانية - بنكية', 'Bank Credit Facilities', 'liability', 'detail', 'credit', 4, '214');
    await _acct('2143', 'الجزء الجاري من قروض طويلة الأجل', 'Current Portion of LT Loans', 'liability', 'detail', 'credit', 4, '214');

    // 22 — Non-Current Liabilities
    await _acct('22', 'الالتزامات غير المتداولة', 'Non-Current Liabilities', 'liability', 'view', 'credit', 2, '2');

    await _acct('221', 'القروض طويلة الأجل', 'Long-term Loans', 'liability', 'view', 'credit', 3, '22');
    await _acct('2211', 'قروض بنكية طويلة الأجل', 'Long-term Bank Loans', 'liability', 'detail', 'credit', 4, '221');
    await _acct('2212', 'سندات وصكوك', 'Bonds & Sukuk', 'liability', 'detail', 'credit', 4, '221');

    await _acct('222', 'الالتزامات الأخرى طويلة الأجل', 'Other Long-term Liabilities', 'liability', 'view', 'credit', 3, '22');
    await _acct('2221', 'مخصص مكافأة نهاية الخدمة', 'End-of-Service Benefits Provision', 'liability', 'detail', 'credit', 4, '222');
    await _acct('2222', 'التزامات إيجارية طويلة الأجل', 'Long-term Lease Liabilities', 'liability', 'detail', 'credit', 4, '222');

    // ═══════════════════════════════════════════════════════════════════
    // 3. EQUITY (حقوق الملكية) — code 3
    // ═══════════════════════════════════════════════════════════════════
    await _acct('3', 'حقوق الملكية', 'Equity', 'equity', 'view', 'credit', 1, null);
    await _acct('31', 'رأس المال والاحتياطيات', 'Capital & Reserves', 'equity', 'view', 'credit', 2, '3');
    await _acct('311', 'رأس المال', 'Share Capital', 'equity', 'detail', 'credit', 3, '31');
    await _acct('312', 'الاحتياطي القانوني', 'Legal Reserve', 'equity', 'detail', 'credit', 3, '31');
    await _acct('313', 'الأرباح المبقاة', 'Retained Earnings', 'equity', 'detail', 'credit', 3, '31');
    await _acct('314', 'الأرباح والخسائر السنة الحالية', 'Current Year P&L', 'equity', 'detail', 'credit', 3, '31');
    await _acct('315', 'حقوق الشريك / المالك', 'Owner Equity', 'equity', 'detail', 'credit', 3, '31');
    await _acct('316', 'الاحتياطي الاختياري', 'Optional Reserve', 'equity', 'detail', 'credit', 3, '31');
    await _acct('317', 'الاحتياطي العام', 'General Reserve', 'equity', 'detail', 'credit', 3, '31');

    // ═══════════════════════════════════════════════════════════════════
    // 4. REVENUE (الإيرادات) — code 4
    // ═══════════════════════════════════════════════════════════════════
    await _acct('4', 'الإيرادات', 'Revenue', 'revenue', 'view', 'credit', 1, null);

    // 41 — Sales Revenue
    await _acct('41', 'إيرادات المبيعات', 'Sales Revenue', 'revenue', 'view', 'credit', 2, '4');
    await _acct('411', 'مبيعات المنتجات الصناعية', 'Industrial Products Sales', 'revenue', 'view', 'credit', 3, '41');
    await _acct('4111', 'مبيعات المنتج الأول', 'Product Line 1 Sales', 'revenue', 'detail', 'credit', 4, '411');
    await _acct('4112', 'مبيعات المنتج الثاني', 'Product Line 2 Sales', 'revenue', 'detail', 'credit', 4, '411');
    await _acct('4113', 'مبيعات المنتج الثالث', 'Product Line 3 Sales', 'revenue', 'detail', 'credit', 4, '411');
    await _acct('412', 'مبيعات البضاعة التجارية', 'Trading Goods Sales', 'revenue', 'view', 'credit', 3, '41');
    await _acct('4121', 'مبيعات محلية - تجاري', 'Local Trading Sales', 'revenue', 'detail', 'credit', 4, '412');
    await _acct('4122', 'مبيعات تصدير - تجاري', 'Export Trading Sales', 'revenue', 'detail', 'credit', 4, '412');
    await _acct('413', 'إيرادات الخدمات', 'Service Revenue', 'revenue', 'view', 'credit', 3, '41');
    await _acct('4131', 'خدمات ما بعد البيع', 'After-sales Services', 'revenue', 'detail', 'credit', 4, '413');
    await _acct('4132', 'خدمات الصيانة والإصلاح', 'Maintenance & Repair Services', 'revenue', 'detail', 'credit', 4, '413');
    await _acct('414', 'إيرادات التوصيل', 'Delivery Revenue', 'revenue', 'detail', 'credit', 3, '41');

    // 42 — Sales Returns
    await _acct('42', 'مردودات ومسموحات المبيعات', 'Sales Returns & Allowances', 'revenue', 'view', 'debit', 2, '4');
    await _acct('4211', 'مردودات المبيعات', 'Sales Returns', 'revenue', 'detail', 'debit', 3, '42');
    await _acct('4212', 'خصم المبيعات', 'Sales Discounts', 'revenue', 'detail', 'debit', 3, '42');

    // 43 — Other Income
    await _acct('43', 'الإيرادات الأخرى', 'Other Income', 'revenue', 'view', 'credit', 2, '4');
    await _acct('4311', 'إيرادات أرباح الاستثمارات', 'Investment Income', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4312', 'إيرادات فوائد', 'Interest Income', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4313', 'إيرادات إيجارات', 'Rental Income', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4314', 'أرباح بيع أصول ثابتة', 'Gain on Asset Disposal', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4315', 'إيرادات متنوعة أخرى', 'Miscellaneous Income', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4316', 'خصم المشتريات المكتسب', 'Purchase Discount Earned', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4317', 'فائض مخزون', 'Inventory Surplus', 'revenue', 'detail', 'credit', 3, '43');
    await _acct('4318', 'فائض نقدي', 'Cash Surplus', 'revenue', 'detail', 'credit', 3, '43');
    // Spec 139 — dedicated account for journal-entry rounding remainders. The JE
    // writer books the sub-cap residual here (both a small gain=credit and a
    // small loss=debit) instead of hiding it in a business leg. Income-side
    // normal; remappable via the account-mapping screen (purpose
    // 'rounding_difference'). Idempotent (_acct guards WHERE NOT EXISTS).
    await _acct('4319', 'فروق تقريب', 'Rounding Differences', 'revenue', 'detail', 'credit', 3, '43');

    // ═══════════════════════════════════════════════════════════════════
    // 5. COGS (تكلفة البضاعة المباعة) — code 5
    // ═══════════════════════════════════════════════════════════════════
    await _acct('5', 'تكلفة البضاعة المباعة', 'Cost of Goods Sold', 'expense', 'view', 'debit', 1, null);

    await _acct('51', 'تكاليف الإنتاج الصناعي', 'Manufacturing Costs', 'expense', 'view', 'debit', 2, '5');
    await _acct('511', 'المواد الخام المباشرة', 'Direct Raw Materials', 'expense', 'view', 'debit', 3, '51');
    await _acct('5111', 'استهلاك المواد الخام', 'Raw Materials Consumed', 'expense', 'detail', 'debit', 4, '511');
    await _acct('5112', 'استهلاك مواد التغليف', 'Packaging Materials Consumed', 'expense', 'detail', 'debit', 4, '511');
    await _acct('512', 'العمالة المباشرة', 'Direct Labor', 'expense', 'view', 'debit', 3, '51');
    await _acct('5121', 'رواتب عمال الإنتاج', 'Production Workers Salaries', 'expense', 'detail', 'debit', 4, '512');
    await _acct('5122', 'أجور إضافية - إنتاج', 'Production Overtime Wages', 'expense', 'detail', 'debit', 4, '512');
    await _acct('5123', 'مكافآت وحوافز إنتاجية', 'Production Bonuses & Incentives', 'expense', 'detail', 'debit', 4, '512');
    await _acct('513', 'التكاليف الصناعية غير المباشرة', 'Manufacturing Overhead', 'expense', 'view', 'debit', 3, '51');
    await _acct('5131', 'إهلاك الآلات والمعدات', 'Depreciation - Machinery', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5132', 'إهلاك المباني الصناعية', 'Depreciation - Factory Buildings', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5133', 'صيانة وإصلاح الآلات', 'Machinery Maintenance & Repair', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5134', 'مصروف الكهرباء والطاقة - مصنع', 'Factory Electricity & Energy', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5135', 'مصروف المياه - مصنع', 'Factory Water', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5136', 'مصروف الوقود - الإنتاج', 'Production Fuel', 'expense', 'detail', 'debit', 4, '513');
    await _acct('5137', 'مستلزمات الإنتاج الأخرى', 'Other Production Supplies', 'expense', 'detail', 'debit', 4, '513');
    // Spec 146 (S-MFG-GL): applied manufacturing overhead — the credit party for
    // indirect costs capitalised into WIP at completion. Contra within the 513
    // subtree → credit-normal, so period-end settlement (actual 513x debit vs
    // applied 5138 credit → over/under variance) is a natural comparison.
    await _acct('5138', 'تحميل صناعي مطبّق', 'Applied Manufacturing Overhead', 'expense', 'detail', 'credit', 4, '513');

    await _acct('52', 'تكلفة البضاعة التجارية المباعة', 'Cost of Trading Goods Sold', 'expense', 'view', 'debit', 2, '5');
    await _acct('5211', 'تكلفة بضاعة تجارية محلية', 'Local Trading Goods Cost', 'expense', 'detail', 'debit', 3, '52');
    await _acct('5212', 'تكلفة بضاعة تجارية مستوردة', 'Imported Trading Goods Cost', 'expense', 'detail', 'debit', 3, '52');
    await _acct('5213', 'تكاليف الاستيراد والجمارك', 'Import & Customs Costs', 'expense', 'detail', 'debit', 3, '52');
    await _acct('5214', 'مردودات المشتريات', 'Purchase Returns', 'expense', 'detail', 'credit', 3, '52');

    // ═══════════════════════════════════════════════════════════════════
    // 6. OPERATING EXPENSES (مصروفات التشغيل) — code 6
    // ═══════════════════════════════════════════════════════════════════
    await _acct('6', 'مصروفات التشغيل', 'Operating Expenses', 'expense', 'view', 'debit', 1, null);

    // 61 — Selling & Distribution
    await _acct('61', 'مصروفات المبيعات والتوزيع', 'Selling & Distribution Expenses', 'expense', 'view', 'debit', 2, '6');
    await _acct('611', 'رواتب وأجور - مبيعات', 'Salaries - Sales Dept', 'expense', 'detail', 'debit', 3, '61');
    await _acct('612', 'عمولات المبيعات', 'Sales Commissions', 'expense', 'detail', 'debit', 3, '61');
    await _acct('613', 'مصروف إعلان وتسويق', 'Advertising & Marketing', 'expense', 'detail', 'debit', 3, '61');
    await _acct('614', 'مصروف نقل وتوزيع', 'Freight & Distribution', 'expense', 'detail', 'debit', 3, '61');
    await _acct('615', 'مصروف تغليف وتعبئة', 'Packaging & Packing Expenses', 'expense', 'detail', 'debit', 3, '61');
    await _acct('616', 'مصروف ضمانات وخدمة عملاء', 'Warranty & Customer Service', 'expense', 'detail', 'debit', 3, '61');
    await _acct('617', 'سفر وانتقالات - مبيعات', 'Travel & Transport - Sales', 'expense', 'detail', 'debit', 3, '61');
    await _acct('618', 'مصروف المعارض والبازارات', 'Exhibitions & Trade Shows', 'expense', 'detail', 'debit', 3, '61');

    // 62 — General & Administrative
    await _acct('62', 'المصروفات الإدارية والعمومية', 'General & Administrative Expenses', 'expense', 'view', 'debit', 2, '6');
    await _acct('621', 'رواتب وأجور - إدارة', 'Salaries - Admin Dept', 'expense', 'detail', 'debit', 3, '62');
    await _acct('622', 'مكافآت نهاية الخدمة', 'End-of-Service Benefits', 'expense', 'detail', 'debit', 3, '62');
    await _acct('623', 'مصروف الإيجارات', 'Rent Expense', 'expense', 'detail', 'debit', 3, '62');
    await _acct('624', 'مصروف الكهرباء والمياه - إدارة', 'Electricity & Water - Admin', 'expense', 'detail', 'debit', 3, '62');
    await _acct('625', 'مصروف الهاتف والإنترنت', 'Telephone & Internet', 'expense', 'detail', 'debit', 3, '62');
    await _acct('626', 'مصروف القرطاسية والمطبوعات', 'Stationery & Printing', 'expense', 'detail', 'debit', 3, '62');
    await _acct('627', 'مصروف الصيانة - إدارة', 'Maintenance - Admin', 'expense', 'detail', 'debit', 3, '62');
    await _acct('628', 'مصروف التأمين', 'Insurance Expense', 'expense', 'detail', 'debit', 3, '62');
    await _acct('629', 'مصروف الاستشارات والمحاسبة', 'Consulting & Accounting Fees', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6210', 'مصروف الترخيص والرسوم الحكومية', 'Licenses & Government Fees', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6211', 'مصروف النظافة والأمن', 'Cleaning & Security', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6212', 'مصروف سفر وانتقالات - إدارة', 'Travel & Transport - Admin', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6213', 'مصروفات الإهلاك - إداري', 'Depreciation - Admin Assets', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6214', 'مصروفات متنوعة - إدارة', 'Miscellaneous Admin Expenses', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6215', 'خصم مسموح به', 'Discount Allowed', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6216', 'عجز مخزون', 'Inventory Shrinkage', 'expense', 'detail', 'debit', 3, '62');
    await _acct('6217', 'عجز نقدي', 'Cash Shortage', 'expense', 'detail', 'debit', 3, '62');

    // 63 — Finance Costs (fixed codes to avoid duplication with 62x)
    await _acct('63', 'مصروفات التمويل', 'Finance Costs', 'expense', 'view', 'debit', 2, '6');
    await _acct('6311', 'فوائد قروض بنكية', 'Bank Loan Interest', 'expense', 'detail', 'debit', 3, null);
    await _acct('6312', 'عمولات بنكية', 'Bank Commissions & Charges', 'expense', 'detail', 'debit', 3, null);
    await _acct('6313', 'خسائر فروق العملة', 'Foreign Exchange Losses', 'expense', 'detail', 'debit', 3, null);

    // 64 — Other Expenses
    await _acct('64', 'المصروفات الأخرى', 'Other Expenses', 'expense', 'view', 'debit', 2, '6');
    await _acct('641', 'ديون معدومة وهالكة', 'Bad Debts Written Off', 'expense', 'detail', 'debit', 3, null);
    await _acct('642', 'خسائر بيع أصول ثابتة', 'Loss on Asset Disposal', 'expense', 'detail', 'debit', 3, null);
    await _acct('643', 'مصروف هبوط أسعار المخزون', 'Inventory Write-down Expense', 'expense', 'detail', 'debit', 3, null);
    await _acct('644', 'مصروفات استثنائية', 'Extraordinary Expenses', 'expense', 'detail', 'debit', 3, null);

    // ═══════════════════════════════════════════════════════════════════
    // 7. CLOSING & CLEARING (حسابات ختامية) — code 7
    // ═══════════════════════════════════════════════════════════════════
    await _acct('7', 'حسابات ختامية ومقاصة', 'Closing & Clearing Accounts', 'expense', 'view', 'debit', 1, null);
    await _acct('71', 'حساب المتاجرة', 'Trading Account', 'expense', 'detail', 'debit', 2, null);
    await _acct('72', 'حساب الأرباح والخسائر', 'Profit & Loss Account', 'expense', 'detail', 'debit', 2, null);
    await _acct('73', 'ضريبة الدخل', 'Income Tax', 'expense', 'detail', 'debit', 2, null);
    await _acct('74', 'حساب التوزيعات / الأرباح الموزعة', 'Dividends Distribution', 'expense', 'detail', 'debit', 2, null);
    await _acct('75', 'حساب المقاصة الداخلية', 'Internal Clearing Account', 'expense', 'detail', 'debit', 2, null);
  }

  /// Seed default invoice templates for designer
  Future<void> seedDefaultInvoiceTemplates() async {
    // Create default thermal receipt template
    await createTemplate(
      name: 'الفاتورة الحرارية',
      type: 'thermal',
      paperSize: '80mm',
      paperWidth: 80,
      defaultFontSize: 10,
    );
    // Set thermal as default
    await setDefaultTemplate(1);

    // Create default A4 invoice template
    await createTemplate(
      name: 'فاتورة A4',
      type: 'a4',
      paperSize: 'A4',
      paperWidth: 210,
      paperHeight: 297,
      defaultFontSize: 12,
    );
    // Set A4 as default for its type
    await setDefaultTemplate(2);
  }
}

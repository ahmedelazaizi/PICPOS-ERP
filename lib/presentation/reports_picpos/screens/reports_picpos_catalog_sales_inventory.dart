part of 'reports_picpos_screen.dart';

/// كتالوجُ تقارير PicPos — **المصدرُ الوحيد**.
///
/// ⚠️ **رُفع من داخل `State` إلى مستوى الملفّ** ليقرأه الشريطُ الجانبيّ:
/// أمرُ المالك 2026-09-12 يضع رؤوسَ فئات التقارير في الشريط وتحتَها
/// تقاريرُها. ونسخُ العناوين هناك كان يُنتج مصدراً ثانياً — والملفُّ يحمل
/// أصلاً تحذيراً من ازدواجٍ قائم («الكتالوجُ وحدَه مفروك»)، فثالثٌ يضاعفه.
///
/// و[open] هي كلُّ ما كان يربطه بالشجرة: من يريد **وصفَ** الكتالوج لا فتحَه
/// يمرّر دالّةً لا تفعل شيئاً، فيقرأ العناوينَ والمعرّفاتِ والصلاحيّاتِ
/// من عين ما يُفتَح منه.
List<PicposReportCategory> buildPicposReportCatalog({
  required PicposReportActions actions,
  required String? eInvoicePlatform,
}) {
    return [
      PicposReportCategory(
        id: 'sales',
        title: tr('تقارير المبيعات'),
        icon: PhosphorIconsBold.chartLineUp,
        color: AppColors.success,
        mainReports: [
          PicposReportEntry(
            id: 'sales_main',
            title: tr('تقرير المبيعات'),
            subtitle: tr('تقرير المبيعات الرئيسي بكافة الفلاتر'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesReportScreen()),
          ),
          PicposReportEntry(
            id: 'sales_summary',
            title: tr('ملخص المبيعات'),
            subtitle: tr('نظرة سريعة بأرقام اليوم'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesReportScreen()),
          ),
          // منسوخٌ عن الأصل (`screens/reports_screen.dart`) — الشاشةُ الوجهةُ
          // نفسُها بلا تعديل. الكتالوجُ وحدَه مفروك، فالبطاقةُ تُضاف في
          // الاثنين معاً وإلّا ظهر التقريرُ في هويّةٍ وغاب عن الأخرى.
          PicposReportEntry(
            id: 'tables_report',
            title: tr('تقرير الطاولات'),
            subtitle: tr('الإيراد ودوران الطاولة ونصيب الضيف لكل قسم وطاولة'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const TablesReportScreen()),
          ),
        ],
        shortcuts: [
           PicposReportShortcut('s_today', tr('مبيعات اليوم'), 'sales_main'),
           PicposReportShortcut('s_range', tr('من تاريخ إلى تاريخ'), 'sales_main'),
          // ⚠️ كانت بلا `action` فتسقط على `parent.action()` = تقريرُ
          // المبيعات العامّ **بلا أيّ ترشيحٍ بالكاشير** — وهو بعينه العطبُ
          // الموثَّقُ فوق لشريحة «حسب المجموعة»، ومصدرُ بلاغ المالك
          // 2026-08-14 «التقريرُ حسب المستخدم غيرُ دقيق»: الشريحةُ تَعِد
          // بترشيحٍ لا يقع.
          PicposReportShortcut('s_cashier', tr('حسب الكاشير'), 'sales_main',
              action: () => actions.open(() => const ShiftsReportScreen())),
           PicposReportShortcut('s_branch', tr('حسب الفرع'), 'sales_main'),
          PicposReportShortcut('s_product', tr('حسب الصنف'), 'sales_main',
              action: () => actions.open(() => const TopProductsReportScreen())),
          PicposReportShortcut('s_group', tr('حسب المجموعة'), 'sales_main',
              action: () => actions.open(() => const SalesByClassificationReport())),
           PicposReportShortcut('s_payment', tr('حسب طريقة الدفع'), 'sales_main'),
           PicposReportShortcut(
              's_credit', tr('مبيعات آجل / نقدي / فيزا'), 'sales_main'),
        ],
      ),
      PicposReportCategory(
        id: 'profit',
        title: tr('تقارير الأرباح'),
        icon: PhosphorIconsBold.money,
        color: AppColors.successDark,
        mainReports: [
          PicposReportEntry(
            id: 'category_profit',
            title: tr('أرباح التصنيفات'),
            subtitle: tr('تحليل تكلفة المبيعات وصافي الربح لكل تصنيف'),
            permission: 'reports_category_profit',
            action: () => actions.open(() => const CategoryProfitReportScreen()),
          ),
          PicposReportEntry(
            id: 'consumption',
            title: tr('تقرير استهلاك الخامات'),
            subtitle: tr('استهلاك الخامات وربحية المنتجات (auto-deplete)'),
            permission: 'reports_category_profit',
            action: () => actions.open(() => const ConsumptionReportScreen()),
          ),
          PicposReportEntry(
            id: 'top_profitable',
            title: tr('الأصناف الأكثر ربحية'),
            subtitle: tr('ترتيب المنتجات حسب الربح'),
            action: () => actions.open(() => const TopProductsReportScreen()),
          ),
          PicposReportEntry(
            id: 'profit_margin',
            title: tr('هامش الربح'),
            subtitle: tr('تحليل هامش الربح حسب الفئة'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: profitMarginReport()),
            ),
          ),
        ],
        shortcuts: [
           PicposReportShortcut('p_invoice', tr('ربح كل فاتورة'), 'category_profit'),
          PicposReportShortcut('p_product', tr('ربح كل صنف'), 'category_profit',
              action: () => actions.open(() => const TopProductsReportScreen())),
          PicposReportShortcut('p_group', tr('حسب المجموعة'), 'category_profit',
              action: () => actions.open(() => const CategoryProfitReportScreen())),
          // تقريرُ أرباح التصنيفات **لا مرشِّحَ مستخدمٍ فيه أصلاً** (مقيسٌ:
          // صفرُ ذكرٍ لـ`_selectedUserId`)، فالشريحةُ كانت تَعِد بما لا
          // يستطيعه المصدر. وجهتُها «الإغلاق حسب المستخدم» حيث الأرقامُ
          // مبوّبةٌ بالاسم فعلاً.
          PicposReportShortcut('p_cashier', tr('حسب الكاشير'), 'category_profit',
              action: () => actions.open(() => const ShiftsReportScreen())),
           PicposReportShortcut('p_branch', tr('حسب الفرع'), 'category_profit'),
        ],
      ),
      PicposReportCategory(
        id: 'returns',
        title: tr('تقارير المرتجعات'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        color: AppColors.error,
        mainReports: [
          PicposReportEntry(
            id: 'sales_returns',
            title: tr('مرتجعات المبيعات'),
            subtitle: tr('تحليل مرتجعات المبيعات والمبالغ المستردة'),
            action: () => actions.open(() => const SalesReturnsReportScreen()),
          ),
          PicposReportEntry(
            id: 'purchase_returns',
            title: tr('مرتجعات المشتريات'),
            subtitle: tr('تحليل مرتجعات المشتريات من الموردين'),
            action: () => actions.open(() => const PurchaseReturnsReportScreen()),
          ),
        ],
        // ⚠️ `r_cashier` («حسب الكاشير») **أُزيلت** 2026-08-14: تقريرُ
        // مرتجعات المبيعات لا مرشِّحَ مستخدمٍ فيه إطلاقاً (صفرُ ذكرٍ لـ
        // `_selectedUserId` فيه)، والشريحةُ كانت بلا `action` فتسقط على
        // التقرير العامّ وتعرض مرتجعاتِ **كلّ** الكاشيرين تحت عنوانٍ يقول
        // «حسب الكاشير». وهذا بعينه بلاغُ المالك «التقريرُ حسب المستخدم غيرُ
        // دقيق». وإعادتُها تحتاج مرشِّحَ مستخدمٍ في التقرير نفسِه — بندٌ
        // مستقلٌّ مصرَّحٌ به عند التسليم، لا شريحةٌ تكذب.
        shortcuts:  [
          PicposReportShortcut('r_today', tr('مرتجعات اليوم'), 'sales_returns'),
          PicposReportShortcut('r_product', tr('حسب الصنف'), 'sales_returns'),
          PicposReportShortcut('r_customer', tr('حسب العميل'), 'sales_returns'),
        ],
      ),
      PicposReportCategory(
        id: 'inventory',
        title: tr('تقارير المخزون'),
        icon: PhosphorIconsBold.warehouse,
        color: AppColors.info,
        mainReports: [
          PicposReportEntry(
            id: 'inv_current',
            title: tr('تقرير المخزون الحالي'),
            subtitle: tr('أرصدة وقيم المخزون بالتكلفة والبيع'),
            action: () => actions.open(() => const InventoryReportScreen()),
          ),
          PicposReportEntry(
            id: 'inv_gl_reconciliation',
            title: tr('تسوية المخزون مع الأستاذ العام'),
            subtitle: tr('مقارنة قيمة المخزون بحساب 1136 ومصادر الفروق'),
            action: actions.showInventoryGlReconciliation,
          ),
          PicposReportEntry(
            id: 'inv_movement',
            title: tr('حركة الأصناف'),
            subtitle: tr('كرت صنف تفصيلي مع كل العمليات'),
            action: () => actions.open(() => const StockMovementsScreen()),
          ),
          PicposReportEntry(
            id: 'inv_stocktake',
            title: tr('تقرير الجرد'),
            subtitle: tr('تقرير الجرد الدوري والفروق'),
            action: () => actions.open(() => const StockAuditScreen()),
          ),
          PicposReportEntry(
            id: 'inv_top_selling',
            title: tr('الأصناف الأكثر مبيعاً'),
            subtitle: tr('تحليل الأصناف الأعلى طلباً والأكثر ربحية'),
            action: () => actions.open(() => const TopProductsReportScreen()),
          ),
          PicposReportEntry(
            id: 'low_stock',
            title: tr('أصناف منخفضة المخزون'),
            subtitle: tr('قائمة الأصناف التي وصلت لحد الطلب'),
            action: actions.showLowStock,
          ),
          PicposReportEntry(
            id: 'expired_products',
            title: tr('منتجات منتهية الصلاحية'),
            subtitle: tr('قائمة الأصناف التي انتهت صلاحيتها وتحتاج إعدام'),
            action: actions.showExpired,
          ),
          PicposReportEntry(
            id: 'expiring_products',
            title: tr('منتجات قاربت على الانتهاء'),
            subtitle: tr('تنتهي صلاحيتها خلال الـ 30 يوماً القادمة'),
            action: actions.showExpiring,
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('i_low', tr('قليلة المخزون'), 'low_stock'),
          PicposReportShortcut('i_dead', tr('الأصناف الراكدة'), 'inv_movement'),
        ],
      ),
      PicposReportCategory(
        id: 'purchases',
        title: tr('تقارير المشتريات'),
        icon: PhosphorIconsBold.shoppingCart,
        color: const Color(0xFFD97706),
        mainReports: [
          PicposReportEntry(
            id: 'purch_main',
            title: tr('تقرير المشتريات'),
            subtitle: tr('تقرير المشتريات بفلاتر كاملة'),
            action: () => actions.open(() => const PurchasesReportScreen()),
          ),
          PicposReportEntry(
            id: 'purch_orders',
            title: tr('أوامر الشراء'),
            subtitle: tr('متابعة أوامر الشراء المفتوحة'),
            action: () => actions.open(() => const PurchaseOrdersScreen()),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('pu_today', tr('مشتريات اليوم'), 'purch_main'),
          PicposReportShortcut('pu_supplier', tr('حسب المورد'), 'purch_main'),
          PicposReportShortcut('pu_product', tr('حسب الصنف'), 'purch_main'),
          PicposReportShortcut('pu_branch', tr('حسب الفرع'), 'purch_main'),
        ],
      ),
      PicposReportCategory(
        id: 'customers',
        title: tr('تقارير العملاء'),
        icon: PhosphorIconsBold.users,
        color: const Color(0xFF8B5CF6),
        mainReports: [
          PicposReportEntry(
            id: 'cust_statement',
            title: tr('كشف حساب العميل'),
            subtitle: tr('كشف حساب تفصيلي بالحركات'),
            action: () => actions.open(() => const PartyStatementPicposScreen()),
          ),
          PicposReportEntry(
            id: 'cust_aging',
            title: tr('تقادم ذمم العملاء'),
            subtitle: tr('الذمم المتأخرة بشرائح الأيام'),
            action: () => actions.open(() => const ArAgingReportPicposScreen()),
          ),
          PicposReportEntry(
            id: 'cust_behavior',
            title: tr('تحليل سلوك العملاء'),
            subtitle: tr('تكرار الشراء ومتوسط الفاتورة'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: partyBehaviorReport(suppliers: false)),
            ),
          ),
          PicposReportEntry(
            id: 'cust_reconciliation',
            title: tr('تسوية الذمم مع الأستاذ العام'),
            subtitle: tr('مقارنة أرصدة العملاء مع حساب الذمم'),
            action: actions.showArReconciliation,
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('c_sales', tr('مبيعات العميل'), 'cust_statement'),
          PicposReportShortcut('c_collect', tr('تحصيلات العملاء'), 'cust_statement'),
          PicposReportShortcut('c_debt', tr('العملاء المديونين'), 'cust_aging'),
          PicposReportShortcut('c_top', tr('حسب حجم المبيعات'), 'cust_behavior'),
        ],
      ),
      // المرحلة و — تقاريرُ المناديب: من الختم لا من المسار الحاليّ.
      PicposReportCategory(
        id: 'reps',
        title: tr('تقارير المناديب'),
        icon: PhosphorIconsBold.truck,
        color: const Color(0xFF0D9488),
        mainReports: [
          for (final kind in RepReportKind.values)
            PicposReportEntry(
              id: kind.id,
              title: kind.title,
              subtitle: kind.subtitle,
              permission: PermissionCodes.distributionView,
              action: () =>
                  actions.open(() => RepReportsPicposScreen(kind: kind)),
            ),
        ],
        shortcuts: const [],
      ),
      PicposReportCategory(
        id: 'suppliers',
        title: tr('تقارير الموردين'),
        icon: PhosphorIconsBold.truck,
        color: const Color(0xFFEA580C),
        mainReports: [
          PicposReportEntry(
            id: 'sup_statement',
            title: tr('كشف حساب المورد'),
            subtitle: tr('كشف تفصيلي بالحركات'),
            // دفعة ١٢ — الفئة كلها كانت بتترسم لأي حد معاه reports_view
            // (حقل permission اختياري، ولما يبقى null التايل بيظهر بلا فحص).
            permission: PermissionCodes.reportsSuppliers,
            action: () =>
                actions.open(() => const PartyStatementPicposScreen(isSupplier: true)),
          ),
          PicposReportEntry(
            id: 'sup_behavior',
            title: tr('تحليل سلوك الموردين'),
            subtitle: tr('الموردون النشطون وحجم التعامل'),
            permission: PermissionCodes.reportsSuppliers,
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: partyBehaviorReport(suppliers: true)),
            ),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('su_purch', tr('مشتريات المورد'), 'sup_statement'),
          PicposReportShortcut('su_debt', tr('مديونية الموردين'), 'sup_statement'),
          PicposReportShortcut('su_pay', tr('دفعات الموردين'), 'sup_statement'),
          PicposReportShortcut('su_top', tr('حسب حجم الشراء'), 'sup_behavior'),
        ],
      ),
      PicposReportCategory(
        id: 'cashbox',
        title: tr('الصناديق والكاش'),
        icon: PhosphorIconsBold.wallet,
        color: AppColors.primary,
        mainReports: [
          PicposReportEntry(
            id: 'cb_treasury',
            title: tr('حركة الخزينة'),
            subtitle: tr('سجل المقبوضات والمدفوعات والمصروفات'),
            permission: PermissionCodes.reportsTreasury,
            action: () => actions.open(() => const TreasuryReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_shifts',
            title: tr('تقرير الورديات'),
            subtitle: tr('فتح وتسكير الورديات وعجز النقدية'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const ShiftsReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_delivery',
            title: tr('تقرير عمليات التوصيل'),
            subtitle: tr('إحصائيات المناديب ورسوم شركات التوصيل'),
            action: () => actions.open(() => const DeliveryReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_expenses',
            title: tr('تقرير المصروفات التشغيلية'),
            subtitle: tr('إجمالي المصروفات حسب الفئة والفرع والفترة'),
            action: () => actions.open(() => const ExpensesReportScreen()),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('cb_open', tr('فتح وإغلاق الصندوق'), 'cb_shifts'),
          PicposReportShortcut('cb_diff', tr('العجز والزيادة'), 'cb_shifts'),
          PicposReportShortcut('cb_in_out', tr('المقبوضات والمدفوعات'), 'cb_treasury'),
          PicposReportShortcut('cb_methods', tr('نقدي / فيزا / آجل'), 'cb_treasury'),
        ],
      ),
      PicposReportCategory(
        id: 'users',
        title: tr('تقارير المستخدمين'),
        icon: PhosphorIconsBold.userCircle,
        color: const Color(0xFF7C3AED),
        mainReports: [
          // ⚠️ الثلاثةُ كانت **بلا `permission:`** حتى 2026-08-13، والمُصيِّر
          // لا يلفّ إلا ما له كود (`r.permission != null` أدناه). فكانت
          // «التقارير» باباً خلفياً: من يملك `reports_view` وحدَه يفتح سجلَّ
          // النشاط، و**شاشةَ إدارة المستخدمين** التي فيها إسنادُ الأدوار
          // وتصفيرُ كلمات المرور — أي تصعيدُ امتيازٍ كامل. والبابُ الأماميُّ
          // لنفس الشاشة محروسٌ في `settings_picpos_screen.dart:654`.
          PicposReportEntry(
            id: 'u_activity',
            title: tr('نشاط المستخدمين'),
            subtitle: tr('العمليات لكل مستخدم'),
            permission: PermissionCodes.auditView,
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: userActivityReport()),
            ),
          ),
          PicposReportEntry(
            id: 'u_login',
            title: tr('سجل دخول المستخدمين'),
            subtitle: tr('متى دخل كل مستخدم وخرج'),
            permission: PermissionCodes.auditView,
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل دخول المستخدمين'),
                presetSubtitle: tr('من دخل ومتى خرج — بما فيه ترقية الصلاحيات'),
                presetCategory: 'auth',
              ),
            ),
          ),
          PicposReportEntry(
            id: 'u_perms',
            title: tr('صلاحيات المستخدمين'),
            subtitle: tr('مصفوفة صلاحيات لكل دور ومستخدم'),
            // مهمة 14: هذا الفورك (reports_picpos_screen.dart) خاص بـ PicPos
            // فقط (Brand.isPicPos) — فالـ push يروح مباشرة لشاشة المستخدمين
            // بهوية PicPos، بلا حاجة لفحص العلامة هنا.
            permission: PermissionCodes.usersManage,
            action: () => actions.open(() => const UsersManagementPicposScreen()),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'branches',
        title: tr('تقارير الفروع'),
        icon: PhosphorIconsBold.buildings,
        color: const Color(0xFF0891B2),
        mainReports: [
          PicposReportEntry(
            id: 'br_performance',
            title: tr('أداء الفروع'),
            subtitle: tr('مقارنة مبيعات وأرباح الفروع'),
            action: () => actions.open(() => const BranchPerformanceScreen()),
          ),
          PicposReportEntry(
            id: 'br_transfers',
            title: tr('التحويلات بين الفروع'),
            subtitle: tr('سجل التحويلات وحركة المخزون'),
            action: () => actions.open(() => const StockMovementsScreen()),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'taxes',
        title: tr('تقارير الضرائب'),
        icon: PhosphorIconsBold.percent,
        color: const Color(0xFF0369A1),
        mainReports: [
          PicposReportEntry(
            id: 'tx_main',
            title: tr('تقرير ضريبة المبيعات'),
            subtitle: tr('الضرائب المحصلة والمدفوعة وصافي الالتزام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => actions.open(() => const TaxReportScreen()),
          ),
          PicposReportEntry(
            id: 'tx_vat_recon',
            title: tr('تسوية ضريبة القيمة المضافة'),
            subtitle: tr('مقارنة ضريبة الفواتير مع الأستاذ العام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => actions.open(() => const VatReconciliationScreen()),
          ),
          if (eInvoicePlatform != null)
            PicposReportEntry(
              id: 'tx_einvoice',
              title: tr('تقرير الفوترة الإلكترونية'),
              subtitle: tr('متابعة حالات الإرسال والقبول من الضرائب'),
              action: () => actions.open(() => const EInvoiceDashboardScreen()),
            ),
        ],
        shortcuts:  [
          PicposReportShortcut('tx_sales', tr('ضرائب المبيعات'), 'tx_main'),
          PicposReportShortcut('tx_purch', tr('ضرائب المشتريات'), 'tx_main'),
        ],
      ),
      PicposReportCategory(
        id: 'audit',
        title: tr('الحركة والسجلات'),
        icon: PhosphorIconsBold.listChecks,
        color: AppColors.errorDark,
        mainReports: [
          PicposReportEntry(
            id: 'a_ops',
            title: tr('سجل العمليات'),
            subtitle: tr('كل العمليات في النظام'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل العمليات'),
                presetSubtitle: tr('كل ما جرى على النظام بلا ترشيح'),
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_edits',
            title: tr('سجل التعديلات'),
            subtitle: tr('الفواتير والمستندات المعدلة'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل التعديلات'),
                presetSubtitle: tr('تعديلٌ وقع على مستندٍ صادر'),
                presetActions: ActivityLogPresets.documentEdits,
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_print',
            title: tr('سجل الطباعة'),
            subtitle: tr('متى طُبع كل مستند ومن قبل من'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل الطباعة'),
                presetSubtitle: tr('كل طباعةٍ بمن نفّذها ووقتها'),
                presetActions: ActivityLogPresets.printed,
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_void',
            title: tr('سجل الإلغاءات'),
            subtitle: tr('الفواتير الملغاة وأسبابها'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل الإلغاءات'),
                presetSubtitle: tr('إلغاءُ مستندٍ صادرٍ أو حذفُه'),
                presetActions: ActivityLogPresets.voided,
              ),
            ),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'analytics',
        title: tr('التحليلات والإحصائيات'),
        icon: PhosphorIconsBold.chartDonut,
        color: const Color(0xFFA21CAF),
        mainReports: [
          PicposReportEntry(
            id: 'an_sales',
            title: tr('تحليل المبيعات'),
            subtitle: tr('اتجاهات وأنماط المبيعات'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: salesTrendReport()),
            ),
          ),
          PicposReportEntry(
            id: 'an_classifications',
            title: tr('المبيعات حسب التصنيف'),
            subtitle: tr('تحليل المبيعات حسب المجموعات أو أنواع البيع'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesByClassificationReport()),
          ),
          PicposReportEntry(
            id: 'an_financial',
            title: tr('القوائم المالية الختامية'),
            subtitle: tr('الميزانية، قائمة الدخل، وميزان المراجعة (Real-time)'),
            action: () => actions.open(() => Brand.isPicPos
                ? const FinancialStatementsPicPosScreen()
                : const FinancialStatementsScreen()),
          ),
          PicposReportEntry(
            id: 'an_customers',
            title: tr('تحليل العملاء'),
            subtitle: tr('تقسيم العملاء (RFM)'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: customerSegmentsReport()),
            ),
          ),
          PicposReportEntry(
            id: 'an_inventory',
            title: tr('تحليل المخزون'),
            subtitle: tr('دوران وكفاءة المخزون'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: inventoryTurnoverReport()),
            ),
          ),
        ],
      ),
    ];
  }
// Spec 078 — Role-Permission default-grant matrix.
//
// Mirrors the role-permission seed in database_seeder_permissions.dart
// (seedRolesAndPermissions). Re-declared here as a typed, immutable
// constant so:
//   1. The pre-flight check (RoleGrantPreflightService) has a single
//      source of truth to diff against without going through the
//      seeder's imperative INSERT loops.
//   2. The Settings UI can display "this role normally has X perms"
//      to operators without re-running the seeder.
//
// Source of truth contract:
// - Fresh installs: the seeder's role-grant loops (lines ~693-880 of
//   database_seeder_permissions.dart) are authoritative.
// - Existing installs after upgrade: this matrix tells the operator
//   which perms SHOULD have been granted but weren't (because the
//   seeder only runs on fresh install). The UI's "grant defaults"
//   button INSERT-OR-IGNOREs from this matrix.
//
// **Drift detector**: a unit test (role_grant_matrix_test.dart) reads
// the seeder source and asserts each role's list matches the matrix
// below — change the seeder, this test fails until you mirror the
// change here. Prevents silent divergence between the two declarations.
//
// **Admin role**: gets a catch-all in the seeder (every perm except
// `criticalFinancialOps`) AND syncAllPermissions auto-grants new
// perms to admin on every server-mode boot. So in theory admin
// never needs an entry here.
//
// **In practice** (Spec 086, field 2026-05-19): on at least one
// production server the auto-grant in `syncAllPermissions` silently
// missed `branches_manage`, `pos_shift_open`, `pos_shift_close` —
// admin hit 403 on shift open/close and branch insert through the
// mirror. Root cause undetermined (raw SQL `ON CONFLICT DO NOTHING`
// against composite PK + per-row try blocks make individual failures
// invisible). Adding a minimal safety-net entry below makes the
// matrix-based self-heal (`grantMissingDefaults`) treat admin like
// any other role for THESE specific codes — defense in depth.

class RoleGrantMatrix {
  RoleGrantMatrix._();

  /// Role name (Arabic, as inserted by the seeder) → set of perm
  /// codes that role SHOULD have for default operation.
  ///
  /// "Should have" means: without these, the user in that role will
  /// hit 403 on common server endpoints once Spec 077's flag is ON.
  static const Map<String, Set<String>> defaultGrants = {
    // Spec 086 — safety net for admin essentials. NOT a full admin
    // perm list (the seeder + syncAllPermissions catch-all are still
    // authoritative for the complete set). These are the codes that
    // field smoke (2026-05-19, mirror V148) caught silently missing
    // and that block core POS / branch flows when absent.
    'مدير النظام': {
      'branches_manage',
      'pos_shift_open',
      'pos_shift_close',
      // Dashboard بقت متبوّبة بـ`dashboard_access` بدل `pos_access`. الكود ده
      // بيتمنح لكل دور تشغيلي عشان الترقية ما تسحبش الشاشة من حد — السحب
      // قرار المدير، مش أثر جانبي للإصلاح.
      'dashboard_access',
      // Task 6a — نفس منطق سبب٠٨٦ فوق: الأكواد الستة دي مش في أي قايمة
      // أدوار ثابتة في السيدر (`assets_view`/`distribution_view`/
      // `einvoice_view`/`manufacturing_view` مالهاش دور غير مدير النظام
      // أصلاً)، فـ`syncAllPermissions` هي اللي بتمنحها لمدير النظام وقت
      // التشغيل — مش `seedRolesAndPermissions` الثابت. سجل سبب٠٨٦ نفسه
      // بيقول إن اللوب ده فشل بصمت لأكواد معيّنة على سيرفر إنتاج فعلي.
      // إضافتها هنا كخط دفاع تاني بتخلي `grantMissingDefaults` (زرار
      // «منح الصلاحيات الافتراضية») قادر يصلّح تركيبة قديمة اتصاب بنفس
      // الفشل الصامت، من غير ما نمنح أي دور تاني حاجة مكانش عنده.
      // ملحوظة: `modify_closed_period` اتقصد قصداً برّه القايمة دي —
      // كود فصل سلطات (segregation of duties)، ما ينفعش يتمنح تلقائياً
      // ولا حتى لمدير النظام.
      'assets_manage',
      'assets_depreciation',
      'distribution_manage',
      'einvoice_submit',
      'einvoice_cancel',
      'manufacturing_manage',
      // Task 6b — نفس المنطق بالظبط: `kitchen_view`/`loyalty_view`/
      // `offers_view`/`tables_view` مالهاش دور غير مدير النظام في أي قايمة
      // ثابتة تحت (نفس حالة الأربعة كودات فوق)، فـ`syncAllPermissions` هي
      // اللي بتمنح الأكواد دي وقت التشغيل. إضافتهم هنا خط دفاع تاني بس، مش
      // منحة جديدة.
      'kitchen_manage',
      'loyalty_manage',
      'modifiers_manage',
      'offers_create',
      'offers_edit',
      'offers_delete',
      'tables_manage',
      // Task 7 — نفس المنطق بالظبط: الأكواد التمانية دي (البيع السريع) مش في
      // أي قايمة أدوار ثابتة في السيدر أصلاً — حتى الأكواد الشقيقة المنفَّذة
      // فعلاً من قبل زي pos_search/pos_table_select/pos_clear_cart مش موجودة
      // هناك برضه. الوضع الطبيعي لأكواد البيع السريع الدقيقة دي إن المدير هو
      // اللي يفعّلها لكل دور من شاشة «الأدوار والصلاحيات» حسب احتياج الفرع —
      // مش منحة افتراضية للأدوار المزروعة. إضافتها هنا خط دفاع تاني بس
      // (زي سبب٠٨٦) عشان زرار «منح الصلاحيات الافتراضية» يقدر يصلّح مدير
      // النظام لو syncAllPermissions فشل بصمت، مش منحة جديدة لأي دور تشغيلي.
      'pos_customer_add',
      'pos_expense_description',
      'pos_grid_toggle',
      'pos_low_stock_alert',
      'pos_note_add',
      'pos_notifications',
      'pos_weight_dialog',
      'pos_work_order',
      // دفعة ٨ — نفس المنطق: الستة دول مش في أي قايمة أدوار ثابتة كانت
      // بتخص مدير النظام (بياخدهم من حلقة «كل الصلاحيات ما عدا الحرجة» +
      // `syncAllPermissions`)، والمدخل هنا خط دفاع تاني بس زي سبب٠٨٦.
      'products_price_view',
      'products_cost_view',
      'products_stock_view',
      'products_lock',
      'products_expiry',
      'products_image',
      // دفعة ٩ — نفس المنطق (خط دفاع تاني لمدير النظام).
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'sales_return_delete',
      'purchases_print',
      'purchases_return_print',
      // دفعة ١٠ — إعدادات على مستوى النظام. **ولا دور تشغيلي بياخدها**:
      // كل حرّاسها بتجاوز مدير يعني مفيش منع نهائي، والنهارده أي دور معاه
      // `settings_view` (مدير فرع/محاسب متقدم) يقدر يبدّل وصلة قاعدة
      // البيانات أو يغيّر عملة النظام — وده بالظبط اللي الأكواد دي موجودة
      // عشانه. المدخل هنا خط دفاع تاني لمدير النظام بس.
      'settings_company',
      'settings_currency',
      'settings_pos_edit',
      'settings_tax',
      'system_database',
      'system_license',
      // دفعة ١١ — كروت/رسوم لوحة التحكم.
      'dashboard_sales_today',
      'dashboard_chart',
      'dashboard_alerts',
      // دفعة ١٢ — التقارير.
      'reports_suppliers',
      'reports_delivery_recon',
      // التكاليف المحمَّلة — نفس منطق `assets_depreciation` فوق حرفاً بحرف:
      // كودٌ جديدٌ مالوش دور تشغيلي في أي قايمة ثابتة تحت، فـ`syncAllPermissions`
      // هي اللي بتمنحه لمدير النظام وقت التشغيل — وهي اللي فشلت بصمت على
      // سيرفر إنتاج فعلي (سبب٠٨٦). المدخل هنا خط دفاع تاني بس عشان زرار «منح
      // الصلاحيات الافتراضية» يقدر يصلّح، مش منحة جديدة لأي دور.
      //
      // ⚠️ ومنحه لدور تشغيلي (مخزني/محاسب) قرار مالك مش أثر جانبي للإصلاح:
      // التطبيق بيرحّل قيد يومية وبيحرّك تكلفة كل صنف في الفاتورة.
      'landed_cost_apply',
    },
    // دفعة ١١ — `dashboard_alerts` (بانر تنبيه نقص المخزون) اتمنح لكل دور
    // تشغيلي تحت: الحارس بتاعه إخفاء بلا تجاوز مدير، وكل دور بيشوف اللوحة
    // النهارده بيشوف البانر، فمن غير المنحة الترقية بتشيله — والتنبيه ده شغل
    // يومي لأمين المخزن.
    //
    // بالمقابل `dashboard_sales_today` و`dashboard_chart` **ما اتمنحوش لأي
    // دور تشغيلي عن قصد**: دول بيانات فلوس (صافي الإيراد، هامش الربح،
    // تركيبة الإيراد) — نفس فئة `dashboard_profit` و`treasury_balance_view`
    // اللي مش ممنوحين لأي دور أصلاً. منح الرسوم كان هيسرّب هامش الربح من
    // القوس بينما كارت الربح نفسه مموّه.
    'كاشير': {
      'pos_access',
      'pos_hold_order',
      'pos_save',
      'pos_print',
      'pos_shift_open',
      'pos_shift_close',
      // 2026-08-13 — شريحةُ «توصيل» في لوحة الدفع صارت محروسةً بـ
      // `pos_delivery` (قرارُ المالك). وبلا المنحة يطلب **كلُّ** طلبِ توصيلٍ
      // كلمةَ مرور مسؤول — كسرُ شغلٍ لا تأمين، وهو نفسُ منطق منحة
      // `sales_amounts_view` أدناه.
      'pos_delivery',
      // 2026-08-16 — قرارُ المالك: زرُّ «مرتجع سريع» ومحرِّرُ أسطره في
      // شاشة بيع PicPos صارا محروسَين بـ`pos_return`/`pos_item_plus`/
      // `pos_item_minus` (حارسُ التكافؤ رصد وصولَهما). هذه أفعالٌ يوميّةٌ
      // للكاشير الأساسي، وإنفاذُها بلا منحٍ كان سيجعل كلَّ ضغطةِ «+» أو
      // فتحِ وضع المرتجع تطلب موافقةَ مسؤول — كسرُ شغلٍ لا تأمين، بنفس
      // منطق `pos_delivery` فوق. (‏`pos_return` كان ممنوحاً سلفاً لـ«كاشير
      // متقدم»/«مدير فرع» وحدهما؛ القرارُ اليوم يضيف الكاشيرَ الأساسيّ.)
      'pos_return',
      'pos_item_plus',
      'pos_item_minus',
      // Spec 084 — Spec 077 gates `/api/sales` POST on `sales_create`.
      // Without it the entire POS path dies (4× DEAD-LETTER per session).
      // `sales_view` lets the cashier list their previous invoices.
      'sales_create',
      'sales_view',
      'dashboard_access',
      'dashboard_alerts',
      // دفعة ٩ — `sales_amounts_view` بيحجب مبالغ قائمة فواتير البيع، وأي
      // دور معاه `sales_view` كان بيشوفها النهارده. الطباعة بتجاوز مدير
      // فمش منع، بس كلمة سر مع كل طباعة مش قابلة للاستعمال.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
    },
    'مخزني': {
      'inventory_view',
      'inventory_edit',
      'products_view',
      'products_add',
      'products_edit',
      'suppliers_view',
      'purchases_create',
      'categories_view',
      'dashboard_access',
      'dashboard_alerts',
      // دفعة ٨ — الأعمدة والأقسام دي كانت مكشوفة لأي دور يفتح شاشة الأصناف
      // (أكواد بلا إنفاذ). بعد ما اتحطّ عليها حرّاس، الدور ده لازم ياخدها
      // في **مسار الترقية** كمان مش في التركيب الجديد بس — المصفوفة هي
      // اللي `grantMissingDefaults()` بيقرا منها للتركيبات القايمة.
      'products_price_view',
      'products_cost_view',
      'products_stock_view',
      'products_lock',
      'products_expiry',
      'products_image',
      // دفعة ٩ — الدور ده معاه `purchases_create` بس (مالوش `sales_view`).
      'purchases_print',
      'purchases_return_print',
    },
    'محاسب': {
      'reports_view',
      'reports_export',
      // دفعة ١٢ — كشف حساب المورد شغل يومي للدور ده (معاه reports_view
      // و suppliers_view)؛ من غير المنحة كل فتحة تستنى موافقة مدير.
      'reports_suppliers',
      'treasury_view',
      'customers_view',
      'suppliers_view',
      'sales_view',
      'purchases_view',
      'dashboard_access',
      'dashboard_alerts',
      // Task 3d — عنصر قائمة «التحليلات» كان على reports_view العام
      // بينما screenPermissionMap يربط الشاشة بـ analytics_view. هذا
      // الدور عنده reports_view فكان بيشوف الرابط قبل الإصلاح؛ الكود
      // ده بيتمنح هنا عشان الإصلاح ما يسحبش الرابط لوحده — السحب قرار
      // المدير.
      'analytics_view',
      // دفعة ٩ — معاه `sales_view` و`purchases_view` فبيفتح القايمتين.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'purchases_print',
      'purchases_return_print',
    },
    'مدير مالي': {
      // Inherits the full accountant set
      'reports_view',
      'reports_export',
      // دفعة ١٢ — كشف حساب المورد شغل يومي للدور ده (معاه reports_view
      // و suppliers_view)؛ من غير المنحة كل فتحة تستنى موافقة مدير.
      'reports_suppliers',
      'treasury_view',
      'customers_view',
      'suppliers_view',
      'sales_view',
      'purchases_view',
      'dashboard_access',
      'dashboard_alerts',
      // FM-only extras (Spec 077 Batch 0.5)
      'commercial_papers_manage',
      // Task 3d — نفس منطق analytics_view فوق (محاسب).
      'analytics_view',
      // دفعة ٩ — بيورّث طقم المحاسب (السيدر بينفّذ نفس القايمة للدورين).
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'purchases_print',
      'purchases_return_print',
      // §٤ — `isOriginallyManager` فحصُ نصٍّ على اسم الدور، فكلُّ دورٍ اسمُه
      // يحوي «مدير» مُعفىً اليومَ من حوار كلمة مرور القائمة الجانبية بلا نظرٍ
      // في صلاحياته. والمنحةُ هنا تجعل المربّعَ في شاشة الصلاحيات موافقاً
      // للواقع بدل أن يظهر مطفأً والدورُ مُعفىً فعلاً.
      'system_sidebar_open',
    },
    'كاشير متقدم': {
      'pos_access',
      'pos_discount',
      'pos_return',
      'pos_payment_cash',
      'pos_payment_card',
      'pos_hold_order',
      'customers_view',
      'pos_shift_open',
      'pos_shift_close',
      // Spec 084 — same gap as basic cashier.
      'sales_create',
      'sales_view',
      'dashboard_access',
      'dashboard_alerts',
      // دفعة ٩ — نفس منحة الكاشير العادي.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      // 2026-08-16 — قرارُ المالك: زرّا «+»/«−» في محرِّر أسطر المرتجع
      // (شاشة PicPos) صارا محروسَين. نفسُ سبب منحة «كاشير» فوق.
      'pos_item_plus',
      'pos_item_minus',
    },
    'مدير فرع': {
      // Inherits advanced cashier
      'pos_access',
      'pos_discount',
      'pos_return',
      'pos_payment_cash',
      'pos_payment_card',
      'pos_hold_order',
      'customers_view',
      'pos_shift_open',
      'pos_shift_close',
      // 2026-08-16 — قرارُ المالك: نفسُ سبب منحة «كاشير متقدم» (الدورُ يرثه
      // مفهومياً هنا).
      'pos_item_plus',
      'pos_item_minus',
      // Spec 084 — branch manager must be able to ring sales too.
      'sales_create',
      // Plus branch-manager extras
      'inventory_view',
      'reports_view',
      'treasury_view',
      'pos_closing_view_details',
      'products_add',
      'branches_manage',
      'users_manage',
      'sales_view',
      'purchases_create',
      'settings_view',
      'dashboard_access',
      'dashboard_alerts',
      // Task 3d — نفس منطق analytics_view (محاسب فوق): الدور ده عنده
      // reports_view فكان بيشوف رابط «التحليلات» قبل ما نربطه بكوده
      // الخاص.
      'analytics_view',
      // دفعة ٨ — نفس سبب «مخزني» فوق: `products_add` بيفتح شاشة الأصناف.
      'products_price_view',
      'products_cost_view',
      'products_stock_view',
      'products_lock',
      'products_expiry',
      'products_image',
      // دفعة ٩ — بيورّث طقم الكاشير المتقدم (مبيعات) + `purchases_create`.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'purchases_print',
      'purchases_return_print',
      // §٤ — نفسُ سبب منحة «مدير مالي» فوق.
      'system_sidebar_open',
    },
    'محاسب متقدم': {
      'treasury_view',
      'reports_view',
      'settings_view',
      'pos_closing_view_details',
      'sales_view',
      'purchases_create',
      'inventory_view',
      'analytics_view',
      'dashboard_access',
      'dashboard_alerts',
      // Task 3d — عنصر قائمة «الفروع» كان على settings_view العام
      // بينما screenPermissionMap يربط الشاشة بـ branches_manage. هذا
      // الدور عنده settings_view فكان بيشوف الرابط؛ الكود ده بيتمنح هنا
      // عشان الإصلاح ما يسحبش الرابط لوحده.
      'branches_manage',
      // دفعة ٩ — `sales_view` + `purchases_create`.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'purchases_print',
      'purchases_return_print',
    },
    'مدير مخزون': {
      'inventory_view',
      'inventory_transfer',
      'products_add',
      'purchases_create',
      'reports_view',
      'sales_view',
      'dashboard_access',
      'dashboard_alerts',
      // Task 3d — نفس منطق analytics_view فوق (محاسب).
      'analytics_view',
      // دفعة ٨ — نفس سبب «مخزني» فوق: `products_add` بيفتح شاشة الأصناف.
      'products_price_view',
      'products_cost_view',
      'products_stock_view',
      'products_lock',
      'products_expiry',
      'products_image',
      // دفعة ٩ — `sales_view` + `purchases_create`.
      'sales_amounts_view',
      'sales_print',
      'sales_return_print',
      'purchases_print',
      'purchases_return_print',
      // §٤ — نفسُ سبب منحتَي «مدير مالي» و«مدير فرع» فوق.
      'system_sidebar_open',
    },
  };

  /// Roles in the matrix — for quick membership check.
  /// Custom roles created by operators won't appear here and are
  /// considered "not managed by the matrix" — the pre-flight check
  /// surfaces them with a "manual grant required" note instead of
  /// auto-granting.
  static Set<String> get knownRoleNames => defaultGrants.keys.toSet();
}

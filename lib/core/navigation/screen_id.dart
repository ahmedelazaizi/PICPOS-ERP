/// Stable identifiers for navigation entries.
///
/// The attached [index] keeps backward compatibility with the current
/// screen-index based navigation until the app is migrated completely.
/// اسمُ شاشةِ القيود — **موضعٌ واحدٌ يقرؤه الجميع**.
///
/// قرارُ المالك 2026-09-18 على تصميم الشاشة: الاسمُ يصير «اليومية العامة».
/// وكان مكتوباً في **أربعة مواضع** (المدخلُ الجانبيُّ · عنوانُ الشاشة ·
/// وسمُ التاب · بطاقةُ حاوية الحسابات)، فتغييرُ واحدٍ يترك الثلاثةَ تقول
/// غيرَه — ويقرأ المستخدمُ اسمَين لشاشةٍ واحدة.
const String journalEntriesScreenLabel = 'اليومية العامة';

/// اسمُ شاشة الأوراق التجارية — **موضعٌ واحدٌ يقرؤه الجميع**.
///
/// قرارُ المالك 2026-09-18 على تصميم الشاشة: الاسمُ يصير «إدارة الشيكات».
/// وكان مكتوباً في ثلاثة مواضعَ بصيغتَين مختلفتَين: «الشيكات» في المدخل
/// الجانبيّ وفي المُوجِّه، و«الشيكات والأوراق التجارية» عنواناً للشاشة —
/// فيقرأ المستخدمُ اسمَين لشاشةٍ واحدة.
///
/// ⚠️ **و«إدارة» ليست زينةً**: الشاشةُ تُنشئ وتُودع وتُظهِّر وتُرتجع، لا
/// تعرض وحدَها. والاسمُ القديمُ كان يَعِد بقائمةٍ فحسب.
const String chequesScreenLabel = 'إدارة الشيكات';

enum ScreenId {
  dashboard(0),
  pos(1),
  offers(2),
  tables(3),
  products(4),
  categories(5),
  parties(6),
  // index 7 is unused (reserved)
  inventory(8),
  purchases(9),
  treasury(10),
  reports(11),
  settings(12),
  branches(13),
  kitchen(14),
  analytics(15),
  hr(16),
  salesInvoices(17),
  activityLog(18),
  inventoryBonds(19),
  stockTransfer(20),
  scalePlu(21), // Alias for pluManager
  pluManager(21),
  eInvoice(22),
  loyalty(23),
  distribution(24),
  manufacturing(25),
  operationalExpenses(26),
  chartOfAccounts(27),
  fiscalYear(28),
  stockMovements(29),
  purchaseOrders(30),
  accountMapping(31),
  journalEntries(32),
  costCenters(33),
  commercialPapers(34),
  fixedAssets(35),
  generalLedger(36),
  salesOrders(37),
  stockRequisitions(38),
  branchPerformance(39),
  helpCenter(40),
  landedCost(41),
  cycleCounting(42), // Alias for fieldAudit
  fieldAudit(42),
  reportBuilder(43),
  salesReturns(44),
  purchaseReturns(45),
  budgeting(46),
  approvals(47),
  users(48),
  rolesAndPermissions(49),
  auditTrail(50),
  payroll(51),
  attendance(52),
  bankReconciliation(53),
  treasuryAdvanced(54),
  pricingRules(55),
  shiftClose(56),
  taxReports(57),
  syncConflicts(58),
  auditDashboard(59),
  // Phase 8: Region Layer
  regions(60),

  /// شاشةُ الحجوزات (‏PicPos — مطاعم ومقاهٍ وصالونات).
  ///
  /// ⚠️ ولا يكفي إضافتُها هنا ولا في `screenPermissionMap`: الحلقةُ في
  /// `userAllowedScreensProvider` تُرشِّح بـ`flavorAllowedScreenIds` **قبل**
  /// فحصِ الصلاحية، فما ليس في نطاق الملفّ يسقط حتى مع تجاوزِ مدير النظام.
  /// وهو بالضبط ما وقع لإغلاق الورديّة. ويقيسه
  /// `test/unit/bookings_screen_wiring_test.dart`.
  bookings(61),

  /// القوائمُ المالية — ميزانُ المراجعة وقائمةُ الدخل والمركزُ المالي
  /// والتدفّقاتُ النقدية.
  ///
  /// ⚠️ **نُقلت إلى مجموعة الحسابات بقرار المالك 2026-08-23**، وكانت تُفتَح
  /// من داخل شاشة التقارير بلا معرِّفِ شاشةٍ خاصٍّ بها. والسببُ مقيسٌ لا
  /// ذوقيّ: `getTrialBalance` و`getIncomeStatement` و`getBalanceSheet` تُقرأ
  /// كلُّها من جدول `accounts` وسطورِ القيود في `accounting_reports_dao` —
  /// نفسِ منبعِ دفتر الأستاذ وشجرة الحسابات. ومحاسبيّاً هي مخرَجُ دورة
  /// القيد لا تقريرٌ تشغيليّ (‏IAS 1).
  ///
  /// ⚠️ ومدخلُ التقارير **باقٍ** يشير إلى نفس الشاشة — إبقاؤه مجّانيٌّ
  /// ويحفظ عادةَ من يبحث عنها هناك.
  financialStatements(62),

  /// حاويةُ «الحسابات» — المدخلُ الوحيدُ في القائمة الجانبيّة بعد الطيّ،
  /// يفتح تبويباتِ التصميم السبعة.
  ///
  /// ⚠️ ومعرِّفاتُ التبويبات (‏[ScreenId.chartOfAccounts] وأخواتُها) **باقيةٌ**
  /// كما هي: الطيُّ يمسّ مدخلَ القائمة لا المسار. فبلوغُها المباشرُ ومنحُ
  /// صلاحيّاتِها ومدخلُ التقارير للقوائم المالية كلُّها تعمل بلا تبديل.
  accountingHub(63),

  /// شاشةُ حسم القوالب — أيُّ مستندٍ يخرج بأيِّ قالبٍ على أيِّ طابعة.
  ///
  /// ⚠️ **وصلاحيّتُها `settings_printer` القائمةُ لا صلاحيةٌ جديدة**: هي
  /// عينُ ما تحرسه شاشاتُ الطابعات في الإعدادات، وإضافةُ كودٍ جديدٍ تمسّ
  /// سجلَّ التكافؤ وتترك كلَّ دورٍ قائمٍ بلا الشاشة حتى يُمنح يدويّاً.
  templateResolution(64),

  /// «فئات الأصول» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
  ///
  /// 🔴 **ولا تُنشأ الفئةُ في PicPos اليوم إطلاقاً**: حوارا الإنشاء والتعديل
  /// (`showCreateAssetCategoryDialog` وأختُها) **جزءٌ** من شاشة UralCash
  /// (`part 'fixed_assets_dialogs.dart';` في `fixed_assets_screen.dart`)،
  /// والفوركُ لا يبلغهما. فتبويبةُ «الفئات» تعرض جدولاً للقراءة وحدَها —
  /// و`createFixedAsset` **تشترط** `categoryId`. أي أنّ شاشةَ الأصول في
  /// PicPos لا تُسجِّل أصلاً على تنصيبةٍ جديدةٍ بلا فئاتٍ مبذورة.
  ///
  /// ⚠️ **وصلاحيّتُها `assets_view` القائمةُ**: نفسُ ما تحرسه شاشةُ الأصول،
  /// وكودٌ جديدٌ يمسّ سجلَّ التكافؤ ويترك كلَّ دورٍ قائمٍ بلا الشاشة.
  assetCategories(65),

  /// «التوزيع والمواقع» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
  ///
  /// 🔴 **والموقعُ نصٌّ حرّ**: «الفرع الرئيسي» و«الفرع الرئيسى» موقعان في
  /// كلّ تجميع، فيقرأ المديرُ توزيعاً لم يقع. والشاشةُ تُعيد التسميةَ على
  /// كلّ أصلٍ يحملها — وهو العلاجُ الوحيدُ بلا جدولٍ جديد.
  assetLocations(66);

  const ScreenId(this.navigationIndex);
  final int navigationIndex;

  static ScreenId? fromIndex(int index) {
    for (final value in ScreenId.values) {
      if (value.navigationIndex == index) return value;
    }
    return null;
  }
}

/// Enum representing all navigable screens in the application.
///
/// Each screen has a unique integer [value] for backward compatibility
/// with the permission system and stored preferences.
///
/// **R-12**: Replaces magic numbers with type-safe enum values.
enum AppScreen {
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
  scalePlu(21),
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
  // Phase C: Enterprise Modules
  landedCost(41),
  cycleCounting(42),
  reportBuilder(43),
  // Phase 2 Audit: Returns Screens
  salesReturns(44),
  purchaseReturns(45),

  /// المطابقةُ البنكيّة — يجب أن تطابق `ScreenId.bankReconciliation`.
  ///
  /// 🔴 **وكانت غائبةً منذ 2026-09-01**: المعرِّفُ في خريطة
  /// الصلاحيات وفي نطاق `unified`، ولا `AppScreen` له ولا
  /// `ScreenConfig` — أي **صلاحيّةٌ تُمنَح لشاشةٍ لا شيءَ يبنيها**.
  /// وسترُها أنَّ حاويةَ «الحسابات» تفتحُها تبويباً فتتجاوز
  /// `ScreenConfig` كلَّه. ويشدُّها الآن `allowed_screens_can_render_test`.
  bankReconciliation(53),

  // Shift management
  shiftClose(56),
  // Phase 14: Hardening
  syncConflicts(58),
  auditDashboard(59),
  // Phase 8: Region Layer
  regions(60),
  bookings(61),

  /// القوائمُ المالية — يجب أن تطابق `ScreenId.financialStatements`.
  financialStatements(62),

  /// حسمُ القوالب — يجب أن تطابق `ScreenId.templateResolution`.
  templateResolution(64),

  /// فئاتُ الأصول — يجب أن تطابق `ScreenId.assetCategories`.
  assetCategories(65),

  /// التوزيعُ والمواقع — يجب أن تطابق `ScreenId.assetLocations`.
  assetLocations(66),

  /// سندُ القيد — يجب أن تطابق `ScreenId.journalVoucher`.
  journalVoucher(67),

  /// سندُ القبض — يجب أن تطابق `ScreenId.receiptVoucher`.
  receiptVoucher(68),

  /// سندُ الصرف — يجب أن تطابق `ScreenId.paymentVoucher`.
  paymentVoucher(69),

  /// دفترُ الشيكات — يجب أن تطابق `ScreenId.chequeBooks`.
  chequeBooks(70),

  /// المشتريات الخارجيّة — يجب أن تطابق `ScreenId.importPurchases`.
  importPurchases(71),

  /// مصمّمُ القاعة — يجب أن تطابق `ScreenId.floorPlanDesigner`.
  floorPlanDesigner(72),

  /// يجب أن تطابق `ScreenId.trialBalance`.
  trialBalance(73),

  /// يجب أن تطابق `ScreenId.journalTemplates`.
  journalTemplates(74),

  /// يجب أن تطابق `ScreenId.quotations`.
  quotations(75),

  /// قائمتا PicPos المنفصلتان لنفس جدول الأطراف.
  customers(76),
  suppliers(77),

  /// يجب أن تطابق `ScreenId.repDistribution`.
  repDistribution(78),

  /// يجب أن تطابق `ScreenId.hrEmployees` / `ScreenId.hrOrganization`.
  hrEmployees(79),
  hrOrganization(80);

  /// The integer index for this screen, used in permission maps and storage.
  final int value;

  const AppScreen(this.value);

  /// Look up an [AppScreen] by its integer [value].
  /// Returns `null` if no screen matches.
  static AppScreen? fromValue(int value) {
    for (final screen in AppScreen.values) {
      if (screen.value == value) return screen;
    }
    return null;
  }
}

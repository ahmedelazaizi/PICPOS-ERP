/// Stable identifiers for navigation entries.
///
/// The attached [index] keeps backward compatibility with the current
/// screen-index based navigation until the app is migrated completely.
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
  bookings(61);

  const ScreenId(this.navigationIndex);
  final int navigationIndex;

  static ScreenId? fromIndex(int index) {
    for (final value in ScreenId.values) {
      if (value.navigationIndex == index) return value;
    }
    return null;
  }
}

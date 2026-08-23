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
  // Shift management
  shiftClose(56),
  // Phase 14: Hardening
  syncConflicts(58),
  auditDashboard(59),
  // Phase 8: Region Layer
  regions(60),
  bookings(61),

  /// القوائمُ المالية — يجب أن تطابق `ScreenId.financialStatements`.
  financialStatements(62);

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

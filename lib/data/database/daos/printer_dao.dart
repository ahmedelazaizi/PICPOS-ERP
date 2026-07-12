part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRINTER DAO EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

extension PrinterDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // PRINTER CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all printers
  Future<List<Printer>> getAllPrinters() {
    return (select(printers)..orderBy([(p) => OrderingTerm.asc(p.name)])).get();
  }

  /// Get active printers
  Future<List<Printer>> getActivePrinters() {
    return (select(printers)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Get first active printer by purpose (pos_receipt, kitchen, tables, barcode)
  Future<Printer?> getActivePrinterByPurpose(String purpose) {
    return (select(printers)
          ..where((p) => p.isActive.equals(true) & p.purpose.equals(purpose))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Watch all printers
  Stream<List<Printer>> watchPrinters() {
    return (select(
      printers,
    )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  }

  /// Get printer by ID
  Future<Printer?> getPrinterById(int? id) async {
    if (id == null) return null;
    return (select(printers)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Insert new printer
  Future<int> insertPrinter({
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
  }) async {
    final gid = UuidV7.generate();
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createPrinter({
        'globalId': gid,
        'name': name,
        'port': port,
        'ipAddress': ipAddress,
        'portNumber': portNumber,
        'printerType': printerType,
        'purpose': purpose,
        'description': description,
      });
      if (serverId != null) return serverId;
    }
    return into(printers).insert(
      PrintersCompanion.insert(
        name: name,
        port: Value(port),
        ipAddress: Value(ipAddress),
        portNumber: Value(portNumber),
        printerType: Value(printerType),
        purpose: Value(purpose),
        description: Value(description),
        globalId: Value(gid),
      ),
    );
  }

  /// Update printer
  Future<bool> updatePrinter({
    required int id,
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
    bool isActive = true,
  }) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updatePrinter(id, {
        'name': name,
        'port': port,
        'ipAddress': ipAddress,
        'portNumber': portNumber,
        'printerType': printerType,
        'purpose': purpose,
        'description': description,
        'isActive': isActive,
      });
    }
    return (update(printers)..where((p) => p.id.equals(id)))
        .write(
          PrintersCompanion(
            name: Value(name),
            port: Value(port),
            ipAddress: Value(ipAddress),
            portNumber: Value(portNumber),
            printerType: Value(printerType),
            purpose: Value(purpose),
            description: Value(description),
            isActive: Value(isActive),
          ),
        )
        .then((count) => count > 0);
  }

  /// Delete printer
  Future<bool> deletePrinter(int id) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deletePrinter(id);
    }
    // Unlink printer from any categories first
    await (update(categories)..where((c) => c.printerId.equals(id))).write(
      const CategoriesCompanion(printerId: Value(null)),
    );
    return (delete(printers)..where((p) => p.id.equals(id))).go().then((count) => count > 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CATEGORY-PRINTER OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Update category printer link
  Future<bool> updateCategoryPrinter(int categoryId, int? printerId) async {
    return (update(categories)..where((c) => c.id.equals(categoryId)))
        .write(CategoriesCompanion(printerId: Value(printerId)))
        .then((count) => count > 0);
  }

  /// Insert category with printer support
  Future<int> insertCategoryWithPrinter({
    required String name,
    String? description,
    String color = '#2563EB',
    int? parentId,
    int sortOrder = 0,
    int? printerId,
    String? iconName,
  }) async {
    return into(categories).insert(
      CategoriesCompanion.insert(
        name: name,
        description: Value(description),
        color: Value(color),
        parentId: Value(parentId),
        sortOrder: Value(sortOrder),
        printerId: Value(printerId),
        iconName: Value(iconName),
        // UUID-First Phase 1 Slice 3: stable identity across installs.
        globalId: Value(UuidV7.generate()),
      ),
    );
  }

  /// Get all unique printer group names from settings
  Future<List<String>> getAllPrinterGroupNames() async {
    final settingsRows = await (select(
      settings,
    )..where((s) => s.key.like('printer.group.%'))).get();

    // Extract group name from key 'printer.group.GROUP_NAME.ip'
    final groups = settingsRows
        .map((s) {
          final parts = s.key.split('.');
          return parts.length > 2 ? parts[2] : null;
        })
        .whereType<String>()
        .toSet()
        .toList();

    return groups;
  }

  /// Get printer group for a specific product category
  Future<String?> getPrinterGroupForCategory(int categoryId) async {
    final query = selectOnly(categories)
      ..addColumns([categories.printerGroup])
      ..where(categories.id.equals(categoryId));
    final row = await query.getSingleOrNull();
    return row?.read(categories.printerGroup);
  }

  /// Update category with printer assignment and icon
  Future<void> updateCategoryWithPrinter({
    required int id,
    required String name,
    String? color,
    int? printerId,
    String? iconName,
  }) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        color: color != null ? Value(color) : const Value.absent(),
        printerId: Value(printerId),
        iconName: Value(iconName),
      ),
    );
  }

  /// Set category lock status
  /// Products inherit lock status from their category - no direct modification needed
  /// Product display logic checks category.isLocked to determine effective status
  Future<bool> setCategoryLocked(int categoryId, bool isLocked) async {
    return (update(categories)..where((c) => c.id.equals(categoryId)))
        .write(CategoriesCompanion(isLocked: Value(isLocked)))
        .then((count) => count > 0);
  }

  /// Exclude entire category: mark as excluded - products hidden from POS grid but searchable
  /// This is different from locking: excluded products CAN be found via search/barcode
  Future<void> excludeCategoryWithAllProducts(int categoryId) async {
    await (update(categories)..where((c) => c.id.equals(categoryId))).write(
      const CategoriesCompanion(isExcluded: Value(true)),
    );
  }

  /// Un-exclude entire category: products visible again in POS grid browsing
  Future<void> unexcludeCategoryWithAllProducts(int categoryId) async {
    await (update(categories)..where((c) => c.id.equals(categoryId))).write(
      const CategoriesCompanion(isExcluded: Value(false)),
    );
  }

  /// Set category POS visibility (v100)
  Future<bool> setCategoryShowInPos(int categoryId, bool showInPos) async {
    return (update(categories)..where((c) => c.id.equals(categoryId)))
        .write(CategoriesCompanion(showInPos: Value(showInPos)))
        .then((count) => count > 0);
  }
}

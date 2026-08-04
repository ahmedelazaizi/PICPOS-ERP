part of '../database.dart';

extension Epoch1Migrations on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // EPOCH 1: v1 → v59 — Core schema, basic features, initial indexes
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _migrateEpoch1(Migrator m, int from) async {
    // Migration from v1 to v2: Add expiry tracking
    if (from < 2) {
      await m.addColumn(products, products.trackExpiry);
      await m.addColumn(products, products.defaultShelfDays);
      await m.addColumn(products, products.alertDaysBefore);
      await m.addColumn(
        purchaseInvoiceItems,
        purchaseInvoiceItems.batchNumber,
      );
      await m.addColumn(
        purchaseInvoiceItems,
        purchaseInvoiceItems.productionDate,
      );
      await m.addColumn(
        purchaseInvoiceItems,
        purchaseInvoiceItems.expiryDate,
      );
      await m.addColumn(salesInvoiceItems, salesInvoiceItems.batchId);
      await m.createTable(productBatches);
    }
    // Migration from v2 to v3: Add secure password hashing
    if (from < 3) {
      await m.addColumn(users, users.passwordSalt);
      final existingUsers = await select(users).get();
      for (final user in existingUsers) {
        final salt = SecurityService.generateSalt();
        final newHash = await SecurityService.hashPasswordArgon2('admin');
        await (update(users)..where((u) => u.id.equals(user.id))).write(
          UsersCompanion(
            passwordSalt: Value(salt),
            passwordHash: Value(newHash),
          ),
        );
      }
    }
    // Migration from v4 to v5: Add Full Text Search (FTS5) for products
    if (from < 5) {
      await m.database.customStatement(
        "CREATE VIRTUAL TABLE products_fts USING fts5(code, name, content='products', content_rowid='id');",
      );
      await m.database.customStatement(
        "INSERT INTO products_fts(rowid, code, name) SELECT id, code, name FROM products WHERE is_active = 1;",
      );
      await m.database.customStatement('''
            CREATE TRIGGER products_ai AFTER INSERT ON products BEGIN
              INSERT INTO products_fts(rowid, code, name) VALUES (new.id, new.code, new.name);
            END;
          ''');
      await m.database.customStatement('''
            CREATE TRIGGER products_ad AFTER DELETE ON products BEGIN
              INSERT INTO products_fts(products_fts, rowid, code, name) VALUES('delete', old.id, old.code, old.name);
            END;
          ''');
      await m.database.customStatement('''
            CREATE TRIGGER products_au AFTER UPDATE ON products BEGIN
              INSERT INTO products_fts(products_fts, rowid, code, name) VALUES('delete', old.id, old.code, old.name);
              INSERT INTO products_fts(rowid, code, name) VALUES (new.id, new.code, new.name);
            END;
          ''');
    }
    // Migration from v5 to v6: Add cost_price to sales_invoice_items
    if (from < 6) {
      try {
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.costPrice);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    if (from < 7) {
      await m.createTable(offers);
      await m.createTable(offerItems);
    }
    if (from < 8) {
      await m.createTable(restaurantTables);
      await m.createTable(tableOrders);
      await m.createTable(tableOrderItems);
    }
    if (from < 9) {
      await m.createTable(printers);
      await m.addColumn(categories, categories.printerId);
    }
    if (from < 10) {
      await m.createTable(roles);
      await m.createTable(permissions);
      await m.createTable(rolePermissions);
      await m.addColumn(users, users.roleId);
      await m.addColumn(users, users.pin);
      await m.addColumn(users, users.defaultScreen);
      await m.addColumn(users, users.isLocked);
      await seedRolesAndPermissions();
    }
    if (from < 11) {
      await m.database.customStatement(
        "DROP TABLE IF EXISTS products_fts;",
      );
      await m.database.customStatement(
        "CREATE VIRTUAL TABLE products_fts USING fts5(code, name, description, content='products', content_rowid='id', tokenizer='unicode61');",
      );
      await m.database.customStatement(
        "INSERT INTO products_fts(rowid, code, name, description) SELECT id, code, name, description FROM products WHERE is_active = 1;",
      );
      await m.database.customStatement(
        "CREATE VIRTUAL TABLE parties_fts USING fts5(name, phone, address, content='parties', content_rowid='id', tokenizer='unicode61');",
      );
      await m.database.customStatement(
        "INSERT INTO parties_fts(rowid, name, phone, address) SELECT id, name, phone, address FROM parties WHERE is_active = 1;",
      );
    }
    if (from < 12) {
      await accountingDao.syncDefaultAccounts();
    }
    if (from < 13) {
      await m.createTable(deliveryCompanies);
      await m.createTable(couriers);
      await m.addColumn(salesInvoices, salesInvoices.deliveryStatus);
      await m.addColumn(salesInvoices, salesInvoices.deliveryFee);
      await m.addColumn(salesInvoices, salesInvoices.deliveryCompanyId);
      await m.addColumn(salesInvoices, salesInvoices.courierId);
    }
    if (from < 14) {
      try {
        await m.addColumn(parties, parties.fixedDiscount);
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.sortOrder);
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.taxRate);
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.taxAmount);
        await m.addColumn(tableOrderItems, tableOrderItems.taxRate);
        await m.addColumn(tableOrderItems, tableOrderItems.taxAmount);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    if (from < 15) {
      try {
        await m.addColumn(products, products.taxRate);
        await m.addColumn(
          purchaseInvoiceItems,
          purchaseInvoiceItems.taxRate,
        );
        await m.addColumn(
          purchaseInvoiceItems,
          purchaseInvoiceItems.taxAmount,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    if (from < 16) {
      await m.createTable(employees);
      await m.createTable(employeeAttendance);
      await m.createTable(salaryPayments);
      try {
        await m.addColumn(offers, offers.barcode);
        await m.addColumn(salesInvoices, salesInvoices.cashPaid);
        await m.addColumn(salesInvoices, salesInvoices.bankPaid);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    if (from < 17) {
      try {
        await m.addColumn(products, products.priceTalabat);
        await m.addColumn(products, products.priceCareem);
        await m.addColumn(products, products.priceAshyae);
        await m.addColumn(parties, parties.priceLevel);
        await m.addColumn(salesInvoices, salesInvoices.saleType);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    if (from < 18) {
      await m.createTable(stockAudits);
      await m.createTable(stockAuditItems);
    }
    if (from < 19) {
      try {
        await m.addColumn(printers, printers.purpose);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v20: Add category icon field
    if (from < 20) {
      try {
        await m.addColumn(categories, categories.iconName);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v21: Invoice Template Designer
    if (from < 21) {
      await m.createTable(invoiceTableSettings);
    }
    // Migration v22: Add table header font family and size
    if (from < 22) {
      try {
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.headerFontSize,
        );
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.headerFontFamily,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }

    // Migration v23: Inventory Bonds & Delivery Companies support
    if (from < 23) {
      try {
        await m.createTable(inventoryBonds);
        await m.createTable(inventoryBondItems);
        await m.addColumn(parties, parties.isDeliveryCompany);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v24: Add orderNumber to salesInvoices
    if (from < 24) {
      try {
        await m.addColumn(salesInvoices, salesInvoices.orderNumber);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v25: Link delivery companies to Parties (Financial)
    if (from < 25) {
      try {
        await m.addColumn(
          salesInvoices,
          salesInvoices.deliveryCompanyPartyId,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v26: Primary barcode for products
    if (from < 26) {
      try {
        await m.addColumn(products, products.barcode);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v27: Supplier invoice number in purchases
    if (from < 27) {
      try {
        await m.addColumn(
          purchaseInvoices,
          purchaseInvoices.supplierInvoiceNumber,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v28: Add columnWidths to invoiceTableSettings
    if (from < 28) {
      try {
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.columnWidths,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v29: Standardize Invoice Designer fields to match code
    if (from < 29) {
      try {
        // Elements
        await m.addColumn(
          invoiceTemplateElements,
          invoiceTemplateElements.xPosition,
        );
        await m.addColumn(
          invoiceTemplateElements,
          invoiceTemplateElements.yPosition,
        );
        await m.addColumn(
          invoiceTemplateElements,
          invoiceTemplateElements.content,
        );
        await m.addColumn(
          invoiceTemplateElements,
          invoiceTemplateElements.isBold,
        );
        await m.addColumn(
          invoiceTemplateElements,
          invoiceTemplateElements.isItalic,
        );

        // Table Settings
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.xPosition,
        );
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.yPosition,
        );
        await m.addColumn(invoiceTableSettings, invoiceTableSettings.width);
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.fontSize,
        );
        await m.addColumn(
          invoiceTableSettings,
          invoiceTableSettings.showIndex,
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v29: Add isFavorite to parties (favorite customers)
    if (from < 29) {
      try {
        await m.addColumn(parties, parties.isFavorite);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v30: Seed delivery company parties for existing databases
    if (from < 30) {
      try {
        await seedDeliveryCompanyPartiesIfNotExists();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v31: Add maxDiscountPercent to users
    if (from < 31) {
      try {
        await m.addColumn(users, users.maxDiscountPercent);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v32: Add isExcluded to categories
    if (from < 32) {
      try {
        await m.addColumn(categories, categories.isExcluded);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v33: Add cardCode to users for MSR card login
    if (from < 33) {
      try {
        await m.addColumn(users, users.cardCode);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v34: Add sortOrder to products for drag-and-drop ordering
    if (from < 34) {
      try {
        await m.addColumn(products, products.sortOrder);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v35: Seed comprehensive POS header & scale upload permissions
    if (from < 35) {
      await seedV35Permissions();
    }
    // Migration v36: Held order granular permissions & closing blind mode
    if (from < 36) {
      await seedV36Permissions();
    }
    // Migration v37: Granular POS permissions
    if (from < 37) {
      await seedV37Permissions();
    }
    // Migration v38: Multi-warehouse transfers
    if (from < 38) {
      try {
        await m.addColumn(
          inventoryBonds,
          (inventoryBonds as dynamic).toWarehouseId,
        );
        await seedV38Permissions();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v39: Phase 4 Fiscal Control
    if (from < 39) {
      try {
        await m.addColumn(
          salesInvoices,
          (salesInvoices as dynamic).isLocked,
        );
        await m.createTable(shifts);
        await seedV39Permissions();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v40: Arabic Search Normalization
    if (from < 40) {
      try {
        await m.addColumn(products, (products as dynamic).searchName);
        // Re-create FTS table to include searchName
        await m.database.customStatement(
          "DROP TABLE IF EXISTS products_fts;",
        );
        await m.database.customStatement(
          "CREATE VIRTUAL TABLE products_fts USING fts5(code, name, description, searchName, content='products', content_rowid='id', tokenizer='unicode61');",
        );
        // Populate searchName for existing products (fallback to name if null during migration)
        // Actual normalization happens in DAO on save, but for migration we'll just index what we have
        await m.database.customStatement(
          "INSERT INTO products_fts(rowid, code, name, description, searchName) SELECT id, code, name, description, name FROM products WHERE is_active = 1;",
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v41: Comprehensive permission seeding
    if (from < 41) {
      await seedV41Permissions();
    }
    // Migration v42: Scale PLU number & sale type
    if (from < 42) {
      try {
        await m.addColumn(products, products.scalePluNumber);
        await m.addColumn(products, products.scaleType);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v43: Multi-scale registry table
    if (from < 43) {
      try {
        await m.createTable(labelScales);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v44: Advanced Accounting (Phase 1)
    if (from < 44) {
      try {
        // New tables
        await m.createTable(costCenters);
        await m.createTable(fiscalYears);
        await m.createTable(activityProfiles);
        // New columns on existing tables
        await m.addColumn(journalEntries, journalEntries.isAutoPosted);
        await m.addColumn(journalEntries, journalEntries.fiscalYearId);
        await m.addColumn(
          journalEntryLines,
          journalEntryLines.costCenterId,
        );
        // Sync new default accounts needed for auto-posting
        await accountingDao.syncDefaultAccounts();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v45: Commercial Papers & Finance (Phase 2)
    if (from < 45) {
      try {
        await m.createTable(commercialPapers);
        await m.createTable(paperStatusHistory);
        await m.createTable(currencies);
        await m.createTable(exchangeRateHistory);
        await m.createTable(priceLists);
        await m.createTable(priceListItems);
        // Seed default currency
        await seedDefaultCurrencies();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v46: Manufacturing & Assets (Phase 3)
    if (from < 46) {
      try {
        await m.createTable(billOfMaterials);
        await m.createTable(bomComponents);
        await m.createTable(manufacturingOrders);
        await m.createTable(assetCategories);
        await m.createTable(fixedAssets);
        await m.createTable(assetDepreciations);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v47: E-Invoicing Infrastructure (Phase 4)
    if (from < 47) {
      try {
        await m.createTable(eInvoiceConfigs);
        await m.createTable(eInvoiceSubmissions);
        await m.createTable(taxTypes);
        await m.createTable(taxSubtypes);
        // Add e-invoicing classification fields to products
        await m.addColumn(products, products.egsCode);
        await m.addColumn(products, products.gpcCode);
        await m.addColumn(products, products.itemTaxType);
        await m.addColumn(products, products.itemTaxSubtype);
        // Seed ETA tax types reference data
        await seedTaxTypes();
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v48: HR Phase 5 — Leaves, Overtime, Fingerprint Devices
    if (from < 48) {
      try {
        await m.createTable(employeeLeaves);
        await m.createTable(leaveBalances);
        await m.createTable(overtimeRecords);
        await m.createTable(fingerprintDevices);
        await m.addColumn(employees, employees.deviceUserId);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v49: Loyalty Points + Distribution
    if (from < 49) {
      try {
        await m.createTable(loyaltyPrograms);
        await m.createTable(customerLoyaltyPoints);
        await m.createTable(loyaltyTransactions);
        await m.createTable(salesRoutes);
        await m.createTable(routeVisits);
        await m.createTable(salesRepTargets);
        await m.createTable(salesRepCollections);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v50: Advanced Offers
    if (from < 50) {
      try {
        await m.addColumn(offers, offers.offerType);
        await m.addColumn(offers, offers.discountValue);
        await m.addColumn(offers, offers.buyQuantity);
        await m.addColumn(offers, offers.getQuantity);
        await m.addColumn(offers, offers.minQuantity);
        await m.addColumn(offers, offers.maxUses);
        await m.addColumn(offers, offers.currentUses);
        await m.addColumn(offers, offers.timeStart);
        await m.addColumn(offers, offers.timeEnd);
        await m.addColumn(offers, offers.categoryId);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v51: Performance Hardening (Composite Indices)
    // NOTE: Index definitions missing from table classes - skipping until properly defined
    // if (from < 51) { ... }

    // Migration v52: Performance Hardening (Composite Indices)
    // NOTE: Index definitions missing from table classes - skipping until properly defined
    // if (from < 52) { ... }
    // Migration v54: Sync Engine (SyncOutbox Table)
    if (from < 54) {
      try {
        await m.createTable(syncOutbox);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v55 -> 56: Sequences table to prevent race conditions
    if (from < 56) {
      try {
        await m.createTable(documentSequences);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v57: Performance Hardening (Composite Indices)
    if (from < 57) {
      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_inventory_balances_composite ON inventory_balances (product_id, warehouse_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_composite ON stock_movements (product_id, warehouse_id, created_at);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements (reference_type, reference_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_composite ON journal_entry_lines (account_id, entry_id);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // Migration v58: PIR Phase 0 — UNIQUE constraint on InventoryBalances
    if (from < 58) {
      try {
        // Drop old non-unique composite index and create UNIQUE one
        await m.database.customStatement(
          'DROP INDEX IF EXISTS idx_inventory_balances_composite;',
        );
        await m.database.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_balances_composite '
          'ON inventory_balances (product_id, warehouse_id);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }

    // v59: Performance indexes for treasury and barcode lookup (PIR §2.3)
    if (from < 59) {
      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_safe_transactions_safe '
          'ON safe_transactions(safe_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_products_barcode '
          'ON products(barcode);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
  } // end _migrateEpoch1
}

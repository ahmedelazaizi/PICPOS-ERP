part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// UNITS & CATEGORIES & PRODUCTS
// ═══════════════════════════════════════════════════════════════════════════

class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 50)(); // قطعة، كرتونة
  TextColumn get symbol => text().withLength(max: 20)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  RealColumn get conversionFactor => real().withDefault(const Constant(1.0))();
  // Spec 129 F6 — seeded-default flag (see Branches.isSystemDefault).
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get description => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#2563EB'))();
  TextColumn get iconName =>
      text().nullable()(); // أيقونة التصنيف (اسم الأيقونة من Phosphor Icons)
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isLocked => boolean().withDefault(
    const Constant(false),
  )(); // #9 قفل التصنيف - منع التعديل/البيع
  BoolColumn get isExcluded => boolean().withDefault(
    const Constant(false),
  )(); // تصنيف مستثنى - لا يظهر في البيع السريع إلا بالبحث
  IntColumn get printerId =>
      integer().nullable().references(Printers, #id)(); // طابعة أمر الشغل
  TextColumn get printerGroup =>
      text().nullable()(); // NEW: Printer group name (e.g. 'kitchen', 'bar')
  BoolColumn get showInPos => boolean().withDefault(
    const Constant(true),
  )(); // v100: إظهار/إخفاء التصنيف في البيع السريع
  BoolColumn get isGlobal => boolean().withDefault(const Constant(true))();
  TextColumn get branchIds => text().nullable()(); // CSV of permitted branch IDs
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  // Spec 129 F6 — seeded-default flag (see Branches.isSystemDefault).
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// PIR R-10: Join table for Category-Branch visibility
class CategoryBranches extends Table {
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get branchId => integer().references(Branches, #id)();

  @override
  Set<Column> get primaryKey => {categoryId, branchId};
}


@TableIndex(name: 'idx_products_barcode', columns: {#barcode})
@TableIndex(name: 'idx_products_category', columns: {#categoryId})
@TableIndex(name: 'idx_products_code', columns: {#code})
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 50)(); // Internal code
  TextColumn get barcode =>
      text().nullable().withLength(max: 100)(); // #Phase2: Primary barcode
  TextColumn get name => text().withLength(max: 200)();
  TextColumn get searchName =>
      text().nullable()(); // #Phase4: Normalized Arabic name for FTS
  TextColumn get description => text().nullable()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  IntColumn get supplierId =>
      integer().nullable()(); // 7.2: Default supplier for this product
  IntColumn get warehouseId => integer().nullable().references(
    Warehouses,
    #id,
  )(); // 10.2: Default warehouse for this product
  RealColumn get salePrice => real().withDefault(const Constant(0))();
  // Multi-level pricing
  RealColumn get priceTalabat =>
      real().withDefault(const Constant(0))(); // طلبات
  RealColumn get priceCareem => real().withDefault(const Constant(0))(); // كريم
  RealColumn get priceAshyae =>
      real().withDefault(const Constant(0))(); // أشيائي
  RealColumn get wholesalePrice =>
      real().withDefault(const Constant(0))(); // 7.5: سعر الجملة
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(0))();
  RealColumn get currentStock => real().withDefault(const Constant(0))();
  TextColumn get imagePath => text().nullable()();
  BlobColumn get imageData =>
      blob().nullable()(); // Product image stored as bytes
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isLocked => boolean().withDefault(
    const Constant(false),
  )(); // #9 قفل الصنف - منع التعديل/البيع
  BoolColumn get trackInventory =>
      boolean().withDefault(const Constant(true))();
  // Expiry tracking fields
  BoolColumn get trackExpiry =>
      boolean().withDefault(const Constant(false))(); // يتطلب تتبع صلاحية
  IntColumn get defaultShelfDays => integer().withDefault(
    const Constant(0),
  )(); // مدة الصلاحية الافتراضية بالأيام
  IntColumn get alertDaysBefore =>
      integer().withDefault(const Constant(30))(); // التنبيه قبل الانتهاء بأيام
  // Weight-based sales fields
  BoolColumn get isSoldByWeight =>
      boolean().withDefault(const Constant(false))(); // يُباع بالوزن
  RealColumn get pricePerUnit => real().nullable()(); // سعر الوحدة (كيلو/جرام)
  TextColumn get weightUnit =>
      text().withDefault(const Constant('kg'))(); // kg, g
  // Negative sale control
  BoolColumn get allowNegativeSale =>
      boolean().withDefault(const Constant(false))(); // السماح بالبيع بالسالب
  // Product classification for manufacturing
  TextColumn get productType => text().withDefault(
    const Constant('general'),
  )(); // general=عام, raw_material=خامة, finished_goods=منتج تام, service=خدمة
  BoolColumn get isKitchenSet => boolean().withDefault(
    const Constant(false),
  )(); // #Phase6: صنف يرسل للمطبخ
  RealColumn get taxRate =>
      real().withDefault(const Constant(0))(); // نسبة الضريبة لهذا الصنف
  // Scale integration fields
  IntColumn get scalePluNumber =>
      integer().nullable()(); // رقم المادة عالميزان (PLU)
  TextColumn get scaleType => text().withDefault(
    const Constant('count'),
  )(); // count, weight, weightByPiece, display
  // E-Invoicing classification fields (Phase 4)
  TextColumn get egsCode => text().nullable()(); // كود EGS مصري (EG-TaxReg-SKU)
  TextColumn get gpcCode => text().nullable()(); // كود GPC دولي (GS1)
  TextColumn get itemTaxType =>
      text().withDefault(const Constant('T1'))(); // نوع الضريبة (T1-T20)
  TextColumn get itemTaxSubtype => text().withDefault(
    const Constant('V009'),
  )(); // النوع الفرعي (V009=بيع عام 14%)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))(); // ترتيب العرض في البيع السريع

  // Phase 14: UUID for deterministic sync — prevents ID collision between branches

  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  // v138 (Issue 2): provenance flag — true for products created directly on
  // the server (admin via the server UI), false for products created on a
  // client and round-tripped through the API. The client product-edit
  // dialog locks rows where this is true so the SoT (server) stays the
  // single canonical edit point. Default true is the conservative backfill
  // for existing rows: anything already on disk got there via a server
  // pull, so treating it as server-canonical is correct.
  BoolColumn get createdOnServer =>
      boolean().withDefault(const Constant(true))();
}

@TableIndex(name: 'idx_product_barcodes_barcode', columns: {#barcode})
@TableIndex(name: 'idx_product_barcodes_product', columns: {#productId})
class ProductBarcodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get barcode => text().withLength(max: 50)();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Product packaging units (كرتونة، عبوة، كيس، قطعة)
/// Each product can have multiple units with different prices
@TableIndex(name: 'idx_product_units_product', columns: {#productId})
@TableIndex(name: 'idx_product_units_barcode', columns: {#barcode})
class ProductUnits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get unitName =>
      text().withLength(max: 50)(); // كرتونة، عبوة، كيس، قطعة
  TextColumn get barcode => text().nullable()(); // باركود هذه الوحدة
  RealColumn get quantityInBase =>
      real().withDefault(const Constant(1))(); // عدد القطع في هذه الوحدة
  RealColumn get salePrice =>
      real().withDefault(const Constant(0))(); // سعر البيع
  RealColumn get costPrice =>
      real().withDefault(const Constant(0))(); // سعر الشراء
  BoolColumn get isDefaultPurchase => boolean().withDefault(
    const Constant(false),
  )(); // الوحدة الافتراضية للشراء
  BoolColumn get isDefaultSale =>
      boolean().withDefault(const Constant(false))(); // الوحدة الافتراضية للبيع
  BoolColumn get isBaseUnit => boolean().withDefault(
    const Constant(false),
  )(); // الوحدة الأساسية (القطعة)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Product Batches for expiry tracking (FEFO - First Expiry First Out)
@DataClassName('ProductBatch')
@TableIndex(name: 'idx_product_batches_expiry', columns: {#expiryDate})
@TableIndex(name: 'idx_product_batches_product', columns: {#productId})
@TableIndex(name: 'idx_product_batches_status', columns: {#status})
class ProductBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  TextColumn get batchNumber => text().withLength(max: 50)(); // رقم الباتش
  DateTimeColumn get productionDate => dateTime().nullable()(); // تاريخ الإنتاج
  DateTimeColumn get expiryDate => dateTime()(); // تاريخ الانتهاء
  RealColumn get quantity =>
      real().withDefault(const Constant(0))(); // الكمية المتبقية
  RealColumn get initialQuantity =>
      real().withDefault(const Constant(0))(); // الكمية الأصلية
  RealColumn get unitCost =>
      real().withDefault(const Constant(0))(); // تكلفة الوحدة
  IntColumn get purchaseInvoiceId =>
      integer().nullable().references(PurchaseInvoices, #id)();
  TextColumn get status => text().withDefault(
    const Constant('active'),
  )(); // active, expired, depleted
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

}

/// Per-warehouse product pricing (أسعار مخصصة لكل مخزن)
/// Allows different sale/cost/wholesale prices per warehouse
@TableIndex(
  name: 'idx_warehouse_prices_product_warehouse',
  columns: {#productId, #warehouseId},
  unique: true,
)
@TableIndex(name: 'idx_warehouse_prices_product', columns: {#productId})
class WarehousePrices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  RealColumn get salePrice => real().withDefault(const Constant(0))();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get wholesalePrice => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTIES & SALES & PURCHASE
// ═══════════════════════════════════════════════════════════════════════════

/// Party groups/categories for classifying customers and suppliers.
///
/// Phase 2 enrichment: added `description`, `defaultDiscount`,
/// `defaultPaymentTerms`, `priceLevel`, `notes`, `parentGroupId` so an
/// admin can attach business rules at the group level (applied manually
/// by the user — no automatic enforcement in this phase).
class PartyGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 200)();
  TextColumn get type => text().withDefault(const Constant('both'))(); // customer, supplier, both
  TextColumn get description => text().nullable()(); // وصف المجموعة
  RealColumn get defaultDiscount => real().withDefault(const Constant(0))(); // خصم افتراضى % (0-100)
  TextColumn get defaultPaymentTerms => text().nullable()(); // شروط دفع افتراضية (نص حر: COD, 30 يوم, ...)
  TextColumn get priceLevel => text().nullable()(); // مستوى أسعار افتراضى (يطابق parties.priceLevel)
  TextColumn get notes => text().nullable()(); // ملاحظات حرة
  // Nested hierarchy placeholder — nullable self-ref allows a future
  // "Groups of groups" feature without another migration. Not exposed in
  // the UI yet in Phase 2 (simple flat list).
  IntColumn get parentGroupId => integer().nullable().customConstraint('REFERENCES party_groups(id)')();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_parties_customer', columns: {#isCustomer})
@TableIndex(name: 'idx_parties_supplier', columns: {#isSupplier})
class Parties extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().nullable()(); // كود العميل/المورد
  TextColumn get name => text().withLength(max: 200)();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get taxId => text().nullable()();
  TextColumn get tin => text().nullable().withLength(max: 15)(); // Tax ID (Saudi/Egypt compliance)
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  BoolColumn get isCustomer => boolean().withDefault(const Constant(true))();
  BoolColumn get isSupplier => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeliveryCompany =>
      boolean().withDefault(const Constant(false))(); // #Phase2: شركة توصيل
  BoolColumn get isFavorite =>
      boolean().withDefault(const Constant(false))(); // عميل مفضل/ثابت
  RealColumn get balance =>
      real().withDefault(const Constant(0))(); // +debit / -credit
  RealColumn get creditLimit => real().withDefault(const Constant(0))();

  // ═══ v164 — شروطُ التعامل (أمرُ المالك 2026-08-26) ═══════════════════════
  //
  // أربعةُ حقولٍ **متّفقٌ عليها** لا مشتقّة. وما يُشتقّ لا يُخزَّن هنا عمداً:
  // «الالتزامُ بمواعيد التوريد» يُقاس من `purchase_orders.received_at` مقابلَ
  // `expected_date`، و«متوسّطُ السداد الفعليّ» من `payment_allocations`
  // مقابلَ تواريخ الفواتير. رقمُ التزامٍ يكتبه إنسانٌ يكذب؛ والتاريخان
  // يقولان الحقيقةَ وحدَهما.

  /// مهلةُ السداد المتّفقةُ بالأيّام — «مدّةُ السماح» للعميل و«مدّةُ السداد»
  /// للمورد. تُشتقّ منها استحقاقُ الفاتورة **عند إصدارها**.
  ///
  /// والافتراضُ صفرٌ عمداً: يبقى استحقاقُ كلّ فاتورةٍ قائمةٍ يومَ إصدارها،
  /// فلا تتحرّك أرقامُ التقادم لحظةَ الترقية.
  IntColumn get paymentTermsDays => integer().withDefault(const Constant(0))();

  /// نسبةُ خصم السداد المعجَّل — «٢٪ خلال ١٠ أيّام» شرطان لا واحد، ولذلك
  /// حقلان: النسبةُ هنا والمهلةُ في [earlyPaymentDiscountDays]. ونسبةٌ بلا
  /// مهلةٍ لا معنى لها، فكلتاهما صفرٌ = لا خصمَ معجَّل.
  RealColumn get earlyPaymentDiscountPct =>
      real().withDefault(const Constant(0))();

  /// عددُ الأيّام التي يسري فيها [earlyPaymentDiscountPct] من تاريخ الفاتورة.
  IntColumn get earlyPaymentDiscountDays =>
      integer().withDefault(const Constant(0))();

  /// تقييمُ المورد ١..٥ — حكمٌ بشريٌّ لا يُشتقّ من بيانات. `null` = لم يُقيَّم
  /// بعد، وهي حالةٌ مختلفةٌ عن «تقييمٌ منخفض» فلا تُطوى إلى صفر.
  IntColumn get supplierRating => integer().nullable()();
  RealColumn get fixedDiscount => real().withDefault(
    const Constant(0),
  )(); // NEW: Default discount percentage for this party
  TextColumn get priceLevel => text().withDefault(
    const Constant('default'),
  )(); // default, talabat, careem, ashyae
  IntColumn get accountId =>
      integer().nullable().references(Accounts, #id)(); // NEW: Link to GL Account (Task 10)
  IntColumn get groupId =>
      integer().nullable().references(PartyGroups, #id)(); // تصنيف العميل/المورد
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  BoolColumn get isGlobal => boolean().withDefault(const Constant(true))();
  TextColumn get branchIds => text().nullable()(); // CSV of branch IDs
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة للطرف
  // Spec 129 F6 — seeded-default flag (see Branches.isSystemDefault). Marks
  // only the seeded delivery-company parties (طلبات / كريم / اشيائي), not
  // user-created customers/suppliers.
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('PurchaseInvoiceData')
@TableIndex(name: 'idx_purchase_invoices_date', columns: {#invoiceDate})
@TableIndex(name: 'idx_purchase_invoices_supplier', columns: {#supplierId})
@TableIndex(name: 'idx_purchase_invoices_warehouse', columns: {#warehouseId})
@TableIndex(name: 'idx_purchase_invoices_status', columns: {#status})
@TableIndex(name: 'idx_purchase_invoices_payment', columns: {#paymentMethod})

@TableIndex(name: 'idx_purchase_invoices_idempotency', columns: {#idempotencyKey})
class PurchaseInvoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().withLength(max: 50)();
  TextColumn get supplierInvoiceNumber => text().nullable().withLength(
    max: 50,
  )(); // #Phase2: رقم فاتورة المورد اليدوي
  IntColumn get supplierId => integer().references(Parties, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  // L3 (2026-04-28): direct branchId so multi-branch reports + filters
  // don't require a 2-hop JOIN (Invoice → Warehouse → Branch) on every row.
  // Nullable for backward-compat with rows created before this column existed.
  IntColumn get branchId => integer().nullable().references(Branches, #id)();
  DateTimeColumn get invoiceDate => dateTime()();

  /// v164 — تاريخُ الاستحقاق. **لقطةٌ وقتَ الإصدار لا حسابٌ حيّ.**
  ///
  /// ⚠️ لا يُشتقّ من `parties.payment_terms_days` عند القراءة: تغييرُ مهلةِ
  /// طرفٍ اليومَ كان سيُزحزح استحقاقَ كلّ فاتورةٍ قديمةٍ له بأثرٍ رجعيّ،
  /// فتتبدّل أعمارُ الدين لمستنداتٍ أُغلقت. نفسُ مبدأ
  /// `sales_invoice_items.cost_price`.
  ///
  /// ⚠️ و`null` تعني **بلا مهلة** = يستحق يومَ إصداره، فتُقرأ دائماً
  /// `COALESCE(due_date, invoice_date)`. وبهذا لا تكتب الهجرةُ صفّاً واحداً
  /// ويبقى سلوكُ ما قبلَها حرفيّاً.
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get paid => real().withDefault(const Constant(0))();
  TextColumn get paymentMethod =>
      text().withDefault(const Constant('cash'))(); // cash, transfer, card
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, partial, paid
  BoolColumn get isLocked =>
      boolean().withDefault(const Constant(false))(); // قفل بعد الدفع الكامل
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  TextColumn get integrityHash => text().nullable()(); // TCE-02: هاش الفاتورة للأرشيف غير القابل للتعديل
  TextColumn get notes => text().nullable()();

  // Phase 4: Distributed Sync Reliability

  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  TextColumn get idempotencyKey => text().nullable()(); // Deduplication key for offline replay resilience
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))(); // Soft Delete
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get deletedBy => integer().nullable().references(Users, #id)(); // PIR P0-01: Who deleted
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_purchase_items_invoice', columns: {#invoiceId})
@TableIndex(name: 'idx_purchase_items_product', columns: {#productId})
class PurchaseInvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(PurchaseInvoices, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  // Batch/Expiry fields
  TextColumn get batchNumber => text().nullable()(); // رقم الباتش
  DateTimeColumn get productionDate => dateTime().nullable()(); // تاريخ الإنتاج
  DateTimeColumn get expiryDate => dateTime().nullable()(); // تاريخ الانتهاء
  RealColumn get taxRate =>
      real().withDefault(const Constant(0))(); // نسبة الضريبة لهذا الصنف
  RealColumn get taxAmount =>
      real().withDefault(const Constant(0))(); // مبلغ الضريبة المحسوب
  TextColumn get unitName => text().nullable()(); // NEW: Selected unit name (e.g., Piece, Box)
  RealColumn get quantityInBase =>
      real().withDefault(const Constant(1.0))(); // NEW: Conversion factor to base unit
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('SalesInvoiceData')
@TableIndex(name: 'idx_sales_invoices_date', columns: {#invoiceDate})
@TableIndex(name: 'idx_sales_invoices_customer', columns: {#customerId})
@TableIndex(name: 'idx_sales_invoices_status', columns: {#status})
@TableIndex(
  name: 'idx_sales_invoices_composite',
  columns: {#invoiceDate, #customerId},
)
@TableIndex(
  name: 'idx_sales_invoices_status_date',
  columns: {#status, #invoiceDate},
)
@TableIndex(name: 'idx_sales_invoices_warehouse', columns: {#warehouseId})
@TableIndex(name: 'idx_sales_invoices_user', columns: {#userId})
@TableIndex(name: 'idx_sales_invoices_payment', columns: {#paymentMethod})

@TableIndex(name: 'idx_sales_invoices_idempotency', columns: {#idempotencyKey})
class SalesInvoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().withLength(max: 50)();
  IntColumn get customerId => integer().nullable().references(Parties, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  // L3 (2026-04-28): direct branchId for multi-branch reports + filters.
  // Resolved from warehouse.branchId at create time and stamped on the row
  // so reports don't need a 2-hop JOIN. Nullable for backward-compat.
  IntColumn get branchId => integer().nullable().references(Branches, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  DateTimeColumn get invoiceDate => dateTime()();

  /// v164 — تاريخُ الاستحقاق. **لقطةٌ وقتَ الإصدار لا حسابٌ حيّ.**
  ///
  /// ⚠️ لا يُشتقّ من `parties.payment_terms_days` عند القراءة: تغييرُ مهلةِ
  /// طرفٍ اليومَ كان سيُزحزح استحقاقَ كلّ فاتورةٍ قديمةٍ له بأثرٍ رجعيّ،
  /// فتتبدّل أعمارُ الدين لمستنداتٍ أُغلقت. نفسُ مبدأ
  /// `sales_invoice_items.cost_price`.
  ///
  /// ⚠️ و`null` تعني **بلا مهلة** = يستحق يومَ إصداره، فتُقرأ دائماً
  /// `COALESCE(due_date, invoice_date)`. وبهذا لا تكتب الهجرةُ صفّاً واحداً
  /// ويبقى سلوكُ ما قبلَها حرفيّاً.
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get paid => real().withDefault(const Constant(0))();
  RealColumn get cashPaid =>
      real().withDefault(const Constant(0))(); // NEW: Split payment support
  RealColumn get bankPaid =>
      real().withDefault(const Constant(0))(); // NEW: Split payment support
  RealColumn get clickPaid =>
      real().withDefault(const Constant(0))(); // Click transfer split payment
  TextColumn get paymentMethod => text().withDefault(
    const Constant('cash'),
  )(); // cash, card, click, credit, multiple
  TextColumn get saleType => text().withDefault(
    const Constant('default'),
  )(); // default, talabat, careem, ashyae
  TextColumn get status => text().withDefault(
    const Constant('completed'),
  )(); // pending, completed, returned, booked
  TextColumn get deliveryStatus =>
      text().nullable()(); // pending, shipped, delivered, cancelled
  RealColumn get deliveryFee => real().withDefault(const Constant(0))();
  IntColumn get deliveryCompanyId =>
      integer().nullable().references(DeliveryCompanies, #id)();
  IntColumn get deliveryCompanyPartyId => integer().nullable().references(
    Parties,
    #id,
  )(); // #Phase2: رابط مالي مع شركة التوصيل
  IntColumn get courierId => integer().nullable().references(Couriers, #id)();
  IntColumn get orderNumber =>
      integer().nullable()(); // #Phase2: Daily order number (1..N)
  TextColumn get platformOrderNumber =>
      text().nullable()(); // #Phase4: External platform order ID (Talabat, etc.)
  BoolColumn get isLocked =>
      boolean().withDefault(const Constant(false))(); // #Phase4: Fiscal Lock
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  TextColumn get integrityHash => text().nullable()(); // TCE-02: هاش الفاتورة للأرشيف غير القابل للتعديل
  TextColumn get notes => text().nullable()();
  // ISS-FIN-05: Dedicated ad-hoc customer fields (previously embedded in notes)
  TextColumn get adhocCustomerName => text().nullable()();
  TextColumn get adhocCustomerPhone => text().nullable()();
  TextColumn get adhocCustomerNote => text().nullable()();

  // Phase 4: Distributed Sync Reliability

  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  TextColumn get idempotencyKey => text().nullable()(); // Deduplication key for offline replay resilience
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))(); // Soft Delete
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get deletedBy => integer().nullable().references(Users, #id)(); // PIR P0-01: Who deleted
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_sales_items_invoice', columns: {#invoiceId})
@TableIndex(name: 'idx_sales_items_product', columns: {#productId})
class SalesInvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(SalesInvoices, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  // Batch tracking for FEFO
  IntColumn get batchId => integer().nullable().references(
    ProductBatches,
    #id,
  )(); // الباتش المباع منه
  RealColumn get costPrice => real().withDefault(
    const Constant(0),
  )(); // NEW: Cost price at time of sale for profit calculation
  IntColumn get sortOrder => integer().withDefault(
    const Constant(0),
  )(); // NEW: Custom sort order in invoice
  TextColumn get note =>
      text().nullable()(); // NEW: Item notes for kitchen/delivery
  RealColumn get taxRate => real().withDefault(
    const Constant(0),
  )(); // NEW: Tax percentage for this item
  RealColumn get taxAmount =>
      real().withDefault(const Constant(0))(); // NEW: Calculated tax amount
  TextColumn get unitName => text().nullable()(); // NEW: Selected unit name (e.g., Piece, Box)
  RealColumn get quantityInBase =>
      real().withDefault(const Constant(1.0))(); // NEW: Conversion factor to base unit
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Held orders (suspended orders in POS that are not yet completed)
class HeldOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get holdNumber => text().withLength(max: 50)(); // HOLD-xxx
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  BoolColumn get discountIsPercent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  IntColumn get customerId => integer().nullable().references(Parties, #id)();
  TextColumn get customerName =>
      text().nullable()(); // اسم العميل الاختياري للتمييز
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Items in a held order
class HeldOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get heldOrderId => integer().references(HeldOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get customPrice => real().nullable()(); // For weight-based pricing
  TextColumn get note => text().nullable()(); // Item notes
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE ORDERS (أوامر الشراء)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('PurchaseOrderData')
@TableIndex(name: 'idx_po_supplier', columns: {#supplierId})
@TableIndex(name: 'idx_po_date', columns: {#orderDate})
class PurchaseOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNumber => text().withLength(max: 50)();
  IntColumn get supplierId => integer().references(Parties, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  DateTimeColumn get orderDate => dateTime()();
  DateTimeColumn get expectedDate => dateTime().nullable()(); // تاريخ التسليم المتوقع

  /// v164 — تاريخُ اكتمال الاستلام فعليّاً.
  ///
  /// وجودُه هو ما يجعل «الالتزامَ بمواعيد التوريد» رقماً **مقيساً** لا
  /// مكتوباً: النسبةُ = أوامرُ استُلمت في موعدها ÷ أوامرُ استُلمت. و`null`
  /// تعني «لم يكتمل استلامُه بعد» — لا «تأخّر»، فأمرٌ مفتوحٌ ليس تأخّراً.
  DateTimeColumn get receivedAt => dateTime().nullable()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, sent, confirmed, received, cancelled
  TextColumn get notes => text().nullable()();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  IntColumn get convertedToInvoiceId => integer().nullable().references(PurchaseInvoices, #id)(); // ربط بفاتورة المشتريات
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_po_items_order', columns: {#orderId})
@TableIndex(name: 'idx_po_items_product', columns: {#productId})
class PurchaseOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(PurchaseOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  RealColumn get receivedQuantity => real().withDefault(const Constant(0))(); // الكمية المستلمة
  RealColumn get taxRate => real().withDefault(const Constant(0))(); // نسبة الضريبة
  RealColumn get taxAmount => real().withDefault(const Constant(0))(); // مبلغ الضريبة
  TextColumn get notes => text().nullable()();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// SALES ORDERS (أوامر البيع / طلبات البيع)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('SalesOrderData')
@TableIndex(name: 'idx_so_customer', columns: {#customerId})
@TableIndex(name: 'idx_so_date', columns: {#orderDate})
class SalesOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNumber => text().withLength(max: 50)();
  IntColumn get customerId => integer().nullable().references(Parties, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  DateTimeColumn get orderDate => dateTime()();
  DateTimeColumn get expectedDate => dateTime().nullable()(); // تاريخ التسليم المتوقع
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, sent, confirmed, delivered, cancelled
  TextColumn get notes => text().nullable()();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  IntColumn get convertedToInvoiceId => integer().nullable().references(SalesInvoices, #id)(); // ربط بفاتورة المبيعات
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_so_items_order', columns: {#orderId})
@TableIndex(name: 'idx_so_items_product', columns: {#productId})
class SalesOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(SalesOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  RealColumn get deliveredQuantity => real().withDefault(const Constant(0))(); // الكمية المسلمة
  RealColumn get taxRate => real().withDefault(const Constant(0))(); // نسبة الضريبة
  RealColumn get taxAmount => real().withDefault(const Constant(0))(); // مبلغ الضريبة
  TextColumn get notes => text().nullable()();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENTS (المدفوعات المستقلة)
// ═══════════════════════════════════════════════════════════════════════════

/// جدول مدفوعات مستقل — يدعم الدفع الجزئي والمتعدد لنفس الفاتورة.
/// كل سجل يمثل عملية دفع واحدة (نقدي / بنكي / إلكتروني)
@DataClassName('PaymentData')
@TableIndex(name: 'idx_payments_date', columns: {#paymentDate})
@TableIndex(name: 'idx_payments_party', columns: {#partyId})
@TableIndex(name: 'idx_payments_safe', columns: {#safeId})

@TableIndex(name: 'idx_payments_idempotency', columns: {#idempotencyKey})
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get paymentNumber => text().withLength(max: 50)(); // PAY-xxx
  DateTimeColumn get paymentDate => dateTime()();
  RealColumn get amount => real()(); // المبلغ المدفوع
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))(); // cash, bank, card, click
  IntColumn get safeId => integer().references(Safes, #id)(); // الصندوق/البنك المستلم
  IntColumn get partyId => integer().nullable().references(Parties, #id)(); // العميل أو المورد
  TextColumn get paymentType => text()(); // receipt=سند قبض, payment=سند صرف
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  IntColumn get safeTransactionId => integer().nullable().references(SafeTransactions, #id)(); // ربط بحركة الخزينة

  // Phase 4: Distributed Sync Reliability

  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  TextColumn get idempotencyKey => text().nullable()(); // Deduplication key for offline replay resilience
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))(); // Soft Delete
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get deletedBy => integer().nullable().references(Users, #id)(); // PIR P0-01: Who deleted
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// ربط المدفوعات بالفواتير — يسمح بتوزيع مبلغ الدفعة على أكثر من فاتورة
@DataClassName('PaymentAllocationData')
@TableIndex(name: 'idx_payment_alloc_payment', columns: {#paymentId})
@TableIndex(name: 'idx_payment_alloc_invoice_type', columns: {#invoiceType, #invoiceId})
class PaymentAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId => integer().references(Payments, #id)();
  TextColumn get invoiceType => text()(); // sales, purchase
  IntColumn get invoiceId => integer()(); // ID الفاتورة (SalesInvoice أو PurchaseInvoice)
  RealColumn get allocatedAmount => real()(); // المبلغ المخصص لهذه الفاتورة
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// v114 / Feature 009 — Auto-Deplete BOM on Sale: consumption log
// ═══════════════════════════════════════════════════════════════════════════

/// Append-only audit + reversal log of every raw-material deduction caused by
/// an auto-deplete sale. Critical for exact-cost returns (FR-021) — the
/// `unitCostAtSale` column freezes the WAC at sale time so partial/full
/// returns restore inventory at the original cost, not the post-sale WAC.
///
/// Sync policy: appendOnly (Constitution III, R5).
///
/// Note: `reversedByReturnId` references SalesInvoices(id) (the return invoice
/// row, status='returned'), NOT a SalesReturns table — that table does not
/// exist in this codebase. Returns are modeled as new sales_invoices rows.
@DataClassName('SaleBomConsumptionData')
@TableIndex(name: 'idx_sale_bom_consumptions_invoice', columns: {#saleInvoiceId})
@TableIndex(name: 'idx_sale_bom_consumptions_global', columns: {#globalId})
class SaleBomConsumptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleInvoiceId => integer().references(SalesInvoices, #id)();
  IntColumn get saleInvoiceItemId =>
      integer().references(SalesInvoiceItems, #id)();
  IntColumn get bomId => integer().references(BillOfMaterials, #id)();
  IntColumn get rawMaterialId => integer().references(Products, #id)();
  RealColumn get consumedQty => real()(); // base unit
  RealColumn get unitCostAtSale => real()(); // WAC frozen at sale time
  RealColumn get wastageApplied =>
      real().withDefault(const Constant(0))(); // 0..1 fraction (0.02 = 2%)
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)();
  // Marks the row as reversed by a sales-return invoice (immutable once set).
  IntColumn get reversedByReturnId =>
      integer().nullable().references(SalesInvoices, #id)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  // Deterministic UUIDv5 derived from (saleGlobalId, rawMaterialId, seq) so
  // retries produce identical IDs (idempotency under fire-and-forget pushes).
  TextColumn get globalId => text().unique()();
}

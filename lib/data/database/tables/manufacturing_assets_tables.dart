part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MANUFACTURING (التصنيع — Bill of Materials + Production Orders)
// ═══════════════════════════════════════════════════════════════════════════

/// Bill of Materials — قائمة المكونات للمنتج المصنّع
@DataClassName('BillOfMaterialData')
class BillOfMaterials extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get finishedProductId => integer().references(Products, #id)();
  TextColumn get bomCode => text().withLength(max: 30)();
  RealColumn get expectedQuantity => real().withDefault(const Constant(1))();
  RealColumn get estimatedCost => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // v114 — Feature 009 (Auto-Deplete BOM on Sale)
  // When true, selling the finished product deducts raw materials directly
  // at sale time instead of requiring a manual production order.
  BoolColumn get autoDepleteOnSale =>
      boolean().withDefault(const Constant(false))();
  // Allowed values: 'prefer_finished_stock' (RD-1 default — deduct on-hand
  // finished stock first, auto-deplete only the residual) or
  // 'always_auto_deplete' (ignore finished stock).
  TextColumn get depletionPolicy => text()
      .withLength(max: 30)
      .withDefault(const Constant('prefer_finished_stock'))();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  //
  // أُضيفت مع أبنائها لا بعدَها: `manufacturing_orders` و`bom_components`
  // تشيران إليها، فجهازٌ يستقبل الابنَ بلا الأبِ يكسر مفتاحَه. وحارسُ
  // التغطية كان يعدّها مُزامَنةً لأنّ اسمَها يرد في **تعليقٍ** داخلَ
  // `sale_bom_consumption_sync_strategy.dart` — والحارسُ يقرأ نصَّ الملفّ
  // كلَّه بما فيه التعليقات.
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// BOM Components — مكونات كل قائمة تصنيع
@DataClassName('BomComponentData')
@TableIndex(name: 'idx_bom_components_bom', columns: {#bomId})
class BomComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bomId => integer().references(BillOfMaterials, #id)();
  IntColumn get rawMaterialId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  TextColumn get unit =>
      text().withLength(max: 20).withDefault(const Constant('قطعة'))();
  RealColumn get quantityInBase =>
      real().withDefault(const Constant(1))(); // معامل التحويل للوحدة الأساسية
  RealColumn get wastagePercent =>
      real().withDefault(const Constant(0))(); // نسبة الهالك

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Manufacturing Orders — أوامر الإنتاج
@DataClassName('ManufacturingOrderData')
@TableIndex(name: 'idx_mfg_orders_status', columns: {#status})
class ManufacturingOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNumber => text().withLength(max: 30)();
  IntColumn get bomId => integer().references(BillOfMaterials, #id)();
  RealColumn get orderedQty => real()();
  RealColumn get producedQty => real().withDefault(const Constant(0))();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  // Status: draft, in_progress, completed, cancelled
  RealColumn get additionalCosts => real().withDefault(const Constant(0))();
  RealColumn get totalCost => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════════════════
// FIXED ASSETS (الأصول الثابتة والإهلاك)
// ═══════════════════════════════════════════════════════════════════════════

/// Asset categories — فئات الأصول
class AssetCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  RealColumn get defaultUsefulLife =>
      real().withDefault(const Constant(5))(); // بالسنوات
  TextColumn get defaultDepreciationMethod =>
      text().withDefault(const Constant('straight_line'))();
  IntColumn get accountId =>
      integer().nullable().references(Accounts, #id)(); // حساب الأصل
  IntColumn get depreciationAccountId =>
      integer().nullable().references(Accounts, #id)(); // حساب الإهلاك

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Fixed Assets — بطاقة الأصل الثابت
@DataClassName('FixedAssetData')
@TableIndex(name: 'idx_fixed_assets_category', columns: {#categoryId})
class FixedAssets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 30)();
  TextColumn get name => text().withLength(max: 100)();
  IntColumn get categoryId => integer().references(AssetCategories, #id)();
  TextColumn get location => text().nullable().withLength(max: 100)();
  RealColumn get purchasePrice => real()();
  DateTimeColumn get purchaseDate => dateTime()();
  RealColumn get usefulLifeYears => real()();
  RealColumn get salvageValue => real().withDefault(const Constant(0))();
  TextColumn get depreciationMethod =>
      text().withDefault(const Constant('straight_line'))();
  // Methods: straight_line, declining_balance
  RealColumn get accumulatedDepreciation =>
      real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  // Status: active, disposed, sold
  DateTimeColumn get disposalDate => dateTime().nullable()();
  RealColumn get disposalValue => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)();
  // v142 (Feature 004): per-asset Chart-of-Accounts sub-account linkage.
  // The linked account is created atomically with the asset (DAO contract).
  // Acquisition + depreciation JEs continue to debit the category account
  // (Constitution I — Behavior Preservation). Per-asset GL flows out of scope.
  IntColumn get linkedAccountId => integer().nullable().references(Accounts, #id)();

  /// v174 — المسؤولُ عن الأصل (بطاقةُ الأصل، بلاغُ المالك 2026-09-18).
  ///
  /// **مستخدمٌ من النظام لا نصٌّ حرّ** بقرار المالك: النصُّ يُكتَب بثلاث
  /// صيغٍ للشخص الواحد فلا يُجمَع عليه ولا يُساءَل به، والربطُ يجعل «ما في
  /// عهدة فلان» استعلاماً لا بحثاً.
  IntColumn get custodianUserId =>
      integer().nullable().references(Users, #id)();

  TextColumn get globalId => text().nullable().unique()();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// طلبُ استبعاد أصلٍ — مستندٌ مستقلٌّ له دورةُ حياة.
///
/// ═══ لماذا جدولٌ لا أعمدةٌ على `FixedAssets` ═══
///
/// بقرار المالك 2026-09-18 صار للاستبعاد **زرّان منفصلان** (حفظُ مسوّدةٍ ثمّ
/// مراجعةٌ واعتماد)، وصار تحصيلُه **نقديّاً أو آجلاً على ذمّة عميل**. فلزم
/// حفظُ طريقةٍ ومشترٍ وطريقةِ تحصيلٍ وحالةٍ ومَن اعتمد ومتى.
///
/// والاستبعادُ **حدثٌ** لا صفةٌ في الأصل: خمسةُ أعمدةٍ على `FixedAssets`
/// تترك الأصلَ محمَّلاً بحقولٍ ميّتةٍ لو رُفض الطلبُ أو أُلغي، ولا تُبقي أثراً
/// لمن طلب ومن رفض.
///
/// والسابقةُ في هذا المستودع صريحة: `LandedCostSheets` مستندٌ مرتبطٌ بفاتورةٍ
/// له `status: draft · applied · cancelled · voided` — وهذا نفسُ الشكل.
///
/// ⚠️ و`FixedAssets.status` **لا يُلمَس إلّا لحظةَ الاعتماد**: مسوّدةٌ تُغيّر
/// حالةَ الأصل تُخرجه من التقارير قبل أن يُوافَق على إخراجه.
@DataClassName('AssetDisposalData')
@TableIndex(name: 'idx_asset_disposals_asset', columns: {#assetId})
@TableIndex(name: 'idx_asset_disposals_status', columns: {#status})
class AssetDisposals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get assetId => integer().references(FixedAssets, #id)();

  /// رقمُ الطلب المتسلسل — `ADP-####`.
  TextColumn get disposalNumber => text().withLength(max: 50)();

  DateTimeColumn get disposalDate => dateTime()();

  /// `sale` (بيع) · `scrap` (إعدام) · `donation` (تبرّع) · `writeoff` (تخريد)
  TextColumn get method => text().withLength(max: 20)();

  /// ثمنُ البيع المتوقَّع. صفرٌ للإعدام والتبرّع.
  RealColumn get disposalValue => real().withDefault(const Constant(0))();

  /// `cash` (نقديّ) · `credit` (آجلٌ على ذمّة العميل)
  ///
  /// ⚠️ و`credit` يفرض `buyerPartyId` غيرَ فارغ: بلا طرفٍ مسجَّلٍ لا ذمّةَ
  /// تُحمَّل، فيصير القيدُ بلا مدينٍ حقيقيّ.
  TextColumn get collectionMethod =>
      text().withLength(max: 10).withDefault(const Constant('cash'))();

  /// المشتري. نصٌّ حرٌّ لا يكفي في `credit` — انظر أعلاه.
  IntColumn get buyerPartyId => integer().nullable().references(Parties, #id)();

  /// سببُ الاستبعاد — بقرار المالك يُستعمَل الحقلُ العامُّ لا عمودٌ جديد.
  TextColumn get notes => text().nullable()();

  /// `draft` · `approved` · `cancelled`
  TextColumn get status =>
      text().withLength(max: 12).withDefault(const Constant('draft'))();

  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  IntColumn get approvedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  IntColumn get costCenterId =>
      integer().nullable().references(CostCenters, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === أعمدةُ المزامنة ===
  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Asset Depreciation entries — سجل الإهلاك الدوري
@DataClassName('AssetDepreciationData')
@TableIndex(name: 'idx_asset_depreciation_asset', columns: {#assetId})
class AssetDepreciations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get assetId => integer().references(FixedAssets, #id)();
  DateTimeColumn get periodDate => dateTime()(); // تاريخ فترة الإهلاك
  RealColumn get depreciationAmount => real()(); // مبلغ الإهلاك
  RealColumn get accumulatedDepreciation => real()(); // الإهلاك المتراكم
  RealColumn get bookValue => real()(); // القيمة الدفترية
  IntColumn get journalEntryId => integer().nullable()(); // قيد الإهلاك
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v166 — أعمدةُ المزامنة (المرحلة ٢) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

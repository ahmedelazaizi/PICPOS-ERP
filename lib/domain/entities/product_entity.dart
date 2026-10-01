import 'dart:typed_data';

/// Product entity for domain layer
///
/// Pure domain entity - no Drift or UI dependencies
class ProductEntity {
  final int id;
  final String code;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final double salePrice;
  final double costPrice;
  final double? pricePerUnit;
  final double currentStock;
  final double minStock;
  final bool trackInventory;
  final bool trackExpiry;
  final bool isSoldByWeight;
  final bool isActive;
  final String? description;
  final String? barcode;
  final int? scalePluNumber;
  final String? scaleType;
  final double taxRate;
  final bool isLocked;
  final bool allowNegativeSale;
  final int defaultShelfDays;
  final int alertDaysBefore;
  final double priceTalabat;
  final double priceCareem;
  final double priceAshyae;
  final double wholesalePrice;
  final int? supplierId;
  final Uint8List? imageData;
  final String productType;
  final int? warehouseId;

  /// v138 (Issue 2): true when the row was created directly on the server
  /// (admin via the desktop server UI) rather than round-tripped through a
  /// client interceptor. The product-edit dialog reads this in client mode
  /// to lock the form: server-canonical rows must be edited on the server
  /// to keep the SoT consistent across all clients.
  final bool createdOnServer;

  /// B3 — `products.tax_exempt` (raw column, v182): the item is taxed at 0 %
  /// everywhere. Resolve rates with `effectiveItemTaxRate`
  /// (`lib/core/tax/effective_item_tax_rate.dart`).
  final bool taxExempt;

  const ProductEntity({
    required this.id,
    required this.code,
    required this.name,
    this.categoryId,
    this.categoryName,
    required this.salePrice,
    required this.costPrice,
    this.pricePerUnit,
    required this.currentStock,
    required this.minStock,
    this.trackInventory = true,
    this.trackExpiry = false,
    this.isSoldByWeight = false,
    this.isActive = true,
    this.description,
    this.barcode,
    this.scalePluNumber,
    this.scaleType,
    this.taxRate = 14.0,
    this.isLocked = false,
    this.allowNegativeSale = false,
    this.defaultShelfDays = 90,
    this.alertDaysBefore = 30,
    this.priceTalabat = 0,
    this.priceCareem = 0,
    this.priceAshyae = 0,
    this.wholesalePrice = 0,
    this.supplierId,
    this.imageData,
    this.productType = 'general',
    this.warehouseId,
    this.createdOnServer = true,
    this.taxExempt = false,
  });

  /// Check if stock is low
  bool get isLowStock => trackInventory && currentStock <= minStock;

  /// Check if out of stock
  bool get isOutOfStock => trackInventory && currentStock <= 0 && !allowNegativeSale;

  /// Profit margin
  double get profitMargin {
    if (costPrice == 0) return 0;
    return ((salePrice - costPrice) / costPrice) * 100;
  }

  /// Stock value
  double get stockValue => currentStock * costPrice;

  ProductEntity copyWith({
    int? id,
    String? code,
    String? name,
    int? categoryId,
    String? categoryName,
    double? salePrice,
    double? costPrice,
    double? pricePerUnit,
    double? currentStock,
    double? minStock,
    bool? trackInventory,
    bool? trackExpiry,
    bool? isSoldByWeight,
    bool? isActive,
    String? description,
    String? barcode,
    int? scalePluNumber,
    String? scaleType,
    double? taxRate,
    bool? isLocked,
    bool? allowNegativeSale,
    int? defaultShelfDays,
    int? alertDaysBefore,
    double? priceTalabat,
    double? priceCareem,
    double? priceAshyae,
    double? wholesalePrice,
    int? supplierId,
    Uint8List? imageData,
    String? productType,
    int? warehouseId,
    bool? createdOnServer,
    bool? taxExempt,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      salePrice: salePrice ?? this.salePrice,
      costPrice: costPrice ?? this.costPrice,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      trackInventory: trackInventory ?? this.trackInventory,
      trackExpiry: trackExpiry ?? this.trackExpiry,
      isSoldByWeight: isSoldByWeight ?? this.isSoldByWeight,
      isActive: isActive ?? this.isActive,
      description: description ?? this.description,
      barcode: barcode ?? this.barcode,
      scalePluNumber: scalePluNumber ?? this.scalePluNumber,
      scaleType: scaleType ?? this.scaleType,
      taxRate: taxRate ?? this.taxRate,
      isLocked: isLocked ?? this.isLocked,
      allowNegativeSale: allowNegativeSale ?? this.allowNegativeSale,
      defaultShelfDays: defaultShelfDays ?? this.defaultShelfDays,
      alertDaysBefore: alertDaysBefore ?? this.alertDaysBefore,
      priceTalabat: priceTalabat ?? this.priceTalabat,
      priceCareem: priceCareem ?? this.priceCareem,
      priceAshyae: priceAshyae ?? this.priceAshyae,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      supplierId: supplierId ?? this.supplierId,
      imageData: imageData ?? this.imageData,
      productType: productType ?? this.productType,
      warehouseId: warehouseId ?? this.warehouseId,
      createdOnServer: createdOnServer ?? this.createdOnServer,
      taxExempt: taxExempt ?? this.taxExempt,
    );
  }
}

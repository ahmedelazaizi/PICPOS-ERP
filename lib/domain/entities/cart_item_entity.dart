import '../../core/tax/effective_item_tax_rate.dart';
import '../../core/utils/number_utils.dart';
import '../../presentation/pos/widgets/modifier_selection_dialog.dart';

/// Item type for exchange operations
enum CartItemType {
  normal, // Regular sale item
  returned, // Returned item (negative - customer returning)
  exchanged, // Exchanged item (positive - customer taking)
}

/// Cart item entity for POS operations
///
/// Pure domain entity - no Drift or UI dependencies
class CartItemEntity {
  final int productId;
  final int? categoryId; // NEW: for classification/matching
  final String productName;
  final String productCode;
  final String? barcode; // Product barcode (user-entered) for printing
  final double quantity;
  final double unitPrice;
  final double? customPrice;
  final double discountPercent;
  final double taxRate;
  final double taxAmount;
  final String? note;
  final String? itemNote; // manual note entered by cashier
  final bool isSoldByWeight;
  final CartItemType itemType; // NEW: for exchange mode
  final List<SelectedModifier> modifiers; // structured addons/options
  // UOM fields: unit-aware pricing & stock conversion
  final int? selectedUnitId; // ProductUnit.id (null = base unit)
  final String? selectedUnitName; // e.g. 'كرتونة' for display
  final double quantityInBase; // conversion factor (e.g. 24 for carton=24 pieces)
  /// B3 — the product is «معفى من الضريبة»: the line is taxed at 0 %
  /// whatever [taxRate] or the company default say (`effectiveItemTaxRate`).
  final bool taxExempt;

  const CartItemEntity({
    required this.productId,
    this.categoryId,
    required this.productName,
    required this.productCode,
    this.barcode,
    required this.quantity,
    required this.unitPrice,
    this.customPrice,
    this.discountPercent = 0,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.note,
    this.itemNote,
    this.isSoldByWeight = false,
    this.itemType = CartItemType.normal,
    this.modifiers = const [],
    this.selectedUnitId,
    this.selectedUnitName,
    this.quantityInBase = 1.0,
    this.taxExempt = false,
  });

  /// Effective price per unit
  double get effectivePrice => customPrice ?? unitPrice;

  /// Stock quantity in base units (e.g., 3 cartons × 24 pieces/carton = 72 pieces)
  double get stockQuantity => quantity * quantityInBase;

  /// Line subtotal before discount
  double get subtotal => NumberUtils.roundCurrency(quantity * effectivePrice);

  /// Discount amount
  double get discountAmount =>
      NumberUtils.roundCurrency(subtotal * (discountPercent / 100));

  /// Line total after discount (before tax)
  double get totalBeforeTax =>
      NumberUtils.roundCurrency(subtotal - discountAmount);

  /// Line tax amount
  double get calculatedTaxAmount => NumberUtils.roundCurrency(totalBeforeTax *
      (effectiveItemTaxRate(
              rate: taxRate, exempt: taxExempt, companyDefault: 0) /
          100));

  /// Grand total for this line (including tax)
  double get total =>
      NumberUtils.roundCurrency(totalBeforeTax + calculatedTaxAmount);

  /// Create copy with modifications
  CartItemEntity copyWith({
    int? productId,
    int? categoryId,
    String? productName,
    String? productCode,
    String? barcode,
    double? quantity,
    double? unitPrice,
    double? customPrice,
    double? discountPercent,
    double? taxRate,
    double? taxAmount,
    String? note,
    String? itemNote,
    bool? isSoldByWeight,
    CartItemType? itemType,
    List<SelectedModifier>? modifiers,
    int? selectedUnitId,
    String? selectedUnitName,
    double? quantityInBase,
    bool? taxExempt,
    // `x ?? this.x` معناها إن `null` = «ما تغيّرش»، فمفيش طريقة تمسح ملاحظة
    // اتكتبت غلط: الكاشير يمسحها ويحفظ وهي تفضل مكتوبة وتتطبع على تذكرة
    // المطبخ. العلمين دول المخرج الوحيد. القيمة الافتراضية `false` =
    // سلوك النهاردة بالحرف لكل المواضع التانية في المنتجين.
    bool clearNote = false,
    bool clearItemNote = false,
  }) {
    return CartItemEntity(
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      barcode: barcode ?? this.barcode,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      customPrice: customPrice ?? this.customPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      taxRate: taxRate ?? this.taxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      note: clearNote ? null : (note ?? this.note),
      itemNote: clearItemNote ? null : (itemNote ?? this.itemNote),
      isSoldByWeight: isSoldByWeight ?? this.isSoldByWeight,
      itemType: itemType ?? this.itemType,
      modifiers: modifiers ?? this.modifiers,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      selectedUnitName: selectedUnitName ?? this.selectedUnitName,
      quantityInBase: quantityInBase ?? this.quantityInBase,
      taxExempt: taxExempt ?? this.taxExempt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItemEntity &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          quantity == other.quantity &&
          effectivePrice == other.effectivePrice;

  @override
  int get hashCode =>
      productId.hashCode ^ quantity.hashCode ^ effectivePrice.hashCode;
}

/// B3 — marks every line whose product id is in [exemptProductIds] as
/// [CartItemEntity.taxExempt] with its stored rate zeroed, so readers of the
/// raw `taxRate` agree too. Other lines are returned untouched (same
/// instances); a line already flagged is never un-flagged.
List<CartItemEntity> applyTaxExemptProductIds(
  List<CartItemEntity> items,
  Set<int> exemptProductIds,
) {
  if (exemptProductIds.isEmpty) return items;
  return [
    for (final item in items)
      exemptProductIds.contains(item.productId)
          ? item.copyWith(taxExempt: true, taxRate: 0, taxAmount: 0)
          : item,
  ];
}

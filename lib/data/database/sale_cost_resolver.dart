import 'package:drift/drift.dart';

import 'database.dart';

/// الافتراضي الموحَّد لـ `zero_cost_policy` عند غياب المفتاح (قرار موثَّق).
///
/// قرار المالك: الافتراضي `warn` (يحفظ البيع بتكلفة صفر دون رفض) وهو افتراضي
/// البذر (`database_seeder.dart`) و`JournalEntryFactory`. عند اختيار المستخدم
/// `block` صراحةً يُرمى [CostRequiredException] فتسأل الواجهة عن التكلفة ثم
/// تعيد المحاولة.
const String kDefaultZeroCostPolicy = 'warn';

/// مصدر التكلفة المعتمدة لسطر بيع.
enum SaleCostSource {
  /// لقطة السطر نفسه (أو تكلفة مؤقتة أدخلها المسؤول).
  item,

  /// `products.costPrice` (متوسط التكلفة المرجّح الجاري).
  productCost,

  /// متوسط سعر الشراء من فواتير المشتريات غير المحذوفة.
  purchaseAverage,

  /// لا تكلفة معروفة.
  none,
}

class ResolvedSaleCost {
  const ResolvedSaleCost(this.cost, this.source);
  final double cost;
  final SaleCostSource source;
  bool get isKnown => cost > 0;
}

/// تُرمى حين لا توجد تكلفة معروفة والسياسة `block`: الواجهة تلتقطها وتسأل
/// الكاشير/المسؤول عن تكلفة الصنف ثم تعيد الحفظ بـ `costPrice` في السطر.
/// ترث [Exception] فيبقى أي `catch`/`throwsA(isA<Exception>())` قائماً يعمل.
class CostRequiredException implements Exception {
  CostRequiredException(this.productId, this.productName);
  final int productId;
  final String productName;

  @override
  String toString() => 'Exception: تعذّر حفظ الفاتورة: الصنف "$productName" '
      'متعقّب للمخزون وتكلفته غير محددة. يرجى تحديث تكلفة الصنف أولاً.';
}

/// نقطة واحدة لحل تكلفة البيع. الترتيب:
/// 1) تكلفة السطر (> 0) — تشمل التكلفة المؤقتة التي أدخلها المسؤول.
/// 2) `products.costPrice` (> 0).
/// 3) متوسط الشراء من `purchase_invoice_items`.
/// 4) لا شيء ⇒ [SaleCostSource.none] والمستدعي يطبّق السياسة/السؤال.
/// لا يُستخدم سعر البيع كتكلفة أبداً.
class SaleCostResolver {
  SaleCostResolver(this._db);
  final AppDatabase _db;

  Future<ResolvedSaleCost> resolve({
    required int productId,
    double? itemCost,
    double? productCost,
  }) async {
    if (itemCost != null && itemCost > 0) {
      return ResolvedSaleCost(itemCost, SaleCostSource.item);
    }
    final pc = productCost ?? (await _db.getProductById(productId))?.costPrice;
    if (pc != null && pc > 0) {
      return ResolvedSaleCost(pc, SaleCostSource.productCost);
    }
    final avg = await purchaseAverageCost(productId);
    if (avg > 0) return ResolvedSaleCost(avg, SaleCostSource.purchaseAverage);
    return const ResolvedSaleCost(0, SaleCostSource.none);
  }

  /// متوسط مرجّح للتكلفة بوحدة الأساس؛ 0 إن لم يُشترَ الصنف قط.
  Future<double> purchaseAverageCost(int productId) async {
    final row = await _db.customSelect(
      'SELECT SUM(i.quantity * i.unit_cost) AS amt, '
      'SUM(i.quantity * i.quantity_in_base) AS qty '
      'FROM purchase_invoice_items i '
      'JOIN purchase_invoices p ON p.id = i.invoice_id '
      'WHERE i.product_id = ? AND i.deleted_at IS NULL '
      'AND p.is_deleted = 0 AND i.unit_cost > 0 AND i.quantity > 0',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    final qty = row.read<double?>('qty') ?? 0;
    final amt = row.read<double?>('amt') ?? 0;
    return qty > 0 ? amt / qty : 0;
  }

  /// السياسة الفعلية (مع الافتراضي الموحّد).
  Future<String> policy() async =>
      (await _db.getSettingValue('zero_cost_policy')) ?? kDefaultZeroCostPolicy;

  /// تسجيل التكلفة المؤقتة على الصنف إن كان بلا تكلفة (يُصحَّحها الشراء
  /// التالي عبر WAC لأن الرصيد سالب/صفر). لا تُستبدل تكلفة موجودة.
  Future<void> recordProvisionalCost(int productId, double cost) async {
    if (cost <= 0) return;
    await (_db.update(_db.products)
          ..where((p) => p.id.equals(productId) & p.costPrice.equals(0)))
        .write(ProductsCompanion(costPrice: Value(cost)));
  }
}

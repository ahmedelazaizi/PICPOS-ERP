import '../core/utils/financial_utils.dart';
import '../domain/repositories/settings_repository.dart';

/// ───────────────────────────────────────────────────────────────────
/// Costing Method Service
/// ───────────────────────────────────────────────────────────────────
/// يحدّد صيغة تحميل تكلفة المخزون عند استلام المشتريات.
///
/// ── الصيغ المسموح بها (IAS 2.23-25) ────────────────────────────────
/// المعيار يحصر صيغ تحميل التكلفة في:
///   · المتوسط المرجّح            ← المنفَّذ هنا
///   · الوارد أولاً صادر أولاً (FIFO) ← مسموح، غير منفَّذ (يحتاج طبقات حقيقية)
///   · التمييز المحدد              ← للأصناف غير المتماثلة فقط
/// و LIFO ممنوعة منذ تعديل ٢٠٠٣.
///
/// ── لماذا حُذفت «آخر سعر شراء» ─────────────────────────────────────
/// لم تكن صيغة تحميل تكلفة أصلاً — هي قياس **تكلفة إحلال / جارية**.
/// استعمالها يكتب على `products.costPrice` قيمة لا تقابلها أي حركة في
/// الأستاذ، فيقفز تقييم المخزون بلا قيد مقابل وينحرف عن الحساب الرقابي
/// ١١٣٦. وكانت هي **الافتراضية** ومعروضة في شاشة الإعدادات في المنتجين،
/// بينما مسار الشراء الحيّ (`purchase_dao.createPurchaseInvoice`) يستعمل
/// المتوسط المرجّح مثبَّتاً ويتجاهل الإعداد — وعْد كاذب في الاتجاهين.
///
/// إن كانت الحاجة الفعلية «آخر سعر شراء» لأغراض **التسعير** (بكم أبيع)
/// فذلك قرار مختلف تماماً ويُعرض كمساعد تسعير بعيداً عن التكلفة.
///
/// ── تغيير الصيغة = تغيير سياسة محاسبية ─────────────────────────────
/// `IAS 8` يجعل تبديل الصيغة تغييراً في السياسة المحاسبية يستوجب تعديلاً
/// بأثر رجعي، و`IAS 2.25` يوجب الصيغة نفسها لكل المخزون المتماثل في
/// الطبيعة والاستخدام. فالاختيار قرار إعداد لا تفضيل استخدام.
///
/// مخزَّنة في `settings` تحت `costing_method` (P1-02: نُقلت من
/// SharedPreferences إلى جدول الإعدادات المشفَّر لتسافر مع النسخ الاحتياطية).

enum CostingMethod {
  weightedAverage, // متوسط مرجح (WAC) — الافتراضي والوحيد المنفَّذ
}

class CostingMethodService {
  static const _key = 'costing_method';

  /// أي قيمة مخزَّنة غير معروفة — بما فيها `lastPurchase` على التركيبات
  /// القائمة — تُقرأ كمتوسط مرجّح.
  ///
  /// ده **مش تغيير سلوك**: مسار الشراء الحيّ كان بيستعمل المتوسط المرجّح
  /// فعلاً ويتجاهل الإعداد، فالتصحيح في الاسم المعروض مش في الحساب.
  static Future<CostingMethod> load(ISettingsRepository settings) async {
    final value = await settings.getSetting(_key);
    return CostingMethod.values.firstWhere(
      (m) => m.name == value,
      orElse: () => CostingMethod.weightedAverage,
    );
  }

  static Future<void> save(
      ISettingsRepository settings, CostingMethod method) async {
    await settings.saveSetting(_key, method.name);
  }

  /// Calculate the new cost price based on the selected method.
  ///
  /// [currentStock] — existing quantity on hand
  /// [currentCost] — existing cost price per unit
  /// [purchaseQty] — new quantity being purchased
  /// [purchaseUnitCost] — unit cost of the new purchase
  static double calculateCost({
    required CostingMethod method,
    required double currentStock,
    required double currentCost,
    required double purchaseQty,
    required double purchaseUnitCost,
  }) {
    switch (method) {
      case CostingMethod.weightedAverage:
        final totalQty = currentStock + purchaseQty;
        if (totalQty <= 0) return purchaseUnitCost;
        // WAC = (existing_value + new_value) / total_qty
        // BUG-M04: round to financial precision (3dp) at write time so the
        // stored cost has no long float tail that drifts COGS/margin reports.
        final existingValue = currentStock * currentCost;
        final newValue = purchaseQty * purchaseUnitCost;
        return FinancialUtils.round((existingValue + newValue) / totalQty);
    }
  }

  /// Human-readable label
  static String label(CostingMethod method) {
    switch (method) {
      case CostingMethod.weightedAverage:
        return 'متوسط مرجح (WAC)';
    }
  }
}

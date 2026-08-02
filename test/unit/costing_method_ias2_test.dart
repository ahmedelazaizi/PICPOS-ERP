// طريقة حساب التكلفة — التوافق مع IAS 2.
//
// ── لماذا `lastPurchase` غير مقبولة ─────────────────────────────────────────
// `IAS 2` فقرة ٢٥ تحصر صيغ تحميل التكلفة في اثنتين لا ثالث لهما: **الوارد
// أولاً صادر أولاً (FIFO)** أو **المتوسط المرجّح**. وفقرة ٢٣ تسمح بالتمييز
// المحدد للأصناف غير المتماثلة. و LIFO ممنوعة منذ تعديل ٢٠٠٣.
//
// و«آخر سعر شراء» ليست صيغة تحميل تكلفة أصلاً — هي قياس **تكلفة إحلال /
// جارية**. استعمالها يكتب على `products.costPrice` قيمة لا تقابلها أي حركة
// في الأستاذ، فيقفز تقييم المخزون بلا قيد مقابل وينحرف عن الحساب الرقابي.
//
// ── الأثر الفعلي قبل الإصلاح ────────────────────────────────────────────────
// الخيار كان **الافتراضي** (`?? 'lastPurchase'`) ومعروضاً في شاشة الإعدادات
// في المنتجين. ومسار الشراء الحيّ (`purchase_dao.createPurchaseInvoice`)
// يستعمل المتوسط المرجّح مثبَّتاً في الكود ويتجاهل الإعداد — فالمستخدم كان
// يختار طريقة غير مسموحة ولا يحدث شيء. وعْد كاذب في الاتجاهين.
//
// ── لماذا لا نُوصِّل `lastPurchase` بدل حذفها ───────────────────────────────
// توصيلها يجعل النظام غير متوافق. الصحيح إزالتها كخيار قياس.
//
// ── تغيير الصيغة = تغيير سياسة محاسبية ──────────────────────────────────────
// `IAS 8` يجعل تبديل صيغة التكلفة تغييراً في السياسة المحاسبية يستوجب تعديلاً
// بأثر رجعي. فتوجل حر في الإعدادات هو نفسه مَخرج للمخالفة — لذلك
// [CostingMethod] لم يعد يحمل إلا الصيغ المسموحة، والاختيار بينها قرار إعداد
// لا تفضيل استخدام.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/services/costing_method_service.dart';

void main() {
  group('الصيغ المتاحة محصورة في المسموح به', () {
    test('«آخر سعر شراء» مش خيار', () {
      expect(
        CostingMethod.values.map((m) => m.name),
        isNot(contains('lastPurchase')),
      );
    });

    test('المتوسط المرجّح متاح', () {
      expect(CostingMethod.values, contains(CostingMethod.weightedAverage));
    });

    test('كل صيغة معروضة مسموحة في IAS 2.25', () {
      const permitted = {'weightedAverage', 'fifo', 'specificIdentification'};
      for (final m in CostingMethod.values) {
        expect(permitted, contains(m.name),
            reason: '${m.name} مش صيغة تحميل تكلفة مسموحة');
      }
    });
  });

  group('القيمة المخزّنة', () {
    test('الافتراضي هو المتوسط المرجّح مش آخر سعر شراء', () async {
      expect(await CostingMethodService.load(_EmptySettings()),
          CostingMethod.weightedAverage);
    });

    test('تركيبة قايمة مخزَّن فيها lastPurchase بتتقرا كمتوسط مرجّح', () async {
      // ترقية: القيمة القديمة موجودة في `settings` عند عملاء شغّالين. لازم
      // تتقرا كصيغة مسموحة بدل ما ترمي أو تفضل غير متوافقة. ومسار الشراء
      // الحيّ بيستعمل المتوسط المرجّح فعلاً، فده **مش تغيير سلوك** — ده
      // تصحيح للاسم اللي كان معروض.
      expect(await CostingMethodService.load(_Settings('lastPurchase')),
          CostingMethod.weightedAverage);
    });

    test('قيمة مش معروفة بتقع على المتوسط المرجّح', () async {
      expect(await CostingMethodService.load(_Settings('lifo')),
          CostingMethod.weightedAverage);
    });
  });

  group('calculateCost — المتوسط المرجّح', () {
    test('يمزج الرصيد القائم بالوارد الجديد', () {
      // ١٠ @ ١٠ ثم ١٠ @ ٢٠ ⇒ ٣٠٠ / ٢٠ = ١٥
      expect(
        CostingMethodService.calculateCost(
          method: CostingMethod.weightedAverage,
          currentStock: 10,
          currentCost: 10,
          purchaseQty: 10,
          purchaseUnitCost: 20,
        ),
        15.0,
      );
    });

    test('رصيد صفر أو سالب يقع على تكلفة الوارد', () {
      expect(
        CostingMethodService.calculateCost(
          method: CostingMethod.weightedAverage,
          currentStock: -5,
          currentCost: 10,
          purchaseQty: 5,
          purchaseUnitCost: 20,
        ),
        20.0,
      );
    });
  });
}

class _EmptySettings extends _Settings {
  _EmptySettings() : super(null);
}

class _Settings implements ISettingsRepository {
  _Settings(this._value);
  final String? _value;

  @override
  Future<String?> getSetting(String key) async => _value;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

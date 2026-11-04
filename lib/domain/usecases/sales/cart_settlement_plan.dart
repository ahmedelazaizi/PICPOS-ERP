import '../../../core/utils/financial_utils.dart';
import '../../entities/cart_item_entity.dart';
import 'calculate_invoice_totals_usecase.dart';

/// شكلُ السلّة عند الدفع.
enum CartSettlementKind {
  /// بيعٌ فقط — المسارُ القائمُ بلا أيّ تغيير.
  saleOnly,

  /// مرتجعٌ بلا فاتورة فقط — يُرَدّ نقداً.
  returnOnly,

  /// سلّةٌ مختلطة (بيع + مرتجع بلا فاتورة) — يُسوَّى الصافي.
  mixed,
}

/// خطّةُ تسويةِ سلّةٍ فيها سطورُ مرتجع (بند ٤).
///
/// ⚠️ **المستندُ الواحدُ إمّا بيعٌ وإمّا مرتجع** (`saleType='return'` يقلب
/// المستندَ كلَّه). فالسلّةُ المختلطة تُحفَظ مستندَين: فاتورةُ بيعٍ بسطور
/// البيع، ومستندُ `RET-` بسطور المرتجع. وصافي النقد = [net]، فالحركتان في
/// وردية الدرج تتقاصّان فيطابق الدرجُ ما قبضه الكاشير فعلاً.
///
/// الأرقامُ كلُّها **من نفس [CalculateInvoiceTotalsUseCase]** الذي يعرض
/// الإجماليَّ في الشاشة — لا حاسبَ ثانياً يفترق عنه عند أول تقريب.
class CartSettlementPlan {
  final CartSettlementKind kind;
  final List<CartItemEntity> saleItems;
  final List<CartItemEntity> returnItems;

  /// إجماليُّ مستند البيع (شاملاً رسومَ التوصيل وخصمَ الفاتورة) — موجبٌ دائماً.
  final double saleTotal;

  /// إجماليُّ مستند المرتجع — موجبٌ دائماً (لا خصمَ فاتورةٍ ولا رسوم توصيل عليه).
  final double returnTotal;

  const CartSettlementPlan({
    required this.kind,
    required this.saleItems,
    required this.returnItems,
    required this.saleTotal,
    required this.returnTotal,
  });

  bool get hasReturn => returnItems.isNotEmpty;
  bool get hasSale => saleItems.isNotEmpty;

  /// الصافي = بيع − مرتجع. السالبُ = نقدٌ يخرج من الدرج للعميل.
  double get net => FinancialUtils.round(saleTotal - returnTotal);

  /// ما يقبضه الكاشير من العميل (٠ حين الصافي ≤ ٠).
  double get cashToCollect => net > 0 ? net : 0;

  /// ما يردّه الكاشير نقداً للعميل (٠ حين الصافي ≥ ٠).
  double get cashToRefund => net < 0 ? -net : 0;
}

/// يقسم [items] إلى مستندَي بيعٍ ومرتجع ويحسب إجماليَّ كلٍّ منهما.
CartSettlementPlan planCartSettlement({
  required List<CartItemEntity> items,
  double invoiceDiscountPercent = 0,
  double? invoiceDiscountAmount,
  double taxPercent = 0,
  bool taxEnabled = true,
  double deliveryFee = 0,
}) {
  final calc = CalculateInvoiceTotalsUseCase();
  final returns = [
    for (final i in items)
      if (i.itemType == CartItemType.returned) i,
  ];
  final sales = [
    for (final i in items)
      if (i.itemType != CartItemType.returned) i,
  ];

  final saleTotal = sales.isEmpty
      ? 0.0
      : FinancialUtils.round(calc
              .execute(
                items: sales,
                invoiceDiscountPercent: invoiceDiscountPercent,
                invoiceDiscountAmount: invoiceDiscountAmount,
                taxPercent: taxPercent,
                taxEnabled: taxEnabled,
              )
              .total +
          deliveryFee);
  final returnTotal = returns.isEmpty
      ? 0.0
      : calc
          .execute(
            items: returns,
            taxPercent: taxPercent,
            taxEnabled: taxEnabled,
          )
          .total;

  return CartSettlementPlan(
    kind: returns.isEmpty
        ? CartSettlementKind.saleOnly
        : (sales.isEmpty
            ? CartSettlementKind.returnOnly
            : CartSettlementKind.mixed),
    saleItems: sales,
    returnItems: returns,
    saleTotal: saleTotal,
    returnTotal: returnTotal,
  );
}

/// هل يُفتح الدرجُ آلياً بعد حفظ هذه التسوية؟
///
/// **قرارٌ مسجَّل:** يُفتح فقط حين **يقبض** الكاشيرُ نقداً صافياً (صافٍ موجب)،
/// مع احترام إعداد `drawer` الذي يقيّمه المنادي بـ[drawerSettingOn]. ولا يُفتح
/// عند ردِّ نقدٍ (صافٍ ≤ ٠): قرارُ المالك 2026-10-30 مربوطٌ بـ«قبض نقد»، وطلبُ
/// المالك صراحةً ألّا يُفتح عند الرد؛ ويبقى فتحُه اليدويّ (`pos_open_drawer`)
/// متاحاً للكاشير لإخراج المبلغ.
bool shouldKickDrawerForSettlement(
  CartSettlementPlan plan, {
  required bool drawerSettingOn,
}) =>
    drawerSettingOn && plan.cashToCollect > 0;

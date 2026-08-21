import '../../../core/constants/app_constants.dart';
import '../../../domain/models/exchange_settlement.dart';
import '../../../domain/models/returnable_line.dart';
import 'pos_return_mode.dart';

/// وضعُ الاستبدال — شقُّ المرتجع، ووسمُ العيب لكلِّ سطر.
///
/// **يلفّ [PosReturnMode] ولا ينسخه.** حسابُ المرتجع (`refundTotal`) وسياجُ
/// الكمية (`setQty`) وقبولُ الصنف (`canAcceptProduct`) كلُّها مكتوبةٌ ومُختبَرةٌ
/// هناك. ونسخةٌ ثانيةٌ من حسابِ مالٍ هي العطبُ المتكرّرُ في هذه السلسلة: رقمٌ
/// يُعرَض على الكاشير وآخرُ يُنفَّذ على الدرج، وقد مرّ ذلك على سبع مراجعاتٍ
/// لأن طرفَيه كانا في ملفَّين.
///
/// **وسلّةُ البديل ليست هنا:** هي سلّةُ البيع العاديّةُ نفسُها. فوضعُ
/// الاستبدال — بخلاف وضع المرتجع — **لا يمنع** إضافةَ الأصناف إلى السلّة؛
/// الإضافةُ هي البديلُ نفسُه. ولذلك لا يُمرَّر هذا الوضعُ إلى
/// `blocksCartMutation`.
///
/// **ووسمُ العيب لكلِّ سطرٍ لا للنداء كلِّه** (قرارُ المالك (ب)):
/// `processSalesReturn` يقبل `isDamaged` للنداء، فيقسم `processExchange`
/// الشقَّ إلى مجموعتَين بحسب هذه الوسوم. وسطرٌ موسومٌ بكميةٍ صفرٍ **لا يُرسَل**
/// — وإلّا أُتلف صنفٌ لم يُرتجَع أصلاً.
class PosExchangeMode {
  /// شقُّ المرتجع — مصدرُ كلِّ حسابٍ وكلِّ سياج.
  final PosReturnMode returnLeg;

  final Set<int> _damagedItemIds;

  PosExchangeMode({
    required this.returnLeg,
    Set<int>? damagedItemIds,
  }) : _damagedItemIds = damagedItemIds ?? <int>{};

  factory PosExchangeMode.fromLines({
    required int invoiceId,
    required List<ReturnableLine> lines,
    double? invoiceTotal,
    double invoiceDeliveryFee = 0,
  }) =>
      PosExchangeMode(
        returnLeg: PosReturnMode.fromLines(
          invoiceId: invoiceId,
          lines: lines,
          invoiceTotal: invoiceTotal,
          invoiceDeliveryFee: invoiceDeliveryFee,
        ),
      );

  int get invoiceId => returnLeg.invoiceId;

  Map<int, ReturnableLine> get linesByItemId => returnLeg.linesByItemId;

  Map<int, double> get requestedQty => returnLeg.requestedQty;

  /// إجماليُّ الشقِّ المرتجَع — من `PosReturnMode` لا بجمعٍ محلّيّ.
  double get refundTotal => returnLeg.refundTotal;

  /// شرطُ الحفظ: استبدالٌ بلا مرتجَعٍ ليس استبدالاً.
  bool get hasReturnSelection => returnLeg.requestedQty.values.any((q) => q > 0);

  bool setQty(int itemId, double qty) => returnLeg.setQty(itemId, qty);

  void clearQty(int itemId) => returnLeg.clearQty(itemId);

  bool canAcceptProduct(int productId) => returnLeg.canAcceptProduct(productId);

  bool isDamaged(int itemId) => _damagedItemIds.contains(itemId);

  /// يضبط وسمَ العيب لسطرٍ قائم. وسطرٌ لا وجودَ له يُتجاهَل بلا رمي: الوسمُ
  /// يأتي من نقرةٍ على صفٍّ معروض، فمعرِّفٌ غريبٌ خطأُ نداءٍ لا إدخالُ مستخدم.
  void setDamaged(int itemId, bool damaged) {
    if (!returnLeg.linesByItemId.containsKey(itemId)) return;
    if (damaged) {
      _damagedItemIds.add(itemId);
    } else {
      _damagedItemIds.remove(itemId);
    }
  }

  /// الكمياتُ المؤثّرةُ فقط — ما يُمرَّر إلى `processExchange`.
  Map<int, double> get effectiveReturnQuantities => <int, double>{
        for (final e in returnLeg.requestedQty.entries)
          if (e.value > 0) e.key: e.value,
      };

  /// وسومُ العيب المؤثّرةُ فقط.
  ///
  /// **الفلترةُ بالكمية شرطٌ لا تجميل:** سطرٌ موسومٌ بكميةٍ صفرٍ لو مرّ لَوسم
  /// `processExchange` مجموعةَ «معيب» بصنفٍ لم يُرتجَع، فيُتلَف مخزونٌ سليم.
  Set<int> get effectiveDamagedItemIds => <int>{
        for (final e in returnLeg.requestedQty.entries)
          if (e.value > 0 && _damagedItemIds.contains(e.key)) e.key,
      };

  /// التسويةُ المعروضةُ قبل الحفظ — **من نفس الدالّة الخالصة** التي ينفّذها
  /// المستودع، فلا يفترق المعروضُ عن المنفَّذ.
  ///
  /// ⚠️ وهي تقديرٌ على قيمتَي المستندَين لا أثرُ الدرج المقيس: فاتورةٌ أصليّةٌ
  /// **غيرُ نقديّة** تُردّ إلى قناتها (بنكاً أو رصيدَ عميل) بينما شقُّ البيع
  /// يقبض نقداً كاملاً، فأثرُ الدرج الفعليُّ يخالف هذا الفرق. ولذلك تُعرَض
  /// بعد الحفظ أرقامُ `ExchangeResult` المقيسةُ داخل المعاملة لا هذه.
  ({ExchangeCashDirection direction, double amount}) previewSettlement({
    required double replacementTotal,
    int decimalPlaces = AppConstants.decimalPlaces,
  }) =>
      settleExchange(
        returnTotal: refundTotal,
        saleTotal: replacementTotal,
        decimalPlaces: decimalPlaces,
      );
}

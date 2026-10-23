# الخطةُ الثانية — الاستبدال

> **للعاملين الوكلاء:** مهارةٌ فرعيةٌ إلزامية: استعمل
> `superpowers:subagent-driven-development` (موصى به) أو
> `superpowers:executing-plans` لتنفيذ هذه الخطة مهمّةً مهمّة. الخطواتُ
> بصيغة صناديق التأشير (`- [ ]`).

**الهدف:** زرٌّ يُجري في عمليةٍ ذرّيةٍ واحدة: ارتجاعَ صنفٍ بسعر فاتورته الأصلية،
وبيعَ بديلٍ بسعره الحاليّ، وتسويةَ الفرق نقداً من درج الوردية.

**المعمار:** ثلاثُ طبقات. (١) حسابٌ خالصٌ للفرق يُقرّر اتجاهَ الحركة النقدية.
(٢) خدمةٌ تنفّذ المستندَين — مردودَ مبيعاتٍ وفاتورةَ بيع — داخل **معاملةِ قاعدةٍ
واحدة**، وتربطهما بمفتاح استبدالٍ مشترك. (٣) طرفُ مزامنةٍ واحدٌ يفكّه الخادمُ
إلى مستندَين في معاملةٍ واحدة، فلا تنفصلان طرفاً لطرف.

**التقنيات:** Flutter · Riverpod · Drift (SQLite) · shelf (الخادم) · flutter_test.

## القيودُ العامّة

مقيسةٌ في هذا المستودع لا مفترَضة. كلُّ مهمّةٍ محكومةٌ بها ضمناً:

- **`rm -rf build/native_assets` قبل كلّ `flutter test`** — وإلا انهار المشغّل
  بـ`errno 183` على `sqlite3.dll` وعلّق كلَّ ملفٍّ تالٍ ١٢ دقيقة.
- **ممنوع `dart format`** — الاستعادةُ بـ`git show HEAD:<path> > <path>` لا
  بـ`git checkout`.
- **الاختبارُ يُشاهَد أحمرَ أوّلاً** بتشغيلٍ فعليٍّ مسجَّلٍ حرفياً، **والطفرةُ
  دليلُ الحماية** حيث يحتمل اللبس.
- **حارسُ `presentation_db_import_guard`**: ملفُّ عرضٍ **جديد** لا يستورد
  `data/database`.
- **المسارُ الإلزاميّ للمرتجع: `ReturnsRepositoryImpl.processSalesReturn`** —
  **لا** `ProcessSalesReturnUseCase`، فـ`_validate` فيه بلا سقفِ كمية.
- **حدودُ `scripts/gate.sh` تُضبط في نفس كوميت آخر مهمّة.** الحالية:
  `unit 3442 · widget 674 · integration 710 · pg 45 · analyze 6 info`.
- البوابةُ في الخلفية (`nohup`) — ~٣٥ دقيقةً وسقفُ الأداة ١٠. و«٠ ناجح» في
  سويّةٍ كاملةٍ عرضٌ بيئيٌّ (‏`pub.dev`) لا نتيجةُ قياس.
- **لا يُربط أيُّ عملٍ بـUralCash** (قرارُ المالك)، و`D:\URAL-ERP` لا يُعدَّل.

### قرارُ المخطَّط — يُقاس قبل المهمّة ٣

مفتاحُ الاستبدال يحتاج موضعَ تخزين. **إن لزم عمودٌ جديدٌ فهو تغييرُ مخطَّط**
⇒ `build_runner` (~٤١ دقيقة، ٤٠ منها تحليلٌ صامتٌ بلا نموّ في الكاش — **لا
تقتله**)، وممنوع تعديلُ `database.g.dart` يدوياً. **افحص أوّلاً** هل يكفي حقلٌ
قائم (‏`referenceType`/`referenceId`/`notes` على المستندَين) قبل أن تقترح عموداً.

---

## بنيةُ الملفّات

| الملفّ | المسؤولية |
|---|---|
| `lib/domain/models/exchange_settlement.dart` **(جديد)** | حسابٌ خالص: الفرقُ واتجاهُه |
| `lib/data/repositories/exchange_repository_impl.dart` **(جديد)** | تنفيذُ المستندَين ذرّياً وربطُهما |
| `lib/services/server_proxy.dart` | `submitExchange` |
| `lib/services/interceptor/cwi_trading.dart` | تصفيفُ حمولة الاستبدال |
| `lib/services/api/api_handler.dart` + معالجُ المبيعات | `/api/sales/exchange` |
| `lib/presentation/pos_picpos/state/pos_exchange_mode.dart` **(جديد)** | حالةُ وضع الاستبدال |
| `lib/presentation/pos_picpos/screens/picpos_pos_operations.dart` | الزرُّ والسطحُ والحفظ |

---

## المهمّةُ ١: حاسبُ تسوية الاستبدال — دالّةٌ خالصة

**الملفّات:**
- إنشاء: `lib/domain/models/exchange_settlement.dart`
- اختبار: `test/unit/exchange_settlement_test.dart`

**الواجهات:**
- تُنتج: `enum ExchangeCashDirection { collect, refund, none }` و
  `({ExchangeCashDirection direction, double amount}) settleExchange({required double returnTotal, required double saleTotal, int decimalPlaces = 3})`

**لماذا خالصة:** اتجاهُ الحركة النقدية قرارٌ ماليٌّ يجب أن يُختبر في مللي ثانية،
ولأنّ **حالةَ التساوي يجب ألّا تُنشئ حركةً بصفر** — وهي الحالةُ التي تُنسى.

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/exchange_settlement.dart';

void main() {
  group('settleExchange', () {
    test('البديلُ أغلى ⇒ قبضُ الفرق', () {
      final r = settleExchange(returnTotal: 100, saleTotal: 130);
      expect(r.direction, ExchangeCashDirection.collect);
      expect(r.amount, 30);
    });

    test('البديلُ أرخص ⇒ صرفُ الفرق', () {
      final r = settleExchange(returnTotal: 130, saleTotal: 100);
      expect(r.direction, ExchangeCashDirection.refund);
      expect(r.amount, 30);
    });

    test('متساويان ⇒ لا حركةَ إطلاقاً', () {
      final r = settleExchange(returnTotal: 100, saleTotal: 100);
      expect(r.direction, ExchangeCashDirection.none);
      expect(r.amount, 0);
    });

    test('فرقٌ أصغرُ من دقّةِ العرض يُعامَل لا شيئاً', () {
      // ٠٫٠٠٠٤ تحت التقريب إلى ٣ خانات ⇒ حركةٌ بصفرٍ لا معنى لها،
      // وإنشاؤها يلوّث كشفَ الخزنة بصفوفٍ فارغة.
      final r = settleExchange(returnTotal: 100, saleTotal: 100.0004);
      expect(r.direction, ExchangeCashDirection.none);
    });

    test('المبلغُ موجبٌ دائماً — الاتجاهُ يحمل الإشارة', () {
      expect(settleExchange(returnTotal: 130, saleTotal: 100).amount, 30);
      expect(settleExchange(returnTotal: 100, saleTotal: 130).amount, 30);
    });

    test('يحترم دقّةَ الخانات الممرَّرة', () {
      final r = settleExchange(
        returnTotal: 10, saleTotal: 10.126, decimalPlaces: 2,
      );
      expect(r.direction, ExchangeCashDirection.collect);
      expect(r.amount, 0.13);
    });
  });
}
```

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/exchange_settlement_test.dart
```

المتوقَّع: فشلٌ بـ`Target of URI doesn't exist`.

- [ ] **خطوة ٣: اكتب التنفيذ**

```dart
/// اتّجاهُ الحركة النقدية في الاستبدال.
enum ExchangeCashDirection {
  /// البديلُ أغلى — العميلُ يدفع الفرق.
  collect,

  /// البديلُ أرخص — نردّ الفرق.
  refund,

  /// متساويان — **لا حركةَ إطلاقاً**، ولا صفٌّ بصفر.
  none,
}

/// يقرّر اتّجاهَ الفرق ومقدارَه.
///
/// خالصٌ عمداً: الاتّجاهُ قرارٌ ماليٌّ، وحالةُ التساوي هي التي تُنسى فيُكتب
/// صفُّ خزنةٍ بصفرٍ يلوّث الكشف. والمبلغُ **موجبٌ دائماً** — الإشارةُ في
/// الاتّجاه لا في الرقم، كي لا يتسرّب سالبٌ إلى `createSafeTransaction`.
({ExchangeCashDirection direction, double amount}) settleExchange({
  required double returnTotal,
  required double saleTotal,
  int decimalPlaces = 3,
}) {
  final factor = _pow10(decimalPlaces);
  final diff = ((saleTotal - returnTotal) * factor).roundToDouble() / factor;

  if (diff == 0) {
    return (direction: ExchangeCashDirection.none, amount: 0);
  }
  if (diff > 0) {
    return (direction: ExchangeCashDirection.collect, amount: diff);
  }
  return (direction: ExchangeCashDirection.refund, amount: -diff);
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
```

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح**

```bash
rm -rf build/native_assets && flutter test test/unit/exchange_settlement_test.dart
```

المتوقَّع: `All tests passed!` (‏٦ حالات).

- [ ] **خطوة ٥: أثبِت الحمايةَ بطفرة**

استبدل مؤقّتاً `if (diff == 0)` بـ`if (false)`، شغّل، وتأكّد أن حالتَي «متساويان»
و«فرقٌ تحت الدقّة» **تسقطان**. ثم استعِد الملفَّ وتأكّد أن `git status` نظيف.

- [ ] **خطوة ٦: أودِع**

```bash
git add lib/domain/models/exchange_settlement.dart test/unit/exchange_settlement_test.dart
git commit -m "feat(exchange): حاسبُ تسوية الاستبدال دالّةً خالصةً مختبَرة"
```

---

## المهمّةُ ٢: ربطُ الحاسب بأساس الاسترداد الموحَّد

**الملفّات:**
- تعديل: `lib/domain/models/exchange_settlement.dart`
- اختبار: `test/unit/exchange_settlement_test.dart`

**الواجهات:**
- يستهلك: `calculateReturnRefundTotal({required Iterable<ReturnRefundLineInput> lines, required double invoiceTotal, required double invoiceDeliveryFee, required Map<int,double> returnQuantities, int decimalPlaces = 3})` من `lib/domain/models/return_refund_calculator.dart`، و`ReturnRefundLineInput = ({int id, double quantity, double lineTotal})`.

**🔴 لماذا هذه مهمّةٌ مستقلّة:** عطبٌ **مقيسٌ** في الخطة الأولى كان أن الرقمَ
المعروضَ للكاشير حُسب `Σ qty × unitPrice` (‏قبل الضريبة والخصم) بينما المصروفُ
يُبنى على `item.total` (‏شاملَ الضريبة صافيَ الخصم) ⇒ بضريبة ١٤٪ يُعرض ١٠٠
ويخرج ١١٤. **فشقُّ الارتجاع في الاستبدال يجب أن يستعمل الحاسبَ الموحَّد نفسَه،
ولا يُعيد اشتقاقَ الرقم.**

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
test('شقُّ الارتجاع يستعمل أساسَ الاسترداد الموحَّد لا سعرَ الوحدة', () {
  // سطرٌ بيع: كمية ١، سعرُ وحدةٍ ١٠٠، وإجماليُّ السطر ١١٤ (ضريبة ١٤٪).
  const lines = [(id: 1, quantity: 1.0, lineTotal: 114.0)];
  final returnTotal = calculateReturnRefundTotal(
    lines: lines,
    invoiceTotal: 114,
    invoiceDeliveryFee: 0,
    returnQuantities: {1: 1.0},
  );
  // لو أُخذ سعرُ الوحدة لكان ١٠٠ — وهو بعينه العطبُ المقيس.
  expect(returnTotal, 114);

  final r = settleExchange(returnTotal: returnTotal, saleTotal: 114);
  expect(r.direction, ExchangeCashDirection.none,
      reason: 'استبدالٌ بصنفٍ بنفس القيمة يجب ألّا يُنشئ حركةً نقدية');
});
```

وأضِف الاستيرادَ `import 'package:picpos_erp/domain/models/return_refund_calculator.dart';`.

- [ ] **خطوة ٢: شغّله**

```bash
rm -rf build/native_assets && flutter test test/unit/exchange_settlement_test.dart
```

إن نجح فوراً فالربطُ سليمٌ سلفاً — وثّق ذلك وامضِ. وإن فشل فأصلِح الاستدعاء.

- [ ] **خطوة ٣: أودِع**

```bash
git add test/unit/exchange_settlement_test.dart lib/domain/models/exchange_settlement.dart
git commit -m "test(exchange): شقُّ الارتجاع مربوطٌ بأساس الاسترداد الموحَّد"
```

---

## المهمّةُ ٣: مستودعُ الاستبدال — الذرّيةُ والربط

**الملفّات:**
- إنشاء: `lib/data/repositories/exchange_repository_impl.dart`
- اختبار: `test/unit/exchange_atomicity_test.dart`

**الواجهات:**
- يستهلك: `ReturnsRepositoryImpl.processSalesReturn({required SalesInvoiceData invoice, required Map<int,double> returnQuantities, required Map<int,ProductEntity> productCache, String? reason, required int userId, required String userName, bool isFullReturn, bool isDamaged})` · مسارَ إنشاء فاتورة البيع في `sales_transaction_orchestrator.dart` · `TreasuryDao.resolveRefundSafe({required int userId})` · `settleExchange` (المهمّة ١).
- يُنتج: `Future<ExchangeResult> processExchange({...})` — وقّعه أنت بعد قراءة المستدعِيَين، وسجّل التوقيعَ في تقريرك كي تبني عليه المهمّةُ ٥.

**⚠️ اقرأ أوّلاً:** `returns_repository_impl.dart:276` و
`sales_transaction_orchestrator.dart:144` — كلاهما يفتح `_db.transaction(() async {…})`.
**معاملةٌ داخل معاملةٍ في drift ليست معاملةً مستقلّة**؛ افحص كيف تتداخل قبل أن
تلفّهما، وإن تعذّر اللفُّ فاكتب ذلك بحالة BLOCKED ولا تجتهد بنصف حلّ.

**⚠️ ومفتاحُ الربط:** افحص هل يكفي `referenceType`/`referenceId`/`notes` على
المستندَين. **لا تقترح عموداً جديداً إلا بعد إثبات أن القائمَ لا يكفي** — العمودُ
يعني `build_runner` بأربعين دقيقةَ تحليلٍ صامت.

- [ ] **خطوة ١: اكتب اختبارَ الذرّية الفاشل**

```dart
test('فشلُ شقّ البيع يُلغي شقَّ الارتجاع بالكامل', () async {
  // ابنِ فاتورةَ بيعٍ أصليةً وصنفاً بديلاً **نافدَ المخزون**.
  // ثم نفّذ استبدالاً، وتوقّع الرفض.
  //
  // والتأكيدُ الحاسم — ثلاثةٌ معاً، ولا يكفي واحد:
  //   • لا صفَّ مردودٍ جديد.
  //   • لا حركةَ مخزونٍ من نوع 'return'.
  //   • رصيدُ درج الوردية لم يتغيّر.
  // إذ يمكن أن يُلغى المستندُ ويبقى أثرُه في الخزنة، وهو أسوأُ من الفشل.
});
```

اقرأ `test/unit/return_refund_hits_shift_drawer_test.dart` لتتبع نمطَ التجهيزة
(‏`AppDatabase.forTesting()` وبناءَ الفرعِ والخزنةِ والوردية) — **ولا تنسخ
أسماءَ الأعمدة من هنا، أثبِتها من `lib/data/database/tables/`.**

- [ ] **خطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/exchange_atomicity_test.dart
```

- [ ] **خطوة ٣: اكتب المستودع**

المتطلَّباتُ الملزِمة:
1. **مستندان لا مستندٌ واحد**: مردودُ مبيعاتٍ **و** فاتورةُ بيع، لكلٍّ رقمُه.
2. **الفرقُ لا يمرّ خصماً أبداً** — حركتا خزنةٍ مستقلّتان بحسب `settleExchange`،
   و`none` **لا تُنشئ صفّاً**.
3. **الصرفُ والقبضُ من درج الوردية** عبر `resolveRefundSafe(userId:)`.
4. **رفضٌ مبكّرٌ** إن كان البديلُ غيرَ متوفّرٍ — **قبل أيّ كتابة** (قرارُ المالك:
   يمنع لا يحذّر).
5. **الضريبةُ**: الارتجاعُ يُعكَس بنسبة الفاتورة الأصلية والبيعُ يحمل نسبةَ
   اليوم؛ اختلافُهما فرقٌ حقيقيٌّ **يظهر ولا يُبتلع**.
6. **مفتاحُ استبدالٍ مشتركٌ** يجعل كلَّ مستندٍ يشير إلى الآخر.

- [ ] **خطوة ٤: شغّل وتأكّد من النجاح، ثم السويّتَين**

```bash
rm -rf build/native_assets && flutter test test/unit test/integration
```

`integration` = **710**. أيُّ نقصٍ انحدارٌ يوجب التوقّف.

- [ ] **خطوة ٥: أودِع**

```bash
git add lib/data/repositories/exchange_repository_impl.dart test/unit/exchange_atomicity_test.dart
git commit -m "feat(exchange): مستندان في معاملةٍ واحدة — تنجح كاملةً أو تُلغى"
```

---

## المهمّةُ ٤: المزامنةُ بحمولةٍ واحدة

**الملفّات:**
- تعديل: `lib/services/server_proxy.dart` · `lib/services/interceptor/cwi_trading.dart` · `lib/services/api/api_handler.dart` ومعالجُ المبيعات
- اختبار: `test/unit/exchange_sync_payload_test.dart`

**الواجهات:**
- النموذجُ الذي تتبعه: `submitSalesReturn` في `server_proxy.dart:382` ⇒
  `post('/api/sales/return', returnData, idempotencyKey: idempotencyKey)`،
  ومسارُه في `api_handler.dart:133`، وتصفيفُه في `cwi_trading.dart:102`
  (‏`_tryOrQueue(tableName: 'sales_returns', operation: 'insert', …)`).

**قرارُ المالك ٥:** حمولةٌ **واحدة** يفكّها الخادمُ إلى مستندَين في معاملةٍ
واحدة — لا حمولتان مرتبطتان. فلا نافذةَ انفصالٍ طرفاً لطرف.

- [ ] **خطوة ١: اكتب الاختبارَ الفاشل**

```dart
test('حمولةُ الاستبدال واحدةٌ وتحمل الشقَّين ومفتاحَ الربط', () {
  // ابنِ الحمولةَ وتأكّد أنها تحوي شقَّي الارتجاع والبيع
  // ومفتاحَ الاستبدال المشترك، وأنها **حمولةٌ واحدة** لا اثنتان.
});

test('إرسالُ نفسِ الحمولة مرّتَين لا يُنشئ مستندَين', () {
  // مفتاحُ idempotency هو الضامن — تحقّق أنه يُمرَّر.
});
```

- [ ] **خطوة ٢: شغّله** بـ`rm -rf build/native_assets && flutter test test/unit/exchange_sync_payload_test.dart`

- [ ] **خطوة ٣: أضِف الطرفَ الثلاثيّ**
`submitExchange` في الوكيل · تصفيفُه في المعترِض بجدولٍ منطقيٍّ واحد ·
ومسارُ `/api/sales/exchange` في الخادم يفكّه **داخل معاملةٍ واحدة**.

- [ ] **خطوة ٤: شغّل السويّات** — و`pg` = **45** إن مسّت التغييراتُ الخادم.

- [ ] **خطوة ٥: أودِع**

```bash
git add -A
git commit -m "feat(exchange): مزامنةٌ بحمولةٍ واحدةٍ يفكّها الخادمُ ذرّياً"
```

---

## المهمّةُ ٥: الزرُّ والسطحُ والحفظ

**الملفّات:**
- إنشاء: `lib/presentation/pos_picpos/state/pos_exchange_mode.dart`
- تعديل: `picpos_pos_operations.dart` · `picpos_payment_panel.dart`
- اختبار: `test/widget/picpos_exchange_mode_test.dart`

**الواجهات:**
- يستهلك: `processExchange` (المهمّة ٣) · `settleExchange` (المهمّة ١) ·
  `PosReturnMode` و`ReturnableLine` القائمَين · `PicPosReturnModeBanner` نموذجاً.

**⚠️ ودروسٌ مقيسةٌ من الخطة الأولى — لا تكرّرها:**
1. **السلةُ لا تُملأ من الزرّ وحدَه**: في الخطة الأولى بقي `canAcceptProduct`
   و`unitPriceOf` و`clearQty` **كوداً ميتاً** لأن السطحَ لم يُبنَ. ابنِ سطحَ
   الاختيار **في نفس المهمّة**.
2. **`isEmpty` في لوحة الدفع يُحسب من سلّة البيع** — فزرّا «دفع/حفظ» يُعطَّلان
   في أيّ وضعٍ لا يملأ السلة. عالِجه كما عولج لوضع المرتجع.
3. **احرس كلَّ مداخل تعديل السلة** — وهي **ثلاثة**: `_handleProductTap` و
   `_searchBarcode` و`_showHeldOrders`. والأخيرُ **يحذف الطلبَ المعلَّق من
   القاعدة** فإهمالُه يُبيده نهائياً. عدّها بنفسك ولا تثق بهذا الرقم.
4. **الرقمُ المعروضُ والمنفَّذُ من دالّةٍ واحدة** — لا تُعِد اشتقاقَ الفرق.

- [ ] **خطوة ١: اكتب اختبارَ الحالة الفاشل**

```dart
test('وضعُ الاستبدال يعرض الأرقامَ الثلاثة', () {
  // إجماليُّ المرتجع · إجماليُّ البيع · الفرقُ واتّجاهُه —
  // ثلاثتُها من `settleExchange` لا بحسابٍ محلّيّ.
});

test('الخروجُ من الوضع يُفرّغ الشقَّين معاً', () {
  // بقاءُ أحدهما يعني استبدالاً نصفَ مبنيٍّ يُحفظ بالخطأ.
});
```

- [ ] **خطوة ٢: شغّله** بـ`rm -rf build/native_assets && flutter test test/widget/picpos_exchange_mode_test.dart`

- [ ] **خطوة ٣: اكتب الحالةَ والسطحَ والزرَّ ومسارَ الحفظ**

- [ ] **خطوة ٤: شغّل البوابةَ كاملةً في الخلفية**

```bash
nohup bash scripts/gate.sh --pg > /tmp/gate.log 2>&1 &
```

المتوقَّع: `✓ البوابة كلها خضراء` وخروجٌ صفريٌّ طبيعيٌّ لا مقتول.

- [ ] **خطوة ٥: اضبط الحدودَ على المقيس وأودِع** — وسوِّ الزيادةَ بالضبط في
      رسالة الكوميت.

---

## المراجعةُ الذاتية للخطة

- **تغطيةُ المواصفة §٦:** مستندان ⇒ م٣ · الفرقُ لا خصماً ⇒ م٣ · الذرّية ⇒ م٣ ·
  الضريبة ⇒ م٣ · الربطُ والمزامنةُ بحمولةٍ واحدة ⇒ م٤ · السطحُ والأرقامُ
  الثلاثة ⇒ م٥ · رفضُ البديل النافد ⇒ م٣.
- **بلا عناصرَ نائبة:** المهامُّ ١ و٢ بكودها كاملاً. والمهامُّ ٣-٥ تتطلّب قراءةَ
  مسارَين قائمَين قبل التوقيع، **وهذا مُعلَّمٌ صراحةً بأمر القياس** لا متروكاً —
  لأن رقمَ سطرٍ في مستندٍ يبطُل، وقد بطَل في هذه الجلسة أكثرَ من مرّة.
- **اتّساقُ الأنواع:** `settleExchange` بنفس التوقيع في ١ و٢ و٥ ·
  `ExchangeCashDirection` بنفس القيم · `processExchange` يُوقَّع في ٣ ويُستهلك
  في ٥ بتوقيعه المسجَّل.

**خارجَ هذه الخطة:** البنودُ الأربعةُ الجديدة (زرُّ العودة السريعة · الإغلاقُ
بسلّةٍ عامرة · أدواتُ المطوّر · الإضافةُ السريعة) — دفعةٌ منفصلة.

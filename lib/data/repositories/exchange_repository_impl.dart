import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/uuid_v7.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/models/exchange_settlement.dart';
import '../../domain/models/return_refund_calculator.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../database/database.dart';
import 'returns_repository_impl.dart';
import 'sales_transaction_orchestrator.dart';

/// نتيجةُ استبدالٍ ناجح — كلُّ ما تحتاجه الشاشةُ للطباعة والعرض بلا أن
/// تُعيد اشتقاقَ رقمٍ واحد.
class ExchangeResult {
  /// المفتاحُ المشترك المزروعُ في **المستندَين** (‏`sales_invoices.notes`)،
  /// وهو ما يجعل كلًّا يشير إلى الآخر.
  final String exchangeKey;

  /// مُعرِّفُ مستند المردود. المسارُ المعياريُّ للمرتجع في هذا المستودع
  /// (‏`ReturnsRepositoryImpl.processSalesReturn` — الشكلُ «أ») لا ينشئ صفَّ
  /// فاتورةٍ مستقلًّا للمردود: هويّتُه هي **الفاتورةُ الأصلية** بحالةٍ مقلوبة
  /// (`returned` / `partial_return`) وصفوفُ الخزنة/المخزون المرتبطةُ بها عبر
  /// `reference_id`. فهذا الرقمُ هو نفسُه ما تحمله
  /// `SalesReturnHistoryEntry.originalInvoiceId`.
  final int returnDocumentId;

  /// رقمُ سند المردود (`SRET-N`) مقروءاً من صفّ الخزنة الذي كتبه شقُّ
  /// الارتجاع — نفسُ مصدر `getSalesReturnPrintData`. `null` فقط حين تعذّر
  /// حلُّ خزنةٍ أصلاً.
  final String? returnVoucherNumber;

  final int saleInvoiceId;
  final String saleInvoiceNumber;

  /// **قيمةُ مستند** المردود من الأساس الموحَّد `calculateReturnRefundTotal`.
  /// للعرض بوصفه «إجماليَّ المرتجع» — وليس بالضرورة ما خرج من الدرج.
  final double returnTotal;

  /// **قيمةُ مستند** البيع كما حُفظ فعلاً (‏مقروءٌ من الصفّ، لا محسوبٌ هنا).
  final double saleTotal;

  /// ما خرج من **درج الوردية** فعلاً في شقّ الارتجاع — مقيسٌ من رصيد الدرج
  /// لا مشتقٌّ من قيمة المستند. يقلّ عن [returnTotal] حين يردّ المرتجعُ إلى
  /// خزنةٍ بنكيةٍ (فاتورةٌ أصليةٌ بالبطاقة/التحويل) أو يُسوّى على رصيد عميلٍ
  /// مدين (فاتورةٌ آجلة).
  final double cashRefunded;

  /// ما دخل **درج الوردية** فعلاً في شقّ البيع — مقيسٌ من رصيد الدرج.
  final double cashCollected;

  /// اتّجاهُ ما يفعله الكاشيرُ على الدرج ومقدارُه، من `settleExchange`
  /// مُغذّاةً بـ[cashRefunded] و[cashCollected] — **لا** بقيمتَي المستندَين.
  ///
  /// فما يُعرض هو ما يخرج من الدرج ويدخله بالضبط: `difference ==
  /// (رصيدُ الدرج بعد) − (رصيدُ الدرج قبل)` بالقيمة المطلقة، والاتّجاهُ
  /// إشارتُها. اشتقاقُه من إجماليَّي المستندَين كان يقول «اقبض ٣٠» بينما
  /// العميلُ يدفع ١٣٠ على فاتورةٍ أصليةٍ بنكية.
  final ExchangeCashDirection direction;
  final double difference;

  /// درجُ الوردية الذي وقعت عليه حركتا الشقَّين.
  final int drawerSafeId;

  const ExchangeResult({
    required this.exchangeKey,
    required this.returnDocumentId,
    required this.returnVoucherNumber,
    required this.saleInvoiceId,
    required this.saleInvoiceNumber,
    required this.returnTotal,
    required this.saleTotal,
    required this.cashRefunded,
    required this.cashCollected,
    required this.direction,
    required this.difference,
    required this.drawerSafeId,
  });
}

/// يُرمى حين يكون البديلُ غيرَ متوفّرٍ في المخزن — **قبل أيّ كتابة**.
/// قرارُ المالك: يمنع لا يحذّر.
class ExchangeStockUnavailableException implements Exception {
  final String message;
  const ExchangeStockUnavailableException(this.message);
  @override
  String toString() => message;
}

/// يُرمى حين يفشل أحدُ الشقَّين — رسالةٌ عربيةٌ للكاشير، والمعاملةُ الخارجيةُ
/// تُلغي الشقَّين معاً.
class ExchangeFailedException implements Exception {
  final String message;
  const ExchangeFailedException(this.message);
  @override
  String toString() => message;
}

/// الاستبدال: **مستندان** — مردودُ مبيعاتٍ وفاتورةُ بيع — في **معاملةِ قاعدةٍ
/// واحدة**.
///
/// ## لماذا اللفُّ ذرّيٌّ فعلاً (مقيسٌ لا مفترَض)
///
/// المسارانِ المستهلَكان يفتح كلٌّ منهما `_db.transaction(...)` بنفسه
/// (‏`returns_repository_impl.dart` و`sales_mutations_dao.dart`). ومعاملةٌ
/// داخل معاملةٍ في drift **ليست معاملةً مستقلّة**: على منفّذٍ يدعم التداخل —
/// و`NativeDatabase` يدعمه، والاختبارات تفتح `NativeDatabase.memory` — تُنفَّذ
/// الداخليةُ كـ`SAVEPOINT` تحت الخارجية، ولا يُكتب شيءٌ نهائياً إلا بإتمام
/// **الخارجية**. قياسٌ فعليّ (2026-08-16، خمسةُ مسابير على
/// `AppDatabase.forTesting()`):
///
///   * `transaction(..., requireNew: true)` داخل معاملةٍ **لا يرمي** ⇒ التداخلُ
///     مدعومٌ فعلاً (لا إعادةَ استعمالٍ صامتة للمعاملة الخارجية).
///   * معاملةٌ داخليةٌ **نجحت** ثم انفجرت الخارجيةُ بعدها ⇒ صفُّها اختفى
///     (`rowsAfterOuterRollback=0`).
///   * `adjustSafeBalance` داخل الداخلية ⇒ الرصيدُ عاد ٥٠٠ كما كان.
///
/// والشرطُ الوحيدُ لبقاء هذا صحيحاً: **ألّا يبتلع أحدٌ الاستثناءَ بين
/// الشقَّين**. المسبارُ الرابعُ قاسَ الوجهَ الآخر بالضبط: خارجيةٌ تلتقط
/// استثناءَ الداخلية ⇒ الداخليةُ وحدَها تُلغى **والخارجيةُ تُثبَّت**. لذلك
/// `completeSalesTransaction` — التي تحوّل كلَّ خطأٍ إلى `SaleResult.failure`
/// بدل أن ترميه — تُفحَص نتيجتُها هنا و**يُعاد الرميُ** صراحةً.
///
/// ## لماذا لا عمودَ جديد لمفتاح الاستبدال
///
/// المستندان كلاهما صفٌّ في `sales_invoices` (‏مستندُ المردود في الشكل «أ» هو
/// الفاتورةُ الأصليةُ بحالةٍ مقلوبة)، ولها `notes` نصّيةٌ قائمة. وللمستودع
/// سابقةٌ محسومةٌ لربط مستندٍ بمستند في نفس الحقل: `localReturnLinkNote`
/// (`sales_dao.dart`) يكتب `'Return for invoice #12|gid:<uuid>'` ويقرأها
/// `getSalesReturnHistoryEntries`. فنُلحق لاحقةً بنفس القواعد
/// (`|exch:<key>|exsale:<id>` و`|exch:<key>|exret:<id>`) — لا تصطدم بأيٍّ من
/// المحلِّلَين القائمَين (`_originalGidFromNote` يبحث عن `|gid:` و
/// `_originalIdFromNote` يشترط بدايةَ `'Return for invoice #'`). فلا عمودَ
/// جديدٌ ⇒ لا تغييرَ مخطَّطٍ ⇒ لا `build_runner`.
///
/// ## الخزنة
///
/// شقُّ الارتجاع يصرف قيمتَه **الكاملة** من درج الوردية (‏`processSalesReturn`
/// عبر `resolveRefundSafe`)، وشقُّ البيع يقبض قيمتَه **الكاملة** في **نفس**
/// الدرج (‏`cashSafeId`). فحركتان مستقلّتان، لكلِّ مستندٍ حركتُه بقيمته
/// كاملةً — **ولا خصمَ يبتلع قيمةَ المرتجع** (خصمٌ كهذا يكذب على تقرير
/// المبيعات ويُظهر تنزيلاً لم يحدث). وصافي الدرج = ما يقوله `settleExchange`
/// بالضبط: قبضُ الفرق، أو صرفُه، أو **صفرٌ بلا أيّ صفٍّ بصفر** عند التساوي —
/// وهذا المستودعُ لا يكتب أيَّ صفِّ تسويةٍ ثالثٍ إطلاقاً.
///
/// ## الرقمُ المعروضُ هو الرقمُ المنفَّذ — من مصدرٍ واحد
///
/// شقُّ الارتجاع **لا يصرف نقداً دائماً**: فاتورةٌ أصليةٌ بالبطاقة/التحويل
/// يردّها `processSalesReturn` إلى الخزنة **البنكية**، وفاتورةٌ آجلةٌ على
/// عميلٍ مدين يسوّي جزءَها على **رصيد العميل** (`arRefund`). وشقُّ البيع يقبض
/// `saleTotal` **كاملاً نقداً** على كلّ حال. فاشتقاقُ الفرق من إجماليَّي
/// المستندَين يكذب على الكاشير: الشاشةُ تقول «اقبض ٣٠» والعميلُ يدفع ١٣٠
/// والدرجُ يزيد ١٠٠ عند الإقفال.
///
/// فـ[ExchangeResult.direction] و[ExchangeResult.difference] يُشتقّان من
/// **الشقَّين النقديَّين فعلاً**: رصيدُ الدرج يُقاس ثلاثَ مرّاتٍ داخل
/// المعاملة (قبل · بعد الارتجاع · بعد البيع)، فتخرج `cashRefunded` و
/// `cashCollected` مقيستَين لا مقدَّرتَين، وتُغذَّى بهما `settleExchange`
/// نفسُها — فيبقى الرقمُ المعروضُ والمنفَّذُ من دالّةٍ واحدة. وهذا هو الدرسُ
/// المقيسُ من الخطة الأولى بعينه (‏عُرض ١٠٠ وصُرف ١١٤ لأن المصدرَين اثنان).
///
/// وقيمتا المستندَين تبقيان في [ExchangeResult.returnTotal] و
/// [ExchangeResult.saleTotal] للعرض — فالفرقُ بين قيمة المستند وأثر الدرج
/// **يظهر ولا يُبتلع**.
class ExchangeRepositoryImpl {
  final AppDatabase _db;
  final ReturnsRepositoryImpl _returns;
  final SalesTransactionOrchestrator _sales;

  ExchangeRepositoryImpl(this._db, this._returns, this._sales);

  static final _totals = CalculateInvoiceTotalsUseCase();

  /// ينفّذ استبدالاً كاملاً.
  ///
  /// [originalInvoice] الفاتورةُ الأصليةُ المختارةُ من مُحدِّد الفاتورة.
  /// [returnQuantities] بمفاتيح `sales_invoice_items.id` — نفسُ مفاتيح
  /// `processSalesReturn` بالضبط.
  /// [returnProductCache] بمفاتيح `products.id` للأصناف المرتجَعة.
  /// [replacementItems] سلّةُ البديل بأسعار اليوم.
  /// [damagedItemIds] وسمُ «معيب» **لكلّ سطرٍ على حدة** بمفاتيح
  /// `sales_invoice_items.id` (نفسُ فضاء مفاتيح [returnQuantities]) — قد
  /// يُرجع العميلُ صنفَين أحدُهما معيبٌ والآخرُ سليم. السطرُ الموسومُ:
  /// (أ) **لا يُحتسب** ضمن المتاح عند فحص البديل، و(ب) يمرّ بـ`isDamaged`
  /// إلى `processSalesReturn` فيُتلَف ولا يعود للرفّ.
  /// [customerId] عميلُ فاتورة البيع — يمرّره المنادي صراحةً (‏لا يُورَّث من
  /// الفاتورة الأصلية تلقائياً كي لا يُنسَب بيعٌ نقديٌّ لعميلٍ بغير قصد).
  Future<ExchangeResult> processExchange({
    required SalesInvoiceData originalInvoice,
    required Map<int, double> returnQuantities,
    required Map<int, ProductEntity> returnProductCache,
    required List<CartItemEntity> replacementItems,
    required int warehouseId,
    required int userId,
    required String userName,
    Set<int> damagedItemIds = const <int>{},
    int? customerId,
    double taxPercent = SaleRequest.kDefaultTaxPercent,
    bool taxEnabled = true,
    double discountPercent = 0,
    int? costCenterId,
    int? branchId,
    String? reason,
    String? notes,
  }) async {
    // ── ٠. ضوابطُ المدخلات ────────────────────────────────────────────────
    if (replacementItems.isEmpty) {
      throw const ExchangeFailedException(
        'لا يمكن حفظ استبدالٍ بلا صنفٍ بديل — اختر البديلَ أولاً.',
      );
    }
    final requestedReturn =
        returnQuantities.values.where((q) => q > 0).fold<double>(0, (a, b) => a + b);
    if (requestedReturn <= 0) {
      throw const ExchangeFailedException(
        'لا يمكن حفظ استبدالٍ بلا كميةٍ مرتجَعة — اضبط كمياتِ المرتجع أولاً.',
      );
    }

    final originalItems = await _db.getSalesInvoiceItems(originalInvoice.id);

    // ── ١. رفضُ البديل غيرِ المتوفّر **قبل أيّ كتابة** ────────────────────
    // قرارُ المالك: يمنع لا يحذّر. ولا يُترك الأمرُ لحارس المخزون السالب
    // داخل `adjustStock`: ذاك يمرّ حين يكون `enable_negative_sales` مفعَّلاً
    // أو `allowNegativeSale` على الصنف — والاستبدالُ يشترط وجودَ البديل
    // فعلياً على الرفّ بصرف النظر عن تلك السياسة.
    //
    // قرارُ المالك 2026-08-17 (الخيار ب): **الكميةُ المرتجَعةُ في هذا
    // الاستبدال نفسِه تُحتسب ضمن المتاح** — إلا إن وُسمت معيبة. وهذا ليس
    // تساهلاً بل مطابقةٌ لترتيب التنفيذ الفعليّ: شقُّ الارتجاع يُعيد
    // التخزين **قبل** أن يخصم شقُّ البيع، داخل نفس المعاملة. وبدونه كان
    // تبديلُ وحدةٍ بأخرى **مطابقة** — أشيعُ حالات الاستبدال — يفشل بـ«غيرُ
    // متوفّر» كلَّما كان رصيدُ الرفّ صفراً، رغم أن المرتجَعَ نفسَه يوفّره.
    await _rejectIfReplacementUnavailable(
      items: replacementItems,
      warehouseId: warehouseId,
      returnCredit: _returnCreditByProduct(
        originalItems: originalItems,
        returnQuantities: returnQuantities,
        damagedItemIds: damagedItemIds,
        originalWarehouseId: originalInvoice.warehouseId,
        saleWarehouseId: warehouseId,
      ),
    );

    // ── ٢. درجُ الوردية ───────────────────────────────────────────────────
    // الرفضُ هنا **قبل أيّ كتابة** أوضحُ من انفجارٍ عميقٍ في شقّ البيع
    // (`_recordSalesReceipt` ترمي حين لا خزنةَ نقديةً صالحة).
    final drawer = await _db.resolveRefundSafe(userId: userId);
    if (drawer == null) {
      throw const ExchangeFailedException(
        'لا توجد خزنةٌ نقديةٌ صالحةٌ لدرج الوردية — اضبط الخزائن من الإعدادات '
        '← الخزينة قبل الاستبدال.',
      );
    }

    // ── ٣. أساسُ المرتجع الموحَّد — لا اشتقاقَ محلّيّ ─────────────────────
    final returnTotal = calculateReturnRefundTotal(
      lines: [
        for (final i in originalItems)
          (id: i.id, quantity: i.quantity, lineTotal: i.total),
      ],
      invoiceTotal: originalInvoice.total,
      invoiceDeliveryFee: originalInvoice.deliveryFee,
      returnQuantities: returnQuantities,
      decimalPlaces: AppConstants.decimalPlaces,
    );

    // مرتجعٌ كاملٌ حين لا يبقى في أيّ سطرٍ كميةٌ غيرُ مرتجَعة.
    final isFullReturn = originalItems.isNotEmpty &&
        originalItems.every((i) =>
            (returnQuantities[i.id] ?? 0) >= i.quantity - 0.001);

    // مبلغُ الدفع المتوقَّع لفاتورة البيع — بنفس صيغة المسار الإنتاجيّ
    // (`CalculateInvoiceTotalsUseCase` هي الصيغةُ الخالصةُ التي يعكسها
    // مرورا `completeSalesTransaction`). يُستعمل مدخلاً فقط؛ الإجماليُّ
    // **المعتمَد** يُقرأ من الصفّ المحفوظ أدناه.
    final expectedSaleTotal = _totals
        .execute(
          items: replacementItems,
          invoiceDiscountPercent: discountPercent,
          taxPercent: taxPercent,
          taxEnabled: taxEnabled,
        )
        .total;

    final exchangeKey = UuidV7.generate();

    // شقُّ الارتجاع يُقسَم بحسب الوسم: `processSalesReturn` يقبل `isDamaged`
    // **للنداء كلِّه** لا للسطر، والوسمُ مطلوبٌ لكلّ سطر. فالنداءُ يُقسَم إلى
    // مجموعتَين متباينتَين داخل نفس المعاملة.
    //
    // والانقسامُ آمنٌ من التحقّق المتقاطع (مقيس): سياجُ الكمية في
    // `processSalesReturn` يقرأ `getAlreadyReturnedQty` وهي تعدّ
    // `stock_movements` بـ`reference_type = 'sales_invoice'` فقط، بينما هذا
    // المسارُ يكتب حركاتِه بـ`'sales_return'` — فلا يرى النداءُ الثاني كمياتِ
    // الأوّل ولا يرفضها خطأً.
    final soundQuantities = <int, double>{
      for (final e in returnQuantities.entries)
        if (e.value > 0 && !damagedItemIds.contains(e.key)) e.key: e.value,
    };
    final damagedQuantities = <int, double>{
      for (final e in returnQuantities.entries)
        if (e.value > 0 && damagedItemIds.contains(e.key)) e.key: e.value,
    };

    // ── ٤. المستندان في معاملةٍ واحدة ─────────────────────────────────────
    return _db.transaction(() async {
      // رصيدُ الدرج قبل أيّ شقّ — أساسُ قياس الحركة النقدية الفعلية.
      final drawerBefore = await _drawerBalance(drawer.id);

      // ٤-أ · شقُّ الارتجاع — المسارُ الإلزاميّ.
      // حالةُ الفاتورة الأصلية يكتبها **آخرُ** نداء، فيحمل وحدَه
      // `isFullReturn` المحسوبَ على المجموعتَين معاً.
      final legs = <({Map<int, double> qty, bool damaged})>[
        if (soundQuantities.isNotEmpty)
          (qty: soundQuantities, damaged: false),
        if (damagedQuantities.isNotEmpty)
          (qty: damagedQuantities, damaged: true),
      ];
      for (var i = 0; i < legs.length; i++) {
        final leg = legs[i];
        final isLast = i == legs.length - 1;
        final returnOk = await _returns.processSalesReturn(
          invoice: originalInvoice,
          returnQuantities: leg.qty,
          productCache: returnProductCache,
          reason: reason ??
              (leg.damaged
                  ? 'استبدال (تالف) $exchangeKey'
                  : 'استبدال $exchangeKey'),
          userId: userId,
          userName: userName,
          isFullReturn: isLast && isFullReturn,
          isDamaged: leg.damaged,
        );
        if (!returnOk) {
          throw const ExchangeFailedException(
            'تعذّر تنفيذ شقّ الارتجاع — لم يُحفظ أيُّ شقٍّ من الاستبدال.',
          );
        }
      }

      // ما خرج من الدرج فعلاً في شقّ الارتجاع — مقيسٌ لا مقدَّر.
      final drawerAfterReturn = await _drawerBalance(drawer.id);

      // ٤-ب · شقُّ البيع بأسعار اليوم وضريبةِ اليوم.
      //
      // ⚠️ `completeSalesTransaction` **تبتلع** الاستثناءَ وتُرجع
      // `SaleResult.failure`. وابتلاعُ الاستثناء هو بعينه ما يكسر الذرّية
      // (المسبارُ ٤: خارجيةٌ تلتقط ⇒ الخارجيةُ تُثبَّت) — فيُعاد الرميُ هنا
      // صراحةً كي تُلغى المعاملةُ الخارجيةُ ومعها شقُّ الارتجاع كلُّه.
      final saleResult = await _sales.completeSalesTransaction(SaleRequest(
        items: replacementItems,
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: expectedSaleTotal,
        cashAmount: expectedSaleTotal,
        // نفسُ درج الوردية الذي صُرف منه المرتجع — لا خزنةٌ افتراضيةٌ عامّة.
        cashSafeId: drawer.id,
        discountPercent: discountPercent,
        taxPercent: taxPercent,
        taxEnabled: taxEnabled,
        costCenterId: costCenterId,
        branchId: branchId,
        notes: _saleNote(
          exchangeKey: exchangeKey,
          returnDocumentId: originalInvoice.id,
          userNotes: notes,
        ),
      ));
      if (!saleResult.isSuccess) {
        throw ExchangeFailedException(
          'تعذّر تنفيذ شقّ البيع — أُلغي الاستبدالُ كاملاً ولم يُحفظ مردودٌ '
          'ولا فاتورة. السبب: ${saleResult.errorMessage ?? 'غير معروف'}',
        );
      }
      final saleInvoiceId = saleResult.invoiceId!;

      // ٤-ج · الإجماليُّ المعتمَد من الصفّ المحفوظ لا من حسابٍ موازٍ.
      final sale = await (_db.select(_db.salesInvoices)
            ..where((s) => s.id.equals(saleInvoiceId)))
          .getSingle();
      // سياجٌ ضدّ استبدالٍ «نصفِ مدفوع» صامت: لو افترق المحفوظُ عن المدفوع
      // لصارت فاتورةُ البيع ذمّةً على عميلٍ لم يوقّع عليها، وحركةُ الدرج
      // أقلَّ من قيمة المستند. أوقِف بدل أن تمرّ.
      if ((sale.total - sale.paid).abs() > 0.01) {
        throw ExchangeFailedException(
          'اختلّ حسابُ فاتورة الاستبدال (إجمالي ${sale.total} مقابل مدفوع '
          '${sale.paid}) — أُلغي الاستبدالُ كاملاً.',
        );
      }

      // ٤-د · المفتاحُ المشترك على مستند المردود (الفاتورةُ الأصلية).
      await (_db.update(_db.salesInvoices)
            ..where((s) => s.id.equals(originalInvoice.id)))
          .write(SalesInvoicesCompanion(
        notes: Value(_appendExchangeTag(
          originalInvoice.notes,
          '|exch:$exchangeKey|exsale:$saleInvoiceId',
        )),
      ));

      // ٤-هـ · رقمُ سند المردود — من صفّ الخزنة الذي كتبه شقُّ الارتجاع،
      // نفسُ مصدر `getSalesReturnPrintData`.
      final voucherRow = await (_db.select(_db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('sales_return') &
                t.referenceId.equals(originalInvoice.id))
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();

      // ٤-و · التسويةُ من **الشقَّين النقديَّين فعلاً** لا من قيمتَي
      // المستندَين. الفاتورةُ الأصليةُ البنكيةُ تردّ إلى الخزنة البنكية،
      // والآجلةُ تُسوّى على رصيد العميل — وفي الحالتين يبقى شقُّ البيع يقبض
      // نقداً كاملاً. فالاشتقاقُ من الإجماليَّين يعرض «اقبض ٣٠» بينما يدفع
      // العميلُ ١٣٠. ونفسُ الدالّة الخالصة تُستعمل كي يبقى الرقمُ المعروضُ
      // والمنفَّذُ من مصدرٍ واحد، وكي تبقى عتبةُ «لا حركةَ بصفر» واحدةً.
      final drawerAfterSale = await _drawerBalance(drawer.id);
      final cashRefunded =
          (drawerBefore - drawerAfterReturn).clamp(0.0, double.infinity);
      final cashCollected =
          (drawerAfterSale - drawerAfterReturn).clamp(0.0, double.infinity);
      final settlement = settleExchange(
        returnTotal: cashRefunded,
        saleTotal: cashCollected,
        decimalPlaces: AppConstants.decimalPlaces,
      );

      return ExchangeResult(
        exchangeKey: exchangeKey,
        returnDocumentId: originalInvoice.id,
        returnVoucherNumber: voucherRow?.voucherNumber,
        saleInvoiceId: saleInvoiceId,
        saleInvoiceNumber: sale.invoiceNumber,
        returnTotal: returnTotal,
        saleTotal: sale.total,
        cashRefunded: cashRefunded,
        cashCollected: cashCollected,
        direction: settlement.direction,
        difference: settlement.amount,
        drawerSafeId: drawer.id,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // مساعداتٌ داخلية
  // ─────────────────────────────────────────────────────────────────────────

  Future<double> _drawerBalance(int safeId) async {
    final safe = await (_db.select(_db.safes)..where((s) => s.id.equals(safeId)))
        .getSingleOrNull();
    return safe?.balance ?? 0;
  }

  /// ما يضيفه شقُّ الارتجاع إلى الرفّ **بوحدات الأساس**، بمفتاح `productId`.
  ///
  /// ثلاثةُ شروطٍ يسقط بأيٍّ منها الاحتساب:
  ///  * السطرُ **موسومٌ معيباً** ⇒ `processSalesReturn(isDamaged: true)` يُعيده
  ///    ثم يُتلفه فوراً، فلا يصل الرفَّ (قرارُ المالك ب).
  ///  * **مخزنُ الفاتورة الأصلية ≠ مخزنُ البيع** ⇒ الارتجاعُ يعود إلى
  ///    `invoice.warehouseId` (كما يفعل `processSalesReturn` حرفياً) فلا يوفّر
  ///    شيئاً في مخزن البيع.
  ///  * الصنفُ غيرُ متعقَّبِ المخزون ⇒ لا رصيدَ له أصلاً (‏`trackInventory`
  ///    يُفحص عند الاستهلاك).
  ///
  /// والضربُ في `quantityInBase` مطابقٌ لـ`stockReturnQty` في
  /// `processSalesReturn`: `costPrice`/الرصيد بوحدة الأساس والكميةُ بوحدة
  /// البيع.
  Map<int, double> _returnCreditByProduct({
    required List<SalesInvoiceItem> originalItems,
    required Map<int, double> returnQuantities,
    required Set<int> damagedItemIds,
    required int originalWarehouseId,
    required int saleWarehouseId,
  }) {
    if (originalWarehouseId != saleWarehouseId) return const {};
    final credit = <int, double>{};
    for (final item in originalItems) {
      final qty = returnQuantities[item.id] ?? 0;
      if (qty <= 0) continue;
      if (damagedItemIds.contains(item.id)) continue;
      final inBase = item.quantityInBase > 0 ? item.quantityInBase : 1.0;
      credit[item.productId] = (credit[item.productId] ?? 0) + qty * inBase;
    }
    return credit;
  }

  /// الرصيدُ المتاحُ فعلاً في هذا المخزن = `quantity - reserved_quantity`،
  /// وهو نفسُ التعريف الذي يفرضه `_updateWarehouseBalance` في `adjustStock`
  /// (`(quantity - COALESCE(reserved_quantity, 0)) + $quantity >= 0`) وتفرضه
  /// `reserveStock`. وغيابُ صفِّ رصيدٍ للمخزن = صفرٌ متاح — مطابقةً لفرع
  /// «الصنف غير متوفر في أي مستودع» هناك. ويُضاف إليه [returnCredit] — ما
  /// يعيده شقُّ الارتجاع إلى الرفّ **قبل** أن يخصم شقُّ البيع في نفس
  /// المعاملة.
  Future<void> _rejectIfReplacementUnavailable({
    required List<CartItemEntity> items,
    required int warehouseId,
    required Map<int, double> returnCredit,
  }) async {
    // تُجمَّع الكمياتُ بالصنف: سطران لنفس الصنف يستهلكان نفسَ الرصيد.
    final neededByProduct = <int, double>{};
    for (final item in items) {
      neededByProduct[item.productId] =
          (neededByProduct[item.productId] ?? 0) + item.stockQuantity;
    }

    for (final entry in neededByProduct.entries) {
      final product = await _db.getProductById(entry.key);
      if (product == null) {
        throw ExchangeStockUnavailableException(
          'الصنفُ البديل (#${entry.key}) غيرُ موجود — تعذّر الاستبدال.',
        );
      }
      if (!product.trackInventory) continue; // خدمةٌ / صنفٌ بلا مخزون

      final balance = await (_db.select(_db.inventoryBalances)
            ..where((b) =>
                b.productId.equals(entry.key) &
                b.warehouseId.equals(warehouseId))
            ..limit(1))
          .getSingleOrNull();
      final onShelf =
          (balance?.quantity ?? 0) - (balance?.reservedQuantity ?? 0);
      final available = onShelf + (returnCredit[entry.key] ?? 0);
      if (available + 0.001 < entry.value) {
        throw ExchangeStockUnavailableException(
          'الصنفُ البديل "${product.name}" غيرُ متوفّرٍ بالكمية المطلوبة '
          '(المتاح ${available.toStringAsFixed(AppConstants.decimalPlaces)}، '
          'المطلوب ${entry.value.toStringAsFixed(AppConstants.decimalPlaces)}) '
          '— لا يُحفظ الاستبدالُ ببديلٍ نافد.',
        );
      }
    }
  }

  String _saleNote({
    required String exchangeKey,
    required int returnDocumentId,
    String? userNotes,
  }) =>
      _appendExchangeTag(
        userNotes,
        '|exch:$exchangeKey|exret:$returnDocumentId',
      );

  /// يُلحق لاحقةَ الربط بلا أن يمسح ملاحظةً قائمة، وبلا تكرارٍ عند إعادة
  /// النداء.
  static String _appendExchangeTag(String? existing, String tag) {
    final base = (existing == null || existing.isEmpty) ? 'استبدال' : existing;
    if (base.contains(tag)) return base;
    return '$base$tag';
  }
}

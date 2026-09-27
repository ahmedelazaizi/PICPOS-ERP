import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/e_invoicing_providers.dart';
import '../../../domain/entities/cart_item_entity.dart';
import 'cart_controller.dart';

class CheckoutState {
  final bool isProcessing;
  final String? error;
  final int? lastInvoiceId;

  const CheckoutState({
    this.isProcessing = false,
    this.error,
    this.lastInvoiceId,
  });

  /// `error ?? this.error` معناه «مرِّر null = ما تغيّرش»، فـ`clearError()`
  /// كان **عمليةً فاضية** والرسالةُ القديمة تفضل ملزوقة. والأثرُ في PicPos أن
  /// شاشةَ الدفع تعرض `checkoutController.error ?? 'فشل حفظ الفاتورة'`، فأيُّ
  /// فشلٍ لاحقٍ بلا رسالةٍ خاصة (كرفض حارس إعادة الدخول) يطلع برسالةِ بيعةٍ
  /// **قديمةٍ خالص** — والكاشير يتصرّف على سببٍ غلط.
  ///
  /// `clearError` صريحةٌ لأن `null` وحدها لا تفرّق بين «امسح» و«اترك كما هي».
  CheckoutState copyWith({
    bool? isProcessing,
    String? error,
    bool clearError = false,
    int? lastInvoiceId,
  }) {
    return CheckoutState(
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
      lastInvoiceId: lastInvoiceId ?? this.lastInvoiceId,
    );
  }
}

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    return const CheckoutState();
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// High-level payment processing that handles different methods
  Future<bool> processPayment({
    required String method,
    required double total,
    double? cashAmount,
    double? bankAmount,
    double? clickAmount,
    int? bankSafeId,
    int? customerId,
  }) async {
    if (state.isProcessing) return false;
    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final cartState = ref.read(cartControllerProvider);
      
      // Negative Sale Gating: Restrict if total is negative
      if (cartState.total < 0) {
        state = state.copyWith(isProcessing: false, error: 'المبلغ الإجمالي بالسالب — يرجى تصحيح الأصناف أو تعويض الرصيد');
        return false;
      }

      double paid = 0;
      double? cash;
      double? bank;
      double? click;

      if (method == 'cash') {
        paid = total;
        cash = total;
        bank = 0;
      } else if (method == 'transfer' || method == 'card' || method == 'bank') {
        paid = total;
        cash = 0;
        bank = total;
      } else if (method == 'click') {
        paid = total;
        cash = 0;
        bank = 0;
        click = total;
      } else if (method == 'credit') {
        if (customerId == null) {
          state = state.copyWith(isProcessing: false, error: 'يجب اختيار عميل للبيع بالآجل');
          return false;
        }
        paid = 0;
        cash = 0;
        bank = 0;
      } else {
        // 'multiple' / 'mixed'
        cash = cashAmount;
        bank = bankAmount;
        click = clickAmount;
        paid = (cash ?? 0) + (bank ?? 0) + (click ?? 0);
      }

      return await processCheckout(
        paymentMethod: method,
        paidAmount: paid,
        cashAmount: cash,
        bankAmount: bank,
        clickAmount: click,
        bankSafeId: bankSafeId,
        customerId: customerId,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  Future<bool> processCheckout({
    required String paymentMethod,
    required double paidAmount,
    double? cashAmount,
    double? bankAmount,
    double? clickAmount,
    int? bankSafeId,
    int? customerId,
  }) async {
    // NOTE: No re-entrancy guard here — processPayment() already sets
    // isProcessing=true before calling this method. Adding a guard here
    // would cause processCheckout to short-circuit and return false
    // without ever running, leaving isProcessing stuck at true forever.

    final cartState = ref.read(cartControllerProvider);
    final authState = ref.read(authProvider);
    final userId = authState.originalUser?.id ?? 1;
    final useCase = ref.read(completeSaleUseCaseProvider);

    debugPrint('[CHECKOUT] items=${cartState.items.length}, total=${cartState.total}, '
        'method=$paymentMethod, paid=$paidAmount, '
        'itemTypes=${cartState.items.map((i) => i.itemType.name).toList()}');

    try {
      // ── لا بيعَ بنطاقٍ فارغ (‏قرارُ المالك 2026-08-23) ──────────────────
      // فرعُ البيعة هنا يُشتقّ من **الفرع النشِط** (‏`_resolveBranchId`)،
      // ونطاقُ الرؤية يُشتقّ من **إسنادات المستخدم**. فكاشيرٌ بلا إسنادٍ
      // كان يبيع فعلاً ثمّ لا يرى بيعتَه — مصدرا حقيقةٍ متضادّان.
      //
      // ويُقال السببُ نصّاً صريحاً لا عبر `throw`: الـcatch أدناه يلفّ كلَّ
      // استثناءٍ في «حدث خطأ غير متوقع»، وهذا سببٌ متوقَّعٌ تماماً وله
      // إجراءٌ واضح.
      final scope = await ref.read(branchScopeProvider.future);
      if (scope.isEmptyScope) {
        state = state.copyWith(
          isProcessing: false,
          error: 'لا فروعَ مُسنَدةٌ لحسابك — لا يمكن إتمام البيع. اطلب من '
              'مدير النظام إسنادَ فرعٍ واحدٍ على الأقل، وإلّا سُجّلت البيعةُ '
              'ثمّ اختفت عنك.',
        );
        return false;
      }

      // ── PERF FIX: Resolve all provider values in parallel instead of sequentially ──
      final results = await Future.wait([
        ref.read(activeWarehouseIdProvider.future),        // [0] warehouseId
        ref.read(posCashSafeIdProvider.future),            // [1] cashSafeId
        ref.read(posBankSafeIdProvider.future),            // [2] bankSafeId
        ref.read(posClickSafeIdProvider.future),           // [3] clickSafeId
        _resolveAutoCostCenter(),                          // [4] costCenterId
        _resolveBranchId(),                                // [5] branchId
      ]);

      final warehouseId = results[0] as int;
      final mappedCashSafeId = results[1];
      final mappedBankSafeId = results[2];
      final mappedClickSafeId = results[3];
      final costCenterId = results[4];
      final branchId = results[5];

      debugPrint('[POS_CHECKOUT] warehouseId=$warehouseId, userId=$userId, '
          'deliveryCompanyId=${cartState.deliveryCompanyId}, '
          'courierId=${cartState.courierId}');

      // Map orderType to saleType for invoice persistence
      String saleType;
      if (cartState.orderType == 'delivery') {
        saleType = (cartState.priceLevel != 'retail' && cartState.priceLevel != 'wholesale')
            ? cartState.priceLevel
            : 'delivery';
      } else {
        saleType = cartState.orderType;
      }

      String? finalNotes = cartState.orderNote;
      
      // If there's an adhoc customer note, explicitly append it
      final adhocName = cartState.adhocCustomerName;
      final adhocPhone = cartState.adhocCustomerPhone;
      final adhocNote = cartState.adhocCustomerNote;
      
      if (adhocNote != null && adhocNote.isNotEmpty) {
        finalNotes = finalNotes != null && finalNotes.isNotEmpty
            ? '$finalNotes | $adhocNote'
            : adhocNote;
      }

      final pricesIncludeTax =
          await ref.read(databaseProvider).getSettingValue('prices_include_tax') ==
              'true';
      final request = SaleRequest(
        items: cartState.items,
        customerId: customerId ?? cartState.selectedCustomerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        clickAmount: clickAmount,
        cashSafeId: mappedCashSafeId,
        bankSafeId: bankSafeId ?? mappedBankSafeId,
        clickSafeId: mappedClickSafeId,
        discountPercent: cartState.discountPercent,
        taxPercent: cartState.taxRate * 100,
        taxEnabled: cartState.taxEnabled,
        pricesIncludeTax: pricesIncludeTax,
        deliveryFee: cartState.deliveryFee,
        deliveryCompanyId: cartState.deliveryCompanyId,
        courierId: cartState.courierId,
        deliveryStatus: cartState.deliveryStatus,
        notes: finalNotes,
        quotationId: cartState.linkedQuotationId,
        isReturn: cartState.items.any((i) => i.itemType == CartItemType.returned),
        saleType: cartState.items.any((i) => i.itemType == CartItemType.returned) ? 'return' : saleType,
        adhocCustomerName: adhocName,
        adhocCustomerPhone: adhocPhone,
        adhocCustomerNote: adhocNote,
        costCenterId: costCenterId,
        branchId: branchId,
        platformOrderNumber: cartState.platformOrderNumber,
      );

      final result = await useCase.execute(request);

      if (result.isSuccess) {
        // #Forensic Log: Sale Completion (fire-and-forget — don't block UI)
        try {
          final userName = authState.originalUser?.displayName ?? 'مجهول';
          final logger = ref.read(activityLoggerProvider);
          logger.logSale(
            userId,
            userName,
            result.invoiceId ?? 0,
            cartState.total,
            paymentMethod,
          );
        } catch (_) {}

        // #E-Invoice Auto-Submit (fire-and-forget)
        if (result.invoiceId != null) {
          try {
            final autoSubmitter = ref.read(eInvoiceAutoSubmitterProvider);
            // Non-blocking: wrap in Future so async failures surface in catchError
            // rather than being silently swallowed.
            unawaited(
              Future(() => autoSubmitter.submitSaleInvoice(result.invoiceId!))
                  .catchError((Object e) {
                debugPrint('[E-INVOICE] Auto-submit failed for invoice ${result.invoiceId}: $e');
              }),
            );
          } catch (e) {
            debugPrint('[E-INVOICE] Auto-submit setup failed: $e');
          }
        }

        // ── تفويترُ حجزٍ لا بيعةٌ عاديّة (‏ق-٢) ──────────────────────────
        // بيعةُ نقطةِ البيع وتفويترُ الحجز يمرّان بنفس الشِّفرة وأثرُهما
        // المحاسبيُّ مختلف: التفويترُ وحدَه يُطفئ التزامَ العربون (مدين
        // `2134` / دائن حساب العميل) ويكتب `Bookings.invoiceId`.
        //
        // والعلامةُ **صريحةٌ لا مستنتَجة**: استنتاجُها من «العميل له حجزٌ
        // اليوم» كان سيُطبِّق العربونَ على بيعةٍ عابرةٍ لا علاقةَ لها به.
        // و`takeIfAny` تقرأ وتُفرِّغ ذرّيّاً، فالبيعةُ التالية عاديّةٌ ولا
        // تُطبِّق نفسَ العربون ثانيةً.
        //
        // ⚠️ وفشلُ الخصمِ **لا يُسقط بيعةً نجحت**: الفاتورةُ مُرحَّلةٌ فعلاً
        // والمخزونُ تحرّك. فيُسجَّل الخطأُ ويُقال للمستخدم، ولا يُرمى فوق
        // بيعٍ تمّ.
        final pendingBookingId =
            ref.read(bookingInvoicingProvider.notifier).takeIfAny();
        if (pendingBookingId != null && result.invoiceId != null) {
          try {
            await ref.read(databaseProvider).applyBookingDepositToInvoice(
                  bookingId: pendingBookingId,
                  invoiceId: result.invoiceId!,
                  userId: userId,
                );
          } catch (e) {
            await DiagnosticLogger.log(
              'BOOKING-INVOICE',
              '⚠ تعذّر خصمُ عربون الحجز #$pendingBookingId على الفاتورة '
              '${result.invoiceId} — $e',
            );
            state = state.copyWith(
              error: 'تمّ البيع، لكن تعذّر خصمُ عربون الحجز: $e',
            );
          }
        }

        // NOTE: Server sync is already handled inside completeSalesTransaction()
        // which does direct POST + outbox queuing. No need for a second
        // ClientWriteInterceptor.submitSale call here — that would create
        // duplicate outbox entries.

        state = state.copyWith(
          isProcessing: false,
          lastInvoiceId: result.invoiceId,
        );
        ref.read(cartControllerProvider.notifier).clearCart();

        // Belt-and-suspenders: force the sales-list watcher to emit so the
        // Sales Invoices screen reflects this sale immediately. Drift's
        // table watch usually handles this, but cross-isolate / mode
        // boundaries have shown intermittent misses.
        ref.invalidate(salesInvoicesChangeProvider);

        return true;
      } else {
        state = state.copyWith(
          isProcessing: false,
          error: result.errorMessage,
        );
        return false;
      }
    } on ShiftRequiredException {
      // ليس عطلاً بل طلبَ إجراء (مواصفة 2026-08-18 ح‑١): بيعةٌ نقديّةٌ بلا
      // ورديّةٍ على الدرج. الشاشةُ تعرض فتحَ ورديّةٍ وتعيد المحاولة، فابتلاعُه
      // في `error` نصّاً يحوّله إلى «حدث خطأ غير متوقع» لا مخرجَ منه.
      state = state.copyWith(isProcessing: false);
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'حدث خطأ غير متوقع: $e',
      );
      return false;
    }
  }

  /// Helper to resolve branch ID without blocking on failure
  Future<int?> _resolveBranchId() async {
    try {
      final branchRepo = ref.read(branchRepositoryProvider);
      final activeBranch = await branchRepo.getActiveBranch();
      return activeBranch?.id;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveAsQuotation() async {
    state = state.copyWith(isProcessing: true, clearError: true);

    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      state = state.copyWith(isProcessing: false, error: 'السلة فارغة');
      return false;
    }

    final authState = ref.read(authProvider);
    final userId = authState.originalUser?.id ?? 1;
    final quotationsRepo = ref.read(quotationsRepositoryProvider);

    try {
      final calcUseCase = CalculateInvoiceTotalsUseCase();
      final totals = calcUseCase.execute(
        items: cartState.items,
        invoiceDiscountPercent: cartState.discountPercent,
        taxPercent: cartState.taxEnabled ? cartState.taxRate * 100 : 0,
        taxEnabled: cartState.taxEnabled,
      );

      final quotationId = await quotationsRepo.saveQuotation(
        items: cartState.items,
        customerId: cartState.selectedCustomerId,
        userId: userId,
        subtotal: totals.subtotal,
        discount: totals.totalDiscount,
        tax: totals.taxAmount,
        total: totals.total,
        notes: cartState.orderNote,
      );

      try {
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: userId,
          userName: authState.originalUser?.displayName ?? 'Unknown',
          action: 'create_quotation',
          entityType: 'quotation',
          entityId: quotationId,
          description: 'إنشاء عرض سعر',
          amount: totals.total,
        );
      } catch (_) {}

      state = state.copyWith(isProcessing: false, lastInvoiceId: quotationId);
      ref.read(cartControllerProvider.notifier).clearCart();
      return true;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'فشل حفظ عرض السعر: $e',
      );
      return false;
    }
  }

  /// POS-4: Auto-resolve cost center from the active warehouse → branch fallback.
  /// Priority: warehouse cost center (server setup) → branch cost center → null.
  Future<int?> _resolveAutoCostCenter() async {
    try {
      // 1. Try warehouse cost center (matches server-side setup)
      final warehouseId = await ref.read(activeWarehouseIdProvider.future);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      final warehouse = await inventoryRepo.getWarehouseById(warehouseId);
      if (warehouse?.costCenterId != null) return warehouse!.costCenterId;

      // 2. Fallback to branch cost center
      final branchRepo = ref.read(branchRepositoryProvider);
      final activeBranch = await branchRepo.getActiveBranch();
      return activeBranch?.costCenterId;
    } catch (_) {
      return null;
    }
  }
}


final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

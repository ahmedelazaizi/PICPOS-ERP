part of 'picpos_pos_screen.dart';

/// المرتجع السريع **بلا فاتورة** داخل شاشة البيع السريع (بند ٤).
///
/// الفكرة: وضعُ إدخالٍ يُبدَّل بزرّ، فيُضاف كلُّ صنفٍ يُمسَح أو يُضغَط كسطرِ
/// `CartItemType.returned` بكمية ١ (قابلةٍ للتعديل) بسعر بيع الصنف الحاليّ.
/// الحفظُ يمرّ بمسار `saleType='return'` القائم (مستند `RET-`: مخزون + قيد +
/// حركة خزنة في الوردية) — **لا** `processSalesReturn` الذي يشترط فاتورة.
///
/// قراراتٌ مسجَّلة:
///  * الاستردادُ نقدٌ فقط، وفوق سقف `pos_no_invoice_return_cap` يلزم مسؤول.
///  * سلّةٌ مختلطة مسموحة: تُحفَظ مستندَين وتُسوّى بالصافي (انظر
///    [CartSettlementPlan]).
///  * الدرجُ لا يُفتح عند ردّ نقد (انظر [shouldKickDrawerForSettlement]).
extension _PicPosNoInvoiceReturnOps on _PicPosOperations {
  /// زرُّ «مرتجع» بجوار أدوات السلّة: يشعل وضعَ الإدخال أو يطفئه.
  Future<void> _toggleReturnEntryMode() async {
    final notifier = ref.read(posReturnEntryModeProvider.notifier);
    if (notifier.state) {
      notifier.state = false;
      _refocusScanner();
      return;
    }
    // الوضعان حصريّان: المرتجعُ المرتبط بفاتورة يقفل السلّةَ أصلاً.
    if (ref.read(posReturnModeProvider) != null ||
        ref.read(posExchangeModeProvider) != null) {
      showPosToast(
        context,
        ref,
        tr('أنهِ وضعَ المرتجع أو الاستبدال الحاليّ أوّلاً'),
        type: PosNotificationType.warning,
      );
      return;
    }
    // نفسُ بوّابتَي الدخول في وضع المرتجع المرتبط بفاتورة.
    if (!await ensureQuickReturnPermission(ref, context)) return;
    if (!mounted) return;
    if (!await _userHasPermissionFresh(PermissionCodes.salesReturnCreate)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: tr('إنشاء مرتجع مبيعات'),
        permission: PermissionCodes.salesReturnCreate,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    notifier.state = true;
    showPosToast(
      context,
      ref,
      tr('وضع المرتجع بلا فاتورة: كلُّ صنفٍ يُمسَح يُضاف مرتجعاً بكمية ١'),
      type: PosNotificationType.info,
    );
    _refocusScanner();
  }

  /// يُضيف [product] سطرَ مرتجعٍ (وضعُ الإدخال مشتعل).
  Future<void> _addReturnLine(ProductEntity product, {double? weight}) async {
    var qty = weight ?? 1.0;
    if (product.isSoldByWeight && weight == null) {
      // الصنفُ الموزون بلا وزنٍ ليس مرتجعاً مفهوماً: نسأل عن الوزن.
      final asked = await PicPosNumericKeypadDialog.show(
        context,
        title: product.name,
        initialValue: 1,
        decimals: 3,
        min: 0.001,
      );
      if (asked == null || asked <= 0 || !mounted) {
        _refocusScanner();
        return;
      }
      qty = asked;
    }
    ref.read(cartControllerProvider.notifier).addReturnItem(product, quantity: qty);
    final items = ref.read(cartControllerProvider).items;
    final idx = items.lastIndexWhere(
        (i) => i.productId == product.id && i.itemType == CartItemType.returned);
    if (idx != -1) setState(() => selectedIndex = idx);
    _refocusScanner();
  }

  /// مسحُ باركودٍ أثناء وضع الإدخال: يفكّ باركودَ الميزان ثم الباركودَ ثم الكود.
  ///
  /// ⚠️ لا يمرّ بمتحكّم البحث المشترك: ذاك يضيف **بيعاً** في ستّة مواضع. وباركودُ
  /// وحدةٍ فرعيّةٍ (كرتونة) غيرُ مدعوم هنا — يُرفض كغير مسجَّل بدل تخمين وحدة.
  Future<void> _addReturnByBarcode(String barcode) async {
    final code = barcode.trim();
    barcodeController.clear();
    if (code.isEmpty) return;
    try {
      final scale = await ScaleBarcodeHandler.tryParse(
          RepositoryBarcodeAdapter(ref), code);
      final repo = ref.read(productRepositoryProvider);
      final product = scale?.product ??
          await repo.getProductByBarcode(code) ??
          await repo.getProductByCode(code);
      if (!mounted) return;
      if (product == null) {
        showPosToast(context, ref, tr('باركود غير مسجَّل'),
            type: PosNotificationType.error);
        _refocusScanner();
        return;
      }
      await _addReturnLine(product, weight: scale?.quantity);
    } catch (e) {
      debugPrint('[PicPos-ReturnEntry] تعذّر إضافة المرتجع: $e');
      if (mounted) {
        showPosToast(context, ref, tr('تعذّرت إضافة الصنف'),
            type: PosNotificationType.error);
        _refocusScanner();
      }
    }
  }

  /// حفظُ سلّةٍ فيها سطورُ مرتجع (خالصةٍ أو مختلطة). يُنادى من
  /// `_processPaymentAndSave` بدل مسار البيع حين `hasReturnLines`.
  Future<void> _processNoInvoiceReturnSave(
    CartState cartState, {
    required bool printAfter,
  }) async {
    final hasSale = cartState.hasSaleLines;

    // بوّابات الصلاحية: المرتجعُ دائماً، والبيعُ إن وُجد شقُّ بيع.
    if (!await _userHasPermissionFresh(PermissionCodes.salesReturnCreate)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: tr('إنشاء مرتجع مبيعات'),
        permission: PermissionCodes.salesReturnCreate,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    if (hasSale && !await _userHasPermissionFresh(PermissionCodes.posSave)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: tr('حفظ فاتورة البيع السريع'),
        permission: PermissionCodes.posSave,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    if (!await _validateCartBeforeCheckout(cartState)) return;
    if (!mounted) return;

    try {
      await ref.read(fiscalPeriodValidationProvider(
        (date: DateTime.now(), operation: tr('مرتجع')),
      ).future);
    } catch (e) {
      if (!mounted) return;
      showPosToast(context, ref, e.toString().replaceFirst('Exception: ', ''),
          type: PosNotificationType.error);
      return;
    }

    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final plan = planCartSettlement(
      items: cartState.items,
      invoiceDiscountPercent: cartState.discountPercent,
      invoiceDiscountAmount: cartState.invoiceDiscountAmount,
      taxPercent: cartState.taxEnabled ? cartState.taxRate * 100 : 0,
      taxEnabled: cartState.taxEnabled,
      deliveryFee: cartState.deliveryFee,
    );
    if (plan.returnTotal <= 0) {
      showPosToast(context, ref, tr('قيمة المرتجع صفر — راجع سعر الصنف'),
          type: PosNotificationType.error);
      return;
    }
    if (hasSale &&
        policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'reqcust')) &&
        cartState.selectedCustomerId == null) {
      showPosToast(context, ref, tr('اختر عميلاً قبل الدفع — الإعداد يُلزم بذلك'),
          type: PosNotificationType.error);
      return;
    }

    // سقفُ قيمة المرتجع بلا فاتورة — يقيس **قيمةَ المرتجع** لا الصافي، كي لا
    // يُمرَّر مرتجعٌ كبيرٌ بضمّه إلى بيعٍ كبير. فوقه: موافقةُ مسؤول.
    final cap = noInvoiceReturnCap(policy);
    if (judgeNoInvoiceReturn(returnValue: plan.returnTotal, cap: cap) ==
        NoInvoiceReturnVerdict.needsManager) {
      final ok = await requestManagerApproval(
        context,
        actionName: tr('مرتجع بلا فاتورة {p0} — فوق حدّ {p1}', {
          'p0': plan.returnTotal.toStringAsFixed(2),
          'p1': cap.toStringAsFixed(0),
        }),
      );
      if (!ok || !mounted) {
        if (mounted) {
          showPosToast(context, ref, tr('أُلغي المرتجع — لم يُصادَق على المبلغ'),
              type: PosNotificationType.warning);
          _refocusScanner();
        }
        return;
      }
    }
    // `mgrlimit` على شقّ البيع كما في المسار العاديّ.
    final confirmAbove = quickSaleManagerConfirmAbove(policy);
    if (hasSale && confirmAbove != null && plan.saleTotal > confirmAbove) {
      final okBig = await requestManagerApproval(
        context,
        actionName: tr('فاتورة {p0} — فوق حدّ {p1}', {
          'p0': plan.saleTotal.toStringAsFixed(2),
          'p1': confirmAbove.toStringAsFixed(0),
        }),
      );
      if (!okBig || !mounted) {
        if (mounted) _refocusScanner();
        return;
      }
    }

    // تأكيدُ النقد: قبضٌ (عدّادُ الفكّة) أو ردٌّ (تأكيدٌ صريح).
    if (plan.cashToCollect > 0) {
      final confirmed = await PosCashTenderingDialog.show(
        context,
        totalAmount: plan.cashToCollect,
        showQuickAmounts:
            policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'quickamt')),
      );
      if (confirmed != true || !mounted) {
        _refocusScanner();
        return;
      }
    } else {
      final ok = await AppConfirmDialog.show(
        context,
        title: tr('رد نقدي للعميل'),
        message: plan.cashToRefund > 0
            ? tr('سيُردّ {p0} نقداً للعميل من الدرج (مرتجع بلا فاتورة). متأكد؟',
                {'p0': plan.cashToRefund.toStringAsFixed(2)})
            : tr('المرتجع يساوي البيع تماماً — لا نقد يُقبض ولا يُردّ. متابعة؟'),
        confirmLabel: tr('تأكيد'),
      );
      if (!ok || !mounted) {
        _refocusScanner();
        return;
      }
    }

    var success = false;
    final outcome = await runWithOpenShiftPrompt(
      context: context,
      ref: ref,
      subtitleBuilder: (amount) => tr(
          'حركة نقدية {p0} تمرّ على الدرج.', {'p0': amount.toStringAsFixed(2)}),
      attempt: () async => success = await ref
          .read(checkoutControllerProvider.notifier)
          .processNoInvoiceReturnSettlement(
            plan: plan,
            customerId: cartState.selectedCustomerId,
          ),
    );
    if (!mounted) return;
    if (outcome != ShiftPromptOutcome.completed) {
      showPosToast(
        context,
        ref,
        outcome == ShiftPromptOutcome.cancelledByUser
            ? tr('أُلغيت العملية — لم تُفتَح وردية')
            : tr('تعذّر فتح الوردية، فلم تُحفَظ العملية'),
        type: PosNotificationType.error,
      );
      return;
    }
    if (!success) {
      final err =
          ref.read(checkoutControllerProvider).error ?? tr('فشل حفظ الفاتورة');
      showPosToast(context, ref, err, type: PosNotificationType.error);
      _refocusScanner();
      return;
    }

    ref.read(posReturnEntryModeProvider.notifier).state = false;
    setState(() => selectedIndex = null);
    SystemSound.play(SystemSoundType.click);
    barcodeController.clear();

    // الدرج: يُفتح عند **قبض** نقدٍ صافٍ فقط (انظر [shouldKickDrawerForSettlement]).
    final drawerOn =
        policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'drawer'));
    final openDrawer =
        shouldKickDrawerForSettlement(plan, drawerSettingOn: drawerOn);
    final autoPrint =
        policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'autoprint'));
    final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;

    var printed = false;
    if (printAfter && autoPrint && invoiceId != null) {
      final drawerFuture =
          openDrawer ? _openCashDrawerQuietly() : Future<void>.value();
      if (await _hasReceiptPrinter()) {
        for (var i = 0; i < quickSaleReceiptCopies(policy); i++) {
          printed = await _tryPrintReceipt(invoiceId);
          if (!printed || !mounted) break;
        }
      }
      await drawerFuture;
    } else if (openDrawer) {
      await _openCashDrawerQuietly();
    }
    if (!mounted) return;
    showPosToast(
      context,
      ref,
      plan.cashToRefund > 0
          ? tr('تم حفظ المرتجع — رُدّ {p0} نقداً',
              {'p0': plan.cashToRefund.toStringAsFixed(2)})
          : (printed ? tr('تم حفظ وطباعة الفاتورة') : tr('تم حفظ الفاتورة')),
      type: PosNotificationType.success,
    );
    await _applyAfterInvoiceAction(policy);
  }
}

/// زرُّ «مرتجع» في شريط أدوات السلّة: أحمرُ مضاءٌ حين وضعُ الإدخال مشتعل.
class _ReturnEntryToggle extends ConsumerWidget {
  final VoidCallback onToggle;

  const _ReturnEntryToggle({required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(posReturnEntryModeProvider);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 5),
      child: Tooltip(
        message: active
            ? tr('وضع المرتجع بلا فاتورة مشتعل — اضغط للإطفاء')
            : tr('إدخال أصنافٍ كمرتجع بلا فاتورة'),
        child: InkWell(
          key: const ValueKey('return-entry-toggle'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.error
                  : AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.arrowUUpLeft,
                    size: 12, color: active ? Colors.white : AppColors.error),
                const SizedBox(width: 4),
                Text(
                  active ? tr('مرتجع: مُشتعل') : tr('مرتجع'),
                  style: PicPosText.v(context, 10,
                      color: active ? Colors.white : AppColors.error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

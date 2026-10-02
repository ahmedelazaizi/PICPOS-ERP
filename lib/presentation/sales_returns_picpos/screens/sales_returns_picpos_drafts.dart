// دورةُ مسوّدة مرتجع المبيعات — J2 (قرارُ المالك).
//
// • «حفظ مسودة» ← صفٌّ في `return_drafts` فقط: لا مخزونَ ولا قيدَ ولا
//   خزينةَ ولا رقمَ مستند (الرقمُ يُولَّد عند الترحيل — بلا فجوات).
// • «مراجعة واعتماد» (صلاحيةُ `sales_return_approve`) ← `processReturn`
//   القائمُ نفسُه كاملاً: التأكيدُ ← موافقةُ المدير ← [حفظُ المسوّدة] ←
//   `runWithOpenShiftPrompt` ← المزوّد ← المستودع. ثمّ يُختَم الصفُّ «معتمد».
//   واعتمادٌ مباشرٌ من استمارةٍ جديدة = حفظُ مسوّدةٍ + ترحيلُها بخطوةٍ واحدة؛
//   وإن لم يقع الترحيلُ حُذفت المسوّدةُ التي وُلدت في هذه الخطوة وحدَها.
part of 'sales_returns_picpos_screen.dart';

mixin _SalesReturnsPicposDrafts on ConsumerState<SalesReturnsPicposScreen> {
  // Provided by _SalesReturnsPicposLogic / the State at composition time.
  Future<bool> processReturn({Future<bool> Function()? beforePost});
  TextEditingController get returnReasonController;
  String get selectedReasonCategory;
  set selectedReasonCategory(String value);

  /// المسوّدةُ المفتوحة — `null` لاستمارةٍ لم تُحفَظ بعد.
  int? _draftId;
  bool _savingDraft = false;

  /// يفتح مسوّدةَ [SalesReturnsPicposScreen.draftId] (ثمّ يعتمدها متى طُلب).
  Future<void> openDraftOnStart() async {
    final id = widget.draftId;
    if (id == null) return;
    final repo = ref.read(returnDraftsRepositoryProvider);
    try {
      final draft = await repo.getDraft(id);
      if (draft == null || !draft.isDraft) {
        if (mounted) {
          AppToast.show(context, tr('المسودة غير متاحة — ربما اعتُمدت أو حُذفت'),
              type: ToastType.warning);
        }
        return;
      }
      final invoice = await repo.getSalesInvoice(draft.originalInvoiceId);
      if (invoice == null) {
        if (mounted) {
          AppToast.show(context, tr('الفاتورة الأصلية للمسودة غير موجودة'),
              type: ToastType.error);
        }
        return;
      }
      final ok = await ref.read(salesReturnProvider.notifier).loadDraft(
            invoice: invoice,
            quantities: draft.quantities,
            isFullReturn: draft.isFullReturn,
            isDamaged: draft.isDamaged,
          );
      if (!mounted || !ok) return;
      setState(() {
        _draftId = draft.id;
        final category = draft.reasonCategory ?? '';
        selectedReasonCategory =
            AppConstants.returnReasonCategories.contains(category)
                ? category
                : '';
        returnReasonController.text = draft.reason ?? '';
      });
      if (widget.approveOnOpen) await approveReturn();
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }

  /// هل يملك المستخدمُ «مراجعة واعتماد»؟
  bool get canApproveReturn =>
      watchReturnPermission(ref, PermissionCodes.salesReturnApprove);

  /// صورةُ المسوّدة من حالة الاستمارة — أو `null` مع تنبيهٍ يقول ما ينقص.
  ReturnDraftInput? _draftInput() {
    final state = ref.read(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);
    final invoice = state.selectedInvoice;
    if (invoice == null) return null;
    if (!state.returnQuantities.values.any((q) => q > 0)) {
      AppToast.show(context, tr('يرجى تحديد كمية للإرجاع'),
          type: ToastType.warning);
      return null;
    }
    // نفسُ سقف المستودع (`processSalesReturn`): المرتجَعُ ≤ المتاح.
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.id] ?? 0;
      final available =
          item.quantity - (state.previouslyReturnedQty[item.id] ?? 0);
      if (qty > available + 0.001) {
        AppToast.show(
          context,
          tr('الكمية تتجاوز المتاح ({p0})', {'p0': available}),
          type: ToastType.error,
        );
        return null;
      }
    }
    final total = notifier.calculateReturnTotal();
    var tax = 0.0;
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.id] ?? 0;
      if (qty > 0 && item.quantity > 0) {
        tax += item.taxAmount * (qty / item.quantity);
      }
    }
    final split = SalesReturnRefundSplit.from(
      invoiceTotal: invoice.total,
      invoicePaid: invoice.paid,
      paymentMethod: invoice.paymentMethod,
      cashPaid: invoice.cashPaid,
      bankPaid: invoice.bankPaid,
      totalReturn: total,
      hasCustomer: invoice.customerId != null,
      invoiceRoundingAdjustment: invoice.roundingAdjustment,
    );
    return ReturnDraftInput(
      id: _draftId,
      kind: ReturnDraftKind.sales,
      originalInvoiceId: invoice.id,
      quantities: Map<int, double>.from(state.returnQuantities),
      partyId: invoice.customerId,
      branchId: invoice.branchId,
      warehouseId: invoice.warehouseId,
      reason: returnReasonController.text.trim(),
      reasonCategory: selectedReasonCategory,
      isFullReturn: state.isFullReturn,
      isDamaged: state.isDamaged,
      subtotal: total - tax,
      tax: tax,
      total: total,
      settlement: settlementFromParts(
        balance: split.arRefund,
        cash: split.cashRefund,
        bank: split.bankRefund,
      ),
      userId: ref.read(authProvider).user?.id,
    );
  }

  /// «حفظ مسودة» — يعيد معرّفَ المسوّدة أو `null` إن لم تُحفَظ.
  Future<int?> saveDraft({bool silent = false}) async {
    if (_savingDraft) return null;
    final input = _draftInput();
    if (input == null) return null;
    setState(() => _savingDraft = true);
    try {
      final id =
          await ref.read(returnDraftsRepositoryProvider).saveDraft(input);
      if (!mounted) return id;
      setState(() => _draftId = id);
      ref.invalidate(salesReturnRecordsProvider);
      if (!silent) {
        AppToast.show(context, tr('تم حفظ المسودة — لم يتحرّك مخزونٌ ولا قيد'),
            type: ToastType.success);
      }
      return id;
    } catch (e, stack) {
      if (mounted && !silent) AppErrorHandler.handle(context, e, stack);
      return null;
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  /// «مراجعة واعتماد» — يحفظ المسوّدةَ ثمّ يرحّلها بالمسار القائم.
  Future<void> approveReturn() async {
    if (!readReturnPermission(ref, PermissionCodes.salesReturnApprove)) {
      AppToast.show(context, tr('لا تملك صلاحية «مراجعة واعتماد» المرتجع'),
          type: ToastType.error);
      return;
    }
    final invoiceId = ref.read(salesReturnProvider).selectedInvoice?.id;
    final hadDraft = _draftId != null;
    int? draftId;
    final posted = await processReturn(beforePost: () async {
      draftId = await saveDraft(silent: true);
      // مسوّدةٌ قائمةٌ لم تُحدَّث لا تُرحَّل بحالةٍ تخالف ما حُفظ؛ أمّا
      // الاستمارةُ الجديدة فالمسوّدةُ فيها سجلٌّ لا شرطٌ للترحيل.
      return draftId != null || !hadDraft;
    });
    if (posted) {
      if (draftId != null) {
        try {
          final repo = ref.read(returnDraftsRepositoryProvider);
          final draft = await repo.getDraft(draftId!);
          if (draft != null) await repo.markPosted(draft);
        } catch (e) {
          debugPrint('[J2] mark sales draft posted failed: $e');
        }
      }
      _draftId = null;
      ref.invalidate(salesReturnRecordsProvider);
      if (mounted && widget.popOnDone && invoiceId != null) {
        Navigator.of(context).pop(
          ReturnFormResult(originalInvoiceId: invoiceId, posted: true),
        );
      }
    } else if (!hadDraft && draftId != null) {
      // الترحيلُ لم يقع: المسوّدةُ التي وُلدت في هذه الخطوة تُحذَف.
      try {
        await ref.read(returnDraftsRepositoryProvider).deleteDraft(draftId!);
      } catch (_) {}
      if (mounted) setState(() => _draftId = null);
      ref.invalidate(salesReturnRecordsProvider);
    }
  }
}

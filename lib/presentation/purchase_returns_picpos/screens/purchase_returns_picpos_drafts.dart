// دورةُ مسوّدة مردود المشتريات — J2 (قرارُ المالك). نظيرُ
// `sales_returns_picpos_drafts.dart` حرفاً في القاعدة:
//
// • «حفظ مسودة» ← صفٌّ في `return_drafts` فقط: لا مخزونَ ولا قيدَ ولا
//   خزينةَ ولا رقمَ مستند (PRET- يُولَّد عند الترحيل — بلا فجوات).
// • «مراجعة واعتماد» (صلاحيةُ `purchases_return_approve`) ← `processReturn`
//   القائمُ نفسُه: التأكيدُ ← موافقةُ المدير ← [حفظُ المسوّدة] ←
//   `savePurchaseReturnWithFeedback` (نافذةُ فتح الوردية — J1) ← المستودع.
part of 'purchase_returns_picpos_screen.dart';

mixin _PurchaseReturnsPicposDrafts
    on ConsumerState<PurchaseReturnsPicposScreen> {
  // Provided by _PurchaseReturnsPicposLogic at composition time.
  Future<bool> processReturn({Future<bool> Function()? beforePost});

  /// المسوّدةُ المفتوحة — `null` لاستمارةٍ لم تُحفَظ بعد.
  int? _draftId;
  bool _savingDraft = false;

  /// يفتح مسوّدةَ [PurchaseReturnsPicposScreen.draftId] (ثمّ يعتمدها متى طُلب).
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
      final invoice = await repo.getPurchaseInvoice(draft.originalInvoiceId);
      if (invoice == null) {
        if (mounted) {
          AppToast.show(context, tr('الفاتورة الأصلية للمسودة غير موجودة'),
              type: ToastType.error);
        }
        return;
      }
      final reason = draft.reason;
      final ok = await ref.read(purchaseReturnProvider.notifier).loadDraft(
            invoice: invoice,
            quantities: draft.quantities,
            // سببٌ خارجَ القائمة اليوم (تغيّرت اللغةُ مثلاً) يُترَك فارغاً بدل
            // أن تنهار القائمةُ المنسدلة على قيمةٍ غيرِ موجودة.
            reason: AppConstants.purchaseReturnReasons.contains(reason)
                ? reason
                : null,
          );
      if (!mounted || !ok) return;
      setState(() => _draftId = draft.id);
      if (widget.approveOnOpen) await approveReturn();
    } catch (e, stack) {
      if (mounted) AppErrorHandler.handle(context, e, stack);
    }
  }

  /// هل يملك المستخدمُ «مراجعة واعتماد»؟
  bool get canApproveReturn =>
      watchReturnPermission(ref, PermissionCodes.purchasesReturnApprove);

  ReturnDraftInput? _draftInput() {
    final state = ref.read(purchaseReturnProvider);
    final notifier = ref.read(purchaseReturnProvider.notifier);
    final invoice = state.selectedInvoice;
    if (invoice == null) return null;
    if (!state.returnQuantities.values.any((q) => q > 0)) {
      AppToast.show(context, tr('يرجى تحديد كميات المرتجع'),
          type: ToastType.info);
      return null;
    }
    // نفسُ سقف المزوّد: المرتجَعُ ≤ المتاح (المشترى − المرتجَع سابقاً).
    for (final e in state.returnQuantities.entries) {
      final max = notifier.maxReturnableFor(e.key);
      if (e.value > max + 0.001) {
        AppToast.show(
          context,
          tr('الكمية تتجاوز المتاح ({p0})', {'p0': max}),
          type: ToastType.error,
        );
        return null;
      }
    }
    final net = notifier.calculateReturnTotal();
    final vat = notifier.calculateReturnVat();
    final s = notifier.settlement;
    return ReturnDraftInput(
      id: _draftId,
      kind: ReturnDraftKind.purchase,
      originalInvoiceId: invoice.id,
      quantities: Map<int, double>.from(state.returnQuantities),
      partyId: invoice.supplierId,
      branchId: invoice.branchId,
      warehouseId: invoice.warehouseId,
      reason: state.returnReason,
      subtotal: net,
      tax: vat,
      total: net + vat,
      settlement: s == null
          ? null
          : settlementFromParts(balance: s.apPortion, cash: s.cashPortion),
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
      ref.invalidate(purchaseReturnRecordExtrasProvider);
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
    if (!readReturnPermission(ref, PermissionCodes.purchasesReturnApprove)) {
      AppToast.show(context, tr('لا تملك صلاحية «مراجعة واعتماد» المرتجع'),
          type: ToastType.error);
      return;
    }
    final invoiceId = ref.read(purchaseReturnProvider).selectedInvoice?.id;
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
          debugPrint('[J2] mark purchase draft posted failed: $e');
        }
      }
      _draftId = null;
      ref.invalidate(purchaseReturnRecordExtrasProvider);
      if (mounted && widget.popOnDone && invoiceId != null) {
        Navigator.of(context).pop(
          ReturnFormResult(originalInvoiceId: invoiceId, posted: true),
        );
      }
    } else if (!hadDraft && draftId != null) {
      try {
        await ref.read(returnDraftsRepositoryProvider).deleteDraft(draftId!);
      } catch (_) {}
      if (mounted) setState(() => _draftId = null);
      ref.invalidate(purchaseReturnRecordExtrasProvider);
    }
  }
}

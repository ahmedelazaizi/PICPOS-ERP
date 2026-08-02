part of 'pos_main_screen.dart';

/// يطبّق نتيجة ديالوج «تعديل الصنف» على السلة.
///
/// ── ليه دالة top-level ──────────────────────────────────────────────────────
/// المستدعي الأصلي (`_showEditItemDialog`) كان بيقرا `shouldDelete` و`price`
/// **بس** ويرمي `note` — الكاشير يكتب ملاحظة ويحفظ وهي تتبخّر. اختبار على
/// `updateItemNote` لوحدها كان هيفضل أخضر والباج شغّال، لأن العطل في
/// **التوصيلة** مش في الدالة. الخطوة اتفصلت هنا عشان تتغطّى باختبار من غير
/// تركيب شاشة نقطة بيع كاملة على قاعدة بيانات (مهلة ١٠ دقايق).
///
/// الحذف بيوقف كل حاجة تانية: الصنف مبقاش موجود، فكتابة سعر أو ملاحظة على
/// نفس الـindex بعده بتقع على صنف مختلف.
@visibleForTesting
void applyCartItemEdit(
  CartItemEditData edit, {
  required void Function() onDelete,
  required void Function(double price) onPrice,
  required void Function(String? note) onNote,
}) {
  if (edit.shouldDelete) {
    onDelete();
    return;
  }
  if (edit.price != null) onPrice(edit.price!);
  // بلا فحص null: null معناها «الكاشير مسح الملاحظة» مش «مالهاش لزمة».
  onNote(edit.note);
}

mixin _PosMainDialogsMixin on ConsumerState<PosScreenV2> {
  /// Check if a shift is open for the current user, if not, prompt for opening balance
  Future<void> _ensureShiftOpen() async {
    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final authState = ref.read(authProvider);
      final userId = authState.user?.id ?? 1;

      // Spec 135 NOTE 2 (req 4) — a system-admin login does NOT auto-open its
      // own shift. The admin enters through the previous cashier's OPEN shift
      // (via the closing dialog) to reconcile balances, close it, and record
      // the variances. Cashiers keep the auto-open behaviour below.
      if (authState.isOriginallyAdmin) {
        unawaited(DiagnosticLogger.log('SHIFT-GUARD',
            '_ensureShiftOpen skipped for system admin userId=$userId — '
            'admin attaches to an existing open shift to reconcile/close, '
            'not a new auto-opened shift'));
        return;
      }

      final currentShift = await treasuryRepo.getCurrentOpenShift(userId);
      unawaited(DiagnosticLogger.log('SHIFT-GUARD',
          '_ensureShiftOpen check userId=$userId '
          'openShiftId=${currentShift?.id} '
          'alreadyPrompted=${shiftDialogPromptedUserIds.contains(userId)} '
          'callSite=PosScreenV2.initState'));
      if (currentShift != null) return; // Shift already open

      // Feature 012 / Issue C-SHIFT-LOOP: same-session guard. Once we
      // have already prompted this user in this session, refuse to do
      // it again — even if the lookup transiently returns null. The
      // user will use the manual "فتح الوردية" affordance from the
      // treasury screen if they truly need to reopen.
      if (shiftDialogPromptedUserIds.contains(userId)) {
        unawaited(DiagnosticLogger.log('SHIFT-GUARD',
            '⚠ suppressed re-prompt for userId=$userId '
            '(already prompted in this session) — likely upstream '
            'overwrite of local open-shift row, see ShiftSyncStrategy'));
        return;
      }
      shiftDialogPromptedUserIds.add(userId);

      // Feature 006 #2: properly await the setting future so we don't race
      // the FutureProvider's first load. `ref.read(...).value` returned
      // null on cold-start (provider still loading) and the `?? true`
      // fallback masked toggled-off setups; switch to `.future` so we read
      // the persisted value, not the in-flight AsyncValue.
      final shiftDialogEnabled = await ref.read(posShiftDialogEnabledProvider.future);

      double opening = 0;
      if (!shiftDialogEnabled) {
        opening = 0;
      } else {
        if (!mounted) return;
        final userName = authState.user?.displayName ?? 'كاشير';
        final picked = await showDialog<double>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PosOpeningBalanceDialog(userName: userName),
        );
        opening = picked ?? 0; // Cancel → treat as 0
      }

      // Spec 008 / FR-004: resolve the operating branch so multi-branch
      // users open the shift on their CURRENT branch, not always the
      // first user_branch_access row. Single-branch users get the same
      // value as before (their only branch).
      int? scopedBranchId;
      try {
        final scope = await ref.read(branchScopeProvider.future);
        scopedBranchId = scope.primaryBranchId;
        // Fix: Full-access admins (system admin / مدير النظام) have
        // primaryBranchId=null because BranchScope.fullAccess() sets it
        // to null — no branch restriction. For shift opening we MUST
        // resolve a real branch so the shift close can find the correct
        // safes and the shift reports show the right branch.
        // Fall back to getUserBranchId (first user_branch_access row).
        if (scopedBranchId == null) {
          final db = ref.read(databaseProvider);
          final authState = ref.read(authProvider);
          final uid = authState.user?.id ?? userId;
          scopedBranchId = await db.getUserBranchId(uid);
        }
      } catch (e) {
        debugPrint('openShift: BranchScope lookup failed (non-fatal): $e');
      }


      // Write locally first so the cashier can work immediately even while
      // offline. The local shift ID anchors the rest of the session.
      await treasuryRepo.openShift(userId, opening, branchId: scopedBranchId);

      // Look up the local shift id we just created so it can be passed to the
      // mirror call → ensures the outbox stores it as recordId, which lets
      // OfflineSyncWorker store the local→server FK mapping when the open
      // eventually replays on a real server connection. Without this, the
      // close-shift call later fails with "Shift not found" because the
      // server has its own shiftId that the client never captured.
      // R9 (2026-05-12 fix): also forward the local shift's globalId so the
      // server resolves close-shift by globalId — the previous local→server
      // id-mapping plumbing was bypassed by online opens, causing a
      // recurring "Shift not found" 500 / DEAD-LETTER on every close.
      int? localShiftId;
      String? localShiftGlobalId;
      try {
        final activeShift = await treasuryRepo.getCurrentOpenShift(userId);
        localShiftId = activeShift?.id;
        localShiftGlobalId = activeShift?.globalId;
      } catch (e) {
        debugPrint('openShift: could not fetch local shift id (non-fatal): $e');
      }
      unawaited(DiagnosticLogger.log('SHIFT',
          'New shift opened (PosScreenV2._ensureShiftOpen) '
          'userId=$userId localShiftId=$localShiftId '
          'globalId=$localShiftGlobalId opening=$opening '
          'branchId=$scopedBranchId'));

      // Mirror to server so close-shift later has a matching row there.
      // Previously skipped → server's close handler couldn't find the shift
      // and 500'd with "Shift not found", blocking the sync outbox. In
      // offline/standalone mode this is a no-op (returns null).
      try {
        await ClientWriteInterceptor.openShift(userId, opening,
            localShiftId: localShiftId,
            branchId: scopedBranchId,
            globalId: localShiftGlobalId);
      } catch (e) {
        debugPrint('openShift server mirror failed (non-fatal, will queue): $e');
      }
    } catch (e, st) {
      // Feature 006 #2: surface the failure instead of swallowing it. The
      // operator otherwise sees no shift dialog AND no explanation, and
      // the bug appears identical to "feature broken" even when the real
      // cause is a DB lookup or a server-mirror failure.
      debugPrint('Error ensuring shift open: $e\n$st');
      // Cluster 034 / Issue 1 diag — pipe the actual error into the
      // diagnostic log so the field operator (and we) can see WHY the
      // auto-open failed. Common causes: cash/cash_shortage/cash_surplus
      // accounts not mapped in CoA (treasury_dao.openShift line 217),
      // missing branch row, or a server-mirror failure.
      unawaited(DiagnosticLogger.log(
        'SHIFT-OPEN-FAIL',
        '_ensureShiftOpen threw: $e',
      ));
      if (mounted) {
        // Show the actual error to the operator so they know what to fix.
        // Truncate to keep the toast readable.
        final msg = e.toString();
        final shortMsg = msg.length > 200 ? '${msg.substring(0, 200)}…' : msg;
        AppToast.show(
          context,
          'تعذّر فتح الوردية تلقائياً: $shortMsg',
          type: ToastType.warning,
        );
      }
    }
  }

  void _showOffersDialog() async {
    await PosOffersDialog.show(context);
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showCustomersDialog() async {
    await PosCustomerSelectionDialog.show(context);
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showHeldOrdersDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => HeldOrdersDialog(
        onRetrieve: (id) async {
          await ref.read(cartControllerProvider.notifier).retrieveHeldOrder(id);
          // Focus barcode after retrieve
          if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
        },
      ),
    );
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showPreviousExpensesDialog() async {
    await PosPreviousExpensesDialog.show(context);
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showCashierClosingDialog() async {
    await PosCashierClosingDialog.show(context);
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showPreviousInvoicesDialog() async {
    await PosPreviousInvoicesDialog.show(
      context,
      onEdit: _showEditInvoiceDialog,
      onReprint: (id) => (this as _PosScreenV2State)._reprintInvoice(id),
      onPrintKitchen: (id) => (this as _PosScreenV2State)._printKitchenOrdersForInvoice(id),
    );
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showDeletedItemsDialog() async {
    await PosDeletedItemsDialog.show(context, ref);
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showEditItemDialog(int index) async {
    final cartItems = ref.read(cartControllerProvider).items;
    if (index < 0 || index >= cartItems.length) return;
    final item = cartItems[index];
    final authState = ref.read(authProvider);

    // Check if the ORIGINALLY logged-in user is Admin or Manager — they can
    // edit directly. We deliberately ignore sidebar-level elevation
    // (authState.isAdmin / isManager, which read effectiveRole) so a cashier
    // whose sidebar was unlocked by a walk-through admin still faces a fresh
    // credential prompt for every price edit. See plan: per-action elevation.
    if (!authState.isOriginallyAdmin && !authState.isOriginallyManager) {
      // Cashier needs admin credentials to edit price
      final hasPermission = await _requestAdminCredentials();
      if (!hasPermission) return;
    }

    if (!mounted) return;
    // `itemNote` مش `note`: التاني نص مشتق فيه المعدِّلات كمان، ولو اتعرض في
    // خانة الملاحظة الكاشير هيحفظ «(الحجم: كبير) | 📝 حار» كملاحظة يدوية
    // فتتضاعف المعدِّلات في النص عند أول إعادة تركيب. نفس اللي بيعمله
    // `cart_item_tile.dart` و`cart_item_modifier_panel.dart`.
    final CartItemEditData? editResult = await PosDialogs.showEditCartItem(
      context,
      item.productName,
      item.unitPrice,
      item.itemNote,
    );

    if (editResult != null) {
      final cart = ref.read(cartControllerProvider.notifier);
      applyCartItemEdit(
        editResult,
        onDelete: () => cart.removeFromCart(index),
        onPrice: (price) => cart.updatePrice(index, price),
        onNote: (note) => cart.updateItemNote(index, note),
      );
    }
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  Future<void> _showDeliveryDialog() async {
    final cartState = ref.read(cartControllerProvider);
    final result = await PosDialogs.showDeliveryOptions(
      context,
      ref,
      initialCompanyId: cartState.deliveryCompanyId,
      initialCourierId: cartState.courierId,
      initialFee: cartState.deliveryFee,
      initialStatus: cartState.deliveryStatus ?? 'pending',
    );

    if (result != null) {
      ref
          .read(cartControllerProvider.notifier)
          .setDelivery(
            result.fee,
            companyId: result.companyId,
            courierId: result.courierId,
            status: result.status,
          );
    }
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _showEditInvoiceDialog(SalesInvoiceData invoice) {
    PosEditInvoiceDialog.show(context, invoice: invoice);
  }

  /// Request admin credentials for price edit (cashier override).
  /// Authorizes exactly ONE action — no session elevation.
  Future<bool> _requestAdminCredentials() async {
    return (this as _PosScreenV2State).requestAdminCredentials(
      context: context,
      ref: ref,
    );
  }

}

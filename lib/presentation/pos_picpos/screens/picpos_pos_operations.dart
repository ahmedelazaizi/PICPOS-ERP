part of 'picpos_pos_screen.dart';

/// Operations for the PicPos POS screen.
///
/// ── Why this is a separate, trimmed copy ──────────────────────────────────
/// The UralCash screen's orchestration lives in `pos_main_operations.dart`
/// (799 lines) as a PRIVATE mixin bound to `ConsumerState<PosScreenV2>` that
/// reaches into the state with `(this as _PosScreenV2State)._barcodeFocus` in
/// 28 places. It cannot be called from another class without rewriting it —
/// and rewriting it would mean editing UralCash's most critical screen, which
/// HANDOFF §5 forbids.
///
/// So this is a deliberate, scoped copy: only the flows a `lite` till needs.
/// Dropped entirely — kitchen printing, delivery, offers, table orders,
/// modifiers, quotations, exchange/return conversion. What remains is the
/// money path: add, checkout, save, print, drawer.
///
/// One thing this copy does NOT inherit: the cast-to-concrete-state trick.
/// The mixin declares what it needs as abstract getters, so the coupling is a
/// contract instead of a downcast.
///
/// **If you fix a bug in the payment or save path here, check whether
/// `pos_main_operations.dart` has the same bug.** That is the price of the
/// copy, and it was accepted knowingly.
mixin _PicPosOperations on ConsumerState<PicPosPosScreen> {
  // ── Contract the screen must satisfy ───────────────────────────────────
  TextEditingController get barcodeController;
  FocusNode get barcodeFocus;
  int? get selectedIndex;
  set selectedIndex(int? value);

  void _refocusScanner() {
    if (mounted) barcodeFocus.requestFocus();
  }

  // ── Shift open enforcement ─────────────────────────────────────────────
  //
  // منسوخ حرفياً من `pos_main_dialogs.dart` (`_PosMainDialogsMixin._ensureShiftOpen`)
  // — كان مفقوداً من فورك PicPos POS، فالكاشير في PicPos ما كانش بيشوف ديالوج
  // بدء الوردية عند الدخول زي UralCash (شاشة UralCash POS بتنادي `_ensureShiftOpen`
  // من `initState`؛ الفورك فوّتها فبقى يعتمد على حارس MainScreen وحده اللي بيتخطّى
  // المدير). أي إصلاح منطقي هنا يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٥).
  // يشارك `shiftDialogPromptedUserIds` (حارس الجلسة المشترك) مع حارس MainScreen
  // فمفيش ديالوج مزدوج — أول واحد يفتح بيقيّد المستخدم والتاني بيتخطّى.
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
          'callSite=PicPosPosScreen.initState'));
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
      final shiftDialogEnabled =
          await ref.read(posShiftDialogEnabledProvider.future);

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
        // Full-access admins (system admin) have primaryBranchId=null;
        // fall back to getUserBranchId so the shift close can find the
        // correct safes and the shift reports show the right branch.
        if (scopedBranchId == null) {
          final db = ref.read(databaseProvider);
          final uid = authState.user?.id ?? userId;
          scopedBranchId = await db.getUserBranchId(uid);
        }
      } catch (e) {
        debugPrint('openShift: BranchScope lookup failed (non-fatal): $e');
      }

      // Write locally first so the cashier can work immediately even while
      // offline. The local shift ID anchors the rest of the session.
      await treasuryRepo.openShift(userId, opening, branchId: scopedBranchId);

      // Look up the local shift id/globalId we just created and forward them
      // to the mirror call so close-shift later resolves by globalId (R9 fix
      // for the recurring "Shift not found" 500 / DEAD-LETTER on every close).
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
          'New shift opened (PicPosPosScreen._ensureShiftOpen) '
          'userId=$userId localShiftId=$localShiftId '
          'globalId=$localShiftGlobalId opening=$opening '
          'branchId=$scopedBranchId'));

      // Mirror to server so close-shift later has a matching row there.
      try {
        await ClientWriteInterceptor.openShift(userId, opening,
            localShiftId: localShiftId,
            branchId: scopedBranchId,
            globalId: localShiftGlobalId);
      } catch (e) {
        debugPrint('openShift server mirror failed (non-fatal, will queue): $e');
      }
    } catch (e, st) {
      // Feature 006 #2: surface the failure instead of swallowing it, so the
      // operator sees WHY the auto-open failed (unmapped CoA cash accounts,
      // missing branch row, or a server-mirror failure) rather than "broken".
      debugPrint('Error ensuring shift open: $e\n$st');
      unawaited(DiagnosticLogger.log(
        'SHIFT-OPEN-FAIL',
        '_ensureShiftOpen threw: $e',
      ));
      if (mounted) {
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

  // ── Adding items ───────────────────────────────────────────────────────

  /// Tapping a card in the product grid.
  ///
  /// `cartController.addItem` owns the price level, the stock guard and the
  /// negative-sale policy, so there is nothing to decide here. It refuses
  /// silently for an out-of-stock item (the card already renders «غير متوفر»),
  /// which is why the cart length is compared before and after rather than
  /// assuming the add landed.
  void _handleProductTap(ProductEntity product) {
    final before = ref.read(cartControllerProvider).items.length;
    final stacking = resolveStackingFlags(
      isSoldByWeight: product.isSoldByWeight,
      preventStacking: ref.read(preventItemStackingProvider).value ?? false,
    );
    ref.read(cartControllerProvider.notifier).addItem(
          product,
          forceNewEntry: stacking.forceNewEntry,
          mergeWeight: stacking.mergeWeight,
        );
    final items = ref.read(cartControllerProvider).items;
    if (items.length > before) {
      setState(() => selectedIndex = items.length - 1);
    } else if (items.length == before) {
      // Either merged into an existing line, or refused. Select the line the
      // product is on so the cashier sees what changed either way.
      final idx = items.lastIndexWhere((i) => i.productId == product.id);
      if (idx != -1) {
        setState(() => selectedIndex = idx);
      } else {
        showPosToast(context, ref, 'الصنف غير متوفر في المخزون',
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();
  }

  /// Barcode / internal-code entry. Delegates wholesale to the shared
  /// search controller, which owns scale-label parsing, unit barcodes, offer
  /// barcodes and the client-mode server fallback. Re-implementing any of
  /// that here would be a second, weaker copy of the hardest code in the POS.
  Future<void> _searchBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return;
    await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);

    if (!mounted) return;
    final searchState = ref.read(posSearchControllerProvider);
    final error = searchState.error;
    if (error != null) {
      showPosToast(context, ref, error, type: PosNotificationType.error);
      ref.read(posSearchControllerProvider.notifier).clearSearchResults();
    } else {
      // Successful add — select the last line so F6/F8 act on what was just
      // scanned, which is what the cashier expects.
      final items = ref.read(cartControllerProvider).items;
      if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
    }

    barcodeController.clear();
    _refocusScanner();
  }

  // ── Line operations (F6 / F8) ──────────────────────────────────────────

  void _removeAt(int index) {
    final items = ref.read(cartControllerProvider).items;
    if (index < 0 || index >= items.length) return;
    ref.read(cartControllerProvider.notifier).removeFromCart(index);
    final remaining = ref.read(cartControllerProvider).items.length;
    setState(() {
      selectedIndex = remaining == 0
          ? null
          : (index >= remaining ? remaining - 1 : index);
    });
    _refocusScanner();
  }

  void _deleteSelected() {
    final idx = selectedIndex;
    if (idx == null) {
      showPosToast(context, ref, 'اختر صنفاً أولاً',
          type: PosNotificationType.info);
      return;
    }
    _removeAt(idx);
  }

  Future<void> _editSelected() async {
    final idx = selectedIndex;
    final items = ref.read(cartControllerProvider).items;
    if (idx == null || idx >= items.length) {
      showPosToast(context, ref, 'اختر صنفاً أولاً',
          type: PosNotificationType.info);
      return;
    }
    await _showLineEditDialog(idx, items[idx]);
    _refocusScanner();
  }

  /// Line editor for F6.
  ///
  /// Deliberately NOT the shared `EditCartItemDialog` — that one takes a drift
  /// `Product` plus its `ProductUnit` list and needs two repository round-trips
  /// to open. Everything editable on a lite till (quantity, price, line
  /// discount) is already on the `CartItemEntity`, so this opens instantly and
  /// touches no repository.
  Future<void> _showLineEditDialog(int index, CartItemEntity item) async {
    final qtyCtl =
        TextEditingController(text: NumberUtils.formatQuantity(item.quantity));
    final priceCtl =
        TextEditingController(text: item.effectivePrice.toString());
    final discCtl =
        TextEditingController(text: item.discountPercent.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(item.productName,
              style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الكمية', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'السعر', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الخصم %', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final cart = ref.read(cartControllerProvider.notifier);
      final qty = double.tryParse(qtyCtl.text.trim());
      final price = double.tryParse(priceCtl.text.trim());
      final disc = double.tryParse(discCtl.text.trim());
      if (qty != null && qty > 0) cart.updateQuantity(index, qty);
      if (price != null && price >= 0) cart.updatePrice(index, price);
      if (disc != null && disc >= 0 && disc <= 100) {
        cart.setItemDiscount(index, disc);
      }
    }

    qtyCtl.dispose();
    priceCtl.dispose();
    discCtl.dispose();
  }

  // ── Invoice-level discount ─────────────────────────────────────────────

  Future<void> _editInvoiceDiscount() async {
    final current = ref.read(cartControllerProvider).discountPercent;
    final controller =
        TextEditingController(text: current == 0 ? '' : current.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خصم الفاتورة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'نسبة الخصم %',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) =>
                Navigator.pop(ctx, double.tryParse(v.trim()) ?? current),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(controller.text.trim()) ?? current),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && result >= 0 && result <= 100) {
      ref.read(cartControllerProvider.notifier).setDiscount(result);
    }
    _refocusScanner();
  }

  // ── Checkout (F4) ──────────────────────────────────────────────────────

  Future<void> _handleCheckout() async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      showPosToast(context, ref, 'الفاتورة فارغة',
          type: PosNotificationType.info);
      return;
    }
    if (!await _validateCartBeforeCheckout(cartState)) return;

    // Selling into a closed fiscal year would post a journal entry into a
    // locked period. Fail before taking the customer's money, not after.
    try {
      await ref.read(fiscalPeriodValidationProvider(
        (date: DateTime.now(), operation: 'بيع'),
      ).future);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.lock_clock, color: AppColors.error, size: 26),
              SizedBox(width: 8),
              Text('السنة المالية مغلقة'),
            ]),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final paymentResult = await PosDialogs.showPaymentDialog(
      context,
      totalAmount: cartState.total,
    );
    if (paymentResult == null) {
      _refocusScanner();
      return;
    }

    final success =
        await ref.read(checkoutControllerProvider.notifier).processPayment(
              method: paymentResult.method,
              total: paymentResult.total,
              cashAmount: paymentResult.cashAmount,
              bankAmount: paymentResult.bankAmount,
              clickAmount: paymentResult.clickAmount,
              bankSafeId: cartState.bankSafeId,
              customerId:
                  paymentResult.customerId ?? cartState.selectedCustomerId,
            );

    if (!mounted) return;
    if (success) {
      setState(() => selectedIndex = null);
      // Surface the auto-balance rounding adjustment, same as the UralCash
      // screen — a silent sub-piaster fix is still a fix the operator should
      // be able to see when reconciling.
      final adj = JournalEntryDiagnostics.lastRoundingAdjustment;
      if (adj.abs() > 0.001) {
        showPosToast(
          context,
          ref,
          'تمت تسوية فروقات تقريب ${adj.abs().toStringAsFixed(3)}',
          type: PosNotificationType.info,
        );
      }
      SystemSound.play(SystemSoundType.click);
      barcodeController.clear();
    } else {
      final err =
          ref.read(checkoutControllerProvider).error ?? 'فشل حفظ الفاتورة';
      showPosToast(context, ref, err, type: PosNotificationType.error);
    }
    _refocusScanner();
  }

  /// Blocks nothing outright — zero price or zero quantity is sometimes
  /// deliberate (a giveaway line, a correction). It just refuses to let it
  /// happen silently.
  Future<bool> _validateCartBeforeCheckout(CartState cartState) async {
    final zeroPrice = <String>[];
    final zeroQty = <String>[];
    for (final item in cartState.items) {
      if (item.effectivePrice <= 0) zeroPrice.add(item.productName);
      if (item.quantity <= 0) zeroQty.add(item.productName);
    }
    if (zeroPrice.isEmpty && zeroQty.isEmpty) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 26),
            SizedBox(width: 8),
            Text('أصناف بدون قيمة'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (zeroPrice.isNotEmpty) ...[
                const Text('أصناف بسعر صفر:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroPrice.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
                const SizedBox(height: 8),
              ],
              if (zeroQty.isNotEmpty) ...[
                const Text('أصناف بكمية صفر:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroQty.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
              ],
              const Divider(),
              const Text('هل تريد المتابعة؟',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، تعديل الفاتورة'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white),
              child: const Text('نعم، متابعة'),
            ),
          ],
        ),
      ),
    );
    return proceed == true;
  }

  // ── Save (F2) / print (F3) ─────────────────────────────────────────────

  Future<void> _saveInvoice({required bool printAfter}) async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      showPosToast(context, ref, 'الفاتورة فارغة',
          type: PosNotificationType.info);
      return;
    }
    if (!await _validateCartBeforeCheckout(cartState)) return;

    final success =
        await ref.read(checkoutControllerProvider.notifier).processPayment(
              method: cartState.paymentMethod,
              total: cartState.total,
              cashAmount: cartState.paymentMethod == 'cash'
                  ? cartState.total
                  : 0,
              bankAmount: 0,
              clickAmount: 0,
              bankSafeId: cartState.bankSafeId,
              customerId: cartState.selectedCustomerId,
            );

    if (!mounted) return;
    if (!success) {
      final err =
          ref.read(checkoutControllerProvider).error ?? 'فشل حفظ الفاتورة';
      showPosToast(context, ref, err, type: PosNotificationType.error);
      _refocusScanner();
      return;
    }

    setState(() => selectedIndex = null);
    barcodeController.clear();

    if (printAfter) {
      final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
      if (invoiceId != null) {
        try {
          await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
        } catch (e) {
          if (mounted) {
            showPosToast(context, ref, 'تعذّرت الطباعة: $e',
                type: PosNotificationType.error);
          }
        }
      }
    } else {
      showPosToast(context, ref, 'تم حفظ الفاتورة',
          type: PosNotificationType.success);
    }
    _refocusScanner();
  }

  // ── Cancel the whole invoice (ESC) ─────────────────────────────────────

  Future<void> _cancelInvoice() async {
    final items = ref.read(cartControllerProvider).items;
    if (items.isEmpty) {
      _refocusScanner();
      return;
    }
    final ok = await AppConfirmDialog.show(
      context,
      title: 'إلغاء الفاتورة',
      message: 'سيتم مسح كل الأصناف. متأكد؟',
      confirmLabel: 'إلغاء الفاتورة',
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() => selectedIndex = null);
    barcodeController.clear();
    _refocusScanner();
  }

  // ── Side-panel operations ──────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const PosCustomerSelectionDialog(),
    );
    _refocusScanner();
  }

  Future<void> _showHeldOrders() async {
    await showDialog<void>(
      context: context,
      builder: (_) => HeldOrdersDialog(
        onRetrieve: (orderId) async {
          await ref
              .read(cartControllerProvider.notifier)
              .retrieveHeldOrder(orderId);
          if (mounted) setState(() => selectedIndex = null);
        },
      ),
    );
    _refocusScanner();
  }

  Future<void> _holdOrder() async {
    final items = ref.read(cartControllerProvider).items;
    if (items.isEmpty) {
      showPosToast(context, ref, 'الفاتورة فارغة',
          type: PosNotificationType.info);
      return;
    }
    final err = await ref.read(cartControllerProvider.notifier).holdOrder();
    if (!mounted) return;
    if (err == null) {
      setState(() => selectedIndex = null);
      showPosToast(context, ref, 'تم تعليق الفاتورة',
          type: PosNotificationType.success);
    } else {
      showPosToast(context, ref, err, type: PosNotificationType.error);
    }
    _refocusScanner();
  }

  Future<void> _showExpenses() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const PosPreviousExpensesDialog(),
    );
    _refocusScanner();
  }

  Future<void> _showPreviousInvoices() async {
    await showDialog<void>(
      context: context,
      builder: (_) => PosPreviousInvoicesDialog(
        onReprint: (id) =>
            ref.read(posControllerProvider.notifier).printInvoice(id),
        // Editing a posted invoice is out of the lite scope — the correction
        // path there is a sales return, which lite does ship.
        onEdit: (_) {
          showPosToast(context, ref,
              'تعديل فاتورة مرحّلة غير متاح — استخدم مردود المبيعات',
              type: PosNotificationType.info);
        },
        // No kitchen module in lite.
        onPrintKitchen: (_) {},
      ),
    );
    _refocusScanner();
  }

  /// Drawer printer resolution mirrors the UralCash screen: a drawer-specific
  /// printer wins, then the receipt printer, then the OS default. Tills often
  /// have the drawer wired to the receipt printer's kick port, so the fallback
  /// is the common case rather than an error path.
  Future<String> _drawerPrinterName() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final drawer = await settings.getSetting('cash_drawer_printer');
      if (drawer != null && drawer.isNotEmpty) return drawer;
      final receipt = await settings.getSetting('receipt_printer');
      return receipt ?? 'Default';
    } catch (_) {
      return 'Default';
    }
  }

  Future<void> _openDrawer() async {
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
      final user = ref.read(authProvider).user;
      await ref.read(activityLoggerProvider).logCashDrawerOpen(
            user?.id ?? 0,
            user?.displayName ?? 'مستخدم',
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, 'تعذّر فتح الدرج: $e',
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();
  }
}

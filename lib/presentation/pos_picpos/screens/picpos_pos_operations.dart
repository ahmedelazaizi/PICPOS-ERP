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
///
/// ── الفروق المقصودة عن `pos_main_operations.dart` ─────────────────────────
/// المسارين بقوا شبه توأمين بعد توحيد الدفع (طلبين ١ و ٢)، فالفروق الباقية
/// **كلها مقصودة** ومش سهو نسخ:
///
/// | | PicPos (هنا) | UralCash (`pos_main_operations.dart`) |
/// |---|---|---|
/// | تحقّق الفترة المالية قبل الدفع | ✔ | ✘ |
/// | توست تسوية فروقات التقريب | ✔ | ✘ |
/// | `printKitchenOrders` | ✘ (مفيش مطبخ في lite) | ✔ |
/// | ديالوج تحصيل النقدية | ✔ | ✔ |
/// | «حفظ» بيفتح الدرج | ✘ عن قصد | ✔ |
/// | أزرار طرق الدفع في اللوحة | ✘ (الديالوج بس) | ✔ |
/// | `allowedMethods` على ديالوج الدفع | ✔ | ✘ (`null` = الكل) |
/// | تعديل فاتورة مرحّلة مبوَّب بصلاحية | ✔ | ✘ (بلا بوابة) |
/// | تخطي «غير متوفر» | سؤال صريح → `allowOversell` | ضغط «آجل» قبل السحب |
///
/// أي صف جديد في الجدول ده لازم يكون قرار، مش نتيجة.

/// فحص صريح قبل فتح ديالوج الميزان — نفس الفحص الموجود في
/// `pos_main_operations.dart` (`canOpenPosWeightDialog`)، لكن مكرَّر هنا بدل
/// ما يتشارك، لأن الملفين مكتبتين مختلفتين (`part of` جذور مختلفة) ومفيش
/// نقطة مشتركة موجودة أصلاً بينهم غير النسخ الصريح المقصود لهذا الفورك (زي
/// ما موثّق في تعليق رأس الملف).
@visibleForTesting
bool canOpenPosWeightDialog(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWeightDialog);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد
/// في نقطة الاستدعاء (زي `pos_main_operations.dart`).
@visibleForTesting
Future<bool> ensurePosWeightDialogPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canOpenPosWeightDialog(permissions)) return true;
  if (context.mounted) {
    showPosToast(context, ref, 'ليس لديك صلاحية استخدام الميزان',
        type: PosNotificationType.error);
  }
  return false;
}

// ── صلاحياتُ السلّة ────────────────────────────────────────────────────────
//
// بلاغٌ ميدانيّ (2026-08-11): «رفعتُ التحديد عن حذف صنف من السلة، ودخلتُ
// بالكاشير، فحذف الصنفَ ولم يظهر حوارُ كلمة المرور».
//
// الأربعةُ محروسةٌ في `pos/widgets/cart_item_tile.dart` و`cart_view.dart` —
// وهذه الشاشةُ توأمٌ كُتب من جديدٍ **ولا يستوردهما** (‏السببُ موثَّقٌ في
// `picpos_payment_panel.dart:11`). فنُقل السلوكُ ولم تُنقل الحراسة: لم يكن
// ثمّة تجاوزٌ للصلاحية بل **غيابُ نقطةِ فحصٍ من الأساس**.
//
// دوالُّ قرارٍ خالصةٌ قصداً — تُختبر بلا شجرةِ ودجت، والوصلُ محروسٌ في
// `picpos_permission_parity_test`. ومديرُ النظام يمرّ بلا كودٍ صريحٍ لأن هذه
// ليست عملياتٍ ماليةً حرجة، تماماً كـ`canOpenPosWeightDialog` فوق.

bool _isAdmin(List<String> p) =>
    p.contains('system_admin') || p.contains('*');

/// حذفُ صنفٍ من السلة (`pos_remove_item`).
@visibleForTesting
bool canRemoveCartItem(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posRemoveItem);

/// تفريغُ السلة بالكامل (`pos_clear_cart`).
@visibleForTesting
bool canClearCart(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posClearCart);

/// تعديلُ سعر صنفٍ في البيع (`pos_price_edit`).
@visibleForTesting
bool canEditCartPrice(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posPriceEdit);

/// تعديلُ كميةِ صنفٍ في السلة (`pos_quantity_edit`).
@visibleForTesting
bool canEditCartQuantity(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posQuantityEdit);

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

  /// Hand the till to another cashier. وردية الخارج بتفضل مفتوحة — الديالوج
  /// بيبلّغ بيها بس (`notifyOpenShift`)، ونفس الإشعار بيتنادى عند الخروج.
  Future<void> _switchUser() async {
    // A cart in progress belongs to the outgoing cashier; make them decide
    // what to do with it before the session changes underneath them.
    if (ref.read(cartControllerProvider).items.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('السلة غير فارغة'),
            content: const Text(
              'فيه أصناف في السلة لسه ما اتحفظتش. تحويل المستخدم هيمسحها. '
              'تحب تكمّل؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رجوع'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مسح وتحويل'),
              ),
            ],
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }

    final switched = await PicposSwitchUserDialog.show(context, ref);
    if (!mounted) return;
    if (switched) {
      setState(() => selectedIndex = null);
      showPosToast(
        context,
        ref,
        'تم التحويل إلى ${ref.read(authProvider).effectiveUser?.displayName ?? 'المستخدم الجديد'}',
        type: PosNotificationType.success,
      );

      // ── فتح وردية الكاشير الجديد ─────────────────────────────────────────
      // `_ensureShiftOpen` بتتنادى من `initState` بس، والشاشة **مابتعملش
      // remount** لما التحويل بيحصل في مكانه. فمن غير النداء ده الكاشير الجاي
      // بيقف على تِل **بلا وردية مفتوحة ومحدش بينبّهه**، ومبيعاته تقع بره أي
      // نافذة وردية — يعني تقرير الإغلاق ما يشوفهاش وقائمة «الفواتير السابقة»
      // بترتد لليوم التقويمي.
      //
      // بلا `await` قبل التوست عشان الكاشير يشوف تأكيد التحويل الأول ثم يتصرّف
      // في الوردية.
      await _ensureShiftOpen();
      if (!mounted) return;
      _refocusScanner();
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
  ///
  /// A weighed item cannot be added on a tap alone — it has no quantity until
  /// something weighs it. PicPos used to add it as quantity 1, i.e. one
  /// kilogram of whatever the cashier tapped, while still rendering the scale
  /// badge on the card. The weight prompt below closes that gap; it is the
  /// same `PosDialogs.showWeightInput` UralCash uses, which short-circuits
  /// silently when a live scale is connected and stable.
  Future<void> _handleProductTap(ProductEntity product) async {
    // سؤال «غير متوفر» **أول حاجة**، قبل الميزان وقبل منتقي الوحدة: لو الكاشير
    // قال لا، ما يكونش وزن الصنف واختار وحدته على الفاضي. الفحص ده مكرَّر في
    // `_addToCart` كخط دفاع تاني، ومش بيسأل مرتين — أول موافقة بتفتح
    // `allowOversell` فالنداء التاني ما بيبقى متوقّف أصلاً.
    if (!await _ensureOversellAllowed(product)) {
      _refocusScanner();
      return;
    }
    if (!mounted) return;

    if (product.isSoldByWeight) {
      if (!await ensurePosWeightDialogPermission(ref, context)) {
        _refocusScanner();
        return;
      }
      final weight = await PosDialogs.showWeightInput(context, ref, product);
      // null = cashier cancelled. Adding nothing is the correct outcome.
      if (weight == null || weight <= 0) {
        _refocusScanner();
        return;
      }
      if (!mounted) return;
      await _addProductWithUnits(product, quantity: weight);
      return;
    }
    await _addProductWithUnits(product);
  }

  /// Adds [product] to the cart, offering the unit picker first when the
  /// product is sold in more than one packaging unit.
  Future<void> _addProductWithUnits(
    ProductEntity product, {
    double quantity = 1,
  }) async {
    final units =
        await ref.read(productRepositoryProvider).getProductUnits(product.id);
    if (!mounted) return;

    if (units.length > 1) {
      final selectedUnit = await UnitSelectionDialog.show(
        context,
        productName: product.name,
        units: units,
      );
      // Cancelling the unit picker cancels the whole add — guessing a unit
      // would silently price the line wrong.
      if (selectedUnit == null) {
        _refocusScanner();
        return;
      }
      if (!mounted) return;

      final unitPrice = selectedUnit.salePrice > 0
          ? selectedUnit.salePrice
          : product.salePrice;
      await _addToCart(product, quantity: quantity, customPrice: unitPrice);
      if (!mounted) return;

      final cartItems = ref.read(cartControllerProvider).items;
      if (cartItems.isNotEmpty) {
        ref.read(cartControllerProvider.notifier).updateItemUnit(
              cartItems.length - 1,
              unitId: selectedUnit.id,
              unitName: selectedUnit.unitName,
              quantityInBase: selectedUnit.quantityInBase,
              unitSalePrice: unitPrice,
            );
      }
      return;
    }

    await _addToCart(product, quantity: quantity);
  }

  /// The actual cart write, plus the selection/rejection bookkeeping the
  /// PicPos cart relies on.
  Future<void> _addToCart(
    ProductEntity product, {
    double quantity = 1,
    double? customPrice,
  }) async {
    // ── الرفض بسبب المخزون: نسأل بدل ما نرفض في الصمت ──────────────────────
    // القدرة على بيع صنف غير متوفر كانت موجودة عن طريق ضغط «آجل» قبل السحب
    // (اقرا `CartState.allowOversell`). أزرار الطرق اتشالت من اللوحة، فالمسار
    // ده رجع هنا **صريحاً**: بنسأل في اللحظة اللي الرفض بيحصل فيها، فالقدرة
    // بقت مكتشَفة بدل ما تكون معرفة شفهية.
    if (!await _ensureOversellAllowed(product)) {
      _refocusScanner();
      return;
    }
    if (!mounted) return;

    // Live-scale duplicate-weight guard. Only for the tap → weight-dialog
    // flow: two identical PRE-PRINTED labels are two legitimate weighings,
    // so `searchBarcode` deliberately skips this check. Here, the same
    // (product, weight) twice within 30s usually means the cashier forgot to
    // change the item on the scale.
    bool shouldWarnDuplicate = false;
    if (product.isSoldByWeight && quantity > 0) {
      shouldWarnDuplicate = ref
          .read(posSearchControllerProvider.notifier)
          .checkAndWarnDuplicateWeight(
            productId: product.id,
            productName: product.name,
            weightKg: quantity,
          );
    }

    final before = ref.read(cartControllerProvider).items.length;
    final stacking = resolveStackingFlags(
      isSoldByWeight: product.isSoldByWeight,
      preventStacking: ref.read(preventItemStackingProvider).value ?? false,
    );
    ref.read(cartControllerProvider.notifier).addItem(
          product,
          quantity: quantity,
          forceNewEntry: stacking.forceNewEntry,
          mergeWeight: stacking.mergeWeight,
          customPrice: customPrice,
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
        // مش رفض مخزون — ده اتعامل معاه فوق قبل الإضافة. أي رفض تاني (سعر
        // صفر مرفوض من الـ use case مثلاً) بيوصل هنا.
        showPosToast(context, ref, 'تعذّرت إضافة الصنف',
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();

    // Raised AFTER the add so the cart reflects reality when the cashier
    // acknowledges. The item stays in the cart either way — the popup only
    // makes sure a repeated weight cannot go unnoticed.
    if (shouldWarnDuplicate && mounted) {
      final msg = ref.read(posSearchControllerProvider).duplicateWeightWarning;
      // Cleared immediately so a follow-up add with a new weight doesn't
      // re-trigger the popup from stale state.
      ref
          .read(posSearchControllerProvider.notifier)
          .clearDuplicateWeightWarning();
      if (msg != null) _showDuplicateWeightDialog(msg);
    }
  }

  /// يتأكد إن [product] مسموح إضافته رغم إن مخزونه صفر أو أقل.
  ///
  /// `true` = كمّل الإضافة (مش مرفوض أصلاً، أو الكاشير سمح). `false` = وقف.
  ///
  /// ── ليه في اللحظة دي مش في إعداد ─────────────────────────────────────────
  /// المسار القديم كان «اضغط آجل قبل ما تسحب» — معرفة شفهية، ومربوطة بقرار
  /// مالي مالوش علاقة. والسؤال في لحظة الرفض هو أوضح مكان ممكن يتحط فيه:
  /// الكاشير شايف الصنف اللي اتوقف، وشايف الرصيد الحقيقي، وبياخد القرار وهو
  /// عارف نتيجته.
  ///
  /// السماح بيفضل مفتوح **لباقي الفاتورة** (`CartState.allowOversell`)، فمفيش
  /// سؤال متكرر على كل صنف في نفس البيعة. و`clearCart` بيصفّره.
  ///
  /// المحلات اللي البيع بالسالب عندها روتين بتفتح `enable_negative_sales` على
  /// مستوى التركيب — ساعتها الحارس ما بيوقفش أصلاً وما بيظهرش أي سؤال.
  Future<bool> _ensureOversellAllowed(ProductEntity product) async {
    final cart = ref.read(cartControllerProvider.notifier);
    final globalNegativeSales =
        ref.read(enableNegativeSalesProvider).value ?? false;

    if (!cart.isBlockedByStock(product,
        globalNegativeSales: globalNegativeSales)) {
      return true;
    }
    if (!mounted) return false;

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(PhosphorIconsBold.warningDiamond,
                color: AppColors.warning, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('الصنف غير متوفر')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: PicPosText.v(15)),
              const SizedBox(height: 6),
              Text(
                'الرصيد الحالي: ${NumberUtils.formatQuantity(product.currentStock)}',
                style: PicPosText.v(13, color: AppColors.error),
              ),
              const Divider(height: 18),
              Text(
                'تسمح بالبيع بالسالب في هذه الفاتورة؟ الرصيد هيبقى سالب '
                'ولازم جرد يصحّحه.',
                style: PicPosText.l(13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('لا', style: PicPosText.l(14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('نعم، اسمح بالسالب'),
            ),
          ],
        ),
      ),
    );

    if (approved != true) return false;
    cart.setAllowOversell(true);
    return true;
  }

  /// Blocking popup for a repeated live-scale weight. The single button just
  /// acknowledges — the cart keeps the item.
  Future<void> _showDuplicateWeightDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(PhosphorIconsBold.warning,
              color: AppColors.warning, size: 44),
          title: const Text(
            'تنبيه: نفس الوزن',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    _refocusScanner();
  }

  /// Barcode / internal-code entry. Delegates wholesale to the shared
  /// search controller, which owns scale-label parsing, unit barcodes, offer
  /// barcodes and the client-mode server fallback. Re-implementing any of
  /// that here would be a second, weaker copy of the hardest code in the POS.
  Future<void> _searchBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return;

    // إجمالي الكميات قبل السحب — اقرا `_scanWasRefused` تحت.
    final qtyBefore = _totalCartQuantity();

    await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);

    if (!mounted) return;
    final searchState = ref.read(posSearchControllerProvider);
    final error = searchState.error;
    if (error != null) {
      showPosToast(context, ref, error, type: PosNotificationType.error);
      ref.read(posSearchControllerProvider.notifier).clearSearchResults();
    } else if (_totalCartQuantity() == qtyBefore) {
      await _handleSilentlyRefusedScan(barcode);
    } else {
      // Successful add — select the last line so F6/F8 act on what was just
      // scanned, which is what the cashier expects.
      final items = ref.read(cartControllerProvider).items;
      if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
    }

    barcodeController.clear();
    _refocusScanner();
  }

  double _totalCartQuantity() => ref
      .read(cartControllerProvider)
      .items
      .fold<double>(0, (sum, i) => sum + i.quantity);

  /// مسحة رجعت «نجاح» ومغيّرتش السلة.
  ///
  /// ── إزاي عرفنا ───────────────────────────────────────────────────────────
  /// متحكّم البحث المشترك بينادي `addItem` ثم يزمّر نجاح **بلا ما يتأكد** إن
  /// الإضافة نزلت (٦ مواضع نداء فيه، كلها بنفس الشكل). فصنف مخزونه صفر بيتمسح،
  /// الزمّور يقول تم، والسلة زي ما هي. باج قائم مشترك مع UralCash، بس بقى باين
  /// أكتر هنا بعد ما مسار الضغط على الكارت بقى بيسأل.
  ///
  /// المقارنة بإجمالي **الكميات** مش عدد السطور: الدمج في سطر موجود («منع
  /// تراكم الأصناف» مقفول) بيزوّد كمية وما بيزوّدش سطر.
  ///
  /// ── وليه لازم نتحقّق قبل ما نتكلّم ────────────────────────────────────────
  /// «السلة ما اتغيرتش» **مش** معناها رفض مخزون بالضرورة: `applyOffer` بترجع
  /// بلا إضافة لو العرض مضاف قبل كده أو لو ما طلّعش أصناف. فتوست «الصنف غير
  /// متوفر» على مسح باركود عرض مرتين كان هيبقى كذب. فبندوّر على الصنف بنفسنا
  /// ونتأكد إنه **فعلاً** متوقّف بالمخزون قبل أي كلام.
  ///
  /// ولو الكاشير سمح، بنعيد نداء `searchBarcode` بنفس الباركود بدل ما نضيف
  /// إحنا: المتحكّم ده بيفهم باركود الميزان وباركود الوحدات والعروض، وإعادة
  /// النداء بتستفيد من ده كله. مرة واحدة بس — مفيش لوب.
  Future<void> _handleSilentlyRefusedScan(String barcode) async {
    final blocked = await _blockedProductForBarcode(barcode);
    // مش رفض مخزون (عرض مكرّر، باركود مالوش صنف، …) — المتحكّم اتعامل معاه.
    if (blocked == null || !mounted) return;

    if (!await _ensureOversellAllowed(blocked)) return;
    if (!mounted) return;

    await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);
    if (!mounted) return;
    final items = ref.read(cartControllerProvider).items;
    if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
  }

  /// يرجّع الصنف اللي الباركود ده بيشاور عليه **لو** حارس المخزون بيوقفه، وإلا
  /// `null`.
  ///
  /// ── باركود الميزان ───────────────────────────────────────────────────────
  /// باركود الميزان (EAN-13 بيبدأ بـ `2` وجواه الـ PLU والوزن مدسوسين) **عمره
  /// ما بيتطابق خام** مع باركود صنف أو كوده — الرقم اللي على الملصق بيتغيّر مع
  /// كل وزنة. فبنفكّه الأول بـ [ScaleBarcodeHandler.tryParse]، وهو **نفس**
  /// المُفكِّك اللي متحكّم البحث المشترك بيستعمله: بيقرأ بروفايل الميزان من
  /// الإعدادات، ويجرّب الـ PLU بالكود وبالباركود وبـ `getProductByScalePlu`.
  /// إعادة استخدامه معناها إن الصنف اللي بنسأل عنه هو **بالظبط** الصنف اللي
  /// المتحكّم حاول يضيفه ورفضه — نسخة تانية من التفكيك كانت هتفتح باب إننا
  /// نسأل عن صنف والرفض حصل لصنف تاني.
  ///
  /// `tryParse` قراءة بحتة (بيرجّع نتيجة، والإضافة شغل المستدعي) فنداؤه هنا على
  /// مسار الفشل مالوش أي أثر جانبي.
  ///
  /// ولو مش باركود ميزان بيرجع `null` بسرعة، وساعتها بندوّر بالباركود ثم بالكود
  /// — نفس أول خطوتين في المتحكّم.
  Future<ProductEntity?> _blockedProductForBarcode(String barcode) async {
    try {
      final code = barcode.trim();
      ProductEntity? product;

      final scaleResult = await ScaleBarcodeHandler.tryParse(
        RepositoryBarcodeAdapter(ref),
        code,
      );
      product = scaleResult?.product;
      product ??= await ref.read(productRepositoryProvider)
          .getProductByBarcode(code);
      product ??=
          await ref.read(productRepositoryProvider).getProductByCode(code);
      if (product == null) return null;

      final globalNegativeSales =
          ref.read(enableNegativeSalesProvider).value ?? false;
      final blocked = ref.read(cartControllerProvider).blocksAdd(
            product,
            globalNegativeSales: globalNegativeSales,
          );
      return blocked ? product : null;
    } catch (e) {
      debugPrint('[PicPos-Scan] تعذّر التحقّق من سبب الرفض: $e');
      return null;
    }
  }

  // ── Line operations (F6 / F8) ──────────────────────────────────────────

  /// يطلب موافقةَ مسؤولٍ حين ينقص المستخدمَ الكودُ — ويرجع `false` لو رُفض.
  ///
  /// اختيارُ المالك (2026-08-12): **حوارُ كلمة المرور على كلّ رفض**، لا على
  /// المالية الحرجة وحدَها. فالفعلُ الممنوع يمرّ بموافقة مسؤولٍ حاضرٍ يملك
  /// الصلاحيةَ بنفسه — و`requestManagerApproval` يشترط ذلك ولا يكتفي بأنه
  /// مدير. والموافقةُ وحيدةُ الاستعمال ولا تُصعّد الجلسة.
  Future<bool> _ensureCartPermission(
    bool Function(List<String>) can,
    String permission,
    String actionName,
  ) async {
    final perms = ref.read(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    if (can(perms)) return true;
    if (!mounted) return false;
    return requestManagerApproval(
      context,
      actionName: actionName,
      permission: permission,
    );
  }

  Future<void> _removeAt(int index) async {
    final items = ref.read(cartControllerProvider).items;
    if (index < 0 || index >= items.length) return;
    if (!await _ensureCartPermission(
      canRemoveCartItem,
      PermissionCodes.posRemoveItem,
      'حذف صنف من السلة',
    )) {
      return;
    }
    if (!mounted) return;
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
      // كلٌّ على حدة: الحوارُ يعدّل الثلاثةَ معاً، فمن يملك تعديلَ الكمية
      // ولا يملك تعديلَ السعر يجب أن يمرّ الأولُ ويُستأذَن في الثاني — لا
      // أن يسقط الاثنان ولا أن يمرّا معاً.
      final current = ref.read(cartControllerProvider).items[index];
      if (qty != null && qty > 0 && qty != current.quantity) {
        if (await _ensureCartPermission(
          canEditCartQuantity,
          PermissionCodes.posQuantityEdit,
          'تعديل الكمية',
        )) {
          cart.updateQuantity(index, qty);
        }
      }
      if (price != null && price >= 0 && price != current.effectivePrice) {
        if (await _ensureCartPermission(
          canEditCartPrice,
          PermissionCodes.posPriceEdit,
          'تعديل سعر الصنف',
        )) {
          cart.updatePrice(index, price);
        }
      }
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

  // ── مسار الدفع الموحَّد (F4 دفع · F2 حفظ) ───────────────────────────────

  /// `دفع F4` — حفظ + طباعة + فتح الدرج (طلب ١).
  Future<void> _handleCheckout() => _processPaymentAndSave(printAfter: true);

  /// `حفظ F2` — حفظ فقط: بلا طباعة وبلا درج.
  Future<void> _saveOnly() => _processPaymentAndSave(printAfter: false);

  /// المسار الوحيد اللي أي فاتورة بيع بتخرج منه من شاشة PicPos.
  ///
  /// ── ليه مسار واحد بدل مسارين ──────────────────────────────────────────
  /// كان فيه `_handleCheckout` (بديالوج دفع) و `_saveInvoice` (بلا ديالوج،
  /// بترحّل بـ `cartState.paymentMethod` مباشرة). التقسيم ده كان سليم وقت ما
  /// كان صف طرق الدفع موجود في اللوحة، لأن الكاشير كان بيختار الطريقة هناك
  /// قبل ما يضغط حفظ.
  ///
  /// بعد ما الصف اتشال (طلب ٢) بقت `cart.paymentMethod` هي الافتراضي `'cash'`
  /// لكل فاتورة غير منصات — فـ«حفظ» كانت هترحّل **كل** المبيعات نقدي، بما فيها
  /// بيعة بطاقة، بلا أي إشارة للكاشير. فالمسارين اتوحّدوا: الاتنين بيمرّوا
  /// بالديالوج، والفرق الوحيد بينهم بقى [printAfter].
  ///
  /// ── الفروق المقصودة عن `pos_main_operations._processPaymentAndSave` ────
  /// • هنا فيه تحقّق فترة مالية قبل الدفع — UralCash مالهاش.
  /// • هنا فيه توست تسوية التقريب — UralCash مالهاش.
  /// • مفيش `printKitchenOrders` — مفيش موديول مطبخ في lite.
  /// • `حفظ` هنا **ما بيفتحش الدرج**؛ في UralCash بيفتحه. الزرين لازم يفرقوا،
  ///   ودرج بيفتح بلا فلوس بيدرّب الكاشير إنه يتجاهل الركلة.
  Future<void> _processPaymentAndSave({required bool printAfter}) async {
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

    // بوابة `pos_save` — منقولة من UralCash. الفورك ده كان **بلا أي إنفاذ**
    // لصلاحية الحفظ: سحب الصلاحية من الكاشير ما كانش بيمنعه من إتمام بيعة.
    if (!await _userHasPermissionFresh(PermissionCodes.posSave)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'حفظ فاتورة نقطة البيع',
        permission: PermissionCodes.posSave,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    final total = cartState.total;

    // شركات التوصيل بتتحاسب آجل. القيد ده كان عايش كـ `creditOnly` في صف طرق
    // الدفع في اللوحة؛ الصف اتشال، فالقيد نزل هنا — على مسار الكتابة، فما
    // يقدرش يتفوّت.
    final isPlatform =
        ['talabat', 'careem', 'ashyae'].contains(cartState.priceLevel);
    final isCredit = cartState.paymentMethod == 'credit';

    // ── ليه متغيّرات مفكوكة ومش كائن `PaymentResult` ──────────────────────
    // الشاشة بتستورد `pos_dialogs.dart` بـ `hide PaymentResult`، فالنوع نفسه
    // مش قابل للتسمية هنا. ومسار المنصات مالوش داعي يبني كائن من الأساس —
    // قيمه كلها معروفة مقدماً. فالمتغيّرات المفكوكة بتحل الاتنين.
    final String method;
    final double paidTotal;
    final double? cashAmount;
    final double? bankAmount;
    final double? clickAmount;
    final int? resultCustomerId;

    if (isPlatform && isCredit) {
      method = 'credit';
      paidTotal = total;
      cashAmount = 0;
      bankAmount = 0;
      clickAmount = 0;
      resultCustomerId = cartState.selectedCustomerId;
    } else {
      final result = await PosDialogs.showPaymentDialog(
        context,
        totalAmount: total,
        initialMethod: isPlatform ? 'credit' : 'cash',
        allowedMethods: await _allowedPaymentMethods(isPlatform: isPlatform),
      );
      if (result == null || !mounted) {
        _refocusScanner();
        return;
      }
      method = result.method;
      paidTotal = result.total;
      cashAmount = result.cashAmount;
      bankAmount = result.bankAmount;
      clickAmount = result.clickAmount;
      resultCustomerId = result.customerId;
    }

    // لازم تتكتب على السلة: شاشة العميل (CFD) وشيب الصندوق وفحص «غير متوفر
    // على الآجل» كلهم بيقروا من `cart.paymentMethod`. الفورك ده كان ناسيها،
    // فالسلة والفاتورة المرحّلة كانوا بيختلفوا.
    ref.read(cartControllerProvider.notifier).setPaymentMethod(method);

    // عرض الفكة للعميل (طلب ٢). الصندوق الأخضر «الباقي للعميل (فكة)» جوه
    // ديالوج الدفع متعشّش في فرع `multiple` بس، فمسار النقدي مالوش أي عرض
    // للفكة. نفس حل UralCash: ديالوج تحصيل النقدية بخانة المستلم وأزرار الفئات.
    if (method == 'cash') {
      final confirmed =
          await PosCashTenderingDialog.show(context, totalAmount: total);
      if (confirmed != true || !mounted) {
        _refocusScanner();
        return;
      }
    }

    final bankSafeId = await _ensureBankSafeSelected(
      method,
      bankAmount: bankAmount,
      clickAmount: clickAmount,
    );
    if (!mounted) return;

    final success =
        await ref.read(checkoutControllerProvider.notifier).processPayment(
              method: method,
              total: paidTotal,
              cashAmount: cashAmount,
              bankAmount: bankAmount,
              clickAmount: clickAmount,
              bankSafeId: bankSafeId,
              customerId: resultCustomerId ?? cartState.selectedCustomerId,
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

    if (printAfter) {
      // الدرج بيتركل **بالتوازي** مع الطباعة مش بعدها: الركلة بتروح للطابعة
      // على نفس المنفذ، وتسلسلهم كان بيضيف زمن ميت على مسار حرج.
      final drawerFuture = _openCashDrawerQuietly();
      final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
      final printed = invoiceId != null && await _hasReceiptPrinter()
          ? await _tryPrintReceipt(invoiceId)
          : false;
      await drawerFuture;
      if (mounted) {
        showPosToast(
          context,
          ref,
          printed ? 'تم حفظ وطباعة الفاتورة' : 'تم حفظ الفاتورة',
          type: PosNotificationType.success,
        );
      }
    } else {
      showPosToast(context, ref, 'تم حفظ الفاتورة',
          type: PosNotificationType.success);
    }
    _refocusScanner();
  }

  /// هل فيه طابعة إيصالات مضبوطة فعلاً؟
  ///
  /// ── ليه الفحص ده موجود ────────────────────────────────────────────────────
  /// `printInvoice` **مابيرميش** لما مفيش طابعة مضبوطة — بيسقط على
  /// `Printing.layoutPdf` اللي بيفتح **ديالوج الطباعة بتاع النظام**
  /// (`printer_resolver.dart:32` وتعليقه: «caller will show print dialog»).
  ///
  /// ده كان مقبول وقت ما الطباعة كانت زرار منفصل الكاشير بيختاره. بعد طلب ١
  /// بقت الطباعة جزء من `دفع` — أي **كل بيعة**. فعلى تركيب لسه ما ضبطش طابعته
  /// (أو محل مالوش طابعة إيصالات أصلاً) كل بيعة كانت هتتوقف على ديالوج طباعة
  /// لازم حد يقفله باليد. ده مش تعطيل للقرار، ده حماية له: «دفع بيطبع» تفضل
  /// صح لما فيه طابعة، وتفضل صامتة لما مفيش.
  ///
  /// المرجع هو `pos_receipt` في مستودع الطابعات — نفس المفتاح اللي
  /// `PrinterResolver.resolveReceiptPrinter` بيسأل عنه، فمفيش مصدر تاني للحقيقة.
  Future<bool> _hasReceiptPrinter() async {
    try {
      final printer = await ref
          .read(printersRepositoryProvider)
          .getActivePrinterByPurpose('pos_receipt');
      if (printer == null) {
        debugPrint('[PicPos-Print] مفيش طابعة إيصالات مضبوطة — تم تخطي الطباعة');
      }
      return printer != null;
    } catch (e) {
      // فشل قراءة الإعداد ما يصحّش يمنع الطباعة — نحاول ونسيب معالج الخطأ يتصرّف.
      debugPrint('[PicPos-Print] تعذّر فحص الطابعة: $e — هنحاول الطباعة');
      return true;
    }
  }

  /// يطبع الإيصال ويرجّع هل نجح. الفاتورة **مترحّلة** بالفعل قبل النداء ده.
  ///
  /// فشل الطباعة تحذير، **لا تراجع** — إلغاء بيعة محصَّلة عشان ورق ناقص أسوأ
  /// بكتير من إيصال مش مطبوع.
  Future<bool> _tryPrintReceipt(int invoiceId) async {
    try {
      await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
      return true;
    } catch (e) {
      debugPrint('[PicPos-Print] فشلت طباعة الفاتورة #$invoiceId: $e');
      if (mounted) {
        showPosToast(context, ref,
            '⚠️ الحفظ تم، لكن فشلت الطباعة (تأكد من الورق)',
            type: PosNotificationType.warning);
      }
      return false;
    }
  }

  /// فحص صلاحية طازة — منقول من `pos_main_operations._userHasPermissionFresh`.
  ///
  /// بيستهلك توكن موافقة المدير المرتبط بالفعل الأول (فالكاشير ما يتسألش كلمة
  /// المرور مرتين لنفس الزر)، وبعدها بيبطّل كاش الصلاحيات عشان تغيير المدير
  /// يسري بلا تسجيل خروج، وبيحترم تخطي مدير النظام إلا للعمليات المالية
  /// الحرجة. **مش** بيقرأ أي علم ترقية جلسة: كلمة مرور واحدة ما يصحّش تفتح كل
  /// الأفعال المحمية لباقي الجلسة.
  Future<bool> _userHasPermissionFresh(String permissionCode) async {
    if (ManagerApprovalCache.instance.consume(permissionCode)) return true;

    ref.invalidate(currentUserPermissionsProvider);
    final codes = await ref.read(currentUserPermissionsProvider.future);

    if (codes.contains(permissionCode)) return true;

    final isSystemAdmin =
        codes.contains('system_admin') || codes.contains('*');
    final isCriticalFin =
        PermissionCodes.criticalFinancialOps.contains(permissionCode);
    return isSystemAdmin && !isCriticalFin;
  }

  /// طرق الدفع المسموح بها للمستخدم الحالي.
  ///
  /// أكواد الصلاحيات دي كانت بتُنفَّذ بـ `PermissionGuard` حوالين كل زر طريقة
  /// في لوحة الدفع. الأزرار اتشالت (طلب ٢)، فالإنفاذ نزل هنا — نقطة الاختيار
  /// الوحيدة الباقية. مفيش واحدة من الخمس في `criticalFinancialOps`، فتخطي
  /// مدير النظام مُعاد بالحرف زي `PermissionGuard`.
  Future<Set<String>> _allowedPaymentMethods({
    required bool isPlatform,
  }) async {
    // عميل منصة = آجل وبس. بنرجّعها قبل قراءة الصلاحيات: القيد ده على مستوى
    // العميل مش على مستوى المستخدم.
    if (isPlatform) return {'credit'};

    const codeFor = {
      'cash': PermissionCodes.posPaymentCash,
      'card': PermissionCodes.posPaymentCard,
      'click': PermissionCodes.posPaymentTransfer,
      'credit': PermissionCodes.posPaymentCredit,
      'multiple': PermissionCodes.posPaymentMultiple,
    };

    try {
      final codes = await ref.read(currentUserPermissionsProvider.future);
      if (codes.contains('system_admin') || codes.contains('*')) {
        return codeFor.keys.toSet();
      }
      return codeFor.entries
          .where((e) => codes.contains(e.value))
          .map((e) => e.key)
          .toSet();
    } catch (_) {
      // فشل قراءة الصلاحيات ما يصحّش يقفل التِل. نرجّع `null`-المعنى (الكل)
      // عن طريق كل المفاتيح — نفس اللي كان بيحصل قبل الطلب ده.
      return codeFor.keys.toSet();
    }
  }

  /// يضمن إن فاتورة بنكية ليها خزنة بنك محدَّدة **قبل** الترحيل.
  ///
  /// اختيار البنك كان عايش في صف طرق الدفع في اللوحة، والصف اتشال. لو اعتمدنا
  /// على الشيب في اللوحة وحده، كاشير اختار «بطاقة» من الديالوج ومحدَّدش بنك
  /// كانت الفاتورة تترحّل على الخزنة الافتراضية بلا ما حدّ يقصد. فالضمانة نزلت
  /// على مسار الكتابة: واحدة → تلقائي، أكتر → نسأل، ولا شيء → `null` ويتولّى
  /// الـ DAO الاحتياطي (نفس سلوك UralCash بالحرف).
  ///
  /// ── ليه المبالغ داخلة في القرار ──────────────────────────────────────────
  /// `card` و `click` المفردين بيرجّعوا مبالغ `null` من الديالوج (الـ DAO
  /// بيستنتج التوزيع من الطريقة نفسها)، فالطريقة لوحدها هي الإشارة. أما `mixed`
  /// فبيرجّع أرقام حقيقية — وتقسيم **نقدي بالكامل** مالوش أي جزء بنكي، فسؤال
  /// الكاشير «اختر البنك» فيه كان هيبقى سؤال بلا معنى.
  Future<int?> _ensureBankSafeSelected(
    String method, {
    double? bankAmount,
    double? clickAmount,
  }) async {
    final isBank = method == 'card' ||
        method == 'click' ||
        (method == 'mixed' &&
            ((bankAmount ?? 0) > 0 || (clickAmount ?? 0) > 0));
    if (!isBank) return ref.read(cartControllerProvider).bankSafeId;

    final safes = await ref.read(branchBankSafesProvider.future);
    final current = ref.read(cartControllerProvider).bankSafeId;

    if (safes.isEmpty) return null;
    if (safes.length == 1) {
      ref.read(cartControllerProvider.notifier).setBankSafe(safes.first.id);
      return safes.first.id;
    }
    if (current != null && safes.any((s) => s.id == current)) return current;
    if (!mounted) return null;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر الحساب البنكي'),
          children: [
            for (final safe in safes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, safe.id),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.bank,
                        size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(child: Text(safe.name)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(cartControllerProvider.notifier).setBankSafe(picked);
    }
    return picked;
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
    if (!await _ensureCartPermission(
      canClearCart,
      PermissionCodes.posClearCart,
      'تفريغ السلة',
    )) {
      return;
    }
    if (!mounted) return;
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() => selectedIndex = null);
    barcodeController.clear();
    _refocusScanner();
  }

  // ── Side-panel operations ──────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    // `pos_customer_select` كان محروساً في `pos/widgets/cart/
    // cart_totals_panel.dart` وحدَه — شاشةٌ لا يصل إليها PicPos.
    if (!await ensureSelectCustomerPermission(ref, context)) return;
    if (!mounted) return;
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

  /// «الفاتورة السابقة» — زر صف الأزرار، و F3، ورقم الفاتورة في الترويسة،
  /// كلهم بيوصّلوا هنا.
  Future<void> _showLastInvoice() async {
    await PicPosLastInvoiceDialog.show(context);
    _refocusScanner();
  }

  Future<void> _showPreviousInvoices() async {
    // `pos_previous_invoices` — ليست عرضاً بريئاً: تكشف مبيعاتِ الورديات
    // الأخرى وأسعارَها وعملاءَها.
    if (!await ensurePreviousInvoicesPermission(ref, context)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PosPreviousInvoicesDialog(
        onReprint: (id) =>
            ref.read(posControllerProvider.notifier).printInvoice(id),
        onEdit: _editPostedInvoice,
        // No kitchen module in lite.
        onPrintKitchen: (_) {},
      ),
    );
    _refocusScanner();
  }

  /// تعديل **طريقة دفع** فاتورة مرحّلة + ملاحظاتها (طلب ٥).
  ///
  /// ── إيه اللي بيتعدَّل وإيه اللي لأ ────────────────────────────────────────
  /// طريقة الدفع والملاحظات والتقسيم بس. **الأصناف والكميات لأ** — تصحيحها
  /// طريقه مردود مبيعات، وده اللي كانت الشاشة دي بتقوله في توست قبل الطلب ده.
  /// الحاجة اللي كانت ناقصة فعلاً هي الحالة الشائعة: الكاشير اختار «نقدي» وهو
  /// كان لازم «بطاقة»، والفاتورة كلها صح ما عدا ده.
  ///
  /// ── ليه بوابة صلاحية إجبارية ─────────────────────────────────────────────
  /// الفعل ده **بيحرّك فلوس ويعيد كتابة دفتر الأستاذ**: الـ DAO بيحذف القيد
  /// القديم ويسجّل واحد جديد وينقل أرصدة الخزن
  /// (`sales_mutations_dao.updateSalesInvoicePayment`). ده مش فعل كاشير عادي،
  /// فبيمر بنفس فحص الصلاحية الطازة اللي الحفظ بيمر بيه، وإلا موافقة مدير.
  ///
  /// تحقّق الفترة المالية موجود جوه الـ DAO أصلاً فمش بنكرّره هنا.
  Future<void> _editPostedInvoice(SalesInvoiceData invoice) async {
    if (!await _userHasPermissionFresh(PermissionCodes.posEditInvoice)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'تعديل طريقة دفع فاتورة مرحّلة',
        permission: PermissionCodes.posEditInvoice,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    await PosEditInvoiceDialog.show(context, invoice: invoice);
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

  /// زر `الدرج` الصريح — الكاشير طلب الفتح، ففشله لازم يقول.
  Future<void> _openDrawer() async {
    // الفتحُ اليدويُّ يفتح الدرجَ **بلا بيعة** — وهو ما يُراقَب. والركلةُ
    // التلقائيةُ على مسار الدفع (`_openCashDrawerQuietly`) لا تُحرَس عن قصد:
    // جزءٌ من إتمام بيعةٍ مأذونةٍ سلفاً، وحراستُها توقف الكاشيرَ في منتصف كلّ
    // فاتورة.
    if (!await ensureOpenCashDrawerPermission(ref, context)) return;
    if (!mounted) return;
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

  /// الركلة الصامتة على مسار `دفع`.
  ///
  /// ── ليه صامتة ────────────────────────────────────────────────────────────
  /// الفاتورة اتحصّلت واتطبعت خلاص. توست أحمر عن الدرج على تِل مالوش درج أصلاً
  /// (وده تركيب شائع) كان معناه تحذير مع **كل** بيعة، والكاشير بيتعلّم يتجاهل
  /// التوستات كلها — بما فيها اللي بتقول إن الطباعة فشلت. الفشل بيتسجّل في
  /// `debugPrint` وخلاص. زر `الدرج` الصريح فوق هو اللي بيبلّغ.
  Future<void> _openCashDrawerQuietly() async {
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
    } catch (e) {
      debugPrint('[PicPos-Drawer] فشل تشغيل الدرج: $e');
    }
  }
}

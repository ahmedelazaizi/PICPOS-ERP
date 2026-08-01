// ignore_for_file: avoid_dynamic_calls
part of 'pos_main_screen.dart';

/// UralCash POS orchestration.
///
/// ── هناك فورك تاني لمسار الدفع ────────────────────────────────────────────
/// `lib/presentation/pos_picpos/screens/picpos_pos_operations.dart` فيه نسخة
/// مقلَّمة من نفس المسار لشاشة PicPos، وبعد توحيد الدفع هناك بقى
/// `_processPaymentAndSave` في الملفين شبه متطابقة. **أي إصلاح في مسار الدفع
/// أو الحفظ هنا لازم يتراجع هناك كذلك** — وجدول الفروق المقصودة (اللي مش
/// المفروض تتوحّد) موجود في تعليق رأس ذلك الملف.
///
/// ── وفيه فورك تالت للمنتج نفسه ─────────────────────────────────────────────
/// `lib/presentation/pos/screens/table_pos_operations.dart` (جوه
/// `TablePosScreen`، خدمة الطاولات) عنده نسخته الخاصة من `_handleProductTap`
/// برضه — مكتشفة متأخر (مراجعة Task 7 لقت `pos_weight_dialog` هناك من غير
/// حماية خالص لأن التريَّاج الأول عدّ فورك ين بس). أي فحص صلاحية على فتح
/// ديالوج المنتج (ميزان، تعديل، إلخ) لازم يتأكد إنه موجود في **التلاتة**
/// الأفرع دي، مش اتنين بس.
@visibleForTesting
bool canOpenPosWeightDialog(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWeightDialog);
}

/// نسخة أعلى مستوى من `canOpenPosWeightDialog` بتقرا الصلاحيات من `ref`
/// وتعرض توست الرفض بنفسها — سطر واحد في نقطة الاستدعاء بدل ٣ (فحص + شرط +
/// توست)، عشان التعديل اللي يشيل الحماية يبقى أوضح في الـdiff وأصعب إنه
/// يحصل بالغلط جزئياً (زي ما لو حد شال الـreturn بس وسايب التوست).
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
    showPosToast(
      context,
      ref,
      'ليس لديك صلاحية استخدام الميزان',
      type: PosNotificationType.error,
    );
  }
  return false;
}

/// فحص صريح قبل طباعة أمر شغل/مطبخ من فاتورة سابقة — كان الزرار شغّال لأي
/// مستخدم من غير أي فحص صلاحية. مش نفس مسار طباعة المطبخ التلقائي وقت
/// «حفظ وطباعة» (`printKitchenOrders` جوه `_processPaymentAndSave`) — ده
/// أثر جانبي من إتمام البيع نفسه، مش فعل منفصل يختاره المستخدم، فسيبناه
/// من غير فحص (زي ما عملت Task 6b مع `kitchenRepo.createWorkOrder`).
@visibleForTesting
bool canPrintPosWorkOrder(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWorkOrder);
}

/// نسخة أعلى مستوى من `canPrintPosWorkOrder` — نفس سبب
/// `ensurePosWeightDialogPermission` فوق.
@visibleForTesting
Future<bool> ensurePosWorkOrderPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canPrintPosWorkOrder(permissions)) return true;
  if (context.mounted) {
    showPosToast(
      context,
      ref,
      'ليس لديك صلاحية طباعة أوامر الشغل',
      type: PosNotificationType.error,
    );
  }
  return false;
}

mixin _PosMainOperationsMixin on ConsumerState<PosScreenV2> {
  void _initOperations() {
    // Logic moved from initState if needed, but mostly focus management
    (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _handleProductTap(ProductEntity product) async {
    // Read stock alert mode setting
    final stockAlertMode = ref.read(posStockAlertModeProvider).value ?? 'zero';

    // Show out-of-stock warning but don't block (allowNegativeSale may be true)
    // Cluster 024 / Issue 2 — also suppress the warning when the install-wide
    // negative-sales toggle is ON; the cart will accept the line anyway.
    final globalNegativeSales =
        ref.read(enableNegativeSalesProvider).value ?? false;
    if (product.isOutOfStock &&
        !product.allowNegativeSale &&
        !globalNegativeSales &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⛔ المنتج "${product.name}" غير متوفر في المخزون (الكمية: ${product.currentStock.toStringAsFixed(0)})',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }

    if (product.isSoldByWeight) {
      if (!await ensurePosWeightDialogPermission(ref, context)) return;
      final weight = await PosDialogs.showWeightInput(context, ref, product);
      if (weight != null && weight > 0) {
        await _addProductWithModifiers(product, quantity: weight);
      }
    } else {
      // If an active offer requires a minQuantity and the product isn't in
      // the cart yet, add that minQuantity so the offer triggers automatically.
      double tapQuantity = 1;
      try {
        final cartItems = ref.read(cartControllerProvider).items;
        final alreadyInCart = cartItems.any((i) => i.productId == product.id);
        if (!alreadyInCart) {
          // ISS-06: Route through offersRepositoryProvider instead of direct DB access
          final offersRepo = ref.read(offersRepositoryProvider);
          final activeOffers = await offersRepo.getActiveOffers();
          for (final offer in activeOffers) {
            if (offer.minQuantity == null || offer.minQuantity! <= 1) continue;
            if (!offersRepo.isOfferWithinTimeWindow(offer)) continue;
            if (offer.maxUses != null &&
                offer.currentUses >= offer.maxUses!) continue;

            bool matches = false;
            if (offer.categoryId != null &&
                offer.categoryId == product.categoryId) {
              matches = true;
            }
            if (!matches) {
              final offerItems = await offersRepo.getOfferItems(offer.id);
              if (offerItems.any((oi) => oi.productId == product.id)) {
                matches = true;
              }
            }
            if (matches) {
              tapQuantity = offer.minQuantity!.toDouble();
              break; // use the first applicable offer's minQuantity
            }
          }
        }
      } catch (_) {}
      await _addProductWithModifiers(product, quantity: tapQuantity);
    }
    
    // POS Priority: Always return focus to scanner after any touch interaction
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();

    // Show low-stock warning after adding to cart (based on alert mode setting)
    final shouldShowLowStockAlert = stockAlertMode == 'min_stock'
        ? product.isLowStock && !product.isOutOfStock
        : false;

    if (shouldShowLowStockAlert && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ تنبيه: "${product.name}" كميته منخفضة (المتبقي: ${product.currentStock.toStringAsFixed(0)}, الحد الأدنى: ${product.minStock.toStringAsFixed(0)})',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  Future<void> _addProductWithModifiers(ProductEntity product, {double quantity = 1}) async {
    final productRepo = ref.read(productRepositoryProvider);
    final units = await productRepo.getProductUnits(product.id);
    
    if (units.length > 1 && mounted) {
      final selectedUnit = await UnitSelectionDialog.show(
        context,
        productName: product.name,
        units: units,
      );
      
      if (selectedUnit != null) {
        final unitPrice = selectedUnit.salePrice > 0 ? selectedUnit.salePrice : product.salePrice;
        _addProductToCart(product, quantity: quantity, customPrice: unitPrice);
        
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
      } else {
        return;
      }
    }
    
    _addProductToCart(product, quantity: quantity);
    
    // Ensure focus even if UnitSelection was cancelled (though caller handles it, we double-down here)
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _addProductToCart(ProductEntity product, {double quantity = 1, double? customPrice}) {
    // ── Digital-scale duplicate-weight guard ──────────────────────────
    // Only for `isSoldByWeight` products added via the LIVE scale flow
    // (product tap → weight dialog → counter scale / manual entry).
    // Barcode-label scans go through `searchBarcode`, which deliberately
    // skips this check — two identical pre-printed labels are legitimate
    // separate weighings.
    //
    // When the cashier tries to add the SAME (product, weight) within the
    // last 30s, it typically means they forgot to change the item on the
    // scale. We raise a blocking popup so they cannot miss it, but the
    // item is still added to the cart — the popup's "متابعة" button just
    // acknowledges the warning; the cashier can then change the scale
    // weight for the next item.
    bool shouldWarnDuplicate = false;
    if (product.isSoldByWeight && quantity > 0) {
      shouldWarnDuplicate = ref.read(posSearchControllerProvider.notifier)
          .checkAndWarnDuplicateWeight(
        productId: product.id,
        productName: product.name,
        weightKg: quantity,
      );
    }

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
    (this as _PosScreenV2State)._barcodeFocus.requestFocus();

    // Show the popup AFTER the add so the cart state reflects reality
    // when the cashier acknowledges. Fire-and-forget — we don't block
    // `_addProductToCart` on the user's dismiss tap.
    if (shouldWarnDuplicate && mounted) {
      final searchStateNow = ref.read(posSearchControllerProvider);
      final msg = searchStateNow.duplicateWeightWarning;
      // Clear state flag immediately so a follow-up add (with a new
      // weight) doesn't re-trigger the popup via stale state.
      ref.read(posSearchControllerProvider.notifier)
          .clearDuplicateWeightWarning();
      if (msg != null) {
        _showDuplicateWeightDialog(msg);
      }
    }
  }

  /// Blocking popup alerting the cashier that the live-scale weight they
  /// just added is identical to the last add for the same product. The
  /// single "متابعة" button simply dismisses — the cart keeps the item.
  Future<void> _showDuplicateWeightDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 48,
          ),
          title: const Text(
            'تنبيه: نفس الوزن',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontFamily: 'Cairo'),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'متابعة',
                style: TextStyle(fontSize: 14, fontFamily: 'Cairo'),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    // Return focus to the scanner so the cashier can immediately proceed.
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  Future<void> _searchBarcode(String barcode) async {
    // Spec 116 (L1) — defensive wrap على UI callback. الـ controller wrap
    // (T005) يلتقط exceptions في searchBarcode، لكن قد توجد errors في
    // dialog rendering (QuickAddProductDialog، AlertDialog) أو ScaffoldMessenger.
    // هذا الـ try/catch هو الـ safety net النهائي قبل صعود الـ exception
    // لـ PlatformDispatcher.onError في main.dart.
    try {
    // Capture cart state before search to detect if product was added
    final cartBefore = ref.read(cartControllerProvider);
    final totalQtyBefore = cartBefore.items.fold<double>(0, (s, i) => s + i.quantity);

    await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);

    // NOTE: No duplicate-weight warning handling here. Barcode scans (scale
    // labels or regular) must NEVER trigger the duplicate-weight popup —
    // that guard is exclusive to the live digital-scale flow via
    // `_addProductToCart`. See pos_search_controller.searchBarcode comment.

    // If cart changed (product was added/merged), skip error dialog even if error state lingers
    final cartAfter = ref.read(cartControllerProvider);
    final totalQtyAfter = cartAfter.items.fold<double>(0, (s, i) => s + i.quantity);
    if (totalQtyAfter > totalQtyBefore) {
      (this as _PosScreenV2State)._barcodeController.clear();
      (this as _PosScreenV2State)._barcodeFocus.requestFocus();
      return;
    }

    // Check if barcode was not found → play alert sound + show quick-add dialog
    //
    // Feature 013 / Issue BARCODE-INACTIVE — only prompt to register when
    // the barcode is genuinely unknown. For inactive products, scale-PLU
    // mismatches, and other lookup failures the controller has already
    // surfaced an explanatory error string; offering "add as new" here
    // would duplicate the existing product (active OR inactive) and
    // corrupt the catalog.
    final searchState = ref.read(posSearchControllerProvider);
    if (searchState.error != null && mounted) {
      if (searchState.errorKind != BarcodeSearchErrorKind.notFound) {
        // Surface the controller's explanation as a non-actionable toast.
        AppToast.show(
          context,
          searchState.error!,
          type: ToastType.warning,
        );
        (this as _PosScreenV2State)._barcodeController.clear();
        (this as _PosScreenV2State)._barcodeFocus.requestFocus();
        return;
      }
      // Show confirmation dialog
      final shouldAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('صنف غير معرف'),
              ],
            ),
            content: Text('الباركود "$barcode" غير مسجل في النظام.\nهل تريد إضافته كصنف جديد؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('نعم — إضافة سريعة'),
              ),
            ],
          ),
        ),
      );

      if (shouldAdd == true && mounted) {
        // SEC: Restrict quick-add to users with products_add permission (manager/admin)
        final authState = ref.read(authProvider);
        final perms = ref.read(currentUserPermissionsProvider).asData?.value ?? [];
        // مدير النظام بس هو اللي بيتجاوز صلاحية إضافة الأصناف. قبل كده كانت
        // `isAdmin || isManager`، وهي بتتحدد بمطابقة اسم الدور — فـ«مدير فرع»
        // كان بيعدّي بلا صلاحية.
        final canAddProducts = authState.hasSystemAdminBypass || perms.contains(PermissionCodes.productsAdd);

        if (!canAddProducts) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⛔ إضافة الأصناف تتطلب صلاحية المدير'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          final newProductId = await QuickAddProductDialog.show(context, barcode);
          if (newProductId != null) {
            // Re-scan the barcode to add the newly created product
            await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);
          }
        }
      }
    }

    (this as _PosScreenV2State)._barcodeController.clear();
    (this as _PosScreenV2State)._barcodeFocus.requestFocus();
    } catch (e, st) {
      // Spec 116 (L1) — defensive catch على مستوى UI callback.
      unawaited(
        DiagnosticLogger.log(
          'BARCODE-CRASH-UI',
          'callback barcode="$barcode" error=$e\n$st',
        ).catchError((_) {}),
      );
      debugPrint('[POS] _searchBarcode CRITICAL: $e');
      if (mounted) {
        try {
          AppToast.show(
            context,
            'خطأ في معالجة الباركود — حاول مرة أخرى',
            type: ToastType.error,
          );
        } catch (_) {}
        try {
          (this as _PosScreenV2State)._barcodeController.clear();
          (this as _PosScreenV2State)._barcodeFocus.requestFocus();
        } catch (_) {}
      }
    }
  }

  Future<void> _handleCheckout() async {
    final cartState = ref.read(cartControllerProvider);
    if (!await _validateCartBeforeCheckout(cartState)) return;

    // Pre-checkout: verify an open fiscal year exists for today
    try {
      // ISS-06: Route through fiscalPeriodValidationProvider instead of direct DB access
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
              Icon(Icons.lock_clock, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('السنة المالية مغلقة'),
            ]),
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(fontSize: 14),
            ),
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

    final success = await PosDialogs.showPaymentDialog(
      context,
      totalAmount: cartState.total,
    );

    if (success != null) {
       await _executePayment(success, cartState);
    }
    (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  Future<void> _executePayment(dynamic paymentResult, dynamic cartState) async {
    final success = await ref.read(checkoutControllerProvider.notifier).processPayment(
      method: paymentResult.method,
      total: paymentResult.total,
      cashAmount: paymentResult.cashAmount,
      bankAmount: paymentResult.bankAmount,
      clickAmount: paymentResult.clickAmount,
      bankSafeId: cartState.bankSafeId,
      customerId: paymentResult.customerId ?? cartState.selectedCustomerId,
    );
       
    if (success) {
      _onCheckoutSuccess();
      // Cluster 025 / Issue 1 — surface the JE rounding adjustment when
      // the auto-balance pass absorbed a floating-point diff. Operator
      // sees a brief info toast so they know the JE balanced cleanly
      // even though the line totals had a sub-piaster drift.
      final adj = JournalEntryDiagnostics.lastRoundingAdjustment;
      if (adj.abs() > 0.001 && mounted) {
        showPosToast(
          context,
          ref,
          'تمت تسوية فروقات تقريب ${adj.abs().toStringAsFixed(3)}',
          type: PosNotificationType.info,
        );
      }
      // Play success beep
      SystemSound.play(SystemSoundType.click);
    } else {
      final err = ref.read(checkoutControllerProvider).error ?? 'فشل حفظ الفاتورة';
      showPosToast(context, ref, err, type: PosNotificationType.error);
    }
    (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  void _onCheckoutSuccess() {
      // Clear barcode field and return focus so it's ready for the next customer
      (this as _PosScreenV2State)._barcodeController.clear();
      (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  Future<bool> _validateCartBeforeCheckout(dynamic cartState) async {
    final items = cartState.items as List;
    if (items.isEmpty) return false;

    final zeroPriceItems = <String>[];
    final zeroQtyItems = <String>[];

    for (final item in items) {
      if (item.unitPrice <= 0) zeroPriceItems.add(item.productName);
      if (item.quantity <= 0) zeroQtyItems.add(item.productName);
    }

    if (zeroPriceItems.isEmpty && zeroQtyItems.isEmpty) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('تحذير — أصناف بدون قيمة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (zeroPriceItems.isNotEmpty) ...[
                const Text('⚠️ أصناف بسعر صفر:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                ...zeroPriceItems.map((n) => Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 2),
                  child: Text('• $n', style: const TextStyle(fontSize: 13)),
                )),
                const SizedBox(height: 8),
              ],
              if (zeroQtyItems.isNotEmpty) ...[
                const Text('⚠️ أصناف بكمية صفر:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                ...zeroQtyItems.map((n) => Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 2),
                  child: Text('• $n', style: const TextStyle(fontSize: 13)),
                )),
                const SizedBox(height: 8),
              ],
              const Divider(),
              const Text(
                'هل تريد المتابعة رغم ذلك؟',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، تعديل الفاتورة'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('نعم، متابعة'),
            ),
          ],
        ),
      ),
    );

    return proceed == true;
  }

  Future<void> _saveOrder() async {
    await _processPaymentAndSave(printAfter: false);
  }

  Future<void> _saveAndPrint() async {
    await _processPaymentAndSave(printAfter: true);
  }

  /// Fresh permission check — invalidates the Riverpod cache first so
  /// changes that the admin just made in another dialog/device take
  /// effect without requiring a logout. Honours the same "system admin
  /// bypass (except critical financial ops)" semantics as
  /// [PermissionGuard] for consistency.
  ///
  /// Deliberately does NOT consult any session-elevation flag: the old
  /// short-circuits on `_isAdminElevated` (local 10s window) and
  /// `authState.isElevated` (sidebar walk-through) caused a single admin
  /// password entry to silently whitelist every subsequent gated action
  /// for the rest of the session. Per per-action-elevation plan, each
  /// protected action must re-prompt the admin individually.
  Future<bool> _userHasPermissionFresh(String permissionCode) async {
    // Honour an action-scoped manager approval token first. When the user
    // just clicked a guarded button (e.g. "حفظ وفتح الدرج"), the
    // PermissionGuard already prompted for the admin password and stamped
    // an approval into ManagerApprovalCache. This downstream defence-in-
    // depth check should consume that token rather than prompt the user
    // a SECOND time for the same logical action — the symptom the
    // operator reported as "يطلب كلمة مرور المدير مرة لحفظ البيع ومره
    // لحفظ فاتورة نقطة البيع". Tokens are single-use and expire in 60
    // seconds, so they can't authorise unrelated later operations.
    if (ManagerApprovalCache.instance.consume(permissionCode)) {
      debugPrint('[POS-PERM] check="$permissionCode" '
          '→ pre-approved by manager (token consumed)');
      return true;
    }

    // Force a fresh read from the DB — the cached provider value may be
    // stale if the admin just edited the role in another window.
    ref.invalidate(currentUserPermissionsProvider);
    final codes = await ref.read(currentUserPermissionsProvider.future);

    final hasDirect = codes.contains(permissionCode);
    final isSystemAdmin = codes.contains('system_admin') || codes.contains('*');
    final isCriticalFin = PermissionCodes.criticalFinancialOps.contains(permissionCode);

    // P5 (permission-prompt fix): log the resolution so cases where the
    // dialog wrongly appears can be diagnosed quickly. The user reported
    // that pos_save was prompting for admin password even when the cashier
    // had the permission — this log makes it obvious whether codes are
    // missing, the role wasn't synced, or the permission name mismatched.
    debugPrint('[POS-PERM] check="$permissionCode" '
        'has=$hasDirect isAdmin=$isSystemAdmin critical=$isCriticalFin '
        'codeCount=${codes.length}');

    if (hasDirect) return true;

    // System-admin bypass — same logic as PermissionGuard. Excludes
    // critical financial ops (segregation of duties), but pos_save is
    // NOT in that list so an admin can always save.
    if (isSystemAdmin && !isCriticalFin) {
      return true;
    }
    return false;
  }

  Future<void> _processPaymentAndSave({required bool printAfter}) async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) return;

    if (!await _validateCartBeforeCheckout(cartState)) return;

    // ── Enforce pos_save permission at the SAVE entry point. ────────
    //
    // Previously the only gate was `PermissionGuard` on the save button
    // widget, which:
    //   1. read from a stale Riverpod cache (symptom 1: having the
    //      permission still opened the manager-override dialog when the
    //      cache hadn't refreshed yet).
    //   2. could be bypassed entirely by any keyboard shortcut / held-
    //      order resume / programmatic save path that didn't pass
    //      through the button — which is why revoking the permission
    //      still allowed sales to complete (symptom 3).
    //
    // Route every save through one authoritative check:
    //   - Invalidate + refresh the permissions cache first so changes
    //     made by the admin on the same machine take effect immediately.
    //   - If the user has `pos_save` (or is a system admin), proceed.
    //   - Otherwise prompt for manager override via the same dialog the
    //     guard uses, and ONLY proceed on a verified manager password.
    final hasPermission = await _userHasPermissionFresh(
      PermissionCodes.posSave,
    );
    if (!hasPermission) {
      final approved = await requestManagerApproval(
        context,
        actionName: 'حفظ فاتورة نقطة البيع',
        permission: PermissionCodes.posSave,
      );
      if (!approved) return;
    }

    final total = cartState.total;

    // Phase 5 Bypass: If electronic platform (Talabat/Careem/Ashyae) or designated Credit customer,
    // skip the payment dialog entirely since it's already set to 'credit' and we don't need cash/bank breakdown.
    dynamic paymentResult;
    final isPlatform = ['talabat', 'careem', 'ashyae'].contains(cartState.priceLevel);
    final isCredit = cartState.paymentMethod == 'credit';

    if (isPlatform && isCredit) {
      // Mock result for credit platform
      paymentResult = (
        method: 'credit',
        total: total,
        cashAmount: 0.0,
        bankAmount: 0.0,
        clickAmount: 0.0,
        customerId: cartState.selectedCustomerId,
      );
    } else {
      paymentResult = await PosDialogs.showPaymentDialog(
        context,
        totalAmount: total,
      );
    }

    if (paymentResult == null || !mounted) return;

    ref.read(cartControllerProvider.notifier).setPaymentMethod(paymentResult.method);

    if (paymentResult.method == 'cash') {
      final confirmed = await PosCashTenderingDialog.show(context, totalAmount: total);
      if (confirmed != true || !mounted) return;
    }

    final success = await ref.read(checkoutControllerProvider.notifier).processPayment(
      method: paymentResult.method,
      total: paymentResult.total,
      cashAmount: paymentResult.cashAmount,
      bankAmount: paymentResult.bankAmount,
      clickAmount: paymentResult.clickAmount,
      bankSafeId: cartState.bankSafeId,
      customerId: paymentResult.customerId ?? cartState.selectedCustomerId,
    );

    if (!mounted) return;

    if (success) {
      if (printAfter) {
        final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
        
        // ── Accelerated Flow: Open Drawer concurrently with printing ──
        final drawerFuture = _openCashDrawerQuietly();
        
        if (invoiceId != null) {
          try {
            await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
          } catch (e) {
            debugPrint('[SaveAndPrint] Receipt print failed: $e');
            // Notify user about printer but don't block
            if (mounted) {
              showPosToast(context, ref, '⚠️ الحفظ تم، لكن فشلت الطباعة (تأكد من الورق)', type: PosNotificationType.warning);
            }
          }
          try {
            await ref.read(posControllerProvider.notifier).printKitchenOrders(invoiceId);
          } catch (e) {
            debugPrint('[SaveAndPrint] Kitchen print failed: $e');
          }
        }
        
        await drawerFuture; // Ensure drawer is at least attempted
        showPosToast(context, ref, 'تم حفظ وطباعة الفاتورة', type: PosNotificationType.success);
      } else {
        // Trigger cash drawer for "Save Only" as requested by user
        await _openCashDrawerQuietly();
        showPosToast(context, ref, 'تم حفظ الفاتورة بنجاح', type: PosNotificationType.success);
      }
      
      // Clear barcode input ready for new scan items immediately
      (this as _PosScreenV2State)._barcodeController.clear();
      (this as _PosScreenV2State)._barcodeFocus.requestFocus();
    } else {
      final err = ref.read(checkoutControllerProvider).error ?? 'فشل حفظ الفاتورة';
      showPosToast(context, ref, err, type: PosNotificationType.error);
    }
  }

  Future<void> _saveAsQuotation() async {
    final success = await ref
        .read(checkoutControllerProvider.notifier)
        .saveAsQuotation();
    if (mounted) {
      if (success) {
        showPosToast(
          context,
          ref,
          'تم حفظ عرض السعر بنجاح',
          type: PosNotificationType.success,
        );
        (this as _PosScreenV2State)._barcodeController.clear();
        (this as _PosScreenV2State)._barcodeFocus.requestFocus();
      } else {
        final err =
            ref.read(checkoutControllerProvider).error ?? 'فشل حفظ عرض السعر';
        showPosToast(context, ref, err, type: PosNotificationType.error);
      }
    }
  }

  Future<void> _holdCurrentOrder() async {
    final cartState = ref.read(cartControllerProvider);
    final cartController = ref.read(cartControllerProvider.notifier);
    if (cartState.items.isEmpty) return;

    final customerName = await PosDialogs.showHoldOrderDialog(context);
    if (customerName == null) return;

    final holdNum = await cartController.holdOrder(
      customerName: customerName.isEmpty ? null : customerName,
    );

    if (mounted && holdNum != null) {
      cartController.clearCart();
      showPosToast(
        context,
        ref,
        'تم تعليق الفاتورة #$holdNum${customerName.isNotEmpty ? ' - $customerName' : ''}',
        type: PosNotificationType.success,
      );
    }
    
    // Return focus if dialog was cancelled
    if (mounted) (this as _PosScreenV2State)._barcodeFocus.requestFocus();
  }

  Future<void> _reprintInvoice(int invoiceId) async {
    try {
      await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
      if (mounted) {
        showPosToast(
          context,
          ref,
          'تم إعادة الطباعة رقم $invoiceId بنجاح',
          type: PosNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          'خطأ طباعة الفاتورة: $e',
          type: PosNotificationType.error,
        );
      }
    }
  }

  Future<void> _printKitchenOrdersForInvoice(int invoiceId) async {
    if (!await ensurePosWorkOrderPermission(ref, context)) return;
    try {
      await ref
          .read(posControllerProvider.notifier)
          .printKitchenOrders(invoiceId);

      if (mounted) {
        showPosToast(
          context,
          ref,
          'تم إرسال الطلب للمطبخ',
          type: PosNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          'خطأ طباعة أوامر المطبخ: $e',
          type: PosNotificationType.error,
        );
      }
    }
  }

  Future<String> _getDrawerPrinterName() async {
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      // Read drawer-specific printer first, fallback to receipt printer
      final drawerPrinter = await settingsRepo.getSetting('cash_drawer_printer');
      if (drawerPrinter != null && drawerPrinter.isNotEmpty) return drawerPrinter;
      final receiptPrinter = await settingsRepo.getSetting('receipt_printer');
      return receiptPrinter ?? 'Default';
    } catch (_) {
      return 'Default';
    }
  }

  /// Helper to open the cash drawer and fail gracefully with logging
  Future<void> _openCashDrawerQuietly() async {
    try {
      final printerName = await _getDrawerPrinterName();
      await CashDrawerService().openDrawer(printerName: printerName);
    } catch (e) {
      debugPrint('[Drawer] Failed to trigger drawer sensor: $e');
      // If we're on Windows and specific setup fails, it might be due to a missing printer
    }
  }
}
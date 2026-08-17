part of 'pos_table_service_screen.dart';

/// فحص صريح قبل فتح ديالوج الميزان — نفس الفحص الموجود في
/// `pos_main_operations.dart`/`picpos_pos_operations.dart`، مكرَّر هنا لأن
/// `TablePosScreen` (خدمة الطاولات) فورك تالت مستقل كان ناقص من التريَّاج
/// الأول (اتلقّى اتنين بس: UralCash وPicPos) — راجع تعليق رأس
/// `pos_main_operations.dart` عن الفورك التالت ده.
@visibleForTesting
bool canOpenPosWeightDialog(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWeightDialog);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد في
/// نقطة الاستدعاء (زي باقي الأفرع).
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

mixin _TablePosOperationsMixin on ConsumerState<TablePosScreen> {
  late final TextEditingController barcodeController;
  late final FocusNode barcodeFocus;

  void _initOperations() {
    barcodeController = TextEditingController();
    barcodeFocus = FocusNode();
  }

  void _disposeOperations() {
    barcodeController.dispose();
    barcodeFocus.dispose();
  }

  Future<void> _handleBack() async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isNotEmpty) {
      final shouldLeave = await showDialog<bool>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تنبيه'),
                content: const Text(
                    'يوجد أصناف في السلة. هل تريد الخروج من شاشة الطاولة؟ (ستبقى مشغولة)'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('لا'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('خروج'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
      if (shouldLeave && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      final repo = ref.read(restaurantRepositoryProvider);
      await repo.updateTableStatus(widget.tableId, 'available');
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _handleProductTap(ProductEntity product) async {
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
              break;
            }
          }
        }
      } catch (_) {}
      await _addProductWithModifiers(product, quantity: tapQuantity);
    }
    barcodeFocus.requestFocus();
  }

  Future<void> _addProductWithModifiers(ProductEntity product,
      {double quantity = 1}) async {
    try {
      final productRepo = ref.read(productRepositoryProvider);
      final hasModifiers = await productRepo.productHasModifiers(product.id);

      if (hasModifiers && mounted) {
        final modifierGroups =
            await productRepo.getProductModifiers(product.id);
        if (modifierGroups.isNotEmpty && mounted) {
          final selected = await ModifierSelectionDialog.show(
            context,
            productName: product.name,
            modifierGroups: modifierGroups,
          );
          if (selected == null) return;

          final extraPrice =
              selected.fold<double>(0, (sum, m) => sum + m.extraPrice);
          final modifierNote = selected.isNotEmpty
              ? selected
                  .map((m) {
                    if (m.isOption) {
                      final levelLabel = m.quantityLevel.label;
                      final optionText = levelLabel.isNotEmpty
                          ? '$levelLabel ${m.itemName}'
                          : m.itemName;
                      return '(${m.groupName}: $optionText)';
                    }
                    return '+${m.itemName}${m.extraPrice > 0 ? " (+${m.extraPrice.toStringAsFixed(0)} ${AppConstants.currencySymbolEn})" : ""}';
                  })
                  .join(' | ')
              : null;

          ref.read(cartControllerProvider.notifier).addItem(
                product,
                quantity: quantity,
                customPrice:
                    extraPrice > 0 ? product.salePrice + extraPrice : null,
                note: modifierNote,
              );
          return;
        }
      }
    } catch (e) {
      debugPrint('[Modifiers] Check failed: $e');
    }
    ref
        .read(cartControllerProvider.notifier)
        .addItem(product, quantity: quantity);
  }

  Future<void> _searchBarcode(String barcode) async {
    final cartBefore = ref.read(cartControllerProvider);
    final totalQtyBefore = cartBefore.items.fold<double>(0, (s, i) => s + i.quantity);

    await ref
        .read(posSearchControllerProvider.notifier)
        .searchBarcode(barcode);

    // NOTE: No duplicate-weight warning here. Barcode scans (including
    // scale-label barcodes) must never raise the duplicate popup — that
    // guard is exclusive to the LIVE digital-scale flow.

    // If cart changed (product was added/merged), skip error dialog
    final cartAfter = ref.read(cartControllerProvider);
    final totalQtyAfter = cartAfter.items.fold<double>(0, (s, i) => s + i.quantity);
    if (totalQtyAfter > totalQtyBefore) {
      ref.read(posSearchControllerProvider.notifier).clearSearchResults();
      return;
    }

    // Check if barcode was not found → play alert sound + show quick-add dialog
    final searchState = ref.read(posSearchControllerProvider);
    if (searchState.error != null && mounted) {
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
        final newProductId = await QuickAddProductDialog.show(context, barcode);
        if (newProductId != null) {
          await ref.read(posSearchControllerProvider.notifier).searchBarcode(barcode);
        }
      }
    }

    barcodeController.clear();
    barcodeFocus.requestFocus();
  }

  /// تفعيلُ ضريبة الطلب أو إطفاؤها من زرّ الشاشة.
  ///
  /// تُكتب على الطلب أوّلاً، ولا تُحدَّث السلّةُ إلّا بعد نجاح الكتابة —
  /// فمفتاحٌ يتحرّك على الشاشة بينما الطلبُ لم يتغيّر هو بالضبط الفارقُ الذي
  /// يوقف التحصيلَ بعد ذلك برسالةٍ لا يفهمها الكاشير.
  Future<void> _toggleOrderTax(bool enabled) async {
    final orderId = ref.read(posControllerProvider).orderId;
    if (orderId == null) {
      AppToast.show(context, 'لا يوجد طلب مفتوح لهذه الطاولة',
          type: ToastType.warning);
      return;
    }
    final user = ref.read(authProvider).user;
    try {
      await ref.read(tableSessionServiceProvider).setOrderTax(
            orderId: orderId,
            enabled: enabled,
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
          );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر تعديلُ الضريبة: $e',
            type: ToastType.error);
      }
      return;
    }
    ref.read(cartControllerProvider.notifier).toggleTax(enabled);
  }

  Future<void> _checkoutTable() async {
    final restaurantRepo = ref.read(restaurantRepositoryProvider);
    final posState = ref.read(posControllerProvider);
    final orderId = posState.orderId;

    if (orderId == null) {
      AppToast.show(context, 'لا يوجد طلب مفتوح لهذه الطاولة',
          type: ToastType.warning);
      return;
    }

    final tableItems = await restaurantRepo.getTableOrderItems(orderId);
    if (tableItems.isEmpty) {
      AppToast.show(context, 'لا يوجد أصناف في الطلب للتحصيل',
          type: ToastType.warning);
      return;
    }

    // ── السلّةُ تُبنى على صورة الطلب، لا على صورة المنتجات ────────────────
    // المحرّكان (`CalculateInvoiceTotalsUseCase` هنا و`TableOrderTotals`
    // هناك) صارا يحسبان بالقاعدة نفسِها، فلا يتطابقان إلّا إن تطابقت
    // **مدخلاتُهما** كذلك. ولذلك تُنسَخ الضريبةُ ونسبتُها ونِسَبُ البنود
    // وخصمُ الطلب من صفِّ الطلب لا من بطاقة المنتج: نسبةُ البند لقطةٌ أُخذت
    // ساعةَ الطلب، وقراءتُها الآن من المنتج تُعطي رقماً آخر لو غُيّرت
    // البطاقةُ في أثناء الوجبة — وهو الفارقُ الذي كان يوقف التحصيل.
    final order = await restaurantRepo.getActiveOrderForTable(widget.tableId);

    final cartNotifier = ref.read(cartControllerProvider.notifier);
    cartNotifier.clearCart();
    cartNotifier.toggleTax(order?.taxEnabled ?? false);
    if (order != null) cartNotifier.setTaxRate(order.taxRate);
    final productRepo = ref.read(productRepositoryProvider);
    for (final item in tableItems) {
      final product = await productRepo.getProductById(item.productId);
      if (product != null) {
        cartNotifier.addItem(
          product,
          quantity: item.quantity,
          customPrice: item.unitPrice,
          // صفرٌ ليس «معفىً» بل «يقع على نسبة الطلب» — وهي دلالةُ
          // `item.taxRate > 0 ? item.taxRate : taxPercent` في المحرّكين معاً.
          taxRate: item.taxRate,
        );
      }
    }

    // خصمُ الطلب يُنقل إلى السلّة كذلك، وإلّا شُحن الزبونُ بلا خصمٍ ثبّته
    // له الكاشير. و«المبلغُ المقطوع» يُعبَّر عنه نسبةً لأن السلّة لا تعرف
    // إلّا النسبة؛ والحارسُ أسفلَه يبقى الفيصلَ إن بقي فرقُ كسرٍ.
    if (order != null && order.discountValue > 0) {
      final gross = tableItems.fold<double>(
          0, (sum, i) => sum + i.quantity * i.unitPrice);
      if (order.discountType == 'percent') {
        cartNotifier.setDiscount(order.discountValue);
      } else if (order.discountType == 'amount' && gross > 0) {
        cartNotifier.setDiscount(order.discountValue / gross * 100);
      }
    }

    final cartState = ref.read(cartControllerProvider);
    final total = cartState.total;

    // ── فحصٌ قبليّ: ما يُشحَن = ما يُسجَّل ─────────────────────────────────
    // السلّةُ والطلبُ يحسبان بمحرّكين مختلفين: `cartState.total` يضيف
    // الضريبةَ فوق ويطرح خصومَ السلّة والعروض، بينما `recordPayment` يقيس
    // على `effectiveTotal(order) - paidAmount`. فإن اختلفا — ضريبةٌ مفعّلةٌ
    // من مفتاح هذه الشاشة نفسِها، أو صنفٌ حُذف فتُخطّي من السلّة، أو تقسيمٌ
    // جزئيٌّ سبق فالسلّةُ تُعيد شحنَ الإجماليِّ كاملاً — فالفشلُ اليوم يقع
    // **بعد** `processPayment`، أي بعد ترحيل الفاتورة محاسبةً ومخزوناً،
    // فتبقى فاتورةٌ يتيمةٌ وطاولةٌ لا تُغلَق ولا تُلغى.
    //
    // فيُنقل الرفضُ إلى ما قبل أيّ ترحيل: فاتورةٌ لم تصدر لا تحتاج تسوية.
    final double due;
    try {
      due = await ref.read(tableSessionServiceProvider).amountDue(orderId);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر قراءةُ مستحقِّ الطلب: $e',
            type: ToastType.error);
      }
      return;
    }
    final mismatch = checkTableCharge(charged: total, expected: due);
    if (mismatch != null) {
      if (mounted) {
        AppToast.show(context, mismatch.message, type: ToastType.error);
      }
      return;
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<PaymentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: PaymentSheet(
          total: total,
          subtotal: cartState.subtotal,
          discount: cartState.totals.totalDiscount,
          tax: cartState.totals.taxAmount,
          onConfirm: (paymentResult) => Navigator.pop(ctx, paymentResult),
          onCancel: () => Navigator.pop(ctx),
        ),
      ),
    );

    if (result == null || !mounted) return;

    final checkoutCtrl = ref.read(checkoutControllerProvider.notifier);
    final success = await checkoutCtrl.processPayment(
      method: result.method,
      total: total,
      cashAmount: result.cashAmount,
      bankAmount: result.bankAmount,
      bankSafeId: ref.read(cartControllerProvider).bankSafeId,
      customerId: result.customerId,
    );

    if (!success) {
      final error = ref.read(checkoutControllerProvider).error;
      if (mounted) {
        AppToast.show(context, 'فشل الدفع: ${error ?? "خطأ غير معروف"}',
            type: ToastType.error);
      }
      return;
    }

    final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
    if (invoiceId != null) {
      try {
        final salesRepo = ref.read(salesRepositoryProvider);
        await salesRepo.updateSaleType(invoiceId, 'table');
      } catch (_) {}
    }

    if (invoiceId == null) {
      if (mounted) {
        AppToast.show(
          context,
          'تم الدفع لكن تعذّر تسجيله على الطاولة — لا رقم فاتورة',
          type: ToastType.error,
        );
      }
      return;
    }

    // الطاولةُ تصير 🟠 لا 🟢: الدفعُ لا يُغلق، والإغلاقُ خطوةٌ صريحةٌ
    // يقوم بها الموظف بعد تجهيز الطاولة. الخدمةُ تكتب سطرَ السجلِّ بنفسها.
    final user = ref.read(authProvider).user;
    try {
      await ref.read(tableSessionServiceProvider).recordPayment(
            orderId: orderId,
            invoiceId: invoiceId,
            amount: total,
            userId: user?.id,
            userName: user?.displayName,
          );
    } catch (e) {
      // الفاتورةُ #$invoiceId صدرت ورُحِّلت بالفعل (محاسبةً ومخزوناً) قبل
      // هذا الفشل — processPayment سبق recordPayment، فلا معاملةَ تعويضيّةً
      // ممكنةً هنا. أقصى ما يمكن فعلُه ألّا يضيع الأثر: سطرٌ صريحٌ في سجلِّ
      // الطاولة (يظهر في TableLogSheet) يحمل رقمَ الفاتورة والمبلغَ وسببَ
      // الفشل، ورسالةٌ للكاشير تُسمّي الفجوةَ ولا تكتفي برسالةٍ عامّة.
      try {
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'table_payment_reconcile_needed',
          entityType: 'table',
          entityId: widget.tableId,
          description:
              'فاتورةٌ #$invoiceId صدرت ورُحِّلت، لكن تعذّر تسجيلُ دفعتها على '
              '${widget.tableName} — يحتاج تسويةً يدويّة. الخطأ: $e',
          amount: total,
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(
          context,
          '⚠️ فاتورة #$invoiceId صدرت ورُحِّلت لكن لم تُسجَّل على '
          '${widget.tableName} — راجع الطاولةَ يدويّاً',
          type: ToastType.error,
        );
      }
      return;
    }

    if (mounted) {
      barcodeController.clear();
      barcodeFocus.requestFocus();
      AppToast.show(
        context,
        '✅ تم تحصيل ${widget.tableName} — فاتورة #$invoiceId — الطاولةُ مدفوعةٌ بانتظار الإغلاق',
        type: ToastType.success,
      );
      Navigator.pop(context);
    }
  }

  Future<void> _sendToKitchen() async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) return;

    try {
      final kitchenRepo = ref.read(kitchenRepositoryProvider);
      final posState = ref.read(posControllerProvider);
      final restaurantRepo = ref.read(restaurantRepositoryProvider);
      final orderId = posState.orderId;
      final user = ref.read(authProvider).user;
      final productRepo = ref.read(productRepositoryProvider);

      final Map<int?, List<CartItemEntity>> itemsByCategory = {};
      for (final item in cartState.items) {
        final product = await productRepo.getProductById(item.productId);
        (itemsByCategory[product?.categoryId] ??= []).add(item);
      }

      int workOrdersCreated = 0;
      for (final entry in itemsByCategory.entries) {
        final categoryId = entry.key;
        final categoryItems = entry.value;

        String station = 'kitchen';
        if (categoryId != null) {
          try {
            station = await kitchenRepo.getStationForCategory(categoryId);
          } catch (_) {}
        }

        final orderNumber = await kitchenRepo.generateWorkOrderNumber();
        final woItems = categoryItems
            .map((item) => WorkOrderItemData(
                  productId: item.productId,
                  productName: item.productName,
                  quantity: item.quantity,
                  notes: item.note,
                ))
            .toList();

        await kitchenRepo.createWorkOrder(
          orderNumber: orderNumber,
          items: woItems,
          station: station,
          tableOrderId: orderId,
          customerName: widget.tableName,
          createdBy: user?.id,
        );
        workOrdersCreated++;
      }

      if (orderId != null) {
        for (final item in cartState.items) {
          await restaurantRepo.addOrUpdateTableOrderItem(
            orderId: orderId,
            productId: item.productId,
            quantity: item.quantity,
            unitPrice: item.effectivePrice,
            // نسبةُ الصنف تُثبَّت على البند ساعةَ الطلب — هي التي تجعل
            // حسابَ الطاولة يطابق حسابَ السلّة عند التحصيل.
            taxRate: item.taxRate,
          );
        }
        await restaurantRepo.updateTableStatus(widget.tableId, 'occupied');
      }

      try {
        await ref.read(cartControllerProvider.notifier).generateWorkOrders();
      } catch (_) {}

      ref.read(cartControllerProvider.notifier).clearCart();

      try {
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'send_to_kitchen',
          entityType: 'table_order',
          entityId: widget.tableId,
          description:
              'إرسال طلب للمطبخ: ${widget.tableName} (${cartState.items.length} أصناف)',
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(context, '✅ تم إرسال الطلب للمطبخ', type: ToastType.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'فشل الإرسال: $e', type: ToastType.error);
    }
  }

  Future<void> _handleClearTable() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.items.isEmpty) return;
    
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إفراغ الطاولة', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          content: const Text('هل أنت متأكد من إفراغ هذه الطاولة؟ سيتم حذف جميع الطلبات وإرجاع الطاولة لحالة (متاحة).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('إفراغ وتحويل لمتاحة'),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (!shouldClear) return;

    final posState = ref.read(posControllerProvider);
    final orderId = posState.orderId;
    if (orderId != null) {
      final restaurantRepo = ref.read(restaurantRepositoryProvider);
      await restaurantRepo.clearTableOrderItems(orderId);
      await restaurantRepo.updateTableStatus(widget.tableId, 'available');
    }

    ref.read(cartControllerProvider.notifier).clearCart();
    
    try {
        final authState = ref.read(authProvider);
        final actRepo = ref.read(activityLogRepositoryProvider);
        await actRepo.logActivity(
          userId: authState.user?.id,
          userName: authState.user?.displayName ?? '',
          action: 'clear_table',
          entityType: 'table',
          entityId: widget.tableId,
          description: 'تم إفراغ وتصفير طاولة (${widget.tableName})',
        );
    } catch (_) {}

    if (mounted) AppToast.show(context, 'تم إفراغ السلة');
  }

  void _autoSelectFirstCategory() {
    final catsAsync = ref.read(visibleCategoriesProvider);
    catsAsync.whenData((cats) {
      final visible = cats.where((c) => !c.isLocked && !c.isExcluded && c.showInPos).toList();
      if (visible.isNotEmpty) {
        ref.read(posControllerProvider.notifier).setCategoryFilter(visible.first.id);
      }
    });
  }
}

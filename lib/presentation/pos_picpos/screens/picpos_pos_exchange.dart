part of 'picpos_pos_screen.dart';

/// Exchange mode: entering, damaged-lines prompt, cancelling and saving.
extension _PicPosExchangeOps on _PicPosOperations {
  /// يفتح وضعَ الاستبدال: نفسُ مُحدِّد الفاتورة ومحرِّرِ الأسطر، يليهما وسمُ
  /// العيب لكلِّ سطر.
  ///
  /// **وبخلاف `_showQuickReturn` لا يحذّر من سلّةٍ عامرة:** السلّةُ هنا هي
  /// سلّةُ البديل، فامتلاؤها هو الحالةُ المقصودةُ لا تعارضاً.
  Future<void> _showExchange() async {
    if (ref.read(posExchangeModeProvider) != null ||
        ref.read(posReturnModeProvider) != null) {
      showPosToast(context, ref,
          tr('أنت في وضعٍ قائمٍ بالفعل — أنهِ الحفظَ أو الإلغاءَ أوّلاً'),
          type: PosNotificationType.info);
      return;
    }

    // `pos_exchange` — كودٌ مبذورٌ منذ البداية وظلّ مسجَّلاً «بلا ميزة» في
    // `permission_enforcement_registry`. الميزةُ وصلت الآن فيُنفَذ الكودُ
    // ويُشطب سطرُه، وهو ما أمسكه الحارسُ المعاكسُ فورَ وصول السطح.
    if (!await _userHasPermissionFresh(PermissionCodes.posExchange)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: tr('استبدال المنتجات'),
        permission: PermissionCodes.posExchange,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    // الاستبدالُ يرتجع **ويبيع**، فالصلاحيتان معاً — ونفسُ بابِ الاستئذان
    // الذي يسلكه المرتجع السريع حين تنقص صلاحيةُ المرتجع.
    if (!await ensureQuickReturnPermission(ref, context)) return;
    if (!mounted) return;
    if (!await _userHasPermissionFresh(PermissionCodes.salesReturnCreate)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: tr('إنشاء استبدال'),
        permission: PermissionCodes.salesReturnCreate,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    final invoice = await showDialog<SalesInvoiceData>(
      context: context,
      builder: (_) => const _QuickReturnInvoicePickerDialog(),
    );
    if (invoice == null || !mounted) return;

    final returnsRepo = ref.read(returnsRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    final items = await returnsRepo.getSalesInvoiceItems(invoice.id);
    if (!mounted) return;
    if (items.isEmpty) {
      showPosToast(context, ref, tr('لا توجد أصنافٌ في هذه الفاتورة'),
          type: PosNotificationType.info);
      return;
    }

    final productIds = items.map((it) => it.productId).toSet().toList();
    final results = await Future.wait([
      productRepo.getProductsByIds(productIds),
      returnsRepo.getReturnedQuantitiesForInvoice(invoice.id),
    ]);
    if (!mounted) return;
    final products = results[0] as List<ProductEntity>;
    final returnedByProduct = results[1] as Map<int, double>;

    final productCache = <int, ProductEntity>{
      for (final p in products) p.id: p,
    };
    final nameById = <int, String>{for (final p in products) p.id: p.name};

    final mode = PosExchangeMode.fromLines(
      invoiceId: invoice.id,
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
      lines: [
        for (final item in items)
          ReturnableLine(
            invoiceItemId: item.id,
            productId: item.productId,
            productName: nameById[item.productId] ?? tr('صنف #{p0}', {'p0': item.productId}),
            soldQty: item.quantity,
            alreadyReturnedQty: returnedByProduct[item.productId] ?? 0,
            unitPrice: item.unitPrice,
            lineTotal: item.total,
          ),
      ],
    );

    // محرِّرُ الأسطر نفسُه — يعمل على `returnLeg` مباشرةً، فلا نسخةَ ثانيةً
    // من سياج الكمية ولا من حساب المرتجع.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickReturnLinesEditorDialog(
        mode: mode.returnLeg,
        invoiceNumber: invoice.invoiceNumber,
      ),
    );
    if (confirmed != true || !mounted) return;

    if (!mode.hasReturnSelection) {
      showPosToast(context, ref, tr('لا توجد كمياتٌ محدَّدةٌ للاستبدال'),
          type: PosNotificationType.info);
      return;
    }

    // وسمُ العيب **لكلِّ سطر** (قرارُ المالك (ب)) — خطوةٌ منفصلةٌ لا تلمس
    // محرِّرَ المرتجع المشحون، فلا تُخاطر بمسارٍ يعمل.
    final marked = await _markDamagedLines(mode);
    if (!marked || !mounted) return;

    setState(() {
      _exchangeInvoice = invoice;
      _exchangeProductCache = productCache;
    });
    ref.read(posExchangeModeProvider.notifier).state = mode;
    _refocusScanner();
  }

  /// يعرض الأسطرَ المختارةَ ليُوسَم المعيبُ منها. الافتراضُ **سليم**: وسمُ
  /// العيب يُتلف المخزونَ فلا يكون افتراضاً صامتاً.
  Future<bool> _markDamagedLines(PosExchangeMode mode) async {
    final selected = mode.effectiveReturnQuantities.keys.toList();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title:  Text(tr('هل من صنفٍ تالف؟')),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Text(
                    tr('الموسومُ تالفاً لا يعود إلى المخزون القابل للبيع.'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final itemId in selected)
                          SwitchListTile(
                            dense: true,
                            title: Text(
                              mode.linesByItemId[itemId]?.productName ??
                                  tr('صنف #{itemId}', {'itemId': itemId}),
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              tr('الكمية {p0}', {'p0': mode.requestedQty[itemId]}),
                              style: const TextStyle(fontSize: 11),
                            ),
                            value: mode.isDamaged(itemId),
                            onChanged: (v) =>
                                setLocal(() => mode.setDamaged(itemId, v)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child:  Text(tr('متابعة')),
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  /// يُنهي وضعَ الاستبدال — **ويُفرّغ الشقَّين معاً**.
  ///
  /// **ولماذا تُفرَّغ سلّةُ البديل كذلك:** أصنافُها أُضيفت بوصفها بديلاً عن
  /// مرتجَعٍ مختار. وإبقاؤها بعد زوال الوضع يحوّلها صامتاً إلى سلّةِ بيعٍ
  /// عاديّة، فيبيع الكاشيرُ البديلَ بثمنٍ كاملٍ ولم يُرتجَع شيءٌ أصلاً — نصفُ
  /// استبدالٍ يُحفظ بالخطأ. والمخرجُ الوحيدُ إلى هنا هو `ESC`/«مسح الكل» خلف
  /// تأكيدٍ صريحٍ يقول إن السلّة ستُفرَّغ، فلا مسحَ صامت.
  ///
  /// ويُنادى كذلك بعد الحفظ الناجح — والسلّةُ حينها مُفرَّغةٌ سلفاً.
  void _cancelExchange() {
    ref.read(posExchangeModeProvider.notifier).state = null;
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() {
      _exchangeInvoice = null;
      _exchangeProductCache = const {};
    });
  }

  /// مسارُ حفظ الاستبدال — الفرعُ الذي يأخذه `_processPaymentAndSave` حين
  /// يكون `posExchangeModeProvider` غيرَ `null`.
  Future<void> _processExchangeSave(PosExchangeMode mode) async {
    final invoice = _exchangeInvoice;
    if (invoice == null || invoice.id != mode.invoiceId) {
      showPosToast(context, ref, tr('تعذّر تحديد الفاتورة الأصليّة للاستبدال'),
          type: PosNotificationType.error);
      _cancelExchange();
      return;
    }

    final returnQuantities = mode.effectiveReturnQuantities;
    if (returnQuantities.isEmpty) {
      showPosToast(context, ref, tr('لا توجد كمياتٌ محدَّدةٌ للاستبدال'),
          type: PosNotificationType.info);
      return;
    }

    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      showPosToast(context, ref, tr('أضِف أصنافَ البديل إلى السلّة أوّلاً'),
          type: PosNotificationType.info);
      return;
    }

    final auth = ref.read(authProvider);
    final userId = auth.user?.id ?? 0;
    final userName = auth.user?.displayName ?? tr('مستخدم');

    // نفسُ مصادر مسار البيع (`CheckoutController`): المخزنُ الفعّال، والفرعُ
    // من الفرع الفعّال، ومركزُ التكلفة من المخزن ثم الفرع. تُقرأ هنا لأن
    // `processExchange` يستقبلها صراحةً — والمصدرُ واحدٌ لا اجتهادٌ ثانٍ.
    final warehouseId = await ref.read(activeWarehouseIdProvider.future);
    if (!mounted) return;
    final branch = await ref.read(branchRepositoryProvider).getActiveBranch();
    if (!mounted) return;

    ExchangeResult result;
    try {
      result = await ref.read(exchangeRepositoryProvider).processExchange(
            originalInvoice: invoice,
            returnQuantities: returnQuantities,
            returnProductCache: _exchangeProductCache,
            replacementItems: cartState.items,
            warehouseId: warehouseId,
            userId: userId,
            userName: userName,
            damagedItemIds: mode.effectiveDamagedItemIds,
            customerId: cartState.selectedCustomerId,
            taxPercent: cartState.taxRate * 100,
            taxEnabled: cartState.taxEnabled,
            // ⚠️ **صفرٌ دائماً.** تمريرُ الفرق خصماً يجعل تقريرَ المبيعات
            // يعرض تنزيلاً لم يحدث — ممنوعٌ صراحةً في المواصفة. الفرقُ
            // يُسوّى نقداً على الدرج لا على سطر الفاتورة.
            discountPercent: 0,
            branchId: branch?.id,
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, tr('فشل الاستبدال: {e}', {'e': e}),
            type: PosNotificationType.error);
      }
      return;
    }

    if (!mounted) return;

    final invoiceNumber = invoice.invoiceNumber;
    // يُفرّغ الشقَّين معاً — السلّةُ داخلَه، فلا نداءَ ثانٍ لـ`clearCart`.
    _cancelExchange();
    setState(() => selectedIndex = null);
    barcodeController.clear();

    // **الرقمُ المعروضُ بعد الحفظ هو أثرُ الدرج المقيسُ داخل المعاملة**، لا
    // فرقُ الإجماليَّين. فاتورةٌ أصليّةٌ بنكيّةٌ تُردّ إلى قناتها بينما البديلُ
    // يُقبض نقداً كاملاً — وعرضُ الفرق حينها يكذب على الكاشير.
    final settlementText = switch (result.direction) {
      ExchangeCashDirection.collect =>
        tr('حُصِّل {p0}', {'p0': NumberUtils.formatCurrency(result.difference)}),
      ExchangeCashDirection.refund =>
        tr('رُدّ {p0}', {'p0': NumberUtils.formatCurrency(result.difference)}),
      ExchangeCashDirection.none => tr('بلا فرق'),
    };
    showPosToast(context, ref,
        tr('تم استبدال فاتورة {invoiceNumber} — {settlementText}', {'invoiceNumber': invoiceNumber, 'settlementText': settlementText}),
        type: PosNotificationType.success);
    _refocusScanner();
  }
}

part of 'picpos_pos_screen.dart';

/// Captures provider access before the screen is disposed and schedules reset.
VoidCallback createQuickReturnModeExitReset(WidgetRef ref) {
  final notifier = ref.read(posReturnModeProvider.notifier);
  return () {
    if (notifier.state == null) return;
    scheduleMicrotask(() => notifier.state = null);
  };
}

/// سطورُ المرتجع من بنود الفاتورة — استُخرجت حرفياً من `_showQuickReturn`
/// (2026-11-04) لتُختبر على فاتورةٍ حقيقيّة (‏`picpos_quick_return_cart_test`).
/// الحركاتُ بوحدة الأساس ومجمّعةٌ حسب المنتج؛ التوزيعُ على السطور يمنع طرحَ
/// المرتجع السابق كاملاً من كلّ سطرٍ مكرّر.
@visibleForTesting
List<ReturnableLine> buildQuickReturnLines({
  required List<SalesInvoiceItem> items,
  required List<ProductEntity> products,
  required Map<int, double> returnedBaseByProduct,
}) {
  final nameById = <int, String>{for (final p in products) p.id: p.name};
  final returnedSaleQtyByLine = distributeReturnedBaseQtyToSaleLines(
    invoiceLines: items.map(
      (item) => (
        invoiceItemId: item.id,
        productId: item.productId,
        saleQuantity: item.quantity,
        quantityInBase: item.quantityInBase,
      ),
    ),
    returnedBaseByProduct: returnedBaseByProduct,
  );
  return <ReturnableLine>[
    for (final item in items)
      ReturnableLine(
        invoiceItemId: item.id,
        productId: item.productId,
        productName:
            nameById[item.productId] ?? tr('صنف #{p0}', {'p0': item.productId}),
        soldQty: item.quantity,
        alreadyReturnedQty: returnedSaleQtyByLine[item.id] ?? 0,
        unitPrice: item.unitPrice,
        lineTotal: item.total,
      ),
  ];
}

/// Quick return mode: entering, cancelling and saving a sales return.
extension _PicPosReturnOps on _PicPosOperations {
  /// زرُّ «مرتجع سريع» في لوحة الدفع — يفتح مُحدِّدَ فاتورةٍ، ثم **سطحَ
  /// اختيار أسطر** (‏`_QuickReturnLinesEditorDialog`) يعرض كلَّ سطرٍ بمباعه
  /// ومرتجعه السابق ومتاحه وسعره، ويترك للكاشير ضبطَ الكميّات (تبدأ صفراً)
  /// قبل التأكيد. لا تعبئةَ تلقائيّةً كاملة — راجعةُ المراجع C1–C3 (جولةُ
  /// إصلاح ١) رفضت التصميمَ الأصليّ («ضغطةٌ واحدةٌ تُرجع الفاتورةَ كلَّها
  /// بلا رؤيةٍ ولا تحكّم»).
  ///
  /// بعد التأكيد فقط يُضبط `posReturnModeProvider` (فتظهر الترويسةُ الحمراء
  /// ويتحوَّل مسارُ الحفظ في `_processPaymentAndSave`، وتُقفَل إضافةُ أصنافٍ
  /// للسلّة — `_handleProductTap`/`_searchBarcode` أعلاه).
  Future<void> _showQuickReturn({SalesInvoiceData? preselected}) async {
    // ملاحظةٌ صغيرة (جولةُ إصلاح ٢): الزرُّ نفسُه معطَّلٌ في اللوحة حين وضعُ
    // المرتجع فعّالٌ بالفعل (‏`picpos_payment_panel.dart`)، فهذا خطُّ دفاعٍ
    // ثانٍ فقط — بلا هذا الفحص، إعادةُ استدعاءٍ (مثلاً من اختصار كيبورد
    // مستقبليّ) كانت ستستبدل فاتورةً وكمياتٍ ضُبطت بعنايةٍ صامتاً.
    if (ref.read(posReturnModeProvider) != null) {
      showPosToast(
        context,
        ref,
        tr('أنت في وضع المرتجع بالفعل — أنهِ الحفظَ أو الإلغاءَ أوّلاً'),
        type: PosNotificationType.info,
      );
      return;
    }

    // `pos_return` كان محروساً في النظير القديم وحدَه (`pos/widgets/
    // pos_header.dart:320,384`) — ملفٌّ لا تبلغه شاشةُ PicPos. بوّابةُ دخولٍ
    // خشنة: مَن لا يملكه لا يدخل وضعَ المرتجع أصلاً — قبل حتى اختيار فاتورة.
    if (!await ensureQuickReturnPermission(ref, context)) return;
    if (!mounted) return;

    // `sales_return_create` — نفسُ صلاحيّة الشاشة المستقلّة
    // (`sales_returns_picpos_screen.dart`)، وبنفس نمط بوّابةِ `posSave`:
    // فحصٌ طازج ثم موافقةُ مسؤول. بوّابةٌ ثانيةٌ أدقّ من `pos_return`
    // فوق — تخصّ إنشاءَ مستند المرتجع نفسه، لا مجرّد الدخول في وضعه.
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

    // I3 (جولةُ إصلاح ١): وضعُ المرتجع لا يكتب على `cartController` عمداً،
    // فسلّةُ بيعٍ قيدَ التحضير تبقى كما هي أثناء التحرير — لكنّ
    // `_processQuickReturnSave` يمسحها بـ`clearCart()` بعد نجاح الحفظ (نفسُ
    // سلوك أيّ حفظٍ ناجح في هذه الشاشة). الكاشيرُ يستحقّ تحذيراً صريحاً قبل
    // أن يدخل مساراً ينتهي بمسح ما بدأه، لا مسحاً صامتاً لاحقاً.
    if (ref.read(cartControllerProvider).items.isNotEmpty) {
      final proceed = await AppConfirmDialog.show(
        context,
        title: tr('سلّةُ بيعٍ قيدَ التحضير'),
        message: tr(
          'في السلّة أصنافُ بيعٍ لم تُحفَظ بعد. الدخولُ في وضع المرتجع يبقيها كما هي أثناء التحرير، لكنّ حفظَ المرتجع سيُفرغها. متابعة؟',
        ),
        confirmLabel: tr('متابعة المرتجع'),
        isDangerous: true,
      );
      if (!proceed || !mounted) return;
    }

    // [preselected] (بند ٧): فاتورةٌ اختارها الكاشير من «الفواتير السابقة» —
    // نتخطّى المنتقي ونفتح محرّرَ الأسطر مباشرةً، وكلُّ البوّابات أعلاه
    // (حارس الوضع، الصلاحيّتان، تحذير السلّة) سارية. المنتقي يفلتر بـ
    // `getInvoicesForReturn` فلا بدّ من إعادة فحص الأهلية صراحةً هنا.
    if (preselected != null && !canReturnFromPreviousInvoices(preselected)) {
      showPosToast(
        context,
        ref,
        tr('لا يمكن إنشاء مرتجع لهذه الفاتورة'),
        type: PosNotificationType.info,
      );
      return;
    }
    final invoice =
        preselected ??
        await showDialog<SalesInvoiceData>(
          context: context,
          builder: (_) => const _QuickReturnInvoicePickerDialog(),
        );
    if (invoice == null || !mounted) return;

    final returnsRepo = ref.read(returnsRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    final items = await returnsRepo.getSalesInvoiceItems(invoice.id);
    if (!mounted) return;
    if (items.isEmpty) {
      showPosToast(
        context,
        ref,
        tr('لا توجد أصنافٌ في هذه الفاتورة'),
        type: PosNotificationType.info,
      );
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
    // بناءُ السطور استُخرج إلى `buildQuickReturnLines` (‏أعلى هذا الملفّ)
    // ليُختبر على فاتورةٍ حقيقيّة في قاعدة اختبار — المنطقُ نفسُه بلا تغيير.
    final lines = buildQuickReturnLines(
      items: items,
      products: products,
      returnedBaseByProduct: returnedByProduct,
    );

    // الكميّاتُ تبدأ صفراً (قرارُ مالكٍ، مهمّةٌ ٦) — لا تعبئةَ تلقائية.
    // `_QuickReturnLinesEditorDialog` هو مَن يملأها، سطراً سطراً، عبر
    // `setQty`/`clearQty` تحت رؤية الكاشير وتحكّمه.
    //
    // `invoiceTotal`/`invoiceDeliveryFee` من ترويسة الفاتورة — نفسُ
    // مدخلَي `ReturnsRepositoryImpl._calculateReturnTotal`، فمبلغُ
    // الاسترداد المعروض (`mode.refundTotal`) يطابق ما يُصرف فعلياً عند
    // الحفظ بالضبط.
    final mode = PosReturnMode.fromLines(
      invoiceId: invoice.id,
      lines: lines,
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickReturnLinesEditorDialog(
        mode: mode,
        invoiceNumber: invoice.invoiceNumber,
      ),
    );
    if (confirmed != true || !mounted) return;

    // حمايةٌ دفاعيّة: المحرِّرُ يمنع التأكيدَ بلا كميةٍ واحدةٍ فأكثر، فهذا لا
    // يجب أن يُرى فعلياً.
    if (mode.requestedQty.values.every((q) => q <= 0)) {
      showPosToast(
        context,
        ref,
        tr('لا توجد كمياتٌ محدَّدةٌ للإرجاع'),
        type: PosNotificationType.info,
      );
      return;
    }

    setState(() {
      _returnInvoice = invoice;
      _returnProductCache = productCache;
    });
    ref.read(posReturnModeProvider.notifier).state = mode;
    _refocusScanner();
  }

  /// يُنهي وضعَ المرتجع بلا حفظ — يفرّغ الحالةَ المحليّةَ والمزوِّدَ معاً.
  void _cancelQuickReturn() {
    ref.read(posReturnModeProvider.notifier).state = null;
    setState(() {
      _returnInvoice = null;
      _returnProductCache = const {};
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // الاستبدال — المردودُ وبديلُه
  // ══════════════════════════════════════════════════════════════════════

  /// مسارُ حفظ المرتجع — الفرعُ الذي يأخذه `_processPaymentAndSave` كلُّه
  /// حين يكون `posReturnModeProvider` غيرَ `null`. المسارُ الإلزاميّ
  /// `returnsRepository.processSalesReturn` — وهو يفرض سقفَ الكمية
  /// (PIR F9: المطلوبُ ≤ الأصليُّ ناقصَ المُرجَع سلفاً). (كان هنا تحذيرٌ من
  /// `ProcessSalesReturnUseCase` بلا سقف — حُذفت 2026-09-02 كوداً ميّتاً.)
  Future<void> _processQuickReturnSave(PosReturnMode mode) async {
    final invoice = _returnInvoice;
    if (invoice == null || invoice.id != mode.invoiceId) {
      // لا يجب أن يحدث: الوضعُ والفاتورةُ يُضبَطان معاً في `_showQuickReturn`
      // ويُفرَّغان معاً في `_cancelQuickReturn`/هنا. حماية دفاعيّة فقط.
      showPosToast(
        context,
        ref,
        tr('تعذّر تحديد الفاتورة الأصليّة للمرتجع'),
        type: PosNotificationType.error,
      );
      _cancelQuickReturn();
      return;
    }

    // إسقاطُ الأصفار: `PosReturnMode.fromLines` تبدأ كلَّ سطرٍ صفراً
    // (قرارُ مالكٍ، مهمّةٌ ٦)، و`processSalesReturn` يعتبر أيَّ سطرٍ غيرَ
    // مذكورٍ = لا إرجاعَ له.
    // (استُخرج إلى `quickReturnQuantitiesOf` ليُختبر مع المحاسبة — بلا تغيير.)
    final returnQuantities = quickReturnQuantitiesOf(mode);

    if (returnQuantities.isEmpty) {
      showPosToast(
        context,
        ref,
        tr('لا توجد كمياتٌ محدَّدةٌ للإرجاع'),
        type: PosNotificationType.info,
      );
      return;
    }

    final auth = ref.read(authProvider);
    final userId = auth.user?.id ?? 0;
    final userName = auth.user?.displayName ?? tr('مستخدم');

    bool success;
    try {
      success = await ref
          .read(returnsRepositoryProvider)
          .processSalesReturn(
            invoice: invoice,
            returnQuantities: returnQuantities,
            productCache: _returnProductCache,
            userId: userId,
            userName: userName,
            // I2 (جولةُ إصلاح ١): محسوبةٌ لا مثبَّتة — `true` زائفةٌ كانت
            // ستختم الفاتورةَ `'returned'` (‏`processSalesReturn` تفعل هذا
            // صراحةً حين `isFullReturn`) فتستبعدها `getInvoicesForReturn`
            // أبداً حتى لو تبقّى فيها مرتجعٌ لم يُطلَب. انظر `computeIsFullReturn`.
            isFullReturn: computeIsFullReturn(mode),
          );
    } catch (e) {
      if (mounted) {
        showPosToast(
          context,
          ref,
          tr('فشل حفظ المرتجع: {e}', {'e': e}),
          type: PosNotificationType.error,
        );
      }
      return;
    }

    if (!mounted) return;
    if (!success) {
      showPosToast(
        context,
        ref,
        tr('تعذّر حفظ المرتجع — راجع الكمياتِ المحدَّدة'),
        type: PosNotificationType.error,
      );
      return;
    }

    final invoiceNumber = invoice.invoiceNumber;
    _cancelQuickReturn();
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() => selectedIndex = null);
    barcodeController.clear();
    showPosToast(
      context,
      ref,
      tr('تم حفظ مرتجع فاتورة {invoiceNumber}', {
        'invoiceNumber': invoiceNumber,
      }),
      type: PosNotificationType.success,
    );
    _refocusScanner();
  }
}

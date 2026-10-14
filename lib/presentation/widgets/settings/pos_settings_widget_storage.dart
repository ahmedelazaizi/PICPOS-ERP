part of 'pos_settings_widget.dart';

extension _PosSettingsWidgetStorage on _PosSettingsWidgetState {
  Future<void> _loadSettings() async {
    final s = ref.read(settingsRepositoryProvider);
    final autoPrint = await s.getSetting('auto_print_receipt');
    final negativeSales = await s.getSetting('enable_negative_sales');
    final showTax = await s.getSetting('show_tax_button_pos');
    final showDiscount = await s.getSetting('show_discount_button_pos');
    final showDrawer = await s.getSetting('show_drawer_button_pos');
    final showExpense = await s.getSetting('show_expense_button_pos');
    final codeType = await s.getSetting('receipt_code_type');
    final workOrder = await s.getSetting('show_work_order_button');
    final delivery = await s.getSetting('show_delivery_button');
    final offers = await s.getSetting('show_offers_button_pos');
    final keyboard = await s.getSetting('show_keyboard_button_pos');
    final invoicePrefix = await s.getSetting('invoice_code_prefix');
    // Per-document-type prefix settings
    final pSalesPos = await s.getSetting('prefix_sales_pos');
    final pSalesManual = await s.getSetting('prefix_sales_manual');
    final pSalesReturn = await s.getSetting('prefix_sales_return');
    final pPurchase = await s.getSetting('prefix_purchase');
    final pPurchaseReturn = await s.getSetting('prefix_purchase_return');
    final pReceiptVoucher = await s.getSetting('prefix_receipt_voucher');
    final pPaymentVoucher = await s.getSetting('prefix_payment_voucher');
    final pQuotation = await s.getSetting('prefix_quotation');
    final showReturn = await s.getSetting('show_return_button_pos');
    final showHold = await s.getSetting('show_hold_button_pos');
    final showExchange = await s.getSetting('show_exchange_button_pos');
    final showBarcode = await s.getSetting('pos_show_barcode');
    final showPricingInquiry = await s.getSetting('pos_show_pricing_inquiry');
    final showSearch = await s.getSetting('pos_show_search');
    final showSaveOnly = await s.getSetting('pos_show_save_only');
    final showSubtotal = await s.getSetting('pos_show_subtotal');
    final showAddCustomer = await s.getSetting('pos_show_add_customer');
    final showProductSort = await s.getSetting('pos_show_product_sort');
    final showProductImages = await s.getSetting('pos_show_product_images');
    final showProductLayoutToggle = await s.getSetting(
      'pos_show_layout_toggle',
    );
    final cartRatioLocked = await s.getSetting('pos_cart_ratio_locked');
    final cartRatioValue = await s.getSetting('pos_cart_ratio_value');
    final productNameFont = await s.getSetting('pos_product_name_font_size');
    final productPriceFont = await s.getSetting('pos_product_price_font_size');
    final receiptFooter = await s.getSetting('receipt_footer');
    // Table POS settings
    final tposBarcode = await s.getSetting('tpos_show_barcode');
    final tposImages = await s.getSetting('tpos_show_product_images');
    final tposSort = await s.getSetting('tpos_show_product_sort');
    final tposCheckout = await s.getSetting('tpos_show_checkout');
    final tposNameFont = await s.getSetting('tpos_name_font_size');
    final tposPriceFont = await s.getSetting('tpos_price_font_size');
    // New POS features
    final showOrderType = await s.getSetting('pos_show_order_type');
    final showAdhocCustomer = await s.getSetting('pos_show_adhoc_customer');
    final preventStacking = await s.getSetting('pos_prevent_item_stacking');
    // Spec 135 NOTE 1 — read the single canonical key (System A). 0 = disabled.
    final timeoutMinutes = await s.getSetting('session_timeout_minutes');
    // New items 1, 2, 3
    final shiftDialogEnabled = await s.getSetting('pos_shift_dialog_enabled');
    final showTopBar = await s.getSetting('app_show_top_bar');
    final stockAlertMode = await s.getSetting('pos_stock_alert_mode');
    final taxRate = await s.getSetting('pos_default_tax_rate');
    final pricesIncludeTax = await s.getSetting('prices_include_tax');
    // Category display
    final catIconSize = await s.getSetting('pos_category_icon_size');
    final catFontSize = await s.getSetting('pos_category_font_size');
    final catSpacing = await s.getSetting('pos_category_spacing');
    final catRunSpacing = await s.getSetting('pos_category_run_spacing');
    final catLabelWidth = await s.getSetting('pos_category_label_width');
    final catShape = await s.getSetting('pos_category_shape');
    final catMaxHeight = await s.getSetting('pos_category_max_height');
    // Grid display
    final gridCols = await s.getSetting('pos_grid_columns');
    final gridSpacing = await s.getSetting('pos_grid_spacing');
    final gridAspect = await s.getSetting('pos_grid_aspect_ratio');
    // POS default warehouse
    final posWhId = await s.getSetting('pos_default_warehouse_id');
    // Feature 006 #4: per-branch override
    final branchId = await ref.read(activeBranchIdProvider.future);
    final perBranchWhId = branchId != null
        ? await s.getSetting('pos_default_warehouse_branch_$branchId')
        : null;

    final invoiceLang = await s.getSetting('invoice_language');

    if (mounted) {
      setState(() {
        _autoPrint = autoPrint == 'true';
        _enableNegativeSales = negativeSales == 'true';
        _receiptFooter = receiptFooter ?? '';
        _showTaxButtonInPOS = showTax != 'false';
        _showDiscountButtonInPOS = showDiscount != 'false';
        _showDrawerButtonInPOS = showDrawer != 'false';
        _showExpenseButtonInPOS = showExpense != 'false';
        _receiptCodeType = codeType ?? 'barcode';
        _invoiceLanguage = invoiceLang ?? 'ar';
        _showWorkOrderButton = workOrder == 'true';
        _showDeliveryButton = delivery != null
            ? delivery == 'true'
            : AppConfig.features.deliveryEnabled;
        _showOffersButton = offers != 'false';
        _showKeyboardButton = keyboard != 'false';
        _invoiceCodePrefix = invoicePrefix ?? '';
        _prefixSalesPos = pSalesPos ?? '';
        _prefixSalesManual = pSalesManual ?? '';
        _prefixSalesReturn = pSalesReturn ?? '';
        _prefixPurchase = pPurchase ?? '';
        _prefixPurchaseReturn = pPurchaseReturn ?? '';
        _prefixReceiptVoucher = pReceiptVoucher ?? '';
        _prefixPaymentVoucher = pPaymentVoucher ?? '';
        _prefixQuotation = pQuotation ?? '';
        _showReturnButtonInPOS = showReturn != 'false';
        _showHoldButtonInPOS = showHold != 'false';
        _showExchangeButtonInPOS = showExchange != 'false';
        _showBarcodeInPOS = showBarcode != 'false';
        _showPricingInquiryInPOS = showPricingInquiry != 'false';
        _showSearchInPOS = showSearch != 'false';
        _showSaveOnlyInPOS = showSaveOnly != 'false';
        _showSubtotalInPOS = showSubtotal != 'false';
        _showAddCustomerInPOS = showAddCustomer != 'false';
        _showProductSortInPOS = showProductSort != 'false';
        _showProductImagesInPOS = showProductImages != 'false';
        _showProductLayoutToggleInPOS = showProductLayoutToggle != 'false';
        _posCartRatioLocked = cartRatioLocked == 'true';
        _posStockAlertMode = stockAlertMode ?? 'zero';
        _posDefaultTaxRate = double.tryParse(taxRate ?? '0.16') ?? 0.16;
        _pricesIncludeTax = pricesIncludeTax == 'true';
        if (cartRatioValue != null) {
          final parsed = double.tryParse(cartRatioValue);
          if (parsed != null && parsed >= 0.3 && parsed <= 0.7)
            _posCartRatioValue = parsed;
        }
        if (productNameFont != null) {
          final parsed = double.tryParse(productNameFont);
          if (parsed != null && parsed >= 10 && parsed <= 24)
            _productNameFontSize = parsed;
        }
        if (productPriceFont != null) {
          final parsed = double.tryParse(productPriceFont);
          if (parsed != null && parsed >= 10 && parsed <= 24)
            _productPriceFontSize = parsed;
        }
        // Table POS
        _tposShowBarcode = tposBarcode != 'false';
        _tposShowProductImages = tposImages != 'false';
        _tposShowProductSort = tposSort != 'false';
        _tposShowCheckout = tposCheckout != 'false';
        if (tposNameFont != null) {
          final parsed = double.tryParse(tposNameFont);
          if (parsed != null && parsed >= 10 && parsed <= 24)
            _tposNameFontSize = parsed;
        }
        if (tposPriceFont != null) {
          final parsed = double.tryParse(tposPriceFont);
          if (parsed != null && parsed >= 10 && parsed <= 24)
            _tposPriceFontSize = parsed;
        }
        _isLoading = false;
        _showOrderTypeInPOS = showOrderType != 'false';
        _showAdhocCustomerInPOS = showAdhocCustomer != 'false';
        _preventItemStacking = preventStacking == 'true';
        // Spec 135 NOTE 1 — derive enable + minutes from the single canonical
        // session_timeout_minutes value (System A semantics: 0 = disabled).
        final parsedTimeout = timeoutMinutes == null
            ? null
            : double.tryParse(timeoutMinutes);
        _posSessionTimeoutEnabled = parsedTimeout == null
            ? true
            : parsedTimeout > 0;
        if (parsedTimeout != null &&
            parsedTimeout >= 1 &&
            parsedTimeout <= 60) {
          _posSessionTimeoutMinutes = parsedTimeout;
        }
        // New items 1, 2, 3
        _posShiftDialogEnabled = shiftDialogEnabled != 'false';
        _showTopBar = showTopBar != 'false';
        _posStockAlertMode = stockAlertMode ?? 'zero';
        // Category display
        if (catIconSize != null) {
          final p = double.tryParse(catIconSize);
          if (p != null) _catIconSize = p.clamp(30, 80);
        }
        if (catFontSize != null) {
          final p = double.tryParse(catFontSize);
          if (p != null) _catFontSize = p.clamp(8, 18);
        }
        if (catSpacing != null) {
          final p = double.tryParse(catSpacing);
          if (p != null) _catSpacing = p.clamp(4, 24);
        }
        if (catRunSpacing != null) {
          final p = double.tryParse(catRunSpacing);
          if (p != null) _catRunSpacing = p.clamp(4, 16);
        }
        if (catLabelWidth != null) {
          final p = double.tryParse(catLabelWidth);
          if (p != null) _catLabelWidth = p.clamp(40, 80);
        }
        _catShape = catShape ?? 'circle';
        if (catMaxHeight != null) {
          final p = double.tryParse(catMaxHeight);
          if (p != null) _catMaxHeight = p.clamp(80, 300);
        }
        // Grid display
        if (gridCols != null) {
          final p = int.tryParse(gridCols);
          if (p != null) _gridColumns = p.clamp(2, 12);
        }
        if (gridSpacing != null) {
          final p = double.tryParse(gridSpacing);
          if (p != null) _gridSpacing = p.clamp(2, 20);
        }
        if (gridAspect != null) {
          final p = double.tryParse(gridAspect);
          if (p != null) _gridAspectRatio = p.clamp(0.5, 1.5);
        }
        // POS default warehouse
        if (posWhId != null) {
          _posDefaultWarehouseId = int.tryParse(posWhId);
        }
        _currentBranchId = branchId;
        if (perBranchWhId != null && perBranchWhId.isNotEmpty) {
          _perBranchWarehouseId = int.tryParse(perBranchWhId);
        }
      });
    }
  }

  /// يعرض تنزيل «البيع بالسالب» على كل الأصناف بعد تشغيل الإعداد العام.
  ///
  /// الإعداد العام لوحده كان بيسمح بالبيع لكن الواجهة في أماكن تفضل تقول
  /// «غير متوفر»، لأن `ProductEntity.isOutOfStock` و`product_list_tile`
  /// بيقروا علم الصنف بس ومش شايفين الإعداد العام. تنزيل القيمة على الأصناف
  /// بيوحّد كل القُرّاء.
  ///
  /// بيتأكد الأول: ده تعديل جماعي على كل صنف، ومش حاجة تحصل بضغطة مفتاح
  /// من غير ما المستخدم يعرف حجمها.
  Future<void> _offerNegativeSaleOnAllProducts() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: tr('تفعيل البيع بالسالب على كل الأصناف'),
      message: tr(
        'الإعداد العام اتشغّل. تحب أفعّل «السماح بالبيع بالسالب» على كل الأصناف النشطة كمان؟\n\nمن غير كده، بعض الشاشات هتفضل تعرض الصنف الناقص كـ«غير متوفر» رغم إن البيع مسموح.\n\nالتفعيل الجماعي بيشغّل بس ولا بيقفل — أي صنف قافل البيع بالسالب يدوياً هيتشغّل، ومفيش حاجة هتتقفل.',
      ),
      confirmLabel: tr('فعّل على كل الأصناف'),
    );
    if (!ok || !mounted) return;

    final dao = ref.read(databaseProvider);
    final changed = await dao.enableNegativeSaleOnAllProducts();
    if (!mounted) return;

    // الأصناف بتتقري من providers مخزَّنة — من غير التبطيل ده الشاشات
    // تفضل معروضة بالقيم القديمة لحد ما حاجة تانية تبطّلها.
    ref.invalidate(allProductsProvider);

    AppToast.show(
      context,
      changed == 0
          ? tr('كل الأصناف كانت مفعّلة أصلاً — مفيش تغيير')
          : tr('اتفعّل البيع بالسالب على {changed} صنف', {'changed': changed}),
      type: ToastType.success,
    );
  }

  Future<void> _saveSettings() async {
    // ── نسبةُ الضريبة: الرفضُ عند المصدر ────────────────────────────────
    //
    // نقطةُ الحفظ واحدةٌ لكلِّ الإعدادات — المحليّةُ أدناه ومزامنةُ الخادم من
    // خريطةٍ في آخر هذه الدالّة — فبوّابةٌ هنا تغطّي المسارين معاً.
    //
    // ولو مُنع الحفظُ، أُطلق المُتحقِّقُ كي يظهر السببُ في الحقل نفسِه لا في
    // رسالةٍ عابرةٍ وحدَها.
    if (blocksSaveForTaxRate(
      touched: _taxRateTouched,
      rate: _posDefaultTaxRate,
    )) {
      _taxRateFormKey.currentState?.validate();
      if (mounted) {
        AppToast.show(
          context,
          tr(
            'نسبةُ الضريبة الافتراضية غير صالحة — صفرٌ (بلا ضريبة) أو ١٪ فأكثر',
          ),
          type: ToastType.error,
        );
      }
      return;
    }

    final s = ref.read(settingsRepositoryProvider);
    await s.saveSetting('auto_print_receipt', _autoPrint.toString());
    await s.saveSetting(
      'enable_negative_sales',
      _enableNegativeSales.toString(),
    );
    await s.saveSetting('receipt_code_type', _receiptCodeType);
    await s.saveSetting('invoice_language', _invoiceLanguage);
    await s.saveSetting('receipt_footer', _receiptFooter);
    await s.saveSetting('show_tax_button_pos', _showTaxButtonInPOS.toString());
    await s.saveSetting(
      'show_discount_button_pos',
      _showDiscountButtonInPOS.toString(),
    );
    await s.saveSetting(
      'show_drawer_button_pos',
      _showDrawerButtonInPOS.toString(),
    );
    await s.saveSetting(
      'show_expense_button_pos',
      _showExpenseButtonInPOS.toString(),
    );
    await s.saveSetting(
      'show_work_order_button',
      _showWorkOrderButton.toString(),
    );
    await s.saveSetting('show_delivery_button', _showDeliveryButton.toString());
    await s.saveSetting('show_offers_button_pos', _showOffersButton.toString());
    await s.saveSetting(
      'show_keyboard_button_pos',
      _showKeyboardButton.toString(),
    );
    await s.saveSetting(
      'invoice_code_prefix',
      _prefixSalesPos.isNotEmpty ? _prefixSalesPos : _invoiceCodePrefix,
    );
    // Per-document-type prefix settings
    await s.saveSetting('prefix_sales_pos', _prefixSalesPos);
    await s.saveSetting('prefix_sales_manual', _prefixSalesManual);
    await s.saveSetting('prefix_sales_return', _prefixSalesReturn);
    await s.saveSetting('prefix_purchase', _prefixPurchase);
    await s.saveSetting('prefix_purchase_return', _prefixPurchaseReturn);
    await s.saveSetting('prefix_receipt_voucher', _prefixReceiptVoucher);
    await s.saveSetting('prefix_payment_voucher', _prefixPaymentVoucher);
    await s.saveSetting('prefix_quotation', _prefixQuotation);

    // Phase 3: fail loud if two document types end up with the same
    // prefix — duplicates would cause invoice numbers to collide and
    // trip the UNIQUE constraint the moment a transaction saves.
    final db = ref.read(databaseProvider);
    final prefixError = await db.validateInvoicePrefixes();
    if (prefixError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prefixError),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    await s.saveSetting(
      'show_return_button_pos',
      _showReturnButtonInPOS.toString(),
    );
    await s.saveSetting(
      'show_hold_button_pos',
      _showHoldButtonInPOS.toString(),
    );
    await s.saveSetting(
      'show_exchange_button_pos',
      _showExchangeButtonInPOS.toString(),
    );
    await s.saveSetting('pos_show_barcode', _showBarcodeInPOS.toString());
    await s.saveSetting(
      'pos_show_pricing_inquiry',
      _showPricingInquiryInPOS.toString(),
    );
    await s.saveSetting('pos_show_search', _showSearchInPOS.toString());
    await s.saveSetting('pos_show_save_only', _showSaveOnlyInPOS.toString());
    await s.saveSetting('pos_show_subtotal', _showSubtotalInPOS.toString());
    await s.saveSetting(
      'pos_show_add_customer',
      _showAddCustomerInPOS.toString(),
    );
    await s.saveSetting(
      'pos_show_product_sort',
      _showProductSortInPOS.toString(),
    );
    await s.saveSetting(
      'pos_show_product_images',
      _showProductImagesInPOS.toString(),
    );
    await s.saveSetting(
      'pos_show_layout_toggle',
      _showProductLayoutToggleInPOS.toString(),
    );
    await s.saveSetting(
      'pos_cart_ratio_locked',
      _posCartRatioLocked.toString(),
    );
    await s.saveSetting('pos_cart_ratio_value', _posCartRatioValue.toString());
    await s.saveSetting(
      'pos_product_name_font_size',
      _productNameFontSize.toString(),
    );
    await s.saveSetting(
      'pos_product_price_font_size',
      _productPriceFontSize.toString(),
    );
    // Table POS settings
    await s.saveSetting('tpos_show_barcode', _tposShowBarcode.toString());
    await s.saveSetting(
      'tpos_show_product_images',
      _tposShowProductImages.toString(),
    );
    await s.saveSetting(
      'tpos_show_product_sort',
      _tposShowProductSort.toString(),
    );
    await s.saveSetting('tpos_show_checkout', _tposShowCheckout.toString());
    await s.saveSetting('tpos_name_font_size', _tposNameFontSize.toString());
    await s.saveSetting('tpos_price_font_size', _tposPriceFontSize.toString());
    // New POS features
    await s.saveSetting('pos_show_order_type', _showOrderTypeInPOS.toString());
    await s.saveSetting(
      'pos_show_adhoc_customer',
      _showAdhocCustomerInPOS.toString(),
    );
    await s.saveSetting(
      'pos_prevent_item_stacking',
      _preventItemStacking.toString(),
    );
    // Spec 135 NOTE 1 — write the single canonical key. Toggle OFF → 0
    // (disabled); ON → the chosen minutes. This is the SAME key General
    // Settings writes, so there is exactly one flag + one minutes + one
    // detector (InactivityDetector).
    await s.saveSetting(
      'session_timeout_minutes',
      (_posSessionTimeoutEnabled ? _posSessionTimeoutMinutes.round() : 0)
          .toString(),
    );
    // New items 1, 2, 3
    await s.saveSetting(
      'pos_shift_dialog_enabled',
      _posShiftDialogEnabled.toString(),
    );
    await s.saveSetting('app_show_top_bar', _showTopBar.toString());
    await s.saveSetting('pos_stock_alert_mode', _posStockAlertMode);
    await s.saveSetting('pos_default_tax_rate', _posDefaultTaxRate.toString());
    await s.saveSetting('prices_include_tax', _pricesIncludeTax.toString());
    // Category display settings
    await s.saveSetting('pos_category_icon_size', _catIconSize.toString());
    await s.saveSetting('pos_category_font_size', _catFontSize.toString());
    await s.saveSetting('pos_category_spacing', _catSpacing.toString());
    await s.saveSetting('pos_category_run_spacing', _catRunSpacing.toString());
    await s.saveSetting('pos_category_label_width', _catLabelWidth.toString());
    await s.saveSetting('pos_category_shape', _catShape);
    await s.saveSetting('pos_category_max_height', _catMaxHeight.toString());
    // Grid display settings
    await s.saveSetting('pos_grid_columns', _gridColumns.toString());
    await s.saveSetting('pos_grid_spacing', _gridSpacing.toString());
    await s.saveSetting('pos_grid_aspect_ratio', _gridAspectRatio.toString());
    // POS default warehouse
    if (_posDefaultWarehouseId != null) {
      await s.saveSetting(
        'pos_default_warehouse_id',
        _posDefaultWarehouseId.toString(),
      );
    } else {
      await s.saveSetting('pos_default_warehouse_id', '');
    }
    // Feature 006 #4: per-branch override
    if (_currentBranchId != null) {
      final key = 'pos_default_warehouse_branch_$_currentBranchId';
      await s.saveSetting(key, _perBranchWarehouseId?.toString() ?? '');
    }
    // ── Client mode: batch-sync ALL settings to server ──
    final allSettings = <String, String>{
      // Receipt & printing
      'auto_print_receipt': _autoPrint.toString(),
      'receipt_code_type': _receiptCodeType,
      'invoice_language': _invoiceLanguage,
      'receipt_footer': _receiptFooter,
      // Action buttons
      'show_tax_button_pos': _showTaxButtonInPOS.toString(),
      'show_discount_button_pos': _showDiscountButtonInPOS.toString(),
      'show_drawer_button_pos': _showDrawerButtonInPOS.toString(),
      'show_expense_button_pos': _showExpenseButtonInPOS.toString(),
      'show_work_order_button': _showWorkOrderButton.toString(),
      'show_delivery_button': _showDeliveryButton.toString(),
      'show_offers_button_pos': _showOffersButton.toString(),
      'show_keyboard_button_pos': _showKeyboardButton.toString(),
      // Document prefixes
      'invoice_code_prefix': _prefixSalesPos.isNotEmpty
          ? _prefixSalesPos
          : _invoiceCodePrefix,
      'prefix_sales_pos': _prefixSalesPos,
      'prefix_sales_manual': _prefixSalesManual,
      'prefix_sales_return': _prefixSalesReturn,
      'prefix_purchase': _prefixPurchase,
      'prefix_purchase_return': _prefixPurchaseReturn,
      'prefix_receipt_voucher': _prefixReceiptVoucher,
      'prefix_payment_voucher': _prefixPaymentVoucher,
      'prefix_quotation': _prefixQuotation,
      // Cart top buttons
      'show_return_button_pos': _showReturnButtonInPOS.toString(),
      'show_hold_button_pos': _showHoldButtonInPOS.toString(),
      'show_exchange_button_pos': _showExchangeButtonInPOS.toString(),
      // Display toggles
      'pos_show_barcode': _showBarcodeInPOS.toString(),
      'pos_show_pricing_inquiry': _showPricingInquiryInPOS.toString(),
      'pos_show_search': _showSearchInPOS.toString(),
      'pos_show_save_only': _showSaveOnlyInPOS.toString(),
      'pos_show_subtotal': _showSubtotalInPOS.toString(),
      'pos_show_add_customer': _showAddCustomerInPOS.toString(),
      'pos_show_product_sort': _showProductSortInPOS.toString(),
      'pos_show_product_images': _showProductImagesInPOS.toString(),
      'pos_show_layout_toggle': _showProductLayoutToggleInPOS.toString(),
      'pos_show_order_type': _showOrderTypeInPOS.toString(),
      'pos_show_adhoc_customer': _showAdhocCustomerInPOS.toString(),
      'pos_prevent_item_stacking': _preventItemStacking.toString(),
      // Cart settings
      'pos_cart_ratio_locked': _posCartRatioLocked.toString(),
      'pos_cart_ratio_value': _posCartRatioValue.toString(),
      'pos_product_name_font_size': _productNameFontSize.toString(),
      'pos_product_price_font_size': _productPriceFontSize.toString(),
      // Shift & security
      'pos_shift_dialog_enabled': _posShiftDialogEnabled.toString(),
      'app_show_top_bar': _showTopBar.toString(),
      'pos_stock_alert_mode': _posStockAlertMode,
      'pos_default_tax_rate': _posDefaultTaxRate.toString(),
      'prices_include_tax': _pricesIncludeTax.toString(),
      // Spec 135 NOTE 1 — single canonical key (0 = disabled).
      'session_timeout_minutes':
          (_posSessionTimeoutEnabled ? _posSessionTimeoutMinutes.round() : 0)
              .toString(),
      // Table POS settings
      'tpos_show_barcode': _tposShowBarcode.toString(),
      'tpos_show_product_images': _tposShowProductImages.toString(),
      'tpos_show_product_sort': _tposShowProductSort.toString(),
      'tpos_show_checkout': _tposShowCheckout.toString(),
      'tpos_name_font_size': _tposNameFontSize.toString(),
      'tpos_price_font_size': _tposPriceFontSize.toString(),
      // Category display settings
      'pos_category_icon_size': _catIconSize.toString(),
      'pos_category_font_size': _catFontSize.toString(),
      'pos_category_spacing': _catSpacing.toString(),
      'pos_category_run_spacing': _catRunSpacing.toString(),
      'pos_category_label_width': _catLabelWidth.toString(),
      'pos_category_shape': _catShape,
      'pos_category_max_height': _catMaxHeight.toString(),
      // Grid display settings
      'pos_grid_columns': _gridColumns.toString(),
      'pos_grid_spacing': _gridSpacing.toString(),
      'pos_grid_aspect_ratio': _gridAspectRatio.toString(),
      // POS default warehouse
      'pos_default_warehouse_id': _posDefaultWarehouseId?.toString() ?? '',
      // Feature 006 #4: per-branch override (only present when branch known)
      if (_currentBranchId != null)
        'pos_default_warehouse_branch_$_currentBranchId':
            _perBranchWarehouseId?.toString() ?? '',
    };
    // Spec 118 (Bug Z) — تغليف saveSettings بـ try/catch لمنع رفع
    // exceptions (خاصة 429 rate limit) لـ PlatformDispatcher. الـ
    // settings المحلية تم حفظها بالفعل أعلاه (s.saveSetting calls)،
    // فالـ server sync fire-and-forget آمن.
    try {
      await ClientWriteInterceptor.saveSettings(allSettings);
    } catch (e) {
      // ignore: avoid_print
      debugPrint('[POS-SETTINGS-SYNC] server sync failed (local saved): $e');
      if (mounted) {
        final isRateLimit =
            e.toString().contains('429') ||
            e.toString().contains('Too many requests');
        AppToast.show(
          context,
          isRateLimit
              ? tr('تم الحفظ محلياً — السيرفر مشغول، ستُزامَن لاحقاً')
              : tr('تم الحفظ محلياً — السيرفر غير متاح، ستُزامَن لاحقاً'),
          type: ToastType.warning,
        );
      }
    }
    if (mounted) {
      // Invalidate all POS-related providers so changes take effect immediately
      ref.invalidate(showTaxButtonInPOSProvider);
      ref.invalidate(showDiscountButtonInPOSProvider);
      ref.invalidate(showDrawerButtonInPOSProvider);
      ref.invalidate(showExpenseButtonInPOSProvider);
      ref.invalidate(receiptCodeTypeProvider);
      ref.invalidate(showWorkOrderButtonProvider);
      ref.invalidate(showDeliveryButtonProvider);
      ref.invalidate(showOffersButtonProvider);
      ref.invalidate(showKeyboardButtonProvider);
      ref.invalidate(invoiceCodePrefixProvider);
      ref.invalidate(showReturnButtonInPOSProvider);
      ref.invalidate(showHoldButtonInPOSProvider);
      ref.invalidate(showExchangeButtonInPOSProvider);
      ref.invalidate(showBarcodeInPOSProvider);
      ref.invalidate(showPricingInquiryInPOSProvider);
      ref.invalidate(showSearchInPOSProvider);
      ref.invalidate(showSaveOnlyInPOSProvider);
      ref.invalidate(showSubtotalInPOSProvider);
      ref.invalidate(showAddCustomerInPOSProvider);
      ref.invalidate(showProductSortInPOSProvider);
      ref.invalidate(showProductImagesProvider);
      ref.invalidate(showProductLayoutToggleInPOSProvider);
      ref.invalidate(productNameFontSizeProvider);
      ref.invalidate(productPriceFontSizeProvider);
      ref.invalidate(posCartRatioLockedProvider);
      ref.invalidate(posCartRatioValueProvider);
      ref.invalidate(showOrderTypeInPOSProvider);
      ref.invalidate(showAdhocCustomerInPOSProvider);
      ref.invalidate(preventItemStackingProvider);
      ref.invalidate(sessionTimeoutProvider); // Spec 135 NOTE 1 — single key
      ref.invalidate(posShiftDialogEnabledProvider);
      ref.invalidate(showTopBarProvider);
      ref.invalidate(posStockAlertModeProvider);
      ref.invalidate(posDefaultTaxRateProvider);
      // Category display
      ref.invalidate(posCategoryIconSizeProvider);
      ref.invalidate(posCategoryFontSizeProvider);
      ref.invalidate(posCategorySpacingProvider);
      ref.invalidate(posCategoryRunSpacingProvider);
      ref.invalidate(posCategoryLabelWidthProvider);
      ref.invalidate(posCategoryShapeProvider);
      ref.invalidate(posCategoryMaxHeightProvider);
      // Grid display
      ref.invalidate(posGridColumnsProvider);
      ref.invalidate(posGridSpacingProvider);
      ref.invalidate(posGridAspectRatioProvider);
      // Warehouse & safe providers — CRITICAL for branch-specific operations
      ref.invalidate(activeWarehouseIdProvider);
      ref.invalidate(posCashSafeIdProvider);
      ref.invalidate(posBankSafeIdProvider);
      AppToast.show(
        context,
        tr('تم حفظ إعدادات البيع السريع'),
        type: ToastType.success,
      );
    }
  }
}

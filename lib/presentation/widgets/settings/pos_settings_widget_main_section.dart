part of 'pos_settings_widget.dart';

extension _PosSettingsWidgetMainSection on _PosSettingsWidgetState {
  Widget _buildMainPOSSection() {
    return _buildSectionCard(
      title: tr('إعدادات البيع السريع الرئيسية'),
      icon: PhosphorIconsBold.shoppingCart,
      iconColor: AppColors.primary,
      children: [
        // ─── إعدادات الوردية والعرض ───
        _groupHeader(tr('إعدادات الوردية والعرض'), _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.clockCountdown,
          tint: _mainTint,
          title: tr('إظهار ديالوج فتح الوردية'),
          settingKey: 'pos_shift_dialog_enabled',
          sub: tr('عند الإغلاق يتم فتح الوردية تلقائياً بدون سؤال'),
          value: _posShiftDialogEnabled,
          onChanged: (v) => setState(() => _posShiftDialogEnabled = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.layout,
          tint: kQuickSaleSections[0].tint,
          title: tr('إظهار شريط التنقل العلوي'),
          settingKey: 'app_show_top_bar',
          sub: tr('إظهار أو إخفاء شريط التنبيهات والتنقل أعلى الشاشة'),
          value: _showTopBar,
          onChanged: (v) => setState(() => _showTopBar = v),
        ),
        _selectRow<String>(
          icon: PhosphorIconsBold.bellRinging,
          tint: AppColors.warning,
          title: tr('وضع تنبيهات المخزون'),
          settingKey: 'pos_stock_alert_mode',
          sub: _posStockAlertMode == 'min_stock'
              ? tr('تنبيه عند الوصول للحد الأدنى')
              : tr('تنبيه فقط عند نفاد المخزون'),
          value: _posStockAlertMode,
          items: [
            DropdownMenuItem(
              value: 'zero',
              child: Text(tr('نفاد المخزون فقط')),
            ),
            DropdownMenuItem(
              value: 'min_stock',
              child: Text(tr('الحد الأدنى')),
            ),
          ],
          onChanged: (v) => setState(() => _posStockAlertMode = v ?? 'zero'),
        ),
        // Feature 022 (follow-up): expose the negative-sales toggle in
        // POS settings — that's where operators expect it. The same
        // setting key is read by sales_transaction_orchestrator on every
        // sale; defaults to false (block) on fresh installs and is
        // preserved as true on existing installs via the boot-time
        // backfill (Cluster 018).
        // ⚠️ الأيقونةُ تتبع الحالةَ: كهرمانيّةٌ حين يُسمح بالسالب وخضراءُ حين
        // يُمنع — إشارةُ خطرٍ لا زينة، فتُنقَل كما هي إلى صفِّ التصميم.
        widget.picposChrome
            ? _toggleRow(
                icon: PhosphorIconsBold.warning,
                tint: _enableNegativeSales
                    ? AppColors.warning
                    : AppColors.success,
                title: tr('السماح بالبيع بالسالب عند نقص المخزون'),
                settingKey: 'enable_negative_sales',
                sub: _enableNegativeSales
                    ? tr(
                        'يمكن للكاشير بيع أصناف خارج المخزون — قد ينتج مخزون سالب.',
                      )
                    : tr(
                        'يمنع البيع عند نفاد المخزون ويظهر تنبيه باللغة العربية.',
                      ),
                value: _enableNegativeSales,
                onChanged: (v) async {
                  setState(() => _enableNegativeSales = v);
                  if (v) await _offerNegativeSaleOnAllProducts();
                },
              )
            : SwitchListTile(
                title: Text(tr('السماح بالبيع بالسالب عند نقص المخزون')),
                subtitle: Text(
                  _enableNegativeSales
                      ? tr(
                          'يمكن للكاشير بيع أصناف خارج المخزون — قد ينتج مخزون سالب.',
                        )
                      : tr(
                          'يمنع البيع عند نفاد المخزون ويظهر تنبيه باللغة العربية.',
                        ),
                ),
                value: _enableNegativeSales,
                onChanged: (v) async {
                  setState(() => _enableNegativeSales = v);
                  if (v) await _offerNegativeSaleOnAllProducts();
                },
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  PhosphorIconsBold.warning,
                  color: _enableNegativeSales
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
        buildDefaultTaxRateTileGuarded(
          field: buildDefaultTaxRateFormField(
            formKey: _taxRateFormKey,
            initialRate: _posDefaultTaxRate,
            onRateChanged: (rate) => setState(() {
              _posDefaultTaxRate = rate;
              _taxRateTouched = true;
            }),
          ),
        ),
        SwitchListTile(
          title: Text(tr('أسعار البيع تشمل الضريبة')),
          subtitle: Text(
            tr('يفصل POS السعر الإجمالي إلى صافي وضريبة عند الحساب'),
          ),
          value: _pricesIncludeTax,
          onChanged: (value) => setState(() => _pricesIncludeTax = value),
          contentPadding: EdgeInsets.zero,
        ),
        // ─── المخزن الافتراضي للبيع السريع ───
        FutureBuilder(
          // نطاقُ النسبة لا كلُّ المخازن: هذا المنتقي يقرّر أين تُخصم بضاعةُ
          // **كلِّ** بيعةٍ على الجهاز/الفرع، فمخزنُ فرعٍ آخرَ هنا يُخطئ نسبةَ
          // مبيعاتٍ كاملةٍ لا فاتورةً واحدة.
          future: ref.read(assignableWarehousesProvider(null).future),
          builder: (context, snapshot) {
            final warehouses = snapshot.data ?? [];
            if (warehouses.isEmpty) return const SizedBox.shrink();
            // والمنتقي الفرعيُّ أضيقُ من العامّ: مخازنُ هذا الفرعِ حصراً بلا
            // احتياطٍ يوسّع — «لا مخزنَ لهذا الفرع» جوابٌ صحيحٌ في شاشةِ
            // إعداداتٍ ولا يوقف عملاً، بخلافِ منتقي الفاتورة.
            final branchWarehouses = _currentBranchId == null
                ? warehouses
                : warehouses
                      .where((w) => w.branchId == _currentBranchId)
                      .toList();
            return Column(
              children: [
                // Feature 006 #4: Per-branch picker. Wins over the global one
                // when set; lets HQ admins assign each branch a default
                // warehouse without juggling per-device overrides.
                if (_currentBranchId != null)
                  ListTile(
                    title: Text(tr('المخزن الافتراضي لـ POS هذا الفرع')),
                    subtitle: Text(
                      tr('يُطبَّق على كل أجهزة هذا الفرع — يسبق الإعداد العام'),
                    ),
                    contentPadding: EdgeInsets.zero,
                    trailing: DropdownButton<int?>(
                      value:
                          branchWarehouses.any(
                            (w) => w.id == _perBranchWarehouseId,
                          )
                          ? _perBranchWarehouseId
                          : null,
                      underline: const SizedBox.shrink(),
                      hint: Text(tr('استخدم الإعداد العام')),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(tr('استخدم الإعداد العام')),
                        ),
                        // ignore: dead_code
                        ...branchWarehouses.map(
                          (w) => DropdownMenuItem<int?>(
                            value: w.id,
                            child: Text(w.name),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _perBranchWarehouseId = v),
                    ),
                  ),
                ListTile(
                  title: Text(tr('المخزن الافتراضي للبيع السريع (عام)')),
                  subtitle: Text(
                    tr('يُستخدم إذا لم يكن هناك إعداد مخصّص للفرع'),
                  ),
                  contentPadding: EdgeInsets.zero,
                  trailing: DropdownButton<int?>(
                    value: warehouses.any((w) => w.id == _posDefaultWarehouseId)
                        ? _posDefaultWarehouseId
                        : null,
                    underline: const SizedBox.shrink(),
                    hint: Text(tr('تلقائي (الافتراضي)')),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(tr('تلقائي (الافتراضي)')),
                      ),
                      // ignore: dead_code
                      ...warehouses.map(
                        (w) => DropdownMenuItem<int?>(
                          value: w.id,
                          child: Text(w.name),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _posDefaultWarehouseId = v),
                  ),
                ),
              ],
            );
          },
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── أزرار الإجراءات السريعة والسلة ───
        _groupHeader(tr('أزرار البيع السريع والسلة'), _mainTint),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: Text(tr('زر الضريبة')),
              selected: _showTaxButtonInPOS,
              onSelected: (v) => setState(() => _showTaxButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('زر الخصم')),
              selected: _showDiscountButtonInPOS,
              onSelected: (v) => setState(() => _showDiscountButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('زر الدرج')),
              selected: _showDrawerButtonInPOS,
              onSelected: (v) => setState(() => _showDrawerButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('زر المصاريف')),
              selected: _showExpenseButtonInPOS,
              onSelected: (v) => setState(() => _showExpenseButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('زر أمر الشغل')),
              selected: _showWorkOrderButton,
              onSelected: (v) => setState(() => _showWorkOrderButton = v),
            ),
            FilterChip(
              label: Text(tr('زر التوصيل')),
              selected: _showDeliveryButton,
              onSelected: (v) => setState(() => _showDeliveryButton = v),
            ),
            FilterChip(
              label: Text(tr('زر العروض')),
              selected: _showOffersButton,
              onSelected: (v) => setState(() => _showOffersButton = v),
            ),
            FilterChip(
              label: Text(tr('لوحة المفاتيح')),
              selected: _showKeyboardButton,
              onSelected: (v) => setState(() => _showKeyboardButton = v),
            ),
            FilterChip(
              label: Text(tr('زر المرتجعات')),
              selected: _showReturnButtonInPOS,
              onSelected: (v) => setState(() => _showReturnButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('أزرار التعليق')),
              selected: _showHoldButtonInPOS,
              onSelected: (v) => setState(() => _showHoldButtonInPOS = v),
            ),
            FilterChip(
              label: Text(tr('زر الاستبدال')),
              selected: _showExchangeButtonInPOS,
              onSelected: (v) => setState(() => _showExchangeButtonInPOS = v),
            ),
          ],
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات ترقيم المستندات ───
        _groupHeader(tr('إعدادات ترقيم المستندات'), _mainTint),
        Text(
          tr(
            'تحديد بادئة الترقيم لكل نوع مستند. اترك الحقل فارغاً للترقيم الافتراضي.',
          ),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        // Sales group
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _prefixSalesPos,
                decoration: InputDecoration(
                  labelText: tr('فاتورة مبيعات (POS)'),
                  hintText: 'R-',
                  prefixIcon: const Icon(PhosphorIconsBold.receipt, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => _prefixSalesPos = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: _prefixSalesManual,
                decoration: InputDecoration(
                  labelText: tr('فاتورة مبيعات (يدوية)'),
                  hintText: 'INV',
                  prefixIcon: const Icon(PhosphorIconsBold.fileText, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => _prefixSalesManual = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _prefixSalesReturn,
                decoration: InputDecoration(
                  labelText: tr('مردودات مبيعات'),
                  hintText: 'RET-',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.arrowUUpLeft,
                    size: 18,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _prefixSalesReturn = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: _prefixQuotation,
                decoration: InputDecoration(
                  labelText: tr('عرض سعر'),
                  hintText: 'QUO',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.clipboardText,
                    size: 18,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _prefixQuotation = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Purchases group
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _prefixPurchase,
                decoration: InputDecoration(
                  labelText: tr('فاتورة مشتريات'),
                  hintText: 'PUR',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.shoppingBag,
                    size: 18,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _prefixPurchase = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: _prefixPurchaseReturn,
                decoration: InputDecoration(
                  labelText: tr('مردودات مشتريات'),
                  hintText: 'PRET',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.arrowUUpRight,
                    size: 18,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _prefixPurchaseReturn = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Treasury group
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _prefixReceiptVoucher,
                decoration: InputDecoration(
                  labelText: tr('سند قبض'),
                  hintText: 'RV',
                  prefixIcon: const Icon(PhosphorIconsBold.arrowDown, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => _prefixReceiptVoucher = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: _prefixPaymentVoucher,
                decoration: InputDecoration(
                  labelText: tr('سند صرف'),
                  hintText: 'PV',
                  prefixIcon: const Icon(PhosphorIconsBold.arrowUp, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => _prefixPaymentVoucher = v,
              ),
            ),
          ],
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── واجهة العرض والتفاعل ───
        _groupHeader(tr('واجهة العرض والتفاعل'), _mainTint),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: Text(tr('حقل الباركود')),
              selected: _showBarcodeInPOS,
              onSelected: (v) => setState(() => _showBarcodeInPOS = v),
            ),
            FilterChip(
              label: Text(tr('تسعير الأصناف (شاشة منبثقة)')),
              selected: _showPricingInquiryInPOS,
              onSelected: (v) => setState(() => _showPricingInquiryInPOS = v),
            ),
            FilterChip(
              label: Text(tr('البحث عن المنتج')),
              selected: _showSearchInPOS,
              onSelected: (v) => setState(() => _showSearchInPOS = v),
            ),
            FilterChip(
              label: Text(tr('الحفظ فقط')),
              selected: _showSaveOnlyInPOS,
              onSelected: (v) => setState(() => _showSaveOnlyInPOS = v),
            ),
            FilterChip(
              label: Text(tr('المجموع الفرعي')),
              selected: _showSubtotalInPOS,
              onSelected: (v) => setState(() => _showSubtotalInPOS = v),
            ),
            FilterChip(
              label: Text(tr('إضافة عميل')),
              selected: _showAddCustomerInPOS,
              onSelected: (v) => setState(() => _showAddCustomerInPOS = v),
            ),
            FilterChip(
              label: Text(tr('نوع الطلب')),
              selected: _showOrderTypeInPOS,
              onSelected: (v) => setState(() => _showOrderTypeInPOS = v),
            ),
            FilterChip(
              label: Text(tr('اسم العميل بالسلة')),
              selected: _showAdhocCustomerInPOS,
              onSelected: (v) => setState(() => _showAdhocCustomerInPOS = v),
            ),
            // العنوان بيقول «أصناف الميزان» صراحةً لأن ده اللي الإعداد بيعمله
            // فعلاً: أصناف العدد والحبة بتتراكم دايماً مهما كان (شوف
            // `resolveStackingFlags`). العنوان القديم «منع تراكم الأصناف» كان
            // بيوعد بحاجة تانية خالص.
            FilterChip(
              label: Text(tr('منع تراكم أصناف الميزان (سطر لكل وزن)')),
              tooltip: tr(
                'كل وزنة ميزان تنزل في سطر مستقل بدل ما تتجمع. أصناف العدد والحبة بتتراكم دايماً في سطر واحد.',
              ),
              selected: _preventItemStacking,
              onSelected: (v) => setState(() => _preventItemStacking = v),
            ),
          ],
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── أيقونة الصنف وباقي الإعدادات ───
        _groupHeader(tr('عرض المنتجات'), _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.image,
          tint: AppColors.success,
          title: tr('إظهار صور الأصناف'),
          settingKey: 'pos_show_product_images',
          sub: tr('إظهار أو إخفاء صور المنتجات في شبكة البيع السريع'),
          value: _showProductImagesInPOS,
          onChanged: (v) => setState(() => _showProductImagesInPOS = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.sortAscending,
          tint: AppColors.success,
          title: tr('إظهار ترتيب الأصناف'),
          settingKey: 'pos_show_product_sort',
          value: _showProductSortInPOS,
          onChanged: (v) => setState(() => _showProductSortInPOS = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.columns,
          tint: AppColors.success,
          title: tr('إظهار زر طي القائمة'),
          settingKey: 'pos_show_layout_toggle',
          sub: tr('إظهار أو إخفاء زر التحكم في أماكن عرض المنتجات'),
          value: _showProductLayoutToggleInPOS,
          onChanged: (v) => setState(() => _showProductLayoutToggleInPOS = v),
        ),
        if (!widget.picposChrome) const SizedBox(height: 8),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _mainTint,
          title: tr('حجم خط الاسم'),
          settingKey: 'pos_product_name_font_size',
          value: _productNameFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          onChanged: (v) => setState(() => _productNameFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textT,
          tint: _mainTint,
          title: tr('حجم خط السعر'),
          settingKey: 'pos_product_price_font_size',
          value: _productPriceFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          isLast: true,
          onChanged: (v) => setState(() => _productPriceFontSize = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات السلة ───
        _groupHeader(tr('إعدادات السلة'), _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.lockKey,
          tint: AppColors.error,
          title: tr('قفل نسبة عرض السلة'),
          settingKey: 'pos_cart_ratio_locked',
          sub: tr('منع الكاشير من تغيير حجم السلة'),
          value: _posCartRatioLocked,
          isLast: !_posCartRatioLocked,
          onChanged: (v) => setState(() => _posCartRatioLocked = v),
        ),
        if (_posCartRatioLocked) ...[
          if (!widget.picposChrome) const SizedBox(height: 8),
          _sliderRow(
            icon: PhosphorIconsBold.columns,
            tint: _mainTint,
            title: tr('نسبة عرض السلة'),
            settingKey: 'pos_cart_ratio_value',
            sub: tr('٦٠٪ = عمود الأصناف ستون بالمئة والسلة أربعون'),
            value: _posCartRatioValue,
            min: 0.3,
            max: 0.7,
            divisions: 8,
            format: (v) => '${(v * 100).round()}%',
            isLast: true,
            onChanged: (v) => setState(() => _posCartRatioValue = v),
          ),
        ],
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات الأمان ───
        _groupHeader(tr('إعدادات الأمان والحماية'), _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.timer,
          tint: AppColors.warning,
          title: tr('مهلة انتهاء الجلسة'),
          settingKey: 'pos_session_timeout_enabled',
          sub: tr(
            'تسجيل خروج تلقائي عند ترك النظام بدون نشاط (نفس إعداد الإعدادات العامة)',
          ),
          value: _posSessionTimeoutEnabled,
          isLast: !_posSessionTimeoutEnabled,
          onChanged: (v) => setState(() => _posSessionTimeoutEnabled = v),
        ),
        if (_posSessionTimeoutEnabled) ...[
          if (!widget.picposChrome) const SizedBox(height: 8),
          _sliderRow(
            icon: PhosphorIconsBold.hourglass,
            tint: AppColors.warning,
            title: tr('مدة المهلة'),
            legacyTitle: tr('مدة الانتظار (دقائق)'),
            settingKey: 'pos_session_timeout_minutes',
            sub: tr('المفتاح الوحيد المعتمد — صفر يعني تعطيل'),
            value: _posSessionTimeoutMinutes,
            min: 1,
            max: 60,
            divisions: 59,
            labelFormat: (v) => tr('{p0} دقيقة', {'p0': v.round()}),
            isLast: true,
            onChanged: (v) => setState(() => _posSessionTimeoutMinutes = v),
          ),
        ],
      ],
    );
  }
}

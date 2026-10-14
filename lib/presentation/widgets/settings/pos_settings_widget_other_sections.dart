part of 'pos_settings_widget.dart';

extension _PosSettingsWidgetOtherSections on _PosSettingsWidgetState {
  Widget _buildCategoryDisplaySection() {
    return _buildSectionCard(
      title: tr('إعدادات منطقة التصنيفات'),
      icon: PhosphorIconsBold.squaresFour,
      iconColor: AppColors.success,
      children: [
        // في تخطيط التصميم يحمل `QuickSaleSectionHeader` هذا الشرحَ، فتكرارُه
        // هنا سطرٌ ثانٍ بنفس المعنى.
        if (!widget.picposChrome) ...[
          Text(
            tr('تحكم في مظهر أيقونات التصنيفات أسفل منطقة المنتجات'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
        ],
        _sliderRow(
          icon: PhosphorIconsBold.circle,
          tint: _catTint,
          title: tr('حجم الأيقونة'),
          settingKey: 'pos_category_icon_size',
          value: _catIconSize,
          min: 30,
          max: 80,
          divisions: 10,
          onChanged: (v) => setState(() => _catIconSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _catTint,
          title: tr('حجم الخط'),
          legacyTitle: tr('حجم خط الاسم'),
          settingKey: 'pos_category_font_size',
          value: _catFontSize,
          min: 8,
          max: 18,
          divisions: 10,
          onChanged: (v) => setState(() => _catFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsHorizontal,
          tint: _catTint,
          title: tr('التباعد الأفقي'),
          settingKey: 'pos_category_spacing',
          value: _catSpacing,
          min: 4,
          max: 24,
          divisions: 10,
          onChanged: (v) => setState(() => _catSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsVertical,
          tint: _catTint,
          title: tr('تباعد الأسطر'),
          legacyTitle: tr('التباعد الرأسي'),
          settingKey: 'pos_category_run_spacing',
          value: _catRunSpacing,
          min: 4,
          max: 16,
          divisions: 6,
          onChanged: (v) => setState(() => _catRunSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textAlignCenter,
          tint: _catTint,
          title: tr('عرض التسمية'),
          legacyTitle: tr('عرض نص التصنيف'),
          settingKey: 'pos_category_label_width',
          value: _catLabelWidth,
          min: 40,
          max: 80,
          divisions: 8,
          onChanged: (v) => setState(() => _catLabelWidth = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsOutLineVertical,
          tint: _catTint,
          title: tr('أقصى ارتفاع للمنطقة'),
          legacyTitle: tr('ارتفاع المنطقة'),
          settingKey: 'pos_category_max_height',
          sub: tr('ما يزيد يُخفى — الأقسام لا تأكل الشبكة'),
          value: _catMaxHeight,
          min: 80,
          max: 300,
          divisions: 11,
          onChanged: (v) => setState(() => _catMaxHeight = v),
        ),
        if (!widget.picposChrome) const SizedBox(height: 8),
        _selectRow<String>(
          icon: PhosphorIconsBold.shapes,
          tint: _catTint,
          title: tr('شكل الأيقونة'),
          settingKey: 'pos_category_shape',
          value: _catShape,
          isLast: true,
          items: [
            DropdownMenuItem(value: 'circle', child: Text(tr('دائري'))),
            DropdownMenuItem(value: 'rounded', child: Text(tr('مستطيل مدور'))),
          ],
          onChanged: (v) => setState(() => _catShape = v ?? 'circle'),
        ),
      ],
    );
  }

  Widget _buildProductGridSection() {
    return _buildSectionCard(
      title: tr('إعدادات شبكة المنتجات'),
      icon: PhosphorIconsBold.gridFour,
      iconColor: AppColors.info,
      children: [
        if (!widget.picposChrome) ...[
          Text(
            tr('تحكم في عدد وتباعد أيقونات المنتجات في الشبكة'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
        ],
        _sliderRow(
          icon: PhosphorIconsBold.columns,
          tint: _gridTint,
          title: tr('عدد الأعمدة'),
          settingKey: 'pos_grid_columns',
          sub: tr(
            'اثنا عشر عموداً على شاشة عشرة بوصات يجعل الاسم سطراً واحداً مقصوصاً',
          ),
          value: _gridColumns.toDouble(),
          min: 2,
          max: 12,
          divisions: 10,
          onChanged: (v) => setState(() => _gridColumns = v.round()),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.dotsNine,
          tint: _gridTint,
          title: tr('التباعد بين الأيقونات'),
          settingKey: 'pos_grid_spacing',
          value: _gridSpacing,
          min: 2,
          max: 20,
          divisions: 9,
          onChanged: (v) => setState(() => _gridSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.frameCorners,
          tint: _gridTint,
          title: tr('نسبة العرض/الارتفاع'),
          settingKey: 'pos_grid_aspect_ratio',
          sub: tr('أقل من ١ يعني بطاقة أطول من عرضها'),
          value: _gridAspectRatio,
          min: 0.5,
          max: 1.5,
          divisions: 10,
          format: (v) => v.toStringAsFixed(2),
          isLast: true,
          onChanged: (v) => setState(() => _gridAspectRatio = v),
        ),
      ],
    );
  }

  Widget _buildReceiptSection() {
    return _buildSectionCard(
      title: tr('إعدادات الإيصال'),
      icon: PhosphorIconsBold.receipt,
      iconColor: AppColors.info,
      children: [
        // ⚠️ **هذا القسمُ يتفرّع صراحةً لا عبر مساعِدات الصفوف.** ضوابطُه
        // `DropdownButtonFormField` و`TextFormField` بـ`labelText` — أي أنّ
        // التسميةَ **داخلَ** الضابط لا بجانبه. وصفُّ التصميم يضع التسميةَ
        // عنواناً والضابطَ بجواره، فتمريرُها عبر `_selectRow` كان يحوّل
        // ضوابطَ UralCash إلى شكلٍ آخر — والعملُ عليها موقوف.
        if (widget.picposChrome) ...[
          _toggleRow(
            icon: PhosphorIconsBold.printer,
            tint: _receiptTint,
            title: tr('طباعة تلقائية عند البيع'),
            settingKey: 'auto_print_receipt',
            sub: tr('طباعة الإيصال تلقائياً بعد إتمام عملية البيع'),
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
          ),
          _selectRow<String>(
            icon: PhosphorIconsBold.qrCode,
            tint: _receiptTint,
            title: tr('نوع الكود في الإيصال'),
            settingKey: 'receipt_code_type',
            value: _receiptCodeType,
            items: [
              DropdownMenuItem(value: 'barcode', child: Text(tr('باركود'))),
              const DropdownMenuItem(value: 'qr', child: Text('QR Code')),
              DropdownMenuItem(value: 'none', child: Text(tr('بدون'))),
            ],
            onChanged: (v) => setState(() => _receiptCodeType = v ?? 'barcode'),
          ),
          _selectRow<String>(
            icon: PhosphorIconsBold.translate,
            tint: _receiptTint,
            title: tr('لغة طباعة الفاتورة'),
            settingKey: 'invoice_language',
            sub: tr('يبدّل عناوين الأعمدة والمسمّيات على الإيصال'),
            value: _invoiceLanguage,
            items: [
              DropdownMenuItem(value: 'ar', child: Text(tr('العربية'))),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => setState(() => _invoiceLanguage = v ?? 'ar'),
          ),
          QuickSaleSettingRow(
            icon: PhosphorIconsBold.textAlignCenter,
            tint: _receiptTint,
            title: tr('تذييل الإيصال'),
            settingKey: 'receipt_footer',
            sub: tr('سطران كحد أقصى على الحراري ٨٠مم'),
            isLast: true,
            control: SizedBox(
              width: 260,
              child: TextFormField(
                initialValue: _receiptFooter,
                decoration: InputDecoration(
                  hintText: tr('نص يظهر أسفل الإيصال...'),
                  isDense: true,
                ),
                maxLines: 2,
                onChanged: (v) => _receiptFooter = v,
              ),
            ),
          ),
        ] else ...[
          SwitchListTile(
            title: Text(tr('طباعة تلقائية عند البيع')),
            subtitle: Text(tr('طباعة الإيصال تلقائياً بعد إتمام عملية البيع')),
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _receiptCodeType,
            decoration: InputDecoration(
              labelText: tr('نوع الكود في الإيصال'),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 'barcode', child: Text(tr('باركود'))),
              const DropdownMenuItem(value: 'qr', child: Text('QR Code')),
              DropdownMenuItem(value: 'none', child: Text(tr('بدون'))),
            ],
            onChanged: (v) => setState(() => _receiptCodeType = v ?? 'barcode'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _invoiceLanguage,
            decoration: InputDecoration(
              labelText: tr('لغة طباعة الفاتورة'),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 'ar', child: Text(tr('العربية'))),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => setState(() => _invoiceLanguage = v ?? 'ar'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _receiptFooter,
            decoration: InputDecoration(
              labelText: tr('تذييل الإيصال'),
              hintText: tr('نص يظهر أسفل الإيصال...'),
              isDense: true,
            ),
            maxLines: 2,
            onChanged: (v) => _receiptFooter = v,
          ),
        ],
      ],
    );
  }

  Widget _buildTablePOSSection() {
    return _buildSectionCard(
      title: tr('إعدادات نقطة بيع الطاولات'),
      icon: PhosphorIconsBold.table,
      iconColor: AppColors.warning,
      children: [
        if (!widget.picposChrome) ...[
          Text(
            tr('إعدادات تنظيم وتنسيق نقطة بيع الطاولات والصالة'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
        ],
        // ─── واجهة العرض ───
        _groupHeader(tr('واجهة العرض'), _tposTint),
        _toggleRow(
          icon: PhosphorIconsBold.barcode,
          tint: _tposTint,
          title: tr('إظهار حقل الباركود'),
          settingKey: 'tpos_show_barcode',
          sub: tr('إظهار أو إخفاء حقل مسح الباركود'),
          value: _tposShowBarcode,
          onChanged: (v) => setState(() => _tposShowBarcode = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.image,
          tint: _tposTint,
          title: tr('إظهار صور الأصناف'),
          settingKey: 'tpos_show_product_images',
          sub: tr('إظهار أو إخفاء صور المنتجات في شبكة الطاولات'),
          value: _tposShowProductImages,
          onChanged: (v) => setState(() => _tposShowProductImages = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.sortAscending,
          tint: _tposTint,
          title: tr('إظهار ترتيب الأصناف'),
          settingKey: 'tpos_show_product_sort',
          value: _tposShowProductSort,
          onChanged: (v) => setState(() => _tposShowProductSort = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),
        // ─── أزرار الإجراءات ───
        _groupHeader(tr('أزرار الإجراءات'), _tposTint),
        _toggleRow(
          icon: PhosphorIconsBold.money,
          tint: _tposTint,
          title: tr('إظهار زر تحصيل الحساب'),
          settingKey: 'tpos_show_checkout',
          sub: tr('إظهار أو إخفاء زر تحصيل الحساب في سلة الطاولة'),
          value: _tposShowCheckout,
          onChanged: (v) => setState(() => _tposShowCheckout = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),
        // ─── خطوط الأصناف ───
        _groupHeader(tr('حجم خطوط الأصناف'), _tposTint),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _tposTint,
          title: tr('حجم خط الاسم'),
          settingKey: 'tpos_name_font_size',
          value: _tposNameFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          onChanged: (v) => setState(() => _tposNameFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textT,
          tint: _tposTint,
          title: tr('حجم خط السعر'),
          settingKey: 'tpos_price_font_size',
          value: _tposPriceFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          isLast: true,
          onChanged: (v) => setState(() => _tposPriceFontSize = v),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    // في تخطيط التصميم: البطاقةُ إطارٌ بالشعرة بلا ظلٍّ، وترويستُها محذوفةٌ
    // لأنّ `QuickSaleSectionHeader` تعرض العنوانَ والأيقونةَ فوقها — وترويستان
    // بنفس النصّ في لوحةٍ واحدةٍ تكرارٌ يراه المستخدم.
    if (widget.picposChrome) {
      return Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(color: context.picposHairline),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

part of '../invoice_designer_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE DESIGNER — UI: Elements Palette, Build, AppBar, Type Buttons
// ═══════════════════════════════════════════════════════════════════════════

mixin _InvoiceDesignerUIMixin on ConsumerState<InvoiceDesignerScreen> {
  // Abstract — provided by the shell
  InvoiceTemplate? get template;
  List<InvoiceTemplateElement> get elements;
  InvoiceTableSetting? get tableSettings;
  InvoiceTemplateElement? get selectedElement;
  Set<int> get selectedElementIds;
  bool get hasChanges;
  set hasChanges(bool val);
  String get templateType;
  set templateType(String val);
  String get templateCategory;
  set templateCategory(String val);
  String get printLanguage;
  set printLanguage(String val);
  TextEditingController get nameController;
  bool get isLoading;

  // Mixin cross-references
  Future<void> onAddElement(String elementType, {String? variableContent});
  void onElementSelected(InvoiceTemplateElement element, [bool isCtrl = false]);
  void onUpdatePosition(InvoiceTemplateElement element, double x, double y);
  void onUpdateSize(InvoiceTemplateElement element, double width, double height);
  void onElementUpdated(InvoiceTemplateElement element, {bool suppressHasChanges = false});
  void onElementDeleted();
  void onTableSettingsUpdated(InvoiceTableSetting settings);
  Future<void> saveTemplate();
  Future<void> showPreview();
  void onReset();
  Future<void> showTemplatesList();
  Future<void> exportTemplateToFile();
  Future<void> showImportDialog();
  Future<void> importTemplateFromFile();

  Widget buildElementsPalette() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child:  Row(
            children: [
              const Icon(PhosphorIconsBold.listBullets, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('عناصر الفاتورة'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildPaletteSection(tr('معلومات الشركة'), [
                 _PaletteItem(tr('اسم الشركة'), 'variable', 'company_name', PhosphorIconsBold.buildings),
                 _PaletteItem(tr('عنوان الشركة'), 'variable', 'company_address', PhosphorIconsBold.mapPin),
                 _PaletteItem(tr('هاتف الشركة'), 'variable', 'company_phone', PhosphorIconsBold.phone),
                 _PaletteItem(tr('شعار الشركة'), 'image', 'logo', PhosphorIconsBold.image),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('معلومات الفاتورة'), [
                 _PaletteItem(tr('رقم الفاتورة'), 'variable', 'invoice_number', PhosphorIconsBold.hash),
                 _PaletteItem(tr('رقم الطلب'), 'variable', 'order_number', PhosphorIconsBold.listNumbers),
                 _PaletteItem(tr('التاريخ'), 'variable', 'date', PhosphorIconsBold.calendar),
                 _PaletteItem(tr('الوقت'), 'variable', 'time', PhosphorIconsBold.clock),
                 _PaletteItem(tr('الكاشير'), 'variable', 'cashier_name', PhosphorIconsBold.user),
                 _PaletteItem(tr('نوع الدفع'), 'variable', 'payment_method', PhosphorIconsBold.creditCard),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('العميل (مسجل)'), [
                 _PaletteItem(tr('اسم العميل'), 'variable', 'customer_name', PhosphorIconsBold.user),
                 _PaletteItem(tr('هاتف العميل'), 'variable', 'customer_phone', PhosphorIconsBold.phone),
                 _PaletteItem(tr('عنوان العميل'), 'variable', 'customer_address', PhosphorIconsBold.mapPin),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('العميل (نصي)'), [
                 _PaletteItem(tr('اسم العميل النصي'), 'variable', 'adhoc_customer_name', PhosphorIconsBold.userCircle),
                 _PaletteItem(tr('هاتف العميل النصي'), 'variable', 'adhoc_customer_phone', PhosphorIconsBold.phoneCall),
                 _PaletteItem(tr('ملاحظات الفاتورة'), 'variable', 'notes', PhosphorIconsBold.notepad),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('جدول الأصناف'), [
                 _PaletteItem(tr('جدول الأصناف'), 'variable', 'items_table', PhosphorIconsBold.table),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('المبالغ'), [
                 _PaletteItem(tr('الإجمالي الفرعي'), 'variable', 'subtotal', PhosphorIconsBold.currencyDollar),
                 _PaletteItem(tr('الضريبة'), 'variable', 'tax_amount', PhosphorIconsBold.percent),
                 _PaletteItem(tr('الخصم'), 'variable', 'discount', PhosphorIconsBold.tag),
                 _PaletteItem(tr('الإجمالي النهائي'), 'variable', 'grand_total', PhosphorIconsBold.coins),
                 _PaletteItem(tr('المدفوع'), 'variable', 'paid_amount', PhosphorIconsBold.money),
                 _PaletteItem(tr('الباقي'), 'variable', 'change', PhosphorIconsBold.arrowsLeftRight),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('عناصر التصميم'), [
                 _PaletteItem(tr('نص ثابت'), 'text', '', PhosphorIconsBold.textT),
                 _PaletteItem(tr('خط فاصل'), 'line', '', PhosphorIconsBold.lineSegment),
                 _PaletteItem(tr('مستطيل'), 'rectangle', '', PhosphorIconsBold.square),
                 _PaletteItem(tr('صورة'), 'image', '', PhosphorIconsBold.image),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('ملصقات الباركود'), [
                 _PaletteItem(tr('اسم المنتج'), 'variable', 'product_name', PhosphorIconsBold.tag),
                 _PaletteItem(tr('كود المنتج'), 'variable', 'product_code', PhosphorIconsBold.barcode),
                 _PaletteItem(tr('صورة الباركود'), 'variable', 'barcode_image', PhosphorIconsBold.barcode),
                 _PaletteItem(tr('سعر المنتج'), 'variable', 'product_price', PhosphorIconsBold.currencyDollar),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('الإضافات والخيارات'), [
                 _PaletteItem(tr('الإضافات'), 'variable', 'item_additions', PhosphorIconsBold.plusCircle),
                 _PaletteItem(tr('الخيارات'), 'variable', 'item_options', PhosphorIconsBold.faders),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection(tr('حقول إضافية'), [
                const _PaletteItem('QR Code', 'variable', 'qr_code', PhosphorIconsBold.qrCode),
                 _PaletteItem(tr('الرقم الضريبي'), 'variable', 'tax_registration', PhosphorIconsBold.identificationBadge),
                 _PaletteItem(tr('اسم المندوب'), 'variable', 'courier_name', PhosphorIconsBold.motorcycle),
                 _PaletteItem(tr('رقم الوردية'), 'variable', 'shift_number', PhosphorIconsBold.clockCounterClockwise),
              ]),
              if (templateCategory == 'shift_closing') ...[
                const SizedBox(height: 12),
                _buildPaletteSection(tr('ملخص المبيعات'), [
                   _PaletteItem(tr('عدد الفواتير'), 'variable', 'shift_invoice_count', PhosphorIconsBold.receipt),
                   _PaletteItem(tr('إجمالي المبيعات'), 'variable', 'shift_total_sales', PhosphorIconsBold.currencyDollar),
                   _PaletteItem(tr('مصروفات الوردية'), 'variable', 'shift_total_expenses', PhosphorIconsBold.arrowDown),
                   _PaletteItem(tr('مرتجعات نقدية'), 'variable', 'shift_cash_refunds', PhosphorIconsBold.arrowUUpLeft),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection(tr('تسوية النقد'), [
                   _PaletteItem(tr('رصيد النقد (نظام)'), 'variable', 'shift_system_cash', PhosphorIconsBold.coins),
                   _PaletteItem(tr('النقد الفعلي'), 'variable', 'shift_actual_cash', PhosphorIconsBold.money),
                   _PaletteItem(tr('فارق النقد'), 'variable', 'shift_cash_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection(tr('تسوية البطاقة'), [
                   _PaletteItem(tr('رصيد البطاقة (نظام)'), 'variable', 'shift_system_card', PhosphorIconsBold.creditCard),
                   _PaletteItem(tr('البطاقة الفعلي'), 'variable', 'shift_actual_card', PhosphorIconsBold.creditCard),
                   _PaletteItem(tr('فارق البطاقة'), 'variable', 'shift_card_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                // §٥-٢ — «كليك» تدخل في «إجمالي النظام» و«إجمالي الفعلي» تحت،
                // ولم تكن لها عناصرُ تعرضها هنا. فالمصمّمُ لا يملك وضعَها في
                // القالب أصلاً، والمطبوعُ يعرض النقدَ والبطاقةَ بإجماليٍّ
                // يشملها — فلا يجمع.
                _buildPaletteSection(tr('تسوية كليك'), [
                   _PaletteItem(tr('رصيد كليك (نظام)'), 'variable', 'shift_system_click', PhosphorIconsBold.deviceMobile),
                   _PaletteItem(tr('كليك الفعلي'), 'variable', 'shift_actual_click', PhosphorIconsBold.deviceMobile),
                   _PaletteItem(tr('فارق كليك'), 'variable', 'shift_click_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection(tr('الإجماليات'), [
                   _PaletteItem(tr('إجمالي النظام'), 'variable', 'shift_total_system', PhosphorIconsBold.calculator),
                   _PaletteItem(tr('إجمالي الفعلي'), 'variable', 'shift_total_actual', PhosphorIconsBold.wallet),
                   _PaletteItem(tr('الفارق الكلي'), 'variable', 'shift_total_variance', PhosphorIconsBold.chartBar),
                   _PaletteItem(tr('الحالة'), 'variable', 'shift_status', PhosphorIconsBold.checkCircle),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaletteSection(String title, List<_PaletteItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, right: 4),
          child: Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: items.map((item) => _buildPaletteButton(item)).toList()),
      ],
    );
  }

  Widget _buildPaletteButton(_PaletteItem item) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(item.label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );

    return Tooltip(
      message: tr('اسحب للكانفاس أو انقر لإضافة: {p0}', {'p0': item.label}),
      child: Draggable<PaletteDragData>(
        data: PaletteDragData(item.type, item.content),
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(item.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: child,
        ),
        child: InkWell(
          onTap: () => onAddElement(item.type, variableContent: item.content),
          borderRadius: BorderRadius.circular(6),
          child: child,
        ),
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.picposChrome) return _buildPicposBody();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.picposField,
        appBar: buildAppBar(),
        body: _buildEditorColumn(),
      ),
    );
  }

  /// عمودُ المحرّر — شريطُ الأدوات ومحرّرُ الأقسام. مشتركٌ بين القشرتَين
  /// حرفيّاً، فلا نسخةَ ثانيةً منه.
  Widget _buildEditorColumn() {
    return Column(
      children: [
        InvoiceDesignerToolbar(
          onAddElement: onAddElement,
          onSave: saveTemplate,
          onPreview: showPreview,
          onReset: onReset,
          currentTemplate: template,
          currentLanguage: printLanguage,
          onLanguageChanged: (lang) async {
            setState(() => printLanguage = lang);
            // ISS-09: Use repository instead of direct DB access
            await ref.read(settingsRepositoryProvider).saveSetting('print_language', lang);
            ref.invalidate(printLanguageProvider);
          },
        ),
        Expanded(
          child: InvoiceSectionEditor(
            elements: elements,
            tableSettings: tableSettings,
            templateType: templateType,
            templateCategory: templateCategory,
            paperWidth: template?.paperWidth.toDouble() ?? 80,
            onAddElement: (type, {variableContent}) =>
                onAddElement(type, variableContent: variableContent),
            onElementUpdated: (el, {bool suppressHasChanges = false}) => onElementUpdated(el, suppressHasChanges: suppressHasChanges),
            onElementDeleted: onElementDeleted,
            onUpdateTableSettings: onTableSettingsUpdated,
          ),
        ),
      ],
    );
  }

  /// قشرةُ PicPos: ترويسةٌ موحّدةٌ فوقَ **عينِ** أدوات `AppBar` المشتركة.
  ///
  /// الأدواتُ لا تُنسَخ ولا تُختصَر: `buildAppBar()` نفسُها تُبنى وتوضع في
  /// `subHeader` عبر `AppBar` بلا خلفيّةٍ ولا ظلٍّ ولا زرِّ رجوعٍ تلقائيّ —
  /// فالرجوعُ تعطيه ترويسةُ PicPos وحدَها، ووجودُ اثنين يربك.
  ///
  /// ولا حقلَ بحثٍ هنا رغم أنّ `HEADS.designer` يعطي `hint: 'بحث في
  /// العناصر...'`: العناصرُ تعيش داخل `InvoiceSectionEditor` ولا يرشّحها شيء،
  /// فحقلٌ لا يرشّح كزرٍّ لا يعمل. يُبنى حين يُبنى الترشيحُ في المحرّر.
  Widget _buildPicposBody() {
    return PicPosScreenScaffold(
      title: tr('مصمم الفواتير'),
      subtitle: tr('الإعدادات ← الأجهزة والطباعة'),
      icon: PhosphorIconsBold.fileText,
      headerActions: [
        ElevatedButton.icon(
          onPressed: saveTemplate,
          icon: const Icon(PhosphorIconsBold.check, size: 15),
          label:  Text(tr('حفظ القالب')),
        ),
      ],
      subHeader: SizedBox(
        height: kToolbarHeight,
        child: Builder(
          builder: (_) {
            final bar = buildAppBar() as AppBar;
            return AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: context.picposCard,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: bar.title,
              actions: bar.actions,
            );
          },
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: _buildEditorColumn(),
    );
  }

  PreferredSizeWidget buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.fileText),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: nameController,
              decoration:  InputDecoration(hintText: tr('اسم القالب'), border: InputBorder.none, isDense: true),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() => hasChanges = true),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.picposCard, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: templateCategory, isDense: true,
                style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
                items:  [
                  DropdownMenuItem(value: 'receipt', child: Text(tr('البيع السريع'))),
                  DropdownMenuItem(value: 'invoice', child: Text(tr('فواتير المبيعات'))),
                  DropdownMenuItem(value: 'purchase', child: Text(tr('فواتير المشتريات'))),
                  DropdownMenuItem(value: 'kitchen', child: Text(tr('طلبات المطبخ'))),
                  DropdownMenuItem(value: 'quotation', child: Text(tr('عروض الأسعار'))),
                  DropdownMenuItem(value: 'barcode', child: Text(tr('ملصقات الباركود'))),
                  DropdownMenuItem(value: 'shift_closing', child: Text(tr('تقرير إغلاق الوردية'))),
                ],
                onChanged: (val) { if (val != null) setState(() => templateCategory = val); },
              ),
            ),
          ),
        ],
      ),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: context.picposCard, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTypeButton('Thermal', 'thermal'),
              Container(width: 1, height: 24, color: AppColors.primary),
              _buildTypeButton('A4', 'a4'),
              Container(width: 1, height: 24, color: AppColors.primary),
              _buildTypeButton(tr('مطبخ'), 'kitchen'),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(icon: const Icon(PhosphorIconsBold.uploadSimple), tooltip: tr('تصدير التصميم كملف'), onPressed: exportTemplateToFile),
        PopupMenuButton<String>(
          icon: const Icon(PhosphorIconsBold.downloadSimple), tooltip: tr('استيراد تصميم'),
          onSelected: (value) {
            if (value == 'preset') {
              showImportDialog();
            } else if (value == 'file') {
              importTemplateFromFile();
            }
          },
          itemBuilder: (_) => [
             PopupMenuItem(value: 'preset', child: Row(children: [const Icon(PhosphorIconsBold.package, size: 20), const SizedBox(width: 8), Text(tr('نماذج جاهزة'))])),
             PopupMenuItem(value: 'file', child: Row(children: [const Icon(PhosphorIconsBold.fileArrowDown, size: 20), const SizedBox(width: 8), Text(tr('استيراد من ملف'))])),
          ],
        ),
        IconButton(icon: const Icon(PhosphorIconsBold.folder), tooltip: tr('القوالب المحفوظة'), onPressed: showTemplatesList),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildTypeButton(String label, String type) {
    final isSelected = templateType == type;
    return InkWell(
      onTap: () => setState(() { templateType = type; hasChanges = true; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.primary)),
      ),
    );
  }
}

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
          child: const Row(
            children: [
              Icon(PhosphorIconsBold.listBullets, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('عناصر الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildPaletteSection('معلومات الشركة', [
                const _PaletteItem('اسم الشركة', 'variable', 'company_name', PhosphorIconsBold.buildings),
                const _PaletteItem('عنوان الشركة', 'variable', 'company_address', PhosphorIconsBold.mapPin),
                const _PaletteItem('هاتف الشركة', 'variable', 'company_phone', PhosphorIconsBold.phone),
                const _PaletteItem('شعار الشركة', 'image', 'logo', PhosphorIconsBold.image),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('معلومات الفاتورة', [
                const _PaletteItem('رقم الفاتورة', 'variable', 'invoice_number', PhosphorIconsBold.hash),
                const _PaletteItem('رقم الطلب', 'variable', 'order_number', PhosphorIconsBold.listNumbers),
                const _PaletteItem('التاريخ', 'variable', 'date', PhosphorIconsBold.calendar),
                const _PaletteItem('الوقت', 'variable', 'time', PhosphorIconsBold.clock),
                const _PaletteItem('الكاشير', 'variable', 'cashier_name', PhosphorIconsBold.user),
                const _PaletteItem('نوع الدفع', 'variable', 'payment_method', PhosphorIconsBold.creditCard),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('العميل (مسجل)', [
                const _PaletteItem('اسم العميل', 'variable', 'customer_name', PhosphorIconsBold.user),
                const _PaletteItem('هاتف العميل', 'variable', 'customer_phone', PhosphorIconsBold.phone),
                const _PaletteItem('عنوان العميل', 'variable', 'customer_address', PhosphorIconsBold.mapPin),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('العميل (نصي)', [
                const _PaletteItem('اسم العميل النصي', 'variable', 'adhoc_customer_name', PhosphorIconsBold.userCircle),
                const _PaletteItem('هاتف العميل النصي', 'variable', 'adhoc_customer_phone', PhosphorIconsBold.phoneCall),
                const _PaletteItem('ملاحظات الفاتورة', 'variable', 'notes', PhosphorIconsBold.notepad),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('جدول الأصناف', [
                const _PaletteItem('جدول الأصناف', 'variable', 'items_table', PhosphorIconsBold.table),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('المبالغ', [
                const _PaletteItem('الإجمالي الفرعي', 'variable', 'subtotal', PhosphorIconsBold.currencyDollar),
                const _PaletteItem('الضريبة', 'variable', 'tax_amount', PhosphorIconsBold.percent),
                const _PaletteItem('الخصم', 'variable', 'discount', PhosphorIconsBold.tag),
                const _PaletteItem('الإجمالي النهائي', 'variable', 'grand_total', PhosphorIconsBold.coins),
                const _PaletteItem('المدفوع', 'variable', 'paid_amount', PhosphorIconsBold.money),
                const _PaletteItem('الباقي', 'variable', 'change', PhosphorIconsBold.arrowsLeftRight),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('عناصر التصميم', [
                const _PaletteItem('نص ثابت', 'text', '', PhosphorIconsBold.textT),
                const _PaletteItem('خط فاصل', 'line', '', PhosphorIconsBold.lineSegment),
                const _PaletteItem('مستطيل', 'rectangle', '', PhosphorIconsBold.square),
                const _PaletteItem('صورة', 'image', '', PhosphorIconsBold.image),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('ملصقات الباركود', [
                const _PaletteItem('اسم المنتج', 'variable', 'product_name', PhosphorIconsBold.tag),
                const _PaletteItem('كود المنتج', 'variable', 'product_code', PhosphorIconsBold.barcode),
                const _PaletteItem('صورة الباركود', 'variable', 'barcode_image', PhosphorIconsBold.barcode),
                const _PaletteItem('سعر المنتج', 'variable', 'product_price', PhosphorIconsBold.currencyDollar),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('الإضافات والخيارات', [
                const _PaletteItem('الإضافات', 'variable', 'item_additions', PhosphorIconsBold.plusCircle),
                const _PaletteItem('الخيارات', 'variable', 'item_options', PhosphorIconsBold.faders),
              ]),
              const SizedBox(height: 12),
              _buildPaletteSection('حقول إضافية', [
                const _PaletteItem('QR Code', 'variable', 'qr_code', PhosphorIconsBold.qrCode),
                const _PaletteItem('الرقم الضريبي', 'variable', 'tax_registration', PhosphorIconsBold.identificationBadge),
                const _PaletteItem('اسم المندوب', 'variable', 'courier_name', PhosphorIconsBold.motorcycle),
                const _PaletteItem('رقم الوردية', 'variable', 'shift_number', PhosphorIconsBold.clockCounterClockwise),
              ]),
              if (templateCategory == 'shift_closing') ...[
                const SizedBox(height: 12),
                _buildPaletteSection('ملخص المبيعات', [
                  const _PaletteItem('عدد الفواتير', 'variable', 'shift_invoice_count', PhosphorIconsBold.receipt),
                  const _PaletteItem('إجمالي المبيعات', 'variable', 'shift_total_sales', PhosphorIconsBold.currencyDollar),
                  const _PaletteItem('مصروفات الوردية', 'variable', 'shift_total_expenses', PhosphorIconsBold.arrowDown),
                  const _PaletteItem('مرتجعات نقدية', 'variable', 'shift_cash_refunds', PhosphorIconsBold.arrowUUpLeft),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection('تسوية النقد', [
                  const _PaletteItem('رصيد النقد (نظام)', 'variable', 'shift_system_cash', PhosphorIconsBold.coins),
                  const _PaletteItem('النقد الفعلي', 'variable', 'shift_actual_cash', PhosphorIconsBold.money),
                  const _PaletteItem('فارق النقد', 'variable', 'shift_cash_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection('تسوية البطاقة', [
                  const _PaletteItem('رصيد البطاقة (نظام)', 'variable', 'shift_system_card', PhosphorIconsBold.creditCard),
                  const _PaletteItem('البطاقة الفعلي', 'variable', 'shift_actual_card', PhosphorIconsBold.creditCard),
                  const _PaletteItem('فارق البطاقة', 'variable', 'shift_card_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                // §٥-٢ — «كليك» تدخل في «إجمالي النظام» و«إجمالي الفعلي» تحت،
                // ولم تكن لها عناصرُ تعرضها هنا. فالمصمّمُ لا يملك وضعَها في
                // القالب أصلاً، والمطبوعُ يعرض النقدَ والبطاقةَ بإجماليٍّ
                // يشملها — فلا يجمع.
                _buildPaletteSection('تسوية كليك', [
                  const _PaletteItem('رصيد كليك (نظام)', 'variable', 'shift_system_click', PhosphorIconsBold.deviceMobile),
                  const _PaletteItem('كليك الفعلي', 'variable', 'shift_actual_click', PhosphorIconsBold.deviceMobile),
                  const _PaletteItem('فارق كليك', 'variable', 'shift_click_variance', PhosphorIconsBold.plusMinus),
                ]),
                const SizedBox(height: 12),
                _buildPaletteSection('الإجماليات', [
                  const _PaletteItem('إجمالي النظام', 'variable', 'shift_total_system', PhosphorIconsBold.calculator),
                  const _PaletteItem('إجمالي الفعلي', 'variable', 'shift_total_actual', PhosphorIconsBold.wallet),
                  const _PaletteItem('الفارق الكلي', 'variable', 'shift_total_variance', PhosphorIconsBold.chartBar),
                  const _PaletteItem('الحالة', 'variable', 'shift_status', PhosphorIconsBold.checkCircle),
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
      message: 'اسحب للكانفاس أو انقر لإضافة: ${item.label}',
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: buildAppBar(),
        body: Column(
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
        ),
      ),
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
              decoration: const InputDecoration(hintText: 'اسم القالب', border: InputBorder.none, isDense: true),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() => hasChanges = true),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: templateCategory, isDense: true,
                style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'receipt', child: Text('البيع السريع')),
                  DropdownMenuItem(value: 'invoice', child: Text('فواتير المبيعات')),
                  DropdownMenuItem(value: 'purchase', child: Text('فواتير المشتريات')),
                  DropdownMenuItem(value: 'kitchen', child: Text('طلبات المطبخ')),
                  DropdownMenuItem(value: 'quotation', child: Text('عروض الأسعار')),
                  DropdownMenuItem(value: 'barcode', child: Text('ملصقات الباركود')),
                  DropdownMenuItem(value: 'shift_closing', child: Text('تقرير إغلاق الوردية')),
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
            color: Colors.white, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTypeButton('Thermal', 'thermal'),
              Container(width: 1, height: 24, color: AppColors.primary),
              _buildTypeButton('A4', 'a4'),
              Container(width: 1, height: 24, color: AppColors.primary),
              _buildTypeButton('مطبخ', 'kitchen'),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(icon: const Icon(PhosphorIconsBold.uploadSimple), tooltip: 'تصدير التصميم كملف', onPressed: exportTemplateToFile),
        PopupMenuButton<String>(
          icon: const Icon(PhosphorIconsBold.downloadSimple), tooltip: 'استيراد تصميم',
          onSelected: (value) {
            if (value == 'preset') {
              showImportDialog();
            } else if (value == 'file') {
              importTemplateFromFile();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'preset', child: Row(children: [Icon(PhosphorIconsBold.package, size: 20), SizedBox(width: 8), Text('نماذج جاهزة')])),
            const PopupMenuItem(value: 'file', child: Row(children: [Icon(PhosphorIconsBold.fileArrowDown, size: 20), SizedBox(width: 8), Text('استيراد من ملف')])),
          ],
        ),
        IconButton(icon: const Icon(PhosphorIconsBold.folder), tooltip: 'القوالب المحفوظة', onPressed: showTemplatesList),
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

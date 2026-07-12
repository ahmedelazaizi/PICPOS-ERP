import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../../data/database/database.dart';
import 'package:intl/intl.dart' as intl;

class InvoicePreviewDialog extends StatelessWidget {
  final InvoiceTemplate? template;
  final List<InvoiceTemplateElement> elements;
  final InvoiceTableSetting? tableSettings;
  final String templateType;
  final Map<String, String> companyData;

  const InvoicePreviewDialog({
    super.key,
    this.template,
    required this.elements,
    this.tableSettings,
    required this.templateType,
    this.companyData = const {},
  });

  @override
  Widget build(BuildContext context) {
    // Filter to ONLY valid elementTypes — must match the print service filter
    // This ensures preview === print output
    final validElements = List<InvoiceTemplateElement>.from(
      elements.where((e) => e.isVisible && 
        const {'variable', 'text', 'line', 'image', 'rectangle'}.contains(e.elementType)),
    )..sort((a, b) {
        // Primary: sortOrder (respects user's custom drag ordering from section editor)
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;
        // Tiebreaker for equal sortOrder (e.g. fresh seeder templates):
        // use section-priority to ensure logical grouping
        final aPriority = _contentSectionPriority(_resolveType(a));
        final bPriority = _contentSectionPriority(_resolveType(b));
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);
        return a.yPosition.compareTo(b.yPosition);
      });

    // Dedup by resolved content — keep only first occurrence of each content key
    final seenContent = <String>{};
    final sortedElements = <InvoiceTemplateElement>[];
    for (final el in validElements) {
      final key = _resolveType(el);
      if (!seenContent.contains(key)) {
        seenContent.add(key);
        sortedElements.add(el);
      }
    }

    final isThermal = templateType == 'thermal' || templateType == 'kitchen';
    final paperWidthPx = isThermal ? 300.0 : 500.0;

    return Dialog(
      child: Container(
        width: 800,
        height: 900,
        padding: const EdgeInsets.all(32),
        color: Colors.white,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'معاينة الفاتورة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            // ── Paper width indicator ──
            _buildPaperInfoBar(),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    width: paperWidthPx,
                    constraints: const BoxConstraints(minHeight: 300),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: _buildFlowContent(sortedElements),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Paper width info bar — shows paper type, width, and fit indicator
  Widget _buildPaperInfoBar() {
    final isThermal = templateType == 'thermal' || templateType == 'kitchen';
    final paperWidthMm = template?.paperWidth ?? (isThermal ? 80.0 : 210.0);
    final paperTypeName = templateType == 'kitchen'
        ? 'مطبخ (حرارى)'
        : isThermal
            ? 'حرارى'
            : 'A4';

    // Check if any elements have large font sizes that might overflow
    final maxFontSize = elements
        .where((e) => e.isVisible)
        .fold<double>(0, (max, e) => e.fontSize > max ? e.fontSize : max);
    
    // For thermal: fonts > 16pt risk overflow on 79-80mm paper
    final bool hasOverflowRisk = isThermal && maxFontSize > 16;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasOverflowRisk
            ? Colors.orange.shade50
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasOverflowRisk
              ? Colors.orange.shade300
              : Colors.green.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasOverflowRisk ? Icons.warning_amber_rounded : Icons.check_circle,
            color: hasOverflowRisk ? Colors.orange.shade700 : Colors.green.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'نوع الورقة: $paperTypeName  |  العرض: ${paperWidthMm.toStringAsFixed(0)}mm',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const Spacer(),
          if (hasOverflowRisk)
            Text(
              'حجم الخط (${maxFontSize.toStringAsFixed(0)}) قد يتجاوز عرض الورقة',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              'التصميم مناسب لعرض الورقة ✓',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  /// Section priority for ordering — matches section editor's section sequence.
  /// Lower number = appears earlier in the invoice.
  static int _contentSectionPriority(String resolvedType) {
    // Header section (priority 0)
    if (const {'logo', 'company_name', 'company_address', 'company_phone',
               'company_tax_number', 'branch_name'}.contains(resolvedType)) {
      return 0;
    }
    // Invoice info section (priority 1)
    if (const {'invoice_number', 'order_number', 'date', 'time',
               'cashier_name', 'warehouse_name', 'payment_method',
               'sale_type', 'invoice_type_label'}.contains(resolvedType)) {
      return 1;
    }
    // Customer section (priority 2)
    if (const {'customer_name', 'customer_phone', 'customer_address',
               'adhoc_customer_name', 'adhoc_customer_phone',
               'supplier_name', 'table_number', 'waiter_name'}.contains(resolvedType)) {
      return 2;
    }
    // Delivery section (priority 3)
    if (const {'delivery_type', 'delivery_address', 'delivery_fee',
               'courier_name'}.contains(resolvedType)) {
      return 3;
    }
    // Totals section (priority 5 — after items table which is inserted at 4)
    if (const {'subtotal', 'discount', 'tax', 'tax_amount', 'total',
               'total_amount', 'grand_total', 'paid', 'paid_amount',
               'remaining', 'change', 'cash_amount', 'bank_amount',
               'click_amount'}.contains(resolvedType)) {
      return 5;
    }
    // Notes section (priority 6)
    if (const {'notes', 'kitchen_notes'}.contains(resolvedType)) return 6;
    // Footer section (priority 7)
    if (const {'footer_text', 'qr_code', 'tax_registration'}.contains(resolvedType)) return 7;
    // Dividers stay in place
    if (resolvedType == 'divider') return 4;
    // Unknown — put after totals
    return 8;
  }

  /// All known element types that should be rendered
  static const _knownTypes = {
    'logo', 'company_name', 'company_address', 'company_phone', 'company_tax_number',
    'invoice_number', 'order_number', 'date', 'time', 'invoice_type_label',
    'customer_name', 'customer_phone', 'customer_address',
    'adhoc_customer_name', 'adhoc_customer_phone',
    'cashier_name', 'payment_method', 'sale_type',
    'subtotal', 'discount', 'tax', 'tax_amount', 'total', 'total_amount',
    'grand_total', 'paid', 'paid_amount', 'remaining', 'change',
    'cash_amount', 'bank_amount', 'click_amount',
    'delivery_fee', 'delivery_type', 'delivery_address', 'courier_name',
    'notes', 'footer_text', 'qr_code', 'tax_registration',
    'table_number', 'waiter_name', 'kitchen_notes',
    'warehouse_name', 'branch_name', 'supplier_name',
    'divider',
  };

  /// Flow-based content rendering — matches print service's flow logic
  Widget _buildFlowContent(List<InvoiceTemplateElement> sortedElements) {
    // Elements are already filtered to valid types in build()
    final widgets = <Widget>[];
    bool tableInserted = false;
    int i = 0;

    while (i < sortedElements.length) {
      final el = sortedElements[i];
      final resolvedType = _resolveType(el);

      // Insert items table before totals
      if (!tableInserted &&
          (resolvedType == 'subtotal' ||
           resolvedType == 'total' ||
           resolvedType == 'total_amount' ||
           resolvedType == 'discount' ||
           resolvedType == 'tax' ||
           resolvedType == 'tax_amount' ||
           resolvedType == 'paid' ||
           resolvedType == 'remaining')) {
        if (tableSettings != null) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Divider(color: Colors.grey.shade300, height: 1),
          ));
          widgets.add(_buildItemsTable(tableSettings!));
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Divider(color: Colors.grey.shade300, height: 1),
          ));
        }
        tableInserted = true;
      }

      // Check if this element and the next form an inline group (flexWidth < 100)
      if (el.flexWidth < 100 && i + 1 < sortedElements.length) {
        // Collect consecutive inline elements
        final group = <InvoiceTemplateElement>[el];
        while (i + group.length < sortedElements.length &&
            group.last.flexWidth < 100) {
          group.add(sortedElements[i + group.length]);
        }

        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: group
                .map((g) => Expanded(child: _buildElementWidget(g)))
                .toList(),
          ),
        ));
        i += group.length;
      } else {
        // Single element — full width
        widgets.add(_buildElementWidget(el));
        i++;
      }
    }

    // If table hasn't been inserted yet, add at end
    if (!tableInserted && tableSettings != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: Colors.grey.shade300, height: 1),
      ));
      widgets.add(_buildItemsTable(tableSettings!));
    }

    if (widgets.isEmpty) {
      return const Center(
        child: Text('لا توجد عناصر', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  String _resolveType(InvoiceTemplateElement element) {
    String resolvedType = element.elementType;
    if ((resolvedType == 'variable' || resolvedType == 'text') &&
        element.content != null &&
        element.content!.isNotEmpty) {
      resolvedType = element.content!;
    } else if (resolvedType == 'line') {
      resolvedType = 'divider';
    } else if (resolvedType == 'image' && element.content == 'logo') {
      resolvedType = 'logo';
    }
    return resolvedType;
  }

  Widget _buildElementWidget(InvoiceTemplateElement element) {
    final resolvedType = _resolveType(element);
    final style = TextStyle(
      fontSize: element.fontSize,
      fontWeight: element.isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: element.isItalic ? FontStyle.italic : FontStyle.normal,
      color: Color(int.parse(element.fontColor.replaceFirst('#', '0xFF'))),
      fontFamily: _getFontFamily(element.fontFamily),
    );

    switch (resolvedType) {
      case 'divider':
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: Colors.grey.shade400,
        );
      case 'logo':
        // Use element's width (stored as sizePercent * 100, e.g. 40 = 40%)
        final logoWidth = element.width.clamp(15.0, 100.0);
        final alignment = _getTextAlign(element.textAlign) == TextAlign.center
            ? Alignment.center
            : _getTextAlign(element.textAlign) == TextAlign.left
                ? Alignment.centerLeft
                : Alignment.centerRight;
        return Align(
          alignment: alignment,
          child: Container(
            width: logoWidth, height: logoWidth * 0.6,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image, color: Colors.grey, size: 16),
                SizedBox(width: 4),
                Text('LOGO', style: TextStyle(fontSize: 8, color: Colors.grey)),
              ],
            ),
          ),
        );
      case 'qr_code':
        return Center(
          child: Container(
            width: 50, height: 50,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.black,
            child: const Center(
              child: Text('QR', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        );
      case 'company_name':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            companyData['company_name'] ?? 'اسم الشركة',
            textAlign: _getTextAlign(element.textAlign),
            style: style.copyWith(fontWeight: FontWeight.bold, fontSize: element.fontSize.clamp(12, 18)),
          ),
        );
      default:
        // Key-value layout for most elements
        final label = _getLabel(resolvedType);
        final value = _getPlaceholderValue(resolvedType);
        if (label.isNotEmpty) {
          // Totals-like elements
          if (_isTotalField(resolvedType)) {
            final isMainTotal = resolvedType == 'total' || resolvedType == 'total_amount';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: style.copyWith(
                    fontWeight: isMainTotal ? FontWeight.bold : FontWeight.normal,
                  )),
                  Text(value, style: style.copyWith(
                    fontWeight: isMainTotal ? FontWeight.bold : FontWeight.w600,
                    fontSize: (element.fontSize + 1).clamp(10, 18),
                  )),
                ],
              ),
            );
          }
          // Regular field: label: value
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '$label: $value',
              textAlign: _getTextAlign(element.textAlign),
              style: style,
            ),
          );
        }
        // Text or content-based
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            element.content ?? value,
            textAlign: _getTextAlign(element.textAlign),
            style: style,
          ),
        );
    }
  }

  bool _isTotalField(String type) {
    return const {
      'subtotal', 'discount', 'tax', 'tax_amount', 'total',
      'total_amount', 'paid', 'remaining', 'cash_amount',
      'bank_amount', 'click_amount',
    }.contains(type);
  }

  String _getLabel(String type) {
    const labels = {
      'invoice_number': 'رقم الفاتورة',
      'order_number': 'رقم الطلب',
      'date': 'التاريخ',
      'time': 'الوقت',
      'customer_name': 'اسم العميل',
      'customer_phone': 'الهاتف',
      'customer_address': 'العنوان',
      'cashier_name': 'الكاشير',
      'payment_method': 'طريقة الدفع',
      'sale_type': 'نوع البيع',
      'warehouse_name': 'المخزن',
      'branch_name': 'الفرع',
      'company_address': 'عنوان الشركة',
      'company_phone': 'هاتف الشركة',
      'company_tax_number': 'الرقم الضريبي',
      'adhoc_customer_name': 'اسم العميل النصي',
      'adhoc_customer_phone': 'هاتف العميل النصي',
      'supplier_name': 'المورد',
      'subtotal': 'الإجمالي الفرعي',
      'discount': 'الخصم',
      'tax': 'الضريبة',
      'tax_amount': 'الضريبة',
      'total': 'الإجمالي النهائي',
      'total_amount': 'الإجمالي النهائي',
      'paid': 'المدفوع',
      'remaining': 'المتبقي',
      'cash_amount': 'مدفوع نقداً',
      'bank_amount': 'مدفوع بنكياً',
      'click_amount': 'مدفوع كليك',
      'notes': 'ملاحظات الفاتورة',
      'footer_text': 'نص التذييل',
      'delivery_fee': 'رسوم التوصيل',
      'delivery_type': 'نوع التوصيل',
      'delivery_address': 'عنوان التوصيل',
      'courier_name': 'المندوب',
      'table_number': 'رقم الطاولة',
      'waiter_name': 'الويتر',
      'invoice_type_label': 'نوع الفاتورة',
    };
    return labels[type] ?? '';
  }

  String _getPlaceholderValue(String key) {
    final now = DateTime.now();
    // Read decimal places from tableSettings
    int decimalPlaces = 2;
    if (tableSettings?.columnWidths != null) {
      try {
        final decoded = jsonDecode(tableSettings!.columnWidths!) as Map<String, dynamic>;
        if (decoded.containsKey('_decimalPlaces')) {
          decimalPlaces = (decoded['_decimalPlaces'] as num).toInt();
        }
      } catch (_) {}
    }
    final decPattern = decimalPlaces == 0 ? '#,##0' : '#,##0.${'0' * decimalPlaces}';
    final formatter = intl.NumberFormat(decPattern);

    switch (key) {
      case 'invoice_number': return 'R-1234';
      case 'order_number': return '5678';
      case 'date': return intl.DateFormat('yyyy/MM/dd').format(now);
      case 'time': return intl.DateFormat('HH:mm').format(now);
      case 'invoice_type_label': return 'مبيعات';
      case 'customer_name': return 'عميل نقدي';
      case 'customer_phone': return '01012345678';
      case 'customer_address': return 'القاهرة، مصر';
      case 'adhoc_customer_name': return 'محمد أحمد';
      case 'adhoc_customer_phone': return '01023456789';
      case 'supplier_name': return 'مورد تجريبي';
      case 'company_name': return companyData['company_name'] ?? 'سوبر ماركت المدينة';
      case 'company_address': return companyData['company_address'] ?? 'عنوان الشركة';
      case 'company_phone': return companyData['company_phone'] ?? '01000000000';
      case 'company_tax_number': return companyData['company_tax_number'] ?? '123-456-789';
      case 'subtotal': return formatter.format(351.50);
      case 'discount': return formatter.format(5.00);
      case 'tax': case 'tax_amount': return formatter.format(49.21);
      case 'total': case 'total_amount': return formatter.format(395.71);
      case 'paid': return formatter.format(395.71);
      case 'remaining': return formatter.format(0);
      case 'cash_amount': return formatter.format(300.00);
      case 'bank_amount': return formatter.format(95.71);
      case 'click_amount': return formatter.format(0);
      case 'delivery_fee': return formatter.format(25.00);
      case 'delivery_type': return 'توصيل للمنزل';
      case 'delivery_address': return 'شارع التحرير';
      case 'sale_type': return 'نقدي';
      case 'payment_method': return 'نقدي';
      case 'cashier_name': return 'أحمد محمد';
      case 'warehouse_name': return 'المخزن الرئيسي';
      case 'branch_name': return 'الفرع الرئيسي';
      case 'table_number': return '5';
      case 'waiter_name': return 'محمد علي';
      case 'notes': return 'شكراً لتعاملكم معنا';
      case 'footer_text': return 'شكراً لزيارتكم';
      default: return key;
    }
  }

  Widget _buildItemsTable(InvoiceTableSetting settings) {
    // Parse flex ratios from JSON with defaults
    final defaultWidths = <String, double>{
      'index': 0.8, 'product': 3.0, 'code': 1.5,
      'quantity': 1.0, 'price': 1.2, 'discount': 1.0,
      'tax': 1.0, 'total': 1.5, 'unit': 1.0,
      'barcode': 1.5, 'notes': 2.0,
    };
    int decimalPlaces = 2;
    bool showHeader = true;
    try {
      if (settings.columnWidths != null) {
        final Map<String, dynamic> decoded = jsonDecode(settings.columnWidths!);
        decoded.forEach((key, value) {
          if (key == '_decimalPlaces') {
            decimalPlaces = (value as num).toInt();
          } else if (key == '_showHeader') {
            showHeader = value as bool? ?? true;
          } else if (value is num) {
            defaultWidths[key] = value.toDouble();
          }
        });
      }
    } catch (_) {}

    int getFlex(String key) => (defaultWidths[key]! * 10).round();

    final headerFontSize = settings.headerFontSize.clamp(1, 24).toDouble();
    final bodyFontSize = settings.fontSize.clamp(1, 24).toDouble();

    Widget headerFlex(String text, String key) => Expanded(
      flex: getFlex(key),
      child: Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: headerFontSize, color: Colors.white)),
    );
    Widget cellFlex(String text, String key) => Expanded(
      flex: getFlex(key),
      child: Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontSize: bodyFontSize), overflow: TextOverflow.ellipsis),
    );

    // Sample items — use dynamic decimal formatting
    String fmt(num val) => val.toStringAsFixed(decimalPlaces);
    final items = [
      {'idx': '1', 'name': 'أرز بسمتي 5كجم', 'code': 'P001', 'qty': fmt(2), 'price': fmt(100), 'disc': fmt(0), 'tax': fmt(14), 'total': fmt(214), 'unit': 'كجم', 'barcode': '622115', 'notes': ''},
      {'idx': '2', 'name': 'زيت ذرة 1لتر', 'code': 'P002', 'qty': fmt(1), 'price': fmt(50), 'disc': fmt(5), 'tax': fmt(7), 'total': fmt(52), 'unit': 'قطعة', 'barcode': '622116', 'notes': ''},
      {'idx': '3', 'name': 'برجر لحم', 'code': 'P003', 'qty': fmt(1), 'price': fmt(85), 'disc': fmt(0), 'tax': fmt(12), 'total': fmt(97), 'unit': 'قطعة', 'barcode': '622117', 'notes': 'حار'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // Header
          if (showHeader)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Row(children: [
              if (settings.showIndex) headerFlex('م', 'index'),
              if (settings.showProductName) headerFlex('المنتج', 'product'),
              if (settings.showProductCode) headerFlex('الكود', 'code'),
              if (settings.showQuantity) headerFlex('العدد', 'quantity'),
              if (settings.showUnitPrice) headerFlex('السعر', 'price'),
              if (settings.showUnit) headerFlex('الوحدة', 'unit'),
              if (settings.showDiscount) headerFlex('خصم', 'discount'),
              if (settings.showTax) headerFlex('ض', 'tax'),
              if (settings.showTotal) headerFlex('الإجمالي', 'total'),
              if (settings.showBarcode) headerFlex('باركود', 'barcode'),
              if (settings.showNotes) headerFlex('ملاحظات', 'notes'),
            ]),
          ),
          // Rows
          for (final item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(children: [
                if (settings.showIndex) cellFlex(item['idx']!, 'index'),
                if (settings.showProductName) cellFlex(item['name']!, 'product'),
                if (settings.showProductCode) cellFlex(item['code']!, 'code'),
                if (settings.showQuantity) cellFlex(item['qty']!, 'quantity'),
                if (settings.showUnitPrice) cellFlex(item['price']!, 'price'),
                if (settings.showUnit) cellFlex(item['unit']!, 'unit'),
                if (settings.showDiscount) cellFlex(item['disc']!, 'discount'),
                if (settings.showTax) cellFlex(item['tax']!, 'tax'),
                if (settings.showTotal) cellFlex(item['total']!, 'total'),
                if (settings.showBarcode) cellFlex(item['barcode']!, 'barcode'),
                if (settings.showNotes) cellFlex(item['notes']!, 'notes'),
              ]),
            ),
        ],
      ),
    );
  }

  TextAlign _getTextAlign(String align) {
    switch (align) {
      case 'left': return TextAlign.left;
      case 'center': return TextAlign.center;
      case 'right': return TextAlign.right;
      default: return TextAlign.right;
    }
  }

  String _getFontFamily(String? fontFamily) {
    switch (fontFamily) {
      case 'Cairo': return 'Cairo';
      case 'Tajawal': return 'Tajawal';
      case 'IBM Plex Sans Arabic': return 'IBM Plex Sans Arabic';
      default: return 'Cairo';
    }
  }
}

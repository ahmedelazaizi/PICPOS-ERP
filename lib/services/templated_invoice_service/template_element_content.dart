// TemplatedInvoiceService - builds the content of one template element.
part of '../templated_invoice_service.dart';

/// Flow-layout element content builder of [TemplatedInvoiceService].
abstract final class _TemplatedElementContent {
  /// بناء محتوى عنصر واحد من القالب (resolvedType تم حله بالفعل في الـ caller)
  ///
  /// [shift] — لقطةُ إقفال الوردية حين يكون المطبوعُ تقريرَ وردية. تُقرأ
  /// **قبل** جدول الفاتورة كي تُحلَّ أنواعُ `shift_*` التي يعرضها المحرر.
  ///
  /// [statement] — لقطةُ كشف الحساب، بنفس العقد: تُسأل قبل جدول الفاتورة
  /// وتُرجع `null` لما ليس لها.
  static pw.Widget _buildElementContent({
    required String resolvedType,
    required InvoiceTemplateElement element,
    ShiftClosingSnapshot? shift,
    PartyStatementSnapshot? statement,
    required String invoiceNumber,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    required double remaining,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    String? companyTaxId,
    String paymentMethod = 'نقدي',
    InvoiceTableSetting? tableSettings,
    Uint8List? logoBytes,
    String? cashierName,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? salesType,
    String? orderNumber,
    String? platformOrderNumber,
    double? cashAmount,
    double? bankAmount,
    ReceiptQr? receiptQr,
    String? companyNameEn,
    String? companyCrNumber,
    String locale = 'ar',
  }) {
    final style = _TemplatedItemsTable._getStyle(element);
    final align = _TemplatedItemsTable._getAlignment(element.textAlign);
    // تُطهِّر labelAr وcontent من emoji قبل وصولهما إلى pw.Text.
    // باقي الكود يستخدم eLbl وeCnt بدلاً من element.labelAr و element.content.
    final eLbl = element.labelAr != null ? sanitizeForPdf(element.labelAr!) : null;
    final eCnt = element.content != null ? sanitizeForPdf(element.content!) : null;
    String lbl(String? elLabel, String fallback) {
      final s = sanitizeForPdf(elLabel ?? '');
      return s.isEmpty ? fallback : s;
    }

    // عناصرُ الورديّة أولاً: أنواعُها لا تتقاطع مع أنواع الفاتورة، والمُحلِّل
    // يرجّع `null` لأيّ نوعٍ ليس منها — فلا يخطف شيئاً.
    if (shift != null) {
      final shiftValue = TemplatedInvoiceService.resolveShiftValue(resolvedType, shift);
      if (shiftValue != null) {
        final label = lbl(eLbl?.trim(), '');
        return pw.Text(
          label.isEmpty ? shiftValue : '$label: $shiftValue',
          style: style,
          textAlign: align,
        );
      }
    }

    // وكشفُ الحساب بنفس العقد — يُسأل قبل جدول الفاتورة ويُرجع `null` لما
    // ليس له. و`''` منه تعني «حقلي وقيمتُه فارغة» فيُطوى العنصرُ ولا يترك
    // تسميةً معلَّقة.
    if (statement != null) {
      final v = pv.resolvePartyStatementValue(resolvedType, statement,
          decimals: _docDecimals);
      if (v != null) {
        if (v.isEmpty) return pw.SizedBox();
        final label = lbl(eLbl?.trim(), '');
        return pw.Text(
          label.isEmpty ? v : '$label: $v',
          style: style,
          textAlign: align,
        );
      }
    }

    switch (resolvedType) {
      // Company Info
      case 'company_name':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Text(
            companyMainName(
                nameAr: companyName, nameEn: companyNameEn, locale: locale),
            style: style,
            textAlign: align,
          ),
        );
      case 'company_name_en':
        final nameEn = companySecondaryName(
            nameAr: companyName, nameEn: companyNameEn, locale: locale);
        return nameEn.isEmpty
            ? pw.SizedBox()
            : pw.Text(nameEn, style: style, textAlign: align);
      case 'company_cr_number':
        final crLine = companyCrLine(companyCrNumber, locale: locale);
        return crLine.isEmpty
            ? pw.SizedBox()
            : pw.Text(crLine, style: style, textAlign: align);
      case 'company_address':
        return pw.Text(companyAddress, style: style, textAlign: align);
      case 'company_phone':
        // ⚠️ `ltrIsolate` هنا **أيضاً**: هذا المسارُ (v1) يبني نصَّه بنفسه
        // ولا يمرُّ بـ`resolveContentValue`، فإصلاحُ ذاك وحدَه ترك الحراريَّ
        // مقلوباً — مقيسٌ بمسبار، لا مفترَض.
        return pw.Text('هاتف: ${pv.ltrIsolate(companyPhone)}',
            style: style, textAlign: align);
      case 'company_tax_id':
        return companyTaxId != null
            ? pw.Text(
                'السجل الضريبي: ${companyTaxWithCr(taxId: companyTaxId, crNumber: companyCrNumber, locale: locale)}',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'logo':
        if (logoBytes != null && logoBytes.isNotEmpty) {
          final image = pw.MemoryImage(logoBytes);
          return pw.Center(
            child: pw.Image(
              image,
              width: element.width,
              height: element.height,
              fit: pw.BoxFit.contain,
            ),
          );
        }
        // ⚠️ **بلا شعارٍ ⇒ لا شيء، لا صندوقٌ مكتوبٌ فيه `LOGO`.**
        //
        // كانت الكلمةُ الإنجليزيّةُ تصل ورقةَ العميل في سبعَ عشرةَ بصمةً
        // ذهبيّةً من سبعٍ وعشرين — كلُّ فواتير A4 وكشوفِ الحساب وإيصالاتٍ
        // حراريّة. وصندوقٌ فارغٌ في مستندٍ ماليٍّ ليس نائباً عن شعار؛ هو
        // عيبُ طباعةٍ يراه المشتري.
        //
        // ونظيرُه في هذا الملفّ: الرقمُ الضريبيُّ الغائبُ يُرجع `pw.SizedBox()`
        // ولا يطبع «TAX ID».
        return pw.SizedBox();

      // Invoice Info
      case 'invoice_title':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            eCnt ?? 'فاتورة مبيعات',
            style: style,
            textAlign: align,
          ),
        );
      case 'invoice_number':
        return pw.Text(
          '${eLbl ?? 'رقم الفاتورة'}: $invoiceNumber',
          style: style,
          textAlign: align,
        );
      case 'date':
        return pw.Text(
          '${eLbl ?? 'التاريخ'}: ${date.day}/${date.month}/${date.year}',
          style: style,
          textAlign: align,
        );
      case 'time':
        return pw.Text(
          '${eLbl ?? 'الوقت'}: ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          style: style,
          textAlign: align,
        );
      case 'cashier_name':
        return pw.Text(
          '${eLbl ?? 'الكاشير'}: ${cashierName ?? ''}',
          style: style,
          textAlign: align,
        );
      case 'order_number':
        final orderLabel = eLbl?.trim().isNotEmpty == true ? eLbl! : 'رقم الطلب';
        return pw.Text(
          '$orderLabel: ${platformOrderNumber ?? orderNumber ?? invoiceNumber}',
          style: style,
          textAlign: align,
        );
      case 'table_number':
        final tableValue = platformOrderNumber ?? adhocCustomerName ?? customerName ?? '';
        if (tableValue.isEmpty) return pw.SizedBox();
        final tableLabel = eLbl?.trim().isNotEmpty == true ? eLbl! : 'رقم الطاولة';
        return pw.Text(
          '$tableLabel: $tableValue',
          style: style,
          textAlign: align,
        );
      case 'payment_method':
        return pw.Text(
          '${eLbl ?? 'طريقة الدفع'}: '
          '${TemplatedInvoiceService.mapPaymentMethodLabel(paymentMethod)}',
          style: style,
          textAlign: align,
        );

      // Customer Info
      case 'customer':
        return customerName != null
            ? pw.Text(
                '${eLbl ?? 'العميل'}: $customerName',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'customer_phone':
        return customerPhone != null
            ? pw.Text(
                '${eLbl ?? 'الهاتف'}: ${pv.ltrIsolate(customerPhone)}',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'customer_address':
        return customerAddress != null
            ? pw.Text(
                '${eLbl ?? 'العنوان'}: $customerAddress',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'adhoc_customer_name':
        return adhocCustomerName != null && adhocCustomerName.isNotEmpty
            ? pw.Text(
                '${eLbl ?? 'اسم العميل'}: $adhocCustomerName',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'adhoc_customer_phone':
        return adhocCustomerPhone != null && adhocCustomerPhone.isNotEmpty
            ? pw.Text(
                '${eLbl ?? 'هاتف العميل'}: ${pv.ltrIsolate(adhocCustomerPhone)}',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();

      // Items Table
      case 'items_table':
        return _TemplatedItemsTable._buildItemsTable(items, tableSettings, style);

      // Totals
      case 'subtotal':
        return _TemplatedItemsTable._totalRow(
          eLbl ?? 'المجموع الفرعي',
          subtotal,
          style,
          align,
        );
      case 'discount':
        return discount > 0
            ? _TemplatedItemsTable._totalRow(
                eLbl ?? 'الخصم',
                discount,
                style,
                align,
                isSubtraction: true,
              )
            : pw.SizedBox();
      case 'tax':
        return tax > 0
            ? _TemplatedItemsTable._totalRow(eLbl ?? 'الضريبة', tax, style, align)
            : pw.SizedBox();
      case 'total':
        return _TemplatedItemsTable._totalRow(
          eLbl ?? 'الإجمالي',
          total,
          style.copyWith(fontWeight: pw.FontWeight.bold),
          align,
        );
      case 'paid':
        return _TemplatedItemsTable._totalRow(eLbl ?? 'المدفوع', paid, style, align);
      case 'remaining':
        return _TemplatedItemsTable._totalRow(
          eLbl ?? 'المتبقي',
          remaining,
          style.copyWith(color: remaining > 0 ? PdfColors.red : null),
          align,
        );
      case 'delivery_fee':
        return deliveryFee > 0
            ? _TemplatedItemsTable._totalRow(eLbl ?? 'رسوم التوصيل', deliveryFee, style, align)
            : pw.SizedBox();

      // Info-only fields (label: value)
      case 'sale_type':
      case 'invoice_type_label':
        final saleLabel = salesType != null && salesType.isNotEmpty
            ? _TemplatedInvoiceValues._mapSaleTypeLabel(salesType)
            : paymentMethod;
        // ⚠️ كانت تُرجع القيمةَ عاريةً وتتجاهل `labelAr` — فيُطبع «مبيعات»
        // بلا عنوانٍ بجوار «طريقة الدفع: نقدي» المُسمّاة، فيقرؤها المشغّلُ
        // كلمةً شاردة. جاراتُها كلُّها تسبق القيمةَ بتسميتها (‏`supplier_name`
        // تحتها مباشرةً مثالاً). رُصد على ورق 2026-08-12.
        final saleTypeLabel = eLbl ?? _TemplatedInvoiceValues._getLabel(resolvedType);
        return pw.Text(
          saleTypeLabel.isEmpty
  // ignore: dead_code
              ? (saleLabel ?? '')
  // ignore: dead_code
              : '$saleTypeLabel: ${saleLabel ?? ''}',
          style: style,
          textAlign: align,
        );
      case 'supplier_name':
        return pw.Text(
          '${eLbl ?? 'المورد'}: ${customerName ?? ''}',
          style: style,
          textAlign: align,
        );
      // Visual Elements
      case 'divider':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Divider(thickness: 0.5),
        );
      case 'spacer':
        return pw.SizedBox(height: 8);
      case 'qr_code':
        // لا اعتمادَ من البوّابة بعد على جهازٍ مُفعَّل ⇒ لا رمزَ إطلاقاً.
        // ورمزٌ ببيانات البيعة هنا كان سيخرج بلا بياناتٍ ضريبيّةٍ من ماكينةِ
        // منشأةٍ مسجَّلةٍ ضريبيّاً.
        if (receiptQr != null && receiptQr.kind == ReceiptQrKind.none) {
          return pw.SizedBox.shrink();
        }
        return pw.Center(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: receiptQr?.payload ?? invoiceNumber,
                width: 50,
                height: 50,
                drawText: false,
                textStyle: pw.TextStyle(font: _arabicFont, fontSize: 6),
              ),
              // وسمُ الرمز غير الضريبيّ على الورقة نفسِها — من يقرأ الإيصالَ
              // لا يرى قرارَ الكود.
              if (receiptQr != null &&
                  receiptQr.kind == ReceiptQrKind.nonFiscal &&
                  receiptQr.disclaimer.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    receiptQr.disclaimer,
                    style: style.copyWith(fontSize: 6),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
            ],
          ),
        );
      case 'barcode':
        return pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoiceNumber,
            width: 60,
            height: 25,
            textStyle: pw.TextStyle(font: _arabicFont, fontSize: 6),
          ),
        );

      // Custom text / notes / footer
      case 'text':
      case 'custom_text':
        return eCnt != null
            ? pw.Text(eCnt, style: style, textAlign: align)
            : pw.SizedBox();
      case 'notes':
        final noteText = notes ?? eCnt;
        return noteText != null && noteText.isNotEmpty
            ? pw.Text(noteText, style: style, textAlign: align)
            : pw.SizedBox();

      // إضافاتُ الأصناف وخياراتُها — مجموعةً على مستوى الفاتورة، وهو ما
      // تعاينه شاشةُ المصمّم («الإضافات: كاتشب، مايونيز»). كانا يسقطان على
      // `default` فيرجعان `SizedBox()` أي يختفيان بلا أثر.
      case 'item_additions':
        final additions = _TemplatedInvoiceValues.extractItemAdditions(items);
        if (additions.isEmpty) return pw.SizedBox();
        final addLabel = eLbl?.trim();
        return pw.Text(
          addLabel == null || addLabel.isEmpty
              ? 'الإضافات: $additions'
              : '$addLabel: $additions',
          style: style,
          textAlign: align,
        );
      case 'item_options':
        final options = _TemplatedInvoiceValues.extractItemOptions(items);
        if (options.isEmpty) return pw.SizedBox();
        final optLabel = eLbl?.trim();
        return pw.Text(
          optLabel == null || optLabel.isEmpty
              ? 'الخيارات: $options'
              : '$optLabel: $options',
          style: style,
          textAlign: align,
        );
      case 'footer':
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            eCnt ?? 'شكراً لتعاملكم معنا',
            style: style, textAlign: align,
          ),
        );

      // ══════════════════════════════════════════════════════════════════
      // SMART DEFAULT — mirrors the preview dialog's fallback behavior.
      // Any element type not explicitly cased above is rendered using
      // its label (from labelAr or _getLabel) + real data value.
      // Totals-like fields render as label ↔ value rows (right-aligned).
      // ══════════════════════════════════════════════════════════════════
      default:
        // نصٌّ ثابتٌ يُرسم كما هو.
        //
        // ⚠️ `_resolveType` يستبدل نوعَ عنصر النصّ **بمحتواه** كي يصلح
        // مفتاحاً للترتيب وإزالة التكرار. فحالةُ `case 'text'` أعلاه لا
        // تُبلَغ أبداً لأيّ نصٍّ له محتوى — يسقط هنا، ولا قيمةَ بيانٍ له،
        // فيختفي بلا أثر. رُصد على ورقٍ حقيقيّ 2026-08-12: عناوينُ قنوات
        // تقرير الوردية **وسطرا التوقيع** غائبةٌ عن كلّ مطبوعٍ بقالب.
        //
        // الشرطُ يفحص النوعَ الخام لا المُحلَّل، ويأتي **داخل** `default`
        // لا قبل الـswitch: عنصرُ نصٍّ محتواه مفتاحُ بياناتٍ معروفٌ يبقى
        // على سلوكه القديم فيُحَلّ قيمةً.
        if ((element.elementType == 'text' ||
                element.elementType == 'custom_text') &&
            (eCnt?.isNotEmpty ?? false)) {
          return pw.Text(eCnt!, style: style, textAlign: align);
        }

        final label = eLbl ?? _TemplatedInvoiceValues._getLabel(resolvedType);
        final value = _TemplatedInvoiceValues._getDataValue(
          resolvedType,
          invoiceNumber: invoiceNumber,
          date: date,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          companyName: companyName,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          companyTaxId: companyTaxId,
          paymentMethod: paymentMethod,
          cashierName: cashierName,
          notes: notes,
          adhocCustomerName: adhocCustomerName,
          adhocCustomerPhone: adhocCustomerPhone,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          deliveryFee: deliveryFee,
          total: total,
          paid: paid,
          remaining: remaining,
          orderNumber: orderNumber,
          platformOrderNumber: platformOrderNumber,
          cashAmount: cashAmount,
          bankAmount: bankAmount,
        );

        // §٥-٣ (بلاغٌ ميدانيّ 2026-08-11): كان الشرطُ `&&`، فتسميةٌ **معروفةٌ**
        // بقيمةٍ فارغةٍ تُطبع معلَّقةً بلا رقم: «الكاشير:» و«المخزن:» في
        // الإيصال المرصود. والحقولُ التي ترجع `''` مقصودةٌ ومعلومة — انظر
        // `_getDataValue`: «Fields where data is not yet passed through to the
        // print service» (‏`warehouse_name` · `branch_name` · `cash_amount` ·
        // `bank_amount` · `click_amount` …).
        //
        // فالقاعدة: **عنصرٌ بلا قيمةٍ لا يقول شيئاً فلا يُطبع.** تسميةٌ وحدَها
        // أسوأُ من لا شيء: القارئُ يظنّ البيانَ ناقصاً لا الحقلَ غيرَ مفعَّل.
        if (value.isEmpty) {
          if (label.isEmpty) {
            debugPrint('[TemplatedInvoice] ⚠ Unknown: "$resolvedType"');
          }
          return pw.SizedBox();
        }

        // Totals-like fields → right-aligned label ↔ value row
        if (_TemplatedInvoiceValues._isTotalField(resolvedType)) {
          final num? numVal = double.tryParse(value);
          if (numVal != null) {
            final isMainTotal = resolvedType == 'total' || resolvedType == 'total_amount';
            return _TemplatedItemsTable._totalRow(
              label,
              numVal.toDouble(),
              isMainTotal ? style.copyWith(fontWeight: pw.FontWeight.bold) : style,
              align,
            );
          }
        }

        // Regular field → label: value
        if (label.isNotEmpty && value.isNotEmpty) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text('$label: $value', style: style, textAlign: align),
          );
        }

        // Label-only or value-only
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Text(
            label.isNotEmpty ? label : value,
            style: style, textAlign: align,
          ),
        );
    }
  }
}

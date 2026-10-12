// TemplatedInvoiceService - shift-closing values, element type resolution and data values.
part of '../templated_invoice_service.dart';

/// Shift-closing values, element-type resolution and data values of [TemplatedInvoiceService].
abstract final class _TemplatedInvoiceValues {
  // ── إضافاتُ الصنف وخياراتُه ─────────────────────────────────────────────
  //
  // السلّةُ تركّب الاختياراتِ في نصٍّ واحدٍ (`composeCartItemNote`) يُخزَّن في
  // `sales_invoice_items.note` ويصل هنا في `item['note']`:
  //
  //   الخيار  ⇒ `(اسمُ المجموعة: [مستوى] الاسم)`
  //   الإضافة ⇒ `+الاسم [سعر عملة]`
  //   ملاحظةُ الكاشير ⇒ `📝 نصّ`
  //   والفصلُ بـ` | `
  //
  // فالاستخراجُ من هذا الشكل حتميّ. والملاحظةُ اليدوية لا تُخلط بهما:
  // «بدون بصل» ليست إضافةً ولا خياراً، وخلطُها يجعل المطبخَ يقرأ طلباً لم
  // يُطلب.

  /// أجزاءُ ملاحظةِ بندٍ واحد، مقسَّمةً على الفاصل.
  static Iterable<String> _noteParts(List<Map<String, dynamic>> items) sync* {
    for (final item in items) {
      final raw = (item['note'] as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      for (final p in raw.split('|')) {
        final t = p.trim();
        if (t.isNotEmpty) yield t;
      }
    }
  }

  /// يحافظ على ترتيب أوّل ظهورٍ ويُسقط التكرار — الطباعةُ للقارئ لا للآلة.
  static String _joinUnique(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      if (v.isEmpty || !seen.add(v)) continue;
      out.add(v);
    }
    return out.join('، ');
  }

  /// `+الاسم [سعر]` ⇒ «الاسم». السعرُ يُسقط: العنصرُ ملخّصٌ لا فاتورة.
  static final _additionPrice = RegExp(r'\s+[\d.,]+\s*\S*$');

  static String extractItemAdditions(List<Map<String, dynamic>> items) {
    return _joinUnique(_noteParts(items)
        .where((p) => p.startsWith('+'))
        .map((p) => p.substring(1).replaceAll(_additionPrice, '').trim()));
  }

  static String extractItemOptions(List<Map<String, dynamic>> items) {
    return _joinUnique(_noteParts(items)
        .where((p) => p.startsWith('(') && p.endsWith(')'))
        .map((p) {
      final inner = p.substring(1, p.length - 1);
      final colon = inner.indexOf(':');
      return (colon >= 0 ? inner.substring(colon + 1) : inner).trim();
    }));
  }

  static String? resolveShiftValue(String type, ShiftClosingSnapshot s) {
    String n(double v) => v.toStringAsFixed(_docDecimals);

    switch (type) {
      case 'shift_invoice_count':
        return s.invoiceCount.toString();
      case 'shift_total_sales':
        return n(s.totalSales);
      case 'shift_system_cash':
        return n(s.systemCash);
      case 'shift_actual_cash':
        return n(s.actualCash);
      case 'shift_cash_variance':
        return n(s.cashVariance);
      case 'shift_system_card':
        return n(s.systemCard);
      case 'shift_actual_card':
        return n(s.actualCard);
      case 'shift_card_variance':
        return n(s.cardVariance);

      // §٥-٢ (بلاغٌ ميدانيّ 2026-08-11): «كليك» قناةُ دفعٍ كاملةٌ في اللقطة
      // وتدخل في `shift_total_system` و`shift_total_actual` تحت — وكانت
      // غائبةً عن **كلّ** طبقات القالب: لا حالةَ هنا، ولا عنصرَ في لوحة
      // المصمّم، ولا صفَّ في القالب المبذور. فالمطبوعُ يعرض النقدَ والبطاقةَ
      // ويطبع إجمالياً يشملها: المرصود `240,000 + 120,000` بإجمالي
      // `560,000`. والقارئُ يجمع ما يراه فلا يطابق، فيظنّ العطبَ في الحساب.
      case 'shift_system_click':
        return n(s.systemClick);
      case 'shift_actual_click':
        return n(s.actualClick);
      case 'shift_click_variance':
        return n(s.clickVariance);

      case 'shift_total_variance':
        return n(s.totalVariance);
      case 'shift_total_expenses':
        return n(s.totalExpenses);
      case 'shift_cash_refunds':
        return n(s.cashRefunds);

      // ── بنودُ «الحركة» الباقيةُ من الشاشة (بلاغ المالك 2026-08-12) ──
      // شاشةُ `picpos_past_shifts_panel` تقرأ اللقطةَ مباشرةً فتعرض ستّةَ
      // بنود؛ ثلاثةٌ منها لم يكن لها مفتاحٌ هنا فسقطت من الورقة وحدَها.
      // والمشغّلُ يقارن الاثنين — بندٌ على الشاشة وغائبٌ عن المطبوع يُقرأ
      // نقصاً في المطبوع لا نقصاً في القالب.
      case 'shift_opening_balance':
        return n(s.openingBalance);
      case 'shift_cash_income':
        return n(s.cashIncome);

      // ⚠️ الآجلُ **للتوضيح لا للتسوية**: مبيعاتٌ لم تُقبَض، فلا خزنةَ
      // تحمله. ضمُّه إلى `shift_total_system` كان يخلق عجزاً وهمياً بقيمته
      // في كلّ ورديةٍ فيها بيعٌ آجل. يُعرض ويبقى خارج المجاميع.
      case 'shift_credit_sales':
        return n(s.creditSales);
      case 'shift_credit_count':
        return s.creditSalesCount.toString();

      // مجاميعُ مشتقّة — لا حقلَ لها في اللقطة. تُجمع من الثلاثة (نقد ·
      // بطاقة · كليك) لا من `totalSales`: الأخيرُ مبيعاتٌ والأولُ متحصَّل،
      // ويفترقان بالآجل والمصروفات.
      case 'shift_total_system':
        return n(s.systemCash + s.systemCard + s.systemClick);
      case 'shift_total_actual':
        return n(s.actualCash + s.actualCard + s.actualClick);

      case 'shift_status':
        // أهمُّ سطرٍ في التقرير — الفرقُ ينطق بكلمته لا برقمه وحدَه.
        if (s.totalVariance.abs() < 0.001) return 'مطابق';
        return s.totalVariance < 0
            ? 'عجز: ${n(s.totalVariance)}'
            : 'زيادة: +${n(s.totalVariance)}';

      case 'shift_number':
        // لا رقمَ ورديةٍ في اللقطة — الموظّفُ والوقتُ هما ما يميّزها للقارئ.
        final who = s.employeeName?.trim();
        final when = s.closedAt;
        if (who != null && who.isNotEmpty && when != null) {
          return '$who — ${when.day}/${when.month}/${when.year}';
        }
        return who?.isNotEmpty == true ? who! : '—';

      case 'shift_closing':
        return 'تقرير إغلاق الوردية';

      default:
        return null;
    }
  }

  /// تفويضٌ — انظر `_getDataValue`.
  static String _getLabel(String type) => pv.contentLabel(type);

  /// تفويضٌ — انظر `_getDataValue`.
  static bool _isTotalField(String type) => pv.isTotalField(type);

  /// Resolve element type from DB element — handles variable, text, image, line
  static String _resolveType(InvoiceTemplateElement element) {
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
    const nameMapping = {
      'customer_name': 'customer',
      'tax_amount': 'tax',
      'grand_total': 'total',
      'total_amount': 'total',
      'paid_amount': 'paid',
      'change': 'remaining',
      'company_tax_number': 'company_tax_id',
      'footer_text': 'footer',
    };
    return nameMapping[resolvedType] ?? resolvedType;
  }

  /// Map sale type codes to human-readable Arabic labels (with platform hashtags)
  static String _mapSaleTypeLabel(String saleType) {
    switch (saleType.toLowerCase()) {
      case 'delivery':
        return 'توصيل';
      case 'internal':
      case 'default':
        return 'محلي';
      case 'dine_in':
      case 'صالة':
        return 'صالة';
      case 'takeaway':
      case 'سفري':
        return 'سفري';
      case 'talabat':
      case 'طلبات':
        return '#طلبات';
      case 'careem':
      case 'كريم':
        return '#كريم';
      case 'marsool':
      case 'مرسول':
        return '#مرسول';
      case 'jahez':
      case 'جاهز':
        return '#جاهز';
      case 'hungerstation':
        return '#هنقرستيشن';
      case 'toyo':
      case 'toyou':
        return '#ToYou';
      default:
        return saleType;
    }
  }

  /// Get the actual data value for an element type from the print parameters
  /// تفويضٌ إلى الحساب الخالص في `domain/printing/print_values.dart`.
  ///
  /// كان المبدّلُ كلُّه هنا. ونَقلُه لم يكن ترتيباً: المسارُ الجديد
  /// (`layout_version == 2`) يحتاج **نصّاً** لا ودجت، فلو نُسخ الحسابُ
  /// هناك لافترق المطبوعان عند أوّل إصلاح. فصار مصدراً واحداً يقرؤه
  /// المساران.
  static String _getDataValue(
    String type, {
    required String invoiceNumber,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    String? companyTaxId,
    required String paymentMethod,
    String? cashierName,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    required double remaining,
    String? orderNumber,
    String? platformOrderNumber,
    double? cashAmount,
    double? bankAmount,
  }) =>
      pv.resolveContentValue(
        type,
        pv.PrintPayload(
          invoiceNumber: invoiceNumber,
          date: date,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          adhocCustomerName: adhocCustomerName,
          adhocCustomerPhone: adhocCustomerPhone,
          companyName: companyName,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          companyTaxId: companyTaxId,
          paymentMethod: paymentMethod,
          cashierName: cashierName,
          notes: notes,
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
          decimals: _docDecimals,
        ),
      );
}

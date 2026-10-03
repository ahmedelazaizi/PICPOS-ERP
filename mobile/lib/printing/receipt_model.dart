/// Receipt layout model (pure Dart): what is printed, in order, independent
/// of how it is rasterized. Builders for the sales invoice, the sales return
/// and the collection receipt follow the desktop thermal layouts
/// (`ThermalReceiptGenerator`, `ThermalVoucherGenerator`) and its identity /
/// QR rules, now shared in `picpos_rules`. ARCHITECTURE-I §10.
library;

import 'package:picpos_rules/picpos_rules.dart';

/// Thermal paper: printable width in dots at 203 dpi and characters per line
/// of the printer's font A (for reference; text is rasterized).
enum PaperWidth {
  mm58(384, 32),
  mm80(576, 48);

  const PaperWidth(this.dots, this.chars);
  final int dots;
  final int chars;

  static PaperWidth byName(String? n) => n == 'mm58' ? mm58 : mm80;
}

enum ReceiptAlign { start, center, end }

enum ReceiptTextSize { small, normal, large }

sealed class ReceiptBlock {
  const ReceiptBlock();
}

class ReceiptText extends ReceiptBlock {
  const ReceiptText(this.text,
      {this.align = ReceiptAlign.center, this.size = ReceiptTextSize.normal, this.bold = false});
  final String text;
  final ReceiptAlign align;
  final ReceiptTextSize size;
  final bool bold;
  @override
  String toString() => 'Text($text)';
}

/// Label at the reading start, value at the other end.
class ReceiptRow extends ReceiptBlock {
  const ReceiptRow(this.label, this.value, {this.bold = false, this.large = false});
  final String label;
  final String value;
  final bool bold;
  final bool large;
  @override
  String toString() => 'Row($label: $value)';
}

/// One invoice line: name, then `qty × price` and the line total.
class ReceiptItem extends ReceiptBlock {
  const ReceiptItem(this.name, this.detail, this.total);
  final String name;
  final String detail;
  final String total;
  @override
  String toString() => 'Item($name | $detail | $total)';
}

class ReceiptDivider extends ReceiptBlock {
  const ReceiptDivider({this.thick = false});
  final bool thick;
}

class ReceiptQrCode extends ReceiptBlock {
  const ReceiptQrCode(this.payload, {this.caption = ''});
  final String payload;
  final String caption;
}

/// CODE128 of [data] with the human-readable value under it.
class ReceiptBarcode extends ReceiptBlock {
  const ReceiptBarcode(this.data);
  final String data;
}

class ReceiptFeed extends ReceiptBlock {
  const ReceiptFeed([this.lines = 1]);
  final int lines;
}

class Receipt {
  Receipt({required this.kind, required this.number, required this.blocks, this.locale = 'ar'});

  /// `sales_invoice` | `sales_return` | `collection` | `test`.
  final String kind;
  final String number;
  final List<ReceiptBlock> blocks;
  final String locale;
  bool get rtl => locale != 'en';

  Iterable<String> get texts sync* {
    for (final b in blocks) {
      switch (b) {
        case ReceiptText(:final text):
          yield text;
        case ReceiptRow(:final label, :final value):
          yield '$label: $value';
        case ReceiptItem(:final name, :final detail, :final total):
          yield '$name | $detail | $total';
        case ReceiptQrCode(:final caption):
          if (caption.isNotEmpty) yield caption;
        case ReceiptBarcode(:final data):
          yield data;
        case ReceiptDivider() || ReceiptFeed():
          break;
      }
    }
  }

  ReceiptQrCode? get qr => blocks.whereType<ReceiptQrCode>().firstOrNull;
  ReceiptBarcode? get barcode => blocks.whereType<ReceiptBarcode>().firstOrNull;
  String? valueOf(String label) =>
      blocks.whereType<ReceiptRow>().where((r) => r.label == label).map((r) => r.value).firstOrNull;
}

/// Printed company identity (cloud `company` profile, filled by the desktop).
class ReceiptCompany {
  const ReceiptCompany({
    required this.nameAr,
    this.nameEn,
    this.taxNumber,
    this.commercialRegister,
    this.address,
    this.phone,
    this.currency = '',
    this.eInvoiceEnabled = false,
    this.decimals = 2,
  });

  factory ReceiptCompany.fromProfile(Map<String, Object?> m) => ReceiptCompany(
        nameAr: '${m['name'] ?? ''}',
        nameEn: m['nameEn'] as String?,
        taxNumber: m['taxNumber'] as String?,
        commercialRegister: m['commercialRegister'] as String?,
        address: m['address'] as String?,
        phone: m['phone'] as String?,
        currency: '${m['currency'] ?? ''}',
        eInvoiceEnabled: m['eInvoiceEnabled'] == true,
        decimals: (m['decimalPlaces'] as int?) ?? 2,
      );

  final String nameAr;
  final String? nameEn;
  final String? taxNumber;
  final String? commercialRegister;
  final String? address;
  final String? phone;
  final String currency;
  final bool eInvoiceEnabled;
  final int decimals;
}

class ReceiptLineData {
  const ReceiptLineData({required this.name, required this.quantity, required this.unitPrice, required this.total});
  final String name;
  final double quantity;
  final double unitPrice;
  final double total;
}

/// Shared header fields of a field document.
class ReceiptParty {
  const ReceiptParty({required this.customerName, required this.repName, this.routeName});
  final String customerName;
  final String repName;
  final String? routeName;
}

/// Receipt labels (AR default / EN).
class ReceiptLabels {
  const ReceiptLabels(this.locale);
  final String locale;
  bool get ar => locale != 'en';
  String _t(String a, String e) => ar ? a : e;

  String get invoiceTitle => _t('فاتورة مبيعات', 'Sales Invoice');
  String get returnTitle => _t('إشعار مرتجع مبيعات', 'Sales Return Credit Note');
  String get collectionTitle => _t('سند قبض', 'Receipt Voucher');
  String get number => _t('رقم', 'No.');
  String get returnNumber => _t('رقم المرتجع', 'Return No.');
  String get originalInvoice => _t('الفاتورة الأصلية', 'Original invoice');
  String get voucherNumber => _t('رقم السند', 'Voucher No.');
  String get date => _t('التاريخ', 'Date');
  String get rep => _t('المندوب', 'Rep');
  String get route => _t('خط السير', 'Route');
  String get customer => _t('العميل', 'Customer');
  String get receivedFrom => _t('استلمنا من', 'Received from');
  String get subtotal => _t('المجموع الفرعي', 'Subtotal');
  String get tax => _t('الضريبة', 'Tax');
  String get total => _t('الإجمالي', 'TOTAL');
  String get paid => _t('المدفوع', 'Paid');
  String get remaining => _t('المتبقي', 'Remaining');
  String get newBalance => _t('الرصيد الجديد', 'New balance');
  String get returnTotal => _t('إجمالي المرتجع', 'Refund total');
  String get arOffset => _t('خصم من الرصيد', 'Offset against balance');
  String get cashRefund => _t('استرداد نقدي', 'Cash refund');
  String get reason => _t('السبب', 'Reason');
  String returnReason(String code) => switch (code) {
        'damaged' => _t('تالف', 'Damaged'),
        'expired' => _t('منتهي الصلاحية', 'Expired'),
        'wrong_item' => _t('صنف خاطئ', 'Wrong item'),
        'customer_request' => _t('طلب العميل', 'Customer request'),
        'other' => _t('أخرى', 'Other'),
        _ => code,
      };
  String get amount => _t('المبلغ', 'Amount');
  String get paymentMethod => _t('طريقة الدفع', 'Payment');
  String method(String m) => switch (m) {
        'cash' => _t('نقدي', 'Cash'),
        'credit' => _t('آجل', 'Credit'),
        _ => _t('نقدي + آجل', 'Mixed'),
      };
  String get verification => _t('رمز التحقق', 'Verification');
  String get notSynced => _t('لم تُرسل للخادم بعد', 'Not yet sent to the server');
  String get thanks => _t('~ شكراً لزيارتكم ~', '~ Thank you ~');
  String get receiver => _t('المستلم', 'Receiver');
  String get deliverer => _t('المسلم', 'Deliverer');
  String get reprint => _t('نسخة مكررة', 'REPRINT');
  // K-1: rep expense (payment) voucher.
  String get expenseTitle => _t('سند صرف', 'Payment Voucher');
  String get expenseCategory => _t('بند المصروف', 'Expense');
  String get note => _t('البيان', 'Note');
  String get paidFromCustody => _t('صُرف من عهدة', 'Paid from custody of');
  String get custodyAfter => _t('رصيد العهدة بعد الصرف', 'Custody after');
  String get overCustody => _t('تجاوز العهدة', 'Custody exceeded');
}

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

class ReceiptBuilder {
  ReceiptBuilder(this.company, {this.locale = 'ar'}) : l = ReceiptLabels(locale);
  final ReceiptCompany company;
  final String locale;
  final ReceiptLabels l;

  String money(double v) => v.toStringAsFixed(company.decimals);

  /// Identity header (desktop `_buildHeader`): main name large/bold, then
  /// secondary name, address, phone, tax · CR — all via `picpos_rules`.
  List<ReceiptBlock> header() {
    final lines = companyHeaderLines(
      nameAr: company.nameAr,
      nameEn: company.nameEn,
      address: company.address,
      phone: company.phone,
      taxId: company.taxNumber,
      crNumber: company.commercialRegister,
      locale: locale,
    );
    return [
      for (var i = 0; i < lines.length; i++)
        ReceiptText(lines[i],
            size: i == 0 ? ReceiptTextSize.large : ReceiptTextSize.small, bold: i == 0),
      const ReceiptDivider(thick: true),
    ];
  }

  List<ReceiptBlock> _partyRows(ReceiptParty p, {bool customerFirst = true}) => [
        if (customerFirst) ReceiptRow(l.customer, p.customerName),
        ReceiptRow(l.rep, p.repName),
        if ((p.routeName ?? '').isNotEmpty) ReceiptRow(l.route, p.routeName!),
      ];

  List<ReceiptBlock> _footer({String? integrityHash, bool reprint = false}) => [
        const ReceiptDivider(),
        ReceiptText(
          integrityHash == null || integrityHash.isEmpty
              ? l.notSynced
              : '${l.verification}: ${ltrIsolate(integrityShortHash(integrityHash))}',
          size: ReceiptTextSize.small,
        ),
        if (reprint) ReceiptText(l.reprint, size: ReceiptTextSize.small, bold: true),
      ];

  Receipt salesInvoice({
    required String globalId,
    required String number,
    required DateTime date,
    required ReceiptParty party,
    required List<ReceiptLineData> lines,
    required double net,
    required double tax,
    required double total,
    required double paid,
    double? newBalance,
    String? integrityHash,
    bool reprint = false,
    String? gatewayQrCode,
    String? submissionStatus,
  }) {
    final remaining = roundDp(total - paid, company.decimals);
    final qr = resolveReceiptQr(
      eInvoiceEnabled: company.eInvoiceEnabled,
      submissionStatus: submissionStatus,
      gatewayQrCode: gatewayQrCode,
      invoiceNumber: number,
      issuedAt: date,
      total: total,
      companyName: companyMainName(nameAr: company.nameAr, nameEn: company.nameEn, locale: locale),
      reference: globalId,
    );
    return Receipt(kind: 'sales_invoice', number: number, locale: locale, blocks: [
      ...header(),
      ReceiptText(l.invoiceTitle, bold: true),
      ReceiptRow(l.number, ltrIsolate(number)),
      ReceiptRow(l.date, ltrIsolate(_fmtDate(date))),
      ..._partyRows(party),
      const ReceiptDivider(),
      for (final x in lines)
        ReceiptItem(x.name, '${_qty(x.quantity)} × ${money(x.unitPrice)}', money(x.total)),
      const ReceiptDivider(),
      ReceiptRow(l.subtotal, money(net)),
      ReceiptRow(l.tax, money(tax)),
      ReceiptRow(l.total, money(total), bold: true, large: true),
      ReceiptRow(l.paid, money(paid)),
      if (remaining > 0.005) ReceiptRow(l.remaining, money(remaining), bold: true),
      ReceiptRow(l.paymentMethod, l.method(salesPaymentMethod(paid: paid, remaining: remaining))),
      if (newBalance != null) ReceiptRow(l.newBalance, money(newBalance)),
      const ReceiptDivider(),
      ReceiptBarcode(number),
      if (qr.kind != ReceiptQrKind.none) ReceiptQrCode(qr.payload, caption: qr.disclaimer),
      ..._footer(integrityHash: integrityHash, reprint: reprint),
      ReceiptText(l.thanks, bold: true),
      const ReceiptFeed(3),
    ]);
  }

  Receipt salesReturn({
    required String number,
    required DateTime date,
    required ReceiptParty party,
    String? originalNumber,
    required List<ReceiptLineData> lines,
    required double total,
    required double tax,
    required double arOffset,
    required double cashRefund,
    double? newBalance,
    String? reason,
    String? integrityHash,
    bool reprint = false,
  }) =>
      Receipt(kind: 'sales_return', number: number, locale: locale, blocks: [
        ...header(),
        ReceiptText(l.returnTitle, bold: true),
        ReceiptRow(l.returnNumber, ltrIsolate(number)),
        if ((originalNumber ?? '').isNotEmpty) ReceiptRow(l.originalInvoice, ltrIsolate(originalNumber!)),
        ReceiptRow(l.date, ltrIsolate(_fmtDate(date))),
        ..._partyRows(party),
        const ReceiptDivider(),
        for (final x in lines) ReceiptItem(x.name, '${_qty(x.quantity)} × ${money(x.unitPrice)}', money(x.total)),
        const ReceiptDivider(),
        ReceiptRow(l.tax, money(tax)),
        ReceiptRow(l.returnTotal, money(total), bold: true, large: true),
        ReceiptRow(l.arOffset, money(arOffset)),
        ReceiptRow(l.cashRefund, money(cashRefund)),
        if (newBalance != null) ReceiptRow(l.newBalance, money(newBalance)),
        if ((reason ?? '').isNotEmpty) ReceiptRow(l.reason, l.returnReason(reason!)),
        const ReceiptDivider(),
        ReceiptBarcode(number),
        ..._footer(integrityHash: integrityHash, reprint: reprint),
        ReceiptRow(l.receiver, '..........'),
        ReceiptRow(l.deliverer, '..........'),
        const ReceiptFeed(3),
      ]);

  Receipt collection({
    required String number,
    required DateTime date,
    required ReceiptParty party,
    required double amount,
    double? newBalance,
    bool reprint = false,
  }) =>
      Receipt(kind: 'collection', number: number, locale: locale, blocks: [
        ...header(),
        ReceiptText(l.collectionTitle, bold: true, size: ReceiptTextSize.large),
        ReceiptRow(l.voucherNumber, ltrIsolate(number)),
        ReceiptRow(l.date, ltrIsolate(_fmtDate(date))),
        ReceiptRow(l.receivedFrom, party.customerName),
        ..._partyRows(party, customerFirst: false),
        const ReceiptDivider(),
        ReceiptRow(l.amount, '${money(amount)} ${company.currency}'.trim(), bold: true, large: true),
        if (newBalance != null) ReceiptRow(l.newBalance, money(newBalance)),
        const ReceiptDivider(),
        ReceiptBarcode(number),
        if (reprint) ReceiptText(l.reprint, size: ReceiptTextSize.small, bold: true),
        ReceiptRow(l.receiver, '..........'),
        ReceiptRow(l.deliverer, '..........'),
        const ReceiptFeed(3),
      ]);

  /// K-1: rep expense paid from his custody (desktop thermal payment voucher
  /// layout: title, number, date, payee/category, amount, signatures).
  Receipt expense({
    required String number,
    required DateTime date,
    required String repName,
    String? routeName,
    required String category,
    required double amount,
    String? note,
    double? custodyAfter,
    bool overCustody = false,
    bool reprint = false,
  }) =>
      Receipt(kind: 'expense', number: number, locale: locale, blocks: [
        ...header(),
        ReceiptText(l.expenseTitle, bold: true, size: ReceiptTextSize.large),
        ReceiptRow(l.voucherNumber, ltrIsolate(number)),
        ReceiptRow(l.date, ltrIsolate(_fmtDate(date))),
        ReceiptRow(l.paidFromCustody, repName),
        if ((routeName ?? '').isNotEmpty) ReceiptRow(l.route, routeName!),
        const ReceiptDivider(),
        ReceiptRow(l.expenseCategory, category),
        if ((note ?? '').isNotEmpty) ReceiptRow(l.note, note!),
        ReceiptRow(l.amount, '${money(amount)} ${company.currency}'.trim(), bold: true, large: true),
        if (custodyAfter != null) ReceiptRow(l.custodyAfter, money(custodyAfter)),
        if (overCustody) ReceiptText(l.overCustody, bold: true),
        const ReceiptDivider(),
        ReceiptBarcode(number),
        if (reprint) ReceiptText(l.reprint, size: ReceiptTextSize.small, bold: true),
        ReceiptRow(l.receiver, '..........'),
        ReceiptRow(l.deliverer, '..........'),
        const ReceiptFeed(3),
      ]);

  /// Printer check from the settings screen.
  Receipt test(PaperWidth width) => Receipt(kind: 'test', number: 'TEST', locale: locale, blocks: [
        ...header(),
        ReceiptText(l.ar ? 'طباعة تجريبية' : 'Test print', bold: true),
        ReceiptText(l.ar ? 'عرض الورق ${width == PaperWidth.mm58 ? 58 : 80} مم' : 'Paper ${width == PaperWidth.mm58 ? 58 : 80} mm'),
        const ReceiptText('أبجد هوز حطي كلمن ١٢٣٤٥٦٧٨٩٠ 1234567890'),
        const ReceiptBarcode('TEST-123'),
        const ReceiptQrCode('PicPos Van'),
        const ReceiptFeed(3),
      ]);
}

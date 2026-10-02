import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_rules/picpos_rules.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart' show CartLine;
import 'package:picpos_van/printing/receipt_composer.dart';
import 'package:picpos_van/printing/receipt_model.dart';

import 'support/fakes.dart';

const company = ReceiptCompany(
  nameAr: 'شركة الوادي',
  nameEn: 'Al Wadi Co.',
  taxNumber: '123456',
  commercialRegister: '9988',
  address: 'عمّان',
  phone: '0790000000',
  currency: 'JOD',
);

const party = ReceiptParty(customerName: 'بقالة الأمل', repName: 'مندوب ١', routeName: 'خط ١');

void main() {
  group('sales invoice layout', () {
    Receipt invoice({ReceiptCompany c = company, String locale = 'ar', String? hash}) =>
        ReceiptBuilder(c, locale: locale).salesInvoice(
          globalId: 'gid-1',
          number: 'VS-100000',
          date: DateTime(2026, 5, 1, 10, 30),
          party: party,
          lines: const [
            ReceiptLineData(name: 'مياه ٦ لتر', quantity: 2, unitPrice: 2.5, total: 5.8),
            ReceiptLineData(name: 'خبز', quantity: 3, unitPrice: 1, total: 3),
          ],
          net: 8,
          tax: 0.8,
          total: 8.8,
          paid: 5,
          newBalance: 93.8,
          integrityHash: hash,
        );

    test('identity header matches the desktop rules (name, EN name, address, phone, tax · CR)', () {
      final r = invoice();
      final header = r.blocks.takeWhile((b) => b is! ReceiptDivider).cast<ReceiptText>().toList();
      expect(header.map((t) => t.text), [
        'شركة الوادي',
        'Al Wadi Co.',
        'عمّان',
        '${kLrm}0790000000$kLrm',
        'الرقم الضريبي: ${kLrm}123456$kLrm  ·  س.ت: ${kLrm}9988$kLrm',
      ]);
      expect(header.first.bold, isTrue);
      expect(header.first.size, ReceiptTextSize.large);
    });

    test('lines, totals, payment, balance and codes', () {
      final r = invoice();
      expect(r.kind, 'sales_invoice');
      expect(r.blocks.whereType<ReceiptItem>().map((i) => i.toString()),
          ['Item(مياه ٦ لتر | 2 × 2.50 | 5.80)', 'Item(خبز | 3 × 1.00 | 3.00)']);
      expect(r.valueOf('المجموع الفرعي'), '8.00');
      expect(r.valueOf('الضريبة'), '0.80');
      expect(r.valueOf('الإجمالي'), '8.80');
      expect(r.valueOf('المدفوع'), '5.00');
      expect(r.valueOf('المتبقي'), '3.80');
      expect(r.valueOf('طريقة الدفع'), 'نقدي + آجل');
      expect(r.valueOf('الرصيد الجديد'), '93.80');
      expect(r.valueOf('العميل'), 'بقالة الأمل');
      expect(r.valueOf('المندوب'), 'مندوب ١');
      expect(r.valueOf('خط السير'), 'خط ١');
      expect(r.valueOf('رقم'), '${kLrm}VS-100000$kLrm');
      expect(r.barcode!.data, 'VS-100000');
    });

    test('QR: non-fiscal verification payload (invoice, date, total, company, reference) + disclaimer', () {
      final qr = invoice().qr!;
      expect(qr.payload,
          'فاتورة: VS-100000\nالتاريخ: 2026-05-01 10:30\nالإجمالي: 8.80\nالمنشأة: شركة الوادي\nالمرجع: gid-1');
      expect(qr.caption, kNonFiscalQrDisclaimer);
    });

    test('e-invoicing company: no non-fiscal QR before the gateway QR exists (desktop rule)', () {
      const ei = ReceiptCompany(nameAr: 'شركة', taxNumber: '1', eInvoiceEnabled: true);
      expect(invoice(c: ei).qr, isNull);
      expect(invoice(c: ei).barcode!.data, 'VS-100000');
    });

    test('verification line: pending until the cloud signs, then the short hash', () {
      expect(invoice().texts, contains('لم تُرسل للخادم بعد'));
      expect(invoice(hash: 'v2:f7bc83f430538424b132').texts, contains('رمز التحقق: ${kLrm}f7bc-83f4-3053$kLrm'));
    });

    test('English receipt: English name first, CR label, English labels', () {
      final r = invoice(locale: 'en');
      expect(r.rtl, isFalse);
      expect((r.blocks.first as ReceiptText).text, 'Al Wadi Co.');
      expect(r.texts, contains('Tax No.: ${kLrm}123456$kLrm  ·  CR: ${kLrm}9988$kLrm'));
      expect(r.valueOf('TOTAL'), '8.80');
    });

    test('fully paid → no remaining row, cash', () {
      final r = ReceiptBuilder(company).salesInvoice(
          globalId: 'g', number: 'VS-1', date: DateTime(2026), party: party, lines: const [], net: 1, tax: 0, total: 1, paid: 1);
      expect(r.valueOf('المتبقي'), isNull);
      expect(r.valueOf('طريقة الدفع'), 'نقدي');
    });
  });

  test('return and collection layouts', () {
    final b = ReceiptBuilder(company);
    final ret = b.salesReturn(
      number: 'VR-100000',
      date: DateTime(2026, 5, 1),
      party: party,
      originalNumber: 'VS-99',
      lines: const [ReceiptLineData(name: 'مياه', quantity: 1, unitPrice: 2.9, total: 2.9)],
      total: 2.9,
      tax: 0.4,
      arOffset: 2.9,
      cashRefund: 0,
      reason: 'damaged',
    );
    expect(ret.valueOf('الفاتورة الأصلية'), '${kLrm}VS-99$kLrm');
    expect(ret.valueOf('إجمالي المرتجع'), '2.90');
    expect(ret.valueOf('خصم من الرصيد'), '2.90');
    expect(ret.valueOf('السبب'), 'تالف');
    expect(ret.barcode!.data, 'VR-100000');
    expect(ret.qr, isNull);

    final col = b.collection(number: 'R-1003', date: DateTime(2026, 5, 1), party: party, amount: 10, newBalance: 80);
    expect(col.texts, contains('سند قبض'));
    expect(col.valueOf('استلمنا من'), 'بقالة الأمل');
    expect(col.valueOf('المبلغ'), '10.00 JOD');
    expect(col.valueOf('الرصيد الجديد'), '80.00');
    expect(col.barcode!.data, 'R-1003');
  });

  test('composer builds receipts from saved outbox documents (offline, last-synced data)', () async {
    final (c, _) = await readyController();
    await c.applyServerPayload({
      'company': {
        'name': 'شركة الوادي',
        'nameEn': 'Al Wadi Co.',
        'taxNumber': '123456',
        'commercialRegister': '9988',
        'decimalPlaces': 2,
        'defaultTaxRate': 16.0,
      },
      'routes': [
        {'globalId': 'r1', 'name': 'خط الشمال'},
      ],
    });
    final cust = (await c.store.get(Kinds.customers, 'c2'))!;
    await c.store.upsert(Kinds.customers, [
      {...cust, 'routeGlobalId': 'r1'},
    ]);
    final sale = await c.createSale(customerGlobalId: 'c2', lines: [
      CartLine(productGlobalId: 'p1', name: 'مياه ٦ لتر', unitPrice: 2.5, taxRate: 16, quantity: 2),
    ], paid: 5);
    final r = await ReceiptComposer(c).compose(sale);
    expect(r.number, 'VS-100000');
    expect(r.valueOf('العميل'), 'سوبرماركت النور');
    expect(r.valueOf('خط السير'), 'خط الشمال');
    expect(r.valueOf('الإجمالي'), '5.80');
    expect(r.valueOf('الضريبة'), '0.80');
    expect(r.valueOf('المتبقي'), '0.80');
    expect(r.valueOf('الرصيد الجديد'), '0.80');
    expect(r.blocks.whereType<ReceiptItem>().single.toString(), 'Item(مياه ٦ لتر | 2 × 2.50 | 5.80)');
    expect(r.texts, contains('الرقم الضريبي: ${kLrm}123456$kLrm  ·  س.ت: ${kLrm}9988$kLrm'));
    expect(r.qr!.payload, contains('المرجع: ${sale.globalId}'));
    // Device-local receipt fields never reach the server.
    expect((sale.payload['lines'] as List).single, containsPair('_name', 'مياه ٦ لتر'));

    final book = (await c.voucherBooks()).single;
    final col = await c.createCollection(customerGlobalId: 'c1', amount: 10, book: book, leaf: 1003);
    final cr = await ReceiptComposer(c).compose(col);
    expect(cr.number, 'R-1003');
    expect(cr.valueOf('الرصيد الجديد'), '80.00');

    final ret = await c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p2': 1}, reason: 'expired');
    final rr = await ReceiptComposer(c).compose(ret);
    expect(rr.valueOf('الفاتورة الأصلية'), '${kLrm}VS-99$kLrm');
    expect(rr.valueOf('إجمالي المرتجع'), '1.00');
    expect(rr.blocks.whereType<ReceiptItem>().single.toString(), 'Item(خبز | 1 × 1.00 | 1.00)');
  });

  test('paper widths: 58 mm = 384 dots, 80 mm = 576 dots', () {
    expect(PaperWidth.mm58.dots, 384);
    expect(PaperWidth.mm80.dots, 576);
    expect(PaperWidth.byName('mm58'), PaperWidth.mm58);
    expect(PaperWidth.byName(null), PaperWidth.mm80);
  });
}

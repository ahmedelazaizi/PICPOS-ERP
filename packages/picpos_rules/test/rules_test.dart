import 'dart:convert';

import 'package:picpos_rules/picpos_rules.dart';
import 'package:test/test.dart';

void main() {
  group('effectiveItemTaxRate (desktop lib/core/tax)', () {
    test('exempt is always 0', () {
      expect(effectiveItemTaxRate(rate: 16, exempt: true, companyDefault: 16), 0);
    });
    test('positive item rate wins', () {
      expect(effectiveItemTaxRate(rate: 8, exempt: false, companyDefault: 16), 8);
    });
    test('zero item rate falls back to company default', () {
      expect(effectiveItemTaxRate(rate: 0, exempt: false, companyDefault: 16), 16);
    });
  });

  group('rounding and totals', () {
    test('roundDp rounds half away from zero after float normalisation', () {
      expect(roundDp(0.125), 0.13);
      expect(roundDp(-0.125), -0.13);
      expect(roundDp(0.1 + 0.2), 0.3);
      expect(roundDp(1.23456, 3), 1.235);
      expect(round2(7.0 * 0.16), 1.12);
    });

    test('computeTotals: per-line tax on net, 2dp rounding', () {
      final t = computeTotals([
        LineInput(quantity: 3, unitPrice: 2.5, discount: 0.5, taxRate: 16),
        LineInput(quantity: 2, unitPrice: 1, discount: 0, taxRate: 0),
      ]);
      expect(t.subtotal, 9.5);
      expect(t.discount, 0.5);
      expect(t.tax, 1.12); // (7.5 - 0.5) * 16 %
      expect(t.total, 10.12);
    });
  });

  group('sale math', () {
    test('credit limit 0 means no limit; only remaining > 0.01 counts', () {
      expect(exceedsCreditLimit(balance: 1000, creditLimit: 0, remaining: 500), isFalse);
      expect(exceedsCreditLimit(balance: 90, creditLimit: 100, remaining: 0.01), isFalse);
      expect(exceedsCreditLimit(balance: 90, creditLimit: 100, remaining: 10), isFalse);
      expect(exceedsCreditLimit(balance: 90, creditLimit: 100, remaining: 10.5), isTrue);
    });
    test('payment method', () {
      expect(salesPaymentMethod(paid: 10, remaining: 0), 'cash');
      expect(salesPaymentMethod(paid: 10, remaining: 0.005), 'cash');
      expect(salesPaymentMethod(paid: 4, remaining: 6), 'mixed');
      expect(salesPaymentMethod(paid: 0, remaining: 10), 'credit');
    });
  });

  group('integrity', () {
    test('payload uses the desktop sales format; v2 HMAC-SHA256', () {
      final payload = salesIntegrityPayload(
        number: 'VS-100000',
        date: DateTime.utc(2026, 1, 2, 3, 4, 5),
        total: 10.12,
        subtotal: 9.5,
        discount: 0.5,
        tax: 1.12,
        paid: 10.12,
        customerId: null,
        userId: 7,
        paymentMethod: 'cash',
      );
      expect(payload, 'VS-100000|2026-01-02T03:04:05.000Z|10.1200|9.5000|0.5000|1.1200|10.1200|0|7|cash');
      final sig = signV2('secret', payload);
      expect(sig, startsWith('v2:'));
      expect(sig.length, 3 + 64);
      expect(sig, signV2('secret', payload));
      expect(sig, isNot(signV2('other', payload)));
      // Known HMAC-SHA256 vector (RFC 4231 style check of the primitive).
      expect(signV2('key', 'The quick brown fox jumps over the lazy dog'),
          'v2:f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
    });
    test('short hash groups the first 12 hex digits', () {
      expect(integrityShortHash('v2:f7bc83f430538424'), 'f7bc-83f4-3053');
      expect(integrityShortHash(null), '');
      expect(integrityShortHash('v2:abc'), 'abc');
    });
  });

  group('normalizeBarcode', () {
    test('strips wedge suffixes, control chars and AIM prefixes', () {
      expect(normalizeBarcode('6251234567890\n'), '6251234567890');
      expect(normalizeBarcode(' 6251234567890\r\n'), '6251234567890');
      expect(normalizeBarcode('6251234567890\t'), '6251234567890');
      expect(normalizeBarcode(']E06251234567890'), '6251234567890');
      expect(normalizeBarcode(']C1\x1d0106251234567890'), '0106251234567890');
      expect(normalizeBarcode('\n'), '');
      expect(normalizeBarcode('ABC-123'), 'ABC-123');
    });
  });

  group('company identity (desktop printing rules)', () {
    test('Arabic document: Arabic main, English secondary, tax · CR on one line', () {
      final lines = companyHeaderLines(
        nameAr: 'شركة الوادي',
        nameEn: 'Al Wadi Co.',
        address: 'عمّان',
        phone: '0790000000',
        taxId: '123456',
        crNumber: '9988',
      );
      expect(lines, [
        'شركة الوادي',
        'Al Wadi Co.',
        'عمّان',
        '${kLrm}0790000000$kLrm',
        'الرقم الضريبي: ${kLrm}123456$kLrm  ·  س.ت: ${kLrm}9988$kLrm',
      ]);
    });
    test('English document uses the English name and CR label', () {
      final lines = companyHeaderLines(nameAr: 'شركة الوادي', nameEn: 'Al Wadi Co.', crNumber: '9988', locale: 'en');
      expect(lines, ['Al Wadi Co.', 'CR: ${kLrm}9988$kLrm']);
    });
    test('empty values print nothing; identical English name is not repeated', () {
      expect(companyHeaderLines(nameAr: 'PicPos', nameEn: 'PicPos', taxId: ' ', crNumber: null), ['PicPos']);
      expect(companyCrLine(''), '');
      expect(companySecondaryName(nameAr: 'أ', nameEn: null), '');
    });
  });

  group('receipt QR (desktop decision)', () {
    final at = DateTime(2026, 3, 4, 5, 6);
    test('not e-invoicing → non-fiscal readable payload with reference and disclaimer', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: false,
        submissionStatus: null,
        gatewayQrCode: null,
        invoiceNumber: 'VS-100001',
        issuedAt: at,
        total: 12.5,
        companyName: 'شركة الوادي',
        reference: 'gid-1',
      );
      expect(qr.kind, ReceiptQrKind.nonFiscal);
      expect(qr.payload, 'فاتورة: VS-100001\nالتاريخ: 2026-03-04 05:06\nالإجمالي: 12.50\nالمنشأة: شركة الوادي\nالمرجع: gid-1');
      expect(qr.disclaimer, kNonFiscalQrDisclaimer);
    });
    test('e-invoicing: gateway QR only when valid, else none', () {
      ReceiptQr r(String? st, String? qr) => resolveReceiptQr(
          eInvoiceEnabled: true,
          submissionStatus: st,
          gatewayQrCode: qr,
          invoiceNumber: 'X',
          issuedAt: at,
          total: 1,
          companyName: 'c');
      expect(r('valid', 'AQID').kind, ReceiptQrKind.fiscal);
      expect(r('valid', 'AQID').payload, 'AQID');
      expect(r('pending', 'AQID').kind, ReceiptQrKind.none);
      expect(r('valid', '').kind, ReceiptQrKind.none);
    });
    test('JoFotara TLV: tag/length/value, base64', () {
      final b64 = jofotaraTlvQr(
          sellerName: 'AB', sellerTrn: '123', invoiceDate: '2026-01-01', totalAmount: 11.6, vatAmount: 1.6);
      final bytes = base64Decode(b64);
      expect(bytes.sublist(0, 4), [1, 2, 65, 66]);
      expect(bytes.sublist(4, 9), [2, 3, 49, 50, 51]);
      expect(utf8.decode(bytes.sublist(bytes.length - 4)), '1.60');
      // Arabic seller name is measured in UTF-8 bytes.
      final ar = base64Decode(jofotaraTlvQr(
          sellerName: 'أ', sellerTrn: '', invoiceDate: '', totalAmount: 0, vatAmount: 0));
      expect(ar.sublist(0, 4), [1, 2, 0xD8, 0xA3]);
    });
  });
}

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/invoice_integrity_service.dart';

void main() {
  const invoice = <String, Object>{
    'invoiceNumber': 'INV-1',
    'invoiceDate': '2026-01-01T00:00:00.000Z',
  };

  Future<String> sign() async {
    final values = <String, String>{};
    await InvoiceIntegrityService.initialize(
      readSetting: (key) async => values[key],
      writeSetting: (key, value) async => values[key] = value,
    );
    return InvoiceIntegrityService.computeSalesInvoiceHash(
      invoiceNumber: invoice['invoiceNumber']! as String,
      invoiceDate: DateTime.parse(invoice['invoiceDate']! as String),
      total: 10,
      subtotal: 9,
      discount: 0,
      tax: 1,
      paid: 10,
      customerId: 2,
      userId: 3,
      paymentMethod: 'cash',
    );
  }

  test('new invoice signatures use v2 and verify', () async {
    final signature = await sign();
    expect(signature, startsWith('v2:'));
    expect(
      InvoiceIntegrityService.verifySalesInvoiceHash(
        storedHash: signature,
        invoiceNumber: 'INV-1',
        invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
        total: 10,
        subtotal: 9,
        discount: 0,
        tax: 1,
        paid: 10,
        customerId: 2,
        userId: 3,
        paymentMethod: 'cash',
      ),
      isTrue,
    );
  });

  test('tampered v2 invoice data fails verification', () async {
    final signature = await sign();
    expect(
      InvoiceIntegrityService.verifySalesInvoiceHash(
        storedHash: signature,
        invoiceNumber: 'INV-1',
        invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
        total: 11,
        subtotal: 9,
        discount: 0,
        tax: 1,
        paid: 10,
        customerId: 2,
        userId: 3,
        paymentMethod: 'cash',
      ),
      isFalse,
    );
  });

  test('legacy invoice signatures remain verifiable', () {
    final payload = [
      'INV-1',
      '2026-01-01T00:00:00.000Z',
      '10.0000',
      '9.0000',
      '0.0000',
      '1.0000',
      '10.0000',
      '2',
      '3',
      'cash',
    ].join('|');
    final legacy = Hmac(sha256, utf8.encode('UralCash-ERP-Integrity-v1'))
        .convert(utf8.encode(payload)).toString();
    expect(
      InvoiceIntegrityService.verifySalesInvoiceHash(
        storedHash: legacy,
        invoiceNumber: 'INV-1',
        invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
        total: 10,
        subtotal: 9,
        discount: 0,
        tax: 1,
        paid: 10,
        customerId: 2,
        userId: 3,
        paymentMethod: 'cash',
      ),
      isTrue,
    );
  });
}
